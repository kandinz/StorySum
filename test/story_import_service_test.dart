import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:app_story/services/story_import_service.dart';

void main() {
  group('StoryImportService - TXT Import', () {
    final service = StoryImportService();

    test('Phân tích file TXT có tiêu đề chương rõ ràng', () {
      const txtContent = '''
Chương 1: Mở đầu cuộc phiêu lưu
Trời xanh mây trắng, nhân vật chính bắt đầu cuộc hành trình.
Cậu bước đi trên con đường làng quen thuộc.

Chương 2: Bí mật trong hang động
Đến trước cửa hang, cậu phát hiện một quyển bí kíp cổ xưa.
Những dòng chữ lấp lánh phát sáng trong đêm tối.

Chương 3: Kết thúc hành trình
Sau bao gian nan, cậu đã trở thành một bậc thầy vĩ đại.
''';

      final bytes = Uint8List.fromList(utf8.encode(txtContent));
      final result = service.importFromTxt(bytes, 'Tieu_Thuyet_Hay.txt');

      expect(result.storyTitle, 'Tieu Thuyet Hay');
      expect(result.chapters.length, 3);
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1: Mở đầu cuộc phiêu lưu');
      expect(result.chapters[0].content, contains('nhân vật chính bắt đầu cuộc hành trình'));
      expect(result.chapters[1].chapterNumber, 2);
      expect(result.chapters[1].chapterTitle, 'Chương 2: Bí mật trong hang động');
      expect(result.chapters[2].chapterNumber, 3);
      expect(result.chapters[2].chapterTitle, 'Chương 3: Kết thúc hành trình');
    });

    test('Phân tích file TXT tiếng Trung dạng số 3 chữ số và tên file chứa thông tin tác giả (VD: 001 下次再见...)', () {
      const chineseTxtContent = '''
恶魔疯缠：宝贝，今天又要杀我吗
Author: 时凌
Description:
　　• 当前来源：番茄
　　• 书籍主角：米迦勒,路西法

001 下次再见，吃干抹尽
　　“圣洁美丽的炽天使殿下，被关在黑暗的地狱中成为我身下的感觉如何？”
　　“米迦勒，既然不爱，那就恨吧。”

002 是蛇啊~
　　朦朦胧胧的莹光照进偌大的寝殿里面。
　　床上轻纱帐似弱风扶柳般的轻轻晃动着。
　　天使没有着衣睡觉的习惯。

003 事业脑路西法限时上线
　　地狱深处的大殿之上，恶魔之王正凝视着手中的权杖。
''';

      final bytes = Uint8List.fromList(utf8.encode(chineseTxtContent));
      final result = service.importFromTxt(
        bytes,
        '恶魔疯缠：宝贝，今天又要杀我吗 作者：时凌.txt',
        sourcePath: r'C:\Users\Gum\Downloads\恶魔疯缠：宝贝，今天又要杀我吗 作者：时凌.txt',
      );

      expect(result.storyTitle, '恶魔疯缠：宝贝，今天又要杀我吗');
      expect(result.chapters.length, 3);
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1: 下次再见，吃干抹尽');
      expect(result.chapters[0].content, contains('圣洁美丽的炽天使殿下'));
      expect(result.chapters[1].chapterNumber, 2);
      expect(result.chapters[1].chapterTitle, 'Chương 2: 是蛇啊~');
      expect(result.chapters[1].content, contains('天使没有着衣睡觉的习惯'));
      expect(result.chapters[2].chapterNumber, 3);
      expect(result.chapters[2].chapterTitle, 'Chương 3: 事业脑路西法限时上线');
    });

    test('Phân tích file TXT tiếng Trung có định dạng 第...章 và số chữ Hán', () {
      const chineseNumContent = '''
第一章 初入仙途
少年踏上修仙之路，天地灵气汇聚周身。

第十二章 突破筑基
雷劫降临，九天神雷滚滚而来。

第一百零五章 飞升仙界
金光万道，飞升仙界的通道终于打开。
''';

      final bytes = Uint8List.fromList(utf8.encode(chineseNumContent));
      final result = service.importFromTxt(bytes, '《修仙传奇》 [作者：忘语].txt');

      expect(result.storyTitle, '修仙传奇');
      expect(result.chapters.length, 3);
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1: 初入仙途');
      expect(result.chapters[1].chapterNumber, 12);
      expect(result.chapters[1].chapterTitle, 'Chương 12: 突破筑基');
      expect(result.chapters[2].chapterNumber, 105);
      expect(result.chapters[2].chapterTitle, 'Chương 105: 飞升仙界');
    });

    test('Làm sạch tên truyện và chuyển đổi số chữ Hán chính xác', () {
      expect(StoryImportService.cleanStoryTitle('恶魔疯缠：宝贝，今天又要杀我吗 作者：时凌.txt'), '恶魔疯缠：宝贝，今天又要杀我吗');
      expect(StoryImportService.cleanStoryTitle('[Full] Đấu La Đại Lục - Tác giả: Đường Gia Tam Thiếu.txt'), 'Đấu La Đại Lục');
      expect(StoryImportService.cleanStoryTitle('《Quỷ Bí Chi Chủ》 by Ái Tiềm Thủy Đích Ô Tặc.txt'), 'Quỷ Bí Chi Chủ');

      expect(StoryImportService.parseChapterNumber('1'), 1);
      expect(StoryImportService.parseChapterNumber('001'), 1);
      expect(StoryImportService.parseChapterNumber('一'), 1);
      expect(StoryImportService.parseChapterNumber('十二'), 12);
      expect(StoryImportService.parseChapterNumber('二十五'), 25);
      expect(StoryImportService.parseChapterNumber('一百零五'), 105);
      expect(StoryImportService.parseChapterNumber('一千二百三十四'), 1234);
    });

    test('Phân tích file TXT thực tế từ Downloads nếu có', () {
      final sampleFile = File(r'C:\Users\Gum\Downloads\恶魔疯缠：宝贝，今天又要杀我吗 作者：时凌.txt');
      if (sampleFile.existsSync()) {
        final bytes = sampleFile.readAsBytesSync();
        final result = service.importFromTxt(bytes, sampleFile.path, sourcePath: sampleFile.path);

        expect(result.storyTitle, '恶魔疯缠：宝贝，今天又要杀我吗');
        expect(result.chapters.length, 41);
        expect(result.chapters[0].chapterNumber, 1);
        expect(result.chapters[0].chapterTitle, 'Chương 1: 下次再见，吃干抹尽');
        expect(result.chapters[0].content.length, greaterThan(100));
        expect(result.chapters[1].chapterNumber, 2);
        expect(result.chapters[1].chapterTitle, 'Chương 2: 是蛇啊~');
        expect(result.chapters[1].content.length, greaterThan(100));
      }
    });
  });

  group('StoryImportService - EPUB Import', () {
    final service = StoryImportService();

    test('Phân tích cấu trúc file EPUB', () {
      final archive = Archive();

      // 1. container.xml
      const containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
      archive.addFile(ArchiveFile('META-INF/container.xml', containerXml.length, utf8.encode(containerXml)));

      // 2. content.opf
      const opfXml = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Bí Mật Không Gian</dc:title>
  </metadata>
  <manifest>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chap2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''';
      archive.addFile(ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)));

      // 3. chap1.xhtml
      const chap1Html = '''<?xml version="1.0" encoding="utf-8"?>
<html>
<head><title>Chương 1: Khởi đầu</title></head>
<body>
  <h1>Chương 1: Khởi đầu</h1>
  <p>Vào một ngày đẹp trời, cánh cổng không gian mở ra trước mắt mọi người. Cuộc sống bình yên đã hoàn toàn thay đổi.</p>
</body>
</html>''';
      archive.addFile(ArchiveFile('OEBPS/chap1.xhtml', chap1Html.length, utf8.encode(chap1Html)));

      // 4. chap2.xhtml
      const chap2Html = '''<?xml version="1.0" encoding="utf-8"?>
<html>
<head><title>Chương 2: Thế giới mới</title></head>
<body>
  <h1>Chương 2: Thế giới mới</h1>
  <p>Bước qua cánh cổng, một vùng đất trù phú và kỳ bí hiện ra trước mắt đoàn thám hiểm dũng cảm.</p>
</body>
</html>''';
      archive.addFile(ArchiveFile('OEBPS/chap2.xhtml', chap2Html.length, utf8.encode(chap2Html)));

      final zipBytes = ZipEncoder().encode(archive);
      final result = service.importFromEpub(Uint8List.fromList(zipBytes), 'test.epub');

      expect(result.storyTitle, 'Bí Mật Không Gian');
      expect(result.chapters.length, 2);
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1: Khởi đầu');
      expect(result.chapters[0].content, contains('cánh cổng không gian mở ra'));
      expect(result.chapters[1].chapterNumber, 2);
      expect(result.chapters[1].chapterTitle, 'Chương 2: Thế giới mới');
      expect(result.chapters[1].content, contains('đoàn thám hiểm dũng cảm'));
    });

    test('Bỏ qua trang Mục lục (TOC) trong file EPUB để Chương 1 là chương đầu tiên', () {
      final archive = Archive();

      // 1. container.xml
      const containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
      archive.addFile(ArchiveFile('META-INF/container.xml', containerXml.length, utf8.encode(containerXml)));

      // 2. content.opf có chứa toc item
      const opfXml = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Tiên Hiệp Truyền Kỳ</dc:title>
  </metadata>
  <manifest>
    <item id="toc" href="toc.xhtml" properties="nav" media-type="application/xhtml+xml"/>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chap2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="toc"/>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''';
      archive.addFile(ArchiveFile('OEBPS/content.opf', opfXml.length, utf8.encode(opfXml)));

      // 3. toc.xhtml (Trang mục lục)
      const tocHtml = '''<?xml version="1.0" encoding="utf-8"?>
<html>
<head><title>Mục Lục</title></head>
<body>
  <h1>Mục Lục</h1>
  <ul>
    <li><a href="chap1.xhtml">Chương 1: Xuất sơn</a></li>
    <li><a href="chap2.xhtml">Chương 2: Đạp kiếm</a></li>
  </ul>
</body>
</html>''';
      archive.addFile(ArchiveFile('OEBPS/toc.xhtml', tocHtml.length, utf8.encode(tocHtml)));

      // 4. chap1.xhtml
      const chap1Html = '''<?xml version="1.0" encoding="utf-8"?>
<html>
<head><title>Chương 1: Xuất sơn</title></head>
<body>
  <h1>Chương 1: Xuất sơn</h1>
  <p>Thiếu niên bước xuống núi, bắt đầu con đường tu tiên đầy gian khổ nhưng hào hùng.</p>
</body>
</html>''';
      archive.addFile(ArchiveFile('OEBPS/chap1.xhtml', chap1Html.length, utf8.encode(chap1Html)));

      // 5. chap2.xhtml
      const chap2Html = '''<?xml version="1.0" encoding="utf-8"?>
<html>
<head><title>Chương 2: Đạp kiếm</title></head>
<body>
  <h1>Chương 2: Đạp kiếm</h1>
  <p>Ngự kiếm phi hành ngàn dặm, vượt qua muôn trùng núi non hiểm trở.</p>
</body>
</html>''';
      archive.addFile(ArchiveFile('OEBPS/chap2.xhtml', chap2Html.length, utf8.encode(chap2Html)));

      final zipBytes = ZipEncoder().encode(archive);
      final result = service.importFromEpub(Uint8List.fromList(zipBytes), 'tien_hiep.epub');

      expect(result.storyTitle, 'Tiên Hiệp Truyền Kỳ');
      // Phải bỏ qua trang mục lục -> chỉ còn 2 chương thực sự
      expect(result.chapters.length, 2);
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1: Xuất sơn');
      expect(result.chapters[0].content, contains('Thiếu niên bước xuống núi'));
      expect(result.chapters[1].chapterNumber, 2);
      expect(result.chapters[1].chapterTitle, 'Chương 2: Đạp kiếm');
      expect(result.chapters[1].content, contains('Ngự kiếm phi hành'));
    });
  });

  group('Chapter Grouping Logic (Nhóm 100 chương)', () {
    int getGroupIndex(int chapterNumber) {
      if (chapterNumber <= 0) return 0;
      return (chapterNumber - 1) ~/ 100;
    }

    String getGroupLabel(int groupIndex) {
      final start = groupIndex * 100 + 1;
      final end = (groupIndex + 1) * 100;
      return 'Chương $start - $end';
    }

    test('Tính toán nhóm 100 chương chính xác', () {
      expect(getGroupIndex(1), 0);
      expect(getGroupLabel(0), 'Chương 1 - 100');

      expect(getGroupIndex(50), 0);
      expect(getGroupIndex(100), 0);

      expect(getGroupIndex(101), 1);
      expect(getGroupLabel(1), 'Chương 101 - 200');
      expect(getGroupIndex(200), 1);

      expect(getGroupIndex(201), 2);
      expect(getGroupLabel(2), 'Chương 201 - 300');

      expect(getGroupIndex(1542), 15);
      expect(getGroupLabel(15), 'Chương 1501 - 1600');
    });
  });
}
