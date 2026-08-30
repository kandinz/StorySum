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
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
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
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
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

  /// Xóa danh sách file audio trên đĩa
  static Future<void> deleteSentenceAudioFiles(Iterable<String?> paths) async {
    for (final path in paths) {
      if (path != null && path.trim().isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print('Lỗi xóa file audio câu ($path): $e');
        }
      }
    }
  }

  /// Xóa tất cả file audio thuộc về một voice cụ thể trong thư mục AppStory_Audios
  static Future<void> deleteVoiceAudioFiles(String voiceId) async {
    try {
      final dir = await getAudioStorageDirectory();
      if (!await dir.exists()) return;
      final safeVoice = voiceId.replaceAll(RegExp(r'[^\w-]'), '_');
      final targetPattern = '_$safeVoice';

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.contains(targetPattern)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('Lỗi xóa file audio của giọng $voiceId: $e');
    }
  }

  /// Xóa tất cả các file audio của giọng cũ đã tạo trước đó trong thư mục lưu trữ audio
  static Future<void> deleteOldVoiceAudioFiles({
    String? oldVoiceId,
    String? currentVoiceId,
  }) async {
    try {
      final dir = await getAudioStorageDirectory();
      if (!await dir.exists()) return;

      final safeOldVoice = (oldVoiceId != null && oldVoiceId.trim().isNotEmpty)
          ? oldVoiceId.replaceAll(RegExp(r'[^\w-]'), '_')
          : null;
      final safeCurrentVoice = (currentVoiceId != null && currentVoiceId.trim().isNotEmpty)
          ? currentVoiceId.replaceAll(RegExp(r'[^\w-]'), '_')
          : null;

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);

          bool shouldDelete = false;
          // 1. Nếu chỉ định rõ oldVoiceId và file chứa tag của oldVoice
          if (safeOldVoice != null && name.contains('_$safeOldVoice')) {
            shouldDelete = true;
          }
          // 2. Nếu là file audio câu (có định dạng _C..._S...) mà không phải thuộc giọng hiện tại
          else if (safeCurrentVoice != null) {
            final isSentenceFile = name.contains(RegExp(r'_C\d+_(?:TomTat|NoiDung)_S\d+'));
            if (isSentenceFile && !name.contains('_$safeCurrentVoice')) {
              shouldDelete = true;
            }
          }

          if (shouldDelete) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('Lỗi quét xóa audio giọng cũ: $e');
    }
  }

  /// Xóa tất cả các file audio thuộc một chương cụ thể
  static Future<void> deleteChapterAudioFiles({
    required String storyTitle,
    required int chapterNumber,
  }) async {
    try {
      final dir = await getAudioStorageDirectory();
      if (!await dir.exists()) return;
      String safeStory = storyTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .trim();
      if (safeStory.isEmpty) safeStory = 'Truyen';
      final prefix = '${safeStory}_C${chapterNumber}_';
      final oldPrefix = '${safeStory}_Chuong_${chapterNumber}_';

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith(prefix) || name.startsWith(oldPrefix)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('Lỗi xóa audio chương: $e');
    }
  }

  /// Xóa tất cả các file audio thuộc một truyện cụ thể
  static Future<void> deleteStoryAudioFiles(String storyTitle) async {
    try {
      final dir = await getAudioStorageDirectory();
      if (!await dir.exists()) return;
      String safeStory = storyTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .trim();
      if (safeStory.isEmpty) safeStory = 'Truyen';
      final prefix = '${safeStory}_';

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith(prefix)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('Lỗi xóa audio truyện: $e');
    }
  }

  /// Xóa toàn bộ file audio trong thư mục AppStory_Audios
  static Future<void> deleteAllAudios() async {
    try {
      final dir = await getAudioStorageDirectory();
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('Lỗi xóa toàn bộ audio: $e');
    }
  }
}
