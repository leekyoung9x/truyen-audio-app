/// Cau hinh tap trung duy nhat cho toan bo app.
///
/// Sau nay doi sang https/domain chi can sua file nay.
///
/// CANH BAO: HTTP hien tai la dev-only (mang noi bo, khong TLS).
/// Production phai dung https + domain co chung chi hop le.
///
/// WEB (v6): browser KHONG bao gio goi thang IP TTS (mixed-content + CORS
/// preflight tu page HTTPS). Moi request di qua proxy cung origin:
/// `<page-origin>/api/*` (Caddy strip /api -> proxy 8896 -> TTS noi bo).
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Base URL cua TTS server DU PHONG (Vieneu, v8: xuong fallback).
const String vieneuBaseUrl = 'http://144.202.5.197:8001';

/// Base URL cua TTS server CHINH (Kokoro, v8: len primary).
const String kokoroBaseUrl = 'http://144.202.5.197:8000';

/// Base URL cua proxy cung origin cho Web (`<origin>/api`,
/// KHONG hardcode IP — browser tu lay origin cua page dang chay).
///
/// Native (Android/iOS/desktop) khong co CORS/mixed-content nen goi thang IP.
const String webProxyBaseUrl = '/api';

/// Base URL parse ma UI nen dung: Web -> proxy, native -> server that.
String get parseBaseUrl => kIsWeb ? webProxyBaseUrl : vieneuBaseUrl;

/// Timeout (giay) cho tung endpoint.
class ApiTimeouts {
  ApiTimeouts._();

  /// Chuong truyen co the dai (toi da 12000 ky tu) -> cho phep toi 120s.
  static const int vieneuTts = 120;

  /// Parse 1 URL hoac doan text (v9: proxy tra ngay 1 page TOC <= 40s).
  static const int vieneuParse = 45;

  /// Lay danh sach giong doc.
  static const int voices = 15;

  /// Moi chunk Kokoro (<= 5000 ky tu, thuc te cat ~400 ky tu/chunk).
  static const int kokoroChunk = 30;

  /// v11: chuong dai (>4500 chu) qua proxy chunked — toi da 150s
  /// (20s + 10s/chunk, toi da ~22-30 chunk). Chuong ngan 45s (v13).
  static const int kokoroLongChapter = 150;

  /// v13: 1 TANG TIMEOUT DUY NHAT cho ca flow tao audio theo do dai chuong
  /// (fix bug 2 tang chong nhau v11/v12: tang step ngoai 30s kill truoc
  /// tang tao audio trong 150s; do that 2026-10-28 Kokoro 3000 chu mat
  /// 41s direct nen tang ngan 30s cu kill oan ca chuong ngan).
  /// Text <= [TextLimits.proxyChunkThreshold] (4500 chu) = 45s;
  /// dai hon = [kokoroLongChapter] (150s).
  static const int flowShortChapter = 45;

  /// v12: timeout prefetch NEN cho chuong ngan (<= proxyChunkThreshold).
  /// Giu ten v12 (khong vo caller cu); gia tri = flow 1 tang (v13).
  /// notice nhe (KHONG pha UI chuong dang phat). Chuong dai prefetch
  /// dung chung [kokoroLongChapter] 150s.
  static const int prefetchShortChapter = 45;

  /// v13: giu ten cu cho test/seam; gia tri = [flowShortChapter] (1 tang).
  /// Khong dung so rieng nua.
  static const int defaultStep = 45;
}

/// Voice mac dinh.
class DefaultVoice {
  DefaultVoice._();

  /// Giong nu Bac tu nhien (Vieneu).
  static const String vieneu = 'Trúc Ly';

  /// Giong nam ke chuyen phu (Vieneu).
  static const String vieneuMaleStory = 'Thiện Minh';

  /// Giong chinh (Kokoro, v8 primary).
  static const String kokoro = 'diem_trinh';
}

/// Gioi han do dai text cua tung provider.
class TextLimits {
  TextLimits._();

  /// Vieneu nhan toi da 12000 ky tu / request.
  static const int vieneuMaxChars = 12000;

  /// Kokoro nhan 1-5000 ky tu / request.
  static const int kokoroMaxChars = 5000;

  /// Do dai muc tieu moi chunk khi tu cat text cho Kokoro.
  static const int kokoroChunkTarget = 400;

  /// So request Kokoro chay song song toi da.
  static const int kokoroMaxParallel = 4;

  /// v11: nguong text dai — Web gui NGUYEN qua proxy de proxy tu cat
  /// (tranh cat 2 lan), thay vi cat o client nhu native.
  /// Phai khop `TTS_CHUNK_THRESHOLD` trong server/proxy_server.py.
  static const int proxyChunkThreshold = 4500;

  /// v11: so chunk progressive (`/tts_chunk`) chay song song toi da (Web).
  /// Thap hon native (server Kokoro xu ly gan nhu tuan tu + mang Web chiu
  /// timeout ngan hon); proxy rieng van fan-out sau.
  static const int proxyChunkParallel = 2;
}

/// Toc do doc hop le.
class SpeedRange {
  SpeedRange._();

  static const double min = 0.5;
  static const double max = 1.5;
  static const double step = 0.1;
  static const double def = 1.0;
}
