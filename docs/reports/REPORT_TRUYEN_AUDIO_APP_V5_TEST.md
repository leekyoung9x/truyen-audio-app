# REPORT_TRUYEN_AUDIO_APP_V5_TEST — Bộ testcase chuẩn (v5)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: Flutter 3.47.8
Role: `code-full` (CHỈ viết test — không sửa `lib/`, không commit)

## 1. Kết quả nghiệm thu

- `flutter analyze`: **0 issue** (lib + test).
- `flutter test`: **98/98 pass, 0 skip, 0 fail**.
- `widget_test.dart` RÁC (counter mẫu, import sai MyApp): **ĐÃ XÓA**.
- 3 file unit cũ (fallback/chunk/parse): **giữ nguyên** (không trùng, không thiếu case đã có).

## 2. Bảng test (file / case / số lượng / pass)

| File test | Nội dung | Số case | Pass |
|---|---|---|---|
| `app_startup_test.dart` | Khởi động + regression white-screen Web (A) | 4 | 4 |
| `paste_link_screen_test.dart` | Widget nhập link, validation, lỗi mạng (B) | 7 | 7 |
| `chapter_list_screen_test.dart` | Widget list chương, điều hướng player, empty-state (B) | 5 | 5 |
| `player_screen_test.dart` | Widget player: play/pause, tua ±10s, next/prev, tốc độ, hẹn giờ ngủ (B) | 8 | 8 |
| `settings_screen_test.dart` | Widget settings: provider order, voice, tốc độ, back (B) | 7 | 7 |
| `navigation_test.dart` | go_router 4 route + back + route sai (C) | 3 | 3 |
| `fallback_chain_test.dart` (cũ, giữ) | Fallback Vieneu→Kokoro, chunk split | 10 | 10 |
| `kokoro_concat_test.dart` (cũ, giữ) | Concat song song ≤4, speed clamp | 2 | 2 |
| `parse_and_magic_test.dart` (cũ, giữ) | Magic bytes, ParseClient guard | 7 | 7 |
| `tts_edge_cases_test.dart` (mới, D) | Vieneu/Kokoro validate, chunk biên 5000, chain thiếu provider, progress, VoiceInfo, limits | 19 | 19 |
| `audio_cache_test.dart` (mới, D) | AudioCache thật (Hive tạm) + FakeAudioCache + guards | 11 | 11 |
| `parse_and_chapter_audio_test.dart` (mới, D) | Parse timeout/lỗi/trim, ensureChapterAudio hit/miss/fallback/progress, magic biên | 15 | 15 |
| **Tổng** | | **98** | **98** |

Fakes dùng chung (`test/fakes/`): `fake_tts.dart` (FakeTtsProvider, makeStubParseClient, makeSampleParseResult, makeStubProviderDio), `fake_audio_handler.dart` (FakeStoryAudioHandler — snapshot stream + đếm calls), `fake_audio_cache.dart` (FakeAudioCache memory + initTestHive/disposeTestHive/openTestCache cho unit thường), `test_app.dart` (FakeVieneu/KokoroProvider đúng type override, makeTestApp, pumpRealApp, routerGo).

## 3. Coverage ước lượng theo file lib

