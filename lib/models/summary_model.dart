class SummaryModel {
  final String id;
  final String chapterId;
  final String summaryText;
  final List<String> bulletPoints;
  final String modelUsed;
  final int processingTimeMs;
  final DateTime createdAt;

  SummaryModel({
    required this.id,
    required this.chapterId,
    required this.summaryText,
    this.bulletPoints = const [],
    this.modelUsed = 'Default AI',
    this.processingTimeMs = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chapter_id': chapterId,
      'summary_text': summaryText,
      'bullet_points': bulletPoints.join('\n• '),
      'model_used': modelUsed,
      'processing_time_ms': processingTimeMs,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SummaryModel.fromMap(Map<String, dynamic> map) {
    List<String> bullets = [];
    if (map['bullet_points'] != null && map['bullet_points'].toString().isNotEmpty) {
      bullets = map['bullet_points']
          .toString()
          .split('\n• ')
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return SummaryModel(
      id: map['id'] ?? '',
      chapterId: map['chapter_id'] ?? '',
      summaryText: map['summary_text'] ?? '',
      bulletPoints: bullets,
      modelUsed: map['model_used'] ?? 'Default AI',
      processingTimeMs: map['processing_time_ms'] is int 
          ? map['processing_time_ms'] 
          : int.tryParse(map['processing_time_ms']?.toString() ?? '0') ?? 0,
      createdAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at']) ?? DateTime.now() 
          : DateTime.now(),
    );
  }
}
