import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_story/services/crawler_service.dart';

void main() {
  group('Crawler Integration Tests', () {
    final crawler = CrawlerService();

    test('Crawl truyendichmienphi.com chapter', () async {
      const tdmpUrl = 'https://truyendichmienphi.com/truyen/quy-bi-chi-chu/chuong/1';
      try {
        final chapter = await crawler.crawlChapterFromUrl(tdmpUrl).timeout(const Duration(seconds: 10));
        expect(chapter.storyTitle, isNotEmpty);
        expect(chapter.chapterTitle, isNotEmpty);
        expect(chapter.wordCount, greaterThan(50));
      } on SocketException catch (_) {
        // Bỏ qua nếu offline
      } catch (e) {
        if (e.toString().contains('Failed host lookup') || e.toString().contains('TimeoutException')) {
          return;
        }
        rethrow;
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Crawl mtruyen.net chapter', () async {
      const mtruyenUrl = 'https://mtruyen.net/truyen/tien-nghich/chuong-109';
      try {
        final chapter = await crawler.crawlChapterFromUrl(mtruyenUrl).timeout(const Duration(seconds: 10));
        expect(chapter.storyTitle, contains('Tiên Nghịch'));
        expect(chapter.chapterTitle, isNotEmpty);
        expect(chapter.wordCount, greaterThan(50));

        final nextUrl = crawler.buildChapterUrl(mtruyenUrl, 110);
        expect(nextUrl, equals('https://mtruyen.net/truyen/tien-nghich/chuong-110'));
        final nextChapter = await crawler.crawlChapterFromUrl(nextUrl).timeout(const Duration(seconds: 10));
        expect(nextChapter.storyTitle, contains('Tiên Nghịch'));
        expect(nextChapter.chapterNumber, equals(110));
        expect(nextChapter.wordCount, greaterThan(50));
      } on SocketException catch (_) {
        // Bỏ qua nếu offline
      } catch (e) {
        if (e.toString().contains('Failed host lookup') || e.toString().contains('TimeoutException')) {
          return;
        }
        rethrow;
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('Crawl truyenfull.live chapter', () async {
      const truyenfullUrl = 'https://truyenfull.live/quy-bi-chi-chu/quyen-1-chuong-1/';
      final chapter = await crawler.crawlChapterFromUrl(truyenfullUrl).timeout(const Duration(seconds: 15));
      print('Truyenfull story: ${chapter.storyTitle}');
      print('Truyenfull chapter: ${chapter.chapterTitle}');
      print('Truyenfull number: ${chapter.chapterNumber}');
      print('Truyenfull words: ${chapter.wordCount}');
      expect(chapter.storyTitle, isNotEmpty);
      expect(chapter.chapterNumber, equals(1));
      expect(chapter.wordCount, greaterThan(50));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
