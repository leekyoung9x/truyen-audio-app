import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/core/cache/audio_cache.dart';
import 'src/features/app_providers.dart';
import 'src/features/chapters/chapter_list_screen.dart';
import 'src/features/library/paste_link_screen.dart';
import 'src/features/player/audio_handler.dart';
import 'src/features/player/player_screen.dart';
import 'src/features/settings/settings_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const PasteLinkScreen()),
    GoRoute(path: '/chapters', builder: (_, _) => const ChapterListScreen()),
    GoRoute(path: '/player', builder: (_, _) => const PlayerScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Hive (metadata cache) truoc de AudioCache.init() mo box duoc.
  //    Hive.initFlutter tren Web dung IndexedDB mac dinh -> khong can path.
  await Hive.initFlutter();

  // 2. Audio: Web KHONG dung audio_service (khong ho tro background handler
  //    day du, init la crash trang trang) -> dung StoryAudioHandler truc tiep
  //    (just_audio thuan). Native giu nguyen audio_service + session.
  final audioHandler = await _initAudioHandler();

  // 3. Thu muc + box cache audio.
  final cache = await AudioCache.init();

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
        audioCacheProvider.overrideWithValue(cache),
      ],
      child: const TruyenAudioApp(),
    ),
  );
}

/// Khoi tao audio handler theo nen.
///
/// - Web: bo qua audio_service + audio_session (native-only, goi la throw
///   hoac treo -> man hinh trang). Dung handler truc tiep.
/// - Native: cau hinh session + init audio_service nhu cu.
Future<StoryAudioHandler> _initAudioHandler() async {
  if (kIsWeb) {
    return StoryAudioHandler();
  }
  await StoryAudioHandler.configureSession();
  return AudioService.init(
    builder: StoryAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.truyenaudio.app.channel.audio',
      androidNotificationChannelName: 'Nghe truyện',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Material 3 mac dinh + dark mode (theo cau hinh he thong).
class TruyenAudioApp extends StatelessWidget {
  const TruyenAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Truyện Audio',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
