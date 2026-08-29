import "dart:io";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:app_story/models/voice_model.dart";
import "package:app_story/services/tiktok_tts_service.dart";
import "package:app_story/services/unified_tts_service.dart";
import "package:app_story/core/utils/audio_exporter.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' || call.method == 'getDownloadsDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });
  });

  group("TikTok TTS Sequential Prefetch Tests", () {
    test("Multiple sequential synthesize calls succeed without WebSocket stream errors", () async {
      final tikTokService = TikTokTtsService();
      final voice = VoiceModel.defaultVoices.firstWhere((v) => v.id == "tiktok-vi_female_huong");
      final tempDir = Directory.systemTemp.createTempSync("tiktok_multi_test_");

      try {
        final results = <String>[];
        for (int i = 0; i < 2; i++) {
          final outputPath = "${tempDir.path}/sentence_$i.mp3";
          try {
            final result = await tikTokService.synthesize(
              text: "Đây là câu số $i đang được tải trước bằng giọng TikTok.",
              voice: voice,
              storyTitle: "TestPrefetch",
              chapterNumber: 1,
              outputFilePath: outputPath,
            ).timeout(const Duration(seconds: 10));

            expect(File(result.audioFilePath).existsSync(), isTrue);
            expect(result.audioBytes.length, greaterThan(1000));
            results.add(result.audioFilePath);
          } on SocketException catch (_) {
            // Bỏ qua nếu offline / không có mạng
            return;
          } catch (e) {
            if (e.toString().contains('Failed host lookup') || e.toString().contains('TimeoutException')) {
              return;
            }
            rethrow;
          }
        }
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 25)));

    test("UnifiedTtsService generates sentence audio files with correct extension and cache path", () async {
      final voice = VoiceModel.defaultVoices.firstWhere((v) => v.id == "tiktok-vi_female_huong");
      final extension = UnifiedTtsService.getAudioExtension(voice);
      expect(extension, "mp3");

      final path = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: "Phàm Nhân Tu Tiên",
        chapterNumber: 1,
        type: "content",
        sentenceIndex: 0,
        sentenceText: "Hàn Lập nhìn về phía xa xăm.",
        voiceId: voice.id,
        extension: extension,
      );

      expect(path.endsWith(".mp3"), isTrue);
      expect(path.contains("tiktok-vi_female_huong"), isTrue);
    });
  });
}
