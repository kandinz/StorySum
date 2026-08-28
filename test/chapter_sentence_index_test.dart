import 'package:flutter_test/flutter_test.dart';
import 'package:app_story/models/chapter_model.dart';
import 'package:app_story/models/saved_audio_item.dart';

void main() {
  group('Chapter & SavedAudioItem Sentence Index Tests', () {
    test('ChapterModel serialization preserves summary and content indexes', () {
      final chapter = ChapterModel(
        id: 'chap_1',
        storyTitle: 'Đấu Phá Khung Thương',
        chapterTitle: 'Chương 1',
        chapterNumber: 1,
        sourceUrl: 'https://example.com/1',
        content: 'Nội dung câu 1. Nội dung câu 2.',
        wordCount: 10,
        lastPlayedSentenceIndex: 3,
        lastPlayedSummaryIndex: 2,
        lastPlayedContentIndex: 5,
        lastPlayedSource: 'summary',
      );

      final map = chapter.toMap();
      expect(map['last_played_summary_index'], 2);
      expect(map['last_played_content_index'], 5);

      final fromMap = ChapterModel.fromMap(map);
      expect(fromMap.lastPlayedSummaryIndex, 2);
      expect(fromMap.lastPlayedContentIndex, 5);
      expect(fromMap.lastPlayedSource, 'summary');
    });

    test('SavedAudioItem serialization preserves summary and content indexes', () {
      final audioItem = SavedAudioItem(
        id: 'audio_1',
        title: 'Chương 1',
        storyTitle: 'Đấu Phá Khung Thương',
        chapterNumber: 1,
        audioPath: '/path/to/audio.mp3',
        summaryText: 'Tóm tắt câu 1.',
        content: 'Nội dung câu 1.',
        lastPlayedSentenceIndex: 4,
        lastPlayedSummaryIndex: 1,
        lastPlayedContentIndex: 4,
        lastPlayedSource: 'content',
      );

      final map = audioItem.toMap();
      expect(map['last_played_summary_index'], 1);
      expect(map['last_played_content_index'], 4);

      final fromMap = SavedAudioItem.fromMap(map);
      expect(fromMap.lastPlayedSummaryIndex, 1);
      expect(fromMap.lastPlayedContentIndex, 4);
      expect(fromMap.lastPlayedSource, 'content');
    });

    test('Last sentence reset logic resets to 0 (câu đầu tiên)', () {
      int getEffectiveSentenceIndex(int savedIndex, int totalSentences) {
        if (totalSentences <= 0) return 0;
        if (savedIndex >= totalSentences - 1) {
          return 0;
        }
        if (savedIndex < 0 || savedIndex >= totalSentences) {
          return 0;
        }
        return savedIndex;
      }

      expect(getEffectiveSentenceIndex(0, 10), 0);
      expect(getEffectiveSentenceIndex(5, 10), 5);
      expect(getEffectiveSentenceIndex(9, 10), 0);
      expect(getEffectiveSentenceIndex(10, 10), 0);
      expect(getEffectiveSentenceIndex(-1, 10), 0);
    });
  });
}
