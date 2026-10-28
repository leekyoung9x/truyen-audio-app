import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/convert/chapter_audio.dart';
import 'package:truyen_audio_app/src/core/parse/parse_client.dart';

/// Tao bytes gia lap magic bytes that (khong can doc file that).
Uint8List _riffWav() {
  final b = Uint8List(16);
  b[0] = 0x52; // R
  b[1] = 0x49; // I
  b[2] = 0x46; // F
  b[3] = 0x46; // F
  b[8] = 0x57; // W
  b[9] = 0x41; // A
  b[10] = 0x56; // V
  b[11] = 0x45; // E
  return b;
}

void main() {
  group('extensionForAudioBytes (magic bytes)', () {
    test('RIFF....WAVE -> wav', () {
      expect(extensionForAudioBytes(_riffWav()), 'wav');
    });

    test('ID3 -> mp3', () {
      expect(
        extensionForAudioBytes(Uint8List.fromList(const [0x49, 0x44, 0x33])),
        'mp3',
      );
    });

    test('MP3 frame sync 0xFFEx -> mp3', () {
      expect(
        extensionForAudioBytes(Uint8List.fromList(const [0xFF, 0xF3, 0x84])),
        'mp3',
      );
    });

    test('la -> mp3 (mac dinh an toan)', () {
      expect(extensionForAudioBytes(Uint8List(0)), 'mp3');
    });
  });

  group('ParseClient guard (khong can server that)', () {
    test('parseUrl tu choi scheme file://', () async {
      final client = ParseClient(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')),
      );
      expect(
        () => client.parseUrl('file:///etc/passwd'),
        throwsArgumentError,
      );
    });

    test('parseUrl tu choi text khong phai URL', () async {
      final client = ParseClient(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')),
      );
      expect(
        () => client.parseUrl('Chuong 1: khong phai url'),
        throwsArgumentError,
      );
    });

    test('parseText tu choi text rong', () async {
      final client = ParseClient(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')),
      );
      expect(() => client.parseText('   '), throwsArgumentError);
    });
  });
}
