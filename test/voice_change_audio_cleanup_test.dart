import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_story/models/chapter_model.dart';
import 'package:app_story/models/sentence_item.dart';
import 'package:app_story/models/voice_model.dart';
import 'package:app_story/core/utils/audio_exporter.dart';
import 'package:app_story/providers/app_state_provider.dart';
import 'package:app_story/providers/settings_provider.dart';
import 'package:app_story/providers/player_state_provider.dart';
import 'package:app_story/services/unified_tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('voice_change_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' || call.method == 'getDownloadsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Voice Change Audio Cleanup & Invalidation Tests', () {
    test('AudioExporter.deleteOldVoiceAudioFiles deletes files from ALL old voices and legacy chapter files', () async {
      final audioDir = await AudioExporter.getAudioStorageDirectory();

      final fileVoice1 = File(p.join(audioDir.path, 'Truyen_C1_TomTat_S0_tiktok-BV074_streaming_1234.mp3'));
      final fileVoice2 = File(p.join(audioDir.path, 'Truyen_C1_TomTat_S0_edge-vi-VN-NamMinhNeural_5678.mp3'));
      final fileLegacyChapter = File(p.join(audioDir.path, 'Truyen_Chuong_1_TomTat_1725000000.mp3'));
      final fileNewVoice = File(p.join(audioDir.path, 'Truyen_C1_TomTat_S0_tiktok-vi_female_huong_aaaa.mp3'));

      await fileVoice1.writeAsString('audio1');
      await fileVoice2.writeAsString('audio2');
      await fileLegacyChapter.writeAsString('legacy_chapter');
      await fileNewVoice.writeAsString('audio_new');

      await AudioExporter.deleteOldVoiceAudioFiles(
        oldVoiceId: 'edge-vi-VN-NamMinhNeural',
        currentVoiceId: 'tiktok-vi_female_huong',
      );

      expect(await fileNewVoice.exists(), isTrue, reason: 'File của giọng mới phải được giữ lại');
      expect(await fileVoice2.exists(), isFalse, reason: 'File của oldVoiceId phải bị xóa');
      expect(await fileVoice1.exists(), isFalse, reason: 'File của các giọng cũ trước đó khác cũng phải bị xóa');
      expect(await fileLegacyChapter.exists(), isFalse, reason: 'File legacy không khớp giọng mới phải bị xóa');
    });

    test('onVoiceChanged stops player and clears audio path when player was paused', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      // Giả lập player đang paused sau khi phát audio câu cũ
      await player.playAudio(
        filePath: '/storage/Truyen_C1_TomTat_S0_old_voice.mp3',
        title: 'Playing old voice',
        storyTitle: 'Test Story',
        chapterNumber: 1,
      );
      await player.pause();
      expect(player.isPausedByUser, isTrue);
      expect(player.currentAudioPath, '/storage/Truyen_C1_TomTat_S0_old_voice.mp3');

      // Đổi giọng đọc
      await settings.setSelectedVoice('edge-vi-VN-HoaiMyNeural');
      await appState.onVoiceChanged(
        settings: settings,
        player: player,
        oldVoiceId: 'tiktok-vi_female_huong',
      );

      // Player currentAudioPath PHẢI bị reset để không bao giờ phát lại file cũ khi ấn Play
      expect(player.currentAudioPath, isNull, reason: 'player.currentAudioPath phải là null sau khi đổi giọng');
    });

    test('generateSentenceAudioFilePath produces distinct file paths for different voices', () async {
      final voice1 = VoiceModel.defaultVoices.firstWhere((v) => v.id == 'tiktok-vi_female_huong');
      final voice2 = VoiceModel.defaultVoices.firstWhere((v) => v.id == 'edge-vi-VN-NamMinhNeural');

      final path1 = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: 'Đấu Phá Thương Khung',
        chapterNumber: 1,
        type: 'summary',
        sentenceIndex: 0,
        sentenceText: 'Tiêu Viêm là một thiên tài.',
        voiceId: voice1.id,
        extension: UnifiedTtsService.getAudioExtension(voice1),
      );

      final path2 = await AudioExporter.generateSentenceAudioFilePath(
        storyTitle: 'Đấu Phá Thương Khung',
        chapterNumber: 1,
        type: 'summary',
        sentenceIndex: 0,
        sentenceText: 'Tiêu Viêm là một thiên tài.',
        voiceId: voice2.id,
        extension: UnifiedTtsService.getAudioExtension(voice2),
      );

      expect(path1, isNot(equals(path2)), reason: 'Đường dẫn file của 2 giọng phải khác nhau hoàn toàn');
      expect(path1.contains('tiktok-vi_female_huong'), isTrue);
      expect(path2.contains('edge-vi-VN-NamMinhNeural'), isTrue);
    });
  });
}
