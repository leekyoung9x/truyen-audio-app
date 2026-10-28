# REPORT_TRUYEN_AUDIO_APP_V7 — Bóc mục lục HTML + parse từng chương (v7)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter`
Pass: v7 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Bug (user báo screenshot thật 2026-10-27)

User dán URL truyện metruyenchu (`/cau-tai-vo-dao-the-gioi-thanh-thanh`, ~1000
chương) → app hiện đúng 1 chương "Tập võ! ?" 7851 ký tự.

Root cause ĐÃ XÁC MINH bằng curl (không phải đoán):

- Server Vieneu 8001 `/parse {url-trang-truyen}` chỉ bóc TEXT trang giới thiệu
  (trả 2 "Phần": giới thiệu + thể loại), KHÔNG bóc mục lục HTML. Probe:
  `POST 127.0.0.1:8896/parse` (forward 8001) →
  `{"chapters":[{"title":"Phần 1","len":3000},{"title":"Phần 2","len":2764}]}`.
- Trong khi mục lục nằm ngay trong HTML: `div#chapter-list` (100 link page 1
  tĩnh) + phân trang AJAX `/get/listchap/{rid}?page=N` (`var rid='109629'`,
  nút `page(109629,2..15)` + "Cuối"). Mỗi page AJAX = 100 link, page cuối 3
  link → tổng 1403 link thô / 665 số chương distinct (nhiều chương tách 2 phần).
- Thêm bằng chứng: URL user gửi lần 2 không có đuôi `/chuong-1` (lần 1 có) —
  cả 2 đều ra 1–2 chương rác (forward mù sang 8001).

## 2. Fix trong `server/proxy_server.py` (KHÔNG đụng 8001, chỉ sửa proxy mình)

Bóc TOC bằng **stdlib + httpx** (không cần bs4 — server không có sẵn, regex đủ
vì markup mục lục ổn định `<a href='...chuong-...'>title</a>`).

- `POST /api/parse` khi body chỉ có `url` trang truyện (không chứa `/chuong-`
  hay `/chapter`, không có `text`) → tự bóc TOC thay vì forward mù.
  URL chương cụ thể (`/chuong-`, `/chapter`) → forward 8001 như cũ (8001 parse
  1 chương tốt — probe: `chuong-01` → `{"title":"Tập võ! ?","len":7851}` +
  text đầy đủ). Body `{text}` → forward như cũ.
- Heuristic phân biệt: `_is_chapter_url()` check substring `/chuong-` /
  `/chapter` (case-insensitive).
- `GET /api/toc?url=...` (mới): ép bóc TOC, trả
  `{"chapters":[{"title","url","len":0}],"total":N,"texts":[]}`. `len=0` = chưa
  fetch nội dung (lazy ở bước sau).
- Phân trang: đọc `var rid` + các nút `page(rid,N)` trong HTML → fetch tuần tự
  `GET {origin}/get/listchap/{rid}?page=2..max` (tối đa 20 page), dedupe giữ
  thứ tự, sort tăng dần theo số chương (page tĩnh = mới-nhất-trước, AJAX =
  cũ-trước → gộp thô sẽ loạn). Gặp page không có link MỚI → dừng ngay.
- Bẫy thực tế gặp & fix:
  - AJAX `/get/listchap/` **rất chậm (~14s/page**, Cloudflare + bot-check) →
    `TIMEOUT_TOC_PAGE=35s` (12s ban đầu timeout toàn bộ page 2+).
  - Fetch song song 5 page → `ReadTimeout` hàng loạt (site nghi bot) → chuyển
    **tuần tự + sleep 1s** giữa các page.
  - Page vượt quá thực tế (VD ?page=16) wrap về page 1 → dedupe + dừng sớm.
