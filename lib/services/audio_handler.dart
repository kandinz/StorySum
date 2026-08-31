import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.storysum.audio',
      androidNotificationChannelName: 'StorySum Audio Service',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}



class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _bgmPlayer = AudioPlayer();

  bool _bgmEnabled = false;
  double _bgmVolume = 0.2;
  String? _currentBgmUrl;
  bool _isBgmLocal = false;

  bool _isPreviewingBgm = false;

  MyAudioHandler() {
    _init();
  }

  AudioPlayer get player => _player;
  AudioPlayer get bgmPlayer => _bgmPlayer;
  bool get bgmEnabled => _bgmEnabled;
  double get bgmVolume => _bgmVolume;
  String? get currentBgmUrl => _currentBgmUrl;
  bool get isPreviewingBgm => _isPreviewingBgm;

  void _init() {
    // Cài đặt lặp lại vô hạn cho Nhạc nền
    _bgmPlayer.setLoopMode(LoopMode.all);
    _bgmPlayer.setVolume(_bgmVolume);

    // Chuyển đổi sự kiện BGM player để cập nhật preview state
    _bgmPlayer.playbackEventStream.listen((event) {
      if (_bgmPlayer.processingState == ProcessingState.idle ||
          _bgmPlayer.processingState == ProcessingState.completed) {
        if (_isPreviewingBgm && !_bgmPlayer.playing) {
          _isPreviewingBgm = false;
        }
      }
    });

    // Chuyển đổi sự kiện player sang AudioService playback state
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;

      // Đồng bộ trạng thái phát nhạc nền cùng với giọng đọc
      _syncBgmWithVoice(playing);

      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState] ?? AudioProcessingState.idle,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  Future<void> _ensureBgmPrepared() async {
    if (_currentBgmUrl == null || _currentBgmUrl!.isEmpty) return;
    if (_bgmPlayer.audioSource != null && _bgmPlayer.processingState != ProcessingState.idle) {
      return;
    }
    try {
      if (_isBgmLocal) {
        await _bgmPlayer.setFilePath(_currentBgmUrl!);
      } else {
        await _bgmPlayer.setUrl(
          _currentBgmUrl!,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );
      }
      await _bgmPlayer.setLoopMode(LoopMode.all);
      await _bgmPlayer.setVolume(_bgmVolume);
    } catch (_) {}
  }

  Future<void> _syncBgmWithVoice(bool isVoicePlaying) async {
    if (_isPreviewingBgm) return;
    if (_bgmEnabled && _currentBgmUrl != null && _currentBgmUrl!.isNotEmpty) {
      if (isVoicePlaying) {
        await _ensureBgmPrepared();
        if (!_bgmPlayer.playing) {
          try {
            await _bgmPlayer.play();
          } catch (_) {}
        }
      } else {
        if (_bgmPlayer.playing) {
          try {
            await _bgmPlayer.pause();
          } catch (_) {}
        }
      }
    } else {
      if (_bgmPlayer.playing) {
        try {
          await _bgmPlayer.pause();
        } catch (_) {}
      }
    }
  }

  Future<void> setBgmEnabled(bool enabled) async {
    _bgmEnabled = enabled;
    await _syncBgmWithVoice(_player.playing);
  }

  Future<void> setBgmVolume(double volume) async {
    _bgmVolume = volume.clamp(0.0, 1.0);
    await _bgmPlayer.setVolume(_bgmVolume);
  }

  Future<void> setBgmTrack(String url, {bool isLocal = false}) async {
    if (_currentBgmUrl == url && _isBgmLocal == isLocal && _bgmPlayer.audioSource != null) return;

    _currentBgmUrl = url;
    _isBgmLocal = isLocal;

    final wasPlaying = _bgmPlayer.playing;
    try {
      if (isLocal) {
        await _bgmPlayer.setFilePath(url);
      } else {
        await _bgmPlayer.setUrl(
          url,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );
      }
      await _bgmPlayer.setLoopMode(LoopMode.all);
      await _bgmPlayer.setVolume(_bgmVolume);

      if (wasPlaying || (_bgmEnabled && _player.playing)) {
        await _bgmPlayer.play();
      }
    } catch (_) {}
  }

  Future<void> playBgmPreview(String url, {bool isLocal = false}) async {
    if (url.trim().isEmpty) return;
    try {
      _isPreviewingBgm = true;
      await _bgmPlayer.stop();
      if (isLocal) {
        await _bgmPlayer.setFilePath(url);
      } else {
        await _bgmPlayer.setUrl(
          url,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );
      }
      await _bgmPlayer.setLoopMode(LoopMode.all);
      await _bgmPlayer.setVolume(_bgmVolume > 0.05 ? _bgmVolume : 0.4);
      await _bgmPlayer.play();
    } catch (e) {
      _isPreviewingBgm = false;
      print('Lỗi nghe thử BGM: $e');
      rethrow;
    }
  }

  Future<void> stopBgmPreview() async {
    try {
      _isPreviewingBgm = false;
      await _bgmPlayer.stop();
      if (_bgmEnabled && _player.playing && _currentBgmUrl != null && _currentBgmUrl!.isNotEmpty) {
        if (_isBgmLocal) {
          await _bgmPlayer.setFilePath(_currentBgmUrl!);
        } else {
          await _bgmPlayer.setUrl(
            _currentBgmUrl!,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          );
        }
        await _bgmPlayer.setLoopMode(LoopMode.all);
        await _bgmPlayer.setVolume(_bgmVolume);
        await _bgmPlayer.play();
      }
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    await _player.play();
    await _syncBgmWithVoice(true);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    await _syncBgmWithVoice(false);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _syncBgmWithVoice(false);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> fastForward() async {
    final newPos = _player.position + const Duration(seconds: 10);
    final dur = _player.duration ?? Duration.zero;
    await seek(newPos > dur ? dur : newPos);
  }

  @override
  Future<void> rewind() async {
    final newPos = _player.position - const Duration(seconds: 10);
    await seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  Future<void> playFilePath(String filePath, {required String title, required String storyTitle}) async {
    mediaItem.add(MediaItem(
      id: filePath,
      album: storyTitle,
      title: title,
      artist: 'StorySum TTS',
      duration: _player.duration,
    ));

    try {
      await _player.setFilePath(filePath);
      await _player.play();
      await _syncBgmWithVoice(true);
    } catch (e) {
      print('Lỗi playFilePath: $e');
    }
  }
}
