import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';
import '../../models/chapter_model.dart';
import '../../models/summary_model.dart';
import '../../models/saved_audio_item.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_story.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgradeDB,
      onOpen: _onOpenDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableChapters} (
        id TEXT PRIMARY KEY,
        story_title TEXT,
        chapter_title TEXT,
        chapter_number INTEGER,
        source_url TEXT,
        content TEXT,
        word_count INTEGER,
        created_at TEXT,
        last_played_sentence INTEGER DEFAULT 0,
        last_played_summary_index INTEGER DEFAULT 0,
        last_played_content_index INTEGER DEFAULT 0,
        last_played_source TEXT DEFAULT 'summary',
        last_played_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.tableSummaries} (
        id TEXT PRIMARY KEY,
        chapter_id TEXT,
        summary_text TEXT,
        bullet_points TEXT,
        model_used TEXT,
        processing_time_ms INTEGER,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.tableAudios} (
        id TEXT PRIMARY KEY,
        title TEXT,
        story_title TEXT,
        chapter_number INTEGER,
        audio_path TEXT,
        summary_text TEXT,
        duration_seconds INTEGER,
        file_size_bytes INTEGER,
        voice_used TEXT,
        created_at TEXT,
        last_played_sentence INTEGER DEFAULT 0,
        last_played_summary_index INTEGER DEFAULT 0,
        last_played_content_index INTEGER DEFAULT 0,
        last_played_source TEXT DEFAULT 'summary',
        last_played_at TEXT
      )
    ''');
  }

  Future _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    await _ensureColumnsExist(db);
  }

  Future _onOpenDB(Database db) async {
    await _ensureColumnsExist(db);
  }

  Future<void> _ensureColumnsExist(Database db) async {
    final tables = [AppConstants.tableChapters, AppConstants.tableAudios];
    for (final table in tables) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN last_played_sentence INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN last_played_summary_index INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN last_played_content_index INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE $table ADD COLUMN last_played_source TEXT DEFAULT 'summary'");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN last_played_at TEXT');
      } catch (_) {}
    }
  }

  // ==========================================
  // Chapter Operations (Tự động ghi đè bản cũ trùng truyện & số chương)
  // ==========================================
  Future<int> insertChapter(ChapterModel chapter) async {
    final db = await database;
    
    // Giữ lại vị trí câu cuối nếu đã có trước đó
    final existing = await getChapterByStoryAndNumber(chapter.storyTitle, chapter.chapterNumber);
    final toSave = existing != null
        ? chapter.copyWith(
            lastPlayedSentenceIndex: chapter.lastPlayedAt != null ? chapter.lastPlayedSentenceIndex : (chapter.lastPlayedSentenceIndex > 0 ? chapter.lastPlayedSentenceIndex : existing.lastPlayedSentenceIndex),
            lastPlayedSummaryIndex: chapter.lastPlayedAt != null ? chapter.lastPlayedSummaryIndex : (chapter.lastPlayedSummaryIndex > 0 ? chapter.lastPlayedSummaryIndex : existing.lastPlayedSummaryIndex),
            lastPlayedContentIndex: chapter.lastPlayedAt != null ? chapter.lastPlayedContentIndex : (chapter.lastPlayedContentIndex > 0 ? chapter.lastPlayedContentIndex : existing.lastPlayedContentIndex),
            lastPlayedSource: chapter.lastPlayedAt != null ? chapter.lastPlayedSource : existing.lastPlayedSource,
            lastPlayedAt: chapter.lastPlayedAt ?? existing.lastPlayedAt,
          )
        : chapter;

    await db.delete(
      AppConstants.tableChapters,
      where: 'story_title = ? AND chapter_number = ?',
      whereArgs: [chapter.storyTitle, chapter.chapterNumber],
    );
    return await db.insert(
      AppConstants.tableChapters,
      toSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChapterModel?> getChapter(String id) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.tableChapters,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return ChapterModel.fromMap(maps.first);
    }
    return null;
  }

  Future<ChapterModel?> getChapterByStoryAndNumber(String storyTitle, int chapterNumber) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.tableChapters,
      where: 'story_title = ? AND chapter_number = ?',
      whereArgs: [storyTitle, chapterNumber],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return ChapterModel.fromMap(maps.first);
    }
    return null;
  }

  Future<List<ChapterModel>> getAllChapters() async {
    final db = await database;
    final result = await db.query(AppConstants.tableChapters, orderBy: 'created_at DESC');
    return result.map((json) => ChapterModel.fromMap(json)).toList();
  }

  Future<void> insertChaptersBatch(List<ChapterModel> chapters) async {
    if (chapters.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.delete(
        AppConstants.tableChapters,
        where: 'story_title = ? AND chapter_number = ?',
        whereArgs: [chapter.storyTitle, chapter.chapterNumber],
      );
      batch.insert(
        AppConstants.tableChapters,
        chapter.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChapterModel>> getChaptersByStory(String storyTitle) async {
    final db = await database;
    final result = await db.query(
      AppConstants.tableChapters,
      where: 'story_title = ?',
      whereArgs: [storyTitle],
      orderBy: 'chapter_number ASC',
    );
    return result.map((json) => ChapterModel.fromMap(json)).toList();
  }

  Future<int> deleteChapter(String id) async {
    final db = await database;
    return await db.delete(
      AppConstants.tableChapters,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // Summary Operations (Tự động ghi đè bản cũ trùng chapter_id)
  // ==========================================
  Future<int> insertSummary(SummaryModel summary) async {
    final db = await database;
    await db.delete(
      AppConstants.tableSummaries,
      where: 'chapter_id = ?',
      whereArgs: [summary.chapterId],
    );
    return await db.insert(
      AppConstants.tableSummaries,
      summary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SummaryModel?> getSummaryByChapterId(String chapterId) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.tableSummaries,
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );
    if (maps.isNotEmpty) {
      return SummaryModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> deleteSummary(String chapterId) async {
    final db = await database;
    return await db.delete(
      AppConstants.tableSummaries,
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );
  }

  // ==========================================
  // Audio Operations (Tự động ghi đè bản cũ trùng truyện & số chương)
  // ==========================================
  Future<int> insertAudio(SavedAudioItem audio) async {
    final db = await database;
    
    // Giữ lại vị trí câu cuối nếu đã có trước đó
    final existing = await getSavedAudioByStoryAndNumber(audio.storyTitle, audio.chapterNumber);
    final toSave = existing != null
        ? audio.copyWith(
            lastPlayedSentenceIndex: audio.lastPlayedAt != null ? audio.lastPlayedSentenceIndex : (audio.lastPlayedSentenceIndex > 0 ? audio.lastPlayedSentenceIndex : existing.lastPlayedSentenceIndex),
            lastPlayedSummaryIndex: audio.lastPlayedAt != null ? audio.lastPlayedSummaryIndex : (audio.lastPlayedSummaryIndex > 0 ? audio.lastPlayedSummaryIndex : existing.lastPlayedSummaryIndex),
            lastPlayedContentIndex: audio.lastPlayedAt != null ? audio.lastPlayedContentIndex : (audio.lastPlayedContentIndex > 0 ? audio.lastPlayedContentIndex : existing.lastPlayedContentIndex),
            lastPlayedSource: audio.lastPlayedAt != null ? audio.lastPlayedSource : existing.lastPlayedSource,
            lastPlayedAt: audio.lastPlayedAt ?? existing.lastPlayedAt,
          )
        : audio;

    await db.delete(
      AppConstants.tableAudios,
      where: 'story_title = ? AND chapter_number = ?',
      whereArgs: [audio.storyTitle, audio.chapterNumber],
    );

    return await db.insert(
      AppConstants.tableAudios,
      toSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAudiosBatch(List<SavedAudioItem> audios) async {
    if (audios.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final audio in audios) {
      batch.delete(
        AppConstants.tableAudios,
        where: 'story_title = ? AND chapter_number = ?',
        whereArgs: [audio.storyTitle, audio.chapterNumber],
      );
      batch.insert(
        AppConstants.tableAudios,
        audio.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SavedAudioItem>> getAllSavedAudios() async {
    final db = await database;
    final result = await db.query(AppConstants.tableAudios, orderBy: 'created_at DESC');
    final items = <SavedAudioItem>[];
    for (var json in result) {
      final storyTitle = json['story_title'] as String? ?? '';
      final chapterNumber = json['chapter_number'] is int
          ? json['chapter_number'] as int
          : int.tryParse(json['chapter_number']?.toString() ?? '0') ?? 0;

      final chapters = await db.query(
        AppConstants.tableChapters,
        where: "chapter_number = ? AND (story_title = ? OR ? = '')",
        whereArgs: [chapterNumber, storyTitle, storyTitle],
        limit: 1,
      );
      String? content;
      String? chapterId;
      String? actualChapterTitle;
      int lastPlayedSentence = json['last_played_sentence'] is int
          ? json['last_played_sentence'] as int
          : int.tryParse(json['last_played_sentence']?.toString() ?? '0') ?? 0;
      int lastSummaryIdx = json['last_played_summary_index'] is int
          ? json['last_played_summary_index'] as int
          : int.tryParse(json['last_played_summary_index']?.toString() ?? '') ?? 0;
      int lastContentIdx = json['last_played_content_index'] is int
          ? json['last_played_content_index'] as int
          : int.tryParse(json['last_played_content_index']?.toString() ?? '') ?? 0;

      String lastPlayedSource = json['last_played_source']?.toString() ?? 'summary';
      DateTime? lastPlayedAt = json['last_played_at'] != null
          ? DateTime.tryParse(json['last_played_at'].toString())
          : null;

      if (chapters.isNotEmpty) {
        content = chapters.first['content'] as String?;
        chapterId = chapters.first['id'] as String?;
        actualChapterTitle = chapters.first['chapter_title'] as String?;
        if (lastPlayedSentence == 0 && chapters.first['last_played_sentence'] != null) {
          lastPlayedSentence = chapters.first['last_played_sentence'] is int
              ? chapters.first['last_played_sentence'] as int
              : int.tryParse(chapters.first['last_played_sentence'].toString()) ?? 0;
        }
        if (lastSummaryIdx == 0 && chapters.first['last_played_summary_index'] != null) {
          lastSummaryIdx = chapters.first['last_played_summary_index'] is int
              ? chapters.first['last_played_summary_index'] as int
              : int.tryParse(chapters.first['last_played_summary_index'].toString()) ?? 0;
        }
        if (lastContentIdx == 0 && chapters.first['last_played_content_index'] != null) {
          lastContentIdx = chapters.first['last_played_content_index'] is int
              ? chapters.first['last_played_content_index'] as int
              : int.tryParse(chapters.first['last_played_content_index'].toString()) ?? 0;
        }
        if (chapters.first['last_played_source'] != null) {
          lastPlayedSource = chapters.first['last_played_source'].toString();
        }
        if (lastPlayedAt == null && chapters.first['last_played_at'] != null) {
          lastPlayedAt = DateTime.tryParse(chapters.first['last_played_at'].toString());
        }
      }
      var mapData = Map<String, dynamic>.from(json);
      if (actualChapterTitle != null && actualChapterTitle.isNotEmpty) {
        mapData['title'] = actualChapterTitle;
      }
      mapData['last_played_sentence'] = lastPlayedSentence;
      mapData['last_played_summary_index'] = lastSummaryIdx;
      mapData['last_played_content_index'] = lastContentIdx;
      mapData['last_played_source'] = lastPlayedSource;
      mapData['last_played_at'] = lastPlayedAt?.toIso8601String();

      items.add(SavedAudioItem.fromMap(mapData, content: content, chapterId: chapterId));
    }
    return items;
  }

  Future<SavedAudioItem?> getSavedAudioByStoryAndNumber(String storyTitle, int chapterNumber) async {
    final db = await database;
    final result = await db.query(
      AppConstants.tableAudios,
      where: "chapter_number = ? AND (story_title = ? OR ? = '')",
      whereArgs: [chapterNumber, storyTitle, storyTitle],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      final json = result.first;
      final st = json['story_title'] as String? ?? storyTitle;
      final chapters = await db.query(
        AppConstants.tableChapters,
        where: "chapter_number = ? AND (story_title = ? OR ? = '')",
        whereArgs: [chapterNumber, st, st],
        limit: 1,
      );
      String? content;
      String? chapterId;
      String? actualChapterTitle;
      int lastPlayedSentence = json['last_played_sentence'] is int
          ? json['last_played_sentence'] as int
          : int.tryParse(json['last_played_sentence']?.toString() ?? '0') ?? 0;
      int lastSummaryIdx = json['last_played_summary_index'] is int
          ? json['last_played_summary_index'] as int
          : int.tryParse(json['last_played_summary_index']?.toString() ?? '') ?? 0;
      int lastContentIdx = json['last_played_content_index'] is int
          ? json['last_played_content_index'] as int
          : int.tryParse(json['last_played_content_index']?.toString() ?? '') ?? 0;

      String lastPlayedSource = json['last_played_source']?.toString() ?? 'summary';
      DateTime? lastPlayedAt = json['last_played_at'] != null
          ? DateTime.tryParse(json['last_played_at'].toString())
          : null;

      if (chapters.isNotEmpty) {
        content = chapters.first['content'] as String?;
        chapterId = chapters.first['id'] as String?;
        actualChapterTitle = chapters.first['chapter_title'] as String?;
        if (lastPlayedSentence == 0 && chapters.first['last_played_sentence'] != null) {
          lastPlayedSentence = chapters.first['last_played_sentence'] is int
              ? chapters.first['last_played_sentence'] as int
              : int.tryParse(chapters.first['last_played_sentence'].toString()) ?? 0;
        }
        if (lastSummaryIdx == 0 && chapters.first['last_played_summary_index'] != null) {
          lastSummaryIdx = chapters.first['last_played_summary_index'] is int
              ? chapters.first['last_played_summary_index'] as int
              : int.tryParse(chapters.first['last_played_summary_index'].toString()) ?? 0;
        }
        if (lastContentIdx == 0 && chapters.first['last_played_content_index'] != null) {
          lastContentIdx = chapters.first['last_played_content_index'] is int
              ? chapters.first['last_played_content_index'] as int
              : int.tryParse(chapters.first['last_played_content_index'].toString()) ?? 0;
        }
        if (chapters.first['last_played_source'] != null) {
          lastPlayedSource = chapters.first['last_played_source'].toString();
        }
        if (lastPlayedAt == null && chapters.first['last_played_at'] != null) {
          lastPlayedAt = DateTime.tryParse(chapters.first['last_played_at'].toString());
        }
      }
      var mapData = Map<String, dynamic>.from(json);
      if (actualChapterTitle != null && actualChapterTitle.isNotEmpty) {
        mapData['title'] = actualChapterTitle;
      }
      mapData['last_played_sentence'] = lastPlayedSentence;
      mapData['last_played_summary_index'] = lastSummaryIdx;
      mapData['last_played_content_index'] = lastContentIdx;
      mapData['last_played_source'] = lastPlayedSource;
      mapData['last_played_at'] = lastPlayedAt?.toIso8601String();

      return SavedAudioItem.fromMap(mapData, content: content, chapterId: chapterId);
    }
    return null;
  }

  Future<SavedAudioItem?> getSavedAudioByNumber(int chapterNumber) async {
    final db = await database;
    final result = await db.query(
      AppConstants.tableAudios,
      where: 'chapter_number = ?',
      whereArgs: [chapterNumber],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (result.isNotEmpty) {
      final json = result.first;
      final st = json['story_title'] as String? ?? '';
      final chapters = await db.query(
        AppConstants.tableChapters,
        where: "chapter_number = ? AND (story_title = ? OR ? = '')",
        whereArgs: [chapterNumber, st, st],
        limit: 1,
      );
      String? content;
      String? chapterId;
      String? actualChapterTitle;
      int lastPlayedSentence = json['last_played_sentence'] is int
          ? json['last_played_sentence'] as int
          : int.tryParse(json['last_played_sentence']?.toString() ?? '0') ?? 0;
      int lastSummaryIdx = json['last_played_summary_index'] is int
          ? json['last_played_summary_index'] as int
          : int.tryParse(json['last_played_summary_index']?.toString() ?? '') ?? 0;
      int lastContentIdx = json['last_played_content_index'] is int
          ? json['last_played_content_index'] as int
          : int.tryParse(json['last_played_content_index']?.toString() ?? '') ?? 0;

      String lastPlayedSource = json['last_played_source']?.toString() ?? 'summary';
      DateTime? lastPlayedAt = json['last_played_at'] != null
          ? DateTime.tryParse(json['last_played_at'].toString())
          : null;

      if (chapters.isNotEmpty) {
        content = chapters.first['content'] as String?;
        chapterId = chapters.first['id'] as String?;
        actualChapterTitle = chapters.first['chapter_title'] as String?;
        if (lastPlayedSentence == 0 && chapters.first['last_played_sentence'] != null) {
          lastPlayedSentence = chapters.first['last_played_sentence'] is int
              ? chapters.first['last_played_sentence'] as int
              : int.tryParse(chapters.first['last_played_sentence'].toString()) ?? 0;
        }
        if (lastSummaryIdx == 0 && chapters.first['last_played_summary_index'] != null) {
          lastSummaryIdx = chapters.first['last_played_summary_index'] is int
              ? chapters.first['last_played_summary_index'] as int
              : int.tryParse(chapters.first['last_played_summary_index'].toString()) ?? 0;
        }
        if (lastContentIdx == 0 && chapters.first['last_played_content_index'] != null) {
          lastContentIdx = chapters.first['last_played_content_index'] is int
              ? chapters.first['last_played_content_index'] as int
              : int.tryParse(chapters.first['last_played_content_index'].toString()) ?? 0;
        }
        if (chapters.first['last_played_source'] != null) {
          lastPlayedSource = chapters.first['last_played_source'].toString();
        }
        if (lastPlayedAt == null && chapters.first['last_played_at'] != null) {
          lastPlayedAt = DateTime.tryParse(chapters.first['last_played_at'].toString());
        }
      }
      var mapData = Map<String, dynamic>.from(json);
      if (actualChapterTitle != null && actualChapterTitle.isNotEmpty) {
        mapData['title'] = actualChapterTitle;
      }
      mapData['last_played_sentence'] = lastPlayedSentence;
      mapData['last_played_summary_index'] = lastSummaryIdx;
      mapData['last_played_content_index'] = lastContentIdx;
      mapData['last_played_source'] = lastPlayedSource;
      mapData['last_played_at'] = lastPlayedAt?.toIso8601String();

      return SavedAudioItem.fromMap(mapData, content: content, chapterId: chapterId);
    }
    return null;
  }

  /// Cập nhật vị trí câu cuối đã phát cho một chương (lưu riêng cho tóm tắt & nội dung)
  Future<void> updateLastPlayedPosition({
    required String storyTitle,
    required int chapterNumber,
    required int sentenceIndex,
    required String sourceType,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    final Map<String, dynamic> updateData = {
      'last_played_sentence': sentenceIndex,
      'last_played_source': sourceType,
      'last_played_at': nowIso,
    };

    if (sourceType == 'summary') {
      updateData['last_played_summary_index'] = sentenceIndex;
    } else if (sourceType == 'content') {
      updateData['last_played_content_index'] = sentenceIndex;
    }

    await db.update(
      AppConstants.tableChapters,
      updateData,
      where: 'story_title = ? AND chapter_number = ?',
      whereArgs: [storyTitle, chapterNumber],
    );

    await db.update(
      AppConstants.tableAudios,
      updateData,
      where: 'story_title = ? AND chapter_number = ?',
      whereArgs: [storyTitle, chapterNumber],
    );
  }

  Future<int> deleteAudio(String id) async {
    final db = await database;
    return await db.delete(
      AppConstants.tableAudios,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete(AppConstants.tableAudios);
    await db.delete(AppConstants.tableSummaries);
    await db.delete(AppConstants.tableChapters);
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
