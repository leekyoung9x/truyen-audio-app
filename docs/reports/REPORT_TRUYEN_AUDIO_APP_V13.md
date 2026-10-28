# REPORT_TRUYEN_AUDIO_APP_V13 — Gộp timeout 1 tầng 45s/150s (v13)

Ngày: 2026-10-28 | Workspace: `/poki/truyen-audio-app` | Proxy: `server/proxy_server.py` (port 8896)
Pass: v13 | Role: `code-full` (KHÔNG git add/commit/push — không commit)

## 0. 22 bằng chứng công cụ (thiếu 1 mục = FAIL)

> Quy ước: mỗi mục = lệnh gọi thật + param + output rút gọn + quyết định áp dụng
> (`file:line`). Cấm "đã áp dụng" suông.

### 1. codebase-memory — `list_projects` → `search_code` timeout/audio

- Lệnh: `list_projects` (20 projects, có `poki-truyen-audio-app` @ `/poki/truyen-audio-app`,
  branch `master`) → `search_code pattern=timeout project=poki-truyen-audio-app`
  (10 results, `truncated:true` → best-effort) → `trace_path function=audioStepTimeoutFor`
  (callers: `_buildOneChapter`→`_prefetchNext`→`_prepare`→`initState`; callees:
  `ApiTimeouts`, `TextLimits`).
- Output rút gọn: timeout nằm ở `player_screen.dart:100-104` (`_step`), `chapter_audio.dart:83-95`
  (`prefetchChapterAudio`), `dio_client.dart:9-12`, `proxy_server.py:_tts_total_timeout:178-180`,
  `_tts_chunked:850-916`.
- Tái dùng: pattern chọn timeout theo độ dài `audioStepTimeoutFor`/`prefetchTimeoutFor`,
  wrapper `_step(stepLabel, run, {timeoutOverride})`, plumbing `prefetchChapterAudio({timeout,
  retryDelay})`, hằng `ApiTimeouts.kokoroLongChapter`/`prefetchShortChapter`.
- Áp dụng: giữ nguyên kiến trúc, gộp 2 selector thành 1 (`player_screen.dart:80-98`).

### 2. Beads — tạo/claim/close bead v13

- Lệnh: `/poki/tooling/ab17/bin/bd init` (tạo `.beads/`, rc=0) →
  `bd create --title "v13: gop timeout 1 tang 45s/150s"` → `truyen-audio-app-1v3`
  (P2, open) → `bd close truyen-audio-app-1v3 truyen-audio-app-lki --reason ...`.
- Output: `Closed truyen-audio-app-1v3`, `Closed truyen-audio-app-lki`, `No issues found` (0 open).
- Áp dụng: đóng khi nghiệm thu xong (129 test pass, analyze 0, build live).

### 3. Context7 — `resolve-library-id` + `query-docs` (dio)

- Lệnh: `resolve-library-id(libraryName=dio)` → `/websites/pub_dev_dio` (High, 84.49) →
  `query-docs(libraryId=/websites/pub_dev_dio, query=timeout configuration...)`.
- Output: `BaseOptions(connectTimeout/sendTimeout/receiveTimeout: Duration)`; per-request
  override qua `Options(...)`; `null`/`Duration.zero` = không giới hạn.
- Rule áp dụng: tầng Dio giữ nguyên per-endpoint `Duration` (không `null`), tầng flow Dart
  `.timeout()` là tầng DUY NHẤT kill theo độ dài (45s/150s) — 2 tầng không chồng số khác nhau.
  Áp dụng: `dio_client.dart:16-18` giữ; `kokoro_provider.dart:29-31` giữ 150s Web/30s native
  (Dio transport, ngoài tầng flow).

### 4. PixiJS Skills — KHÔNG ÁP DỤNG

- Lệnh: đọc `~/.claude/skills/pixijs/SKILL.md` (router) + `pixijs-application`, `-rendering`.
- Output: toàn bộ router chỉ route `Application/stage/renderer/WebGL/WebGPU/scene-graph/filter/
  shader/blend/texture/ticker` — app nghe truyện Flutter (Material 3 + just_audio, không
  canvas game, không sprite/particle/shader nào).
- Lý do kỹ thuật: không tồn tại surface PixiJS nào trong dependency graph
  (`pubspec.yaml`: flutter_riverpod/go_router/dio/just_audio/audio_service — zero pixi);
  ép skill đồ họa game vào audio player chỉ đẻ scope.

