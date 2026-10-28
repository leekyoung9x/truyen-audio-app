# REPORT — App truyện-audio pass 2 (skill audit + fix, v2)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | Role: `code-full`
Brief: `/poki/briefs/TRUYEN_AUDIO_APP_V1_20261027.md` mục 7 ADDENDUM (checklist bắt buộc pass này)

V1: `docs/reports/REPORT_TRUYEN_AUDIO_APP_V1.md`. Pass này SỬA TRỰC TIẾP vào source v1.

## 0. Tóm tắt thay đổi v2

| # | Nhóm skill (brief) | Fix thật vào source | File:line (sau sửa) |
|---|---|---|---|
| 3 | Context7 (riverpod-2.5/go_router-14/dio-5/just_audio-0.9/audio_service-0.18/hive-2) | Đối chiếu API: `Provider.overrideWithValue`, `GoRouter(context.go/canPop)`, `BaseOptions(connectTimeout: Duration, ResponseType.bytes)`, `AudioSource.file`, `BaseAudioHandler+QueueHandler+SeekHandler`, `Hive.openBox/put/get` — code v1 ĐÚNG, không phải sửa API. Ghi rule áp dụng (§1) | — |
| 3 | Context7 | Dio v1 thiếu CancelToken (comment trong `dio_client` sai sự thật) → thêm `cancelToken` xuyên suốt `TtsProvider.synthesize → Vieneu/Kokoro → FallbackChain → ensureChapterAudio` | `core/tts/tts_provider.dart:42-47`, `vieneu_provider.dart:45-51,73`, `kokoro_provider.dart:46-52,64,81,112-127`, `fallback_chain.dart:29-45,50-75`, `convert/chapter_audio.dart:24-25,54-61` |
| 9 | Serena (`find_symbol` + `find_referencing_symbols`) | Serena session bị gắn project C# (`CleanArch`), không dùng cho workspace Dart → thay bằng codebase-memory graph: `search_graph FallbackChain` (25 hits) + `trace_path synthesize/splitIntoChunks` + `check_index_coverage` 4 file core (no_recorded_issue). Phát hiện hot path convert: `KokoroProvider.synthesize` (batch song song) + `splitIntoChunks` | §2 |
| 15 | Superpowers TDD/debug/verify | Viết `test/` cho `fallback_chain` (Vieneu→Kokoro khi timeout) + chunk/concat Kokoro (~400 ký tự, song song ≤4 — mock `HttpClientAdapter` đếm in-flight) + magic-bytes + guard parse. Review vòng 1b bắt bug thật: `synthesize()` quên forward `cancelToken` → fix | `test/fallback_chain_test.dart`, `test/kokoro_concat_test.dart`, `test/parse_and_magic_test.dart`, `fallback_chain.dart:37-43` |
| 11+12+13 | ui-ux-pro-max + design-taste-frontend + impeccable | Audit 3 màn hình, fix: icon trang trí `excludeFromSemantics`, `Semantics(liveRegion)` cho lỗi parse, `autofillHints.url`, `AutovalidateMode.onUserInteraction`, `Semantics(button/selected/label)` từng chương, subtitle giữ chỗ progress (chống CLS), `Colors.red` → `colorScheme.error`, title `maxLines/ellipsis`, slider `SliderTheme` + thumb 10px, time `FontFeature.tabularFigures`, nút play `minimumSize 72x72` (≥48dp) + `semanticLabel` | `paste_link_screen.dart:83-91,102-113,119-125,131-144,149-155`, `chapter_list_screen.dart:60-100`, `player_screen.dart:1,236-320` |
| 16 | Trail of Bits | `parseUrl` chỉ nhận http/https (chặn `file://`, anti-SSRF client-side); cache `_checkKey` (md5 hex 32) + `_checkExtension` (`[a-z0-9]+`) chặn path traversal, `remove()` sanitize `fileName` từ metadata ngoài; `AudioHandler.loadPlaylist` từ chối playlist rỗng + file không tồn tại; `dispose()` đóng timer/stream/player | `parse_client.dart:54-67`, `cache/audio_cache.dart:65-72,94-117,136-137,163-186`, `player/audio_handler.dart:142-163,223-231` |
| 18 | Matt Pocock / implement-spec | Mọi fix bám spec v1, không đẻ scope mới (không thêm màn hình, không đổi cây thư mục) | — |
| 20 | Karpathy | Cắt scope: KHÔNG persist settings ra Hive (giữ StateProvider v1), KHÔNG bulk-offline (giữ `ensureChapterAudio` 1 chương, v2 gọi lặp), KHÔNG retry/backoff trong Dio (timeout + fallback đã đủ v1), KHÔNG xóa `cached_network_image/shimmer/flutter_animate` khỏi pubspec dù chưa import (giữ cho v2 dùng) | §6 |
| 1 | codebase-memory | `list_projects` (19 projects, chưa có truyen-audio-app) → `search_code` dio/audio-cache trong `/poki` (0 hit — không có code tái dùng) → `index_repository` workspace mới: **indexed, 185 nodes / 515 edges**, project `poki-truyen-audio-app` | §7 |

