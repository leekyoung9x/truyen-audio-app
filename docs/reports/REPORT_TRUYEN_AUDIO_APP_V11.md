# REPORT_TRUYEN_AUDIO_APP_V11 — Chunk-split trong proxy + phát ngay (v11)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | Proxy: `server/proxy_server.py` (port 8896)
Pass: v11 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Bug (user báo screenshot thật 2026-10-27 + Lead verify)

- Chương 1 truyện user (**7851 chữ**) → app báo "Kẹt ở tạo audio quá 30s".
- Lead verify: proxy `POST /api/tts` gửi **NGUYÊN 7851 chữ** sang Kokoro
  (giới hạn 5000) → **422**; rơi sang Vieneu full-text → **timeout 120s** → **502**.
  Cả 2 chết.
- Root cause kiến trúc: chunk-split (~400 chữ, song song) chỉ nằm ở **app
  Flutter** (`KokoroProvider.splitIntoChunks`); proxy không có → Web gửi cục
  to là chết. Native direct-IP không qua proxy nên không dính.

## 2. Fix proxy (chính) — `server/proxy_server.py` v9 → v11

- `POST /api/tts`: text > **4500 chữ** (`TTS_CHUNK_THRESHOLD`) → tự cắt chunk
  ≤400 chữ (`split_text_chunks`, port 1-1 logic Dart: tách câu theo dấu câu +
  xuống dòng, câu đơn dài hơn target thì cắt cứng), gọi Kokoro **song song**
  (`asyncio.gather` + semaphore) rồi **nối MP3 raw** trả về (Kokoro trả MP3
  frame `fff3...`, không ID3 header → nối bytes thô an toàn, giống client).
  Header **`X-Chunks: N`** để debug/progress.
- Chunk lỗi → **retry 1 lần** → vẫn lỗi → **fallback chunk đó sang Vieneu**
  (transcode WAV→MP3 qua `ffmpeg` + libmp3lame có sẵn trên VPS để nối đồng
  nhất). Hết cách mới 502. `provider: kokoro` giữ semantics cũ (không fallback,
  502 rõ chunk index); `provider: auto` mới fallback theo chunk.
- Timeout tổng = `min(20s + 10s/chunk, 150s)` → 504 rõ ràng khi quá.
- Voice riêng theo provider: body thêm `vieneu_voice` / `kokoro_voice`
  (fallback chunk giữ đúng giọng user chọn, không "cướp" giọng).
- **v11.1 hiệu chỉnh bằng số liệu** (2026-10-27): Kokoro box xử lý gần như
  single-flight (~2-5s/chunk tuần tự, đo 4 chunk thật 280-367 chữ: 2.0-5.2s).
  Fan-out 6 gây backlog → timeout hàng loạt → retry nhân đôi tải (death
  spiral, đã quan sát: 22 chunk song song → 504 toàn bộ). Giảm
  `TTS_CHUNK_PARALLEL` 6 → **2**, `TTS_CHUNK_TIMEOUT` 30s → **45s**
  (sống qua lúc server bận, tránh retry giả tạo thêm tải).

## 3. Stream phát ngay (phụ, không break chunk-split)

- `POST /api/tts_chunk` (mới, cả `/tts_chunk` + `/api/tts_chunk`): body
  `{text, chunk: idx, ...}` — cắt giống `_tts_chunked` rồi tổng hợp **đúng
  1 chunk idx**. Trả audio + headers `X-Chunks` (tổng) + `X-Chunk-Idx`.
  Error paths: text ngắn chỉ có chunk 0; idx ngoài phạm vi → 422 rõ phạm vi;
  chunk hỏng → 502 rõ idx (auto có fallback Vieneu như full).
- App xin chunk 0 trước (**phát ngay sau ~3s**), các chunk sau về dần
  (progressive, song song 2), nối bytes — không đợi full 128s.

## 4. App Flutter (tối thiểu)

- `lib/src/core/tts/kokoro_provider.dart`:
  - Web + text > 4500 chữ → **KHÔNG cắt ở client nữa** (tránh cắt 2 lần),
    chạy progressive qua `/tts_chunk` (chunk 0 trước đọc `X-Chunks` làm
    progress thật, các chunk sau song song ≤2, nối bytes). Proxy cũ (404
    `/tts_chunk`) → fallback single-shot `/tts` (cắt 5000 đầu) để không break.
  - Gửi `provider: auto` + `vieneu_voice`/`kokoro_voice` (auto để chunk lỗi
    được fallback thay vì 502 cả chương). Native direct-IP **giữ nguyên**
    cắt client (`splitIntoChunks` không đổi).
  - Dio Web timeout 150s (`ApiTimeouts.kokoroLongChapter`); native giữ 30s.
  - Constructor thêm `vieneuVoiceForFallback` (optional, default giọng
    Vieneu mặc định ở proxy); `app_providers.dart` wire giọng Vieneu user
    chọn vào.
