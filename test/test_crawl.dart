import '../lib/services/crawler_service.dart';

void main() async {
  final crawler = CrawlerService();

  print('=============================================');
  print('TEST 1: Crawl truyendichmienphi.com');
  final tdmpUrl = 'https://truyendichmienphi.com/truyen/quy-bi-chi-chu/chuong/1';
  try {
    final chapter = await crawler.crawlChapterFromUrl(tdmpUrl);
    print('SUCCESS TDMP!');
    print('  ID: ${chapter.id}');
    print('  Story: ${chapter.storyTitle}');
    print('  Chapter: ${chapter.chapterTitle}');
    print('  Word count: ${chapter.wordCount}');
    print('  Paragraphs count: ${chapter.paragraphs.length}');
  } catch (e) {
    print('  TDMP Error: $e');
  }

  print('=============================================');
  print('TEST 2: buildChapterUrl next chapter');
  final nextUrl = crawler.buildChapterUrl(tdmpUrl, 2);
  print('Next URL: $nextUrl');
}