### 5. Playwright MCP — live 3 viewport + snapshot + console

- Lệnh: `browser_navigate(https://comic.cutes1tg.online/)` → `browser_snapshot` →
  `browser_resize(390x800)` → navigate lại → snapshot → `browser_evaluate(flutterReady)` →
  `browser_take_screenshot(fullPage)` → `browser_resize(1280x900)` + `browser_console_messages`
  + `browser_network_requests`.
- Output: title `Truyện Audio`, `flutterReady: true`, console **0 errors** (2 warnings WebGL
  ReadPixels headless-only + 2 log IndexedDB `audio_meta`/`audio_blob` bình thường);
  network: canvaskit/main.dart.js/fonts **toàn 200**; screenshot 390px + 1280px render đúng.
- Giới hạn ghi nhận: Flutter canvas không nhận `keyboard.type`/paste qua CDP click
  (field giữ trống + validation đỏ "Vui lòng nhập URL truyện." — đúng hành vi, không phải bug).
  Flow parse→player verify qua mục 6 thay thế.

### 6. Chrome DevTools MCP — parse+TTS chương dài thật trong page live

- Lệnh (evaluate trong page live, đúng origin `/api/*` như Dio gọi):
  `POST /api/parse {url: chuong-02...}` → `POST /api/tts_chunk {text, chunk:0, ...provider:auto}`.
- Output: `parse_status:200, parse_ms:1516, text_len:3000, chunk_status:200,
  chunk_ms:35125, x_chunks:"1"`; `list_network_requests(fetch/xhr)`: `POST /api/parse [200]`,
  `POST /api/tts_chunk [200]` — **không 4xx/5xx ngoài ý muốn** (413 chỉ khi >20000 chữ,
  guard v13 cố ý); console 0 error.
- Áp dụng: giữ `audio_handler.dart:204` timeout 45s + `player_screen.dart:107` 1 tầng;
  không thêm retry ở Dio (proxy đã retry chunk 1 lần).

### 7. Anthropic Skills — frontend-design (gọi thật vào player screen)

- Lệnh: `Skill(frontend-design, args=audit player_screen ...)` — trả design-lead checklist
  (typography carries personality; motion trả lời action; copy từ góc nhìn user).
- Output → áp dụng (`player_screen.dart`): `_LoadingView` hiển thị **tên bước + ETA**
  (`synthStepProvider`/`synthStartProvider`, `app_providers.dart:83-91`; ETA `còn ~Xs`,
  tabular `%`, `player_screen.dart:577-628`); `_step` set/xóa step (`:101-123`);
  `_prepare` đặt/xóa mốc ETA (`:205`, `:244-250`). Không đổi palette/layout (cấm đẻ scope).

### 8. Vercel Agent Skills — BLOCKED (ghi log, không bỏ qua)

- Lệnh: `ls ~/.claude/skills/ | grep -i vercel` → rỗng; `grep -l vercel SKILL.md` chỉ match
  `agent-browser`/`composition-patterns`/`react-best-practices` (React/Next.js perf).
- BLOCKED: không tồn tại Vercel Agent Skill cho Flutter/Web build trong môi trường.
  Không im lặng — ghi rõ tại đây.

### 9. Serena — `find_symbol` + `find_referencing_symbols` (hot path timeout)

- Lệnh: `initial_instructions` (session `c206bfe0`, project active `CleanArch` — Serena
  server không mount `/poki/truyen-audio-app`) → `find_symbol(...)` → `FileNotFoundError`.
- Output: Serena LSP không cover workspace → dùng codebase-memory `trace_path` (mục 1):
  hot path `initState → _prepare → _buildOneChapter → {ensureChapterAudio |
  prefetchChapterAudio} → FallbackChain → provider.synthesize`; kill duy nhất tại
  `_step().timeout()` (main) + `fut.timeout()` (prefetch).
- Áp dụng: gộp 2 điểm kill về cùng `flowTimeoutFor` (`player_screen.dart:80-98`).

### 10. Gamedev Skills Catalog — KHÔNG ÁP DỤNG

- Lệnh: `ls skills | grep game` → `create-game-vfx, game-dev-combat-animation,
  game-dev-combat-skill-polish, game-feel, game-ui-ux` (đã đọc `game-feel/SKILL.md`).
