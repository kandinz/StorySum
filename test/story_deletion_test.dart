import 'package:app_story/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_story/models/chapter_model.dart';
import 'package:app_story/providers/app_state_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Story Deletion & State Reset Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyLastPlayedStory: 'Đấu Phá Thương Khung',
        AppConstants.keyLastPlayedChapter: 1,
        AppConstants.keyLastPlayedSentenceIndex: 3,
      });
    });

    test('isSameStory so khớp chính xác tên truyện không phân biệt hoa thường và khoảng trắng', () {
      expect(AppStateProvider.isSameStory('Đấu Phá Thương Khung', 'đấu phá thương khung'), isTrue);
      expect(AppStateProvider.isSameStory('  Đấu Phá  ', 'Đấu Phá'), isTrue);
      expect(AppStateProvider.isSameStory('Quỷ Bí Chi Chủ', 'Đấu La Đại Lục'), isFalse);
      expect(AppStateProvider.isSameStory(null, 'Đấu Phá'), isFalse);
      expect(AppStateProvider.isSameStory('Đấu Phá', null), isFalse);
      expect(AppStateProvider.isSameStory('', ''), isFalse);
    });

    test('clearCurrentStory đặt lại toàn bộ trạng thái về Chưa chọn truyện', () async {
      final appState = AppStateProvider();

      // Gọi clearCurrentStory
      await appState.clearCurrentStory();

      expect(appState.currentChapter, isNull);
      expect(appState.hasActiveChapter, isFalse);
      expect(appState.displayStoryTitle, isEmpty);
      expect(appState.headerTitle, 'Chưa chọn truyện');
      expect(appState.summarySentences, isEmpty);
      expect(appState.contentSentences, isEmpty);
      expect(appState.activeSentenceIndex, isNull);
      expect(appState.lastPlayedStoryTitle, isNull);
      expect(appState.lastPlayedChapterNumber, isNull);
      expect(appState.isProcessing, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConstants.keyLastPlayedStory), isNull);
    });
  });
}
