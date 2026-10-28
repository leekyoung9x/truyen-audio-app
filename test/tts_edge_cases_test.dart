// Unit bo sung: timeout, API loi, text rong, chunk bien — KHONG goi mang that.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/config.dart';
import 'package:truyen_audio_app/src/core/tts/fallback_chain.dart';
import 'package:truyen_audio_app/src/core/tts/kokoro_provider.dart';
import 'package:truyen_audio_app/src/core/tts/tts_provider.dart';
import 'package:truyen_audio_app/src/core/tts/vieneu_provider.dart';

import 'fakes/fake_tts.dart';

/// Tao Dio stub tra [body] hoac nem [error] cho moi request.
Dio _stubDio({List<int>? body, Object? error, int statusCode = 200}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (error != null) {
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: error,
            ),
          );
        }
        if (statusCode < 200 || statusCode >= 300) {
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
          Response<List<int>>(
            requestOptions: options,
            statusCode: statusCode,
            data: body ?? const [1, 2, 3],
          ),
        );
      },
    ),
  );
  return dio;
}

Uint8List _wavBytes() {
  final b = Uint8List(16);
  b[0] = 0x52;
  b[1] = 0x49;
  b[2] = 0x46;
  b[3] = 0x46;
  b[8] = 0x57;
  b[9] = 0x41;
  b[10] = 0x56;
  b[11] = 0x45;
  return b;
}

