class ChapterModel {
  final String id;
  final String storyTitle;
  final String chapterTitle;
  final int chapterNumber;
  final String sourceUrl;
  final String content;
  final int wordCount;
  final DateTime createdAt;
  final int lastPlayedSentenceIndex;
  final int lastPlayedSummaryIndex;
  final int lastPlayedContentIndex;
  final String lastPlayedSource; // 'summary' | 'content'
  final DateTime? lastPlayedAt;

  ChapterModel({
    required this.id,
    required this.storyTitle,
    required this.chapterTitle,
    required this.chapterNumber,
    required this.sourceUrl,
    required this.content,
    required this.wordCount,
    DateTime? createdAt,
    this.lastPlayedSentenceIndex = 0,
    this.lastPlayedSummaryIndex = 0,
    this.lastPlayedContentIndex = 0,
    this.lastPlayedSource = 'summary',
    this.lastPlayedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  List<String> get paragraphs =>
      content.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'story_title': storyTitle,
      'chapter_title': chapterTitle,
      'chapter_number': chapterNumber,
      'source_url': sourceUrl,
      'content': content,
      'word_count': wordCount,
      'created_at': createdAt.toIso8601String(),
      'last_played_sentence': lastPlayedSentenceIndex,
      'last_played_summary_index': lastPlayedSummaryIndex,
      'last_played_content_index': lastPlayedContentIndex,
      'last_played_source': lastPlayedSource,
      'last_played_at': lastPlayedAt?.toIso8601String(),
    };
  }

  factory ChapterModel.fromMap(Map<String, dynamic> map) {
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

    return ChapterModel(
      id: map['id'] ?? '',
      storyTitle: map['story_title'] ?? 'Truyện chưa đặt tên',
      chapterTitle: map['chapter_title'] ?? 'Chương ${map['chapter_number'] ?? ''}',
      chapterNumber: map['chapter_number'] is int
          ? map['chapter_number']
          : int.tryParse(map['chapter_number']?.toString() ?? '0') ?? 0,
      sourceUrl: map['source_url'] ?? '',
      content: map['content'] ?? '',
      wordCount: map['word_count'] is int
          ? map['word_count']
          : int.tryParse(map['word_count']?.toString() ?? '0') ?? 0,
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

  ChapterModel copyWith({
    String? id,
    String? storyTitle,
    String? chapterTitle,
    int? chapterNumber,
    String? sourceUrl,
    String? content,
    int? wordCount,
    DateTime? createdAt,
    int? lastPlayedSentenceIndex,
    int? lastPlayedSummaryIndex,
    int? lastPlayedContentIndex,
    String? lastPlayedSource,
    DateTime? lastPlayedAt,
  }) {
    return ChapterModel(
      id: id ?? this.id,
      storyTitle: storyTitle ?? this.storyTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      content: content ?? this.content,
      wordCount: wordCount ?? this.wordCount,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedSentenceIndex: lastPlayedSentenceIndex ?? this.lastPlayedSentenceIndex,
      lastPlayedSummaryIndex: lastPlayedSummaryIndex ?? this.lastPlayedSummaryIndex,
      lastPlayedContentIndex: lastPlayedContentIndex ?? this.lastPlayedContentIndex,
      lastPlayedSource: lastPlayedSource ?? this.lastPlayedSource,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }
}
