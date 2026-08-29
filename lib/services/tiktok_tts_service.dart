import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/tts_synthesis_result.dart';
import '../models/voice_model.dart';
import '../core/utils/audio_exporter.dart';
import '../core/utils/text_normalizer.dart';

class _TikTokTaskJob {
  final String text;
  final String speaker;
  final Completer<Uint8List?> completer;

  _TikTokTaskJob({
    required this.text,
    required this.speaker,
    required this.completer,
  });
}

class TikTokTtsService {
  static const String _wsUrl =
      'wss://sami-normal-sg.capcutapi.com/internal/api/v1/ws?device_id=7486429558272460289&iid=7486431924195657473&app_id=359289&region=VN&update_version_code=5.7.1.2101&version_code=5.7.1&appKey=ddjeqjLGMn&device_type=macos&device_platform=macos';
  
  static const String _token =
      'WTV6R2t6V3ZwNUIwQkFETutGxuveRZ9iTmOBC/a3wzMS7zzza86Ky9nIfYhyeoSiWYP1ZO04X7X1+RThg/zczU6u8ga3dTIJpduvWpCqrmr0Kv7BJf6tcGFgevJ/Jaa1slHj/l4NUJ/eCesl1dYBYQ51oKbuFnZjF7qXVWzsoz326XwRdNEmOufSHnuW+kuy+sS7K/sn3gVWsCC4XFi+FYntDxrVTYS/Pv2LtBgpgULmib5+5kMq2ZuJfCDYvq4NthciciB6KUCf1sOsu7VD/27Tquz8Q58NYALFvX85bjvxQJOz0iV3oUiip0RyqR1ltZPNI/LgN2OGCphyCgOJdlUUdgIbSJpaKL+5PMTM4yBuwCU4QPbYYzTs9x2ZA+7zt41ng+i5+EPtePyDjR4VFTz+7zglLw/E+KqN/nscyqLCyrumn4YgfQ3JYnSnz1WLE6q3aD175yweKBj9f9jyqxnLVmEYy9VjmoxuYNRgVmfT6M17bT9iL0PJTlJ6UqKHuNRT6ubv37ZSr961Gw+RJhyLUDBt8AD1B8YDdF4OImS+LgGjfujaY1agc4tfrnk4V4YcAXyTRlYwLMC9ATDp9CbiBrlMBmYm88gwGaTR9pbI2KcQ4Kg86jZYc6CxNM34sbMG/1LlmqvqLe+E3IG6ebOmyVbL+kYK70c1fT5TcmzVwX5O3JGkHHtFoeCmd4Eyyov6QsO1Jewx0gpjp05dqw==';

  static final Queue<_TikTokTaskJob> _queue = Queue<_TikTokTaskJob>();
  static bool _isProcessingQueue = false;

  /// Xử lý gửi 1 task trên WebSocket riêng biệt, tránh xung đột Stream subscription
  static Future<Uint8List?> _synthesizeRaw(String text, String speaker) async {
    WebSocket? socket;
    StreamSubscription? sub;
    Timer? timeoutTimer;
    final chunks = <List<int>>[];
    final completer = Completer<Uint8List?>();

    void cleanup() {
      timeoutTimer?.cancel();
      sub?.cancel();
      try {
        socket?.close();
      } catch (_) {}
    }

    timeoutTimer = Timer(const Duration(seconds: 15), () {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    try {
      socket = await WebSocket.connect(_wsUrl).timeout(const Duration(seconds: 8));

      sub = socket.listen((event) {
        if (event is List<int>) {
          chunks.add(event);
        } else if (event is String) {
          try {
            final msg = jsonDecode(event);
            final eventType = msg['event'];

            if (eventType == 'TaskFailed') {
              cleanup();
              if (!completer.isCompleted) completer.complete(null);
            } else if (eventType == 'TaskEnd' || eventType == 'TaskFinished') {
              final totalLength = chunks.fold<int>(0, (acc, c) => acc + c.length);
              final combined = Uint8List(totalLength);
              int offset = 0;
              for (final c in chunks) {
                combined.setRange(offset, offset + c.length, c);
                offset += c.length;
              }
              cleanup();
              if (!completer.isCompleted) completer.complete(combined);
            }
          } catch (_) {}
        }
      }, onError: (err) {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      });

      final payload = jsonEncode({
        'audio_config': {
          'bit_rate': 128000,
          'format': 'mp3',
          'sample_rate': 24000,
        },
        'speaker': speaker,
        'text': text.trim(),
      });

      socket.add(jsonEncode({
        'appkey': 'ddjeqjLGMn',
        'event': 'StartTask',
        'namespace': 'TTS',
        'payload': payload,
        'token': _token,
        'version': 'sdk_v1',
      }));
    } catch (_) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }

  /// Chạy hàng đợi tuần tự để gửi task an toàn và ổn định
  static void _processQueue() async {
    if (_isProcessingQueue || _queue.isEmpty) return;
    _isProcessingQueue = true;

    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      try {
        var result = await _synthesizeRaw(job.text, job.speaker);
        // Thử lại 1 lần nếu gặp sự cố mạng chớp nhoáng
        if (result == null || result.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 200));
          result = await _synthesizeRaw(job.text, job.speaker);
        }
        if (!job.completer.isCompleted) {
          job.completer.complete(result);
        }
      } catch (e) {
        if (!job.completer.isCompleted) {
          job.completer.complete(null);
        }
      }
      // Nghỉ nhẹ 30ms giữa các task tuần tự
      await Future.delayed(const Duration(milliseconds: 30));
    }

    _isProcessingQueue = false;
  }

  /// Tổng hợp âm thanh TikTok theo hàng đợi an toàn
  Future<Uint8List?> synthesizeBytes(String text, String speaker) {
    final completer = Completer<Uint8List?>();
    _queue.add(_TikTokTaskJob(
      text: text,
      speaker: speaker,
      completer: completer,
    ));
    _processQueue();
    return completer.future;
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

    final voiceSpeaker = voice.speakerId ?? 'BV074_streaming';
    final outputPath = outputFilePath ??
        await AudioExporter.generateAudioFilePath(
          storyTitle: storyTitle,
          chapterNumber: chapterNumber,
          type: audioType,
          extension: 'mp3',
        );

    onProgress?.call(0.3);

    final audioBytes = await synthesizeBytes(cleanText, voiceSpeaker);

    if (audioBytes == null || audioBytes.isEmpty) {
      throw Exception('Không thể tổng hợp giọng đọc từ TikTok TTS');
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