- Dispatcher theo domain: `_toc_parser_name()` — v7 chỉ `metruyenchu*` chạy;
  site khác trả **422 + message rõ** ("chưa hỗ trợ ... site X, hãy paste URL
  chương cụ thể") thay vì 1 chương rác. Anti-SSRF: chặn loopback/link-local/
  private/reserved/metadata host (`_host_bi_chan`), chỉ http/https.
- UA browser + `Referer` + `X-Requested-With` cho AJAX (site chặn bot trần).

## 3. App Flutter (sửa tối thiểu)

- `lib/src/core/parse/parse_client.dart`:
  - `ChapterInfo` thêm `url` (default `''`, tương thích JSON cũ không có url)
    + getter `hasUrl`.
  - `ParseResult.copyWithTexts()` — lưu text sau lazy-fetch.
  - `ParseClient.fetchChapterText(url)` — `POST /parse {url-chuong}` (proxy
    forward 8001), lấy `texts[0]`, rỗng → throw rõ ràng.
- `lib/src/features/player/player_screen.dart`: `_prepare()` lazy-fetch —
  chương nào `texts` rỗng mà có `url` thì fetch trước khi synth; texts đệm `' '`
  cho đủ `chapters.length` rồi `copyWithTexts` lưu lại (lần sau khỏi tải).
  Chương lỗi → bỏ qua, vẫn phát chương tải được. `chapterUrlOf` ưu tiên url
  thật (cache key đúng từng chương).
- `lib/src/features/chapters/chapter_list_screen.dart`: AppBar vẫn
  `"N chương"` (đúng N=1403 với truyện test); banner nhỏ "Mở chương để tải
  nội dung rồi nghe" khi là TOC; subtitle `len=0` → "Chạm để tải nội dung"
  thay vì "0 ký tự"; semantics label tương ứng.

## 4. Nghiệm thu (bắt buộc, curl + browser)

### curl — `POST /api/parse {url-trang-truyen}` (proxy 8896, sau restart systemd)

```
total: 1403 | chapters: 1403 | texts: 0 | PASS >=500: True
first: Chương 00: Phiên Ngoại Hoa Mai Ai Gửi (1/2) | url absolute https://...
last:  Chương 674: Hóa Hư (...) (2/2)
665 số chương distinct (0..674), sort tăng dần OK, mọi url absolute metruyenchu
```

- `GET /toc?url=...` → total 1403 (giống hệt).
- URL chương lẻ → forward 8001: `Tập võ! ? / len 7851 / texts 1` (không đổi).
- Site khác (`truyenfull.vn`) → 422 + message rõ (không còn chương rác).
- Body `{text}` cũ → 8001 parse như cũ (không regression).

### `flutter analyze` — 0 issue (`No issues found!`)

### `flutter test` — 98/98 pass (hơn V6: 19 pass + 9 widget-fail có sẵn)

V6: 19 unit pass + 9 widget fail (`HiveError: You need to initialize Hive`,
finder text — có sẵn, không do v6). V7: **98/98 pass**, gồm
`chapter_list_screen_test` (3 chương mock + điều hướng), `player_screen_test`
(prefetch 3 chương, play/pause, sleep timer), `parse_and_*` (guard SSRF
client, magic bytes). Không test nào stub `url` mới — field có default nên
tương thích ngược hoàn toàn.

### `flutter build web --release` — OK

### Browser-verify (Chrome thật + playwright-core)

Giới hạn harness (giống V6, ghi trung thực): Flutter Web render trên canvas,
không bật accessibility tree headless (`Accessibility.getFullAXTree` chỉ thấy
nút "Enable accessibility") → không điền form / bấm nút qua CDP được. Verify
bằng **in-page fetch trong chính page HTTPS** (đúng code path XHR mà Dio của
app sẽ đi) + screenshot trang chủ.

- Script `/tmp/v7_inpage.js` chạy trong page `build/web` (serve `:8901`):
  - `POST /parse {url-trang-truyen}` → **200, 1403 chapters trong 143s**,
    first `Chương 00: Phiên Ngoại Hoa Mai Ai Gửi (1/2)` + url absolute,
    last `Chương 674: ... (2/2)`. **PASS ≥500.**
  - Lazy-fetch chương lẻ (`POST /parse {url-chuong}` — code path player):
    **200, `len=10750`, textLen=10750** (text thật, không phải rác).
  - `requestfailed: none`, không CORS/mixed-content error.
- Screenshot `/tmp/v7_home.png`: page load OK (title "Truyện Audio", Hive
  IndexedDB init, chỉ warning GPU ReadPixels vô hại như V4).
- Live `https://comic.cutes1tg.online` (Caddy serve thẳng
  `/poki/truyen-audio-app/build/web` — build v7 mới đã nằm đúng chỗ, không cần
  copy; route `/api` → 8896 không đổi):
  - `GET /` → 200, title "Truyện Audio", 0 pageerror/requestfailed
    (screenshot `/tmp/v7_live_home.png`).
  - `POST /api/parse {text}` → 200 tách đúng (không regression).
  - `POST /api/parse {url-trang-truyen}` → **200, total 1403 chapters**
    (đúng N, qua đúng domain production).

### Cách chạy / vận hành proxy

```bash
systemctl status truyen-proxy          # Restart=always
curl -s http://127.0.0.1:8896/health   # {"ok":true,...}
curl -s -X POST http://127.0.0.1:8896/parse \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://metruyenchu.com.vn/..."}' | head -c 300
```

Lưu ý vận hành gặp trong pass: 1 lệnh `systemctl restart` từ shell background
bị kill giữa chừng để lại job `restart running` + unit kẹt `deactivating`
(~90s, uvicorn giữ keepalive không chịu SIGTERM). Fix: chờ process cũ tự thoát
(`kill` báo No such process) → systemd tự lên `active` với code mới. Lần sau
nên `systemctl restart` từ shell foreground hoặc `systemctl kill` trước.

## 5. Whitelist path (câu cuối)

- `server/proxy_server.py` (v7: TOC metruyenchu + `GET /toc` + dispatcher + sort)
- `lib/src/core/parse/parse_client.dart` (`ChapterInfo.url`, `copyWithTexts`,
  `fetchChapterText`)
- `lib/src/features/player/player_screen.dart` (lazy-fetch text TOC)
- `lib/src/features/chapters/chapter_list_screen.dart` (banner + subtitle TOC)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
