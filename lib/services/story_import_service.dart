import 'dart:async';
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

class _IsolateImportParams {
  final Uint8List bytes;
  final String fileName;
  final String sourcePath;
  final String ext;
  final SendPort sendPort;

  _IsolateImportParams({
    required this.bytes,
    required this.fileName,
    required this.sourcePath,
    required this.ext,
    required this.sendPort,
  });
}

void _isolateImportEntry(_IsolateImportParams params) {
  try {
    final service = StoryImportService();
    ImportStoryResult res;
    if (params.ext == '.txt') {
      res = service.importFromTxt(
        params.bytes,
        params.fileName,
        sourcePath: params.sourcePath,
        onProgress: (p, s, cur, tot) {
          params.sendPort.send({
            'type': 'progress',
            'progress': 0.05 + (p * 0.60), // 5% -> 65%
            'status': s,
            'current': cur,
            'total': tot,
          });
        },
      );
    } else {
      res = service.importFromEpub(
        params.bytes,
        params.fileName,
        sourcePath: params.sourcePath,
        onProgress: (p, s, cur, tot) {
          params.sendPort.send({
            'type': 'progress',
            'progress': 0.05 + (p * 0.60), // 5% -> 65%
            'status': s,
            'current': cur,
            'total': tot,
          });
        },
      );
    }
    params.sendPort.send({
      'type': 'result',
      'storyTitle': res.storyTitle,
      'sourcePath': res.sourcePath,
      'chapters': res.chapters,
    });
  } catch (e) {
    params.sendPort.send({
      'type': 'error',
      'message': e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
    });
  }
}

class _ExtractedChapterHeader {
  final int start;
  final int? chapterNumber;
  final String rawTitle;

  _ExtractedChapterHeader({
    required this.start,
    required this.chapterNumber,
    required this.rawTitle,
  });
}

