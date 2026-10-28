# REPORT_TRUYEN_AUDIO_APP_V8 — Kokoro lên primary (v8)

Ngày: 2026-10-27 | Workspace: `/poki/truyen-audio-app` | SDK: `/opt/flutter/bin/flutter`
Pass: v8 | Role: `code-full` (CẤM git add/commit/push — không commit)

## 1. Yêu cầu (user 2026-10-27)

Đổi thứ tự TTS: **Kokoro 8000 lên đầu (primary), Vieneu 8001 xuống fallback**.
Lý do: user muốn giọng Kokoro default.

## 2. Thay đổi

### `server/proxy_server.py` (v7 → v8)

- `POST /tts` auto (mặc định + mọi hint lạ): **Kokoro trước, lỗi/timeout mới sang
  Vieneu** (trước đây ngược lại). Không chunk ở proxy — chunking vẫn ở client.
- Tách 2 hàm Kokoro rõ nghĩa:
  - `_call_kokoro_soft()` (auto): lỗi/timeout/status-lạ → `None` để fallback
    sang Vieneu (fix bug cũ: `_call_kokoro` cũ trả `JSONResponse` lỗi — object
    truthy nên `or` KHÔNG BAO GIỜ fallback được, auto thực chất là
    Kokoro-only cứng).
  - `_call_kokoro_strict()` (hint `kokoro`): lỗi → báo lỗi rõ, không fallback
    (giữ semantics client ép giọng).
- Timeout riêng: `TIMEOUT_TTS_KOKORO = 30.0` (chunk Kokoro ≤5000 ký tự, khớp
  `ApiTimeouts.kokoroChunk`), `TIMEOUT_TTS_VIENEU = 120.0` (giữ nguyên cho
  chương dài 12000 ký tự). Bỏ `TIMEOUT_TTS` chung.
- `provider` hint giữ nguyên: `vieneu` → chỉ 8001, `kokoro` → chỉ 8000,
  thiếu/khác → auto Kokoro-first.
- Docstring route + `FastAPI(version="8")` cập nhật.

### App Flutter (default Kokoro, Web không hardcode IP — giữ nguyên)

- `lib/src/features/app_providers.dart`:
  - `providerOrderSettingProvider` default `'vieneu_first'` → `'kokoro_first'`.
  - `providerOrderFrom`: `'vieneu_first'` → `vieneuFirst`, **mọi giá trị khác
    (kể cả chuỗi lạ/cũ) → `kokoroFirst`** (trước đây lạ → Vieneu). Nhất quán
    primary mới.
- `lib/src/core/config.dart`: comment `kokoroBaseUrl` CHÍNH (v8),
  `vieneuBaseUrl` DU PHÒNG; `DefaultVoice.kokoro` comment "giọng chính".
  Web vẫn `kIsWeb ? '/api'` — không hardcode IP.
- `kokoro_provider.dart` / `vieneu_provider.dart`: chỉ đổi comment
  CHÍNH/DU PHÒNG (logic `provider` hint + timeout chunk 30s / 120s giữ nguyên).
- `FallbackChain`, `chapter_audio.dart`, `player_screen.dart`: không cần sửa —
  đã generic theo `ProviderOrder` (user vẫn chọn Vieneu-trước trong Settings).
- Test cập nhật theo default mới: `settings_screen_test.dart` (default
  `kokoro_first`, đổi 2 chiều), `tts_edge_cases_test.dart` (lạ → Kokoro).
  Test `fallback_chain` / `parse_and_chapter_audio` dùng `ProviderOrder`
  explicit cho cả 2 hướng — giữ nguyên, vẫn pass.

## 3. Nghiệm thu

### curl proxy (127.0.0.1:8896, sau `systemctl restart truyen-proxy` → active)

- `POST /api/tts {"text":"Xin chào","voice":"diem_trinh"}` (auto) →
  **200 `audio/mpeg` 6792 bytes, MP3** (Kokoro first).
- `POST /api/tts {"text":"Xin chào","voice":"Trúc Ly","provider":"vieneu"}` →
  **200 `audio/wav` 97964 bytes, RIFF/WAVE 48kHz** (Vieneu fallback vẫn chạy).

### `flutter analyze` — `No issues found!`

### `flutter test` — 98/98 pass (`All tests passed!`)

### `flutter build web --release` — OK (Caddy serve thẳng `build/web`, không đổi config)

### Live `https://comic.cutes1tg.online` — curl

- `GET /` → 200; `GET /api/voices/kokoro` → 200 (14 giọng, `diem_trinh` đầu);
  `GET /api/voices/vieneu` → 200 (25 giọng).
- `POST /api/tts` auto → 200 `audio/mpeg` 6792 bytes.

### Browser-verify (Chrome thật + playwright-core, script `/tmp/v8_inpage.js`)

In-page fetch trong chính page HTTPS (đúng code path XHR của Dio):

- Title `"Truyện Audio"`, screenshot `/tmp/v8_live_home.png`.
- `POST /api/tts` auto → 200 `audio/mpeg` 6816 bytes, magic `fff3…` (MP3 Kokoro).
- `POST /api/tts {provider:vieneu}` → 200 `audio/wav` 97964 bytes,
  magic `52494646` (RIFF Vieneu).
- `requestfailed: none`, `pageerror: none`, **console error: none**.

## 4. Vận hành

```bash
systemctl status truyen-proxy          # Restart=always, active
curl -s http://127.0.0.1:8896/health   # {"ok":true,...}
```

Restart lần này sạch (không kẹt `deactivating` như v7).

## 5. Whitelist path (câu cuối)

- `server/proxy_server.py` (v8: auto Kokoro-first + soft/strict split + timeout
  riêng 30s/120s)
- `lib/src/features/app_providers.dart` (default `kokoro_first`,
  `providerOrderFrom` lạ → Kokoro)
- `lib/src/core/config.dart` (comment CHÍNH/DU PHÒNG)
- `lib/src/core/tts/kokoro_provider.dart`, `lib/src/core/tts/vieneu_provider.dart`
  (comment role)
- `test/settings_screen_test.dart`, `test/tts_edge_cases_test.dart`
  (expectation default mới)
- `docs/reports/REPORT_TRUYEN_AUDIO_APP_V8.md` (report này)
- Không commit (tuân thủ brief: CẤM git add/commit/push).
