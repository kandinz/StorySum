import 'package:flutter_test/flutter_test.dart';
import 'package:app_story/core/utils/text_normalizer.dart';
import 'package:app_story/providers/app_state_provider.dart';

void main() {
  group('TextNormalizer Tests', () {
    test('Removes middle dot and special characters inside words', () {
      expect(TextNormalizer.normalize('g·iết'), 'giết');
      expect(TextNormalizer.normalize('c·hết'), 'chết');
      expect(TextNormalizer.normalize('m·áu'), 'máu');
      expect(TextNormalizer.normalize('s·át n·hân'), 'sát nhân');
      expect(TextNormalizer.normalize('b·ạo l·ực'), 'bạo lực');
      expect(TextNormalizer.normalize('t·h·i'), 'thi');
      expect(TextNormalizer.normalize('t•hi'), 'thi');
      expect(TextNormalizer.normalize('t*hi'), 'thi');
      expect(TextNormalizer.normalize('t_hi'), 'thi');
      expect(TextNormalizer.normalize('g.i.ế.t'), 'giết');
      expect(TextNormalizer.normalize('m-á-u'), 'máu');
      expect(TextNormalizer.normalize('c/h/ế/t'), 'chết');
      expect(TextNormalizer.normalize('đ|ánh'), 'đánh');
    });

    test('Converts "t·hi t·hể" and "thi thể" to "chết" accurately', () {
      expect(TextNormalizer.normalize('t·hi t·hể'), 'chết');
      expect(TextNormalizer.normalize('T·hi T·hể'), 'Chết');
      expect(TextNormalizer.normalize('thi thể'), 'chết');
      expect(TextNormalizer.normalize('Thi thể'), 'Chết');
      expect(TextNormalizer.normalize('THI THỂ'), 'CHẾT');
    });

    test('Normalizes full sentence with "t·hi t·hể" for TTS audio', () {
      const input = 'Phát hiện một t·hi t·hể nằm trên nền đất, g·iết người c·ướp của.';
      final output = TextNormalizer.normalize(input);
      expect(output, 'Phát hiện một chết nằm trên nền đất, giết người cướp của.');
    });

    test('Removes ending particle "a" / "A" standing alone at sentence end', () {
      expect(TextNormalizer.normalize('Cái gì a?'), 'Cái gì?');
      expect(TextNormalizer.normalize('Chuyện gì vậy a.'), 'Chuyện gì vậy.');
      expect(TextNormalizer.normalize('Ngươi là ai a!'), 'Ngươi là ai!');
      expect(TextNormalizer.normalize('Thật sao a...'), 'Thật sao...');
      expect(TextNormalizer.normalize('Đúng vậy a'), 'Đúng vậy');
      expect(TextNormalizer.normalize('Ngươi nói cái gì A?'), 'Ngươi nói cái gì?');
      expect(TextNormalizer.normalize('“Cái gì a?”'), '"Cái gì?"');
      // Không được cắt chữ của các từ kết thúc bằng "a"
      expect(TextNormalizer.normalize('Ta đi qua nhà ba.'), 'Ta đi qua nhà ba.');
      expect(TextNormalizer.normalize('A! Ngươi đã tới.'), 'A! Ngươi đã tới.');
    });

    test('Removes HTML tags and decodes entities', () {
      expect(TextNormalizer.normalize('<p>Xin <b>chào</b> các bạn!</p>'), 'Xin chào các bạn!');
      expect(TextNormalizer.normalize('Tiêu Viêm &amp; Dược Lão'), 'Tiêu Viêm và Dược Lão');
      expect(TextNormalizer.normalize('&quot;Ta đồng ý&quot;'), '"Ta đồng ý"');
      expect(TextNormalizer.normalize('Chương 1&nbsp;&nbsp;Khởi đầu'), 'Chương 1 Khởi đầu');
    });

    test('Removes Markdown syntax and headers', () {
      expect(TextNormalizer.normalize('### Chương 10: Trận chiến **quyết định**!'), 'Chương 10: Trận chiến quyết định!');
      expect(TextNormalizer.normalize('*Nghiêng* và __đậm__ cùng ~~gạch ngang~~'), 'Nghiêng và đậm cùng gạch ngang');
      expect(TextNormalizer.normalize('> Trích dẫn lời nói'), 'Trích dẫn lời nói');
      expect(TextNormalizer.normalize('```dart\nvar a = 1;\n```\nNội dung sau code'), 'Nội dung sau code');
    });

    test('Converts full-width CJK punctuation to standard punctuation', () {
      expect(TextNormalizer.normalize('Tiêu Viêm，ngươi muốn chết sao？'), 'Tiêu Viêm, ngươi muốn chết sao?');
      expect(TextNormalizer.normalize('【Hệ Thống】Thông báo！'), 'Hệ Thống Thông báo!');
      expect(TextNormalizer.normalize('《Đấu Phá Thương Khung》rất hay。'), '"Đấu Phá Thương Khung" rất hay.');
    });

    test('Removes Emojis, Icons, Dingbats, Math and Graphic symbols', () {
      expect(TextNormalizer.normalize('Chào mừng bạn 🔥👏🎉 đã đến với câu chuyện!'), 'Chào mừng bạn đã đến với câu chuyện!');
      expect(TextNormalizer.normalize('★ Tiêu Viêm ★ Đấu Đế ⚡'), 'Tiêu Viêm Đấu Đế');
      expect(TextNormalizer.normalize('Giá: \$100 ± 5% (chuẩn ✔)'), 'Giá: 100 5 (chuẩn)');
      expect(TextNormalizer.normalize('→ Nhấp vào đây ➔ ➜'), 'Nhấp vào đây');
    });

    test('Removes repetitive decorative separators', () {
      expect(TextNormalizer.normalize('------ Chương 1 ------'), 'Chương 1');
      expect(TextNormalizer.normalize('====== Hết ======~~~~~~'), 'Hết');
      expect(TextNormalizer.normalize('Tiêu Viêm mỉm cười. * * * Sau đó hắn rời đi.'), 'Tiêu Viêm mỉm cười. Sau đó hắn rời đi.');
    });

    test('Preserves decimal numbers and inserts space for joined punctuation', () {
      expect(TextNormalizer.normalize('câu 1.câu 2'), 'câu 1. câu 2');
      expect(TextNormalizer.normalize('Giá trị Pi là 3.14159 và 1.5 mét.'), 'Giá trị Pi là 3.14159 và 1.5 mét.');
      expect(TextNormalizer.normalize('ai đó?tôi đây!mau lên...nguy cấp'), 'ai đó? tôi đây! mau lên... nguy cấp');
    });
  });

  group('AppStateProvider splitIntoSentences with Normalization', () {
    final appState = AppStateProvider();

    test('Splits and normalizes sentences simultaneously', () {
      const text = 'Hắn thấy t·hi t·hể của đối phương. Tên s·át n·hân đã bỏ trốn!';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 2);
      expect(sentences[0].text, 'Hắn thấy chết của đối phương.');
      expect(sentences[1].text, 'Tên sát nhân đã bỏ trốn!');
    });

    test('Splits text with emojis, symbols and markdown cleanly', () {
      const text = '🎉 **Chúc mừng!** Ngươi đã vượt qua thử thách 🔥.\n• Hãy cẩn thận tiếp theo ★!';
      final sentences = appState.splitIntoSentences(text);

      expect(sentences.length, 3);
      expect(sentences[0].text, 'Chúc mừng!');
      expect(sentences[1].text, 'Ngươi đã vượt qua thử thách.');
      expect(sentences[2].text, 'Hãy cẩn thận tiếp theo!');
    });
  });
}
