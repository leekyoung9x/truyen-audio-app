# REPORT_TRUYEN_AUDIO_APP_V4 — Fix white-screen Web (guard audio_service/path_provider)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter` 3.47.8

## 1. Root cause (đã xác nhận bằng browser thật)

Web build load xong trắng xóa: `hasGlassPane: true`, `canvas: 0`,
console `Uncaught Error ... (main.dart.js:...)` ngay sau
`Got object store box in database audio_meta` (Hive IndexedDB mở OK rồi mới crash).

Nguyên nhân: `main()` gọi 2 API native-only **trước `runApp`**:

- `StoryAudioHandler.configureSession()` → `AudioSession.instance`
  (audio_session chứa `dart:io`, trên Web là stub → throw).
- `AudioService.init(...)` → audio_service Web không hỗ trợ background
  handler đầy đủ → throw lúc init → `runApp` không bao giờ chạy → trắng màn hình.

Nghi phạm 2 (đúng): `AudioCache.init()` gọi `getApplicationDocumentsDirectory()`
(path_provider trả path ảo trên Web) + mọi `File(...)` trong cache là stub —
phải tách mode Web (bytes vào Hive/IndexedDB).

## 2. Đã sửa (file:line, tương đối theo file mới)

### `lib/main.dart` — tách init theo nền (viết lại hàm main + `_initAudioHandler`)
- Web (`kIsWeb`): **bỏ qua** `AudioService.init` + `configureSession`,
  dùng `StoryAudioHandler()` trực tiếp (just_audio thuần, không qua audio_service).
- Native: giữ nguyên `configureSession()` + `AudioService.init(...)`.

### `lib/src/core/cache/audio_cache.dart`
- `AudioCache._` giờ giữ `Directory? _dir` + `Box? _blobBox` (mode Web).
- `init()`: Web mở thêm Hive box `'audio_blob'` (IndexedDB), **không gọi**
  path_provider/Directory. Native giữ nguyên.
- Mới `CachedAudio` (bytes + meta + `filePath?` + `extension`), `lookupAudio()`,
  `storeAudio()`, `getByKey()`, `isWebBlob`. `lookup()`/`store()` cũ giữ lại
  (native-only, Web throw `StateError` rõ nghĩa).
- `remove()`/`clear()`: null-safe `_dir`, xóa cả blob box.

### `lib/src/features/player/audio_handler.dart`
- `ChapterMediaItem`: `filePath` → nullable + thêm `audioBytes?` + `mimeType?`.
- `loadPlaylist()`: Web validate `audioBytes`, phát qua
  `AudioSource.uri(Uri.dataFromBytes(...))`; native validate file tồn tại
  như cũ + `AudioSource.file`.
- `configureSession()`: `if (kIsWeb) return;`.
- Import `dart:io` thu hẹp `show File` (Web compile: file này vẫn được
  import nhưng mọi call-site File đều nằm sau nhánh `!kIsWeb`).

### `lib/src/core/convert/chapter_audio.dart`
- Bỏ `dart:io`, `ensureChapterAudio` trả `CachedAudio` (dùng
  `lookupAudio`/`storeAudio` — chạy cả 2 nền). Sửa luôn call `store` cũ
  truyền nhầm `speed:` (primary) → `usedSpeed` (provider thắng).

### `lib/src/features/player/player_screen.dart:97-105`
- Dựng `ChapterMediaItem` mới: native truyền `filePath`, Web truyền
  `audioBytes` + `mimeType: audio/<ext>`.

### `test/widget_test.dart` (viết lại — file cũ stale, reference `MyApp` không tồn tại)
- Smoke test: pump `TruyenAudioApp` thật + `StoryAudioHandler()` trực tiếp
  (không qua AudioService — đúng regression white-screen), assert vào route `/`.
- Unit `AudioCache.cacheKey` md5 hex 32 ký tự.

## 3. Bằng chứng browser (chuẩn mới: screenshot + console, không chỉ curl)

- Serve: `build/web` → `http://127.0.0.1:8897/` (curl 200 — chỉ là điều kiện cần).
- Verify script: `/tmp/v4tools/verify_web.js` (playwright-core + system Chrome 156).
- Kết quả lần cuối:
  - Screenshot `/tmp/v4tools/v4_web.png`: **thấy UI đầy đủ**
    (AppBar "Truyện Audio", icon sách, "Dán link truyện để nghe",
    SegmentedButton Link/Dán text, ô URL, nút "Tách chương") —
    pixel check: **99.98% non-white** (không trắng).
  - Console: **không `pageerror`, không `Uncaught Error`**, chỉ còn:
    `Injecting <script> tag`, `Got object store box ... audio_meta`,
    `... audio_blob`, 1 warning GPU ReadPixels (headless, vô hại).
  - Tương tác (`/tmp/v4tools/v4_web_interact.png`): click "Tách chương" khi
    trống → hiện validate "Vui lòng nhập URL truyện" → app sống, form hoạt động.
- Lưu ý kỹ thuật: `canvas: 0` qua `querySelector('canvas')` là **bình thường**
  (Flutter Web đặt canvas trong shadow DOM của `flt-glass-pane`) — screenshot
  + pixel check mới là bằng chứng đúng.

## 4. Log analyze/test/build

- `flutter analyze`: **No issues found!** (0 error/warning/info).
- `flutter test`: **All tests passed!** — 21/21
  (fallback_chain 6 + kokoro_concat 4 + parse_and_magic 9 + widget 2).
- `flutter build web --release`: **✓ Built build/web** (~31s, exit 0).

## 5. Ghi chú quy trình

- GitNexus `detect_changes`: repo chưa có commit nào (mọi file untracked) nên
  tool không resolve được base → thay bằng check thủ công: chỉ sửa 5 file
  `lib/` trên + viết lại `test/widget_test.dart`; không đụng file khác.
- Impact: `StoryAudioHandler` 1 caller (`main`), `AudioCache` 2 callers —
  blast radius thấp. `loadPlaylist` graph báo 0 caller (thiếu coverage) nhưng
  đã đọc source trực tiếp: caller duy nhất `player_screen.dart:110` đã update.
- Không `git add/commit/push` theo brief.

Whitelist path: `lib/main.dart`, `lib/src/core/cache/audio_cache.dart`,
`lib/src/core/convert/chapter_audio.dart`,
`lib/src/features/player/audio_handler.dart`,
`lib/src/features/player/player_screen.dart`,
`test/widget_test.dart`, `docs/reports/REPORT_TRUYEN_AUDIO_APP_V4.md`.
Không commit.
