import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../network/dio_client.dart';
import 'tts_provider.dart';

/// Provider CHINH (v8): Kokoro TTS server.
///
/// Gioi han: text 1-5000 ky tu, speed 0.5-1.5, format wav|mp3.
/// Provider nay TU cat [text] thanh chunk ~400 ky tu theo dau cau
/// (. ! ? … xuong dong), goi song song toi da 4 request,
/// roi noi bytes lai (khong chen header giua cac chunk).
///
/// v11 (Web + text dai > 4500 chu): proxy tu cat chunk (server/proxy_server.py
/// v11) nen KHONG cat o client nua (tranh cat 2 lan) — goi progressive
/// `POST /tts_chunk` theo idx (phat ngay chunk 0, progress that theo
/// header X-Chunks) roi noi bytes. Native (direct-IP, khong qua proxy)
/// giu nguyen cat client. Text ngan (< thi nguong) giu single-shot `/tts`.
class KokoroProvider implements TtsProvider {
  KokoroProvider({Dio? dio, String? vieneuVoiceForFallback})
    : _dio = dio ?? createDioClient(
        // Web: qua proxy cung origin (`/api`), tranh mixed-content/CORS.
        // v11: text dai progressive (/tts_chunk) co the mat toi 150s
        // (proxy: 20s + 10s/chunk) -> dung timeout dai cho moi request.
        baseUrl: kIsWeb ? webProxyBaseUrl : kokoroBaseUrl,
        timeoutSeconds: kIsWeb
            ? ApiTimeouts.kokoroLongChapter
            : ApiTimeouts.kokoroChunk,
      ),
      _vieneuVoiceForFallback = vieneuVoiceForFallback;

  final Dio _dio;

  /// Voice Vieneu dung khi proxy fallback chunk loi sang Vieneu (v11).
  /// Wire tu settings o [app_providers] de giu dung giong user chon.
  final String? _vieneuVoiceForFallback;
  List<VoiceInfo>? _cachedVoices;

  @override
  String get name => 'Kokoro';

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async {
    if (_cachedVoices != null && !forceRefresh) return _cachedVoices!;
    // Web: proxy tach 2 server thanh 2 path (GET /api/voices/kokoro).
    final res = await _dio.get<Map<String, dynamic>>(
      kIsWeb ? '/voices/kokoro' : '/voices',
    );
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['voices'];
    final list = raw is List ? raw : const <dynamic>[];
    _cachedVoices = list
        .whereType<Map<String, dynamic>>()
        .map(VoiceInfo.fromJson)
        .toList();
    return _cachedVoices!;
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Text TTS khong duoc rong.');
    }
    final clampedSpeed = speed.clamp(SpeedRange.min, SpeedRange.max).toDouble();

