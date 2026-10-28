# REPORT_TRUYEN_AUDIO_APP_V9 — TOC phân trang, trả page 1 ngay (v9)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter`
Pass: v9 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Bug (user báo screenshot thật 2026-10-27)

App Dio timeout 30s khi tách truyện 1k+ chương: proxy v7 fetch **tuần tự 15 pages
AJAX (~14s/page + sleep 1s = 3-4 phút)** mới trả → app `The request connection
took longer than 0:00:30`. User yêu cầu đúng kiểu web: **lấy trang 1 trước, hiện
danh sách trang, bấm trang nào lấy trang đó**.

## 2. Fix proxy (`server/proxy_server.py`, v8 → v9)

Nguyên tắc: **mỗi request chỉ fetch tối đa 1 URL** (HTML page 1 hoặc đúng 1 AJAX),
tổng ≤ 40s (dưới Dio 45s mới).

- `POST /parse {url-trang-truyen}` + `GET /toc?url=...` nhận thêm `page`
  (default 1, clamp 1..max_page):
  - `page=1`: fetch HTML 1 lần → bóc links page 1 + `rid` + `max_page` (từ
    `page(rid,N)`) → trả ngay (<20s, thực tế 4.9s). KHÔNG fetch các page sau.
  - `page>1`: fetch đúng 1 AJAX `/get/listchap/{rid}?page=N` → trả chapters
    page đó + cùng metadata.
- Response thêm metadata phân trang:
  `{"chapters":[...1 page...], "total"/"total_estimate":1500, "page":1,
  "max_page":15, "rid":"109629", "story_url":..., "texts":[]}`.
- Cache 2 lớp: RAM dict `{story_url: {rid, max_page, ts, pages:{N:chapters}}}` +
  persist JSON `/tmp/toc_cache.json` (restart không mất). TTL 1h. Lần 2 cùng
  truyện + cùng page → <1s (thực tế 0.014s local, 0.003s in-page).
- Tổng 1 request bọc `asyncio.wait_for(..., TIMEOUT_TOC_TOTAL=40s)` → 504 rõ
  ràng + gợi ý thử lại nếu site chậm (thay vì treo tới Dio timeout).
- Xóa crawl tuần tự v7 (`_toc_metruyenchu` 2..max + sleep 1s → thay bằng
  `_toc_ajax_page` 1-shot + `_meta_metruyenchu` bóc rid/max_page từ HTML).
- Giữ nguyên: parse chương lẻ (`/chuong-` forward 8001), parse `{text}`,
  422 site lạ, anti-SSRF, TTS Kokoro-primary.

## 3. App Flutter (sửa tối thiểu)

- `lib/src/core/parse/parse_client.dart`:
  - `ParseResult` thêm `page/maxPage/totalEstimate/rid/storyUrl` (default
    1/1/0/'…'/'' → tương thích JSON cũ, test cũ không sửa), `hasPaging`,
    `copyWithPage` (đổi chapters giữ metadata).
  - `ParseClient.fetchTocPage(storyUrl, page)` — GET /toc (nhẹ hơn POST).
- `lib/src/features/chapters/chapter_list_screen.dart`: `ConsumerWidget` →
  `ConsumerStatefulWidget` + thanh `_PhanTrangBar` kiểu web
  (`<< 1 ... p-1 p p+1 ... N >>`, nút Đầu/Cuối, spinner khi trang đang tải).
  Bấm trang → `fetchTocPage` → `copyWithPage`. Prefetch trang kế sau frame đầu
  (không block UI, lỗi bỏ qua âm thầm — bấm sang sẽ tải lại có lỗi rõ).
  Loading theo trang: "Đang tải trang 2/15...".
- `lib/src/core/config.dart`: `ApiTimeouts.vieneuParse` 30 → **45s** (dưới
  proxy 40s + margin, trên site chậm ~14s/page).
- `lib/src/features/library/paste_link_screen.dart`: nút loading
  "Đang tải trang 1..." (đúng bản chất v9).
- `test/fakes/fake_tts.dart`: `makeStubParseClient(paged: {N: json})` — stub
  GET /toc theo ?page= + POST /parse trả page 1 có metadata.
- `test/toc_pagination_test.dart` (mới, 7 test): fromJson metadata/default cũ,
  copyWithPage, fetchTocPage gửi đúng page + guard SSRF, widget chuyển trang
  1→2 (AppBar "trang 2/2", provider.page=2), widget kiểu cũ không hiện phân trang.

## 4. Nghiệm thu

### curl proxy local (127.0.0.1:8896, sau `systemctl restart truyen-proxy` → active)

Truyện user (`metruyenchu.../cau-tai-vo-dao-the-gioi-thanh-thanh`):

- **Page 1 (POST /parse): 4.9s** (v7: 3-4 phút), 105 chương, page 1/15,
  estimate 1500, rid 109629. **PASS <20s.**
- **Page 2 (GET /toc&page=2): 9.1s**, 100 chương. **PASS <40s.**
- **Page 1 lại (cache): 0.014s.** **PASS <2s.**
- Page 99 → clamp 15/15, 3 chương cuối (không 502).
- Regression: body `{text}` → 8001 forward OK; site lạ → 422 rõ;
  chương lẻ forward 8001 OK (live: `len` 2 chapters + texts).

### Live `https://comic.cutes1tg.online` (build web v9 đã nằm đúng chỗ)

- `GET /api/toc?page=1` → 200, 105 chương, 1/15 (0.02s từ cache proxy).
- Browser-verify (Chrome headless + CDP, in-page fetch trong chính page HTTPS
  — đúng code path XHR của Dio, script `/tmp/v9_inpage.js`):
  - Page 1 → **200 trong 3ms** (cache), 105 chương, max 15, first
    "Chương 01: Loạn thế"; page 2 → **200 trong 2ms**, 100 chương.
  - Không CORS/mixed-content error (fetch cùng origin).
- Giới hạn harness (ghi trung thực, giống V7): Flutter Web render canvas nên
  headless screenshot chỉ ra trang trắng (1 màu) — không điền form/bấm nút qua
  CDP được. Bù bằng in-page fetch (đúng transport app dùng) + xác nhận
  `main.dart.js` (build 17:31, sau code v9) chứa string UI phân trang
  ("Phân trang mục lục, trang ..."). Luồng bấm trang đã cover bởi widget test.
- Screenshot: `/tmp/v9_live_home2.png` (trắng — giới hạn headless, xem trên).

### `flutter analyze` — `No issues found!`

### `flutter test` — 105/105 pass (98 cũ + 7 mới, `All tests passed!`)

### `flutter build web --release` — OK (Caddy serve thẳng `build/web`)

## 5. Vận hành

```bash
systemctl status truyen-proxy          # active, v9 code
curl -s http://127.0.0.1:8896/health   # {"ok":true,...}
rm /tmp/toc_cache.json                 # xa cache TOC neu can boc lai tu dau
```

## 6. Whitelist path (câu cuối)

- `server/proxy_server.py` (v9: 1-page fetch + cache RAM/JSON + 504 tổng 40s)
- `lib/src/core/parse/parse_client.dart` (pagination fields + `fetchTocPage`)
- `lib/src/features/chapters/chapter_list_screen.dart` (thanh phân trang +
  prefetch)
- `lib/src/core/config.dart` (`vieneuParse` 45s)
- `lib/src/features/library/paste_link_screen.dart` (loading "trang 1...")
- `test/fakes/fake_tts.dart` (stub `paged`), `test/toc_pagination_test.dart` (mới)
- `docs/reports/REPORT_TRUYEN_AUDIO_APP_V9.md` (report này)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
