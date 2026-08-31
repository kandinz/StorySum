import 'package:flutter_test/flutter_test.dart';
import 'package:app_story/providers/app_state_provider.dart';
import 'package:app_story/models/chapter_model.dart';

void main() {
  group('Sentence Splitting Tests', () {
    final appState = AppStateProvider();

    test('Splits sentences by punctuation (. ! ? …)', () {
      const text = 'Tiêu Viêm mở mắt ra. Hắn nhìn xung quanh! Nơi này là đâu? Thật kỳ lạ…';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 4);
      expect(sentences[0].index, 0);
      expect(sentences[0].text, 'Tiêu Viêm mở mắt ra.');
      expect(sentences[1].index, 1);
      expect(sentences[1].text, 'Hắn nhìn xung quanh!');
      expect(sentences[2].index, 2);
      expect(sentences[2].text, 'Nơi này là đâu?');
      expect(sentences[3].index, 3);
      expect(sentences[3].text, 'Thật kỳ lạ…');
    });

    test('Splits sentences with newlines and bullet points', () {
      const text = '• Điểm thứ nhất.\n• Điểm thứ hai.\nĐiểm thứ ba.';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 3);
      expect(sentences[0].text, 'Điểm thứ nhất.');
      expect(sentences[1].text, 'Điểm thứ hai.');
      expect(sentences[2].text, 'Điểm thứ ba.');
    });

    test('Handles empty text gracefully', () {
      final sentences = appState.splitIntoSentences('   ');
      expect(sentences, isEmpty);
    });

    test('Builds sentence list with chapter header prepended', () {
      final chapter = ChapterModel(
        id: '1',
        storyTitle: 'Đấu Phá Thương Khung',
        chapterTitle: 'Gặp gỡ Dược Lão',
        chapterNumber: 178,
        sourceUrl: '',
        content: 'Tiêu Viêm đứng dậy. Hắn bắt đầu tu luyện.',
        wordCount: 10,
      );

      final sentences = appState.buildSentenceListWithHeader(chapter.content, chapter);

      expect(sentences.length, 3);
      expect(sentences[0].index, 0);
      expect(sentences[0].text, 'Chương 178: Gặp gỡ Dược Lão');
      expect(sentences[1].index, 1);
      expect(sentences[2].index, 2);
      expect(sentences[2].text, 'Hắn bắt đầu tu luyện.');
    });

    test('Tách câu khi dấu chấm dính liền (vd câu 1.câu 2)', () {
      const text = 'câu 1.câu 2';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 2);
      expect(sentences[0].text, 'câu 1.');
      expect(sentences[1].text, 'câu 2');
    });

    test('Tách câu khi các dấu câu khác dính liền (! ? …)', () {
      const text = 'ngươi là ai?ta là Tiêu Viêm!chạy mau...nguy hiểm quá';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 4);
      expect(sentences[0].text, 'ngươi là ai?');
      expect(sentences[1].text, 'ta là Tiêu Viêm!');
      expect(sentences[2].text, 'chạy mau...');
      expect(sentences[3].text, 'nguy hiểm quá');
    });

    test('Bảo toàn số thập phân không bị tách nhầm', () {
      const text = 'Giá trị số Pi xấp xỉ 3.14159. Khoảng cách là 1.5 km.';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 2);
      expect(sentences[0].text, 'Giá trị số Pi xấp xỉ 3.14159.');
      expect(sentences[1].text, 'Khoảng cách là 1.5 km.');
    });

    test('Bỏ qua các câu không có chữ cái tiếng Việt, tiếng Anh hoặc chữ số', () {
      const text = 'Câu thứ nhất hợp lệ.\n...\n---\n(   )\n\n!!!\nCâu thứ hai hợp lệ với số 123.\n【】\n\nCâu thứ ba kết thúc.';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 3);
      expect(sentences[0].text, 'Câu thứ nhất hợp lệ.');
      expect(sentences[1].text, 'Câu thứ hai hợp lệ với số 123.');
      expect(sentences[2].text, 'Câu thứ ba kết thúc.');
    });

    test('Bỏ qua câu chỉ chứa ký tự đặc biệt hoặc tiếng Trung/Nhật không có chữ cái tiếng Việt/Anh/số', () {
      const text = 'Tiêu Viêm mở mắt.\n（完）\n【作者有话说】\n***\n（下期再见）\n\nHắn bắt đầu bước đi.';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 2);
      expect(sentences[0].text, 'Tiêu Viêm mở mắt.');
      expect(sentences[1].text, 'Hắn bắt đầu bước đi.');
    });
  });
}
