import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'providers/player_state_provider.dart';
import 'providers/app_state_provider.dart';
import 'views/splash_screen.dart';

void main() {
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

  final settingsProvider = SettingsProvider();
  final playerStateProvider = PlayerStateProvider();
  final appStateProvider = AppStateProvider();

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
      home: const SplashScreen(),
    );
  }
}