KHÔNG DÙNG (lý do, không phải bỏ sót — theo brief):
- 4 PixiJS / 10 Gamedev / 17 Unity: game-only, app này không có canvas/game loop.
- 5 Playwright / 6 DevTools / 21 Browser Use / 22 Agent Browser: chỉ có ý nghĩa khi build Web — để dành pass QA Web riêng.
- 7 Anthropic / 8 Vercel / 14 MengTo: web/React-centric, không khớp Flutter.
- Beads (#2 trong brief): tracking task nhẹ — pass này task list ngắn, theo dõi trực tiếp trong report thay vì tool riêng.

## 1. Context7 — lệnh thật + output rút gọn + quyết định

`resolve-library-id` (3 calls): riverpod → `/rrousselgit/riverpod` (+`/websites/pub_dev_flutter_riverpod`);
go_router → `/websites/pub_dev_packages_go_router`; dio → `/websites/pub_dev_packages_dio`
(+`/websites/pub_dev_dio`, benchmark cao nhất 84.49 nhưng query cùng nội dung).

`query-docs` (6 calls, version trong brief được xác nhận qua changelog/API docs):
1. `flutter_riverpod` "StateProvider Provider overrideWithValue 2.5" →
   `Provider.overrideWithValue(value)` tồn tại (signature `Override overrideWithValue(ValueT)`).
   **Áp dụng:** `main.dart:46-47` + `app_providers.dart:24` ĐÚNG — giữ nguyên.
2. `dio` "BaseOptions Duration ResponseType bytes" →
   `BaseOptions(baseUrl, connectTimeout: Duration, receiveTimeout: Duration)`,
   `Options(responseType: ResponseType.bytes)`, `CancelToken` per-request.
   **Áp dụng:** v1 ĐÚNG timeout/`ResponseType.bytes`; SAI comment "CancelToken" trong
   `dio_client.dart` (không có param nào nhận token) → **fix:** docstring sửa thành
   per-request token + thêm `CancelToken? cancelToken` vào mọi `synthesize`/`parseUrl`/`parseText`.
3. `go_router` "GoRouter context.go canPop 14" → `GoRouter(routes:)`, `context.go()`,
   `canPop()` (từ 4.1, vẫn có ở 14.8.1).
   **Áp dụng:** `main.dart:15-22`, `settings_screen.dart:75` ĐÚNG — giữ nguyên.
4. `just_audio` "AudioSource.file" → `AudioSource.file(path, {tag})` = `AudioSource.uri(Uri.file(...))`.
   **Áp dụng:** `audio_handler.dart:157` ĐÚNG — giữ nguyên, thêm guard file-exists trước khi load.
5. `audio_service` "BaseAudioHandler QueueHandler SeekHandler 0.18" →
   `class X extends BaseAudioHandler with QueueHandler, SeekHandler`,
   `skipToQueueItem(i) => seek(Duration.zero, index: i)`, `AudioService.init(builder, config)`.
   **Áp dụng:** `audio_handler.dart:49,142-176`, `main.dart:32-40` ĐÚNG — giữ nguyên, thêm `dispose()`.
6. `hive` "openBox put get" → `Hive.openBox()`, `box.put/get/delete/clear`.
   **Áp dụng:** `audio_cache.dart` ĐÚNG — giữ nguyên, thêm validate key/extension.

Rule Context7 áp dụng vào code: **mọi API đối chiếu đều tồn tại ở đúng version brief —
không đổi call-site; chỉ bổ sung param/guard còn thiếu** (CancelToken, guards, dispose).

## 2. Serena → codebase-memory graph (thay thế có lý do)

Serena `initial_instructions` trả về session gắn project `CleanArch` (C#, LS csharp) —
`find_symbol`/`find_referencing_symbols` trên workspace Dart sẽ sai scope nên KHÔNG dùng tiếp
(tránh kết quả giả). Thay bằng codebase-memory (đúng tier verify):

- `search_graph query="FallbackChain synthesize fallback chain"` → 25 hits, top:
  `FallbackChain.synthesize` (fallback_chain.dart:29-35),
  `FallbackChain.synthesizeWithProvider` (:49-55),
  `KokoroProvider._synthesizeChunk` (kokoro_provider.dart:103-107),
  `KokoroProvider.splitIntoChunks` (:125).
- `trace_path synthesize` (ambiguous → 3 candidates, qualify bằng FQN):
  `...fallback_chain.FallbackChain.synthesize` → callees {synthesizeWithProvider, ProviderOrder,
  TtsAllFailedException}, callers 0 (public API, gọi từ `ensureChapterAudio` qua code-read —
  graph chưa index edge này, đã đọc source xác nhận `chapter_audio.dart:48-56`).
- `trace_path splitIntoChunks` → caller duy nhất `KokoroProvider.synthesize`,
  callee duy nhất `TextLimits` ⇒ **hot path convert** = `splitIntoChunks → batch song song ≤4 →
  concat giữ thứ tự → magic-bytes → cache**. Không phát hiện vòng lặp/rò rỉ ngoài bug
  `cancelToken` đã fix (§0).
- `check_index_coverage` 4 file core → `no_recorded_issue, metadata_match` cả 4 (best-effort caveat
  đã ghi nhận; các dòng trích dẫn đã đọc source trực tiếp để qualify).

## 3. TDD — test viết theo spirit (không SDK nên chưa chạy được)

3 file (`test/` mới, dùng `flutter_test` đã có trong `dev_dependencies`):
- `test/fallback_chain_test.dart` — 6 tests: Vieneu thắng / timeout DioException → Kokoro /
  StateError audio-rỗng → Kokoro / ArgumentError KHÔNG fallback / cả 2 fail → TtsAllFailedException /
  kokoroFirst thứ tự ngược. Fake `_FakeProvider` (không mock framework).
- `test/kokoro_concat_test.dart` — mock `HttpClientAdapter` (`_CountingAdapter` đếm in-flight):
  text ~1350 ký tự → N chunk, `maxInFlight ≤ 4` và `> 1`, bytes nối đúng thứ tự (`ID3` header mỗi chunk),
  progress kết thúc 1.0; speed 99 → clamp 1.5 (intercept `options.data['speed']`).
- `test/parse_and_magic_test.dart` — magic bytes RIFF/WAVE→wav, ID3→mp3, frame-sync→mp3, rỗng→mp3;
  `parseUrl('file:///etc/passwd')` / text-không-URL / `parseText(' ')` → `throwsArgumentError`
  (không cần server thật).
- Chạy khi có SDK: `flutter test` (chưa chạy được trên VPS — thiếu Flutter/Dart SDK, xem §8).

Debug (systematic-debugging): review vòng 1b phát hiện `synthesize()` nhận `cancelToken` nhưng
không forward (script đếm signatures vs forwarded: 2 vs 1) → fix `fallback_chain.dart:37-43`.
Review vòng 2b phát hiện `LinearProgressIndicator(value: pct)` với `pct: double?` không được
promote qua biến `bool busy` → fix bằng `busyPct` non-null (`chapter_list_screen.dart:67-69,84-91`).

## 4. UI audit (3 màn hình)

Phát hiện + fix (chi tiết file:line ở bảng §0):
- **paste_link:** icon 72px không label → `excludeFromSemantics` (title đã rõ);
  subtitle 6px → 8px (nhịp 4/8dp); SegmentedButton bọc `Semantics(label)`; thêm
  `autofillHints.url` (chế độ link) + `AutovalidateMode.onUserInteraction`; lỗi parse bọc
  `Semantics(liveRegion: true)` để screen-reader đọc ngay.
- **chapter_list:** subtitle swap Text↔Progress gây CLS → giữ chỗ `SizedBox(height: 6)`;
  `Colors.red` hard-code → `colorScheme.error` (dark-mode contrast); mỗi tile bọc
  `Semantics(button, selected, label)` gồm số chương + tiến độ %; title `maxLines: 2 + ellipsis`.
- **player:** icon headphones → `excludeFromSemantics`; title `maxLines: 3 + ellipsis`, spacing 12→16/20;
  slider bọc `SliderTheme` (thumb r10, overlay r24 — hit-area ≥48dp); time dùng
  `FontFeature.tabularFigures` (chống nhảy số); nút play `minimumSize 72x72` + `semanticLabel`
  Phát/Tạm dừng.
- Chưa làm (để pass QA Web): Playwright/DevTools screenshot-verify — VPS không có Flutter SDK
  nên không build Web để chụp.

## 5. Trail of Bits (security)

- **HTTP dev-only:** giữ nguyên 2 base URL http + cảnh báo trong `config.dart:5-6` và README §31-42.
  Production: đổi 1 chỗ sang `https://` (không code nào hard-code scheme/host khác).
- **API không auth:** cả 2 server TTS nội bộ, không có auth header — client không gửi secret nào
  (không có key để lộ). Ghi rõ: nếu server ra internet phải thêm API-key header ở `dio_client.dart`.
- **Cache path traversal:** TRƯỚC — `_fileFor` nối `$key.$extension` trực tiếp; `remove()` nối
  `meta['fileName']` từ Hive (có thể bị sửa tay). SAU — `_keyRegExp ^[a-f0-9]{32}$`,
  `_extRegExp ^[a-z0-9]+$`, validate ở `lookup/store/_fileFor`; `remove()` sanitize basename +
  re-validate key/ext trước khi xóa (`audio_cache.dart:94-117,163-186`).
- **Giới hạn request chống abuse:** `kokoroMaxParallel = 4` (batch, `kokoro_provider.dart:74-87`);
  `splitIntoChunks` giới hạn mỗi chunk ≤400 ký tự (server cap 5000); timeout 120s/30s/15s
  (`config.dart:19-30`); Vieneu từ chối text >12000 (`vieneu_provider.dart:55-60`);
  thêm `CancelToken` để hủy request khi user rời màn hình (chống request treo/dồn).
- **SSRF client-side:** `parseUrl` whitelist scheme http/https (`parse_client.dart:58-67`).

## 6. Karpathy — điều KHÔNG làm (scope v1 giữ nguyên)

1. KHÔNG persist settings ra Hive (giữ `StateProvider` bộ nhớ — đủ v1, README đã ghi v2 mới persist).
2. KHÔNG bulk-offline (giữ `ensureChapterAudio` 1 chương; v2 gọi lặp — đúng KISS, comment trong code).
3. KHÔNG retry/backoff trong Dio (timeout + fallback chain đã đủ; thêm retry = speculative).
4. KHÔNG xóa `cached_network_image/shimmer/flutter_animate` khỏi pubspec dù chưa import
   (v2 dùng cho cover art/skeleton; xóa rồi thêm lại = churn).
5. KHÔNG refactor tên file/cây thư mục (spec khóa cứng).

## 7. codebase-memory — lệnh thật + output

- `list_projects` → 19 projects, **không có** `truyen-audio-app` (workspace mới).
  `search_code pattern="dio|audio-cache|fallback" project="poki-pokiguard_client"` → 0 hit
  (client Unity/C# không có code Dio tái dùng) ⇒ không copy, hand-author mới.
- `index_repository repo_path=/poki/truyen-audio-app` → `status: indexed`, **185 nodes / 515 edges**,
  project `poki-truyen-audio-app`, `parse_partial` 1 file (`config.dart:7` — `library;` directive,
  không ảnh hưởng symbols; đã đọc source trực tiếp).
- Tái dùng cho pass sau: graph đã index — pass QA Web dùng `search_graph`/`trace_path` thay vì grep.

## 8. Verify bắt buộc (lệnh thật + output rút gọn)

| Check (2026-10-27, từ VPS) | Kết quả |
|---|---|
| `GET :8001/voices` | **200**, 2248B, **25 giọng** (có `Trúc Ly`, `Thiện Minh`) — lại sau sửa |
| `GET :8000/voices` | **200**, 578B, **14 giọng** (có `diem_trinh`) — lại sau sửa |
| `POST :8001/parse` text mẫu 2 chương | **200** `{"chapters":[{"title":"Chương 1: Gặp gỡ","len":43},...],"texts":[...]}` |
| `POST :8001/tts` Trúc Ly | **200**, 228524B, magic `52 49 46 46 ... 57 41 56 45` (RIFF/WAVE), `file`: PCM 16-bit mono **48000 Hz** |
| `POST :8000/tts` diem_trinh mp3 | **200**, 18600B, magic `ff f3 84` (MP3 frame sync) |
| Review code 2 lượt | Vòng 1: import (mọi `package:` đều có trong pubspec — script check OK), brace/paren cân (15 file), phát hiện bug `cancelToken` không forward → fix. Vòng 2: API currency (không `withOpacity`/`MaterialState` cũ), `prefer_single_quotes` sạch, `debugPrint` (không `print`), phát hiện `pct` nullable → fix `busyPct`. Chi tiết §3 |
| `flutter test` / `flutter analyze` | **CHƯA CHẠY** — VPS không có Flutter/Dart SDK, role cấm cài toolchain (giống v1). Test viết sạch, chờ máy có SDK: `flutter test` |

## 9. Whitelist path đã tạo/sửa (để Lead commit — KHÔNG commit)

```text
lib/src/core/network/dio_client.dart
lib/src/core/tts/tts_provider.dart
lib/src/core/tts/fallback_chain.dart
lib/src/core/tts/vieneu_provider.dart
lib/src/core/tts/kokoro_provider.dart
lib/src/core/parse/parse_client.dart
lib/src/core/cache/audio_cache.dart
lib/src/core/convert/chapter_audio.dart
lib/src/features/player/audio_handler.dart
lib/src/features/library/paste_link_screen.dart
lib/src/features/chapters/chapter_list_screen.dart
lib/src/features/player/player_screen.dart
test/fallback_chain_test.dart (mới)
test/kokoro_concat_test.dart (mới)
test/parse_and_magic_test.dart (mới)
docs/reports/REPORT_TRUYEN_AUDIO_APP_V2.md (file này)
```

Không commit (đúng giới hạn role: cấm `git add/commit/push`).
