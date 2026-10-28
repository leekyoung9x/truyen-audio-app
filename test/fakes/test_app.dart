import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:truyen_audio_app/main.dart';
import 'package:truyen_audio_app/src/core/cache/audio_cache.dart';
import 'package:truyen_audio_app/src/core/parse/parse_client.dart';
import 'package:truyen_audio_app/src/core/tts/kokoro_provider.dart';
import 'package:truyen_audio_app/src/core/tts/tts_provider.dart';
import 'package:truyen_audio_app/src/core/tts/vieneu_provider.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';
import 'package:truyen_audio_app/src/features/player/player_screen.dart';

import 'fake_audio_handler.dart';
import 'fake_tts.dart';

export 'fake_audio_handler.dart';
export 'fake_tts.dart';

/// Fake Vieneu DUNG TYPE THAT de override duoc provider (KHONG goi mang).
class FakeVieneuProvider extends VieneuProvider {
  FakeVieneuProvider({
    List<VoiceInfo>? voices,
    Object? failWith,
    List<int>? bytes,
  }) : _voices = voices ?? const [],
       _failWith = failWith,
       _bytes = bytes,
       super(dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')));

  final List<VoiceInfo> _voices;
  final Object? _failWith;
  final List<int>? _bytes;

  int synthesizeCalls = 0;
  int listVoicesCalls = 0;
  String? lastVoice;
  double? lastSpeed;

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async {
    listVoicesCalls++;
    if (_failWith != null && _voices.isEmpty) throw _failWith;
    return _voices;
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    synthesizeCalls++;
    lastVoice = voice;
    lastSpeed = speed;
    if (_failWith != null) throw _failWith;
    onProgress?.call(1.0);
    return Uint8List.fromList(_bytes ?? const [0x49, 0x44, 0x33, 0x01, 0x02]);
  }
}

/// Fake Kokoro DUNG TYPE THAT de override duoc provider (KHONG goi mang).
class FakeKokoroProvider extends KokoroProvider {
  FakeKokoroProvider({
    List<VoiceInfo>? voices,
    Object? failWith,
    List<int>? bytes,
  }) : _voices = voices ?? const [],
       _failWith = failWith,
       _bytes = bytes,
       super(dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')));

  final List<VoiceInfo> _voices;
  final Object? _failWith;
  final List<int>? _bytes;

  int synthesizeCalls = 0;
  int listVoicesCalls = 0;
  String? lastVoice;
  double? lastSpeed;

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async {
    listVoicesCalls++;
    if (_failWith != null && _voices.isEmpty) throw _failWith;
    return _voices;
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    synthesizeCalls++;
    lastVoice = voice;
    lastSpeed = speed;
    if (_failWith != null) throw _failWith;
    onProgress?.call(1.0);
    return Uint8List.fromList(_bytes ?? const [0x49, 0x44, 0x33, 0x01, 0x02]);
  }
}

/// Ket qua tao app test: container (doc/ghi provider) + fake handler.
class TestApp {
  TestApp(this.container, this.handler);

  final ProviderContainer container;
  final FakeStoryAudioHandler handler;
}

/// Tao container test voi moi dependency bi mock.
///
/// - Audio: [FakeStoryAudioHandler] (KHONG goi AudioService.init that —
///   regression cover cho bug white-screen 2026-10-27: app phai len duoc
///   ngay ca khi khong co AudioService that).
/// - Parse/network: Dio stub (3 chuong mau) hoac [parseClient] truyen vao.
/// - TTS: fake Vieneu/Kokoro mac dinh thanh cong (tra MP3 'ID3').
/// - Cache: [cacheOverride] (mac dinh null = chua khoi tao).
///
/// Test tu pump: `UncontrolledProviderScope(container: app.container, ...)`.
TestApp makeTestApp({
  FakeStoryAudioHandler? handler,
  FakeVieneuProvider? vieneu,
  FakeKokoroProvider? kokoro,
  ParseClient? parseClient,
  AudioCache? cacheOverride,
}) {
  final fakeHandler = handler ?? FakeStoryAudioHandler();
  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWith((ref) => fakeHandler),
      parseClientProvider.overrideWith(
        (ref) => parseClient ?? makeStubParseClient(),
      ),
      vieneuProvider.overrideWith(
        (ref) => vieneu ?? FakeVieneuProvider(voices: defaultVieneuVoices()),
      ),
      kokoroProvider.overrideWith(
        (ref) => kokoro ?? FakeKokoroProvider(voices: defaultKokoroVoices()),
      ),
      audioCacheProvider.overrideWith((ref) => cacheOverride),
    ],
  );
  addTearDown(container.dispose);
  return TestApp(container, fakeHandler);
}

/// Pump app THAT ([TruyenAudioApp]) voi container test.
///
/// Vi `_router` trong main.dart la global singleton giua cac test trong
/// cung file, helper nay LUON dua router ve '/' sau khi pump de moi
/// test bat dau tu trang chu (tranh dinh route tu test truoc).
Future<void> pumpRealApp(WidgetTester tester, TestApp app) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: app.container,
      child: const TruyenAudioApp(),
    ),
  );
  await tester.pumpAndSettle();
  // Reset router global ve '/' (context duoi Router moi go duoc).
  final scaffold = find.byType(Scaffold);
  if (scaffold.evaluate().isNotEmpty) {
    GoRouter.of(tester.element(scaffold.first)).go('/');
    await tester.pumpAndSettle();
  }
}

/// Dieu huong router that sang [location] (dung context duoi Router).
Future<void> routerGo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await tester.pumpAndSettle();
}

/// Danh sach giong mac dinh cho settings test.
List<VoiceInfo> defaultVieneuVoices() => const [
  VoiceInfo(id: 'Trúc Ly', label: 'Trúc Ly (nữ Bắc)'),
  VoiceInfo(id: 'Thiện Minh', label: 'Thiện Minh (nam kể chuyện)'),
];

/// Danh sach giong mac dinh cho settings test.
List<VoiceInfo> defaultKokoroVoices() => const [
  VoiceInfo(id: 'diem_trinh', label: 'diem_trinh'),
  VoiceInfo(id: 'linh_dan', label: 'linh_dan'),
];
