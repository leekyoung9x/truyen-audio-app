// Unit mo rong: ParseClient timeout/loi + ensureChapterAudio cache/fallback.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/convert/chapter_audio.dart';
import 'package:truyen_audio_app/src/core/parse/parse_client.dart';
import 'package:truyen_audio_app/src/core/tts/fallback_chain.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/fake_tts.dart';

/// Dio stub tra JSON cho POST /parse hoac nem loi mang.
ParseClient _stubParse({
  Map<String, dynamic>? json,
  DioException? error,
  int? statusCode,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (error != null) {
          return handler.reject(error);
        }
        if (statusCode != null && (statusCode < 200 || statusCode >= 300)) {
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: statusCode,
              ),
            ),
          );
        }
        return handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data:
                json ??
                const {
                  'chapters': [
                    {'title': 'C1', 'len': 10},
                  ],
                  'texts': ['Nội dung 1.'],
                },
          ),
        );
      },
    ),
  );
  return ParseClient(dio: dio);
}

void main() {
  group('parse_client_timeout_va_loi_truyen_qua', () {
    test('parse_url_timeout_nem_dio_exception', () async {
      final client = _stubParse(
        error: DioException(
          requestOptions: RequestOptions(path: '/parse'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      expect(
        () => client.parseUrl('https://truyen.example.com/x'),
        throwsA(isA<DioException>()),
      );
    });

    test('parse_url_server_500_nem_dio_exception', () async {
      final client = _stubParse(statusCode: 500);
      expect(
        () => client.parseUrl('https://truyen.example.com/x'),
        throwsA(isA<DioException>()),
      );
    });

    test('parse_url_trim_khoang_trang_thua', () async {
      final client = _stubParse();
      final result = await client.parseUrl('  https://truyen.example.com/x  ');
      expect(result.chapters.length, 1);
    });

    test('parse_text_dai_thanh_cong', () async {
      final longText = 'Chương 1: Mở đầu. ${'Nội dung rất dài. ' * 500}';
      final client = _stubParse(
        json: {
          'chapters': [
            {'title': 'Chương 1', 'len': longText.length},
          ],
          'texts': [longText],
        },
      );
      final result = await client.parseText(longText);
      expect(result.texts.first, longText);
    });

    test('parse_result_text_of_ngoai_pham_vi_tra_null', () {
      final result = makeSampleParseResult();
      expect(result.textOf(-1), isNull);
      expect(result.textOf(99), isNull);
      expect(result.textOf(0), isNotNull);
    });

    test('parse_result_json_thieu_truong_khong_crash', () {
      const empty = ParseResult(chapters: [], texts: []);
      expect(empty.chapters, isEmpty);
      final partial = ParseResult.fromJson(const {'chapters': 'sai-kieu'});
      expect(partial.chapters, isEmpty);
      expect(partial.texts, isEmpty);
    });

    test('chapter_info_json_thieu_len_mac_dinh_0', () {
      final info = ChapterInfo.fromJson(const {'title': 'C1'});
      expect(info.length, 0);
      final noTitle = ChapterInfo.fromJson(const {});
      expect(noTitle.title, isEmpty);
    });
  });

  group('ensure_chapter_audio_cache_va_fallback', () {
    test('ensure_chapter_audio_cache_hit_khong_goi_chain', () async {
      final cache = FakeAudioCache();
      const text = 'Nội dung đã cache.';
      await cache.storeAudio(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        text: text,
        voice: 'Trúc Ly',
        speed: 1.0,
        chapterUrl: 'u#chapter=0',
        extension: 'mp3',
      );
      final chain = FallbackChain(providers: {
        'Vieneu': FakeTtsProvider('Vieneu'),
        'Kokoro': FakeTtsProvider('Kokoro'),
      });
      final cached = await ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: text,
        chapterUrl: 'u#chapter=0',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'Trúc Ly',
        speedFor: (_) => 1.0,
      );
      expect(cached.bytes, const [1, 2, 3]);
      expect(
        (chain.providers['Vieneu']! as FakeTtsProvider).synthesizeCalls,
        0,
      );
    });

    test('ensure_chapter_audio_miss_goi_chain_va_luu_cache', () async {
      final cache = FakeAudioCache();
      final vieneu = FakeTtsProvider(
        'Vieneu',
        bytes: Uint8List.fromList(const [0x49, 0x44, 0x33]),
      );
      final chain = FallbackChain(
        providers: {'Vieneu': vieneu, 'Kokoro': FakeTtsProvider('Kokoro')},
      );
      const text = 'Chương mới chưa cache.';
      final first = await ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: text,
        chapterUrl: 'u#chapter=1',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'Trúc Ly',
        speedFor: (_) => 1.0,
      );
      expect(vieneu.synthesizeCalls, 1);
      expect(first.meta.voice, 'Trúc Ly');

      // Lan 2 phai hit cache (khong goi chain nua).
      final second = await ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: text,
        chapterUrl: 'u#chapter=1',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'Trúc Ly',
        speedFor: (_) => 1.0,
      );
      expect(vieneu.synthesizeCalls, 1);
      expect(second.bytes, first.bytes);
    });

    test('ensure_chapter_audio_fallback_luu_dung_voice_thang', () async {
      final cache = FakeAudioCache();
      final chain = FallbackChain(providers: {
        'Vieneu': FakeTtsProvider(
          'Vieneu',
          failWith: DioException(requestOptions: RequestOptions(path: '/tts')),
        ),
        'Kokoro': FakeTtsProvider(
          'Kokoro',
          bytes: Uint8List.fromList(const [0x49, 0x44, 0x33]),
        ),
      });
      const text = 'Chương fallback.';
      final cached = await ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: text,
        chapterUrl: 'u#chapter=2',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (p) => p == 'Vieneu' ? 'Trúc Ly' : 'diem_trinh',
        speedFor: (_) => 1.0,
      );
      // Luu voi voice cua provider thang (Kokoro), khong phai voice primary.
      expect(cached.meta.voice, 'diem_trinh');
    });

    test('ensure_chapter_audio_bao_cao_tien_do_0_den_1', () async {
      final cache = FakeAudioCache();
      final chain = FallbackChain(providers: {
        'Vieneu': FakeTtsProvider('Vieneu'),
        'Kokoro': FakeTtsProvider('Kokoro'),
      });
      final progresses = <double>[];
      await ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: 'Chương tiến độ.',
        chapterUrl: 'u#chapter=3',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'v',
        speedFor: (_) => 1.0,
        onProgress: progresses.add,
      );
      expect(progresses, isNotEmpty);
      // FakeTtsProvider bao cao 1.0 duy nhat; FallbackChain 2 provider tinh
      // (0 + 1.0) / 2 = 0.5 (provider dau chiem nua dau tien do).
      expect(progresses.last, 0.5);
    });
  });

  group('extension_for_audio_bytes_bien', () {
    test('extension_wav_riff_day_du', () {
      final b = Uint8List(16);
      b[0] = 0x52;
      b[1] = 0x49;
      b[2] = 0x46;
      b[3] = 0x46;
      b[8] = 0x57;
      b[9] = 0x41;
      b[10] = 0x56;
      b[11] = 0x45;
      expect(extensionForAudioBytes(b), 'wav');
    });

    test('extension_riff_thieu_wave_thanh_mp3', () {
      final b = Uint8List(12);
      b[0] = 0x52;
      b[1] = 0x49;
      b[2] = 0x46;
      b[3] = 0x46;
      expect(extensionForAudioBytes(b), 'mp3');
    });

    test('extension_mp3_frame_sync_ff_fb', () {
      expect(
        extensionForAudioBytes(Uint8List.fromList(const [0xFF, 0xFB, 0x90])),
        'mp3',
      );
    });

    test('extension_1_byte_thanh_mp3', () {
      expect(extensionForAudioBytes(Uint8List.fromList(const [0xFF])), 'mp3');
    });
  });
}
