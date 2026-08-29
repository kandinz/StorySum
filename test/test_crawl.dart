import '../lib/services/crawler_service.dart';

void main() async {
  final crawler = CrawlerService();

  print('=============================================');
  print('TEST 1: Crawl truyendichmienphi.com');
  final tdmpUrl = 'https://truyendichmienphi.com/truyen/quy-bi-chi-chu/chuong/1';
  try {
    final chapter = await crawler.crawlChapterFromUrl(tdmpUrl);
    print('SUCCESS TDMP!');
    print('  Story: "${chapter.storyTitle}"');
    print('  Chapter: "${chapter.chapterTitle}"');
    print('  Word count: ${chapter.wordCount}');
  } catch (e) {
    print('  TDMP Error: $e');
  }

  print('=============================================');
  print('TEST 2: Crawl mtruyen.net');
  final mtruyenUrl = 'https://mtruyen.net/truyen/tien-nghich/chuong-25';
  try {
    final chapter = await crawler.crawlChapterFromUrl(mtruyenUrl);
    print('SUCCESS MTRUYEN!');
    print('  Story: "${chapter.storyTitle}"');
    print('  Chapter: "${chapter.chapterTitle}"');
    print('  Word count: ${chapter.wordCount}');
  } catch (e) {
    print('  MTRUYEN Error: $e');
  }
}
