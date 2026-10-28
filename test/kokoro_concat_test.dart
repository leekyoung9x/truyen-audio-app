import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/config.dart';
import 'package:truyen_audio_app/src/core/tts/kokoro_provider.dart';

/// Adapter dem so request dong thoi de kiem chung gioi han song song <= 4.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.body);

  final List<int> body;
  int inFlight = 0;
  int maxInFlight = 0;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    inFlight--;
    return ResponseBody.fromBytes(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('KokoroProvider chunk + concat (mock Dio)', () {
    test('nhieu chunk: song song <= 4, bytes noi dung thu tu', () async {
      // ~30 cau x ~45 ky tu = ~1350 ky tu -> nhieu chunk 400.
      final sentence = 'Mot cau truyen ngan de kiem tra ghep am thanh. ';
      final text = List.filled(30, sentence).join();
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThan(1));

      final adapter = _CountingAdapter([0x49, 0x44, 0x33]); // 'ID3'
      final dio = Dio(
        BaseOptions(
          baseUrl: kokoroBaseUrl,
          responseType: ResponseType.bytes,
        ),
      )..httpClientAdapter = adapter;
      final provider = KokoroProvider(dio: dio);

      final progresses = <double>[];
      final bytes = await provider.synthesize(
        text: text,
        voice: DefaultVoice.kokoro,
        onProgress: progresses.add,
      );

      // Moi chunk tra 3 bytes 'ID3' -> tong = 3 * so chunk, dung thu tu.
      expect(bytes.length, chunks.length * 3);
      expect(bytes.sublist(0, 3), [0x49, 0x44, 0x33]);
      // Gioi han song song theo TextLimits.
      expect(adapter.maxInFlight, lessThanOrEqualTo(TextLimits.kokoroMaxParallel));
      expect(adapter.maxInFlight, greaterThan(1));
      // Tien do ket thuc o 1.0.
      expect(progresses.last, 1.0);
    });

    test('speed bi clamp ve 0.5-1.5 truoc khi gui', () async {
      var sentSpeed = 0.0;
      final dio = Dio(BaseOptions(baseUrl: kokoroBaseUrl));
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
      final provider = KokoroProvider(dio: dio);
      await provider.synthesize(
        text: 'Ngan.',
        voice: DefaultVoice.kokoro,
        speed: 99,
      );
      expect(sentSpeed, 1.5);
    });
  });
}
