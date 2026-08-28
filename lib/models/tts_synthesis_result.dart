import 'dart:typed_data';

class WordBoundary {
  final int offsetMs;
  final int durationMs;
  final String text;

  WordBoundary({
    required this.offsetMs,
    required this.durationMs,
    required this.text,
  });
}

class TtsSynthesisResult {
  final String audioFilePath;
  final Uint8List audioBytes;
  final List<WordBoundary> wordBoundaries;
  final int durationMs;

  TtsSynthesisResult({
    required this.audioFilePath,
    required this.audioBytes,
    required this.wordBoundaries,
    required this.durationMs,
  });
}
