# REPORT_TRUYEN_AUDIO_APP_V6 — Fix CORS Web qua backend proxy cung origin

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter`
Pass: v6 | Role: `code-full` (được chạy flutter; CẤM git add/commit/push — không commit)

## 1. Root cause (đúng như brief v6, đã xác minh lại bằng probe)

User báo (screenshot 2026-10-27, site `https://comic.cutes1tg.online`): dán link
metruyenchu.com.vn → "Tách chương" → hộp đỏ
`Loi mang khi parse: The connection errored: XMLHttpRequest onError...`.

Root cause kép (xác nhận bằng probe ngày 2026-10-27):

- a) **Mixed-content + CORS preflight.** Page HTTPS gọi thẳng
  `http://144.202.5.197:8001/parse` (HTTP IP trần). Browser chặn mixed-content;
  ngay cả khi qua được, `Content-Type: application/json` không phải CORS
  "simple request" → preflight `OPTIONS`, mà server 8001 **không trả**
  `Access-Control-Allow-Origin` → XHR onError (đúng message user thấy).
- b) Kiến trúc sai: browser không bao giờ được gọi trực tiếp IP HTTP nội bộ
  từ page HTTPS. Parse từ URL do **server 8001 fetch** — việc fetch vẫn OK nếu
  đi từ phía server; chỉ cần browser không gọi thẳng nữa.

Probe ngày 2026-10-27: `8001/voices` → 200, `8000/voices` → 200 (upstream sống,
lỗi nằm ở tầng browser→IP, không phải upstream chết).

## 2. Kiến trúc fix: proxy cùng origin

```
Chrome (https://comic.cutes1tg.online)
  │  GET/POST /api/*  (cùng origin — hết CORS, hết mixed-content)
  ▼
Caddy :443 ── handle_path /api/* ──► FastAPI proxy 127.0.0.1:8896
  │                                     │  HTTP nội bộ
  │                                     ├── GET  /voices/vieneu → 8001/voices
  │                                     ├── GET  /voices/kokoro → 8000/voices
  │                                     ├── POST /parse         → 8001/parse (forward body)
  │                                     └── POST /tts           → 8001 trước, lỗi → 8000
  │                                                           (timeout 120s, có 'provider' hint)
  └── handle { root build/web ... } ──► file tĩnh Flutter Web
```

**Deviation so với brief (có lý do, ghi rõ): port 8896 thay vì 8898.**
`ss -tln` ngày 2026-10-27 cho thấy **:8898 đã bị `beads-board` chiếm**
(`python3 /poki/ops/beads-board/server.py`, phục vụ `beads.cutes1tg.online`).
Port **8896 đang FREE** → proxy v6 dùng **8896**. Caddy + app + report đều
nhất quán 8896. Nếu sau này muốn đúng 8898 thì phải dời beads-board trước.

## 3. Đã sửa (file:line)

### MỚI `server/proxy_server.py` (207 dòng) — FastAPI proxy
- Chọn **Python FastAPI** (theo gợi ý ưu tiên của brief: server đã sẵn stack;
  đã cài `fastapi 0.162.0 + uvicorn + httpx` vào `/usr/bin/python3`).
- `GET /voices/vieneu` (dòng ~77) → pipe `8001/voices`, timeout 15s.
- `GET /voices/kokoro` (dòng ~81) → pipe `8000/voices`, timeout 15s.
- `POST /parse` (dòng ~85) → forward body JSON nguyên sang `8001/parse`,
  timeout 30s.
- `POST /tts` (dòng ~108) → thử Vieneu trước, lỗi/timeout thì Kokoro,
  timeout 120s. Nhận thêm **`provider` hint** (`vieneu|kokoro|auto`, dòng 136):
  `vieneu` chỉ gọi 8001, `kokoro` chỉ gọi 8000 — để **giữ đúng semantics
  FallbackChain phía client** (tránh proxy "cướp" chunk Kokoro bằng voice
  Vieneu sai, tránh double-fallback lệch voice).
- CORS `Access-Control-Allow-Origin: *` + nhận `OPTIONS` (CORSMiddleware).
- Chấp nhận cả `/x` và `/api/x` (hàm `_norm`/alias route) để test trực tiếp
  không qua Caddy vẫn chạy.
- `GET /health` → `{"ok":true,...}` cho systemd/cron check.

### `lib/src/core/config.dart:18-28` — base URL theo nền
- Mới `webProxyBaseUrl = '/api'` (KHÔNG hardcode IP — browser tự dùng origin
  của page) + getter `parseBaseUrl` (Web → `/api`, native → IP thật).
- `vieneuBaseUrl`/`kokoroBaseUrl` giữ nguyên cho native.

### `lib/src/core/parse/parse_client.dart:54-62`
- `baseUrl: kIsWeb ? webProxyBaseUrl : vieneuBaseUrl` (cùng origin trên Web).

### `lib/src/core/tts/vieneu_provider.dart:17-24, 30-38, 66-82`
- baseUrl theo nền; voices path Web → `/voices/vieneu`; body `/tts` Web thêm
  `'provider': 'vieneu'`. Vệ sinh: bỏ `import dart:typed_data` thừa
  (analyze hết info).

### `lib/src/core/tts/kokoro_provider.dart:17-24, 30-38, 117-137`
- baseUrl theo nền; voices path Web → `/voices/kokoro`; chunk `/tts` Web thêm
  `'provider': 'kokoro'` (giữ đúng voice/speed/format + chunking phía client).
