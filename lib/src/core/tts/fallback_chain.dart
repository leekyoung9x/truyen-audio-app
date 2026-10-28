import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'tts_provider.dart';

/// Thu tu uu tien provider do user chon trong Settings.
enum ProviderOrder {
  /// Vieneu truoc, loi/timeout thi chuyen Kokoro.
  vieneuFirst,

  /// Kokoro truoc, loi/timeout thi chuyen Vieneu.
  kokoroFirst,
}

/// Chuoi fallback: thu tung provider theo thu tu cho den khi thanh cong.
///
/// - Loi mang, timeout, 5xx, audio rong -> tu dong chuyen provider tiep theo.
/// - Loi du lieu (text rong / qua dai) van nem thang de UI bao loi ngay.
/// - Chi nem [TtsAllFailedException] khi TAT CA provider deu that bai.
class FallbackChain {
  FallbackChain({required this.providers});

  /// Map ten provider -> instance (vd: {'Vieneu': ..., 'Kokoro': ...}).
  final Map<String, TtsProvider> providers;

  Future<Uint8List> synthesize({
    required String text,
    required ProviderOrder order,
    required String Function(String providerName) voiceFor,
    required double Function(String providerName) speedFor,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final result = await synthesizeWithProvider(
      text: text,
      order: order,
      voiceFor: voiceFor,
      speedFor: speedFor,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return result.bytes;
  }

  /// Giong [synthesize] nhung tra them ten provider da thang,
  /// de caller luu cache voi dung voice da dung (quan trong khi fallback
  /// doi sang provider 2 co voice id khac).
  Future<({Uint8List bytes, String provider})> synthesizeWithProvider({
    required String text,
    required ProviderOrder order,
    required String Function(String providerName) voiceFor,
    required double Function(String providerName) speedFor,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final sequence = order == ProviderOrder.vieneuFirst
        ? const ['Vieneu', 'Kokoro']
        : const ['Kokoro', 'Vieneu'];

    Object? lastError;
    for (var i = 0; i < sequence.length; i++) {
      final providerName = sequence[i];
      final provider = providers[providerName];
      if (provider == null) continue;
      try {
        final bytes = await provider.synthesize(
          text: text,
          voice: voiceFor(providerName),
          speed: speedFor(providerName),
          // Tien do gop: provider thu 2 tiep tuc tu 50%.
          onProgress: onProgress == null
              ? null
              : (p) => onProgress((i + p) / sequence.length),
          cancelToken: cancelToken,
        );
        return (bytes: bytes, provider: providerName);
      } on ArgumentError {
        // Loi du lieu dau vao -> khong fallback, bao loi ngay.
        rethrow;
      } on DioException catch (e) {
        lastError = e;
        debugPrint('FallbackChain: $providerName that bai ($e), chuyen provider.');
        continue;
      } on StateError catch (e) {
        lastError = e;
        debugPrint('FallbackChain: $providerName audio loi ($e), chuyen provider.');
        continue;
      }
    }
    throw TtsAllFailedException(lastError);
  }
}

/// Tat ca provider trong chuoi deu that bai.
class TtsAllFailedException implements Exception {
  TtsAllFailedException(this.cause);

  final Object? cause;

  @override
  String toString() =>
      'Tat ca TTS provider deu that bai. Chi tiet: ${cause ?? 'khong ro'}.';
}