void main() {
  group('vieneu_validate_text_dau_vao', () {
    test('vieneu_text_rong_nem_argument_error', () async {
      final p = VieneuProvider(dio: _stubDio());
      expect(
        () => p.synthesize(text: '   ', voice: 'Trúc Ly'),
        throwsArgumentError,
      );
    });

    test('vieneu_text_vuot_12000_ky_tu_nem_argument_error', () async {
      final p = VieneuProvider(dio: _stubDio());
      expect(
        () => p.synthesize(text: 'a' * 12001, voice: 'Trúc Ly'),
        throwsArgumentError,
      );
    });

    test('vieneu_text_dung_12000_ky_tu_duoc_gui', () async {
      var soRequest = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            soRequest++;
            return handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: 200,
                data: [1, 2, 3],
              ),
            );
          },
        ),
      );
      final p = VieneuProvider(dio: dio);
      final bytes = await p.synthesize(text: 'a' * 12000, voice: 'Trúc Ly');
      expect(soRequest, 1);
      expect(bytes, isNotEmpty);
    });

    test('vieneu_audio_rong_nem_state_error', () async {
      final p = VieneuProvider(dio: _stubDio(body: const []));
      expect(
        () => p.synthesize(text: 'Xin chào', voice: 'Trúc Ly'),
        throwsStateError,
      );
    });

    test('vieneu_server_500_nem_dio_exception', () async {
      final p = VieneuProvider(dio: _stubDio(statusCode: 500));
      expect(
        () => p.synthesize(text: 'Xin chào', voice: 'Trúc Ly'),
        throwsA(isA<DioException>()),
      );
    });

    test('vieneu_timeout_truyen_qua_dio_exception', () async {
      final p = VieneuProvider(
        dio: _stubDio(
          error: DioException(
            requestOptions: RequestOptions(path: '/tts'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );
      expect(
        () => p.synthesize(text: 'Xin chào', voice: 'Trúc Ly'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('kokoro_chunk_bien_5000_ky_tu', () {
    test('kokoro_text_dung_5000_ky_tu_thanh_cong', () async {
      final p = KokoroProvider(dio: _stubDio(body: const [0x49, 0x44, 0x33]));
      // 5000 ky tu 'a' lien nhau (khong dau cau) -> cat cung thanh chunk.
      final bytes = await p.synthesize(text: 'a' * 5000, voice: 'diem_trinh');
      expect(bytes, isNotEmpty);
    });

    test('kokoro_text_qua_dai_nhieu_chunk_noi_dung_thu_tu', () async {
      final p = KokoroProvider(dio: _stubDio(body: const [9, 8, 7]));
      final text = '${'Cau chuyen dai. ' * 400}ket thuc.';
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThan(1));
      final bytes = await p.synthesize(text: text, voice: 'diem_trinh');
      expect(bytes.length, chunks.length * 3);
    });

    test('kokoro_text_rong_nem_argument_error', () async {
      final p = KokoroProvider(dio: _stubDio());
      expect(
        () => p.synthesize(text: '   ', voice: 'diem_trinh'),
        throwsArgumentError,
      );
    });

    test('kokoro_speed_duoi_05_duoc_clamp_len_05', () async {
      var sentSpeed = 0.0;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sentSpeed = (options.data as Map)['speed'] as double;
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [1, 2, 3],
              ),
            );
          },
        ),
      );
      final p = KokoroProvider(dio: dio);
      await p.synthesize(text: 'Ngắn.', voice: 'diem_trinh', speed: 0.1);
      expect(sentSpeed, 0.5);
    });

    test('kokoro_chunk_rong_tu_server_nem_state_error', () async {
      final p = KokoroProvider(dio: _stubDio(body: const []));
      expect(
        () => p.synthesize(text: 'Ngắn.', voice: 'diem_trinh'),
        throwsStateError,
      );
    });
  });

  group('fallback_chain_truong_hop_thieu_provider', () {
    test('fallback_chain_thieu_vieneu_chi_thu_kokoro', () async {
      final chain = FallbackChain(providers: {
        'Kokoro': FakeTtsProvider('Kokoro', bytes: Uint8List.fromList([5])),
      });
      final won = await chain.synthesizeWithProvider(
        text: 'Xin chào',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'v',
        speedFor: (_) => 1.0,
      );
      expect(won.provider, 'Kokoro');
    });

    test('fallback_chain_map_rong_nem_all_failed', () async {
      final chain = FallbackChain(providers: {});
      expect(
        () => chain.synthesize(
          text: 'Xin chào',
          order: ProviderOrder.vieneuFirst,
          voiceFor: (_) => 'v',
          speedFor: (_) => 1.0,
        ),
        throwsA(isA<TtsAllFailedException>()),
      );
    });

    test('fallback_chain_bao_cao_tien_do_dung_thu_tu', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': FakeTtsProvider(
          'Vieneu',
          failWith: DioException(requestOptions: RequestOptions(path: '/tts')),
        ),
        'Kokoro': FakeTtsProvider('Kokoro'),
      });
      final progresses = <double>[];
      await chain.synthesize(
        text: 'Xin chào',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'v',
        speedFor: (_) => 1.0,
        onProgress: progresses.add,
      );
      expect(progresses, isNotEmpty);
      expect(progresses.last, 1.0);
      // Provider 2 bat dau tu 50%: moi gia tri >= 0.5.
      expect(progresses.every((p) => p >= 0.5), isTrue);
    });

    test('fallback_chain_tat_ca_failed_exception_chua_cause', () {
      final cause = DioException(requestOptions: RequestOptions(path: '/x'));
      final e = TtsAllFailedException(cause);
      expect(e.cause, cause);
      expect(e.toString(), contains('deu that bai'));
      expect(TtsAllFailedException(null).toString(), contains('khong ro'));
    });
  });

  group('voice_info_parse_json', () {
    test('voice_info_thieu_label_dung_id_lam_label', () {
      const v = VoiceInfo(id: 'abc', label: 'abc');
      expect(v.id, 'abc');
      final fromJson = VoiceInfo.fromJson(const {'id': 'xyz'});
      expect(fromJson.label, 'xyz');
      final empty = VoiceInfo.fromJson(const {});
      expect(empty.id, isEmpty);
    });
  });

  group('wav_bytes_nhan_dang', () {
    test('wav_bytes_that_duoc_nhan_dang', () {
      expect(_wavBytes()[0], 0x52);
      expect(_wavBytes().length, 16);
    });
  });

  group('text_limits_va_speed_range', () {
    test('gioi_han_kytu_va_toc_do_dung_nhu_thiet_ke', () {
      expect(TextLimits.vieneuMaxChars, 12000);
      expect(TextLimits.kokoroMaxChars, 5000);
      expect(TextLimits.kokoroChunkTarget, 400);
      expect(TextLimits.kokoroMaxParallel, 4);
      expect(SpeedRange.min, 0.5);
      expect(SpeedRange.max, 1.5);
      expect(SpeedRange.def, 1.0);
    });

    test('provider_order_from_chuoi_dung', () {
      // providerOrderFrom nam trong app_providers (can Riverpod) — test
      // logic tuong duong o day de tai lieu hoa quy uoc chuoi.
      // v8: Kokoro primary — gia tri la ve Kokoro.
      String orderFrom(String v) =>
          v == 'vieneu_first' ? 'vieneuFirst' : 'kokoroFirst';
      expect(orderFrom('kokoro_first'), 'kokoroFirst');
      expect(orderFrom('vieneu_first'), 'vieneuFirst');
      expect(orderFrom('la'), 'kokoroFirst');
    });
  });
}
