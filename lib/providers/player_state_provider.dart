import 'dart:async';
import 'package:flutter/material.dart' hide WordBoundary;
import 'package:just_audio/just_audio.dart';
import '../services/audio_player_service.dart';
import '../models/tts_synthesis_result.dart';

enum AudioSourceType {
  summary,
  content,
  custom,
}

class PlayerStateProvider extends ChangeNotifier {
  AudioPlayerService? _playerService;
  AudioPlayerService get playerService => _playerService!;

  bool _isPlaying = false;
  bool _isPausedByUser = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int _highlightedIndex = -1;
  String _currentTitle = 'Chưa phát';
  String _currentStoryTitle = 'Truyện';
  int _currentChapterNumber = 0;
  String? _currentAudioPath;
  AudioSourceType _currentAudioSource = AudioSourceType.summary;
  int? _currentSentenceIndex;
  List<WordBoundary> _boundaries = [];

  // ==========================================
  // SLEEP TIMER (HẸN GIỜ DỪNG PHÁT)
  // ==========================================
  bool _sleepTimerEnabled = false;
  int _sleepTimerMinutes = 30; // Mặc định 30 phút
  DateTime? _sleepTimerEndTime;
  Timer? _sleepTimer;
  Duration _sleepTimerRemaining = Duration.zero;
  VoidCallback? onSleepTimerExpired;

  static const List<int> sleepTimerPresets = [15, 30, 45, 60, 90, 120];

  final StreamController<void> _playbackCompleteController = StreamController<void>.broadcast();

  PlayerStateProvider({AudioPlayerService? playerService}) : _playerService = playerService {
    if (_playerService != null) {
      _initListeners();
    }
  }

  void updatePlayerService(AudioPlayerService service) {
    _playerService = service;
    _initListeners();
    notifyListeners();
  }

  bool get isPlaying => _isPlaying;
  bool get isPausedByUser => _isPausedByUser;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  int get highlightedIndex => _highlightedIndex;
  String get currentTitle => _currentTitle;
  String get currentStoryTitle => _currentStoryTitle;
  int get currentChapterNumber => _currentChapterNumber;
  String? get currentAudioPath => _currentAudioPath;
  AudioSourceType get currentAudioSource => _currentAudioSource;
  int? get currentSentenceIndex => _currentSentenceIndex;
  List<WordBoundary> get boundaries => _boundaries;

  bool get isPlayingSummary => _isPlaying && _currentAudioSource == AudioSourceType.summary;
  bool get isPlayingContent => _isPlaying && _currentAudioSource == AudioSourceType.content;
  Stream<void> get onPlaybackComplete => _playbackCompleteController.stream;

  // Sleep Timer Getters
  bool get sleepTimerEnabled => _sleepTimerEnabled;
  int get sleepTimerMinutes => _sleepTimerMinutes;
  Duration get sleepTimerRemaining => _sleepTimerRemaining;

