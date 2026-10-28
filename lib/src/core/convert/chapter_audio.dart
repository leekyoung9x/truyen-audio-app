import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../cache/audio_cache.dart';
import '../tts/fallback_chain.dart';

/// Core dung lai duoc cho viec chuyen 1 chuong thanh ban audio.
///
/// - Kiem tra cache truoc (ca .wav lan .mp3, vi provider thang co the khac nhau).
/// - Chua co -> chay [FallbackChain] (Vieneu -> Kokoro hoac nguoc lai),
///   doan dinh dang file tu magic bytes roi luu cache.
/// - Ham nay duoc UI goi cho 1 chuong; v2 tai hang loat offline
///   chi can goi lap lai ham nay cho nhieu chuong (kham KISS).
/// - Tra ve [CachedAudio]: bytes phat duoc ca 2 nen (Web doc tu IndexedDB,
///   native doc tu file qua [CachedAudio.filePath]).
Future<CachedAudio> ensureChapterAudio({
  required AudioCache cache,
  required FallbackChain chain,
  required String text,
  required String chapterUrl,
  required ProviderOrder order,
  required String Function(String providerName) voiceFor,
  required double Function(String providerName) speedFor,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final voicePrimary = voiceFor(
    order == ProviderOrder.vieneuFirst ? 'Vieneu' : 'Kokoro',
  );
  final speedPrimary = speedFor(
    order == ProviderOrder.vieneuFirst ? 'Vieneu' : 'Kokoro',
  );

  // 1. Cache hit? Thu ca 2 duoi vi lan truoc co the thang bang provider khac.
  for (final ext in const ['wav', 'mp3']) {
    final hit = await cache.lookupAudio(
      text: text,
      voice: voicePrimary,
      speed: speedPrimary,
      extension: ext,
    );
    // Chi nhan cache neu dung voice/speed chinh ( tranh lech giong doc ).
    if (hit != null) return hit;
  }

  // 2. Tong hop qua fallback chain. Ghi nho provider thang de luu
  // cache voi dung voice da dung (tranh miss cache khi fallback).
  final won = await chain.synthesizeWithProvider(
    text: text,
    order: order,
    voiceFor: voiceFor,
    speedFor: speedFor,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
  final bytes = won.bytes;
  final usedVoice = voiceFor(won.provider);
  final usedSpeed = speedFor(won.provider);

  // 3. Luu cache voi duoi file doan tu magic bytes.
  final extension = extensionForAudioBytes(bytes);
  return cache.storeAudio(
    bytes: bytes,
    text: text,
    voice: usedVoice,
    speed: usedSpeed,
    chapterUrl: chapterUrl,
    extension: extension,
  );
}

/// Prefetch 1 chuong cho _prepare nen (v12): KHONG BAO GIO throw.
///
/// - Thanh cong -> tra [CachedAudio] (da luu cache).
/// - Timeout ([TimeoutException]) -> doi [retryDelay] roi thu lai 1 lan
///   (backoff cho chunk timeout); van loi -> log + tra null.
/// - Loi khac (mang, TTS hong het) -> log + tra null ngay (khong retry).
/// - Caller danh dau chuong loi (progress -1, failedChapters) va hien
///   notice nhe — TUYET DOI khong set _error do, khong chan phat chuong
///   hien tai.
Future<CachedAudio?> prefetchChapterAudio({
  required AudioCache cache,
  required FallbackChain chain,
  required String text,
  required String chapterUrl,
  required ProviderOrder order,
  required String Function(String providerName) voiceFor,
  required double Function(String providerName) speedFor,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
  Duration? timeout,
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  Future<CachedAudio?> once() async {
    try {
      final fut = ensureChapterAudio(
        cache: cache,
        chain: chain,
        text: text,
        chapterUrl: chapterUrl,
        order: order,
        voiceFor: voiceFor,
        speedFor: speedFor,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (timeout == null) return await fut;
      return await fut.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Kẹt ở prefetch audio quá ${timeout.inSeconds} giây.',
        ),
      );
    } on TimeoutException {
      rethrow;
    } catch (e) {
      debugPrint('prefetchChapterAudio: bo qua chuong loi ($e).');
      return null;
    }
  }

  try {
    return await once();
  } on TimeoutException {
    // Retry 1 lan sau backoff 2s (chunk timeout co the do server ban tam thoi).
    await Future<void>.delayed(retryDelay);
    try {
      return await once();
    } on TimeoutException catch (e) {
      debugPrint('prefetchChapterAudio: retry van timeout ($e).');
      return null;
    }
  }
}

/// Doan duoi file tu magic bytes cua audio hoan chinh.
///
/// - RIFF....WAVE -> 'wav' (Vieneu tra PCM 16-bit mono 48kHz).
/// - 'ID3' hoac frame sync 0xFFEx -> 'mp3' (Kokoro).
/// - Con lai mac dinh 'mp3'.
@visibleForTesting
String extensionForAudioBytes(Uint8List bytes) {
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x41 && // A
      bytes[10] == 0x56 && // V
      bytes[11] == 0x45) {
    // E
    return 'wav';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 && // I
      bytes[1] == 0x44 && // D
      bytes[2] == 0x33) {
    // 3
    return 'mp3';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return 'mp3';
  }
  return 'mp3';
}