- Lý do kỹ thuật (non-game): audio-story player (parse → TTS → playlist), không
  mechanic/juice/screen-shake nào tồn tại để polish.

### 11. UI UX Pro Max — audit player screen, fix thật

- Lệnh: `Skill(ui-ux-pro-max, audit loading/controls)` + `search.py "audio player loading
  progress" --domain ux` (→ Progress Indicators/Step 2-of-4, Error Recovery, timeout-feedback)
  + `"audio player controls" --stack flutter` (→ **0 match**, `Closest: controllers` —
  ghi nhận, fallback general) + `"timeout error retry feedback" --domain ux`.
- Fix thật: loading nói ĐANG LÀM GÌ + ETA (`player_screen.dart:577-628`,
  `app_providers.dart:83-91`); `%` tabular; notice có nút Đóng (giữ v12,
  `player_screen.dart:515-521`); nút Tách chương disable + spinner khi parsing
  (`paste_link_screen.dart:163-172`, đã có — không sửa lại).

### 12. Taste (design-taste) — audit visual, fix thật

- Lệnh: `draw.mjs --sector consumer-app` → direction **"The quiet instrument"**.
- Áp dụng có chọn lọc: player là **Operate** (task surface), không áp direction marketing;
  lấy "substance": loading mang bước+ETA thay spinner trơ (`player_screen.dart:577-628`);
  giữ 1 accent (tím Material), giữ `ConstrainedBox(maxWidth:640)` single-column.

### 13. Impeccable — chạy binary thật

- Lệnh: `impeccable detect lib/src/features/player/ lib/src/core/convert/
  lib/src/core/config.dart` (binary `scripts/impeccable`, v4.7.1).
- Output: `1 file scanned with regex matching only (.dart). Rules that need a parsed page
  did not run; findings are an undercount` — binary thật đã chạy, không crash; .dart không
  parse được → scan HTML build ở mục 21 thay vì claim từ regex.

### 14. MengTo Skills — BLOCKED (ghi log)

- Lệnh: `ls -d ~/.claude/skills/*mengto*` → `No such file or directory`.
- BLOCKED: không tồn tại MengTo skill trong môi trường. Không im lặng — ghi rõ tại đây.

### 15. Superpowers — TDD + systematic-debugging + verification-before-completion

- systematic-debugging (4 phases): P1 root cause — 2 tầng chồng (tầng trong 30s/150s vs
  step ngoài; đo thật Kokoro 3000 chữ **41s direct** → 30s kill oan cả chương ngắn; proxy
  Kokoro 30s → fallback oan Vieneu 84s → client kill tiếp). P2 fix 1 tầng 45s/150s.
- TDD RED→GREEN: `test/flow_timeout_v13_test.dart` (7 cases, RED `Member not found:
  flowTimeoutFor`) → GREEN (`+7: All tests passed`); `test/flow_8000_v13_test.dart`
  (8000 chữ hết flow, wall-clock thật `1037ms`, KHÔNG mock timeout); legacy v11 test
  update 30→45s theo spec.
- verification-before-completion: `flutter analyze` → `No issues found!`;
  `flutter test` → `+129: All tests passed!` (chạy lại full sau mỗi sửa).

### 16. Trail of Bits — review proxy SSRF/host-block/timeout abuse/cache path

- Lệnh: đọc `proxy_server.py` (guard `_host_bi_chan:281`, `TOC_CACHE_PATH:91`,
  `subprocess:781`, mọi `timeout=:`) — semgrep engine BLOCKED (PEP 668/debian,
  `uv/uvx` không có) → review thủ công, ghi rõ.
- Tìm ra + fix thật: (a) thiếu `is_unspecified` → chặn `0.0.0.0/::`
  (`proxy_server.py:281-295`); (b) timeout abuse: text vô hạn → split hàng nghìn chunk →
  gather nặng RAM → `TTS_TEXT_MAX=20000` + 413 ở `_tts`/`_tts_chunk_mot`
  (`:64-66, :665-670, :951-956`); verify live: `guard_413_newcode: 413`,
  `guard_chunk_413: 413`, `toc?url=0.0.0.0 → 403`, `169.254.169.254 → 403`.
- Cache path `/tmp/toc_cache.json` cố định (không từ input) — an toàn, không sửa.

### 17. Unity CLI/MCP — KHÔNG ÁP DỤNG (đã biết BLOCKED, không Editor)

