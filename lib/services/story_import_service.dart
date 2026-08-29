import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import '../models/chapter_model.dart';
import '../core/utils/text_normalizer.dart';

class ImportStoryResult {
  final String storyTitle;
  final List<ChapterModel> chapters;
  final String sourcePath;

  ImportStoryResult({
    required this.storyTitle,
    required this.chapters,
    required this.sourcePath,
  });
}

class StoryImportService {
  /// Mở hộp thoại chọn file TXT hoặc EPUB và trích xuất danh sách chương (chạy trên Isolate ngầm)
  Future<ImportStoryResult?> pickAndImportStory() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      final filePath = file.path ?? '';
      final fileName = file.name;
      final ext = p.extension(fileName).toLowerCase();

      Uint8List? bytes = file.bytes;
      if (bytes == null && filePath.isNotEmpty) {
        final f = File(filePath);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Không thể đọc dữ liệu từ tệp tin đã chọn.');
      }

      if (ext != '.txt' && ext != '.epub') {
        throw Exception('Định dạng tệp $ext chưa được hỗ trợ. Vui lòng chọn .txt hoặc .epub');
      }

      final capturedBytes = bytes;
      final capturedFileName = fileName;
      final capturedPath = filePath;

      // Chạy toàn bộ tiến trình phân tích file nặng trong Isolate ngầm để không đơ/lag UI
      return await Isolate.run(() {
        final service = StoryImportService();
        if (ext == '.txt') {
          return service.importFromTxt(capturedBytes, capturedFileName, sourcePath: capturedPath);
        } else {
          return service.importFromEpub(capturedBytes, capturedFileName, sourcePath: capturedPath);
        }
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Trích xuất truyện từ file TXT
  ImportStoryResult importFromTxt(
    Uint8List bytes,
    String fileName, {
    String sourcePath = '',
  }) {
    String rawText;
    try {
      rawText = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      rawText = latin1.decode(bytes);
    }

    rawText = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Tên truyện mặc định lấy từ tên tệp (bỏ phần mở rộng .txt)
    String storyTitle = p.basenameWithoutExtension(fileName).trim();
    storyTitle = storyTitle.replaceAll('_', ' ').replaceAll('-', ' ');
    if (storyTitle.isEmpty) storyTitle = 'Truyện Nhập TXT';

    final chapterRegex = RegExp(
      r'^\s*(?:Chương|Hồi|Chap|Chapter|Tiết|Quyển\s*\d+\s*Chương|Hồi thứ)\s*(\d+)[\s:：.\-–]*(.*)$',
      caseSensitive: false,
      multiLine: true,
    );

    final matches = chapterRegex.allMatches(rawText).toList();
    final List<ChapterModel> chapters = [];

    if (matches.length >= 2) {
      // Tìm thấy các tiêu đề chương rõ ràng
      for (int i = 0; i < matches.length; i++) {
        final currentMatch = matches[i];
        final chapNum = int.tryParse(currentMatch.group(1) ?? '') ?? (i + 1);
        final rawTitle = (currentMatch.group(2) ?? '').trim();
        final chapterTitle = rawTitle.isNotEmpty ? 'Chương $chapNum: $rawTitle' : 'Chương $chapNum';

        final startIndex = currentMatch.start;
        final endIndex = (i + 1 < matches.length) ? matches[i + 1].start : rawText.length;
        String content = rawText.substring(startIndex, endIndex).trim();

        // Chuẩn hóa văn bản
        content = TextNormalizer.normalize(content);
        final wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

        chapters.add(ChapterModel(
          id: 'file_${storyTitle.hashCode}_$chapNum',
          storyTitle: storyTitle,
          chapterTitle: chapterTitle,
          chapterNumber: chapNum,
          sourceUrl: sourcePath.isNotEmpty ? 'file://$sourcePath' : 'file://$fileName',
          content: content,
          wordCount: wordCount,
        ));
      }
    } else {
      // Không có cấu trúc "Chương X", tự động phân đoạn truyện theo số từ (~2500 từ / chương)
      final paragraphs = rawText.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      if (paragraphs.isEmpty) {
        paragraphs.add(rawText.trim());
      }

      final List<String> currentChunk = [];
      int currentWordCount = 0;
      int chapIndex = 1;

      void flushChapter() {
        if (currentChunk.isEmpty) return;
        final content = TextNormalizer.normalize(currentChunk.join('\n\n'));
        final wCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        chapters.add(ChapterModel(
          id: 'file_${storyTitle.hashCode}_$chapIndex',
          storyTitle: storyTitle,
          chapterTitle: 'Chương $chapIndex',
          chapterNumber: chapIndex,
          sourceUrl: sourcePath.isNotEmpty ? 'file://$sourcePath' : 'file://$fileName',
          content: 'Chương $chapIndex\n\n$content',
          wordCount: wCount,
        ));
        chapIndex++;
        currentChunk.clear();
        currentWordCount = 0;
      }

      for (final para in paragraphs) {
        final words = para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        currentChunk.add(para);
        currentWordCount += words;
        if (currentWordCount >= 2200) {
          flushChapter();
        }
      }
      flushChapter();
    }

    if (chapters.isEmpty) {
      throw Exception('Không thể trích xuất nội dung từ tệp tin TXT này.');
    }

    return ImportStoryResult(
      storyTitle: storyTitle,
      chapters: chapters,
      sourcePath: sourcePath,
    );
  }

  /// Trích xuất truyện từ file EPUB
  ImportStoryResult importFromEpub(
    Uint8List bytes,
    String fileName, {
    String sourcePath = '',
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw Exception('Không thể giải nén tệp EPUB (Tệp có thể bị hỏng hoặc định dạng không đúng): $e');
    }

    final fileMap = <String, ArchiveFile>{};
    for (final file in archive) {
      if (file.isFile) {
        fileMap[file.name.replaceAll('\\', '/')] = file;
      }
    }

    // Helper an toàn để lấy byte dữ liệu từ ArchiveFile
    List<int>? getFileBytes(ArchiveFile? file) {
      if (file == null) return null;
      try {
        final b = file.readBytes();
        if (b != null) return b;
      } catch (_) {}
      return null;
    }

    // Helper tìm file trong fileMap không phân biệt hoa thường và đường dẫn chuẩn hóa
    ArchiveFile? findFile(String targetPath) {
      final normalized = targetPath.replaceAll('\\', '/');
      if (fileMap.containsKey(normalized)) return fileMap[normalized];

      final lower = normalized.toLowerCase();
      for (final entry in fileMap.entries) {
        if (entry.key.toLowerCase() == lower) return entry.value;
      }

      // Thử tìm theo tên file ở đuôi
      final base = p.basename(normalized).toLowerCase();
      for (final entry in fileMap.entries) {
        if (entry.key.toLowerCase().endsWith('/$base') || entry.key.toLowerCase() == base) {
          return entry.value;
        }
      }
      return null;
    }

    // 1. Tìm tệp container.xml để lấy đường dẫn tệp OPF
    String opfPath = '';
    final containerFile = findFile('META-INF/container.xml');
    final containerBytes = getFileBytes(containerFile);
    if (containerBytes != null) {
      final containerXml = utf8.decode(containerBytes, allowMalformed: true);
      final match = RegExp(r'full-path="([^"]+)"', caseSensitive: false).firstMatch(containerXml);
      if (match != null) {
        opfPath = Uri.decodeFull(match.group(1)!);
      }
    }

    // Fallback nếu không tìm thấy container.xml: tìm tệp có đuôi .opf
    if (opfPath.isEmpty) {
      for (final path in fileMap.keys) {
        if (path.toLowerCase().endsWith('.opf')) {
          opfPath = path;
          break;
        }
      }
    }

    if (opfPath.isEmpty) {
      throw Exception('Tệp EPUB không hợp lệ: Không tìm thấy tệp kê khai OPF.');
    }

    final opfFile = findFile(opfPath);
    final opfBytes = getFileBytes(opfFile);
    if (opfBytes == null) {
      throw Exception('Không thể mở tệp OPF trong EPUB: $opfPath');
    }

    final opfDir = p.dirname(opfPath).replaceAll('\\', '/');
    final opfXml = utf8.decode(opfBytes, allowMalformed: true);
    final opfDoc = html_parser.parse(opfXml);

    // 2. Trích xuất Tên truyện từ metadata
    String storyTitle = '';
    final titleElements = opfDoc.querySelectorAll('*').where((e) {
      final name = e.localName?.toLowerCase() ?? '';
      return name == 'title' || name == 'dc:title' || name.endsWith(':title');
    });
    for (final el in titleElements) {
      final t = el.text.trim();
      if (t.isNotEmpty) {
        storyTitle = t;
        break;
      }
    }
    if (storyTitle.isEmpty) {
      storyTitle = p.basenameWithoutExtension(fileName).trim().replaceAll('_', ' ').replaceAll('-', ' ');
    }
    if (storyTitle.isEmpty) {
      storyTitle = 'Truyện Nhập EPUB';
    }

    // 3. Đọc danh sách manifest (id -> href)
    final manifestMap = <String, String>{};
    for (final item in opfDoc.querySelectorAll('item')) {
      final id = item.attributes['id'];
      var href = item.attributes['href'];
      if (id != null && href != null) {
        if (href.contains('#')) {
          href = href.split('#').first;
        }
        manifestMap[id] = Uri.decodeFull(href);
      }
    }

    // 4. Đọc thứ tự trang sách từ <spine>
    final spineItemIds = <String>[];
    for (final itemref in opfDoc.querySelectorAll('itemref')) {
      final idref = itemref.attributes['idref'];
      if (idref != null) {
        spineItemIds.add(idref);
      }
    }

    // Fallback nếu spine rỗng: lấy tất cả các file xhtml/html từ manifestMap
    if (spineItemIds.isEmpty) {
      for (final entry in manifestMap.entries) {
        final lower = entry.value.toLowerCase();
        if (lower.endsWith('.xhtml') || lower.endsWith('.html') || lower.endsWith('.htm')) {
          spineItemIds.add(entry.key);
        }
      }
    }

    final List<ChapterModel> chapters = [];
    int chapterNumber = 1;

    for (final idref in spineItemIds) {
      final relativeHref = manifestMap[idref];
      if (relativeHref == null) continue;

      // Xây dựng đường dẫn file trong zip
      String fullFilePath = opfDir.isNotEmpty && opfDir != '.'
          ? '$opfDir/$relativeHref'
          : relativeHref;
      fullFilePath = p.normalize(fullFilePath).replaceAll('\\', '/');

      ArchiveFile? chapterFile = findFile(fullFilePath);
      if (chapterFile == null) continue;

      try {
        final rawBytes = getFileBytes(chapterFile);
        if (rawBytes == null || rawBytes.isEmpty) continue;
        final htmlContent = utf8.decode(rawBytes, allowMalformed: true);

        // Bóc tách tiêu đề & nội dung siêu tốc bằng Regex & Unescape (nhanh hơn 100x DOM AST)
        final parsed = _extractEpubChapterFast(htmlContent, chapterNumber);
        if (parsed == null) continue;

        final chapterTitle = parsed['title']!;
        final bodyText = parsed['body']!;

        // Bỏ qua các trang quá ngắn (ví dụ trang bìa, mục lục rỗng < 20 ký tự)
        if (bodyText.length < 20) continue;

        final wordCount = bodyText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

        // Đảm bảo nội dung có tiêu đề ở đầu
        String finalContent = bodyText;
        if (!finalContent.toLowerCase().startsWith(chapterTitle.toLowerCase())) {
          finalContent = '$chapterTitle\n\n$finalContent';
        }

        final safeHash = storyTitle.hashCode.abs();
        chapters.add(ChapterModel(
          id: 'epub_${safeHash}_$chapterNumber',
          storyTitle: storyTitle,
          chapterTitle: chapterTitle,
          chapterNumber: chapterNumber,
          sourceUrl: sourcePath.isNotEmpty ? 'file://$sourcePath' : 'file://$fileName',
          content: finalContent,
          wordCount: wordCount,
        ));

        chapterNumber++;
      } catch (_) {}
    }

    if (chapters.isEmpty) {
      throw Exception('Không thể trích xuất chương truyện từ tệp tin EPUB này.');
    }

    return ImportStoryResult(
      storyTitle: storyTitle,
      chapters: chapters,
      sourcePath: sourcePath,
    );
  }

  /// Trích xuất nội dung chương EPUB siêu tốc và an toàn bộ nhớ
  static Map<String, String>? _extractEpubChapterFast(String htmlContent, int defaultChapterNumber) {
    if (htmlContent.trim().isEmpty) return null;

    // 1. Trích xuất Tiêu đề chương
    String chapterTitle = '';
    final hMatch = RegExp(r'<(?:h[1-3]|div|p)[^>]*class="[^"]*(?:chapter-title|title)[^"]*"[^>]*>(.*?)</(?:h[1-3]|div|p)>', caseSensitive: false, dotAll: true).firstMatch(htmlContent);
    if (hMatch != null) {
      chapterTitle = _stripHtmlAndUnescape(hMatch.group(1)!);
    }
    if (chapterTitle.isEmpty) {
      final hAnyMatch = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', caseSensitive: false, dotAll: true).firstMatch(htmlContent);
      if (hAnyMatch != null) {
        chapterTitle = _stripHtmlAndUnescape(hAnyMatch.group(1)!);
      }
    }
    if (chapterTitle.isEmpty) {
      final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(htmlContent);
      if (titleMatch != null) {
        chapterTitle = _stripHtmlAndUnescape(titleMatch.group(1)!);
      }
    }

    if (chapterTitle.isEmpty) {
      chapterTitle = 'Chương $defaultChapterNumber';
    }

    // 2. Xóa các khối script, style, head, nav, header, footer
    var cleanHtml = htmlContent
        .replaceAll(RegExp(r'<head\b[^>]*>.*?</head>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<nav\b[^>]*>.*?</nav>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<header\b[^>]*>.*?</header>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<footer\b[^>]*>.*?</footer>', caseSensitive: false, dotAll: true), '');

    // 3. Thay thế ngắt dòng
    cleanHtml = cleanHtml.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    cleanHtml = cleanHtml.replaceAll(RegExp(r'</(?:p|div|h[1-6]|li|tr|section|article)>', caseSensitive: false), '\n\n');

    // 4. Bỏ các tag html còn lại
    cleanHtml = cleanHtml.replaceAll(RegExp(r'<[^>]+>'), '');

    // 5. Unescape HTML entities & chuẩn hóa văn bản
    var bodyText = _unescapeHtml(cleanHtml);
    bodyText = TextNormalizer.normalize(bodyText).trim();

    return {
      'title': chapterTitle,
      'body': bodyText,
    };
  }

  static String _stripHtmlAndUnescape(String html) {
    var text = html.replaceAll(RegExp(r'<[^>]+>'), '');
    return _unescapeHtml(text).trim();
  }

  static String _unescapeHtml(String text) {
    if (!text.contains('&')) return text;
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }
}
