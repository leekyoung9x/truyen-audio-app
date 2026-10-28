# REPORT — App truyện-audio đa nền tảng (Flutter) v1

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | Role: `code-full`

## 1. Đã làm gì

Hand-author toàn bộ source Flutter (không `flutter create`, không SDK trên VPS):

- `pubspec.yaml` — khóa đúng stack brief: riverpod + go_router + dio + html +
  hive/hive_flutter + just_audio + audio_service + audio_session + rxdart +
  cached_network_image + shimmer + flutter_animate + crypto + path_provider.
  Material 3 mặc định, không UI library bên thứ 3.
- `lib/src/core/config.dart` — base URL + timeout + voice/speed mặc định, đúng 1 file.
- `lib/src/core/network/dio_client.dart` — 1 Dio/1 host, CancelToken-ready.
- `lib/src/core/tts/` — abstract provider; Vieneu (WAV 48kHz, ≤12000 ký tự);
  Kokoro (tự cắt chunk ~400 ký tự theo dấu câu, song song ≤4, nối bytes, format mp3);
  `FallbackChain` thử Vieneu → Kokoro theo Settings, `ArgumentError` không fallback,
  chỉ ném `TtsAllFailedException` khi tất cả thất bại; trả về provider thắng để
  cache đúng voice đã dùng.
- `lib/src/core/parse/parse_client.dart` — `POST /parse` với `{url}` hoặc `{text}`.
- `lib/src/core/cache/audio_cache.dart` — tên file `md5(text+voice+speed)`,
  metadata Hive (chapterUrl, voice, createdAt).
- `lib/src/core/convert/chapter_audio.dart` — `ensureChapterAudio()` core dùng lại
  được cho v2 tải offline (cache → fallback → đoán đuôi file từ magic bytes).
- Features: `paste_link_screen` (URL/text → parse → `/chapters`),
  `chapter_list_screen` (tiến độ synth theo chương), `player_screen` + `audio_handler`
  (playlist just_audio, phát nền audio_service, 0.5–1.5x, tua ±10s, hẹn giờ ngủ,
  tải chương hiện tại + prefetch 2 chương kế), `settings_screen`
  (thứ tự provider, voice theo provider load từ API thật, speed).
- `lib/main.dart` — Hive init, AudioService init, ProviderScope override,
  `MaterialApp.router` Material 3 + dark mode.
- `README.md` — SDK, `pub get`/`dart fix`/`analyze`/`run`, cấu hình background
  Android/iOS, cảnh báo HTTP dev-only.
- Tự review 2 lượt: lượt 1 thêm `dart:async`/`dart:typed_data` còn thiếu;
  lượt 2 sửa `clamp()` trả `num` (thêm `.toDouble()`/`.toInt()`),
  sửa `ValueStream` gán nhầm `.stream`, và logic cache sai voice khi fallback
  (thêm `synthesizeWithProvider`).

## 2. Bằng chứng curl rút gọn (2026-10-27, từ VPS)

| Check | Kết quả |
|---|---|
| `GET :8001/voices` | **200** — 25 giọng, có `Trúc Ly`, `Thiện Minh` |
| `GET :8000/voices` | **200** — 14 giọng, có `diem_trinh` |
| `POST :8001/parse` text mẫu 2 chương | **200** — `{"chapters":[{"title":"Chương 1: Gặp gỡ","len":61},...],"texts":[...]}` |
| `POST :8001/tts` `{"text":"Xin chào...","voice":"Trúc Ly"}` | **200**, 259244 bytes, magic `RIFF....WAVE`, `file`: PCM 16-bit mono **48000 Hz** |
| `POST :8000/tts` `{"text":"...","voice":"diem_trinh","speed":1.0,"format":"mp3"}` | **200**, 15696 bytes, magic `ff f3` (MP3 frame sync) |

## 3. CHƯA VERIFY (lý do)

- `flutter analyze`, `flutter build`, `dart fix`, `flutter run` **chưa chạy được**
  vì VPS **không có Flutter/Dart SDK** và role `code-full` cấm cài thêm toolchain
  ngoài `curl/python3/git-read`. Thay bằng: verify API thật qua curl (bảng trên)
  + tự review code 2 lượt theo checklist (import trong pubspec, null-safety,
  API Flutter/Material 3/go_router/riverpod-2.5/dio-5/audio_service-0.18 tồn tại,
  `flutter_lints` theo mắt).
- Native shell (AndroidManifest/iOS Info.plist) chưa tồn tại vì chưa qua
  `flutter create` — README đã ghi XML cần thêm.
- Settings mới dùng StateProvider bộ nhớ (chưa persist Hive) — đủ cho v1,
  v2 nên persist.

## 4. Whitelist path đã tạo/sửa (để Lead commit)

```text
pubspec.yaml
analysis_options.yaml
README.md
lib/main.dart
lib/src/core/config.dart
lib/src/core/network/dio_client.dart
lib/src/core/tts/tts_provider.dart
lib/src/core/tts/vieneu_provider.dart
lib/src/core/tts/kokoro_provider.dart
lib/src/core/tts/fallback_chain.dart
lib/src/core/parse/parse_client.dart
lib/src/core/cache/audio_cache.dart
lib/src/core/convert/chapter_audio.dart
lib/src/features/app_providers.dart
lib/src/features/library/paste_link_screen.dart
lib/src/features/chapters/chapter_list_screen.dart
lib/src/features/player/player_screen.dart
lib/src/features/player/audio_handler.dart
lib/src/features/settings/settings_screen.dart
docs/reports/REPORT_TRUYEN_AUDIO_APP_V1.md (file này)
```

Không commit (đúng giới hạn role: cấm `git add/commit/push`).
