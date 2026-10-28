import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:truyen_audio_app/src/core/cache/audio_cache.dart';

/// Test [AudioCache] THẬT (logic that) nhung chay tren thu muc TAM.
//
// !!! CHI DUNG TRONG `test` THUONG, KHONG DUNG TRONG testWidgets !!!
//
// Phat hien 2026-10-27 (Flutter 3.47): moi async disk IO (createTemp,
// Hive.openBox...) TREO trong testWidgets zone. Widget test can cache thi
// dung [FakeAudioCache] (memory, sync) thay vi mo Hive that.
//
// Cach dung trong unit test thuan:
//
//   late Directory tmp;
//   setUpAll(() => tmp = initTestHive());
//   tearDownAll(() => disposeTestHive(tmp));
//   setUp(() async => (await openTestCache()).clear());
//
// - Native: mock path_provider -> tra tmp.path; [AudioCache.init] mo box
//   that tren disk tam (khong cham Hive that cua app).
// - Web (kIsWeb): [AudioCache.init] chi mo 2 box (meta + blob).

/// Khoi tao Hive cho test: mock path_provider -> thu muc tam, Hive.init.
///
/// Tra ve thu muc tam de tearDown xoa. SYNC (khong treo trong testWidgets).
Directory initTestHive() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final name =
      'audio_cache_test_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final tmp = Directory('${Directory.systemTemp.path}/$name');
  tmp.createSync(recursive: true);
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tmp.path;
        }
        return null;
      });
  Hive.init(tmp.path);
  return tmp;
}

/// Dong box + xoa box tren disk + go mock kenh path_provider + xoa thu muc.
Future<void> disposeTestHive(Directory tmp) async {
  await Hive.deleteFromDisk();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  if (await tmp.exists()) {
    await tmp.delete(recursive: true);
  }
}

/// Mo cache that tren Hive test (goi sau initTestHive).
Future<AudioCache> openTestCache() => AudioCache.init();

/// Cache gia lap IN-MEMORY, dung cho testWidgets (KHONG cham Hive/disk).
///
/// Giu nguyen moi guard/validation quan trong cua [AudioCache] that:
/// - key phai la md5 hex 32 ky tu (nem ArgumentError neu sai),
/// - extension chi chua [a-z0-9] (chan path traversal)
///
/// để test van cover duoc cac guard nay.
class FakeAudioCache implements AudioCache {
  FakeAudioCache();

  final Map<String, Map<String, dynamic>> _meta = {};
  final Map<String, List<int>> _bytes = {};

  @override
  bool get isWebBlob => false;

  static final RegExp _keyRegExp = RegExp(r'^[a-f0-9]{32}$');
  static final RegExp _extRegExp = RegExp(r'^[a-z0-9]+$');

  static void _checkKey(String key) {
    if (!_keyRegExp.hasMatch(key)) {
      throw ArgumentError('Cache key khong hop le.');
    }
  }

  static void _checkExtension(String extension) {
    if (!_extRegExp.hasMatch(extension)) {
      throw ArgumentError('Duoi file cache khong hop le: $extension');
    }
  }

  @override
  Future<CachedAudio?> lookupAudio({
    required String text,
    required String voice,
    required double speed,
    required String extension,
  }) async {
    _checkExtension(extension);
    final key = AudioCache.cacheKey(text: text, voice: voice, speed: speed);
    return getByKey(key);
  }

  @override
  Future<CachedAudio?> getByKey(String key) async {
    _checkKey(key);
    final metaRaw = _meta[key];
    if (metaRaw == null) return null;
    final bytesRaw = _bytes[key];
    if (bytesRaw == null) return null;
    return CachedAudio(
      meta: AudioMeta.fromMap(metaRaw),
      bytes: Uint8List.fromList(bytesRaw),
      filePath: '/mem/$key.mp3',
    );
  }

  /// `lookup` that chi dung tren native (Web luon null). Fake nay tra ve
  /// null de test khong phu thuoc file that.
  @override
  Future<File?> lookup({
    required String text,
    required String voice,
    required double speed,
    required String extension,
  }) async =>
      null;

  @override
  Future<CachedAudio> storeAudio({
    required Uint8List bytes,
    required String text,
    required String voice,
    required double speed,
    required String chapterUrl,
    required String extension,
  }) async {
    _checkExtension(extension);
    final key = AudioCache.cacheKey(text: text, voice: voice, speed: speed);
    final meta = AudioMeta(
      key: key,
      fileName: '$key.$extension',
      chapterUrl: chapterUrl,
      voice: voice,
      speed: speed,
      createdAt: DateTime.now(),
    );
    _meta[key] = meta.toMap().map(
      (k, v) => MapEntry<String, dynamic>(k.toString(), v),
    );
    _bytes[key] = bytes.toList();
    return CachedAudio(
      meta: meta,
      bytes: bytes,
      filePath: '/mem/$key.$extension',
    );
  }

  @override
  Future<File> store({
    required Uint8List bytes,
    required String text,
    required String voice,
    required double speed,
    required String chapterUrl,
    required String extension,
  }) async {
    throw UnimplementedError('FakeAudioCache.store khong ho tro File that.');
  }

  @override
  List<AudioMeta> getAllMeta() =>
      _meta.values.map(AudioMeta.fromMap).toList();

  @override
  Future<void> remove(String key) async {
    _checkKey(key);
    _meta.remove(key);
    _bytes.remove(key);
  }

  @override
  Future<void> clear() async {
    _meta.clear();
    _bytes.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
