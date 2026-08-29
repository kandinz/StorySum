import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../models/chapter_model.dart';
import '../core/utils/text_normalizer.dart';

class CrawlerService {
  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,application/json,*/*;q=0.8',
    'Accept-Language': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
    'Cache-Control': 'no-cache',
  };

  /// Bộ nhớ đệm DNS phân giải qua DNS-over-HTTPS (DoH)
  static final Map<String, String> _dohDnsCache = {};

  /// Phân giải tên miền qua Google DoH để vượt chặn DNS của ISP Việt Nam
  Future<String?> resolveDoH(String host) async {
    if (_dohDnsCache.containsKey(host)) return _dohDnsCache[host];
    try {
      final uri = Uri.parse('https://dns.google/resolve?name=$host&type=A');
      final client = HttpClient();
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 4));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      final answers = json['Answer'] as List?;
      if (answers != null && answers.isNotEmpty) {
        for (var a in answers) {
          final ip = a['data'] as String?;
          if (ip != null &&
              !ip.startsWith('127.') &&
              ip != '0.0.0.0' &&
              RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) {
            _dohDnsCache[host] = ip;
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Tải nội dung web an toàn, tự động giải nén Gzip/Deflate, timeouts và DoH fallback
  Future<String> fetchUrlContent(String url, {Map<String, String>? customHeaders}) async {
    final normalized = normalizeUrl(url);
    final uri = Uri.parse(normalized);
    final mergedHeaders = {
      ..._headers,
      if (customHeaders != null) ...customHeaders,
    };

    // 1. Thử tải qua HttpClient với autoUncompress = true & Connection: close
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.autoUncompress = true;
      client.badCertificateCallback = ((cert, host, port) => true);

      try {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
        for (var entry in mergedHeaders.entries) {
          req.headers.set(entry.key, entry.value);
        }
        req.headers.set('Connection', 'close');

        final resp = await req.close().timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          return await resp.transform(utf8.decoder).join();
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {}

    // 2. Fallback: Phân giải DoH và gửi request với SNI Host Header (Bypass ISP block & DNS Hijacking)
    try {
      final host = uri.host;
      final targetIp = await resolveDoH(host);
      if (targetIp != null && targetIp != host) {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        client.autoUncompress = true;
        client.badCertificateCallback = ((cert, host, port) => true);

        try {
          final port = uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
          final path = uri.hasQuery ? '${uri.path}?${uri.query}' : (uri.path.isEmpty ? '/' : uri.path);
          final directUri = Uri(
            scheme: uri.scheme,
            host: targetIp,
            port: port,
            path: path,
          );

          final req = await client.getUrl(directUri).timeout(const Duration(seconds: 10));
          for (var entry in mergedHeaders.entries) {
            req.headers.set(entry.key, entry.value);
          }
          req.headers.set('Host', host);
          req.headers.set('Connection', 'close');

          final resp = await req.close().timeout(const Duration(seconds: 12));
          if (resp.statusCode == 200) {
            return await resp.transform(utf8.decoder).join();
          }
        } finally {
          client.close(force: true);
        }
      }
    } catch (_) {}

    // 3. Fallback cuối: http.get tiêu chuẩn
    try {
      final resp = await http.get(uri, headers: mergedHeaders).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        try {
          return utf8.decode(resp.bodyBytes);
        } catch (_) {
          return resp.body;
        }
      }
      throw Exception('Mã phản hồi máy chủ: ${resp.statusCode}');
    } catch (e) {
      throw Exception('Không thể kết nối đến máy chủ ($url): $e');
    }
  }

  /// Chuẩn hóa URL, tự động bổ sung scheme https:// nếu người dùng dán thiếu
  String normalizeUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    return trimmed;
  }

  /// Kiểm tra chuỗi nhập vào có phải là URL hay không
  bool isLikelyUrl(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('www.')) {
      return true;
    }
    final urlRegex = RegExp(r'^(?:https?:\/\/)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:\/.*)?$');
    return urlRegex.hasMatch(lower);
  }

  /// Trích xuất số chương từ bất kỳ định dạng link truyện nào
  int? extractChapterNumberFromUrl(String url) {
    final trimmed = normalizeUrl(url);
    if (trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse(trimmed);

      // 1. Kiểm tra Query Parameters (ví dụ: ?chapter=123, ?chap=123, ?chuong=123, ?c=123, ?ch=123, ?ep=123)
      for (final key in ['chapter', 'chap', 'chuong', 'ch', 'c', 'ep', 'episode', 'page']) {
        if (uri.queryParameters.containsKey(key)) {
          final val = uri.queryParameters[key];
          if (val != null) {
            final match = RegExp(r'\d+').firstMatch(val);
            if (match != null) {
              return int.tryParse(match.group(0)!);
            }
          }
        }
      }
    } catch (_) {}

    // 2. Tìm kiếm các mẫu từ khóa kèm số trong URL: chuong-123, chap_123, chapter123, hoi-123, tap-123, c123
    final keywordRegex = RegExp(
      r'(?:chuong|chap|chapter|hoi|tap|episode|ep|c)[-_/\s]*(\d+)',
      caseSensitive: false,
    );
    final allMatches = keywordRegex.allMatches(trimmed).toList();
    if (allMatches.isNotEmpty) {
      final lastMatch = allMatches.last;
      final numStr = lastMatch.group(1);
      if (numStr != null) {
        final parsed = int.tryParse(numStr);
        if (parsed != null) return parsed;
      }
    }

    // 3. Kiểm tra số ở phân đoạn cuối cùng của URL (VD: .../123/ hoặc .../123.html hoặc .../123)
    final endNumberRegex = RegExp(
      r'[-_/](\d+)(?:\.html|\.htm|/)?$',
      caseSensitive: false,
    );
    final endMatch = endNumberRegex.firstMatch(trimmed);
    if (endMatch != null) {
      final numStr = endMatch.group(1);
      if (numStr != null) {
        final parsed = int.tryParse(numStr);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  /// Phân tích thông minh URL đầu vào
  Map<String, dynamic> parseUrlAndChapter(String inputUrl) {
    String trimmed = normalizeUrl(inputUrl);
    if (trimmed.isEmpty) {
      return {'baseUrl': '', 'chapter': null};
    }

    final chapterNum = extractChapterNumberFromUrl(trimmed);
    return {
      'baseUrl': trimmed,
      'chapter': chapterNum,
    };
  }

  /// Tự động sinh URL đầy đủ cho số chương đích từ link hiện tại mà vẫn giữ nguyên cấu trúc link
  String buildChapterUrl(String currentUrl, int targetChapterNumber) {
    String trimmed = normalizeUrl(currentUrl);
    if (trimmed.isEmpty) return '';

    // 1. Nếu có template {chapter}
    if (trimmed.contains('{chapter}')) {
      return trimmed.replaceAll('{chapter}', targetChapterNumber.toString());
    }

    // 2. Nếu có Query Parameters (ví dụ ?chap=123)
    try {
      final uri = Uri.parse(trimmed);
      for (final key in ['chapter', 'chap', 'chuong', 'ch', 'c', 'ep', 'episode', 'page']) {
        if (uri.queryParameters.containsKey(key)) {
          final queryMap = Map<String, String>.from(uri.queryParameters);
          queryMap[key] = targetChapterNumber.toString();
          return uri.replace(queryParameters: queryMap).toString();
        }
      }
    } catch (_) {}

    // 3. Nếu URL chứa từ khóa chương (chuong-123, chap-123, chapter123, c123, ...)
    final keywordRegex = RegExp(
      r'((?:chuong|chap|chapter|hoi|tap|episode|ep|c)[-_/\s]*)(\d+)',
      caseSensitive: false,
    );
    final allMatches = keywordRegex.allMatches(trimmed).toList();
    if (allMatches.isNotEmpty) {
      final lastMatch = allMatches.last;
      final prefix = lastMatch.group(1)!;
      final before = trimmed.substring(0, lastMatch.start);
      final after = trimmed.substring(lastMatch.end);
      return '$before$prefix$targetChapterNumber$after';
    }

    // 4. Nếu URL kết thúc bằng số trước đuôi (VD: .../123/ hoặc .../123.html)
    final endNumberRegex = RegExp(
      r'([-_/])(\d+)((?:\.html|\.htm|/)?)$',
      caseSensitive: false,
    );
    final endMatch = endNumberRegex.firstMatch(trimmed);
    if (endMatch != null) {
      final sep = endMatch.group(1)!;
      final suffix = endMatch.group(3) ?? '';
      final before = trimmed.substring(0, endMatch.start);
      return '$before$sep$targetChapterNumber$suffix';
    }

    // 5. Nếu URL là base dạng .../chuong- hoặc kết thúc bằng -
    if (trimmed.endsWith('-')) {
      return '$trimmed$targetChapterNumber';
    }

    // 6. Nếu URL kết thúc bằng / (VD: https://webnovel.vn/van-co-than-de/)
    if (trimmed.endsWith('/')) {
      return '${trimmed}chuong-$targetChapterNumber/';
    }

    // 7. Fallback: nối thêm /chuong-{number}/
    return '$trimmed/chuong-$targetChapterNumber/';
  }

  /// Crawl một chương truyện dựa vào Base URL và số chương
  Future<ChapterModel> fetchChapter({
    required String baseUrl,
    required int chapterNumber,
  }) async {
    final targetUrl = buildChapterUrl(baseUrl, chapterNumber);
    return crawlChapterFromUrl(targetUrl.isNotEmpty ? targetUrl : baseUrl, chapterNumber: chapterNumber);
  }

  /// Kiểm tra xem trang vừa tải có phải là trang thông tin/mục lục truyện thay vì trang đọc chương hay không
  /// Nếu đúng, tìm kiếm đường link đọc chương thực sự từ danh sách chương trên trang
  String? _findActualChapterUrlFromDoc(dom.Document doc, String currentUrl, int targetChapterNumber) {
    // 1. Kiểm tra nếu trang đã có container đọc chương rõ ràng với độ dài văn bản đủ lớn
    final readingSelectors = [
      '#chapter-c',
      '.chapter-c',
      '#chapter-reading-content',
      '#reading-content',
      '.reading-content',
      '#chap-content',
      '#chapter-content',
      '#vungdoc',
      '.box-chap',
    ];
    for (final sel in readingSelectors) {
      final el = doc.querySelector(sel);
      if (el != null && el.text.trim().length > 150) {
        return null; // Đã là trang đọc chương hợp lệ
      }
    }

    // 2. Quét toàn bộ thẻ <a> trên trang để tìm link khớp với số chương yêu cầu
    final allLinks = doc.querySelectorAll(
      '#list-chapter a, .list-chapter a, ul.list-chapter a, .l-chapters a, .list-chapters a, a[href*="chuong"], a[href*="quyen"], a[href*="chap"]',
    );

    // Ưu tiên 1: Tìm link có href hoặc text khớp chính xác số chương
    for (final a in allLinks) {
      final href = a.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href == '#' || href.startsWith('javascript:')) continue;

      final text = a.text.trim().toLowerCase();
      final title = (a.attributes['title'] ?? '').toLowerCase();
      final hrefLower = href.toLowerCase();

      // Kiểm tra pattern chuong-X hoặc quyen-Y-chuong-X
      final matchInHref = RegExp('(?:quyen-\\d+-)?chuong-$targetChapterNumber(?:/|\\.html|\$)', caseSensitive: false).hasMatch(hrefLower);
      final matchInText = RegExp('chương\\s*$targetChapterNumber\\b', caseSensitive: false).hasMatch(text) ||
          RegExp('chap\\s*$targetChapterNumber\\b', caseSensitive: false).hasMatch(text);
      final matchInTitle = RegExp('chương\\s*$targetChapterNumber\\b', caseSensitive: false).hasMatch(title);

      if (matchInHref || matchInText || matchInTitle) {
        try {
          final resolved = Uri.parse(currentUrl).resolve(href).toString();
          if (resolved != currentUrl) {
            return resolved;
          }
        } catch (_) {}
      }
    }

    // Ưu tiên 2: Nếu targetChapterNumber == 1 và chưa tìm thấy, lấy link chương đầu tiên trong danh sách chương
    if (targetChapterNumber == 1) {
      final firstChapterLinks = doc.querySelectorAll(
        '#list-chapter a[href*="chuong"], .list-chapter a[href*="chuong"], ul.list-chapter a, .l-chapters a',
      );
      for (final a in firstChapterLinks) {
        final href = a.attributes['href']?.trim() ?? '';
        if (href.isNotEmpty && !href.contains('trang-') && !href.startsWith('javascript:')) {
          try {
            final resolved = Uri.parse(currentUrl).resolve(href).toString();
            if (resolved != currentUrl) {
              return resolved;
            }
          } catch (_) {}
        }
      }
    }

    return null;
  }

  /// Crawl một chương truyện trực tiếp từ URL đầy đủ
  Future<ChapterModel> crawlChapterFromUrl(String targetUrl, {int? chapterNumber}) async {
    final normalizedUrl = normalizeUrl(targetUrl);
    final lowerUrl = normalizedUrl.toLowerCase();

    // 1. Xử lý chuyên biệt cho truyendichmienphi.com
    if (lowerUrl.contains('truyendichmienphi')) {
      return _crawlTruyenDichMienPhi(normalizedUrl, chapterNumber: chapterNumber);
    }

    // 2. Crawl tiêu chuẩn cho tất cả các trang web khác
    try {
      String htmlContent = await fetchUrlContent(normalizedUrl);
      if (htmlContent.trim().isEmpty) {
        throw Exception('Không nhận được dữ liệu phản hồi từ trang web.');
      }

      var document = html_parser.parse(htmlContent);
      int currentChapNum = chapterNumber ?? _detectChapterNumber(normalizedUrl, document);
      String actualUrl = normalizedUrl;

      // Tự động nhận diện nếu URL trả về trang thông tin/mục lục truyện thay vì chương đọc
      final redirectChapterUrl = _findActualChapterUrlFromDoc(document, normalizedUrl, currentChapNum);
      if (redirectChapterUrl != null && redirectChapterUrl != normalizedUrl) {
        try {
          final redirectHtml = await fetchUrlContent(redirectChapterUrl);
          if (redirectHtml.trim().isNotEmpty) {
            htmlContent = redirectHtml;
            document = html_parser.parse(redirectHtml);
            actualUrl = redirectChapterUrl;
            currentChapNum = chapterNumber ?? _detectChapterNumber(redirectChapterUrl, document);
          }
        } catch (_) {}
      }

      // Trích xuất Tên truyện & Tên chương
      String storyTitle = _extractStoryTitle(document, actualUrl);
      String chapterTitle = _extractChapterTitle(document, currentChapNum);

      // Trích xuất nội dung truyện thuần túy
      String content = _extractPureStoryContent(
        document: document,
        htmlRaw: htmlContent,
        storyTitle: storyTitle,
        chapterTitle: chapterTitle,
        chapterNumber: currentChapNum,
      );

      if (content.trim().isEmpty) {
        throw Exception('Không tìm thấy nội dung văn bản trong trang.');
      }

      int wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      return ChapterModel(
        id: '${Uri.parse(actualUrl).host}_$currentChapNum',
        storyTitle: storyTitle,
        chapterTitle: chapterTitle,
        chapterNumber: currentChapNum,
        sourceUrl: actualUrl,
        content: content,
        wordCount: wordCount,
      );
    } catch (e) {
      throw Exception('Crawl thất bại [Chương ${chapterNumber ?? '?'}]: ${e.toString()}');
    }
  }

  /// Xử lý crawl riêng biệt cho nguồn Truyện Dịch Miễn Phí (truyendichmienphi.com)
  Future<ChapterModel> _crawlTruyenDichMienPhi(String url, {int? chapterNumber}) async {
    final parsed = parseUrlAndChapter(url);
    final chapNum = chapterNumber ?? parsed['chapter'] ?? 1;

    // Trích xuất slug truyện từ URL: /truyen/{slug}/chuong/{chapNum}
    final slugMatch = RegExp(r'/truyen/([^/]+)', caseSensitive: false).firstMatch(url);
    final slug = slugMatch != null ? slugMatch.group(1)! : '';

    String storyTitle = 'Quỷ Bí Chi Chủ';
    String chapterTitle = 'Chương $chapNum';
    String content = '';

    // 1. Lấy thông tin Tên truyện từ API TDMP
    if (slug.isNotEmpty) {
      try {
        final novelJsonStr = await fetchUrlContent('https://api.truyendichmienphi.com/api/novels/$slug');
        final novelData = jsonDecode(novelJsonStr);
        if (novelData['title'] != null && novelData['title'].toString().trim().isNotEmpty) {
          storyTitle = novelData['title'].toString().trim();
        }
      } catch (_) {}

      // 2. Lấy tên chương chính xác từ danh sách chương của TDMP
      try {
        final chapJsonStr = await fetchUrlContent(
          'https://api.truyendichmienphi.com/api/novels/$slug/chapters?limit=1&page=1&chapter_number_eq=$chapNum&sortBy=chapter_number:asc',
        );
        final chapData = jsonDecode(chapJsonStr);
        final results = chapData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results[0];
          if (first['title'] != null && first['title'].toString().trim().isNotEmpty) {
            chapterTitle = 'Chương $chapNum: ${first['title'].toString().trim()}';
          }
        }
      } catch (_) {}
    }

    // 3. Fallback tìm kiếm nội dung từ các nguồn mở dự phòng
    content = await _fallbackFetchChapterContent(
      storyTitle: storyTitle,
      slug: slug,
      chapterNumber: chapNum,
    );

    if (content.trim().isEmpty) {
      throw Exception('Chương $chapNum của "$storyTitle" hiện đang bị giới hạn trên TDMP và chưa có nguồn dự phòng.');
    }

    int wordCount = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return ChapterModel(
      id: 'truyendichmienphi_${slug}_$chapNum',
      storyTitle: storyTitle,
      chapterTitle: chapterTitle,
      chapterNumber: chapNum,
      sourceUrl: url,
      content: content,
      wordCount: wordCount,
    );
  }

  /// Tìm kiếm và tải nội dung chương từ các nguồn mở dự phòng chất lượng cao
  Future<String> _fallbackFetchChapterContent({
    required String storyTitle,
    required String slug,
    required int chapterNumber,
  }) async {
    final candidateUrls = [
      'https://webnovel.vn/$slug/chuong-$chapterNumber/',
      'https://xtruyen.vn/truyen/$slug/chuong-$chapterNumber',
      'https://truyenfull.live/$slug/chuong-$chapterNumber/',
      'https://dtruyen.com/$slug/chuong-$chapterNumber/',
    ];

    for (var candUrl in candidateUrls) {
      try {
        final html = await fetchUrlContent(candUrl);
        if (html.length > 500 &&
            !html.contains('404 Not Found') &&
            !html.contains('Attention Required! | Cloudflare') &&
            !html.contains('Sorry, you have been blocked')) {
          final doc = html_parser.parse(html);
          final pure = _extractPureStoryContent(
            document: doc,
            htmlRaw: html,
            storyTitle: storyTitle,
            chapterTitle: 'Chương $chapterNumber',
            chapterNumber: chapterNumber,
          );
          if (pure.trim().length > 100) {
            return pure;
          }
        }
      } catch (_) {}
    }
    return '';
  }

  int _detectChapterNumber(String url, dom.Document document) {
    final parsed = parseUrlAndChapter(url);
    if (parsed['chapter'] != null) return parsed['chapter'];

    final chapTitle = _extractChapterTitle(document, 1);
    final match = RegExp(r'\d+').firstMatch(chapTitle);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 1;
    }
    return 1;
  }

  /// Trích xuất tiêu đề truyện
  String _extractStoryTitle(dom.Document document, String url) {
    // 1. Selector ưu tiên của các giao diện đọc truyện phổ biến
    final selectors = [
      '.reader__title a',
      '.reader__title',
      'h1.reader__title',
      '.truyen-title a',
      '.truyen-title',
      'a.truyen-title',
      '.book-title a',
      '.book-title',
      '.story-title',
      'h1.title',
      'h1.name',
    ];

    for (var sel in selectors) {
      try {
        final el = document.querySelector(sel);
        if (el != null && el.text.trim().isNotEmpty) {
          final txt = el.text.trim();
          if (!txt.toLowerCase().startsWith('chương') && !txt.toLowerCase().startsWith('chap')) {
            return txt;
          }
        }
      } catch (_) {}
    }

    // 2. Kiểm tra các thẻ h1 trong trang
    try {
      final h1List = document.querySelectorAll('h1');
      for (var h1 in h1List) {
        final txt = h1.text.trim();
        if (txt.isNotEmpty &&
            !txt.toLowerCase().startsWith('chương') &&
            !txt.toLowerCase().startsWith('chap') &&
            !txt.toLowerCase().startsWith('hồi')) {
          return txt;
        }
      }
    } catch (_) {}

    // 3. Kiểm tra các link dẫn về trang thông tin truyện (a[href*="/truyen/"])
    try {
      final truyenLinks = document.querySelectorAll('a[href*="/truyen/"]');
      for (var link in truyenLinks) {
        final href = link.attributes['href'] ?? '';
        // Bỏ qua link chương (/chuong-...)
        if (!href.contains('/chuong-') && !href.contains('/chuong/')) {
          final txt = link.text.trim();
          if (txt.isNotEmpty &&
              !txt.toLowerCase().contains('trước') &&
              !txt.toLowerCase().contains('sau') &&
              !txt.toLowerCase().contains('mục lục') &&
              !txt.toLowerCase().startsWith('chương') &&
              !txt.toLowerCase().startsWith('chap')) {
            return txt;
          }
        }
      }
    } catch (_) {}

    // 4. Kiểm tra breadcrumbs
    try {
      final breadcrumbLinks = document.querySelectorAll('.breadcrumb a, nav.breadcrumb a, .breadcrumbs a, ol.breadcrumb a, ul.breadcrumb a');
      for (var i = 1; i < breadcrumbLinks.length; i++) {
        final txt = breadcrumbLinks[i].text.trim();
        if (txt.isNotEmpty &&
            !txt.toLowerCase().contains('trang chủ') &&
            !txt.toLowerCase().contains('home') &&
            !txt.toLowerCase().startsWith('chương') &&
            !txt.toLowerCase().startsWith('chap')) {
          return txt;
        }
      }
    } catch (_) {}

    // 5. Phân tích og:title hoặc title
    String rawTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        document.querySelector('title')?.text.trim() ??
        '';

    if (rawTitle.isNotEmpty) {
      // Loại bỏ tên website sau dấu |
      final cleanSite = rawTitle.split('|').first.trim();
      final parts = cleanSite.split(RegExp(r'\s+[-–—]\s+'));
      if (parts.length >= 2) {
        // Dạng 1: "Chương 25 - Tiên Nghịch" -> Lấy "Tiên Nghịch"
        if (parts.first.toLowerCase().contains('chương') || parts.first.toLowerCase().contains('chap')) {
          return parts.last.trim();
        }
        // Dạng 2: "Tiên Nghịch - Chương 25" -> Lấy "Tiên Nghịch"
        if (parts.last.toLowerCase().contains('chương') || parts.last.toLowerCase().contains('chap')) {
          return parts.first.trim();
        }
        return parts.first.trim();
      }
      return cleanSite.split('-').first.trim();
    }

    return 'Truyện chữ';
  }

  /// Trích xuất tên chương
  String _extractChapterTitle(dom.Document document, int chapterNumber) {
    final selectors = [
      '.reader__chapter',
      'p.reader__chapter',
      '.chapter-title',
      'h2.chapter-title',
      'h1.chapter-title',
      '.chapter-text',
      '.chapter-name',
      '.tit-chapter',
      'h2',
      'h1',
    ];

    for (var sel in selectors) {
      final elements = document.querySelectorAll(sel);
      for (var el in elements) {
        final txt = el.text.trim();
        if (txt.toLowerCase().contains('chương') || txt.toLowerCase().contains('chap')) {
          return txt;
        }
      }
    }

    return 'Chương $chapterNumber';
  }

  /// Giải mã nội dung bị mã hóa (Ví dụ xtruyen.vn / Madara theme dùng data_x + zlib deflate)
  String? _tryDecryptDataX(String html) {
    final match = RegExp(r'data_x\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(html);
    if (match == null) return null;
    try {
      final dataX = match.group(1)!;
      const c = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_';
      const s = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

      final buffer = StringBuffer();
      for (var i = 0; i < dataX.length; i++) {
        final char = dataX[i];
        final idx = c.indexOf(char);
        if (idx != -1) {
          buffer.write(s[idx]);
        } else {
          buffer.write(char);
        }
      }
      final compressedBytes = base64.decode(buffer.toString());
      final decompressedBytes = zlib.decode(compressedBytes);
      return utf8.decode(decompressedBytes);
    } catch (e) {
      return null;
    }
  }

  /// Trích xuất CHỈ NỘI DUNG TRUYỆN - Lọc sạch mọi thông tin rác, menu cài đặt đọc, tiêu đề chương, tác giả, quảng cáo
  String _extractPureStoryContent({
    required dom.Document document,
    required String htmlRaw,
    required String storyTitle,
    required String chapterTitle,
    required int chapterNumber,
  }) {
    // 1. Kiểm tra nếu có dữ liệu nén data_x (như xtruyen.vn)
    final decrypted = _tryDecryptDataX(htmlRaw);
    if (decrypted != null && decrypted.trim().isNotEmpty) {
      final cleanContent = _cleanStoryLines(
        rawContent: decrypted,
        storyTitle: storyTitle,
        chapterTitle: chapterTitle,
        chapterNumber: chapterNumber,
      );
      return '$chapterTitle\n\n$cleanContent';
    }

    // 2. Các selector chứa nội dung chương chính xác theo thứ tự ưu tiên
    final contentSelectors = [
      '#chapter-reading-content',
      '#reading-content',
      '.reading-content',
      '#chapter-c',
      '#chapter-content',
      '#chap-content',
      '.chapter-c',
      '.chapter-content',
      '.reading-detail',
      '.box-chap',
      '#vungdoc',
      '.content-box',
      '.doc-truyen',
      'div#content',
      '.entry-content',
      '#article-content',
      'article',
    ];

    dom.Element? contentContainer;
    for (var sel in contentSelectors) {
      final el = document.querySelector(sel);
      if (el != null && el.text.trim().length > 100) {
        contentContainer = el;
        break;
      }
    }

    // Fallback: Tìm thẻ có lượng text dài nhất
    if (contentContainer == null) {
      int maxLen = 0;
      for (var div in document.querySelectorAll('div, section, article')) {
        int len = div.text.trim().length;
        if (len > maxLen && len > 200) {
          maxLen = len;
          contentContainer = div;
        }
      }
    }

    if (contentContainer == null) return '';

    // 3. Xóa triệt để các thành phần giao diện, cài đặt đọc, menu, quảng cáo, popups
    final removeSelectors = [
      'script',
      'style',
      'iframe',
      'noscript',
      'svg',
      'canvas',
      'header',
      'footer',
      'nav',
      'aside',
      // Reader settings & controls
      '.reading-control',
      '.box-setting',
      '.control-read',
      '.selectpicker_chapter',
      '.chapters_selectbox_holder',
      '.c-selectpicker',
      '.entry-header',
      '#manga-reading-nav-head',
      '#manga-reading-nav-foot',
      '.xtruyen-bell-content',
      '.xtruyen-popup-content',
      '.modal',
      '.modal-content',
      '#chapter_comment_ajax',
      '.native-stories',
      '#fcm-notification-popup',
      '#fcm-guide-modal',
      '.word-count-container',
      '.reader__actions',
      '.flag-btn',
      '.appmobile',
      '#reportBox',
      '#voteBox',
      '#donateBox',
      '#readerDrawer',
      // Ads & Popups & Unlocks & Hidden SEO
      '#ads_click_view_chapter',
      '#ads-unlock-reminder',
      '.ads-unlock-container',
      '.ads-unlock-reminder',
      '.ads-unlock-text',
      '.ads-reminder-text',
      '#ads-chapter-top',
      '#ads-chapter-bottom',
      '.ads-chapter-bottom-lien-quan',
      '.ads-lien-quan',
      '.ads-taboola-truyen',
      '#ads-detail-truyen-main-middle',
      '#ads-detail-truyen-main-middle-new',
      '.text-link-bottom',
      'a.text_link_an',
      '#ads-head',
      '#ads-install-app',
      '#ads-xuyentrang-bottom',
      '#catfish-bottom-sp',
      '.ads',
      '.ads-holder',
      '.adv',
      '.ad-box',
      '.banner',
      'ins',
      '.adsbygoogle',
      'button',
      'a.btn',
      '.pagination',
      '.chapter-nav',
      '.navigation',
      '.story-info',
      '.chapter-info',
      '.breadcrumb',
      '.info',
      '.author',
      '.source',
      '.translator',
      '.rating',
      '.comment',
      '.social-share',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      '.alert',
      '.notice',
      '.note',
      '.warning',
      '.disclaimer',
    ];

    for (var sel in removeSelectors) {
      contentContainer.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // Xóa tất cả các phần tử có style ẩn (display:none, visibility:hidden, height:0, color:transparent...)
    final allChildren = contentContainer.querySelectorAll('*');
    for (var child in allChildren) {
      final style = child.attributes['style']?.toLowerCase() ?? '';
      if (style.contains('display:none') ||
          style.contains('display: none') ||
          style.contains('visibility:hidden') ||
          style.contains('visibility: hidden') ||
          style.contains('height:0') ||
          style.contains('height: 0') ||
          style.contains('font-size:0') ||
          style.contains('font-size: 0') ||
          style.contains('font-size: 1px') ||
          style.contains('font-size: 2px') ||
          style.contains('font-size: 5px') ||
          style.contains('color: transparent') ||
          style.contains('color:transparent')) {
        child.remove();
      }
    }

    // Thay thế các thẻ ngắt dòng <br>, <p>, <div> thành ký tự xuống dòng
    for (var br in contentContainer.querySelectorAll('br')) {
      br.replaceWith(dom.Text('\n'));
    }
    for (var p in contentContainer.querySelectorAll('p')) {
      p.append(dom.Text('\n\n'));
    }
    for (var div in contentContainer.querySelectorAll('div')) {
      div.append(dom.Text('\n'));
    }

    final cleanContent = _cleanStoryLines(
      rawContent: contentContainer.text,
      storyTitle: storyTitle,
      chapterTitle: chapterTitle,
      chapterNumber: chapterNumber,
    );

    return '$chapterTitle\n\n$cleanContent';
  }

  /// Lọc từng dòng văn bản - Đảm bảo chỉ giữ lại đúng từng câu văn chương hồi của truyện
  String _cleanStoryLines({
    required String rawContent,
    required String storyTitle,
    required String chapterTitle,
    required int chapterNumber,
  }) {
    String textToClean;

    // Nếu chứa HTML tags, làm sạch qua parseFragment
    if (rawContent.contains('<') && rawContent.contains('>')) {
      final fragment = html_parser.parseFragment(rawContent);

      final removeSelectors = [
        'script', 'style', 'iframe', 'noscript',
        'header', 'footer', 'nav', 'aside',
        '.ads', '.adv', '.native-stories', '.reading-control',
        '#ads_click_view_chapter', '#ads-unlock-reminder',
        'button', 'a.btn', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      ];
      for (var sel in removeSelectors) {
        fragment.querySelectorAll(sel).forEach((e) => e.remove());
      }

      for (var br in fragment.querySelectorAll('br')) {
        br.replaceWith(dom.Text('\n'));
      }
      for (var p in fragment.querySelectorAll('p')) {
        p.append(dom.Text('\n\n'));
      }
      for (var div in fragment.querySelectorAll('div')) {
        div.append(dom.Text('\n'));
      }
      textToClean = fragment.text ?? '';
    } else {
      textToClean = rawContent;
    }

    final lines = textToClean.split('\n');
    final List<String> cleanParagraphs = [];

    final titleLower = storyTitle.toLowerCase().trim();
    final chapTitleLower = chapterTitle.toLowerCase().trim();

    final metadataRegex = RegExp(
      r'^(tác giả|dịch giả|người dịch|nguồn|converter|biên tập|thể loại|trạng thái|tình trạng|đăng bởi|biên soạn|nguồn convert|nhóm dịch|post by|reup by|truyện|chương|chap|chapter|hồi|tiết|quyển)\s*[:：\-]',
      caseSensitive: false,
    );

    final chapterHeaderRegex = RegExp(
      r'^(chương|hồi|chap|chapter|tiết|quyển|hồi thứ)\s*\d+.*$',
      caseSensitive: false,
    );

    final separatorRegex = RegExp(r'^[\-=_~*oO0\.\s]{3,}$');

    final spamPhrases = [
      'bạn đang đọc',
      'chúc bạn đọc truyện',
      'đọc truyện online',
      'tìm kiếm truyện',
      'cập nhật nhanh nhất',
      'truyện được dịch',
      'ủng hộ tác giả',
      'ủng hộ dịch giả',
      'like và share',
      'theo dõi fanpage',
      'tham gia group',
      'mọi người nhớ like',
      'đừng quên đánh giá',
      'bình chọn cho truyện',
      'tải app để đọc',
      'momo:',
      'stk:',
      'donate',
      'truyen full',
      'truyenfull',
      'truyenfullvn',
      'truyenfulllive',
      'truyenfull.vn',
      'truyenfull.live',
      'truyenfull.io',
      'xtruyen',
      'tangthuvien',
      'bachngocsach',
      'dtruyen',
      'metruyenchu',
      'truyenyy',
      'sstruyen',
      'vlogtruyen',
      'truyenplus',
      'nguontruyen',
      'reup',
      'facebook.com',
      'zalo.me',
      't.me/',
      'discord.gg',
      'hãy ủng hộ',
      'mở app',
      'click ads',
      'mở khóa toàn bộ',
      'nội dung chương đang bị khóa',
      'mở lại quảng cáo',
      'để tiếp tục ủng hộ dịch giả',
      'báo lỗi chương',
      'bình luận chương',
      'bình luận truyện',
      'phím mũi tên hoặc wasd',
      'dịch giả:',
      'người dịch:',
      'converter:',
      'diệp công thích rồng',
      // Reader UI terms
      'màu nền',
      'xám nhạt',
      'xanh nhạt',
      'vàng nhạt',
      'màu sepia',
      'xanh đậm',
      'vàng đậm',
      'vàng ố',
      'màu trắng',
      'font chữ',
      'cỡ chữ',
      'chiều cao dòng',
      'chọn chương',
      'đang tải hướng dẫn',
      'nhận thông báo chương mới',
      'webnovel',
      'tuyển tập truyện chọn lọc',
      'top truyện full',
      'list truyện tiên hiệp',
      'tuyển tập truyện ngôn tình',
      'top truyện xuyên không',
    ];

    for (var rawLine in lines) {
      String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (separatorRegex.hasMatch(line)) continue;

      String lineLower = line.toLowerCase();
      if (lineLower == titleLower || lineLower == chapTitleLower) continue;
      if (lineLower == 'chương $chapterNumber' || lineLower == 'chap $chapterNumber') continue;
      if (chapterHeaderRegex.hasMatch(line)) continue;
      if (metadataRegex.hasMatch(line)) continue;

      bool isSpam = false;
      for (var phrase in spamPhrases) {
        if (lineLower.contains(phrase)) {
          isSpam = true;
          break;
        }
      }
      if (isSpam) continue;

      // Loại bỏ dòng quá ngắn chỉ gồm số hoặc ký tự đặc biệt
      if (line.length < 3 && !RegExp(r'[a-zA-ZÀ-ỹ]').hasMatch(line)) continue;

      // Chuẩn hóa ký tự đặc biệt né kiểm duyệt và từ ngữ TTS
      line = TextNormalizer.normalize(line);

      cleanParagraphs.add(line);
    }

    return cleanParagraphs.join('\n\n');
  }
}

