// Unit AudioCache THAT tren Hive tam + FakeAudioCache — test THUONG
// (khong phai testWidgets: Hive.openBox treo trong testWidgets zone).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/cache/audio_cache.dart';

import 'fakes/fake_audio_cache.dart';

Uint8List _mp3() => Uint8List.fromList(const [0x49, 0x44, 0x33, 1, 2]);

void main() {
  group('audio_cache_that_tren_hive_tam', () {
    late Directory tmp;

    setUpAll(() => tmp = initTestHive());
    tearDownAll(() => disposeTestHive(tmp));

    setUp(() async => (await openTestCache()).clear());

    test('audio_cache_store_roi_lookup_trung_bytes', () async {
      final cache = await openTestCache();
      const text = 'Nội dung chương một.';
      final stored = await cache.storeAudio(
        bytes: _mp3(),
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        chapterUrl: 'https://x/y#chapter=0',
        extension: 'mp3',
      );
      expect(stored.filePath, isNotNull);

      final hit = await cache.lookupAudio(
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        extension: 'mp3',
      );
      expect(hit, isNotNull);
      expect(hit!.bytes, _mp3());
      expect(hit.meta.voice, 'Trúc Ly');
    });

    test('audio_cache_lookup_chua_co_tra_ve_null', () async {
      final cache = await openTestCache();
      final hit = await cache.lookupAudio(
        text: 'Chưa từng lưu.',
        voice: 'Trúc Ly',
        speed: 1.0,
        extension: 'mp3',
      );
      expect(hit, isNull);
    });

    test('audio_cache_khac_voice_khac_speed_khac_key', () async {
      final cache = await openTestCache();
      await cache.storeAudio(
        bytes: _mp3(),
        text: 'Cùng text.',
        voice: 'Trúc Ly',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      // Khac voice -> miss.
      final missVoice = await cache.lookupAudio(
        text: 'Cùng text.',
        voice: 'Thiện Minh',
        speed: 1.0,
        extension: 'mp3',
      );
      expect(missVoice, isNull);
      // Khac speed -> miss.
      final missSpeed = await cache.lookupAudio(
        text: 'Cùng text.',
        voice: 'Trúc Ly',
        speed: 1.2,
        extension: 'mp3',
      );
      expect(missSpeed, isNull);
    });

    test('audio_cache_remove_xoa_ban_ghi', () async {
      final cache = await openTestCache();
      const text = 'Chương cần xóa.';
      await cache.storeAudio(
        bytes: _mp3(),
        text: text,
        voice: 'v',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      final key = AudioCache.cacheKey(text: text, voice: 'v', speed: 1.0);
      await cache.remove(key);
      expect(await cache.getByKey(key), isNull);
    });

    test('audio_cache_get_all_meta_va_clear', () async {
      final cache = await openTestCache();
      await cache.storeAudio(
        bytes: _mp3(),
        text: 'Một.',
        voice: 'v',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      await cache.storeAudio(
        bytes: _mp3(),
        text: 'Hai.',
        voice: 'v',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      expect(cache.getAllMeta().length, 2);
      await cache.clear();
      expect(cache.getAllMeta(), isEmpty);
    });

    test('audio_cache_key_sai_nem_argument_error', () async {
      final cache = await openTestCache();
      expect(() => cache.getByKey('khong-phai-md5'), throwsArgumentError);
      expect(() => cache.remove('../x'), throwsArgumentError);
    });

    test('audio_cache_extension_sai_nem_argument_error', () async {
      final cache = await openTestCache();
      expect(
        () => cache.lookupAudio(
          text: 't',
          voice: 'v',
          speed: 1.0,
          extension: '../../etc',
        ),
        throwsArgumentError,
      );
      expect(
        () => cache.storeAudio(
          bytes: _mp3(),
          text: 't',
          voice: 'v',
          speed: 1.0,
          chapterUrl: 'u',
          extension: 'mp3/../x',
        ),
        throwsArgumentError,
      );
    });
  });

  group('fake_audio_cache_memory_dung_cho_widget_test', () {
    test('fake_cache_store_lookup_remove_clear', () async {
      final cache = FakeAudioCache();
      const text = 'Chương memory.';
      final stored = await cache.storeAudio(
        bytes: _mp3(),
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      expect(stored.bytes, _mp3());

      final hit = await cache.lookupAudio(
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        extension: 'mp3',
      );
      expect(hit, isNotNull);
      expect(cache.getAllMeta().length, 1);

      final key = AudioCache.cacheKey(text: text, voice: 'Trúc Ly', speed: 1.0);
      await cache.remove(key);
      expect(await cache.getByKey(key), isNull);

      await cache.storeAudio(
        bytes: _mp3(),
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        chapterUrl: 'u',
        extension: 'mp3',
      );
      await cache.clear();
      expect(cache.getAllMeta(), isEmpty);
    });

    test('fake_cache_giu_nguyen_guard_key_va_extension', () async {
      final cache = FakeAudioCache();
      expect(() => cache.getByKey('sai'), throwsArgumentError);
      expect(
        () => cache.lookupAudio(
          text: 't',
          voice: 'v',
          speed: 1.0,
          extension: '../x',
        ),
        throwsArgumentError,
      );
    });
  });

  group('audio_meta_va_cache_key', () {
    test('audio_cache_cache_key_on_dinh_32_ky_tu_hex', () {
      final k1 = AudioCache.cacheKey(text: 'a', voice: 'v', speed: 1.0);
      final k2 = AudioCache.cacheKey(text: 'a', voice: 'v', speed: 1.0);
      final k3 = AudioCache.cacheKey(text: 'b', voice: 'v', speed: 1.0);
      expect(k1, k2);
      expect(k1, hasLength(32));
      expect(k1, isNot(k3));
    });

    test('audio_meta_to_map_from_map_tron_vong', () {
      final meta = AudioMeta(
        key: 'k',
        fileName: 'k.mp3',
        chapterUrl: 'u',
        voice: 'v',
        speed: 1.2,
        createdAt: DateTime(2026, 10, 27),
      );
      final back = AudioMeta.fromMap(meta.toMap());
      expect(back.key, 'k');
      expect(back.fileName, 'k.mp3');
      expect(back.voice, 'v');
      expect(back.speed, 1.2);
    });
  });
}
