import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'services/audio_handler.dart';
import 'services/audio_player_service.dart';
import 'providers/settings_provider.dart';
import 'providers/player_state_provider.dart';
import 'providers/app_state_provider.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Đặt thanh trạng thái trong suốt
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Khởi tạo Audio Service ngầm cho Android
  final audioHandler = await initAudioService();
  final audioPlayerService = AudioPlayerService(
    audioHandler: audioHandler as MyAudioHandler,
  );

  // Khởi tạo Settings Provider
  final settingsProvider = SettingsProvider();
  await settingsProvider.init();

  // Khởi tạo AppState Provider & load dữ liệu đã lưu
  final appStateProvider = AppStateProvider();
  await appStateProvider.loadSavedData();

  // Khởi tạo PlayerState Provider
  final playerStateProvider = PlayerStateProvider(playerService: audioPlayerService);

  // Đồng bộ cấu hình BGM khi khởi động (chạy ngầm không chặn luồng khởi động giao diện)
  audioPlayerService.setBgmEnabled(settingsProvider.bgmEnabled);
  audioPlayerService.setBgmVolume(settingsProvider.bgmVolume);
  audioPlayerService.setBgmTrack(
    settingsProvider.currentBgmTrack.url,
    isLocal: settingsProvider.currentBgmTrack.isLocal,
  );

  // Lắng nghe sự kiện kết thúc phát câu ở cấp Provider toàn cục (đảm bảo hoạt động ngầm liên tục khi khóa màn hình)
  playerStateProvider.onPlaybackComplete.listen((_) {
    appStateProvider.handleSentenceComplete(
      settings: settingsProvider,
      player: playerStateProvider,
    );
  });

  // Lắng nghe sự kiện hết giờ hẹn dừng phát
  playerStateProvider.onSleepTimerExpired = () {
    appStateProvider.stopPlayback(player: playerStateProvider);
  };



  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
        ),
        ChangeNotifierProvider<PlayerStateProvider>.value(
          value: playerStateProvider,
        ),
        ChangeNotifierProvider<AppStateProvider>.value(
          value: appStateProvider,
        ),
      ],
      child: const StorySumApp(),
    ),
  );
}


class StorySumApp extends StatelessWidget {
  const StorySumApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'StorySum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getThemeData(settings.appThemeMode, context),
      home: const HomeScreen(),
    );
  }
}

