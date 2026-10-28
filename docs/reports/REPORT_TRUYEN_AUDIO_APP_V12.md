# REPORT_TRUYEN_AUDIO_APP_V12 — Prefetch nền không phá UI (v12)

Ngày: 2026-10-28 | Workspace: `/poki/truyen-audio-app` | Proxy: `server/proxy_server.py` (port 8896)
Pass: v12 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Bug (user báo screenshot thật 2026-10-28)

- Player đang ở "Chương 01: Loạn thế", progress 00:00, hiện banner đỏ:
  "Tải audio thất bại: TimeoutException: Kẹt ở tạo audio chương 2 quá 30 giây
  (kịch bản Web đã biết). Hãy bấm Thử lại."
- Nghĩa là: chương 1 đã có audio (hiện controls), nhưng prefetch chương 2
  timeout 30s → lỗi đỏ đè lên UI, user đánh giá "quá tệ".
- Root cause: `_prepare()` tải cả 3 chương trong **một vòng lặp blocking**
  trước khi `loadPlaylist`/`play`. Chương 2 chậm → throw ra ngoài → `catch`
  tổng set `_error` đỏ, dù chương 1 đã có audio (và còn chưa được play vì
  `play()` nằm sau vòng lặp → progress kẹt 00:00).
- 2 bug phụ cùng root cause:
  - V11 nâng timeout chương dài lên 150s + progressive chunk, nhưng prefetch
    vẫn đi chung vòng lặp blocking với cùng `_step` → chương 2 chậm là fail
    cả flow (không phân biệt chương ngắn/dài cho prefetch: cấm dùng cứng
    30s cho mọi chương — brief yêu cầu timeout riêng 45s/150s).
  - `synthProgressProvider` không reset khi chuyển chương (state `{0:1.0,
    1:0.5...}` chương cũ leak sang `_prepare` mới).

## 2. Fix (chỉ `player_screen.dart` + `chapter_audio.dart` + `config.dart`, proxy giữ nguyên v11)

- `lib/src/core/config.dart`: thêm `ApiTimeouts.prefetchShortChapter = 45`
  (prefetch nền chương ngắn 45s — dài hơn step 30s để sống qua lúc server
  bận; chương dài prefetch dùng chung `kokoroLongChapter` 150s).
- `lib/src/core/convert/chapter_audio.dart`: thêm `prefetchChapterAudio()`
  (KHÔNG BAO GIỜ throw) — timeout → đợi `retryDelay` 2s rồi thử lại 1 lần
  (backoff cho chunk timeout); vẫn lỗi → log + trả null. Lỗi khác (mạng,
  TTS hỏng hết) → log + trả null ngay, không retry.
