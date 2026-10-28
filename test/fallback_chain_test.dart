import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/tts/fallback_chain.dart';
import 'package:truyen_audio_app/src/core/tts/kokoro_provider.dart';
import 'package:truyen_audio_app/src/core/tts/tts_provider.dart';

/// Fake TTS provider cho test fallback: dieu khien duoc thanh/bai.
class _FakeProvider implements TtsProvider {
  _FakeProvider(this._name, {this.failWith, this.bytes});

  final String _name;
  final Object? failWith;
  final Uint8List? bytes;

  @override
  String get name => _name;

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async =>
      const [];

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (failWith != null) throw failWith!;
    return bytes ?? Uint8List.fromList(const [1, 2, 3]);
  }
}

Uint8List _bytes(List<int> xs) => Uint8List.fromList(xs);

void main() {
  group('FallbackChain (Vieneu -> Kokoro khi timeout)', () {
    test('dung Vieneu khi Vieneu thanh cong', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider('Vieneu', bytes: _bytes([1])),
        'Kokoro': _FakeProvider('Kokoro', bytes: _bytes([2])),
      });
      final won = await chain.synthesizeWithProvider(
        text: 'Xin chao',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'voice',
        speedFor: (_) => 1.0,
      );
      expect(won.provider, 'Vieneu');
      expect(won.bytes, [1]);
    });

    test('chuyen Kokoro khi Vieneu timeout (DioException)', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider(
          'Vieneu',
          failWith: DioException(
            requestOptions: RequestOptions(path: '/tts'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        'Kokoro': _FakeProvider('Kokoro', bytes: _bytes([9])),
      });
      final won = await chain.synthesizeWithProvider(
        text: 'Xin chao',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'voice',
        speedFor: (_) => 1.0,
      );
      expect(won.provider, 'Kokoro');
      expect(won.bytes, [9]);
    });

    test('chuyen Kokoro khi Vieneu tra audio rong (StateError)', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider('Vieneu', failWith: StateError('rong')),
        'Kokoro': _FakeProvider('Kokoro', bytes: _bytes([7])),
      });
      final won = await chain.synthesizeWithProvider(
        text: 'Xin chao',
        order: ProviderOrder.vieneuFirst,
        voiceFor: (_) => 'voice',
        speedFor: (_) => 1.0,
      );
      expect(won.provider, 'Kokoro');
    });

    test('KHONG fallback khi loi du lieu (ArgumentError)', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider('Vieneu', failWith: ArgumentError('rong')),
        'Kokoro': _FakeProvider('Kokoro', bytes: _bytes([7])),
      });
      expect(
        () => chain.synthesize(
          text: '',
          order: ProviderOrder.vieneuFirst,
          voiceFor: (_) => 'voice',
          speedFor: (_) => 1.0,
        ),
        throwsArgumentError,
      );
    });

    test('nem TtsAllFailedException khi ca 2 that bai', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider(
          'Vieneu',
          failWith: DioException(requestOptions: RequestOptions(path: '/tts')),
        ),
        'Kokoro': _FakeProvider(
          'Kokoro',
          failWith: DioException(requestOptions: RequestOptions(path: '/tts')),
        ),
      });
      expect(
        () => chain.synthesize(
          text: 'Xin chao',
          order: ProviderOrder.vieneuFirst,
          voiceFor: (_) => 'voice',
          speedFor: (_) => 1.0,
        ),
        throwsA(isA<TtsAllFailedException>()),
      );
    });

    test('kokoroFirst: thu Kokoro truoc', () async {
      final chain = FallbackChain(providers: {
        'Vieneu': _FakeProvider('Vieneu', bytes: _bytes([1])),
        'Kokoro': _FakeProvider('Kokoro', bytes: _bytes([2])),
      });
      final won = await chain.synthesizeWithProvider(
        text: 'Xin chao',
        order: ProviderOrder.kokoroFirst,
        voiceFor: (_) => 'voice',
        speedFor: (_) => 1.0,
      );
      expect(won.provider, 'Kokoro');
    });
  });

  group('KokoroProvider.splitIntoChunks (~400 ky tu)', () {
    test('text ngan giu nguyen 1 chunk', () {
      final chunks = KokoroProvider.splitIntoChunks('Xin chao.');
      expect(chunks, ['Xin chao.']);
    });

    test('text rong tra ve rong', () {
      expect(KokoroProvider.splitIntoChunks('   '), isEmpty);
    });

    test('van dai gan 400 ky tu * N chunk, khong mat chu', () {
      final sentence = 'Day la mot cau truyen ngan de kiem tra cat chunk. ';
      final text = List.filled(30, sentence).join();
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(400));
        expect(c, isNotEmpty);
      }
      // Ghep lai phai giu du noi dung (cat mem theo dau cau + khoang trang).
      final joined = chunks.join(' ');
      for (final word in text.split(' ').where((w) => w.isNotEmpty)) {
        expect(joined, contains(word));
      }
    });

    test('cau don dai hon 400 ky tu bi cat cung ma khong mat ky tu', () {
      final text = 'a' * 950;
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThanOrEqualTo(3));
      expect(chunks.join('').replaceAll(' ', ''), text);
    });
  });
}
