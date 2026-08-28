import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'audio_handler.dart';
import '../models/tts_synthesis_result.dart';

class AudioPlayerService {
  final MyAudioHandler audioHandler;
  List<WordBoundary> _currentWordBoundaries = [];
  int _currentWordIndex = -1;

  AudioPlayerService({required this.audioHandler});

  AudioPlayer get player => audioHandler.player;
  List<WordBoundary> get currentWordBoundaries => _currentWordBoundaries;
  int get currentWordIndex => _currentWordIndex;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<PlayerState> get playerStateStream => player.playerStateStream;

  void setWordBoundaries(List<WordBoundary> boundaries) {
    _currentWordBoundaries = boundaries;
    _currentWordIndex = -1;
  }

  /// Tính toán index của câu / từ đang được đọc dựa trên vị trí hiện tại của audio
  int getHighlightIndexForPosition(Duration position) {
    if (_currentWordBoundaries.isEmpty) return -1;
    final posMs = position.inMilliseconds;

    for (int i = 0; i < _currentWordBoundaries.length; i++) {
      final b = _currentWordBoundaries[i];
      if (posMs >= b.offsetMs && posMs < (b.offsetMs + b.durationMs + 200)) {
        _currentWordIndex = i;
        return i;
      }
    }
    return _currentWordIndex;
  }

  Future<void> playAudioFile({
    required String filePath,
    required String title,
    required String storyTitle,
    List<WordBoundary>? boundaries,
  }) async {
    if (boundaries != null) {
      setWordBoundaries(boundaries);
    }
    await audioHandler.playFilePath(
      filePath,
      title: title,
      storyTitle: storyTitle,
    );
  }

  Future<void> play() => audioHandler.play();
  Future<void> pause() => audioHandler.pause();
  Future<void> stop() => audioHandler.stop();
  Future<void> seek(Duration position) => audioHandler.seek(position);
  Future<void> fastForward() => audioHandler.fastForward();
  Future<void> rewind() => audioHandler.rewind();
  Future<void> setSpeed(double speed) => audioHandler.setSpeed(speed);
  Future<void> setPitch(double pitch) => audioHandler.setPitch(pitch);
}