  String get formattedSleepTimerRemaining {
    if (!_sleepTimerEnabled || _sleepTimerRemaining.inSeconds <= 0) return '';
    final minutes = _sleepTimerRemaining.inMinutes;
    final seconds = _sleepTimerRemaining.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void resetManualPause() {
    _isPausedByUser = false;
    notifyListeners();
  }

  void _initListeners() {
    playerService.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.processingState == ProcessingState.completed) {
        if (!_isPausedByUser) {
          _playbackCompleteController.add(null);
        }
      }
      notifyListeners();
    });


    playerService.positionStream.listen((pos) {
      _currentPosition = pos;
      final newIndex = playerService.getHighlightIndexForPosition(pos);
      if (newIndex != _highlightedIndex) {
        _highlightedIndex = newIndex;
      }
      notifyListeners();
    });

    playerService.durationStream.listen((dur) {
      if (dur != null) {
        _totalDuration = dur;
        notifyListeners();
      }
    });

    playerService.bgmPlayer.playerStateStream.listen((state) {
      notifyListeners();
    });
  }

  Future<void> playAudio({
    required String filePath,
    required String title,
    required String storyTitle,
    required int chapterNumber,
    AudioSourceType audioSource = AudioSourceType.summary,
    int? sentenceIndex,
    List<WordBoundary>? boundaries,
  }) async {
    _isPausedByUser = false;
    _currentTitle = title;
    _currentStoryTitle = storyTitle;
    _currentChapterNumber = chapterNumber;
    _currentAudioPath = filePath;
    _currentAudioSource = audioSource;
    _currentSentenceIndex = sentenceIndex;
    _boundaries = boundaries ?? [];

    if (_playerService != null) {
      await _playerService!.playAudioFile(
        filePath: filePath,
        title: title,
        storyTitle: storyTitle,
        boundaries: boundaries,
      );
    }
    notifyListeners();
  }

  void clearCurrentAudio() {
    _currentAudioPath = null;
    _currentSentenceIndex = null;
    notifyListeners();
  }

  Future<void> stop({bool resetPause = false}) async {
    if (resetPause) {
      _isPausedByUser = false;
    }
    if (_playerService != null) {
      await _playerService!.stop();
    }
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _currentSentenceIndex = null;
    _currentAudioPath = null;
    notifyListeners();
  }

  Future<void> pause() async {
    _isPausedByUser = true;
    if (_playerService != null) {
      await _playerService!.pause();
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> play() async {
    _isPausedByUser = false;
    if (_playerService != null) {
      await _playerService!.play();
    }
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration pos) async {
    if (_playerService != null) {
      await _playerService!.seek(pos);
    }
  }

  Future<void> forward10() async {
    if (_playerService != null) {
      await _playerService!.fastForward();
    }
  }

  Future<void> rewind10() async {
    if (_playerService != null) {
      await _playerService!.rewind();
    }
  }

  Future<void> setSpeed(double speed) async {
    if (_playerService != null) {
      await _playerService!.setSpeed(speed);
    }
  }

  Future<void> setPitch(double pitch) async {
    if (_playerService != null) {
      await _playerService!.setPitch(pitch);
    }
  }

  // ==========================================
  // BACKGROUND MUSIC (BGM) LOGIC
  // ==========================================
  bool get bgmEnabled => _playerService?.bgmEnabled ?? false;
  double get bgmVolume => _playerService?.bgmVolume ?? 0.3;
  bool get isPreviewingBgm => _playerService?.isPreviewingBgm ?? false;

  Future<void> setBgmEnabled(bool enabled) async {
    if (_playerService != null) {
      await _playerService!.setBgmEnabled(enabled);
    }
    notifyListeners();
  }

  Future<void> setBgmVolume(double volume) async {
    if (_playerService != null) {
      await _playerService!.setBgmVolume(volume);
    }
    notifyListeners();
  }

  Future<void> setBgmTrack(String url, {bool isLocal = false}) async {
    if (_playerService != null) {
      await _playerService!.setBgmTrack(url, isLocal: isLocal);
    }
    notifyListeners();
  }

  Future<void> playBgmPreview(String url, {bool isLocal = false}) async {
    if (_playerService != null) {
      await _playerService!.playBgmPreview(url, isLocal: isLocal);
    }
    notifyListeners();
  }

  Future<void> stopBgmPreview() async {
    if (_playerService != null) {
      await _playerService!.stopBgmPreview();
    }
    notifyListeners();
  }

  // ==========================================
  // SLEEP TIMER LOGIC
  // ==========================================
  void setSleepTimerMinutes(int minutes) {
    _sleepTimerMinutes = minutes;
    if (_sleepTimerEnabled) {
      startSleepTimer(minutes);
    } else {
      notifyListeners();
    }
  }

  void toggleSleepTimer(bool enable, [int? minutes]) {
    if (enable) {
      startSleepTimer(minutes ?? _sleepTimerMinutes);
    } else {
      cancelSleepTimer();
    }
  }

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerMinutes = minutes;
    _sleepTimerEnabled = true;
    _sleepTimerEndTime = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimerRemaining = Duration(minutes: minutes);

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerEndTime == null) {
        timer.cancel();
        return;
      }
      final remaining = _sleepTimerEndTime!.difference(DateTime.now());
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        timer.cancel();
        _sleepTimerEnabled = false;
        _sleepTimerEndTime = null;
        _sleepTimerRemaining = Duration.zero;
        stop();
        if (onSleepTimerExpired != null) {
          onSleepTimerExpired!();
        }
        notifyListeners();
      } else {
        _sleepTimerRemaining = remaining;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEnabled = false;
    _sleepTimerEndTime = null;
    _sleepTimerRemaining = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playbackCompleteController.close();
    super.dispose();
  }
}
