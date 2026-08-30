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

    await db.execute('''
      CREATE TABLE ${AppConstants.tableBookmarks} (
        id TEXT PRIMARY KEY,
        story_title TEXT,
        chapter_number INTEGER,
        chapter_title TEXT,
        created_at TEXT,
        UNIQUE(story_title, chapter_number) ON CONFLICT REPLACE
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_bookmarks_story ON ${AppConstants.tableBookmarks}(story_title)');
    } catch (_) {}
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

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${AppConstants.tableBookmarks} (
          id TEXT PRIMARY KEY,
          story_title TEXT,
          chapter_number INTEGER,
          chapter_title TEXT,
          created_at TEXT,
          UNIQUE(story_title, chapter_number) ON CONFLICT REPLACE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_bookmarks_story ON ${AppConstants.tableBookmarks}(story_title)');
    } catch (_) {}
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

  /// Nạp nhanh danh sách ChapterModel nhẹ (bỏ qua cột content để tối ưu tốc độ)
  Future<List<ChapterModel>> getLightweightChapters() async {
    final db = await database;
    final result = await db.query(
      AppConstants.tableChapters,
      columns: [
        'id',
        'story_title',
        'chapter_title',
        'chapter_number',
        'source_url',
        'word_count',
        'created_at',
        'last_played_sentence',
        'last_played_summary_index',
        'last_played_content_index',
        'last_played_source',
        'last_played_at',
      ],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => ChapterModel.fromMap(json)).toList();
  }

  Future<void> insertChaptersBatch(
    List<ChapterModel> chapters, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (chapters.isEmpty) return;
    final db = await database;
    final storyTitle = chapters.first.storyTitle;
    await db.delete(
      AppConstants.tableChapters,
      where: 'story_title = ?',
      whereArgs: [storyTitle],
    );

    const chunkSize = 500;
    for (int i = 0; i < chapters.length; i += chunkSize) {
      final end = (i + chunkSize < chapters.length) ? i + chunkSize : chapters.length;
      final chunk = chapters.sublist(i, end);
      final batch = db.batch();
      for (final chapter in chunk) {
        batch.insert(
          AppConstants.tableChapters,
          chapter.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      onProgress?.call(end, chapters.length);
    }
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

  /// Nạp danh sách chương nhẹ cho một truyện cụ thể (không nạp cột content để tối ưu RAM và tốc độ)
  Future<List<ChapterModel>> getLightweightChaptersByStory(String storyTitle) async {
    final db = await database;
    final result = await db.query(
      AppConstants.tableChapters,
      columns: [
        'id',
        'story_title',
        'chapter_title',
        'chapter_number',
        'source_url',
        'word_count',
        'created_at',
        'last_played_sentence',
        'last_played_summary_index',
        'last_played_content_index',
        'last_played_source',
        'last_played_at',
      ],
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

  Future<void> insertAudiosBatch(
    List<SavedAudioItem> audios, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (audios.isEmpty) return;
    final db = await database;
    final storyTitle = audios.first.storyTitle;
    await db.delete(
      AppConstants.tableAudios,
      where: 'story_title = ?',
      whereArgs: [storyTitle],
    );

    const chunkSize = 500;
    for (int i = 0; i < audios.length; i += chunkSize) {
      final end = (i + chunkSize < audios.length) ? i + chunkSize : audios.length;
      final chunk = audios.sublist(i, end);
      final batch = db.batch();
      for (final audio in chunk) {
        batch.insert(
          AppConstants.tableAudios,
          audio.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      onProgress?.call(end, audios.length);
    }
  }

  Future<List<SavedAudioItem>> getAllSavedAudios() async {
    final db = await database;
    // Tối ưu: Dùng một câu lệnh query LEFT JOIN duy nhất thay vì lặp N+1 queries
    final rawList = await db.rawQuery('''
      SELECT 
        a.id AS a_id,
        a.title AS a_title,
        a.story_title AS a_story_title,
        a.chapter_number AS a_chapter_number,
        a.audio_path AS a_audio_path,
        a.summary_text AS a_summary_text,
        a.duration_seconds AS a_duration_seconds,
        a.file_size_bytes AS a_file_size_bytes,
        a.voice_used AS a_voice_used,
        a.created_at AS a_created_at,
        a.last_played_sentence AS a_last_played_sentence,
        a.last_played_summary_index AS a_last_played_summary_index,
        a.last_played_content_index AS a_last_played_content_index,
        a.last_played_source AS a_last_played_source,
        a.last_played_at AS a_last_played_at,
        c.id AS c_id,
        c.chapter_title AS c_chapter_title,
        c.content AS c_content,
        c.last_played_sentence AS c_last_played_sentence,
        c.last_played_summary_index AS c_last_played_summary_index,
        c.last_played_content_index AS c_last_played_content_index,
        c.last_played_source AS c_last_played_source,
        c.last_played_at AS c_last_played_at
      FROM ${AppConstants.tableAudios} a
      LEFT JOIN ${AppConstants.tableChapters} c
        ON a.chapter_number = c.chapter_number
        AND (a.story_title = c.story_title OR a.story_title = '' OR c.story_title = '')
      ORDER BY a.created_at DESC
    ''');

    final items = <SavedAudioItem>[];
    for (var row in rawList) {
      final actualChapterTitle = row['c_chapter_title'] as String?;
      final content = row['c_content'] as String?;
      final chapterId = row['c_id'] as String?;

      int lastPlayedSentence = row['a_last_played_sentence'] is int
          ? row['a_last_played_sentence'] as int
          : int.tryParse(row['a_last_played_sentence']?.toString() ?? '0') ?? 0;
      int lastSummaryIdx = row['a_last_played_summary_index'] is int
          ? row['a_last_played_summary_index'] as int
          : int.tryParse(row['a_last_played_summary_index']?.toString() ?? '') ?? 0;
      int lastContentIdx = row['a_last_played_content_index'] is int
          ? row['a_last_played_content_index'] as int
          : int.tryParse(row['a_last_played_content_index']?.toString() ?? '') ?? 0;

      String lastPlayedSource = row['a_last_played_source']?.toString() ?? 'summary';
      DateTime? lastPlayedAt = row['a_last_played_at'] != null
          ? DateTime.tryParse(row['a_last_played_at'].toString())
          : null;

      if (chapterId != null) {
        if (lastPlayedSentence == 0 && row['c_last_played_sentence'] != null) {
          lastPlayedSentence = row['c_last_played_sentence'] is int
              ? row['c_last_played_sentence'] as int
              : int.tryParse(row['c_last_played_sentence'].toString()) ?? 0;
        }
        if (lastSummaryIdx == 0 && row['c_last_played_summary_index'] != null) {
          lastSummaryIdx = row['c_last_played_summary_index'] is int
              ? row['c_last_played_summary_index'] as int
              : int.tryParse(row['c_last_played_summary_index'].toString()) ?? 0;
        }
        if (lastContentIdx == 0 && row['c_last_played_content_index'] != null) {
          lastContentIdx = row['c_last_played_content_index'] is int
              ? row['c_last_played_content_index'] as int
              : int.tryParse(row['c_last_played_content_index'].toString()) ?? 0;
        }
        if (row['c_last_played_source'] != null) {
          lastPlayedSource = row['c_last_played_source'].toString();
        }
        if (lastPlayedAt == null && row['c_last_played_at'] != null) {
          lastPlayedAt = DateTime.tryParse(row['c_last_played_at'].toString());
        }
      }

      final mapData = <String, dynamic>{
        'id': row['a_id'],
        'title': (actualChapterTitle != null && actualChapterTitle.isNotEmpty)
            ? actualChapterTitle
            : (row['a_title'] ?? 'Audio không tên'),
        'story_title': row['a_story_title'] ?? '',
        'chapter_number': row['a_chapter_number'],
        'audio_path': row['a_audio_path'] ?? '',
        'summary_text': row['a_summary_text'],
        'duration_seconds': row['a_duration_seconds'],
        'file_size_bytes': row['a_file_size_bytes'],
        'voice_used': row['a_voice_used'],
        'created_at': row['a_created_at'],
        'last_played_sentence': lastPlayedSentence,
        'last_played_summary_index': lastSummaryIdx,
        'last_played_content_index': lastContentIdx,
        'last_played_source': lastPlayedSource,
        'last_played_at': lastPlayedAt?.toIso8601String(),
      };

      items.add(SavedAudioItem.fromMap(mapData, content: content, chapterId: chapterId));
    }
    return items;
  }

  /// Nạp nhanh danh sách SavedAudioItem nhẹ (bỏ qua cột content để nạp tức thì 5-10ms)
  Future<List<SavedAudioItem>> getLightweightSavedAudios() async {
    final db = await database;
    final rawList = await db.rawQuery('''
      SELECT 
        a.id AS a_id,
        a.title AS a_title,
        a.story_title AS a_story_title,
        a.chapter_number AS a_chapter_number,
        a.audio_path AS a_audio_path,
        a.summary_text AS a_summary_text,
        a.duration_seconds AS a_duration_seconds,
        a.file_size_bytes AS a_file_size_bytes,
        a.voice_used AS a_voice_used,
        a.created_at AS a_created_at,
        a.last_played_sentence AS a_last_played_sentence,
        a.last_played_summary_index AS a_last_played_summary_index,
        a.last_played_content_index AS a_last_played_content_index,
        a.last_played_source AS a_last_played_source,
        a.last_played_at AS a_last_played_at,
        c.id AS c_id,
        c.chapter_title AS c_chapter_title,
        c.last_played_sentence AS c_last_played_sentence,
        c.last_played_summary_index AS c_last_played_summary_index,
        c.last_played_content_index AS c_last_played_content_index,
        c.last_played_source AS c_last_played_source,
        c.last_played_at AS c_last_played_at
      FROM ${AppConstants.tableAudios} a
      LEFT JOIN ${AppConstants.tableChapters} c
        ON a.chapter_number = c.chapter_number
        AND (a.story_title = c.story_title OR a.story_title = '' OR c.story_title = '')
      ORDER BY a.created_at DESC
    ''');

    final items = <SavedAudioItem>[];
    for (var row in rawList) {
      final actualChapterTitle = row['c_chapter_title'] as String?;
      final chapterId = row['c_id'] as String?;

      int lastPlayedSentence = row['a_last_played_sentence'] is int
          ? row['a_last_played_sentence'] as int
          : int.tryParse(row['a_last_played_sentence']?.toString() ?? '0') ?? 0;
      int lastSummaryIdx = row['a_last_played_summary_index'] is int
          ? row['a_last_played_summary_index'] as int
          : int.tryParse(row['a_last_played_summary_index']?.toString() ?? '') ?? 0;
      int lastContentIdx = row['a_last_played_content_index'] is int
          ? row['a_last_played_content_index'] as int
          : int.tryParse(row['a_last_played_content_index']?.toString() ?? '') ?? 0;

      String lastPlayedSource = row['a_last_played_source']?.toString() ?? 'summary';
      DateTime? lastPlayedAt = row['a_last_played_at'] != null
          ? DateTime.tryParse(row['a_last_played_at'].toString())
          : null;

      if (chapterId != null) {
        if (lastPlayedSentence == 0 && row['c_last_played_sentence'] != null) {
          lastPlayedSentence = row['c_last_played_sentence'] is int
              ? row['c_last_played_sentence'] as int
              : int.tryParse(row['c_last_played_sentence'].toString()) ?? 0;
        }
        if (lastSummaryIdx == 0 && row['c_last_played_summary_index'] != null) {
          lastSummaryIdx = row['c_last_played_summary_index'] is int
              ? row['c_last_played_summary_index'] as int
              : int.tryParse(row['c_last_played_summary_index'].toString()) ?? 0;
        }
        if (lastContentIdx == 0 && row['c_last_played_content_index'] != null) {
          lastContentIdx = row['c_last_played_content_index'] is int
              ? row['c_last_played_content_index'] as int
              : int.tryParse(row['c_last_played_content_index'].toString()) ?? 0;
        }
        if (row['c_last_played_source'] != null) {
          lastPlayedSource = row['c_last_played_source'].toString();
        }
        if (lastPlayedAt == null && row['c_last_played_at'] != null) {
          lastPlayedAt = DateTime.tryParse(row['c_last_played_at'].toString());
        }
      }

      final mapData = <String, dynamic>{
        'id': row['a_id'],
        'title': (actualChapterTitle != null && actualChapterTitle.isNotEmpty)
            ? actualChapterTitle
            : (row['a_title'] ?? 'Audio không tên'),
        'story_title': row['a_story_title'] ?? '',
        'chapter_number': row['a_chapter_number'],
        'audio_path': row['a_audio_path'] ?? '',
        'summary_text': row['a_summary_text'],
        'duration_seconds': row['a_duration_seconds'],
        'file_size_bytes': row['a_file_size_bytes'],
        'voice_used': row['a_voice_used'],
        'created_at': row['a_created_at'],
        'last_played_sentence': lastPlayedSentence,
        'last_played_summary_index': lastSummaryIdx,
        'last_played_content_index': lastContentIdx,
        'last_played_source': lastPlayedSource,
        'last_played_at': lastPlayedAt?.toIso8601String(),
      };

      items.add(SavedAudioItem.fromMap(mapData, content: null, chapterId: chapterId));
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
    await db.delete(AppConstants.tableBookmarks);
  }

  // ==========================================
  // Bookmark Operations
  // ==========================================
  Future<int> addBookmark({
    required String storyTitle,
    required int chapterNumber,
    String chapterTitle = '',
  }) async {
    final db = await database;
    final id = 'bm_${storyTitle.trim().toLowerCase()}_$chapterNumber';
    return await db.insert(
      AppConstants.tableBookmarks,
      {
        'id': id,
        'story_title': storyTitle.trim(),
        'chapter_number': chapterNumber,
        'chapter_title': chapterTitle.trim(),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> removeBookmark({
    required String storyTitle,
    required int chapterNumber,
  }) async {
    final db = await database;
    return await db.delete(
      AppConstants.tableBookmarks,
      where: 'LOWER(TRIM(story_title)) = ? AND chapter_number = ?',
      whereArgs: [storyTitle.trim().toLowerCase(), chapterNumber],
    );
  }

  Future<bool> isChapterBookmarked({
    required String storyTitle,
    required int chapterNumber,
  }) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.tableBookmarks,
      where: 'LOWER(TRIM(story_title)) = ? AND chapter_number = ?',
      whereArgs: [storyTitle.trim().toLowerCase(), chapterNumber],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<Set<int>> getBookmarkedChapterNumbers(String storyTitle) async {
    final db = await database;
    final maps = await db.query(
      AppConstants.tableBookmarks,
      columns: ['chapter_number'],
      where: 'LOWER(TRIM(story_title)) = ?',
      whereArgs: [storyTitle.trim().toLowerCase()],
    );
    return maps
        .map((m) => m['chapter_number'] is int
            ? m['chapter_number'] as int
            : int.tryParse(m['chapter_number']?.toString() ?? '0') ?? 0)
        .where((n) => n > 0)
        .toSet();
  }

  Future<int> deleteBookmarksForStory(String storyTitle) async {
    final db = await database;
    return await db.delete(
      AppConstants.tableBookmarks,
      where: 'LOWER(TRIM(story_title)) = ?',
      whereArgs: [storyTitle.trim().toLowerCase()],
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
