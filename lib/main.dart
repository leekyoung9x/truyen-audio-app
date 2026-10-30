import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

/// Timeout tung buoc init nen (v15: khong buoc nao duoc treo khoi dong).
const _stepTimeout = Duration(seconds: 10);

/// Thong bao nhe khi 1 buoc init nen phai dung fallback (null = moi thu OK).
/// UI hien MaterialBanner + nut tat (khong chan thao tac).
final bootNoticeProvider = StateProvider<String?>((_) => null);

Future<void> main() async {
  // v15: runApp NGAY de toi frame dau <1s. Moi init nang (Hive, audio
  // service, cache dir) chay NEN sau frame dau (_bootAsync), tung buoc
  // timeout 10s + fallback — khong await nao duoc chan truoc runApp.
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      // Seed just_audio thuan (tao dong bo, nhe): UI co handler dung ngay.
      // Boot xong se thay bang ban audio_service + dispose seed nay.
      // Web: day CHINH LA ban chuan (khong dung audio_service).
      audioHandlerProvider.overrideWithValue(StoryAudioHandler()),
      // UI chiu duoc cache null (hien loi nhe o player) nen seed null,
      // boot xong se update bang cache that (hoac memory fallback).
      audioCacheProvider.overrideWithValue(null),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TruyenAudioApp(),
    ),
  );
  unawaited(_bootAsync(container));
}

void _setNotice(ProviderContainer container, String message) {
  container.read(bootNoticeProvider.notifier).state = message;
}

/// Init nang chay NEN sau frame dau. Khong bao gio throw ra ngoai
/// (moi buoc tu try/catch + fallback) — app luon vao duoc.
Future<void> _bootAsync(ProviderContainer container) async {
  try {
    // Doi frame dau (splash/home) ve xong roi moi cham native nang
    // (ExoPlayer, service binding, disk IO).
    await WidgetsBinding.instance.endOfFrame;

    // B1. Hive (metadata cache). Fail -> van chay tiep, cache memory o B3.
    try {
      await Hive.initFlutter().timeout(_stepTimeout);
    } catch (e) {
      debugPrint('[boot] Hive.initFlutter fallback: $e');
      _setNotice(
        container,
        'Không mở được bộ nhớ cục bộ — dùng bộ nhớ tạm, vẫn nghe được.',
      );
    }

    // B2. Audio handler day du (session + audio_service). Fail/timeout ->
    // GIU NGUYEN seed just_audio thuan (van nghe duoc, mat thong bao nen).
    if (!kIsWeb) {
      try {
        final full = await _initAudioHandler().timeout(_stepTimeout);
        final seed = container.read(audioHandlerProvider);
        container.updateOverrides(
          [audioHandlerProvider.overrideWithValue(full)],
        );
        try {
          await seed.dispose();
        } catch (e) {
          debugPrint('[boot] dispose seed handler: $e');
        }
      } catch (e) {
        debugPrint('[boot] audio_service fallback just_audio: $e');
        _setNotice(
          container,
          'Chế độ nghe cơ bản (thông báo nền chưa sẵn sàng).',
        );
      }
    }

    // B3. Thu muc + box cache audio. AudioCache.init tu memory-fallback
    // nen khong throw; timeout van co fallback phong thu.
    try {
      final cache = await AudioCache.init().timeout(
        _stepTimeout,
        onTimeout: AudioCache.memory,
      );
      container.updateOverrides(
        [audioCacheProvider.overrideWithValue(cache)],
      );
    } catch (e) {
      debugPrint('[boot] AudioCache fallback memory: $e');
      container.updateOverrides(
        [audioCacheProvider.overrideWithValue(AudioCache.memory())],
      );
    }
  } catch (e) {
    // Khong bao gio de boot nen crash app.
    debugPrint('[boot] unexpected: $e');
  }
}

/// Khoi tao audio handler theo nen.
///
/// - Web: bo qua audio_service + audio_session (native-only, goi la throw
///   hoac treo -> man hinh trang). Dung handler truc tiep.
/// - Native: cau hinh session + init audio_service nhu cu.
///   (configureSession da fail-open tu v15; AudioService.init duoc timeout
///   + fallback o _bootAsync.)
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
class TruyenAudioApp extends ConsumerWidget {
  const TruyenAudioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(bootNoticeProvider);
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
      // v15: banner nhe khi boot nen phai fallback (VD: audio_service fail).
      // Mac dinh null -> tra child nguyen ven (test cu khong doi).
      builder: (context, child) {
        if (notice == null) return child!;
        return Column(
          children: [
            MaterialBanner(
              content: Text(notice),
              actions: [
                TextButton(
                  onPressed: () =>
                      ref.read(bootNoticeProvider.notifier).state = null,
                  child: const Text('Đã hiểu'),
                ),
              ],
            ),
            Expanded(child: child!),
          ],
        );
      },
    );
  }
}