    // v11 Web + text dai: proxy tu cat chunk (tranh cat 2 lan) — chay
    // progressive qua /tts_chunk (Tien do that theo header X-Chunks).
    // Chi ap dung cho Kokoro-first (provider nay); Vieneu-first van di
    // full-text 1 shot (Vieneu chiu duoc 12000 ky tu).
    if (kIsWeb && trimmed.length > TextLimits.proxyChunkThreshold) {
      return _synthesizeViaProxyChunks(
        trimmed,
        voice: voice,
        speed: clampedSpeed,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // Chunk nho -> 1 request duy nhat, khong can chia.
    final chunks = splitIntoChunks(trimmed);
    if (chunks.length == 1) {
      final bytes = await _synthesizeChunk(
        chunks.first,
        voice: voice,
        speed: clampedSpeed,
        cancelToken: cancelToken,
      );
      onProgress?.call(1.0);
      return bytes;
    }

    // Nhieu chunk: chay song song theo batch (toi da 4 request / batch),
    // giu nguyen thu tu chunk khi noi bytes.
    final parts = List<Uint8List?>.filled(chunks.length, null);
    var done = 0;
    for (var start = 0; start < chunks.length; start += TextLimits.kokoroMaxParallel) {
      final end = math.min(start + TextLimits.kokoroMaxParallel, chunks.length);
      final futures = <Future<void>>[];
      for (var i = start; i < end; i++) {
        futures.add(
          _synthesizeChunk(
            chunks[i],
            voice: voice,
            speed: clampedSpeed,
            cancelToken: cancelToken,
          ).then((b) {
            parts[i] = b;
            done++;
            onProgress?.call(done / chunks.length);
          }),
        );
      }
      await Future.wait(futures);
    }
    onProgress?.call(1.0);

    final totalLen = parts.fold<int>(0, (sum, p) => sum + (p?.length ?? 0));
    final out = Uint8List(totalLen);
    var offset = 0;
    for (final part in parts) {
      if (part == null || part.isEmpty) {
        throw StateError('Kokoro tra ve chunk rong.');
      }
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  Future<Uint8List> _synthesizeChunk(
    String chunk, {
    required String voice,
    required double speed,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.post<List<int>>(
      '/tts',
      // Web: gui them 'provider' hint de proxy chi goi 8000 (giu dung
      // voice/speed/format + chunking phia client).
      data: kIsWeb
          ? {
              'text': chunk,
              'voice': voice,
              'speed': speed,
              'format': 'mp3',
              'provider': 'kokoro',
            }
          : {'text': chunk, 'voice': voice, 'speed': speed, 'format': 'mp3'},
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Kokoro tra ve audio rong.');
    }
    return Uint8List.fromList(bytes);
  }

  /// v11 Web + text dai: chay progressive qua proxy `POST /tts_chunk`.
  ///
  /// Proxy tu cat chunk (cung logic [splitIntoChunks] phia server) nen
  /// client KHONG cat nua (tranh cat 2 lan). Xin chunk 0 truoc (co the phat
  /// ngay), doc tong so chunk tu header `X-Chunks` de bao progress that,
  /// roi lay tuan tu cac chunk con lai (song song toi da
  /// [TextLimits.proxyChunkParallel]) va noi bytes. Proxy cu (404) ->
  /// fallback single-shot `/tts` de khong break.
  Future<Uint8List> _synthesizeViaProxyChunks(
    String text, {
    required String voice,
    required double speed,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    Uint8List first;
    int totalChunks;
    try {
      final r = await _dio.post<List<int>>(
        '/tts_chunk',
        data: {
          'text': text,
          'chunk': 0,
          'voice': voice,
          'speed': speed,
          'format': 'mp3',
          // v11: auto de proxy fallback chunk loi sang Vieneu (giu dung
          // giong Vieneu user chon); kokoro-only se 502 ca chuong khi 1
          // chunk hong — te hon nhieu so voi 1 chunk khac giong nhe.
          'provider': 'auto',
          if (_vieneuVoiceForFallback != null)
            'vieneu_voice': _vieneuVoiceForFallback,
          'kokoro_voice': voice,
        },
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      first = _chunkBytes(r, 0);
      totalChunks = _totalChunksOf(r, fallback: 1);
    } on DioException catch (e) {
      // Proxy cu chua co /tts_chunk (404) -> single-shot nhu cu.
      if (e.response?.statusCode == 404) {
        debugPrint('KokoroProvider: proxy chua co /tts_chunk, dung /tts.');
        final bytes = await _synthesizeChunk(
          text.length <= TextLimits.kokoroMaxChars
              ? text
              : text.substring(0, TextLimits.kokoroMaxChars),
          voice: voice,
          speed: speed,
          cancelToken: cancelToken,
        );
        onProgress?.call(1.0);
        return bytes;
      }
      rethrow;
    }
    if (totalChunks <= 1) {
      onProgress?.call(1.0);
      return first;
    }
    final parts = List<Uint8List?>.filled(totalChunks, null)..[0] = first;
    onProgress?.call(1 / totalChunks);
    var done = 1;
    for (var start = 1;
        start < totalChunks;
        start += TextLimits.proxyChunkParallel) {
      final end = math.min(start + TextLimits.proxyChunkParallel, totalChunks);
      final futures = <Future<void>>[];
      for (var i = start; i < end; i++) {
        futures.add(
          _fetchProxyChunk(
            text,
            i,
            voice: voice,
            speed: speed,
            cancelToken: cancelToken,
          ).then((b) {
            parts[i] = b;
            done++;
            onProgress?.call(done / totalChunks);
          }),
        );
      }
      await Future.wait(futures);
    }
    onProgress?.call(1.0);
    return _concatParts(parts);
  }

  /// Tai 1 chunk idx tu proxy (progressive).
  Future<Uint8List> _fetchProxyChunk(
    String text,
    int idx, {
    required String voice,
    required double speed,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.post<List<int>>(
      '/tts_chunk',
      data: {
        'text': text,
        'chunk': idx,
        'voice': voice,
        'speed': speed,
        'format': 'mp3',
        'provider': 'auto',
        if (_vieneuVoiceForFallback != null)
          'vieneu_voice': _vieneuVoiceForFallback,
        'kokoro_voice': voice,
      },
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
    );
    return _chunkBytes(res, idx);
  }

  /// Trich bytes + validate response chunk.
  Uint8List _chunkBytes(Response<List<int>> res, int idx) {
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Kokoro tra ve chunk $idx rong.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Doc tong so chunk tu header X-Chunks (thieu -> 1).
  int _totalChunksOf(Response<List<int>> res, {required int fallback}) {
    final raw = res.headers.value('x-chunks');
    final n = int.tryParse(raw ?? '');
    return (n == null || n < 1) ? fallback : n;
  }

  /// Noi cac chunk thanh 1 buffer (gi full bytes 0).
  Uint8List _concatParts(List<Uint8List?> parts) {
    final totalLen = parts.fold<int>(0, (sum, p) => sum + (p?.length ?? 0));
    final out = Uint8List(totalLen);
    var offset = 0;
    for (final part in parts) {
      if (part == null || part.isEmpty) {
        throw StateError('Kokoro tra ve chunk rong.');
      }
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  /// Cat [text] thanh chunk ~400 ky tu, uu tien cat tai dau cau.
  ///
  /// De public (static) de unit test / tai su dung ma khong can instance.
  /// Dam bao: moi chunk deu non-empty, ghep lai du noi dung (cat mem).
  @visibleForTesting
  static List<String> splitIntoChunks(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length <= TextLimits.kokoroChunkTarget) return [trimmed];

    // Tach so bo theo dau cau + xuong dong, giu lai dau cau o cuoi cau.
    final sentenceRegExp = RegExp(r'[^.!?…\n]+[.!?…\n]+|[^.!?…\n]+$');
    final sentences = sentenceRegExp
        .allMatches(trimmed)
        .map((m) => m.group(0)!.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return [trimmed];

    final chunks = <String>[];
    final buf = StringBuffer();
    for (final sentence in sentences) {
      // Cau don dai hon muc tieu: cat cung theo do dai (khong mat chu).
      if (sentence.length > TextLimits.kokoroChunkTarget) {
        if (buf.isNotEmpty) {
          chunks.add(buf.toString().trim());
          buf.clear();
        }
        var rest = sentence;
        while (rest.length > TextLimits.kokoroChunkTarget) {
          chunks.add(rest.substring(0, TextLimits.kokoroChunkTarget).trim());
          rest = rest.substring(TextLimits.kokoroChunkTarget).trim();
        }
        if (rest.isNotEmpty) {
          if (buf.isEmpty) {
            buf.write(rest);
          } else {
            chunks.add(buf.toString().trim());
            buf.clear();
            buf.write(rest);
          }
        }
        continue;
      }
      final candidate = buf.isEmpty ? sentence : '${buf.toString()} $sentence';
      if (candidate.length <= TextLimits.kokoroChunkTarget) {
        buf.clear();
        buf.write(candidate);
      } else {
        chunks.add(buf.toString().trim());
        buf.clear();
        buf.write(sentence);
      }
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks.where((c) => c.isNotEmpty).toList();
  }
}
