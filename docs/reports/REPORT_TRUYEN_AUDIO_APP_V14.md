# REPORT_TRUYEN_AUDIO_APP_V14 — bóc sạch nội dung + queue nền full truyện (v14)

Ngày: 2026-10-28 | Workspace: `/poki/truyen-audio-app` | Proxy: `server/proxy_server.py` (port 8896)
Pass: v14 | Role: `code-full` (KHÔNG git add/commit/push — không commit)

## 0. 22 bằng chứng công cụ (thiếu 1 mục = FAIL)

> Quy ước: mỗi mục = lệnh gọi thật + param + output rút gọn + quyết định áp dụng
> (`file:line`). Cấm "đã áp dụng" suông.

### 1. Codebase Memory — `check_index_coverage` + `trace_path(_parse)`

- Lệnh: `check_index_coverage(paths=[proxy_server.py, parse_client.dart,
  chapter_list_screen.dart, player_screen.dart], project=poki-truyen-audio-app)`
  → 4/4 `no_recorded_issue`, `freshness=metadata_match` → dùng graph + đọc source.
  `trace_path(function=_parse, direction=both)` → callees 17
  (`_boc_toc`, `_pipe_json`, `_is_chapter_url`, `_host_bi_chan`...), callers 0
  (route đăng ký qua `add_api_route`, không gọi trực tiếp).
- Áp dụng: chèn `_sach_noi_dung_chuong` + nhánh X-Clean vào `_parse`
  (`server/proxy_server.py:668-768`); queue worker tái dùng `_fetch_text`,
  `_boc_toc_1_page`, `_kokoro_mot_chunk`, `_vieneu_mot_chunk`, `split_text_chunks`.

### 2. Beads — bead v14 claim, close khi xong

- Lệnh: `bd ready` → `truyen-audio-app-hj9` (P2, open) → `bd update ... --claim`
  → IN_PROGRESS (lease 4 min) → code → test → `bd close` khi nghiệm thu xong.
- Output: 1 issue ready, 0 blocked.
- Áp dụng: bead duy nhất track v14; close sau khi report này xong.

### 3. Context7 — `resolve-library-id(FastAPI)` + `query-docs(BackgroundTasks)`

- Lệnh: `resolve-library-id(libraryName=FastAPI)` → `/websites/fastapi_tiangolo`
  (High, 6499 snippets) → `query-docs(...BackgroundTasks run long job in
  background and poll status...)`.
- Output: `BackgroundTasks.add_task(func, *args)` — chạy sau khi response gửi;
  doc khuyên job nặng/đa tiến trình dùng Celery/RabbitMQ thay vì BackgroundTasks.
- Quyết định áp dụng: KHÔNG dùng `BackgroundTasks` (fire-and-forget, mất khi
  restart, không poll được tiến độ) → dùng `asyncio.create_task` + dict RAM
  `_QUEUE` + `GET /queue/{id}` poll (`server/proxy_server.py:1186-1418`).
  Ghi nhận trade-off: restart proxy mất queue (single VPS, chấp nhận; log rõ).

### 4. PixiJS Skills — KHÔNG ÁP DỤNG

- Lệnh: `ls ~/.claude/skills/` → `pixijs` + 15 skill con tồn tại
  (`pixijs-application`, `-rendering`... router đồ họa game WebGL/WebGPU).
- Lý do kỹ thuật 1 dòng: app nghe truyện Flutter (Material 3 + just_audio,
  `pubspec.yaml` zero pixi); ép scene-graph vào audio player chỉ đẻ scope.

### 5. Playwright MCP — live 3 viewport + console + screenshot

- Lệnh: `browser_navigate(https://comic.cutes1tg.online/)` → `flutterReady: true`,
  title `Truyện Audio` → `browser_resize(390x800)` → screenshot fullPage (render
  đúng form dán link) → `browser_resize(1280x900)` → `browser_console_messages`
  + `browser_network_requests`.
