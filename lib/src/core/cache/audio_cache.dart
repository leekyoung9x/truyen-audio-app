import 'dart:async';
import 'dart:io' show Directory, File;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show Uint8List, immutable, kIsWeb, visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata 1 file audio da cache (luu trong Hive box 'audio_meta').
@immutable
class AudioMeta {
  const AudioMeta({
    required this.key,
    required this.fileName,
    required this.chapterUrl,
    required this.voice,
    required this.speed,
    required this.createdAt,
  });

  /// md5(text+voice+speed) — trung voi ten file.
  final String key;
  final String fileName;

  /// URL chuong goc (de nhom cac chuong cung truyen).
  final String chapterUrl;
  final String voice;
  final double speed;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'key': key,
    'fileName': fileName,
    'chapterUrl': chapterUrl,
    'voice': voice,
    'speed': speed,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AudioMeta.fromMap(Map<dynamic, dynamic> map) {
    return AudioMeta(
      key: map['key'].toString(),
      fileName: map['fileName'].toString(),
      chapterUrl: map['chapterUrl'].toString(),
      voice: map['voice'].toString(),
      speed: (map['speed'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'].toString()),
    );
  }
}

/// 1 ban audio da cache: bytes + metadata mo ta.
@immutable
class CachedAudio {
  const CachedAudio({
    required this.meta,
    required this.bytes,
    this.filePath,
  });

  final AudioMeta meta;

  /// Bytes audio day du (doc tu file tren native, tu IndexedDB tren Web).
  final Uint8List bytes;

  /// Duong dan file that — chi co tren native (Web = null).
  final String? filePath;

  /// Duoi file ('wav' | 'mp3') suy tu ten file trong metadata.
  String get extension {
    final name = meta.fileName;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : 'mp3';
  }
}

/// Cache audio: metadata trong Hive + bytes audio.
///
/// - Native (Android/iOS/desktop): bytes luu thanh file trong thu muc cache
///   (path_provider), metadata luu Hive box 'audio_meta'.
/// - Web: `dart:io` File/Directory chi la stub (goi la throw), path_provider
///   tra path ao -> luu bytes truc tiep vao Hive box 'audio_blob'
///   (IndexedDB), khong dong den file/path native.
class AudioCache {
  AudioCache._(this._dir, this._box, [this._blobBox]);

  final Directory? _dir;
  final Box<dynamic> _box;
  final Box<dynamic>? _blobBox;

  static const String boxName = 'audio_meta';

  /// Box luu bytes audio tren Web (IndexedDB). Native khong dung.
  static const String blobBoxName = 'audio_blob';

  /// Co dang o che do Web (bytes luu Hive) khong.
  bool get isWebBlob => _blobBox != null;

  /// Khoi tao: mo Hive box + thu muc cache audio.
  ///
  /// Web: khong goi path_provider / Directory / File (stub -> throw),
  /// chi mo 2 Hive box (metadata + bytes).
  static Future<AudioCache> init() async {
    final box = await Hive.openBox<dynamic>(boxName);
    if (kIsWeb) {
      final blobBox = await Hive.openBox<dynamic>(blobBoxName);
      return AudioCache._(null, box, blobBox);
    }
    final appDir = await getApplicationDocumentsDirectory();
    // Chuan hoa: bo '/' thua o cuoi de noi path khong bi '//'.
    final cleanPath =
        '${appDir.path}/audio_cache'.replaceAll(RegExp(r'/+$'), '');
    final dir = Directory(cleanPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return AudioCache._(dir, box);
  }

  /// Tinh key md5(text + voice + speed). De public de test / tai su dung.
  @visibleForTesting
  static String cacheKey({
    required String text,
    required String voice,
    required double speed,
  }) {
    return md5.convert('${text}_${voice}_$speed'.codeUnits).toString();
  }

  /// Key hop le = md5 hex 32 ky tu (do ta tu sinh, khong nhan tu user).
  static final _keyRegExp = RegExp(r'^[a-f0-9]{32}$');

  /// Duoi file hop le: chi chu thuong + so (wav/mp3). Chan path traversal
  /// ('../', '/') tu caller truyen extension la.
  static final _extRegExp = RegExp(r'^[a-z0-9]+$');

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

  File _fileFor(String key, String extension) {
    _checkKey(key);
    _checkExtension(extension);
    final dir = _dir;
    if (dir == null) {
      throw StateError('AudioCache native khong kha dung tren Web.');
    }
    return File('${dir.path}/$key.$extension');
  }

  /// Tra ve ban audio da cache, null neu chua co.
  ///
  /// - Native: doc file tu disk (bytes de phat online qua file path).
  /// - Web: doc bytes tu Hive box 'audio_blob' (IndexedDB).
  Future<CachedAudio?> lookupAudio({
    required String text,
    required String voice,
    required double speed,
    required String extension,
  }) async {
    _checkExtension(extension);
    final key = cacheKey(text: text, voice: voice, speed: speed);
    return getByKey(key);
  }

  /// Doc truc tiep theo cache key (md5 hex). Null neu khong co ban ghi.
  Future<CachedAudio?> getByKey(String key) async {
    _checkKey(key);
    final metaRaw = _box.get(key);
    if (metaRaw is! Map<dynamic, dynamic>) return null;
    final meta = AudioMeta.fromMap(metaRaw);
    final blobBox = _blobBox;
    if (blobBox != null) {
      final bytesRaw = blobBox.get(key);
      if (bytesRaw is! List<dynamic>) return null;
      return CachedAudio(
        meta: meta,
        bytes: Uint8List.fromList(bytesRaw.cast<int>()),
      );
    }
    final dot = meta.fileName.lastIndexOf('.');
    final ext = dot >= 0 ? meta.fileName.substring(dot + 1) : 'mp3';
    final file = _fileFor(key, ext);
    if (!await file.exists()) return null;
    return CachedAudio(
      meta: meta,
      bytes: await file.readAsBytes(),
      filePath: file.path,
    );
  }

  /// Tra ve file audio da cache, null neu chua co.
  ///
  /// Chi dung tren native (Web khong co file that -> luon null).
  /// Code moi nen dung [lookupAudio] (chay ca 2 nen).
  Future<File?> lookup({
    required String text,
    required String voice,
    required double speed,
    required String extension,
  }) async {
    final hit = await lookupAudio(
      text: text,
      voice: voice,
      speed: speed,
      extension: extension,
    );
    final path = hit?.filePath;
    if (path == null) return null;
    return File(path);
  }

  /// Luu bytes audio vao cache + ghi metadata Hive.
  ///
  /// Tra ve [CachedAudio] (bytes + filePath tren native, filePath null
  /// tren Web). Giu tuong thich voi code cu qua [storeFile].
  Future<CachedAudio> storeAudio({
    required Uint8List bytes,
    required String text,
    required String voice,
    required double speed,
    required String chapterUrl,
    required String extension,
  }) async {
    _checkExtension(extension);
    final key = cacheKey(text: text, voice: voice, speed: speed);
    final meta = AudioMeta(
      key: key,
      fileName: '$key.$extension',
      chapterUrl: chapterUrl,
      voice: voice,
      speed: speed,
      createdAt: DateTime.now(),
    );
    final blobBox = _blobBox;
    if (blobBox != null) {
      await blobBox.put(key, bytes);
      await _box.put(key, meta.toMap());
      return CachedAudio(meta: meta, bytes: bytes);
    }
    final file = _fileFor(key, extension);
    await file.writeAsBytes(bytes, flush: true);
    await _box.put(key, meta.toMap());
    return CachedAudio(meta: meta, bytes: bytes, filePath: file.path);
  }

  /// Luu bytes audio vao cache + ghi metadata Hive (chi native).
  ///
  /// Code moi nen dung [storeAudio] (chay ca 2 nen).
  Future<File> store({
    required Uint8List bytes,
    required String text,
    required String voice,
    required double speed,
    required String chapterUrl,
    required String extension,
  }) async {
    final cached = await storeAudio(
      bytes: bytes,
      text: text,
      voice: voice,
      speed: speed,
      chapterUrl: chapterUrl,
      extension: extension,
    );
    final path = cached.filePath;
    if (path == null) {
      throw StateError('store() (File) khong ho tro tren Web; dung storeAudio().');
    }
    return File(path);
  }

  /// Tat ca metadata (de hien thi / xoa cache theo truyen).
  List<AudioMeta> getAllMeta() {
    return _box.values
        .whereType<Map<dynamic, dynamic>>()
        .map(AudioMeta.fromMap)
        .toList();
  }

  /// Xoa 1 ban cache (file + metadata). Key phai la md5 hex do ta sinh.
  Future<void> remove(String key) async {
    _checkKey(key);
    final meta = _box.get(key);
    if (meta is Map<dynamic, dynamic>) {
      // Chi xoa file nam TRONG cache dir voi ten md5 hop le (chan traversal
      // neu metadata bi sua tay tu ben ngoai).
      final rawName = meta['fileName'].toString();
      final fileName = rawName.split('/').last.split('\\').last;
      final dot = fileName.lastIndexOf('.');
      if (dot > 0) {
        final nameKey = fileName.substring(0, dot);
        final ext = fileName.substring(dot + 1);
        if (_keyRegExp.hasMatch(nameKey) && _extRegExp.hasMatch(ext)) {
          final dir = _dir;
          if (dir != null) {
            final file = File('${dir.path}/$fileName');
            if (await file.exists()) await file.delete();
          }
        }
      }
    }
    await _blobBox?.delete(key);
    await _box.delete(key);
  }

  /// Xoa toan bo cache.
  Future<void> clear() async {
    final dir = _dir;
    if (dir != null && await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    }
    await _blobBox?.clear();
    await _box.clear();
  }
}