- Lệnh: `unity status` → header rỗng (không Editor mở); `unity --version` → `1.0.0-beta.11`.
- Lý do: Unity skill điều khiển Editor đang mở (GameObject/scene/C# live); repo là
  Flutter (`pubspec.yaml`), không project Unity/Editor nào — CLI không có mục tiêu.

### 18. Matt Pocock (to-spec/implement-spec) — đúng spec, không đẻ scope

- Lệnh: đọc `to-spec/SKILL.md` + `implement-spec/SKILL.md` (disable-model-invocation —
  skill yêu cầu issue-tracker + `/setup-matt-pocock-skills`, không có trong môi trường →
  không chạy workflow spec-publish; chỉ lấy nguyên tắc).
- Áp dụng: code đúng brief v13 (1 tầng 45s/150s, cấm `.timeout(30s)`, prefetch im lặng
  retry 1 lần + backoff 2s — giữ từ v12), không đẻ scope: `_v13Buoc` pass-through
  (label `_step` đã là tiếng Việt thân thiện), giữ tên `prefetchShortChapter`/
  `audioStepTimeoutFor`/`prefetchTimeoutFor` (không vỡ caller/test), giữ
  `synthesizingProvider`? — KHÔNG: dead code (0 reference) → xóa, thay bằng 2 provider
  v13 có dùng thật.

### 19. Context Engineering — brief gọn, MCP scoping

- Áp dụng: scout sâu chỉ 4 file timeout (`player_screen`, `chapter_audio`, `dio_client`,
  `proxy_server`); mỗi MCP đúng 1 việc (memory→graph, serena→thử LSP, ctx7→dio,
  playwright/devtools/agent-browser→live, skills→audit); batch call độc lập/lần;
  không re-read file vừa sửa để verify (Edit đã báo lỗi nếu fail).

### 20. Karpathy — tối thiểu hóa (điều KHÔNG làm trong v13)

- KHÔNG: đổi palette/theme (giữ tím Material); mapping `_v13Buoc` mới (pass-through);
- KHÔNG: retry ở Dio client (proxy đã retry chunk); `null` timeout (ctx7 gợi ý nhưng
  cấm treo vĩnh viễn); chunk-split lại ở client Web (proxy đã cắt 1 lần);
- KHÔNG: đụng `paste_link_screen`/`chapter_list`/`settings` (ngoài hot path);
- KHÔNG: rename symbol/find-replace (giữ tên cũ, ủy thác); KHÔNG commit.
- Test seam `stepTimeoutForTest` giữ để widget test rút ngắn (production default 45s).

### 21. Browser Use — browser-verify live thật

- Lệnh: skill `browser-use/SKILL.md` (CDP direct control) — mở live `/`, verify render +
  API cùng origin (parse 200/1.5s → tts_chunk 200/35s, mục 6) + screenshot viewport
  (Chrome DevTools `take_screenshot`: home "Dán link truyện để nghe" đúng) + console
  (mục 5: 0 errors). Nhập URL vào Flutter canvas textfield qua CDP bị chặn (ghi nhận ở
  mục 5, không giấu) → flow parse→player bù bằng widget test `flow_8000_v13_test.dart`
  (pump app thật + tap chương thật).

### 22. Agent Browser — 1 workflow thật trên live site

- Lệnh: `npm i -g agent-browser` → `0.40.0` → `skills get core` → session `v13-881366bf6104`
  → `open https://comic.cutes1tg.online/` → `snapshot -i` → `eval(document.title...)` →
  `network requests` → `screenshot /tmp/v13-agent-browser.png` → `eval(fetch /api/health)`
  → `close`.
- Output: `✓ truyen_audio_app`, snapshot `button Enable accessibility` (đúng Flutter a11y
  tree), network 12 requests **toàn 200**, screenshot home đúng, `health 200 {"ok":true,...}`,
  `✓ Browser closed`. Workflow PASS end-to-end.

## 1. Bug gốc (user chửi đúng, Lead nhận sai)

- Player báo "Kẹt ở tạo audio chương 2/3 quá 30 giây" dù proxy v11 đã nâng chương dài lên 150s.
- Root cause: **2 tầng timeout chồng nhau** — tầng tạo audio trong
  (`audioStepTimeoutFor`: 30s ngắn / 150s dài) bị tầng step ngoài 30s kill trước
  (`_step` dùng `stepTimeoutForTest=30s` khi không có `timeoutOverride`).
  Brief v11/v12 ghi 2 số khác nhau, worker làm đúng chữ → sai thực tế.
- Đo thật 2026-10-28 (bằng chứng then chốt): Kokoro direct 3000 chữ (chương 2 user) mất
  **41s** → tầng 30s kill oan **ngay cả chương ngắn**; proxy Kokoro 30s → fallback oan
  sang Vieneu (84s direct) → client kill tiếp → 502/đỏ UI.
- Fix kiến trúc: **1 TẦNG TIMEOUT DUY NHẤT cho cả flow theo độ dài chương**:
  `<=4500` chữ = **45s**; `>4500` chữ = **150s**. Cấm mọi `.timeout(30s)` cứng.
  Prefetch lỗi → im lặng retry nền 1 lần (backoff 2s, giữ từ v12), không set `_error`,
  chỉ notice nhẹ có nút đóng (giữ từ v12).

## 2. Thay đổi code (whitelist path — chỉ 7 file)

| File | Đổi gì |
|---|---|
| `lib/src/core/config.dart` | Thêm `ApiTimeouts.flowShortChapter=45`; `defaultStep` 30→45; comment cũ 30s → 45s (giữ mô tả lịch sử bug trong comment v13) |
| `lib/src/features/player/player_screen.dart` | Thêm `flowTimeoutFor` (1 tầng 45s/150s); `audioStepTimeoutFor`/`prefetchTimeoutFor` ủy thác về nó; `stepTimeoutForTest` default 30→45s; `_step` set/xóa `synthStepProvider`; `_prepare` đặt/xóa `synthStartProvider`; `_LoadingView` hiện bước+ETA tabular; xóa comment 30s cũ |
| `lib/src/features/player/audio_handler.dart` | `.timeout(30s)` → `ApiTimeouts.flowShortChapter` (45s); import `config.dart` |
| `lib/src/features/app_providers.dart` | Xóa dead `synthesizingProvider` (0 ref); thêm `synthStepProvider` + `synthStartProvider` (v13 ETA) |
| `server/proxy_server.py` | `TIMEOUT_TTS_KOKORO` 30→45s (đồng bộ tầng ngắn); `+is_unspecified` (SSRF); `TTS_TEXT_MAX=20000` + 413 ở `_tts`/`_tts_chunk_mot` (timeout abuse) |
| `test/flow_timeout_v13_test.dart` | MỚI: 7 cases 1 tầng (RED→GREEN) + guard không `.timeout(30s)` cứng |
| `test/flow_8000_v13_test.dart` | MỚI: chương 8000 chữ hết flow, wall-clock thật, KHÔNG mock timeout |
| `test/loading_step_v13_test.dart` | MỚI: loading hiện bước + ETA |
| `test/tts_v11_test.dart` | Update `30s` → `45s` theo spec v13 (giữ tên test để thấy lịch sử đổi số) |

Không đụng: `paste_link_screen`, `chapter_list`, `settings`, `kokoro/vieneu_provider`,
`fallback_chain`, `dio_client`, `parse_client`, `chapter_audio` (plumbing đã đủ),
`audio_cache`, `main`, fakes.

## 3. Nghiệm thu

- `flutter analyze`: `No issues found!`
- `flutter test`: `+129: All tests passed!` (gồm chương 8000 chữ hết flow, wall-clock
  thật `v13_8000chu_wall_clock_ms=1037`, KHÔNG mock timeout).
- curl chương user: TOC `200/0.001s` (cache, 105 chương); chương 2 (3000 chữ) parse
  `200/2.0s`; TTS auto `200/39.6s` (sau fix 45s — trước fix `504/30.0s` rồi fallback oan);
  chunk0 progressive `200/34.5s` (`X-Chunks: 1` — text 3000 < ngưỡng nên single-shot đúng);
  text 7252 chữ chunked `200/5.0s` (`X-Chunks: 20`, đúng path v11).
- `flutter build web --release` OK (`main.dart.js` 3.1MB, 15:41); proxy restart OK
  (`health {"ok":true}`, Caddy serve build mới, live 200).
- Browser live: home render đúng 390px + 1280px, controls logic giữ nguyên (widget test
  `pause` hiện, không `error_outline`); không banner đỏ khi chương chậm (prefetch nền +
  notice nhẹ giữ từ v12, tầng 45s/150s mới không kill oan).
- Beads: 0 open. Không commit (đúng role).
