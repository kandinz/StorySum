import 'package:flutter_test/flutter_test.dart';
import 'package:app_story/services/crawler_service.dart';

void main() {
  group('CrawlerService URL & Chapter Extraction Tests', () {
    final crawler = CrawlerService();

    test('Trích xuất số chương từ xtruyen.vn tiêu chuẩn', () {
      final url = 'https://xtruyen.vn/truyen/pham-nhan-tu-tien/chuong-1/';
      final chap = crawler.extractChapterNumberFromUrl(url);
      expect(chap, equals(1));

      final nextUrl = crawler.buildChapterUrl(url, 2);
      expect(nextUrl, equals('https://xtruyen.vn/truyen/pham-nhan-tu-tien/chuong-2/'));
    });

    test('Trích xuất số chương từ link không có gạch chéo cuối', () {
      final url = 'https://xtruyen.vn/truyen/tu-tien-ta-that-khong-co-muon-lam-liem-cho/chuong-178';
      final chap = crawler.extractChapterNumberFromUrl(url);
      expect(chap, equals(178));

      final nextUrl = crawler.buildChapterUrl(url, 179);
      expect(nextUrl, equals('https://xtruyen.vn/truyen/tu-tien-ta-that-khong-co-muon-lam-liem-cho/chuong-179'));
    });

    test('Trích xuất số chương từ link đuôi .html / .htm', () {
      final url = 'https://tangthuvien.vn/doc-truyen/pham-nhan-tu-tien/chuong-300.html';
      final chap = crawler.extractChapterNumberFromUrl(url);
      expect(chap, equals(300));

      final nextUrl = crawler.buildChapterUrl(url, 301);
      expect(nextUrl, equals('https://tangthuvien.vn/doc-truyen/pham-nhan-tu-tien/chuong-301.html'));
    });

    test('Trích xuất số chương từ dạng chap-, chapter-, c-, hoi-, tap-', () {
      expect(crawler.extractChapterNumberFromUrl('https://site.com/truyen/abc/chap-45'), equals(45));
      expect(crawler.extractChapterNumberFromUrl('https://site.com/truyen/abc/chapter-99.html'), equals(99));
      expect(crawler.extractChapterNumberFromUrl('https://site.com/truyen/abc/c123/'), equals(123));
      expect(crawler.extractChapterNumberFromUrl('https://site.com/truyen/abc/hoi-15'), equals(15));
      expect(crawler.extractChapterNumberFromUrl('https://site.com/truyen/abc/tap-5/'), equals(5));
    });

    test('Trích xuất số chương từ link có kèm tiêu đề phía sau', () {
      final url = 'https://site.com/truyen/abc/chuong-89-dai-chien-hoang-gia.html';
      expect(crawler.extractChapterNumberFromUrl(url), equals(89));

      final nextUrl = crawler.buildChapterUrl(url, 90);
      expect(nextUrl, equals('https://site.com/truyen/abc/chuong-90-dai-chien-hoang-gia.html'));
    });

    test('Trích xuất số chương từ Query Parameters (?chap=, ?chapter=, ?chuong=, ?c=)', () {
      final url1 = 'https://site.com/reader?story=abc&chap=45';
      expect(crawler.extractChapterNumberFromUrl(url1), equals(45));
      expect(crawler.buildChapterUrl(url1, 46), equals('https://site.com/reader?story=abc&chap=46'));

      final url2 = 'https://site.com/read?story_id=10&chapter=120';
      expect(crawler.extractChapterNumberFromUrl(url2), equals(120));
      expect(crawler.buildChapterUrl(url2, 121), equals('https://site.com/read?story_id=10&chapter=121'));
    });

    test('Trích xuất số chương từ số ở cuối URL', () {
      final url = 'https://novels.com/novel-name/123.html';
      expect(crawler.extractChapterNumberFromUrl(url), equals(123));
      expect(crawler.buildChapterUrl(url, 124), equals('https://novels.com/novel-name/124.html'));
    });

    test('Trích xuất và sinh URL cho webnovel.vn', () {
      final url1 = 'https://webnovel.vn/van-co-than-de/chuong-1/';
      expect(crawler.extractChapterNumberFromUrl(url1), equals(1));
      expect(crawler.buildChapterUrl(url1, 2), equals('https://webnovel.vn/van-co-than-de/chuong-2/'));

      final url2 = 'webnovel.vn/van-co-than-de/chuong-1/';
      expect(crawler.extractChapterNumberFromUrl(url2), equals(1));
      expect(crawler.buildChapterUrl(url2, 2), equals('https://webnovel.vn/van-co-than-de/chuong-2/'));

      final storyBaseUrl = 'https://webnovel.vn/van-co-than-de/';
      expect(crawler.buildChapterUrl(storyBaseUrl, 1), equals('https://webnovel.vn/van-co-than-de/chuong-1/'));
    });
  });
}