- `lib/src/core/config.dart`: `proxyChunkThreshold = 4500` (phải khớp
  `TTS_CHUNK_THRESHOLD` server — có test khóa), `proxyChunkParallel = 2`,
  `kokoroLongChapter = 150`, `ApiTimeouts.defaultStep = 30`.
- `lib/src/features/player/player_screen.dart`: `audioStepTimeoutFor(text)` —
  chương ngắn giữ 30s, chương dài (>4500) lên **150s** (theo timeout tổng
  proxy), truyền qua `_step(timeoutOverride:)` ở call site "tạo audio".
  Message timeout hiện số giây thật (`${timeout.inSeconds}`).

## 5. Nghiệm thu

### curl (chương 1 thật của user: `.../chuong-01-Y1P2AcHV2Gdi`, 7851 chữ)

- `POST /api/tts` full (auto) → **200 `audio/mpeg`, 2.73MB, `X-Chunks: 22`,
  125.8s**, ffprobe decode OK (**425s audio**). Không 422/502.
  - ⚠️ Vượt `<90s` của brief ~40%: giới hạn vật lý Kokoro box (single-flight
    2-5s/chunk × 22 chunk ÷ parallel 2). UX thực đã giải quyết bằng progressive
    (phát sau ~3s, progress theo chunk) — user không còn kẹt 30s.
- `POST /api/tts` text ngắn → **200 MP3, 0.9-1.2s** (không regression).
- `POST /api/tts_chunk` chunk 0/5/21 → 200, đúng `X-Chunks: 22`/`X-Chunk-Idx`,
  2-5s/chunk; idx=99 → 422 rõ phạm vi; text ngắn idx≠0 → 422.

### Browser live `https://comic.cutes1tg.online` (Chrome headless + CDP, in-page fetch đúng code path XHR của Dio)

- `/` render đúng UI paste-link (screenshot `/tmp/v11_live_home.png`,
  canvas Flutter, không trắng).
- `parse` truyện user → chương 1 → text **7851 chữ** (1.2s, từ cache proxy).
- `/tts_chunk` chunk 0 → **200 MP3 99KB sau 3.0s, `X-Chunks: 22`** (phát ngay).
- `/tts` full chương → **200, 2.73MB, 127.8s** (khớp curl).
- `/tts` text ngắn → **200, 22KB, 0.9s**.
- Giới hạn harness (giống V7/V9/V10): Flutter Web render canvas, CDP không bấm
  nút qua canvas được. Bù bằng in-page fetch full code path + widget test.

### `flutter analyze` / test / build / restart

- `flutter analyze`: **No issues found**.
- `flutter test`: **117 pass** (108 cũ + 9 mới `test/tts_v11_test.dart`:
  ngưỡng 4500 khớp server, parallel 2, timeout 150s, timeout theo độ dài
  chương ngắn/dài, parity split ~7851 chữ, cắt cứng câu đơn dài).
  Nhánh progressive (`kIsWeb`) không cover được trên VM — cover bằng live
  browser ở trên.
- `flutter build web --release`: OK (`build/web/main.dart.js` 3.1MB).
- `systemctl restart truyen-proxy`: active, `/health` OK (v11, parallel 2).

## 6. Whitelist path (câu cuối)

- `server/proxy_server.py` (v11: `split_text_chunks`, `_tts_chunked`,
  `_tts_chunk_mot`, `_kokoro_mot_chunk`, `_vieneu_mot_chunk`,
  `_wav_sang_mp3`, `_tts_total_timeout`, routes `/tts_chunk`,
  voice riêng `vieneu_voice`/`kokoro_voice`, v11.1 parallel 2/timeout 45s)
- `lib/src/core/tts/kokoro_provider.dart` (v11: progressive `/tts_chunk`,
  không cắt client trên Web text dài, `vieneuVoiceForFallback`)
- `lib/src/core/config.dart` (`proxyChunkThreshold`, `proxyChunkParallel`,
  `kokoroLongChapter`, `defaultStep`)
- `lib/src/features/player/player_screen.dart` (`audioStepTimeoutFor`,
  `timeoutOverride`, message timeout động)
- `lib/src/features/app_providers.dart` (wire giọng Vieneu vào KokoroProvider)
- `test/tts_v11_test.dart` (mới, 9 cases)
- `docs/reports/REPORT_TRUYEN_AUDIO_APP_V11.md` (report này)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