- Tree-shaking: `kIsWeb` là hằng số biên dịch → bundle Web **loại bỏ hoàn
  toàn nhánh IP**. Kiểm chứng: `grep -c 144.202.5.197 build/web/main.dart.js`
  → **0 match**. Đúng yêu cầu "KHÔNG hardcode IP trong code web".

### Caddy (`/etc/caddy/Caddyfile`, block `comic.cutes1tg.online`)
- `handle_path /api/* { uri strip_prefix /api; reverse_proxy 127.0.0.1:8896 }`.
- `handle { root * .../build/web; try_files {path} /index.html; file_server }`
  **thay** `python http.server 8897` cũ (đã kill, port 8897 đã free).
- Bẫy đã gặp & fix: để `try_files` trần ở top-level thì Caddy rewrite
  `/api/* → /index.html` **trước** khi `handle_path` match → phải bọc static
  trong `handle` (order thấp hơn `handle_path`).

### ` /etc/systemd/system/truyen-proxy.service` — chạy bền vững
- `truyen-proxy.service`: `ExecStart=/usr/bin/python3 -m uvicorn
  server.proxy_server:app --host 127.0.0.1 --port 8896`, `Restart=always`,
  log `/var/log/truyen-proxy.log`. Đã `daemon-reload + enable + start`:
  `is-enabled=enabled`, `is-active=active`.
- Backup Caddyfile cũ: `/etc/caddy/Caddyfile.bak-v6-20261027`.

## 4. Nghiệm thu

### `flutter analyze` — 0 issue
`No issues found!` (đã fix 1 info `unnecessary_import` còn lại từ trước).

### `flutter test` — 19/19 unit pass, 9 widget fail CÓ SẴN (không do v6)
- Pass hết: `fallback_chain_test + kokoro_concat_test + parse_and_magic_test`
  (19 test, gồm cả `ParseClient` guard với baseUrl mới).
- 9 fail còn lại là widget test Hive-setup (`HiveError: You need to
  initialize Hive...` + finder text) — **có sẵn từ V5**: repo chưa có commit
  nào nên không `git stash` baseline được, nhưng (1) không test nào trong số
  đó override/mock provider hay baseUrl (`grep` override trong `test/*.dart`
  → 0 file), (2) lỗi toàn ở `fake_audio_cache.openTestCache`/`find.text`,
  không chạm code v6 sửa.

### `flutter build web --release` — OK, bundle 0 IP trần (xem §3).

### Browser-verify (Chrome thật 156, playwright-core + system chrome)
- Trang chủ `https://comic.cutes1tg.online/` (screenshot `/tmp/v6_home.png`):
  thấy đủ UI (AppBar "Truyện Audio", "Dán link truyện để nghe", SegmentedButton
  Link/Dán text, ô URL, nút "Tách chương"). Console: **không `pageerror`,
  không `requestfailed`**, chỉ Hive IndexedDB + warning GPU ReadPixels headless
  (vô hại, đã có từ V4).
- **In-page fetch proof** (chạy `fetch` trong chính page HTTPS bằng Chrome
  thật — đúng code path XHR cùng origin mà Dio sẽ đi):
  `GET /api/voices/vieneu` → **200, 25 giọng**;
  `POST /api/parse` (text mẫu 2 chương) → **200, tách đúng
  ["Chương 1: Mở đầu", "Chương 2: Tiếp theo"]**. Không CORS/mixed-content error.
- **Preflight qua HTTPS**: `OPTIONS /api/parse` → 200 +
  `access-control-allow-origin: *`.
- **Đúng URL của user**: `POST /api/parse {"url":
  "https://metruyenchu.com.vn/cau-tai-vo-dao-the-gioi-thanh-thanh"}` qua proxy
  → 200, chapters `["Phần 1", "Phần 2", ...]` + texts (upstream 8001 fetch
  metruyenchu OK). App Web gọi cùng origin sẽ nhận đúng kết quả này — hết hộp đỏ.
- Giới hạn harness (ghi trung thực): click/type qua CDP tọa độ + Tab đều
  **không focus được** Flutter Web text field trong headless (Flutter xử lý
  key event riêng), nên không có screenshot "list chương sau khi bấm nút".
  Form validate trống ở V4 đã chứng minh nút + form sống; tầng network (nguyên
  nhân hộp đỏ) đã được chứng minh thông 4/4 ở trên bằng browser thật.
- Script verify lưu tại `/tmp/v6tools/` (`inpage_proof.js`, `dump.js`,
  `verify_parse*.js`, `verify_ui_tab.js`); screenshot `/tmp/v6_home.png`.

### Cách chạy / vận hành proxy
```bash
systemctl status truyen-proxy          # systemd (Restart=always)
curl -s http://127.0.0.1:8896/health   # {"ok":true,...}
tail -f /var/log/truyen-proxy.log
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

## 5. Whitelist path (câu cuối)
- `server/proxy_server.py` (mới, FastAPI proxy :8896)
- `/etc/systemd/system/truyen-proxy.service` (mới, unit systemd)
- `/etc/caddy/Caddyfile` (diff block `comic.cutes1tg.online`: `handle_path /api/*` → 8896 + `handle` static `build/web`; backup `/etc/caddy/Caddyfile.bak-v6-20261027`)
- `lib/src/core/config.dart`, `lib/src/core/parse/parse_client.dart`, `lib/src/core/tts/vieneu_provider.dart`, `lib/src/core/tts/kokoro_provider.dart` (Web → `/api` + provider hint)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
