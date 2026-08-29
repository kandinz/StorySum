import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_handler.dart';
import '../services/audio_player_service.dart';
import '../providers/settings_provider.dart';
import '../providers/player_state_provider.dart';
import '../providers/app_state_provider.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  double _progress = 0.05;
  String _statusText = 'Đang khởi động ứng dụng...';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final player = Provider.of<PlayerStateProvider>(context, listen: false);
      final appState = Provider.of<AppStateProvider>(context, listen: false);

      // Bước 1: Khởi tạo Cấu hình & Giọng đọc
      setState(() {
        _progress = 0.25;
        _statusText = 'Đang khởi tạo cấu hình & giọng đọc...';
      });
      await settings.init();
      await Future.delayed(const Duration(milliseconds: 100));

      // Bước 2: Khởi tạo Dịch vụ âm thanh & Trình phát
      setState(() {
        _progress = 0.55;
        _statusText = 'Đang nạp dịch vụ âm thanh & trình phát...';
      });
      final audioHandler = await initAudioService();
      final audioPlayerService = AudioPlayerService(
        audioHandler: audioHandler as MyAudioHandler,
      );
      player.updatePlayerService(audioPlayerService);

      // Đồng bộ BGM
      audioPlayerService.setBgmEnabled(settings.bgmEnabled);
      audioPlayerService.setBgmVolume(settings.bgmVolume);
      audioPlayerService.setBgmTrack(
        settings.currentBgmTrack.url,
        isLocal: settings.currentBgmTrack.isLocal,
      );

      // Lắng nghe sự kiện hoàn tất câu & sleep timer
      player.onPlaybackComplete.listen((_) {
        appState.handleSentenceComplete(
          settings: settings,
          player: player,
        );
      });

      player.onSleepTimerExpired = () {
        appState.stopPlayback(player: player);
      };

      await Future.delayed(const Duration(milliseconds: 100));

      // Bước 3: Tải Kho truyện & Lịch sử đọc
      setState(() {
        _progress = 0.85;
        _statusText = 'Đang nạp kho truyện & lịch sử đọc...';
      });
      await appState.loadSavedData();
      await Future.delayed(const Duration(milliseconds: 100));

      // Bước 4: Hoàn tất
      setState(() {
        _progress = 1.0;
        _statusText = 'Sẵn sàng!';
      });

      await Future.delayed(const Duration(milliseconds: 150));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Lỗi khởi động: $e';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgGradient = LinearGradient(
      colors: [
        Color(0xFF070B16),
        Color(0xFF0A0F1D),
        Color(0xFF0F172A),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 20),

              // Logo & App Name
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF6366F1),
                            Color(0xFF38BDF8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.auto_stories_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFFF8FAFC),
                        Color(0xFF38BDF8),
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'StorySum',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tóm tắt AI & Đọc truyện thông minh',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),

              // Progress Bar & Loading Status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 5,
                        child: LinearProgressIndicator(
                          value: _progress,
                          backgroundColor: const Color(0xFF1E293B),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _statusText,
                        key: ValueKey<String>(_statusText),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}