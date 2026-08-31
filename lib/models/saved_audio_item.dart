import '../core/utils/text_normalizer.dart';

class SavedAudioItem {
  final String id;
  final String title;
  final String storyTitle;
  final int chapterNumber;
  final String audioPath;
  final String? summaryText;
  final String? content;
  final String? chapterId;
  final int durationSeconds;
  final int fileSizeBytes;
  final String voiceUsed;
  final DateTime createdAt;
  final int lastPlayedSentenceIndex;
  final int lastPlayedSummaryIndex;
  final int lastPlayedContentIndex;
  final String lastPlayedSource; // 'summary' | 'content'
  final DateTime? lastPlayedAt;

  int? _summarySentenceCount;
  int? _contentSentenceCount;

  SavedAudioItem({
    required this.id,
    required this.title,
    required this.storyTitle,
    required this.chapterNumber,
    required this.audioPath,
    this.summaryText,
    this.content,
    this.chapterId,
    this.durationSeconds = 0,
    this.fileSizeBytes = 0,
    this.voiceUsed = 'HoaiMy Neural',
    DateTime? createdAt,
    this.lastPlayedSentenceIndex = 0,
    this.lastPlayedSummaryIndex = 0,
    this.lastPlayedContentIndex = 0,
    this.lastPlayedSource = 'summary',
    this.lastPlayedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'story_title': storyTitle,
      'chapter_number': chapterNumber,
      'audio_path': audioPath,
      'summary_text': summaryText ?? '',
      'duration_seconds': durationSeconds,
      'file_size_bytes': fileSizeBytes,
      'voice_used': voiceUsed,
      'created_at': createdAt.toIso8601String(),
      'last_played_sentence': lastPlayedSentenceIndex,
      'last_played_summary_index': lastPlayedSummaryIndex,
      'last_played_content_index': lastPlayedContentIndex,
      'last_played_source': lastPlayedSource,
      'last_played_at': lastPlayedAt?.toIso8601String(),
    };
  }

  factory SavedAudioItem.fromMap(Map<String, dynamic> map, {String? content, String? chapterId}) {
    final lastSentence = map['last_played_sentence'] is int
        ? map['last_played_sentence']
        : int.tryParse(map['last_played_sentence']?.toString() ?? '0') ?? 0;
    final lastSource = map['last_played_source'] ?? 'summary';

    int lastSummaryIdx = map['last_played_summary_index'] is int
        ? map['last_played_summary_index']
        : int.tryParse(map['last_played_summary_index']?.toString() ?? '') ??
            (lastSource == 'summary' ? lastSentence : 0);

    int lastContentIdx = map['last_played_content_index'] is int
        ? map['last_played_content_index']
        : int.tryParse(map['last_played_content_index']?.toString() ?? '') ??
            (lastSource == 'content' ? lastSentence : 0);

    return SavedAudioItem(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Audio không tên',
      storyTitle: map['story_title'] ?? 'Truyện',
      chapterNumber: map['chapter_number'] is int
          ? map['chapter_number']
          : int.tryParse(map['chapter_number']?.toString() ?? '0') ?? 0,
      audioPath: map['audio_path'] ?? '',
      summaryText: map['summary_text'],
      content: content,
      chapterId: chapterId,
      durationSeconds: map['duration_seconds'] is int
          ? map['duration_seconds']
          : int.tryParse(map['duration_seconds']?.toString() ?? '0') ?? 0,
      fileSizeBytes: map['file_size_bytes'] is int
          ? map['file_size_bytes']
          : int.tryParse(map['file_size_bytes']?.toString() ?? '0') ?? 0,
      voiceUsed: map['voice_used'] ?? 'HoaiMy Neural',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at']) ?? DateTime.now()
          : DateTime.now(),
      lastPlayedSentenceIndex: lastSentence,
      lastPlayedSummaryIndex: lastSummaryIdx,
      lastPlayedContentIndex: lastContentIdx,
      lastPlayedSource: lastSource,
      lastPlayedAt: map['last_played_at'] != null
          ? DateTime.tryParse(map['last_played_at'])
          : null,
    );
  }

  SavedAudioItem copyWith({
    String? id,
    String? title,
    String? storyTitle,
    int? chapterNumber,
    String? audioPath,
    String? summaryText,
    String? content,
    String? chapterId,
    int? durationSeconds,
    int? fileSizeBytes,
    String? voiceUsed,
    DateTime? createdAt,
    int? lastPlayedSentenceIndex,
    int? lastPlayedSummaryIndex,
    int? lastPlayedContentIndex,
    String? lastPlayedSource,
    DateTime? lastPlayedAt,
  }) {
    return SavedAudioItem(
      id: id ?? this.id,
      title: title ?? this.title,
      storyTitle: storyTitle ?? this.storyTitle,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      audioPath: audioPath ?? this.audioPath,
      summaryText: summaryText ?? this.summaryText,
      content: content ?? this.content,
      chapterId: chapterId ?? this.chapterId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      voiceUsed: voiceUsed ?? this.voiceUsed,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedSentenceIndex: lastPlayedSentenceIndex ?? this.lastPlayedSentenceIndex,
      lastPlayedSummaryIndex: lastPlayedSummaryIndex ?? this.lastPlayedSummaryIndex,
      lastPlayedContentIndex: lastPlayedContentIndex ?? this.lastPlayedContentIndex,
      lastPlayedSource: lastPlayedSource ?? this.lastPlayedSource,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  String get displayChapterTitle {
    String cleanTitle = title;
    if (cleanTitle.contains(' - ')) {
      final parts = cleanTitle.split(' - ');
      if (parts.length >= 2 && parts[0].trim().toLowerCase() == storyTitle.trim().toLowerCase()) {
        cleanTitle = parts.sublist(1).join(' - ').trim();
      }
    }
    if (cleanTitle.isEmpty || cleanTitle == 'Audio không tên') {
      return 'Chương $chapterNumber';
    }
    if (!cleanTitle.toLowerCase().startsWith('chương') &&
        !cleanTitle.toLowerCase().startsWith('hồi') &&
        !cleanTitle.toLowerCase().startsWith('chap') &&
        !cleanTitle.toLowerCase().startsWith('chapter')) {
      return 'Chương $chapterNumber: $cleanTitle';
    }
    return cleanTitle;
  }

  int get summarySentenceCount {
    if (_summarySentenceCount != null) return _summarySentenceCount!;
    if (summaryText == null || summaryText!.trim().isEmpty) {
      _summarySentenceCount = 0;
      return 0;
    }
    _summarySentenceCount = _countSentences(summaryText!, displayChapterTitle);
    return _summarySentenceCount!;
  }

  int get contentSentenceCount {
    if (_contentSentenceCount != null) return _contentSentenceCount!;
    if (content == null || content!.trim().isEmpty) {
      _contentSentenceCount = 0;
      return 0;
    }
    _contentSentenceCount = _countSentences(content!, displayChapterTitle);
    return _contentSentenceCount!;
  }

  static int _countSentences(String text, String header) {
    String c = text.trim();
    if (header.isNotEmpty && !c.toLowerCase().startsWith(header.toLowerCase())) {
      c = '$header\n\n$c';
    }
    final normalized = TextNormalizer.normalize(c).replaceAll('\r\n', '\n');
    final regex = RegExp(r'(?<=[.!?…])\s+|\n+');
    final rawList = normalized.split(regex);
    int count = 0;
    for (final raw in rawList) {
      final t = raw.trim();
      if (t.isNotEmpty && RegExp(r'[a-zA-Z0-9\u00C0-\u1EF9]').hasMatch(t)) {
        count++;
      }
    }
    return count;
  }
}

