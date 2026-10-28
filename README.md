# Truyện Audio App v1

App nghe truyện-audio đa nền tảng (Android / iOS / Windows / Web) — 1 codebase Flutter.

Luồng dùng: **paste link truyện → parse danh sách chương → chọn chương → TTS thành audio → phát (kể cả chạy nền)**.

## Yêu cầu SDK

- Flutter **3.35+** / Dart **3.8+**
- Kiểm tra: `flutter --version`

> VPS hiện tại **chưa có Flutter/Dart SDK** nên `flutter analyze/build` chưa chạy được ở đây
> (xem mục "CHƯA VERIFY" trong `docs/reports/REPORT_TRUYEN_AUDIO_APP_V1.md`).
> Chạy các lệnh dưới trên máy dev đã cài Flutter.

## Chạy lệnh cơ bản

```bash
flutter pub get
dart fix --apply
flutter analyze
flutter run
```

Build Android APK:

```bash
flutter build apk --release
```

## Backend TTS (đã verify sống ngày 2026-10-27)

| Server | Địa chỉ | Ghi chú |
|---|---|---|
| PRIMARY Vieneu | `http://144.202.5.197:8001` | 25 giọng; default `Trúc Ly`, nam kể chuyện `Thiện Minh`; `POST /tts` text ≤ 12000 ký tự → WAV 48kHz |
| FALLBACK Kokoro | `http://144.202.5.197:8000` | 14 giọng; fallback `diem_trinh`; `POST /tts` text 1–5000 ký tự, speed 0.5–1.5, format `mp3`; app tự cắt chunk ~400 ký tự, gọi song song ≤ 4 request rồi nối bytes |

Mọi base URL + timeout nằm trong **đúng 1 file**: `lib/src/core/config.dart`.
Timeout gợi ý: Vieneu `/tts` 120s (chương dài), `/parse` 30s, `/voices` 15s; Kokoro 30s/chunk.

> ⚠️ **HTTP hiện tại là dev-only.** Production phải dùng `https://` + domain có chứng chỉ
> hợp lệ — chỉ cần sửa `lib/src/core/config.dart` (1 chỗ).

## Cấu hình audio_service phát nền

`audio_service` cần khai báo thêm ở native (file này **chưa có** trong repo vì project
được hand-author, chưa qua `flutter create` — tạo project host rồi copy `lib/` sang,
hoặc thêm tay các file sau):

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<application ...>
  <service android:name="com.ryanheise.audioservice.AudioService"
      android:foregroundServiceType="mediaPlayback"
      android:exported="true">
    <intent-filter>
      <action android:name="android.media.browse.MediaBrowserService"/>
    </intent-filter>
  </service>
  <receiver android:name="com.ryanheise.audioservice.AudioServiceBroadcastReceiver"
      android:exported="true">
    <intent-filter>
      <action android:name="android.media.session.MediaButton"/>
    </intent-filter>
  </receiver>
</application>
```

**iOS** (`ios/Runner/Info.plist`):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## Kiến trúc source

```text
lib/main.dart                        bootstrap (Hive, AudioService, ProviderScope, MaterialApp.router + dark mode)
lib/src/core/config.dart             baseUrls + timeouts + voice/speed mặc định (1 file duy nhất)
lib/src/core/network/dio_client.dart 1 Dio / 1 host + CancelToken
lib/src/core/tts/tts_provider.dart   abstract listVoices/synthesize + VoiceInfo
lib/src/core/tts/vieneu_provider.dart   provider chính (WAV 48kHz)
lib/src/core/tts/kokoro_provider.dart   provider phụ (tự cắt chunk ~400 ký tự, song song ≤4, nối bytes)
lib/src/core/tts/fallback_chain.dart    Vieneu → Kokoro (hoặc ngược lại, theo Settings)
lib/src/core/parse/parse_client.dart    POST /parse với {url} hoặc {text}
lib/src/core/cache/audio_cache.dart     tên file = md5(text+voice+speed), Hive lưu metadata
lib/src/core/convert/chapter_audio.dart ensureChapterAudio() — core dùng lại được cho v2 offline
lib/src/features/app_providers.dart    Riverpod providers (settings, parse state, synth progress, player state)
lib/src/features/library/paste_link_screen.dart
lib/src/features/chapters/chapter_list_screen.dart
lib/src/features/player/player_screen.dart + audio_handler.dart (playlist, nền, 0.5–1.5x, ±10s, hẹn giờ ngủ)
lib/src/features/settings/settings_screen.dart (thứ tự provider, voice theo provider từ API thật, speed)
```

## Quy ước commit

- Không commit trong session hand-author này (role `code-full`, không có quyền git write).
- Lead review rồi commit theo whitelist trong report.
- Suffix message: `Co-Authored-By: Claude Code <noreply@anthropic.com>`