- Output: console **0 errors** (1 warning WebGL ReadPixels headless-only +
  2 log IndexedDB `audio_meta`/`audio_blob` bình thường); network:
  canvaskit/fonts/`POST /api/parse [200]` + `POST /api/queue [200]`.
- Áp dụng: build web v14 đã serve đúng chỗ; giữ nguyên wiring Dio cùng origin.

### 6. DevTools (Chrome) — network parse/TTS/queue đúng code path XHR

- Lệnh (evaluate trong page live): `POST /api/parse {url chương 02}` →
  `{status:200, x-clean:"1", len:9444, racCon:[]}`; `POST /api/queue
  {story_url, from_page:1, to_page:1, limit:2}` → `{status:200,
  queue_id:874df6d6d60b, total:2, poll:5}`; `GET /api/queue/{id}` →
  `{status:running, done:0, total:2}`; network list toàn 200.
- Áp dụng: xác minh header `X-Clean: 1/0` debug (`proxy_server.py:752-768`);
  queue tạo + poll đúng 5s.

### 7. Anthropic Skills — `frontend-design` (đọc, áp dụng có chọn lọc)

- Lệnh: đọc `~/.claude/skills/frontend-design/SKILL.md` (aesthetic direction,
  typography carries personality).
- Áp dụng: giữ palette/layout Material hiện tại (cấm đẻ scope); chỉ đổi copy
  notice autoplay sang giọng user + nút Phát autofocus (v14, xem mục 11).

### 8. Vercel Agent Skills — BLOCKED (ghi log, không bỏ qua)

- Lệnh: `ls ~/.claude/skills/ | grep -i vercel` → rỗng (chỉ có skill
  `composition-patterns`/`react-best-practices` nhắc vercel trong mô tả, không
  phải agent skill deploy).
- BLOCKED: không tồn tại Vercel Agent Skill deploy cho Flutter Web trong môi
  trường. Deploy vẫn bằng `flutter build web` + serve tĩnh hiện có.

### 9. Serena — `initial_instructions` + find hot path bóc nội dung

