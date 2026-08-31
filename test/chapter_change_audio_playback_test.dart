import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:app_story/models/chapter_model.dart';
import 'package:app_story/models/saved_audio_item.dart';
import 'package:app_story/providers/app_state_provider.dart';
import 'package:app_story/providers/settings_provider.dart';
import 'package:app_story/providers/player_state_provider.dart';
import 'package:app_story/core/utils/audio_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = sqfliteDatabaseFactory;

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('chap_playback_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' || call.method == 'getDownloadsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (call) async {
      if (call.method == 'getDatabasesPath') {
        return tempDir.path;
      }
      if (call.method == 'openDatabase') {
        return {'id': 1};
      }
      if (call.method == 'query') {
        return {'columns': <String>[], 'rows': <List<dynamic>>[]};
      }
      if (call.method == 'insert' || call.method == 'update' || call.method == 'delete' || call.method == 'execute') {
        return 1;
      }
      if (call.method == 'batch') {
        return <dynamic>[];
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

  Future<void> createDummyAudio({
    required String storyTitle,
    required int chapterNumber,
    required String type,
    required int sentenceIndex,
    required String sentenceText,
    required String voiceId,
  }) async {
    final path = await AudioExporter.generateSentenceAudioFilePath(
      storyTitle: storyTitle,
      chapterNumber: chapterNumber,
      type: type,
      sentenceIndex: sentenceIndex,
      sentenceText: sentenceText,
      voiceId: voiceId,
      extension: 'mp3',
    );
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(1000, 0));
  }

  group('Chapter Navigation Audio Playback Continuation Tests', () {
    test('goToNextChapter continues playing when audio was playing (manual next button)', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      const storyTitle = 'Test Story';
      const s1 = 'Câu một của chương một.';
      const s2 = 'Câu một của chương hai.';

      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Test Story - Chương 1',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s1,
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 2',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s2,
        voiceId: settings.selectedVoiceId,
      );

      final chapter1Item = SavedAudioItem(
        id: 'saved_chap_1',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
        content: s1,
      );
      final chapter2Item = SavedAudioItem(
        id: 'saved_chap_2',
        title: 'Chương 2',
        storyTitle: storyTitle,
        chapterNumber: 2,
        audioPath: '',
        content: s2,
      );

      appState.savedAudios.addAll([chapter1Item, chapter2Item]);

      await appState.loadSavedChapter(
        chapter1Item,
        settings: settings,
        player: player,
      );

      expect(appState.currentChapter?.chapterNumber, 1);

      // Bắt đầu phát câu 0
      await appState.playSentence(
        sourceType: AudioSourceType.content,
        sentenceIndex: 0,
        settings: settings,
        player: player,
      );
      expect(player.isPlaying, isTrue);

      // Người dùng ấn Next Chapter (isAutoNext = false)
      await appState.goToNextChapter(
        settings: settings,
        player: player,
        isAutoNext: false,
      );

      // Chương mới phải là Chương 2
      expect(appState.currentChapter?.chapterNumber, 2);

      // QUAN TRỌNG: Vì trước đó đang phát audio, khi chuyển chương sang Chương 2 thì audio phải tiếp tục phát!
      expect(player.isPlaying, isTrue,
          reason: 'Khi chuyển sang chương mới trong lúc đang nghe, player phải tiếp tục phát (player.isPlaying phải là true)');
      expect(appState.activeSentenceIndex, isNotNull);
    });

    test('goToPreviousChapter continues playing when audio was playing', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      const storyTitle = 'Test Story';
      const s1 = 'Câu một của chương một.';
      const s2 = 'Câu một của chương hai.';

      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 1',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s1,
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 2',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s2,
        voiceId: settings.selectedVoiceId,
      );

      final chapter1Item = SavedAudioItem(
        id: 'saved_chap_1',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
        content: s1,
      );
      final chapter2Item = SavedAudioItem(
        id: 'saved_chap_2',
        title: 'Chương 2',
        storyTitle: storyTitle,
        chapterNumber: 2,
        audioPath: '',
        content: s2,
      );

      appState.savedAudios.addAll([chapter1Item, chapter2Item]);

      await appState.loadSavedChapter(
        chapter2Item,
        settings: settings,
        player: player,
      );

      expect(appState.currentChapter?.chapterNumber, 2);

      await appState.playSentence(
        sourceType: AudioSourceType.content,
        sentenceIndex: 0,
        settings: settings,
        player: player,
      );
      expect(player.isPlaying, isTrue);

      // Người dùng ấn Previous Chapter
      await appState.goToPreviousChapter(
        settings: settings,
        player: player,
      );

      expect(appState.currentChapter?.chapterNumber, 1);
      expect(player.isPlaying, isTrue,
          reason: 'Khi chuyển lùi về chương trước trong lúc đang nghe, player phải tiếp tục phát');
      expect(appState.activeSentenceIndex, isNotNull);
    });

    test('changeToChapter continues playing when audio was playing', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      const storyTitle = 'Test Story';
      const s1 = 'Câu một của chương một.';
      const s3 = 'Câu một của chương ba.';

      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 1',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s1,
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 3,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 3',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 3,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s3,
        voiceId: settings.selectedVoiceId,
      );

      final chapter1Item = SavedAudioItem(
        id: 'saved_chap_1',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
        content: s1,
      );
      final chapter3Item = SavedAudioItem(
        id: 'saved_chap_3',
        title: 'Chương 3',
        storyTitle: storyTitle,
        chapterNumber: 3,
        audioPath: '',
        content: s3,
      );

      appState.savedAudios.addAll([chapter1Item, chapter3Item]);

      await appState.loadSavedChapter(
        chapter1Item,
        settings: settings,
        player: player,
      );

      await appState.playSentence(
        sourceType: AudioSourceType.content,
        sentenceIndex: 0,
        settings: settings,
        player: player,
      );
      expect(player.isPlaying, isTrue);

      await appState.changeToChapter(
        3,
        settings: settings,
        player: player,
      );

      expect(appState.currentChapter?.chapterNumber, 3);
      expect(player.isPlaying, isTrue,
          reason: 'Khi nhảy trực tiếp đến chương mới trong lúc đang nghe, player phải tiếp tục phát');
      expect(appState.activeSentenceIndex, isNotNull);
    });

    test('autoNextChapter triggers audio continuation on next chapter', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      const storyTitle = 'Test Story';
      const s1 = 'Câu một của chương một.';
      const s2 = 'Câu một của chương hai.';

      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 1',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s1,
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 2',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 1,
        sentenceText: s2,
        voiceId: settings.selectedVoiceId,
      );

      final chapter1Item = SavedAudioItem(
        id: 'saved_chap_1',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
        content: s1,
      );
      final chapter2Item = SavedAudioItem(
        id: 'saved_chap_2',
        title: 'Chương 2',
        storyTitle: storyTitle,
        chapterNumber: 2,
        audioPath: '',
        content: s2,
      );

      appState.savedAudios.addAll([chapter1Item, chapter2Item]);

      await appState.loadSavedChapter(
        chapter1Item,
        settings: settings,
        player: player,
      );

      await settings.setAutoNextChapter(true);

      // Giả lập đang phát câu 0 (đang phát)
      await appState.playSentence(
        sourceType: AudioSourceType.content,
        sentenceIndex: 0,
        settings: settings,
        player: player,
      );
      expect(appState.activeSentenceIndex, 0);
      expect(player.isPlaying, isTrue);

      // Phát hết câu 0 -> chuyển sang câu 1
      await appState.handleSentenceComplete(settings: settings, player: player);
      expect(appState.activeSentenceIndex, 1);
      expect(player.isPlaying, isTrue);

      // Phát hết câu 1 (câu cuối cùng của chương 1) -> Tự động chuyển sang chương 2 và PHẢI tiếp tục phát
      await appState.handleSentenceComplete(settings: settings, player: player);

      expect(appState.currentChapter?.chapterNumber, 2);
      expect(player.isPlaying, isTrue,
          reason: 'Khi nghe hết chương, tự chuyển chương phải tiếp tục phát audio ở chương mới');
      expect(appState.activeSentenceIndex, isNotNull);
    });

    test('manual chapter change does NOT start playback if user was paused', () async {
      final settings = SettingsProvider();
      await settings.init();
      final player = PlayerStateProvider();
      final appState = AppStateProvider();

      const storyTitle = 'Test Story';
      const s1 = 'Câu một của chương một.';
      const s2 = 'Câu một của chương hai.';

      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 1,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 1',
        voiceId: settings.selectedVoiceId,
      );
      await createDummyAudio(
        storyTitle: storyTitle,
        chapterNumber: 2,
        type: 'content',
        sentenceIndex: 0,
        sentenceText: 'Chương 2',
        voiceId: settings.selectedVoiceId,
      );

      final chapter1Item = SavedAudioItem(
        id: 'saved_chap_1',
        title: 'Chương 1',
        storyTitle: storyTitle,
        chapterNumber: 1,
        audioPath: '',
        content: s1,
      );
      final chapter2Item = SavedAudioItem(
        id: 'saved_chap_2',
        title: 'Chương 2',
        storyTitle: storyTitle,
        chapterNumber: 2,
        audioPath: '',
        content: s2,
      );

      appState.savedAudios.addAll([chapter1Item, chapter2Item]);

      await appState.loadSavedChapter(
        chapter1Item,
        settings: settings,
        player: player,
      );

      // Người dùng bấm pause
      await player.pause();
      expect(player.isPausedByUser, isTrue);
      expect(player.isPlaying, isFalse);

      // Người dùng chuyển sang chương 2
      await appState.goToNextChapter(
        settings: settings,
        player: player,
        isAutoNext: false,
      );

      expect(appState.currentChapter?.chapterNumber, 2);
      expect(player.isPlaying, isFalse,
          reason: 'Nếu người dùng đang pause, chuyển chương KHÔNG được tự ý phát audio');
    });
  });
}
