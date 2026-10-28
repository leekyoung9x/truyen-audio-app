# REPORT_TRUYEN_AUDIO_APP_V10 — Fix kẹt loading 100% không hiện controls (v10)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter`
Pass: v10 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Bug (user báo screenshot thật 2026-10-27)

- Player hiện "Đang tạo audio... 100%" + progress đầy, nhưng KHÔNG chuyển sang
  UI controls (play/pause, tua, tốc độ). Mở trực tiếp `#/player` còn trắng xóa.
- Root cause (Lead đã xác định từ `player_screen.dart`): `_prepare()` treo ở
  `await handler.play()` hoặc `ensureChapterAudio` không resolve trên Web →
  `finally { _loading=false }` không chạy → kẹt `_LoadingView` dù progress đã 100%.
- Kịch bản treo: audio tạo xong (bytes có) nhưng `AudioSource.uri(data:)`
  hoặc `play()` trên Web treo/không resolve.

## 2. Fix (chỉ sửa `player_screen.dart` + `audio_handler.dart`)

**`lib/src/features/player/audio_handler.dart`** (1 điểm):
- `loadPlaylist` → `setAudioSource` bọc `.timeout(30s)` với message rõ
  ("Nạp audio quá 30 giây ... data: URI ..."). Caller (`_prepare`) bọc thêm
  1 lớp timeout + hiện controls ngay, nên đây là lưới an toàn tầng 2.

**`lib/src/features/player/player_screen.dart`** (chính):
- Tách 2 trạng thái: `_audioReady` (thực tế là `_items.isNotEmpty` — đã có
  audio) vs `_playing` (từ `snapshotStream`). Có audio là hiện `_ControlsView`
  ngay, kể cả `play()` chưa xong. `_items` được set + `_loading=false` ngay
  sau chương ĐẦU TIÊN tải xong (progressive), các chương sau prefetch tiếp.
- Mọi `await` trong `_prepare` (textOf/lazy-fetch, ensureChapterAudio,
  loadPlaylist, setSpeed, play) bọc `_step(label, run)` timeout 30s.
  Timeout bước nào → `_error` rõ "Kẹt ở \<bước\> quá 30 giây ..." + nút
  Thử lại, không treo vô hạn. `TimeoutException` KHÔNG bị `on Exception`
  của textOf nuốt (vì `continue` chỉ catch `Exception`, `TimeoutException`
  là `Exception`... — lưu ý: vòng textOf catch `on Exception` nên timeout
  lazy-fetch 1 chương = bỏ qua chương đó, đúng hành vi cũ "chương lỗi: bỏ qua").
- `play()` treo → catch riêng `on TimeoutException`: NUỐT, giữ `_error` làm
  **notice nhẹ** trên controls ("Audio đã sẵn sàng nhưng tự phát thất bại.
  Hãy bấm nút Phát.") — state paused, user bấm phát lại được. Không để
  1 promise treo chặn cả UI.
- Vào thẳng `#/player` thiếu state (`parseResult == null`) → hiện SnackBar
  "Chưa có truyện nào. Hãy dán link truyện trước." (TRƯỚC `go('/')` để dùng
  context còn trong cây — Snackbar nằm trên Router nên vẫn hiện sau khi về `/`)
  + redirect về `/`, không trắng xóa. `cache == null` → lỗi rõ + nút Thử lại.
- Chống race `_prepare` cũ/mới: `_loadToken` + `alive()`, retry reset `_items`.
- `PlayerScreenState` public + `@visibleForTesting static stepTimeoutForTest`
  (default 30s production) để widget test rút ngắn timeout mà không đợi thật.

**Test** (`test/player_screen_test.dart`, `test/fakes/fake_audio_handler.dart`):
- `HangingPlayAudioHandler extends FakeStoryAudioHandler`: `play()` treo trên
  gate (mô phỏng bug Web), `unhang()` idempotent, các API khác như fake thường.
- Case 1 `player_play_treo_van_hien_controls_va_bam_phat_lai_duoc`: play treo
  (timeout rút 2s cho test) → UI vẫn hiện controls (icon Phát + tiêu đề chương,
  không còn text "Đang tạo audio..."), bấm phát lại được (`playCalls >= 2`).
- Case 2 `player_vao_thang_khong_state_redirect_ve_trang_chu`: vào `/player`
  không state → redirect, trang chủ hiện lại, không kẹt loading.
- Case cũ `player_thieu_du_lieu...` → tách thành 2 case đúng hành vi mới:
  redirect+snackbar (thiếu parseResult) và lỗi+Thử lại (thiếu cache).
- `flutter test` đếm 108 (105 cũ — trừ 1 case cũ thay bằng 2 case mới + 2 case
  v10 = 105 - 1 + 2 + 2 = 108). Chạy 2 lần, ổn định.

## 3. Nghiệm thu

### `flutter analyze` — `No issues found!`

### `flutter test` — 108/108 pass (`All tests passed!`)

### `flutter build web --release` — OK (`✓ Built build/web`)
- `build/web/main.dart.js` (3.1MB, 17:54) chứa string v10 (dạng escape
  `ẹ`: `"Kẹt ở ... qu\xe1 30 gi\xe2y (kịch..."`).

### Browser live `https://comic.cutes1tg.online` (build web v10 đã nằm đúng chỗ —
Caddy `root * /poki/truyen-audio-app/build/web`, verify curl `live / : 200`)
- Chrome headless + CDP, in-page fetch trong chính page HTTPS (đúng code path
  XHR của Dio, script `/tmp/v10_cdp*.py`):
  - `/` render đúng UI paste-link (screenshot `/tmp/v10_live_home.png`,
    title "Truyện Audio" — không trắng).
  - `POST /api/parse` truyện user → **200, 105 chương, page 1/15**
    ("Chương 01: Loạn thế") — từ cache proxy.
  - Lazy chapter: `POST /api/parse {chapter-url}` → text **7851 ký tự**.
  - `POST /api/tts {text 300 ký tự, diem_trinh}` → **200, `audio/mpeg`,
    114024 bytes** — chứng tỏ bytes audio CÓ trên Web thật, đúng kịch bản
    bug v10 (treo ở play/setAudioSource chứ không phải thiếu audio), fix hiện
    controls ngay là đúng thuốc.
- Giới hạn harness (trung thực, giống V7/V9): Flutter Web render canvas, CDP
  không bấm nút/bơm form qua canvas được. Bù bằng in-page fetch full code path
  (parse → chapter text → TTS bytes) + widget test cover luồng bấm nút/treo.
- Screenshot: `/tmp/v10_live_home.png` (trang chủ render đúng, không trắng).

## 4. Whitelist path (câu cuối)

- `lib/src/features/player/player_screen.dart` (v10: tách `_items`/controls
  ngay, `_step` timeout 30s, nuốt play-treo thành notice, redirect+snackbar
  khi thiếu state, `_loadToken`, `PlayerScreenState.stepTimeoutForTest`)
- `lib/src/features/player/audio_handler.dart` (`setAudioSource` timeout 30s)
- `test/player_screen_test.dart` (2 case v10 mới + tách case thiếu-state)
- `test/fakes/fake_audio_handler.dart` (`HangingPlayAudioHandler`)
- `docs/reports/REPORT_TRUYEN_AUDIO_APP_V10.md` (report này)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
