class TextNormalizer {
  /// Chuẩn hóa toàn diện văn bản trước khi phân tách câu và tạo audio (TTS):
  /// 1. Loại bỏ các ký tự điều khiển ẩn, zero-width, BOM, soft hyphens.
  /// 2. Loại bỏ thẻ HTML và giải mã các HTML entities phổ biến.
  /// 3. Loại bỏ cú pháp Markdown (in đậm, in nghiêng, code, headers, bullets).
  /// 4. Chuyển đổi ký tự Full-width / CJK & ngoặc đặc biệt sang ký tự chuẩn.
  /// 5. Khử triệt để các ký tự né kiểm duyệt chèn giữa chữ cái (t·hi, t•hể, c*hết, s_át, g~iết, g.i.ế.t, m-á-u, đ|ánh, v.v.).
  /// 6. Thay thế từ khóa nhạy cảm theo ngữ cảnh đọc truyện (vd: "thi thể" -> "chết").
  /// 7. Loại bỏ từ cảm thán "a" / "A" đứng 1 mình ở cuối câu hoặc trước dấu kết câu.
  /// 8. Loại bỏ toàn bộ Emojis, Icons đồ họa, Dingbats, hình khối, nốt nhạc, mũi tên, ký hiệu toán học & tiền tệ.
  /// 9. Khử chuỗi ký tự phân cách trang trí lặp lại (---, ===, ~~~, ***, ###, v.v.).
  /// 10. Loại bỏ toàn bộ các ký tự đặc biệt còn lại (chỉ giữ chữ tiếng Việt, số, khoảng trắng và dấu câu chuẩn .,!?:;'"-()…\n).
  /// 11. Chuẩn hóa khoảng trắng và dấu câu (khoảng cách sau dấu câu, dọn dấu dính liền, bảo toàn số thập phân và xuống dòng).
  static String normalize(String input) {
    if (input.isEmpty) return input;

    String text = input;

    // 1. Loại bỏ ký tự zero-width, BOM, soft hyphens và ký tự điều khiển ẩn
    text = text.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u00AD\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]'),
      '',
    );

    // 2. Loại bỏ thẻ HTML & giải mã HTML entities
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', ' và ')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    text = text.replaceAll(RegExp(r'&#\d+;|&[a-zA-Z]+;'), ' ');

    // 3. Loại bỏ cú pháp Markdown
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!);
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!);
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1)!);
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1)!);
    text = text.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m.group(1)!);
    text = text.replaceAll(RegExp(r'```[^`]*```', multiLine: true), ' ');
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);
    text = text.replaceAll(RegExp(r'^\s*[#*•\-]+\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '');

    // 4. Chuyển đổi ký tự Full-width / CJK & ngoặc vuông/nhọn sang ký tự chuẩn
    text = text
        .replaceAll('，', ', ')
        .replaceAll('。', '. ')
        .replaceAll('！', '! ')
        .replaceAll('？', '? ')
        .replaceAll('：', ': ')
        .replaceAll('；', '; ')
        .replaceAll('（', ' (')
        .replaceAll('）', ') ')
        .replaceAll('【', ' ')
        .replaceAll('】', ' ')
        .replaceAll('〖', ' ')
        .replaceAll('〗', ' ')
        .replaceAll('［', ' ')
        .replaceAll('］', ' ')
        .replaceAll('｛', ' ')
        .replaceAll('｝', ' ')
        .replaceAll('「', '"')
        .replaceAll('」', '"')
        .replaceAll('『', '"')
        .replaceAll('』', '"')
        .replaceAll('〔', ' ')
        .replaceAll('〕', ' ')
        .replaceAll('〈', '"')
        .replaceAll('〉', '"')
        .replaceAll('《', '"')
        .replaceAll('》', '"')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('„', '"')
        .replaceAll('«', '"')
        .replaceAll('»', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('`', "'")
        .replaceAll('´', "'")
        .replaceAll('\u3000', ' ');

    // Chèn khoảng trắng sau dấu đóng ngoặc kép nếu ngay sau từ dính liền với từ tiếp theo
    text = text.replaceAllMapped(RegExp(r'([a-zA-ZÀ-ỹ0-9][”"»\)])(?=[a-zA-ZÀ-ỹ0-9])'), (m) => '${m.group(1)} ');

    // 5. Khử các ký tự né kiểm duyệt nằm giữa các ký tự của từ:
    // ví dụ: t·hi, t•hể, c*hết, s_át, g~iết, đ|ánh, m-á-u, c/h/ế/t, m\á\u, g#i#ế#t, k@o, v.v.
    final obfuscationPattern = RegExp(
      r'([a-zA-ZÀ-ỹ0-9])\s*[\u00B7\u2022\u2027\u22C5\u2024\*\_\~\|\/\#\@\$\%\^\&\+\=\-\\\\]\s*([a-zA-ZÀ-ỹ0-9])',
    );
    while (obfuscationPattern.hasMatch(text)) {
      text = text.replaceAllMapped(obfuscationPattern, (m) => '${m.group(1)}${m.group(2)}');
    }

    // Khử dấu chấm né kiểm duyệt giữa từng chữ cái không có khoảng trắng (vd: g.i.ế.t -> giết, t.h.i -> thi)
    // Lưu ý: Chỉ khử khi cả 2 bên là chữ cái dính liền dấu chấm (không có khoảng trắng, không áp dụng cho số thập phân 3.14)
    final dotObfuscationPattern = RegExp(
      r'([a-zA-ZÀ-ỹ])\.([a-zA-ZÀ-ỹ])',
    );
    while (dotObfuscationPattern.hasMatch(text)) {
      text = text.replaceAllMapped(dotObfuscationPattern, (m) => '${m.group(1)}${m.group(2)}');
    }

    // 6. Loại bỏ chuỗi ký tự phân cách trang trí lặp lại (vd: ------, ======, ~~~~~~, ****** v.v.)
    text = text.replaceAll(RegExp(r'(\s*[\-=_~*#]\s*){3,}'), ' ');

    // 7. Chuyển đổi từ khóa theo yêu cầu đọc đúng ngữ cảnh TTS:
    // "thi thể" -> "chết" (Bảo toàn chữ hoa/thường)
    text = text.replaceAllMapped(
      RegExp(r'(^|[^a-zA-ZÀ-ỹ0-9])thi\s+(?:thể|thê\u0309)(?![a-zA-ZÀ-ỹ0-9])', caseSensitive: false),
      (match) {
        final prefix = match.group(1) ?? '';
        final fullMatch = match.group(0)!;
        final raw = fullMatch.substring(prefix.length).trim();
        String replacement = 'chết';
        if (raw == raw.toUpperCase()) {
          replacement = 'CHẾT';
        } else if (raw.isNotEmpty && raw[0] == raw[0].toUpperCase()) {
          replacement = 'Chết';
        }
        return '$prefix$replacement';
      },
    );

    // 8. Loại bỏ từ cảm thán "a" / "A" đứng 1 mình ở cuối câu hoặc trước dấu kết câu:
    // VD: "Cái gì a?" -> "Cái gì?" | "Chuyện gì vậy a." -> "Chuyện gì vậy."
    text = text.replaceAll(RegExp(r'''(?<=\S)\s+[aA]\s*(?=[.!?…,:;\n”"'\)]+|$)'''), '');

    // 9. Loại bỏ toàn bộ Emojis, Symbols, Icon đồ họa, Dingbats, Box Drawing, Arrows, v.v.
    text = text.replaceAll(
      RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B50}-\u{2B59}\u{FE00}-\u{FE0F}\u{E000}-\u{F8FF}\u{D800}-\u{DFFF}]', unicode: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'[\u2500-\u259F\u2190-\u21FF\u27F0-\u27FF\u2900-\u297F\u2B00-\u2BFF]'),
      ' ',
    );

    // 10. Chuyển đổi các dấu gạch ngang dài
    text = text.replaceAll(RegExp(r'[—–―]'), ', ');

    // 11. Loại bỏ các ký tự đặc biệt, biểu tượng toán học, tiền tệ, hình khối, đồ họa còn lại
    // Chỉ giữ lại: chữ cái tiếng Việt, chữ số, khoảng trắng và các dấu câu tiêu chuẩn (. , ! ? : ; ' " - ( ) … \n)
    text = text.replaceAll(
      RegExp(r'''[^\sa-zA-Z0-9\u00C0-\u1EF9.,!?:;'"\-\(\)…\n]'''),
      ' ',
    );

    // 12. Tự động chèn khoảng trắng khi dấu câu dính liền với câu tiếp theo (VD: "câu 1.câu 2" -> "câu 1. câu 2")
    // Bảo toàn số thập phân (3.14, 1.5) bằng cách chỉ chèn khoảng trắng khi sau dấu chấm là chữ cái hoặc dấu mở ngoặc/kép
    text = text.replaceAllMapped(
      RegExp(r'(\.{3,}|…|[.!?])(?=[a-zA-ZÀ-ỹ“«\(\[{])'),
      (m) => '${m.group(1)} ',
    );

    // 13. Chuẩn hóa khoảng trắng và dấu câu thừa
    // Xóa khoảng trắng trong dấu ngoặc đơn: ( abc ) -> (abc)
    text = text.replaceAll(RegExp(r'\(\s+'), '(');
    text = text.replaceAll(RegExp(r'\s+\)'), ')');
    // Xóa khoảng trắng trước dấu câu (VD: "câu , từ ." -> "câu, từ.")
    text = text.replaceAllMapped(RegExp(r'[ \t]+([,.:;!?…])'), (m) => m.group(1)!);
    // Gộp dấu câu lặp lại (VD: "???" -> "?", "!!!" -> "!", ",," -> ",")
    text = text.replaceAllMapped(RegExp(r'([!?,;])\1+'), (m) => m.group(1)!);
    // Gộp nhiều dấu chấm thừa liên tiếp (giữ lại tối đa 3 chấm)
    text = text.replaceAll(RegExp(r'\.{4,}'), '...');
    // Chuẩn hóa khoảng trắng liên tiếp
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return text;
  }
}