- `lib/src/features/player/player_screen.dart`:
  - `_prepare` mới: chỉ chương HIỆN TẠI là blocking (tải → hiện controls
    ngay → nạp playlist → phát). 2 chương kế prefetch NỀN (`unawaited` +
    try/catch riêng, không await): lỗi chỉ log + notice nhẹ, TUYỆT ĐỐI
    không set `_error` đỏ, không chặn phát chương hiện tại.
  - `_buildOneChapter()`: tải + tạo audio 1 chương dùng chung cho cả 2 path.
    `isPrefetch: true` → timeout prefetch riêng 45s/150s
    (`prefetchTimeoutFor`, cấm cứng 30s) + retry 1 lần + backoff 2s.
    Chuông hiện tại hỏng → lỗi đỏ như cũ (không có gì để phát).
  - `_prefetchNext()`: chạy sau khi playlist đã nạp (không đợi play xong);
    token-guard (`loadToken != _loadToken` → dừng ngay khi user chuyển
    chương giữa chừng, không cập nhật UI cũ); chương lỗi → progress -1 +
    `_failedChapters` + `_prefetchNotice` nhẹ ("Chương N tải nền thất bại
    (sẽ bỏ qua khi bấm Chương sau)"); chương OK → `appendToPlaylist`
    (cheap-append, không nạp lại từ đầu, không giật audio đang phát).
  - `_toMediaItem()`: tạo `ChapterMediaItem` dùng chung 2 path.
  - `prefetchFetchTimeout` (static, test-overridable): fetch nội dung chương
    kế ở nền cũng timeout riêng 45s thay vì step 30s.
  - Reset `synthProgressProvider` về chỉ còn `{startIndex: 0.0}` khi chuyển
    chương (tránh leak state chương cũ sang chương mới).
  - `build()`: notice ưu tiên `_error` (đỏ, chương hiện tại) trước rồi đến
    `_prefetchNotice` (nhẹ); cả 2 đều không chặn controls khi đã có audio;
    nút đóng xóa cả 2.
- `lib/src/features/player/audio_handler.dart`: thêm `appendToPlaylist()`
  (cheap-append vào `ConcatenatingAudioSource` hiện tại, giữ vị trí đang
  phát; trùng id/thiếu playlist → throw để caller bỏ qua như notice nhẹ).
- Test fakes: `FakeStoryAudioHandler.appendToPlaylist()` (nối list + emit
  queueLength, giữ tính bất biến như handler thật).

## 3. Nghiệm thu

### `flutter analyze` / test / build / restart

- `flutter analyze`: **No issues found!**
- `flutter test`: **119 pass** (117 cũ + 2 mới v12 trong
  `test/player_screen_test.dart` → group `player_v12_prefetch_khong_pha_ui`):
  - `player_prefetch_timeout_chi_notice_nhe_khong_loi_do`: chương 2
    `TimeoutException` (mô phỏng prefetch timeout) → chương 1 vẫn phát
    (pause, không icon lỗi đỏ), chỉ notice info nhẹ "Chương 2 tải nền thất
    bại", playlist `['chapter-0', 'chapter-2']` (skip chương lỗi),
    progress `{0:1.0, 1:-1.0, 2:1.0}`.
  - `player_prefetch_fail_van_play_chuong_hien_tai`: chương 2+3 TTS hỏng →
    chương 1 vẫn phát, playlist chỉ `['chapter-0']`, progress
    `{0:1.0, 1:-1.0, 2:-1.0}`.
  - Test cũ `player_tai_xong...` cập nhật theo semantics mới: chương hiện
    tại vào playlist ngay (1 item sau `pumpAndSettle`), prefetch nền chen
    xong sau thêm nhịp (3 items) — đúng thứ tự play-trước-prefetch-sau.
- `flutter build web --release`: OK (`build/web/main.dart.js` 3.1MB,
  2026-10-28 14:58, chứa string v12 `prefetchChapterAudio: retry van
  timeout` đã minify trong bundle live).
- Proxy KHÔNG đụng (giữ nguyên v11 theo brief) — `systemctl is-active
  truyen-proxy`: **active**, `/api/health` 200.

### Browser live `https://comic.cutes1tg.online` (build v12 đã serve)

- `/` render canvas Flutter, body 2560 chars (không trắng).
- `main.dart.js` live (3.1MB) chứa code v12 (grep bundle: `prefetch` ×5,
  `prefetchChapterAudio: retry van timeout` có mặt).
- `/api/parse` truyện user → 200 (15162 bytes); `/api/tts` text ngắn →
  200 MP3 19KB (proxy v11 không regression).
- Giới hạn harness (giống V7/V9/V10/V11): Flutter Web render canvas, CDP
  không bấm nút qua canvas được. Bù bằng widget test (flow thật tới
  `/player` với fake TTS/Handler — 2 case v12 ở trên) + in-page check bundle.
- Flow cần user kiểm chứng tay (mở chương 1 → hiện controls ngay → không
  còn banner đỏ khi chương 2 chậm; Network tab thấy prefetch nền) — đã có
  coverage tự động tương đương qua 2 widget test v12.

## 4. Hành vi sau fix (đọc để QA tay)

- Mở chương 1: hiện controls ngay sau khi chương 1 xong (kể cả play() treo
  — giữ semantics v10), phát luôn, progress chạy.
- Chương 2 chậm/hỏng: KHÔNG banner đỏ; chỉ dòng notice nhẹ + icon info, có
  nút đóng; bấm Chương sau → tự skip qua chương lỗi (không có trong
  playlist nên just_audio qua luôn chương kế).
- Chương 2 xong sau: tự nối vào cuối playlist (cheap-append), không giật
  audio đang phát.

## 5. Whitelist path (câu cuối)

- `lib/src/features/player/player_screen.dart` (`_prepare` play-trước-prefetch-sau,
  `_buildOneChapter`, `_prefetchNext`, `_toMediaItem`, `prefetchTimeoutFor`,
  `prefetchFetchTimeout`, reset `synthProgressProvider`, notice `_error ?? _prefetchNotice`)
- `lib/src/core/convert/chapter_audio.dart` (`prefetchChapterAudio`: never-throw + retry 1 + backoff 2s)
- `lib/src/core/config.dart` (`ApiTimeouts.prefetchShortChapter = 45`)
- `lib/src/features/player/audio_handler.dart` (`appendToPlaylist` cheap-append)
- `test/fakes/fake_audio_handler.dart` (`appendToPlaylist` fake)
- `test/player_screen_test.dart` (group v12: 2 cases + `_HangingChapterKokoro`/`_SelectiveFailKokoro`)
- `docs/reports/REPORT_TRUYEN_AUDIO_APP_V12.md` (report này)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
