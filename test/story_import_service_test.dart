import 'dart:convert';
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

    test('Phân tích file TXT không có tiêu đề chương (tự động phân đoạn theo từ)', () {
      // Tạo văn bản dài lặp lại để kiểm tra phân đoạn
      final paragraph = 'Đây là một đoạn văn bản dài miêu tả câu chuyện phiêu lưu hấp dẫn. ' * 50;
      final fullText = List.generate(30, (i) => 'Đoạn $i: $paragraph').join('\n\n');

      final bytes = Uint8List.fromList(utf8.encode(fullText));
      final result = service.importFromTxt(bytes, 'Truyen_Khong_Chia_Chuong.txt');

      expect(result.storyTitle, 'Truyen Khong Chia Chuong');
      expect(result.chapters.length, greaterThanOrEqualTo(2));
      expect(result.chapters[0].chapterNumber, 1);
      expect(result.chapters[0].chapterTitle, 'Chương 1');
      expect(result.chapters[1].chapterNumber, 2);
      expect(result.chapters[1].chapterTitle, 'Chương 2');
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
