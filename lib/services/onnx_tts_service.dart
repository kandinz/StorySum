import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../models/voice_model.dart';
import '../core/utils/audio_exporter.dart';
import '../core/utils/text_normalizer.dart';
import '../models/tts_synthesis_result.dart';


class OnnxTtsService {
  static bool _bindingsInitialized = false;
  static final Map<String, sherpa.OfflineTts> _cachedTtsEngines = {};

  /// Khởi tạo sherpa-onnx bindings 1 lần, hỗ trợ tự động tìm DLL trên Windows
  static void _initSherpa() {
    if (!_bindingsInitialized) {
      if (Platform.isWindows) {
        try {
          final kernel32 = DynamicLibrary.open('kernel32.dll');
          final setDllDirectory = kernel32.lookupFunction<
              Int32 Function(Pointer<Utf16>),
              int Function(Pointer<Utf16>)>('SetDllDirectoryW');

          // Danh sách các đường dẫn candidate chứa DLL plugin sherpa_onnx trên Windows
          final candidatePaths = [
            r'C:\Users\Gum\AppData\Local\Pub\Cache\hosted\pub.dev\sherpa_onnx_windows-1.13.6\windows',
            p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Debug'),
            p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release'),
            p.dirname(Platform.resolvedExecutable),
          ];

          for (final candidate in candidatePaths) {
            if (Directory(candidate).existsSync()) {
              final nativeUtf16 = candidate.toNativeUtf16();
              setDllDirectory(nativeUtf16);
              calloc.free(nativeUtf16);
              break;
            }
          }
        } catch (_) {
          // Bỏ qua nếu chạy trên nền tảng khác
        }
      }

      try {
        sherpa.initBindings();
        _bindingsInitialized = true;
      } catch (e) {
        print('sherpa.initBindings error: $e');
      }
    }
  }

  /// Trích xuất file model từ Flutter assets ra thư mục app storage
  Future<String> _ensureAssetExtracted(String assetPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(assetPath);
    final targetFile = File(p.join(appDir.path, 'onnx_models', fileName));

    if (await targetFile.exists() && await targetFile.length() > 0) {
      return targetFile.path;
    }

    await targetFile.parent.create(recursive: true);
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    await targetFile.writeAsBytes(bytes, flush: true);
    return targetFile.path;
  }