class StoryImportService {
  /// Mở hộp thoại chọn file TXT hoặc EPUB và trích xuất danh sách chương (chạy trên Isolate ngầm với tiến độ thời gian thực)
  Future<ImportStoryResult?> pickAndImportStory({
    void Function(double progress, String status, String? storyTitle, int? current, int? total)? onProgress,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      final filePath = file.path ?? '';
      final fileName = file.name;
      final ext = p.extension(fileName).toLowerCase();

      if (ext != '.txt' && ext != '.epub') {
        throw Exception('Định dạng tệp $ext chưa được hỗ trợ. Vui lòng chọn .txt hoặc .epub');
      }

      final guessedTitle = p.basenameWithoutExtension(fileName).trim().replaceAll('_', ' ').replaceAll('-', ' ');
      onProgress?.call(0.02, 'Đang đọc tệp tin "$fileName"...', guessedTitle, 0, 0);

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

      onProgress?.call(0.05, 'Bắt đầu phân tích cấu trúc truyện...', guessedTitle, 0, 0);

      final receivePort = ReceivePort();
      final completer = Completer<ImportStoryResult>();

      final capturedBytes = bytes;
      final capturedFileName = fileName;
      final capturedPath = filePath;

      final isolate = await Isolate.spawn<_IsolateImportParams>(
        _isolateImportEntry,
        _IsolateImportParams(
          bytes: capturedBytes,
          fileName: capturedFileName,
          sourcePath: capturedPath,
          ext: ext,
          sendPort: receivePort.sendPort,
        ),
      );

      receivePort.listen((message) {
        if (message is Map) {
          final type = message['type'];
          if (type == 'progress') {
            final prog = (message['progress'] as num?)?.toDouble() ?? 0.0;
            final status = (message['status'] as String?) ?? '';
            final current = (message['current'] as int?);
            final total = (message['total'] as int?);
            onProgress?.call(prog, status, guessedTitle, current, total);
          } else if (type == 'result') {
            final storyTitle = message['storyTitle'] as String;
            final sourcePath = message['sourcePath'] as String;
            final chapters = (message['chapters'] as List).cast<ChapterModel>();
            completer.complete(ImportStoryResult(
              storyTitle: storyTitle,
              chapters: chapters,
              sourcePath: sourcePath,
            ));
          } else if (type == 'error') {
            completer.completeError(Exception(message['message']));
          }
        }
      });

      try {
        final importResult = await completer.future;
        return importResult;
      } finally {
        receivePort.close();
        isolate.kill(priority: Isolate.immediate);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Làm sạch và trích xuất tên truyện từ tên tệp tin (loại bỏ phần tác giả, tiền tố tag [Full], [Dịch], v.v.)
  static String cleanStoryTitle(String fileName) {
    String title = p.basenameWithoutExtension(fileName).trim();

    // 1. Loại bỏ các tag đóng mở ngoặc ở đầu/cuối như [Full], [Dịch], [Convert], 【完结】, 【全本】...
    title = title.replaceAll(
      RegExp(r'^[\[【(][^\]】)]*(?:full|hoàn|dịch|convert|raw|完结|全本|精校)[^\]】)]*[\]】)]\s*', caseSensitive: false),
      '',
    );

    // 2. Nếu có dạng 《Tên Truyện》 thì ưu tiên trích xuất tên trong ngoặc
    final bookTitleMatch = RegExp(r'《([^》]+)》').firstMatch(title);
    if (bookTitleMatch != null && bookTitleMatch.group(1)!.trim().isNotEmpty) {
      title = bookTitleMatch.group(1)!.trim();
    }

    // 3. Cắt bỏ phần thông tin tác giả ở cuối: " Tác giả: XYZ", " - Tác giả: XYZ", " 作者：XYZ", " by XYZ", " [Tác giả: XYZ]", " (作者: XYZ)"
    title = title.replaceAll(
      RegExp(r'[\s_\-–—]+[\[(（【]?(?:作者|tác\s*giả|author|by)[\s:：]+.*[\])）】]?$', caseSensitive: false),
      '',
    );

    // 4. Chuẩn hóa khoảng trắng, gạch dưới và dấu phân cách thừa ở cuối
    title = title
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\s_\-–—:：]+$'), '')
        .trim();
    if (title.isEmpty) {
      title = p.basenameWithoutExtension(fileName).trim();
      if (title.isEmpty) title = 'Truyện Nhập TXT';
    }
    return title;
  }

  /// Chuyển đổi số chương từ chữ Hán (一, 二, 十二, 一百零五...) hoặc số Ả Rập sang số nguyên
  static int? parseChapterNumber(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    final directDigits = int.tryParse(clean);
    if (directDigits != null) return directDigits;

    final Map<String, int> digitsMap = {
      '零': 0, '〇': 0, '0': 0,
      '一': 1, '1': 1, '壹': 1,
      '二': 2, '两': 2, '2': 2, '贰': 2,
      '三': 3, '3': 3, '叁': 3,
      '四': 4, '4': 4, '肆': 4,
      '五': 5, '5': 5, '伍': 5,
      '六': 6, '6': 6, '陆': 6,
      '七': 7, '7': 7, '柒': 7,
      '八': 8, '8': 8, '捌': 8,
      '九': 9, '9': 9, '玖': 9,
    };

    int total = 0;
    int currentVal = 0;

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (digitsMap.containsKey(char)) {
        currentVal = digitsMap[char]!;
      } else if (char == '十' || char == '拾') {
        if (currentVal == 0 && i == 0) currentVal = 1;
        total += currentVal * 10;
        currentVal = 0;
      } else if (char == '百' || char == '佰') {
        total += (currentVal == 0 ? 1 : currentVal) * 100;
        currentVal = 0;
      } else if (char == '千' || char == '仟') {
        total += (currentVal == 0 ? 1 : currentVal) * 1000;
        currentVal = 0;
      } else if (char == '万') {
        total = (total + currentVal) * 10000;
        currentVal = 0;
      }
    }
    total += currentVal;
    return total > 0 ? total : null;
  }

  /// Trích xuất truyện từ file TXT
  ImportStoryResult importFromTxt(
    Uint8List bytes,
    String fileName, {
    String sourcePath = '',
    void Function(double progress, String status, int current, int total)? onProgress,
  }) {
    String rawText;
    try {
      rawText = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      rawText = latin1.decode(bytes);
    }

    rawText = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Tên truyện được làm sạch tối ưu từ tên tệp (bỏ thông tin tác giả, tag, mở rộng .txt)
    final storyTitle = cleanStoryTitle(fileName);

    // Strategy 1: Tiêu đề chương có từ khóa rõ ràng (Chương, Chap, Chapter, Hồi, Tiết, 第...章, 番外, Ngoại truyện...)
    final explicitChapterRegex = RegExp(
      r'^\s*(?:(?:Chương|Hồi|Chap|Chapter|Tiết|Quyển\s*\d+\s*Chương|Hồi thứ|Phần|Tập|Mục)\s*(\d+)|第\s*([0-9零〇一二两俩仨三四五六七八九十廿卅百佰千仟万萬亿]+)\s*(?:章|节|回|集|话|卷|部|折|篇)|(?:章|Chapter|Chap)\s*([0-9零〇一二两俩仨三四五六七八九十廿卅百佰千仟万萬亿]+)|(?:番外|Ngoại truyện|Extra|Side Story)\s*([0-9零〇一二两俩仨三四五六七八九十廿卅百佰千仟万萬亿]*))[\s:：.\-–_]*(.*)$',
      caseSensitive: false,
      multiLine: true,
    );

    // Strategy 2: Tiêu đề chương dạng số thứ tự ở đầu dòng (vd: "001 下次再见，吃干抹尽", "1. Mở đầu", "1、Tiêu đề", "01 Tiêu đề")
    final numberedChapterRegex = RegExp(
      r'^\s*(?:(\d{2,4})\s+([^\d\s\n\r].*)|(\d{1,4})[、.．:：\-–—_]\s*([^\d\s\n\r].*)|([零〇一二两俩仨三四五六七八九十廿卅百佰千仟万萬]+)[、.．]\s*(.*))$',
      multiLine: true,
    );

    List<_ExtractedChapterHeader> detectedHeaders = [];

    // Thử Strategy 1
    final explicitMatches = explicitChapterRegex.allMatches(rawText).toList();
    if (explicitMatches.length >= 2) {
      for (final m in explicitMatches) {
        final numStr = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
        final chapNum = parseChapterNumber(numStr);
        final rawTitle = (m.group(5) ?? '').trim();
        detectedHeaders.add(_ExtractedChapterHeader(
          start: m.start,
          chapterNumber: chapNum,
          rawTitle: rawTitle,
        ));
      }
    } else {
      // Thử Strategy 2
      final numberedMatches = numberedChapterRegex.allMatches(rawText).toList();
      if (numberedMatches.length >= 2) {
        for (final m in numberedMatches) {
          final numStr = m.group(1) ?? m.group(3) ?? m.group(5) ?? '';
          final chapNum = parseChapterNumber(numStr);
          final rawTitle = (m.group(2) ?? m.group(4) ?? m.group(6) ?? '').trim();
          detectedHeaders.add(_ExtractedChapterHeader(
            start: m.start,
            chapterNumber: chapNum,
            rawTitle: rawTitle,
          ));
        }
      }
    }

    final List<ChapterModel> chapters = [];

    if (detectedHeaders.length >= 2) {
      // Sắp xếp theo vị trí bắt đầu
      detectedHeaders.sort((a, b) => a.start.compareTo(b.start));

      final total = detectedHeaders.length;
      int assignChapNum = 1;
      for (int i = 0; i < total; i++) {
        if (i % 20 == 0 || i == total - 1) {
          final frac = (i + 1) / total;
          onProgress?.call(frac, 'Đang xử lý chương ${i + 1}/$total...', i + 1, total);
        }

        final currentItem = detectedHeaders[i];
        final rawChapNum = currentItem.chapterNumber;
        final rawTitle = currentItem.rawTitle;
        final rawTitleLower = rawTitle.toLowerCase();

        // Bỏ qua nếu là chương 0 hoặc mục lục
        if (rawChapNum == 0 ||
            rawTitleLower == 'mục lục' ||
            rawTitleLower == 'muc luc' ||
            rawTitleLower == 'table of contents' ||
            rawTitleLower == 'danh sách chương') {
          continue;
        }

        final chapNum = rawChapNum ?? assignChapNum;
        final chapterTitle = rawTitle.isNotEmpty ? 'Chương $chapNum: $rawTitle' : 'Chương $chapNum';

        final startIndex = currentItem.start;
        final endIndex = (i + 1 < detectedHeaders.length) ? detectedHeaders[i + 1].start : rawText.length;
        String content = rawText.substring(startIndex, endIndex).trim();

        // Chuẩn hóa văn bản
        content = TextNormalizer.normalize(content);

        final isCjk = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF\u3040-\u30FF\uAC00-\uD7AF]').hasMatch(content);
        final wordCount = isCjk
            ? content.replaceAll(RegExp(r'\s+'), '').length
            : content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

        // Bỏ qua nếu nội dung quá ngắn (< 5 ký tự)
        if (content.length < 5) continue;

        chapters.add(ChapterModel(
          id: 'file_${storyTitle.hashCode}_$chapNum',
          storyTitle: storyTitle,
          chapterTitle: chapterTitle,
          chapterNumber: chapNum,
          sourceUrl: sourcePath.isNotEmpty ? 'file://$sourcePath' : 'file://$fileName',
          content: content,
          wordCount: wordCount,
        ));

        assignChapNum = chapNum + 1;
      }
    } else {
      // Không có cấu trúc tiêu đề chương rõ ràng, tự động phân đoạn theo dung lượng từ/ký tự
      final paragraphs = rawText.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      if (paragraphs.isEmpty) {
        paragraphs.add(rawText.trim());
      }

      final isCjk = RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF\u3040-\u30FF\uAC00-\uD7AF]').hasMatch(rawText);
      int getUnitCount(String s) {
        if (isCjk) {
          return s.replaceAll(RegExp(r'\s+'), '').length;
        } else {
          return s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        }
      }
      final targetThreshold = isCjk ? 3500 : 2200;

      final totalParas = paragraphs.length;
      final List<String> currentChunk = [];
      int currentUnits = 0;
      int chapIndex = 1;

      void flushChapter() {
        if (currentChunk.isEmpty) return;
        final content = TextNormalizer.normalize(currentChunk.join('\n\n'));
        final wCount = getUnitCount(content);
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
        currentUnits = 0;
      }

      for (int pIdx = 0; pIdx < totalParas; pIdx++) {
        final para = paragraphs[pIdx];
        if (pIdx % 50 == 0 || pIdx == totalParas - 1) {
          final frac = (pIdx + 1) / totalParas;
          onProgress?.call(frac, 'Đang phân đoạn chương (${pIdx + 1}/$totalParas đoạn)...', chapIndex, 0);
        }
        final units = getUnitCount(para);
        currentChunk.add(para);
        currentUnits += units;
        if (currentUnits >= targetThreshold) {
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
    void Function(double progress, String status, int current, int total)? onProgress,
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
    final totalSpine = spineItemIds.length;

    for (int i = 0; i < totalSpine; i++) {
      if (i % 15 == 0 || i == totalSpine - 1) {
        final frac = (i + 1) / totalSpine;
        onProgress?.call(frac, 'Đang đọc trang sách ${i + 1}/$totalSpine...', i + 1, totalSpine);
      }

      final idref = spineItemIds[i];
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

        // Bỏ qua trang Mục lục (TOC), Trang bìa hoặc Trang điều hướng để không bị nhận nhầm là Chương 1
        if (_isTableOfContentsOrExcludedPage(
          title: chapterTitle,
          body: bodyText,
          htmlContent: htmlContent,
          filePath: fullFilePath,
          idref: idref,
        )) {
          continue;
        }

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

  /// Kiểm tra xem một trang sách trong EPUB có phải là Mục lục (TOC), Trang bìa (Cover), hoặc Trang điều hướng cần bỏ qua
  static bool _isTableOfContentsOrExcludedPage({
    required String title,
    required String body,
    required String htmlContent,
    required String filePath,
    required String idref,
  }) {
    final lowerPath = filePath.toLowerCase();
    final lowerId = idref.toLowerCase();
    final lowerTitle = title.toLowerCase().trim();
    final lowerHtml = htmlContent.toLowerCase();

    // 1. Kiểm tra theo đường dẫn hoặc idref của file trong EPUB
    final excludedPatterns = [
      'toc', 'table-of-contents', 'tableofcontents', 'nav.', 'nav.xhtml',
      'muc-luc', 'mucluc', 'muc_luc', 'cover', 'titlepage', 'title_page',
      'halftitle', 'copyright', 'colophon', 'about'
    ];
    for (final pat in excludedPatterns) {
      if (lowerPath.contains(pat) || lowerId.contains(pat)) {
        return true;
      }
    }

    // 2. Kiểm tra các thuộc tính EPUB3 nav hoặc HTML tag toc
    if (lowerHtml.contains('epub:type="toc"') ||
        lowerHtml.contains('class="toc"') ||
        lowerHtml.contains('id="toc"') ||
        lowerHtml.contains('class="table-of-contents"') ||
        lowerHtml.contains('<nav id="toc"') ||
        lowerHtml.contains('properties="nav"')) {
      return true;
    }

    // 3. Kiểm tra Tiêu đề chương trích xuất
    final tocTitles = [
      'mục lục', 'muc luc', 'table of contents', 'contents', 'toc',
      'danh sách chương', 'danh sach chuong', 'bìa', 'trang bìa', 'cover',
      'thông tin xuất bản', 'giới thiệu tác phẩm', 'lời tựa'
    ];
    for (final tt in tocTitles) {
      if (lowerTitle == tt || lowerTitle.startsWith('$tt:') || lowerTitle.startsWith('$tt -')) {
        return true;
      }
    }

    // 4. Kiểm tra nội dung văn bản nếu ngắn và chứa nhiều danh mục chương
    if (body.length < 2500) {
      final chapCount = RegExp(r'(?:chương|chap|chapter|hồi)\s*\d+', caseSensitive: false).allMatches(body).length;
      if (chapCount >= 4) {
        return true; // Đây là trang liệt kê danh sách chương (Mục lục)
      }
    }

    return false;
  }
}
