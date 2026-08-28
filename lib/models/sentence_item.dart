class SentenceItem {
  final int index;
  final String text;
  final String? audioPath;
  final bool isGenerating;
  final bool hasError;

  const SentenceItem({
    required this.index,
    required this.text,
    this.audioPath,
    this.isGenerating = false,
    this.hasError = false,
  });

  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;

  SentenceItem copyWith({
    int? index,
    String? text,
    String? audioPath,
    bool? isGenerating,
    bool? hasError,
  }) {
    return SentenceItem(
      index: index ?? this.index,
      text: text ?? this.text,
      audioPath: audioPath ?? this.audioPath,
      isGenerating: isGenerating ?? this.isGenerating,
      hasError: hasError ?? this.hasError,
    );
  }
}
