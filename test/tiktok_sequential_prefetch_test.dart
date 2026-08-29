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
        for (int i = 0; i < 3; i++) {
          final outputPath = "${tempDir.path}/sentence_$i.mp3";
          final result = await tikTokService.synthesize(
            text: "Đây là câu số $i đang được tải trước bằng giọng TikTok.",
            voice: voice,
            storyTitle: "TestPrefetch",
            chapterNumber: 1,
            outputFilePath: outputPath,
          );

          expect(File(result.audioFilePath).existsSync(), isTrue);
          expect(result.audioBytes.length, greaterThan(1000));
          results.add(result.audioFilePath);
        }

        expect(results.length, 3);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

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