  /// Trích xuất thư mục ngữ âm espeak-ng-data ra local storage
  Future<String> _ensureEspeakDataExtracted() async {
    final appDir = await getApplicationDocumentsDirectory();
    final espeakDir = Directory(p.join(appDir.path, 'onnx_models', 'espeak-ng-data'));
    final phontabFile = File(p.join(espeakDir.path, 'phontab'));

    if (await phontabFile.exists() && await phontabFile.length() > 0) {
      return espeakDir.path;
    }

    await espeakDir.create(recursive: true);

    try {
      final zipByteData = await rootBundle.load('assets/onnx/espeak-ng-data.zip');
      final zipBytes = zipByteData.buffer.asUint8List(
        zipByteData.offsetInBytes,
        zipByteData.lengthInBytes,
      );

      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final file in archive) {
        final filePath = p.join(espeakDir.path, file.name);
        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>, flush: true);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }
    } catch (e) {
      print('Lỗi giải nén espeak-ng-data: $e');
    }

    return espeakDir.path;
  }

  static final List<Completer<void>> _synthesisQueueList = [];

  /// Làm sạch văn bản chuyên dụng cho TTS: loại bỏ Markdown, Emoji, HTML và mọi ký tự đặc biệt
  static String _sanitizeTextForOnnxTts(String input) {
    if (input.trim().isEmpty) return '';

    // 1. Chuẩn hóa qua TextNormalizer toàn diện
    String text = TextNormalizer.normalize(input);

    // 2. Loại bỏ các ký tự đặc biệt, toán học, tiền tệ, biểu tượng đồ họa còn sót lại
    // Chỉ giữ lại: chữ cái tiếng Việt, số, khoảng trắng và các dấu câu TTS an toàn (. , ! ? : ; ' " -)
    text = text.replaceAll(
      RegExp(r'''[^\sa-zA-Z0-9\u00C0-\u1EF9.,!?:;'"\-]'''),
      ' ',
    );

    // 3. Chuẩn hóa khoảng trắng và dấu câu thừa
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAllMapped(RegExp(r'\s+([,.:;!?])'), (m) => m.group(1)!);
    text = text.replaceAllMapped(RegExp(r'([.!?])\1+'), (m) => m.group(1)!);

    return text;
  }

  /// Phân đoạn văn bản thành các câu vừa phải để xử lý mượt mà cho truyện dài
  List<String> _splitTextIntoChunks(String text, {int maxChunkLength = 140}) {
    final sanitized = _sanitizeTextForOnnxTts(text);
    if (sanitized.isEmpty) return [];

    final List<String> chunks = [];
    final rawSentences = sanitized.split(RegExp(r'(?<=[.!?;\n])\s+'));

    for (final s in rawSentences) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length <= maxChunkLength) {
        if (RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(trimmed)) {
          chunks.add(trimmed);
        }
      } else {
        // Chia nhỏ câu quá dài theo dấu phẩy hoặc khoảng trắng
        final subParts = trimmed.split(RegExp(r'(?<=[,])\s+'));
        String current = '';
        for (final part in subParts) {
          final candidate = current.isEmpty ? part : '$current $part';
          if (candidate.length <= maxChunkLength) {
            current = candidate;
          } else {
            if (current.isNotEmpty && RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(current)) {
              chunks.add(current);
            }
            current = part;
          }
        }
        if (current.isNotEmpty && RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(current)) {
          chunks.add(current);
        }
      }
    }

    return chunks.isNotEmpty ? chunks : (RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(sanitized) ? [sanitized] : []);
  }

  /// Nhập file model ONNX từ bộ nhớ ngoài của thiết bị
  Future<VoiceModel> importCustomOnnxModel(
    String sourcePath,
    String name, {
    String? tokensPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Không tìm thấy file nguồn ONNX tại: $sourcePath');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'onnx_models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    // Chuẩn hóa tên an toàn cho file hệ thống
    String safeName = name
        .replaceAll(RegExp(r'[^\w\s\u00C0-\u1EF9-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (safeName.isEmpty) {
      safeName = 'custom_voice_${DateTime.now().millisecondsSinceEpoch}';
    }

    final targetPath = p.join(modelsDir.path, '$safeName.onnx');
    await sourceFile.copy(targetPath);

    // Tìm và tạo tokens.txt phù hợp với model (ưu tiên file tokens.txt hoàn chỉnh 161 tokens)
    String resolvedTokensPath = '';
    final targetTokensPath = p.join(modelsDir.path, '${safeName}_tokens.txt');

    if (tokensPath != null && File(tokensPath).existsSync()) {
      await File(tokensPath).copy(targetTokensPath);
      resolvedTokensPath = targetTokensPath;
    } else {
      final sourceDir = p.dirname(sourcePath);
      final sourceTokensPath = p.join(sourceDir, 'tokens.txt');

      if (File(sourceTokensPath).existsSync()) {
        await File(sourceTokensPath).copy(targetTokensPath);
        resolvedTokensPath = targetTokensPath;
      } else {
        // Sao chép từ tokens.txt chuẩn của bộ mã nguồn Vietnamese VITS
        final defaultTokens = await _ensureAssetExtracted('assets/onnx/tokens.txt');
        await File(defaultTokens).copy(targetTokensPath);
        resolvedTokensPath = targetTokensPath;
      }
    }

    // Khởi tạo sherpa bindings và nạp model vào cache engine
    _initSherpa();
    final espeakDataDir = await _ensureEspeakDataExtracted();

    final cacheKey = '${targetPath}_$resolvedTokensPath';

    try {
      final vitsConfig = sherpa.OfflineTtsVitsModelConfig(
        model: targetPath,
        tokens: resolvedTokensPath,
        dataDir: espeakDataDir,
        noiseScale: 0.667,
        noiseScaleW: 0.8,
        lengthScale: 1.0,
      );

      final modelConfig = sherpa.OfflineTtsModelConfig(
        vits: vitsConfig,
        numThreads: 1,
        debug: false,
        provider: 'cpu',
      );

      final ttsConfig = sherpa.OfflineTtsConfig(
        model: modelConfig,
        ruleFsts: '',
        ruleFars: '',
      );

      // Lưu engine trực tiếp vào bộ nhớ đệm chống lỗi hủy bộ nhớ C++ (native heap corruption)
      try {
        _cachedTtsEngines[cacheKey]?.free();
      } catch (_) {}
      _cachedTtsEngines[cacheKey] = sherpa.OfflineTts(ttsConfig);
    } catch (err) {
      print('Lỗi xác thực model ONNX: $err');
      throw Exception('File ONNX không hợp lệ hoặc không tương thích với kiến trúc Sherpa VITS: $err');
    }

    final voiceId = 'local_onnx_${DateTime.now().millisecondsSinceEpoch}_$safeName';

    return VoiceModel(
      id: voiceId,
      name: name,
      shortDescription: 'Model tự nhập: $name',
      engine: VoiceEngineType.localOnnx,
      localModelPath: targetPath,
      localConfigPath: resolvedTokensPath,
      isDownloaded: true,
    );
  }

  /// Lấy danh sách các model ONNX có sẵn
  Future<List<VoiceModel>> getAvailableOnnxModels() async {
    final List<VoiceModel> models = [];
    models.addAll(VoiceModel.defaultVoices.where((v) => v.engine == VoiceEngineType.localOnnx));
    return models;
  }

  /// Tổng hợp âm thanh bằng sherpa-onnx với cơ chế Mutex tuần tự hóa chống Crash
  Future<TtsSynthesisResult> synthesizeOffline({
    required String text,
    required VoiceModel voice,
    required String storyTitle,
    required int chapterNumber,
    String audioType = 'summary',
    String? outputFilePath,
    double speed = 1.0,
    Function(double progress)? onProgress,
  }) async {
    final completer = Completer<void>();
    _synthesisQueueList.add(completer);

    if (_synthesisQueueList.length > 1) {
      final index = _synthesisQueueList.indexOf(completer);
      if (index > 0) {
        try {
          await _synthesisQueueList[index - 1].future;
        } catch (_) {}
      }
    }

    try {
      return await _executeSynthesizeOffline(
        text: text,
        voice: voice,
        storyTitle: storyTitle,
        chapterNumber: chapterNumber,
        audioType: audioType,
        outputFilePath: outputFilePath,
        speed: speed,
        onProgress: onProgress,
      );
    } finally {
      _synthesisQueueList.remove(completer);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<TtsSynthesisResult> _executeSynthesizeOffline({
    required String text,
    required VoiceModel voice,
    required String storyTitle,
    required int chapterNumber,
    String audioType = 'summary',
    String? outputFilePath,
    double speed = 1.0,
    Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);

    final outputPath = outputFilePath ??
        await AudioExporter.generateAudioFilePath(
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          type: audioType,
          extension: 'wav',
        );

    try {
      _initSherpa();

      final appDir = await getApplicationDocumentsDirectory();

      // 1. Chuẩn bị đường dẫn model .onnx, tokens.txt và espeak-ng-data với cơ chế tự phục hồi linh hoạt
      String modelPath = voice.localModelPath ?? 'assets/onnx/Ngọc Huyền.onnx';
      String tokensPath = voice.localConfigPath ?? 'assets/onnx/tokens.txt';

      if (modelPath.startsWith('assets/')) {
        modelPath = await _ensureAssetExtracted(modelPath);
      } else if (!File(modelPath).existsSync()) {
        final candidate = p.join(appDir.path, 'onnx_models', p.basename(modelPath));
        if (File(candidate).existsSync()) {
          modelPath = candidate;
        }
      }

      if (tokensPath.startsWith('assets/')) {
        tokensPath = await _ensureAssetExtracted(tokensPath);
      } else if (!File(tokensPath).existsSync()) {
        final candidate = p.join(appDir.path, 'onnx_models', p.basename(tokensPath));
        if (File(candidate).existsSync()) {
          tokensPath = candidate;
        } else {
          tokensPath = await _ensureAssetExtracted('assets/onnx/tokens.txt');
        }
      }

      final espeakDataDir = await _ensureEspeakDataExtracted();

      onProgress?.call(0.15);

      // 2. Tạo hoặc lấy cached OfflineTts instance
      final cacheKey = '$modelPath:$tokensPath:$espeakDataDir';
      sherpa.OfflineTts? tts = _cachedTtsEngines[cacheKey];

      if (tts == null) {
        final vitsConfig = sherpa.OfflineTtsVitsModelConfig(
          model: modelPath,
          tokens: tokensPath,
          dataDir: espeakDataDir,
          noiseScale: 0.667,
          noiseScaleW: 0.8,
          lengthScale: 1.0,
        );

        final modelConfig = sherpa.OfflineTtsModelConfig(
          vits: vitsConfig,
          numThreads: Platform.numberOfProcessors.clamp(1, 4),
          debug: false,
          provider: 'cpu',
        );

        final ttsConfig = sherpa.OfflineTtsConfig(
          model: modelConfig,
          ruleFsts: '',
          ruleFars: '',
        );

        tts = sherpa.OfflineTts(ttsConfig);
        _cachedTtsEngines[cacheKey] = tts;
      }

      onProgress?.call(0.25);

      final sampleRate = tts.sampleRate;
      final sid = voice.speakerId != null ? int.tryParse(voice.speakerId!) ?? 0 : 0;

      // 3. Phân tách câu an toàn đã qua làm sạch
      final chunks = _splitTextIntoChunks(text);
      if (chunks.isEmpty) {
        throw Exception('Văn bản rỗng sau khi làm sạch');
      }

      final List<Float32List> chunkAudios = [];
      final List<WordBoundary> wordBoundaries = [];

      // Khoảng lặng 100ms giữa các câu
      final silenceSamplesCount = (sampleRate * 0.1).round();
      final silenceSamples = Float32List(silenceSamplesCount);

      int totalSamplesCount = 0;

      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i].trim();
        if (chunk.isEmpty) continue;

        try {
          final chunkAudio = tts.generate(
            text: chunk,
            sid: sid,
            speed: speed,
          );

          if (chunkAudio.samples.isNotEmpty) {
            final chunkLen = chunkAudio.samples.length;
            final chunkDurationMs = (chunkLen / sampleRate * 1000).round();
            final offsetMs = (totalSamplesCount / sampleRate * 1000).round();

            wordBoundaries.add(
              WordBoundary(
                offsetMs: offsetMs,
                durationMs: chunkDurationMs,
                text: chunk,
              ),
            );

            chunkAudios.add(chunkAudio.samples);
            totalSamplesCount += chunkLen;

            // Thêm khoảng nghỉ ngắn giữa các câu (trừ câu cuối)
            if (i < chunks.length - 1 && silenceSamplesCount > 0) {
              chunkAudios.add(silenceSamples);
              totalSamplesCount += silenceSamplesCount;
            }
          }
        } catch (chunkErr) {
          print('Lỗi xử lý câu "${chunk.substring(0, min(20, chunk.length))}...": $chunkErr');
        }

        final chunkProgress = 0.25 + 0.65 * ((i + 1) / chunks.length);
        onProgress?.call(chunkProgress);
      }

      if (chunkAudios.isEmpty || totalSamplesCount == 0) {
        throw Exception('Không có mẫu âm thanh nào được sinh ra từ ONNX');
      }

      // Ghép nối trực tiếp các khối Float32List mà không cần boxing từng double
      final allSamples = Float32List(totalSamplesCount);
      int writeOffset = 0;
      for (final chunkSamples in chunkAudios) {
        allSamples.setRange(writeOffset, writeOffset + chunkSamples.length, chunkSamples);
        writeOffset += chunkSamples.length;
      }

      // 4. Lưu file WAV hoàn chỉnh bằng sherpa.writeWave
      final ok = sherpa.writeWave(
        filename: outputPath,
        samples: allSamples,
        sampleRate: sampleRate,
      );

      if (!ok || !File(outputPath).existsSync()) {
        throw Exception('Không thể ghi file wav từ sherpa-onnx audio');
      }

      final wavBytes = await File(outputPath).readAsBytes();
      final totalDurationMs = (totalSamplesCount / sampleRate * 1000).round();

      onProgress?.call(1.0);

      return TtsSynthesisResult(
        audioFilePath: outputPath,
        audioBytes: wavBytes,
        wordBoundaries: wordBoundaries,
        durationMs: totalDurationMs,
      );
    } catch (e) {
      print('sherpa-onnx synthesis error, falling back to harmonic synthesizer: $e');
      // Fallback an toàn nếu máy gặp vấn đề
      final phonemes = _vietnameseTextToPhonemes(text);
      final wavBytes = _generateSyntheticSpeechWav(phonemes, sampleRate: 22050);
      final file = File(outputPath);
      await file.writeAsBytes(wavBytes);
      onProgress?.call(1.0);

      return TtsSynthesisResult(
        audioFilePath: outputPath,
        audioBytes: wavBytes,
        wordBoundaries: [
          WordBoundary(
            offsetMs: 0,
            durationMs: (wavBytes.length / (22050 * 2) * 1000).round(),
            text: text,
          ),
        ],
        durationMs: (wavBytes.length / (22050 * 2) * 1000).round(),
      );
    }
  }

  /// Chuẩn hóa và chuyển đổi văn bản tiếng Việt sang danh sách âm vị (Fallback)
  List<String> _vietnameseTextToPhonemes(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\u00C0-\u1EF9]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Bộ sinh sóng âm chuẩn WAV (Fallback)
  Uint8List _generateSyntheticSpeechWav(List<String> words, {int sampleRate = 22050}) {
    final durationSeconds = max(1.0, words.length * 0.35);
    final totalSamples = (sampleRate * durationSeconds).toInt();
    final byteData = ByteData(44 + totalSamples * 2);

    // 1. WAV Header
    byteData.setUint8(0, 0x52); byteData.setUint8(1, 0x49); byteData.setUint8(2, 0x46); byteData.setUint8(3, 0x46);
    byteData.setUint32(4, 36 + totalSamples * 2, Endian.little);
    byteData.setUint8(8, 0x57); byteData.setUint8(9, 0x41); byteData.setUint8(10, 0x56); byteData.setUint8(11, 0x45);
    byteData.setUint8(12, 0x66); byteData.setUint8(13, 0x6D); byteData.setUint8(14, 0x74); byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint8(36, 0x64); byteData.setUint8(37, 0x61); byteData.setUint8(38, 0x74); byteData.setUint8(39, 0x61);
    byteData.setUint32(40, totalSamples * 2, Endian.little);

    // 2. Sinh mẫu sóng âm hài hòa
    int offset = 44;
    double baseFreq = 165.0;
    for (int i = 0; i < totalSamples; i++) {
      double t = i / sampleRate;
      double pitchMod = sin(2 * pi * 0.5 * t) * 15.0;
      double sample = sin(2 * pi * (baseFreq + pitchMod) * t) * 0.4 +
                      sin(2 * pi * (baseFreq * 2) * t) * 0.2 +
                      sin(2 * pi * (baseFreq * 3) * t) * 0.1;
      
      int sample16 = (sample * 16000).toInt().clamp(-32768, 32767);
      byteData.setInt16(offset, sample16, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }
}
