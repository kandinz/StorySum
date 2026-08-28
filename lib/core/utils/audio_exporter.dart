import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class AudioExporter {
  /// Lấy thư mục lưu trữ audio cục bộ của App
  static Future<Directory> getAudioStorageDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(appDocDir.path, 'AppStory_Audios'));
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  /// Tạo đường dẫn file audio mới với phân biệt rõ loại Audio (Tóm tắt vs Nội dung)
  static Future<String> generateAudioFilePath({
    required String storyTitle,
    required int chapterNumber,
    String type = 'summary', // 'summary' | 'content'
    String extension = 'mp3',
  }) async {
    final dir = await getAudioStorageDirectory();
    // Chuẩn hóa tên file an toàn cho hệ điều hành
    String safeStory = storyTitle
        .replaceAll(RegExp(r'[^\w\s\u00C0-\u1EF9-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (safeStory.isEmpty) safeStory = 'Truyen';
    
    final typeTag = type == 'content' ? 'NoiDung' : 'TomTat';
    final fileName = '${safeStory}_Chuong_${chapterNumber}_${typeTag}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    return p.join(dir.path, fileName);
  }

  /// Tạo đường dẫn file audio xác định cho từng câu (hỗ trợ cache và tái sử dụng chuẩn xác theo nội dung câu & giọng đọc)
  static Future<String> generateSentenceAudioFilePath({
    required String storyTitle,
    required int chapterNumber,
    required String type, // 'summary' | 'content'
    required int sentenceIndex,
    String? sentenceText,
    String? voiceId,
    String extension = 'mp3',
  }) async {
    final dir = await getAudioStorageDirectory();
    String safeStory = storyTitle
        .replaceAll(RegExp(r'[^\w\s\u00C0-\u1EF9-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (safeStory.isEmpty) safeStory = 'Truyen';

    final typeTag = type == 'content' ? 'NoiDung' : 'TomTat';
    String hashTag = '';
    if (sentenceText != null && sentenceText.trim().isNotEmpty) {
      final hash = sentenceText.trim().hashCode.abs().toRadixString(16);
      hashTag = '_$hash';
    }
    String voiceTag = '';
    if (voiceId != null && voiceId.trim().isNotEmpty) {
      final safeVoice = voiceId.replaceAll(RegExp(r'[^\w-]'), '_');
      voiceTag = '_$safeVoice';
    }
    final fileName = '${safeStory}_C${chapterNumber}_${typeTag}_S${sentenceIndex}${voiceTag}$hashTag.$extension';
    return p.join(dir.path, fileName);
  }



  /// Xuất file audio sang thư mục Downloads chung của thiết bị
  static Future<String?> exportToDownloads(String sourceFilePath) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) return null;

      // Yêu cầu quyền lưu trữ nếu cần
      if (Platform.isAndroid) {
        await Permission.storage.request();
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir != null) {
        final targetFileName = p.basename(sourceFilePath);
        final targetPath = p.join(downloadsDir.path, targetFileName);
        final targetFile = await sourceFile.copy(targetPath);
        return targetFile.path;
      }
    } catch (e) {
      print('Lỗi xuất file sang Downloads: $e');
    }
    return null;
  }

  /// Chia sẻ file Audio qua các ứng dụng khác
  static Future<void> shareAudioFile(String filePath, {String? title}) async {
    final file = File(filePath);
    if (await file.exists()) {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: title ?? 'Nghe audio truyện từ StorySum',
      );
    }
  }
}