| File lib | Test cover | Mức ước lượng |
|---|---|---|
| `main.dart` (TruyenAudioApp + `_initAudioHandler` guard kIsWeb) | app_startup (mock, không throw, vào `/`) | Cao (widget); nhánh Web-native của `_initAudioHandler` không chạy trực tiếp trên VM |
| `features/library/paste_link_screen.dart` | 7 widget (happy + rỗng + sai scheme + lỗi mạng + rỗng + text mode + settings) | Cao |
| `features/chapters/chapter_list_screen.dart` | 5 widget (list 3 chương, tap chương, nghe từ đầu, đổi truyện, empty-state deep-link) | Cao |
| `features/player/player_screen.dart` | 8 widget (prepare OK/lỗi, play/pause, tua, skip, tốc độ, sleep timer, TTS fail) | Cao |
| `features/player/audio_handler.dart` | Gián tiếp qua FakeStoryAudioHandler (cùng interface); logic just_audio thật (loadPlaylist/setSpeed/seek) KHÔNG test (cần native) | Trung bình (interface + chuẩn bị) |
| `features/settings/settings_screen.dart` | 7 widget (order 2 chiều, voice list/reset/lỗi, tốc độ, back) | Cao |
| `features/app_providers.dart` | Gián tiếp qua mọi widget test (override + seed) | Cao |
| `core/tts/fallback_chain.dart` | 10 cũ + 4 mới (thiếu provider, map rỗng, progress, message) | Cao |
| `core/tts/kokoro_provider.dart` | 2 cũ + chunk biên 5000/5001 + clamp 0.1→0.5 + audio rỗng | Cao |
| `core/tts/vieneu_provider.dart` | rỗng/>12000/đúng 12000/rỗng/500/timeout | Cao |
| `core/tts/tts_provider.dart` (VoiceInfo) | fromJson thiếu field | Cao |
| `core/parse/parse_client.dart` | 3 cũ + timeout/500/trim/text dài/textOf/phạm vi/JSON sai kiểu | Cao |
| `core/convert/chapter_audio.dart` | cache hit/miss/fallback-voice/progress + magic biên | Cao |
| `core/cache/audio_cache.dart` | store/lookup/miss/remove/clear/meta/key-guard/ext-guard (thật + fake) | Cao |
| `core/config.dart` (limits) | Assert hằng số thiết kế | Cao |
| `core/network/dio_client.dart` | Gián tiếp (mọi stub Dio dùng validateStatus 2xx tương đương) | Trung bình |

## 4. Danh sách Key còn thiếu cần thêm vào source (KHÔNG tự sửa — cần Lead duyệt)

Không có `Key`/`testKey` nào trong `lib/` (grep `Key(` chỉ ra `cacheKey`). Widget test hiện tại tìm bằng text/icon/tooltip — đủ dùng nhưng giòn khi đổi copy. Đề xuất thêm:

- `lib/src/features/library/paste_link_screen.dart`: `TextFormField` → `key: Key('paste_input')`; `FilledButton.icon` tách chương → `key: Key('paste_parse_button')`; `_ErrorCard` → `key: Key('paste_error_card')`.
- `lib/src/features/chapters/chapter_list_screen.dart`: `ListTile` mỗi chương → `key: Key('chapter_item_$index')`; nút "Nghe từ đầu" → `key: Key('chapters_play_all')`.
- `lib/src/features/player/player_screen.dart`: nút play/pause → `key: Key('player_play_pause')`; slider seek → `key: Key('player_seek')`; slider tốc độ → `key: Key('player_speed')`; ChoiceChip hẹn giờ → `key: Key('sleep_$minutes')`.
- `lib/src/features/settings/settings_screen.dart`: SegmentedButton order → `key: Key('settings_provider_order')`; Slider tốc độ → `key: Key('settings_speed')`.

## 5. Test skip + phát hiện môi trường (ghi rõ lý do)

- **Skip: 0.**
- Phát hiện 1 (đã xử lý, không skip): async disk IO (`Directory.createTemp`, `Hive.openBox`) **treo trong testWidgets zone** (Flutter 3.47) — widget test dùng `FakeAudioCache` in-memory; Hive thật chỉ dùng trong `test` thường (`audio_cache_test.dart`). Chi tiết trong `test/fakes/fake_audio_cache.dart`.
- Regression Web (white-screen 2026-10-27): cover bằng mock — app pump với `FakeStoryAudioHandler` (không gọi `AudioService.init` thật) + assert lên hình + `kIsWeb == false` trên VM. Test Web thật (`flutter test -d chrome`) chưa chạy — hẹn Pass sau khi Lead duyệt.

## 6. Câu cuối

Whitelist path test đã tạo: `test/fakes/fake_tts.dart`, `test/fakes/fake_audio_handler.dart`, `test/fakes/fake_audio_cache.dart`, `test/fakes/test_app.dart`, `test/app_startup_test.dart`, `test/paste_link_screen_test.dart`, `test/chapter_list_screen_test.dart`, `test/player_screen_test.dart`, `test/settings_screen_test.dart`, `test/navigation_test.dart`, `test/tts_edge_cases_test.dart`, `test/audio_cache_test.dart`, `test/parse_and_chapter_audio_test.dart` (đã xóa `test/widget_test.dart` rác). Không commit.
