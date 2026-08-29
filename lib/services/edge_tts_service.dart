import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/tts_synthesis_result.dart';
import '../models/voice_model.dart';
import '../core/utils/audio_exporter.dart';
import '../core/utils/text_normalizer.dart';

class EdgeTtsService {
  static const List<Map<String, String>> _servers = [
    {'url': 'https://edge-tts1.lilbabyfroggie.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://msedge-tts-json.nickmonty777.workers.dev/tts-json', 'type': 'json'},
    {'url': 'https://msedge-tts-json.nickmonty2020.workers.dev/tts-json', 'type': 'json'},
    {'url': 'https://egde-tts2.quangnguyen251325.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts3.hoannguyen251325.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts4.manhnguyen251325.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts5.thienco-tcc.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts6.odes-agency.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts7.thiencocac-tradecoin.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts8.baileyserena1161.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts9.leroyswanson351.workers.dev/tts', 'type': 'auto'},
    {'url': 'https://edge-tts10.peayhoward.workers.dev/tts', 'type': 'auto'},
  ];

  final http.Client _httpClient;

  EdgeTtsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Gửi yêu cầu tổng hợp tới 1 Worker server cụ thể
  Future<Uint8List?> _fetchWorker(
    Map<String, String> server,
    String text,
    String voice, {
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final url = server['url']!;
      final serverType = server['type'] ?? 'auto';

      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': '*/*',
        },
        body: jsonEncode({
          'text': text,
          'voice': voice,
          'rate': rate,
          'pitch': pitch,
          'volume': volume,
        }),
      ).timeout(timeout);

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      final isAudio = contentType.contains('audio') || (serverType == 'auto' && !contentType.contains('json'));

      if (isAudio && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }

      // Parse JSON response if returned as base64
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          String? b64;
          if (decoded['audio'] is Map) {
            b64 = decoded['audio']['dataBase64'] ?? decoded['audio']['data'];
          } else if (decoded['audio'] is String) {
            b64 = decoded['audio'];
          } else {
            b64 = decoded['data'] ?? decoded['audioData'] ?? decoded['result'];
          }

          if (b64 != null && b64.isNotEmpty) {
            return base64Decode(b64);
          }
        }
      } catch (_) {}

      // Fallback: if bytes look like MP3 header (starts with ID3 or 0xFF, 0xFB/0xF3)
      if (response.bodyBytes.length > 100) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Gửi song song theo lô các server (racing pool)
  Future<Uint8List?> _raceWorkers(
    String text,
    String voice, {
    String rate = '+0%',
    int raceCount = 2,
  }) async {
    final pool = List<Map<String, String>>.from(_servers);

    while (pool.isNotEmpty) {
      final takeCount = pool.length < raceCount ? pool.length : raceCount;
      final batch = pool.sublist(0, takeCount);
      pool.removeRange(0, takeCount);

      final futures = batch.map((s) => _fetchWorker(s, text, voice, rate: rate));
      final results = await Future.wait(futures);

      for (final res in results) {
        if (res != null && res.isNotEmpty) {
          return res;
        }
      }
    }
    return null;
  }

  /// Tổng hợp văn bản thành file MP3 hoàn chỉnh
  Future<TtsSynthesisResult> synthesize({
    required String text,
    required VoiceModel voice,
    required String storyTitle,
    required int chapterNumber,
    String audioType = 'summary',
    String? outputFilePath,
    double speed = 1.0,
    Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.1);

    final cleanText = TextNormalizer.normalize(text).trim();
    if (cleanText.isEmpty) {
      throw Exception('Văn bản rỗng sau khi chuẩn hóa');
    }

    final voiceSpeaker = voice.speakerId ?? 'vi-VN-HoaiMyNeural';
    final outputPath = outputFilePath ??
        await AudioExporter.generateAudioFilePath(
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          type: audioType,
          extension: 'mp3',
        );

    onProgress?.call(0.3);

    final audioBytes = await _raceWorkers(
      cleanText,
      voiceSpeaker,
      rate: '+0%',
      raceCount: 2,
    );

    if (audioBytes == null || audioBytes.isEmpty) {
      throw Exception('Không thể tổng hợp giọng đọc từ Edge TTS (Toàn bộ servers bận)');
    }

    onProgress?.call(0.8);

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(audioBytes, flush: true);

    onProgress?.call(1.0);

    // Ước tính duration từ kích thước file MP3 128kbps (~16KB/s)
    final durationMs = ((audioBytes.length / 16000) * 1000).round();

    return TtsSynthesisResult(
      audioFilePath: outputPath,
      audioBytes: audioBytes,
      wordBoundaries: [
        WordBoundary(
          offsetMs: 0,
          durationMs: durationMs,
          text: cleanText,
        ),
      ],
      durationMs: durationMs,
    );
  }
}
