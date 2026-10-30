// Regression test v15: fix treo logo APK (runApp truoc, init nen sau).
//
// Bug: main() await noi tiep Hive.initFlutter -> _initAudioHandler
// (configureSession + AudioService.init) -> AudioCache.init TRUOC runApp.
// Treo 1 buoc = treo logo vinh vien.
//
// Fix:
// - runApp splash ngay (seed just_audio thuan + cache null), init nang nen
//   sau frame dau, tung buoc timeout 10s + fallback.
// - configureSession fail-open (timeout 8s, khong throw).
// - AudioCache.init fail -> memory fallback (RAM, khong throw).
// - AndroidManifest du quyen audio nen + foregroundServiceType.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/cache/audio_cache.dart';
import 'package:truyen_audio_app/src/features/player/audio_handler.dart';

void main() {
  group('v15_cold_start_runApp_truoc_init_nang', () {
    test('main_runApp_truoc_moi_await_nang', () {
      final src = File('lib/main.dart').readAsStringSync();
      final runAppIdx = src.indexOf('runApp(');
      expect(runAppIdx, greaterThanOrEqualTo(0));

      // Moi await nang phai nam SAU runApp (trong _bootAsync).
      for (final heavy in [
        'await Hive.initFlutter',
        'await AudioCache.init',
        'await AudioService.init',
      ]) {
        final idx = src.indexOf(heavy);
        if (idx >= 0) {
          expect(
            idx,
            greaterThan(runAppIdx),
            reason: '$heavy phai sau runApp (init nen)',
          );
        }
      }

      // main() khong await truc tiep init nang (chi seed + runApp + boot nen).
      final mainStart = src.indexOf('Future<void> main()');
      final bootStart = src.indexOf('_bootAsync');
      expect(mainStart, greaterThanOrEqualTo(0));
      expect(bootStart, greaterThan(mainStart));
      final mainBody = src.substring(mainStart, bootStart);
      expect(
        mainBody.contains('await _initAudioHandler'),
        isFalse,
        reason: 'main() khong duoc await audio truoc runApp',
      );
    });

    test('manifest_du_quyen_audio_nen', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      for (final perm in [
        'android.permission.INTERNET',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.WAKE_LOCK',
        'android.permission.RECEIVE_BOOT_COMPLETED',
      ]) {
        expect(manifest.contains(perm), isTrue, reason: 'thieu $perm');
      }
      expect(
        manifest.contains('foregroundServiceType="mediaPlayback"'),
        isTrue,
        reason: 'service audio thieu foregroundServiceType mediaPlayback',
      );
      expect(
        manifest.contains('com.ryanheise.audioservice.AudioService'),
        isTrue,
      );
    });
  });

  group('v15_fallback_khong_chan_khoi_dong', () {
    test('configureSession_fail_open_khong_throw', () async {
      // Tren VM khong co audio_session native -> truoc v15 nem
      // MissingPluginException (treo logo tren may that); tu v15 fail-open.
      await StoryAudioHandler.configureSession();
    });

    test('audioCache_memory_store_lookup_remove', () async {
      final cache = AudioCache.memory();
      const text = 'chuong mot test memory fallback v15';
      final stored = await cache.storeAudio(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        text: text,
        voice: 'diem_trinh',
        speed: 1.0,
        chapterUrl: 'text:0',
        extension: 'mp3',
      );
      // Memory = che do blob (nhu Web): khong co file that.
      expect(stored.filePath, isNull);

      final hit = await cache.lookupAudio(
        text: text,
        voice: 'diem_trinh',
        speed: 1.0,
        extension: 'mp3',
      );
      expect(hit, isNotNull);
      expect(hit!.bytes, orderedEquals(const [1, 2, 3]));

      await cache.remove(stored.meta.key);
      expect(await cache.getByKey(stored.meta.key), isNull);
    });

    test('audioCache_init_fail_open_khong_throw', () async {
      // File test nay khong Hive.init -> openBox throw -> init() phai tu
      // fallback memory thay vi nem (mo phong storage loi tren may that).
      final cache = await AudioCache.init();
      expect(cache, isNotNull);
    });
  });
}