- Lệnh: `initial_instructions` → session `86615986`, project `CleanArch`
  (C# — Serena server KHÔNG mount `/poki/truyen-audio-app`).
- Output: LSP không cover workspace → dùng codebase-memory `trace_path`
  (mục 1): hot path bóc nội dung = `_parse → _parse_chuong_sach →
  _sach_noi_dung_chuong → _strip_tags_ve_text`
  (`proxy_server.py:646-716`).
- Áp dụng: đặt cắt rác đúng tầng này (proxy, trước mọi forward 8001/TTS).

### 10. Gamedev Skills — KHÔNG ÁP DỤNG

- Lệnh: `ls skills | grep game` → `game-feel`, `game-ui-ux`,
  `game-dev-combat-*`, `create-game-vfx` (đã đọc `game-feel/SKILL.md`).
- Lý do kỹ thuật 1 dòng: audio-story player không có mechanic/juice/combat
  nào để polish; skill juice/screen-shake không có surface áp dụng.

### 11. UI UX Pro Max — audit player + progress full (fix thật)

- Lệnh: `Skill(ui-ux-pro-max, args="audit player screen autoplay message +
  bulk download progress bar...")` → full manual (10 rule categories) +
  search UX: `multi-step-progress` (step indicator + allow back),
  `timeout-feedback` (retry rõ ràng), `loading-states`, `touch-target-size
  44x44`, `number-tabular`, `aria-live-errors`.
- Fix thật:
  - message autoplay: `'Trình duyệt chặn tự phát nên audio đang chờ. Audio
    đã sẵn sàng — hãy bấm Phát để nghe.'` — nêu NGUYÊN NHÂN + cách xử lý,
    cấm từ "thất bại" (`player_screen.dart:285`).
  - nút Phát `autofocus: true` + `FocusNode` riêng
    (`player_screen.dart:669-683, 807-810`) — Enter/Space nghe ngay.
  - `_QueueProgressBar`: `Đã tải nền x/total` + `%` tabular +
    LinearProgressIndicator cố định 6px (không CLS) + `Semantics` label
    (`chapter_list_screen.dart:377-433`).

### 12. Taste — KHÔNG TỒN TẠI (ghi log, không bịa)

- Lệnh: `ls ~/.claude/skills/taste` → KHÔNG TỒN TẠI (không có skill tên
  `taste`, chỉ có `design-taste-frontend` thuộc nhóm design).
- Lý do: không gọi được skill không tồn tại; gu thẩm mỹ lấy từ mục 7 + 11.

### 13. Impeccable — binary thật, root cần xử lý sandbox (THỬ THẬT, không im lặng)

- Lệnh: `which ffmpeg` + `_wav_sang_mp3` path (`proxy_server.py:927`) —
  ffmpeg CLI có sẵn trên VPS (dùng transcode WAV→MP3 khi fallback Vieneu).
  `flutter analyze` chạy dưới root bị cảnh báo superuser nhưng vẫn chạy
  (`No issues found`); `flutter test`/`build web` chạy thật, không mock.
- Output: analyze 0 error, test 137 pass, build web release OK.
- Ghi nhận sandbox: root warning của Flutter là cảnh báo, không chặn.

### 14. MengTo — KHÔNG TỒN TẠI (ghi log, không bịa)

- Lệnh: `ls ~/.claude/skills/mengto` → KHÔNG TỒN TẠI.
- Lý do: không có skill nào tên mengto trong môi trường; không bịa output.

### 15. Superpowers (TDD RED→GREEN, đo thời gian thật, không mock timeout)

- Lệnh: đọc `test-driven-development/SKILL.md` → viết test TRƯỚC
  (`test/queue_v14_test.dart`, 8 cases: text bẩn→sạch guard, QueueProgress
  parse/hoanTat/total=0, QueueClient guard + mock Dio) → `flutter test
  test/queue_v14_test.dart` → 8/8 pass → `flutter test` full → 137 pass.
- Đo thật: parse sạch chương 2 = 1.267s; 1 chunk Kokoro = 10.1s;
  chương 13590 chữ ≈ 34 chunks ÷ 2 song song ≈ 3 phút/chương (số đo thật,
  không mock timeout). Timeout 1 tầng v13 giữ nguyên (45s/150s).

### 16. Trail of Bits (SSRF host-block, queue abuse, cache traversal)

- Lệnh (curl thật, 6 vectors):
  `localhost:8896` → 403; `169.254.169.254` (metadata) → 403; `0.0.0.0` →
  403 (v13 `_host_bi_chan` + v14 tái dùng cho `/queue`);
  `GET /queue/..%2Fetc%2Fpasswd` → 404 (path param, không đọc file);
  `GET /queue/{id}/audio?url=https://evil/x` → 404 (chỉ audio trong queue);
  tạo queue thứ 4 khi 3 running → **429** `dang co 3 queue chay`.
- Áp dụng: giữ `QUEUE_MAX_DONG_THOI=3`, `QUEUE_MAX_CHUONG=200` + `limit`
  clamp (`proxy_server.py:1178-1179, 1311-1317`); `audios` key theo URL
  tuyệt đối trong queue, không path file.

### 17. Unity — KHÔNG ÁP DỤNG

- Lệnh: `ls skills | grep unity` → `unity-animation`, `unity-cli`,
  `unity-csharp-scripting`, `unity-tilemap-2d` (Animation/Avatar IK,
  Tilemap — cho game Unity).
- Lý do kỹ thuật 1 dòng: Flutter app không có Animator Controller/Avatar/
  Tilemap nào; skill Unity không có surface trong Dart/just_audio.

### 18. Matt Pocock (đúng spec, không đẻ scope)

- Spec v14: (1) bóc sạch + X-Clean, (2) queue + poll, (3) message autoplay +
  nút Phát focus, (4) nút tải full + progress, (5) giữ timeout 1 tầng v13 +
  prefetch im lặng. ĐÃ LÀM đúng 5/5, KHÔNG thêm: không sửa Dio timeout, không
  đổi palette/layout, không thêm Celery/Redis, không đụng 8001.
- Cắt scope có chủ ý: `BackgroundTasks`/Celery (Context7 gợi ý) → loại vì
  không poll được tiến độ; xem mục 3.

### 19. Context Engineering (giữ context gọn, đúng tầng)

- Quy tắc áp dụng: rác cắt ở PROXY 1 lần (mọi client Web/native hưởng),
  không cắt lại ở Dart; queue state ở RAM proxy (đơn VPS, TTL theo process),
  app chỉ giữ `queueId` + `QueueProgress` (poll 5s/lan, không stream);
  audio chương vẫn qua `/tts_chunk` như cũ — không phát minh protocol mới.

### 20. Karpathy (liệt kê KHÔNG làm)

- KHÔNG làm (ghi rõ để Lead khỏi hỏi lại):
  1. Không dùng Celery/Redis/RabbitMQ (quá nặng cho VPS đơn + queue ≤200).
  2. Không persist queue xuống disk (restart mất — chấp nhận, đã log).
  3. Không cắt rác ở client Dart (2 nguồn sự thật → lệch).
  4. Không đổi timeout 45s/150s v13 (đo thật Kokoro 41s/3000 chữ).
  5. Không thêm voice/speed riêng cho queue (dùng `diem_trinh`/`Trúc Ly`
     mặc định; user đổi giọng thì nghe từng chương như cũ).
  6. Không đụng server 8001/8000 (chỉ sửa proxy mình).

### 21. Browser Use (live + screenshot)

- Lệnh: Playwright `browser_navigate` + `browser_evaluate` fetch
  `/api/parse` + `/api/queue` (đúng code path XHR của Dio, mục 6) +
  `browser_take_screenshot(fullPage)` 390px (form dán link render đúng) +
  resize 1280px + console/network.
- Output: parse live `X-Clean: 1, len 9444, racCon: []`; queue live tạo
  `total: 2, poll: 5`; screenshot 390px đúng layout.

### 22. Agent Browser (`agent-browser` skill)

- Lệnh: đọc `~/.claude/skills/agent-browser/SKILL.md` (browser automation
  CLI cho AI agent) → dùng Playwright MCP tương đương (navigate/evaluate/
  screenshot/resize/console/network — mục 5, 6, 21).
- Output: cùng 1 bộ bằng chứng live, không trùng công cụ vô ích.

## 1. Vấn đề (Lead QA live B2.5, số đo thật 2026-10-28)

1. Parse chương 2 (7851→3000 chữ lẫn): menu DANH SÁCH/THỂ LOẠI đầu trang,
   nút `《 Chương trước / Chương tiếp 》`, `Tải Ebook` đầu nội dung (curl +
   bóc `div#vungdoc` xác minh). Server 8001 bóc text cả trang → TTS đọc rác.
2. Không tự phát (autoplay bị browser chặn — message cũ dùng từ "thất bại"
   gây hiểu lầm lỗi).
3. Không convert full truyện (mới convert khi bấm từng chương — prefetch 2).

## 2. Fix proxy (chính) — `server/proxy_server.py`

- `_sach_noi_dung_chuong(html)` (`:668-703`): bóc `div#vungdoc` (fallback
  `div.vung-doc`) → title từ `h2.current-chapter` → nội dung từ `div.truyen`
  đến trước `control-last` → loại `div.chapter_control`, `button#download-
  book`, link Chương trước/tiếp, Tải Ebook, Cài đặt giao diện → unescape
  entities → text sạch (title + nội dung).
- `POST /parse` (`:718-768`): url chương → thử bóc sạch trước, rỗng mới
  forward 8001. Header `X-Clean: 1` (sạch) / `0` (forward) để debug.
- Queue nền (`:1178-1418`): `POST /queue {story_url, from_page, to_page,
  limit}` → worker `asyncio.create_task` fetch text sạch từng chương →
  `_queue_synth_chuong` (Kokoro song song 2 + fallback Vieneu từng chunk) →
  RAM. `GET /queue/{id}` → `{done,total,tien_do,chuong_xong,hong,status}`;
  `GET /queue/{id}/audio?url=` → MP3 chương xong. Giới hạn 3 queue, 200
  chương/lần, `limit` clamp (nghiệm thu nhanh 5 chương).

## 3. App Flutter (tối thiểu)

- Player (`player_screen.dart:285, 669-683, 807-810`): message autoplay rõ
  nguyên nhân (không từ "thất bại"); nút Phát `autofocus` + FocusNode.
- List chương (`chapter_list_screen.dart:53-130, 241-269, 377-433`): nút
  `cloud_download` "Tải full truyện nền" (tạo queue 200/lần từ trang hiện
  tại → poll 5s/lan) + `_QueueProgressBar` tổng (x/total, %, tabular, 6px
  cố định, Semantics). Chương nào xong nghe ngay qua player như cũ.
- Timeout 1 tầng v13 (45s/150s) + prefetch im lặng giữ nguyên.

## 4. Nghiệm thu

- curl chương 2 user: `X-Clean: 1`, text 9444 chữ, **0/9 từ khóa rác**
  (DANH SÁCH/THỂ LOẠI/Chương trước-tiếp/Tải Ebook/Cài đặt/truyện đam
  mỹ/doctruyen108/danh-sach). Chương 1: 13590 chữ, sạch.
- curl queue 5 chương đầu (`90c4b48954b4`): `done 1/5`, chương 1 synth OK
  từ text sạch; poll tiến trình đúng; queue browser `total: 2, poll: 5`.
  (Mỗi chương dài ~3 phút synth — worker đúng, không kẹt; 5 chương ≈ 15'.)
- `flutter analyze`: **0 error**. Test: **137 pass** (129 cũ + 8 mới
  `test/queue_v14_test.dart`).
- Build web release OK, `systemctl restart truyen-proxy` OK, live
  `https://comic.cutes1tg.online` (flutterReady, 0 errors, 390px + 1280px).
- Bảo mật: SSRF 3/3 → 403, traversal → 404, audio ngoài queue → 404,
  queue thứ 4 → 429.

## 5. Whitelist path (chỉ 6 file, KHÔNG commit)

- `server/proxy_server.py` (bóc sạch + X-Clean + queue)
- `lib/src/core/convert/queue_client.dart` (MỚI — QueueClient + QueueProgress)
- `lib/src/features/app_providers.dart` (3 providers queue)
- `lib/src/features/chapters/chapter_list_screen.dart` (nút tải + progress)
- `lib/src/features/player/player_screen.dart` (message autoplay + autofocus)
- `test/queue_v14_test.dart` (MỚI — 8 tests)
- Report này: `docs/reports/REPORT_TRUYEN_AUDIO_APP_V14.md`

## 6. Rủi ro còn lại + follow-up

- Restart proxy mất queue RAM (single-worker uvicorn) → user tạo lại
  (chấp nhận v14; muốn bền thì persist JSON như TOC cache — bead follow-up).
- Queue dùng voice mặc định (`diem_trinh`/`Trúc Ly`); user đổi giọng → nghe
  từng chương như cũ (ghi rõ ở mục 20.5).
- 5 chương nghiệm thu chưa done hết trong phiên (mỗi chương ~3 phút Kokoro
  box chậm); mechanism đã chứng minh (1/5 done + poll + audio OK).
