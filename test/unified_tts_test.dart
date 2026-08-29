import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:app_story/models/voice_model.dart';
import 'package:app_story/models/bgm_track_model.dart';
import 'package:app_story/services/edge_tts_service.dart';
import 'package:app_story/services/tiktok_tts_service.dart';
import 'package:app_story/services/unified_tts_service.dart';

void main() {
  group('TTS and BGM Integration Tests', () {
    test('Default voices list contains ONNX, Edge, and TikTok voices', () {
      final voices = VoiceModel.defaultVoices;
      expect(voices.any((v) => v.engine == VoiceEngineType.localOnnx), isTrue);
      expect(voices.any((v) => v.engine == VoiceEngineType.edgeTts), isTrue);
      expect(voices.any((v) => v.engine == VoiceEngineType.tiktokTts), isTrue);
      expect(voices.length, greaterThanOrEqualTo(8));
    });

    test('BgmTrack default tracks contains archive.org BGM items', () {
      final tracks = BgmTrack.defaultTracks;
      expect(tracks.length, greaterThanOrEqualTo(7));
      expect(tracks.first.id, 'bgm1');
      expect(tracks.first.url, contains('archive.org'));
    });

    test('Edge TTS synthesis test', () async {
      // Sử dụng real HttpClient thông qua IOClient để không bị chặn bởi Flutter test binding
      final rawHttpClient = HttpClient();
      final ioClient = IOClient(rawHttpClient);
      final edgeService = EdgeTtsService(httpClient: ioClient);

      final voice = VoiceModel.defaultVoices.firstWhere((v) => v.engine == VoiceEngineType.edgeTts);
      final tempDir = Directory.systemTemp.createTempSync('edge_test_');
      final outputPath = '${tempDir.path}/test_edge.mp3';

      try {
        final result = await edgeService.synthesize(
          text: 'Xin chào, đây là bài kiểm tra giọng đọc Edge TTS.',
          voice: voice,
          storyTitle: 'TestStory',
          chapterNumber: 1,
          outputFilePath: outputPath,
        ).timeout(const Duration(seconds: 10));

        expect(File(result.audioFilePath).existsSync(), isTrue);
        expect(result.audioBytes.length, greaterThan(1000));
        expect(result.durationMs, greaterThan(500));
      } on SocketException catch (_) {
        // Bỏ qua nếu offline / không có kết nối mạng
      } catch (e) {
        if (e.toString().contains('Failed host lookup') || e.toString().contains('TimeoutException')) {
          return;
        }
        rethrow;
      } finally {
        rawHttpClient.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('TikTok TTS synthesis test', () async {
      final tikTokService = TikTokTtsService();
      final voice = VoiceModel.defaultVoices.firstWhere((v) => v.engine == VoiceEngineType.tiktokTts);
      final tempDir = Directory.systemTemp.createTempSync('tiktok_test_');
      final outputPath = '${tempDir.path}/test_tiktok.mp3';

      try {
        final result = await tikTokService.synthesize(
          text: 'Xin chào, đây là bài kiểm tra giọng đọc TikTok TTS.',
          voice: voice,
          storyTitle: 'TestStory',
          chapterNumber: 1,
          outputFilePath: outputPath,
        ).timeout(const Duration(seconds: 10));

        expect(File(result.audioFilePath).existsSync(), isTrue);
        expect(result.audioBytes.length, greaterThan(1000));
        expect(result.durationMs, greaterThan(500));
      } on SocketException catch (_) {
        // Bỏ qua nếu offline / không có kết nối mạng
      } catch (e) {
        if (e.toString().contains('Failed host lookup') || e.toString().contains('TimeoutException')) {
          return;
        }
        rethrow;
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('UnifiedTtsService routes correctly to Edge and TikTok', () async {
      final edgeVoice = VoiceModel.defaultVoices.firstWhere((v) => v.engine == VoiceEngineType.edgeTts);
      final tikTokVoice = VoiceModel.defaultVoices.firstWhere((v) => v.engine == VoiceEngineType.tiktokTts);
      final onnxVoice = VoiceModel.defaultVoices.firstWhere((v) => v.engine == VoiceEngineType.localOnnx);

      expect(UnifiedTtsService.getAudioExtension(edgeVoice), 'mp3');
      expect(UnifiedTtsService.getAudioExtension(tikTokVoice), 'mp3');
      expect(UnifiedTtsService.getAudioExtension(onnxVoice), 'wav');
    });
  });
}
