import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../network/dio_client.dart';
import 'tts_provider.dart';

/// Provider DU PHONG (v8): Vieneu TTS server.
///
/// - `GET /voices` -> 25 giong (da verify ngay 2026-10-27).
/// - `POST /tts` body `{"text","voice"}` (text toi da 12000 ky tu)
///   -> file WAV 48kHz (magic bytes RIFF/WAVE).
class VieneuProvider implements TtsProvider {
  VieneuProvider({Dio? dio})
    : _dio = dio ?? createDioClient(
        // Web: qua proxy cung origin (`/api`), tranh mixed-content/CORS.
        baseUrl: kIsWeb ? webProxyBaseUrl : vieneuBaseUrl,
        timeoutSeconds: ApiTimeouts.vieneuTts,
      );

  final Dio _dio;
  List<VoiceInfo>? _cachedVoices;

  @override
  String get name => 'Vieneu';

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async {
    if (_cachedVoices != null && !forceRefresh) return _cachedVoices!;
    // Web: proxy tach 2 server thanh 2 path (GET /api/voices/vieneu).
    final res = await _dio.get<Map<String, dynamic>>(
      kIsWeb ? '/voices/vieneu' : '/voices',
    );
    final data = res.data ?? const <String, dynamic>{};
    // Server tra {"voices":[{id,label},...]}.
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
    if (trimmed.length > TextLimits.vieneuMaxChars) {
      throw ArgumentError(
        'Text dai ${trimmed.length} ky tu, vuot qua gioi han '
        '${TextLimits.vieneuMaxChars} cua Vieneu.',
      );
    }
    // Vieneu hien khong nhan tham so toc do -> giu mac dinh server.
    // Web: gui them 'provider' hint de proxy chi goi 8001 (khong fallback
    // nham sang Kokoro, giu dung semantics FallbackChain o client).
    final res = await _dio.post<List<int>>(
      '/tts',
      data: kIsWeb
          ? {'text': trimmed, 'voice': voice, 'provider': 'vieneu'}
          : {'text': trimmed, 'voice': voice},
      options: Options(responseType: ResponseType.bytes),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        // Tien do upload chi la uoc luong nhe (text ngan).
        if (total > 0) onProgress?.call(0.1 * sent / total);
      },
    );
    onProgress?.call(1.0);
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Vieneu tra ve audio rong.');
    }
    return Uint8List.fromList(bytes);
  }
}
