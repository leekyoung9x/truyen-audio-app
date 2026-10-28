// Widget test man hinh phat (/player) — handler FAKE, KHONG goi audio that.
import 'dart:async' show TimeoutException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';
import 'package:truyen_audio_app/src/features/player/player_screen.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

/// Di qua flow that toi /player: nhap link -> parse mock -> chapters ->
/// bam chuong dau -> player (prepare chay voi cache fake + TTS fake).
Future<TestApp> _toiPlayer(WidgetTester tester) async {
  final app = makeTestApp(cacheOverride: FakeAudioCache());
  await pumpRealApp(tester, app);
  addTearDown(app.handler.dispose);

  await tester.enterText(
    find.byType(TextFormField),
    'https://truyen.example.com/truyen-hay',
  );
  await tester.tap(find.text('Tách chương'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Chương 1: Khởi đầu'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  group('player_hien_dieu_khien_phat', () {
    testWidgets(
      'player_tai_xong_hien_tieu_de_chuong_va_nut_phat_tam_dung',
      (tester) async {
        final app = await _toiPlayer(tester);

        expect(tester.takeException(), isNull);
        // Tieu de chuong + nut phat/tam dung (fake handler tu play -> playing).
        expect(find.text('Chương 1: Khởi đầu'), findsWidgets);
        expect(find.byIcon(Icons.pause), findsOneWidget);
        // v12: chuong hien tai vao playlist NGAY; 2 chuong ke prefetch NEN
        // (unawaited + cheap-append) — cho them nhip de prefetch that
        // (fake TTS ~sync) chen xong.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(app.handler.loadedItems.length, 3);
      },
    );

    testWidgets(
      'player_thieu_du_lieu_redirect_ve_trang_chu_khong_trang',
      (tester) async {
        // v10: vao thang /player khi chua parse -> redirect ve '/' kem
        // snackbar, khong trang trang, khong man hinh loi day.
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/player');

        expect(tester.takeException(), isNull);
        // Ve trang chu (paste-link) + snackbar huong dan.
        expect(
          find.text('Chưa có truyện nào. Hãy dán link truyện trước.'),
          findsOneWidget,
        );
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
        // Khong con man hinh loi cu.
        expect(find.text('Thử lại'), findsNothing);
      },
    );

    testWidgets(
      'player_thieu_cache_hien_loi_va_nut_thu_lai',
      (tester) async {
        // Co parseResult nhung cache null -> loi + nut Thu lai (khong redirect).
        // Parse khong can cache (chi _prepare can) nen di flow that toi player.
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chương 1: Khởi đầu'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Thiếu cache audio. Hãy khởi động lại app.'),
          findsOneWidget,
        );
        expect(find.text('Thử lại'), findsOneWidget);
      },
    );
  });

  group('player_bam_play_pause_doi_trang_thai', () {
    testWidgets(
      'player_bam_nut_phat_tam_dung_doi_icon_va_trang_thai_handler',
      (tester) async {
        final app = await _toiPlayer(tester);
        expect(app.handler.playCalls, 1); // tu dong phat sau prepare

        // Dang phat -> bam tam dung.
        await tester.tap(find.byIcon(Icons.pause));
        await tester.pump();
        expect(app.handler.pauseCalls, 1);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        // Tam dung -> bam phat lai.
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        expect(app.handler.playCalls, 2);
        expect(find.byIcon(Icons.pause), findsOneWidget);
      },
    );
  });

  group('player_tua_tien_lui_10s', () {
    testWidgets(
      'player_bam_tua_tien_goi_forward_va_tua_lui_goi_rewind',
      (tester) async {
        final app = await _toiPlayer(tester);

        await tester.tap(find.byIcon(Icons.forward_10));
        await tester.pump();
        expect(app.handler.forwardCalls, 1);

        await tester.tap(find.byIcon(Icons.replay_10));
        await tester.pump();
        expect(app.handler.rewindCalls, 1);
      },
    );

    testWidgets(
      'player_bam_chuong_truoc_sau_goi_skip_tuong_ung',
      (tester) async {
        final app = await _toiPlayer(tester);

        await tester.tap(find.byIcon(Icons.skip_next));
        await tester.pump();
        expect(app.handler.skipNextCalls, 1);

        await tester.tap(find.byIcon(Icons.skip_previous));
        await tester.pump();
        expect(app.handler.skipPreviousCalls, 1);
      },
    );
  });

  group('player_doi_toc_do_va_hen_gio_ngu', () {
    testWidgets(
      'player_keo_slider_toc_do_cap_nhat_provider_va_handler',
      (tester) async {
        final app = await _toiPlayer(tester);

        // Co 2 slider: seek bar + toc do. Slider toc do nam gan chu 'Tốc độ'.
        final tocDoRow = find.ancestor(
          of: find.text('Tốc độ'),
          matching: find.byType(Row),
        );
        final tocDoSlider = find.descendant(
          of: tocDoRow,
          matching: find.byType(Slider),
        );
        expect(tocDoSlider, findsOneWidget);

        // Keo ve gia tri khac 1.0: tap vao vi tri 75% slider.
        final center = tester.getCenter(tocDoSlider);
        final size = tester.getSize(tocDoSlider);
        await tester.tapAt(center + Offset(size.width * 0.25, 0));
        await tester.pump();

        expect(app.handler.setSpeedCalls, greaterThanOrEqualTo(1));
        expect(app.container.read(speedSettingProvider), isNot(1.0));
      },
    );

    testWidgets(
      'player_chon_hen_gio_ngu_cap_nhat_provider_va_handler',
      (tester) async {
        final app = await _toiPlayer(tester);

        // Chon hen gio 15 phut.
        await tester.tap(find.text('15p'));
        await tester.pump();

        expect(app.container.read(sleepTimerMinutesProvider), 15);
        expect(app.handler.lastSleepTimerMinutes, 15);

        // Tat hen gio.
        await tester.tap(find.text('Tắt'));
        await tester.pump();
        expect(app.container.read(sleepTimerMinutesProvider), isNull);
        expect(app.handler.lastSleepTimerMinutes, -1);
      },
    );
  });

  group('player_that_bai_tai_audio_hien_loi', () {
    testWidgets(
      'player_tts_that_bai_het_hien_loi_khong_crash',
      (tester) async {
        final boom = Exception('server sap het');
        final app = makeTestApp(
          cacheOverride: FakeAudioCache(),
          vieneu: FakeVieneuProvider(failWith: boom),
          kokoro: FakeKokoroProvider(failWith: boom),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chương 1: Khởi đầu'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Hien loi (khong crash, khong trang).
        expect(find.byIcon(Icons.error_outline), findsWidgets);
      },
    );
  });

  // v10: fix ket loading 100% khong hien controls khi play() treo tren Web.
  group('player_v10_khong_ket_loading_khi_play_treo', () {
    testWidgets(
      'player_play_treo_van_hien_controls_va_bam_phat_lai_duoc',
      (tester) async {
        // Rut timeout buoc xuong 2s de test chay nhanh (default 30s).
        final oldTimeout = PlayerScreenState.stepTimeoutForTest;
        PlayerScreenState.stepTimeoutForTest = const Duration(seconds: 2);
        addTearDown(
          () => PlayerScreenState.stepTimeoutForTest = oldTimeout,
        );
        // Handler mo phong bug Web: loadPlaylist xong, play() treo.
        final hanging = HangingPlayAudioHandler();
        final app = makeTestApp(
          handler: hanging,
          cacheOverride: FakeAudioCache(),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chương 1: Khởi đầu'));
        // Khong pumpAndSettle (play treo) — pump thu cong de cho frame chay.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        // KHONG ket man hinh "Dang tao audio...": controls da hien ngay
        // sau khi chuong dau tai xong (play con treo o background).
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.text('Chương 1: Khởi đầu'), findsWidgets);
        expect(find.textContaining('Đang tạo audio'), findsNothing);

        // Bam phat lai duoc (khong crash, goi play them 1 lan).
        hanging.unhang();
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        expect(hanging.playCalls, greaterThanOrEqualTo(2));

        // Don sach: mo gate de _prepare cu (neu con treo) khong keo dai test.
        hanging.unhang();
      },
    );

    testWidgets(
      'player_vao_thang_khong_state_redirect_ve_trang_chu',
      (tester) async {
        // Brief v10: vao truc tiep #/player khong state -> redirect ve /,
        // khong trang xoa (da co case redirect+snackbar o group tren; case
        // nay assert khong co man hinh loading/error day keo dai).
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/player');

        expect(tester.takeException(), isNull);
        // Trang chu hien lai; khong ket o loading "Dang chuan bi audio...".
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
        expect(find.text('Đang chuẩn bị audio...'), findsNothing);
      },
    );
  });

  // v12: prefetch nen KHONG duoc pha UI chuong hien tai (bug user 2026-10-28:
  // chuong 2 timeout 30s -> banner do de len player chuong 1 dang phat).
  group('player_v12_prefetch_khong_pha_ui', () {
    testWidgets(
      'player_prefetch_timeout_chi_notice_nhe_khong_loi_do',
      (tester) async {
        // Chuong 2 (text chua 'hai') TTS treo vinh vien; chuong 1+3 OK.
        final hangingKokoro = _HangingChapterKokoro(
          hangingSubstring: 'hai',
        );
        final app = makeTestApp(
          cacheOverride: FakeAudioCache(),
          kokoro: hangingKokoro,
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chương 1: Khởi đầu'));
        await tester.pumpAndSettle();
        // Cho prefetch nen xong: chuong 2 timeout -> retry 1 lan (backoff
        // 2s) roi bo qua; chuong 3 OK. Pump so bo thoi gian ao cua test.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 3));

        expect(tester.takeException(), isNull);
        // Chuong 1 van phat binh thuong (controls + pause, khong loi do).
        expect(find.text('Chương 1: Khởi đầu'), findsWidgets);
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        // Notice nhe ve chuong 2 (info, khong chan controls).
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        expect(
          find.textContaining('Chương 2 tải nền thất bại'),
          findsOneWidget,
        );
        // Playlist chi co chuong tai duoc (1 + 3, bo qua 2).
        expect(
          app.handler.loadedItems.map((e) => e.id),
          ['chapter-0', 'chapter-2'],
        );
        // Progress chuong 2 = -1 (loi), chuong 1/3 = 1.0.
        final progress = app.container.read(synthProgressProvider);
        expect(progress[0], 1.0);
        expect(progress[1], -1.0);
        expect(progress[2], 1.0);
      },
    );

    testWidgets(
      'player_prefetch_fail_van_play_chuong_hien_tai',
      (tester) async {
        // Chuong 2+3 (text chua 'hai'/'ba') TTS hong han; chuong 1 OK.
        final selective = _SelectiveFailKokoro(
          failSubstrings: const ['hai', 'ba'],
        );
        final app = makeTestApp(
          cacheOverride: FakeAudioCache(),
          kokoro: selective,
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chương 1: Khởi đầu'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        // Van phat chuong 1 (pause = dang phat), khong man hinh loi day.
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        // Chi chuong 1 trong playlist; chuong hong bi bo qua.
        expect(app.handler.loadedItems.map((e) => e.id), ['chapter-0']);
        // Progress: chuong 1 xong, chuong 2+3 loi (-1).
        final progress = app.container.read(synthProgressProvider);
        expect(progress[0], 1.0);
        expect(progress[1], -1.0);
        expect(progress[2], -1.0);
      },
    );
  });
}

/// Kokoro fake nem [TimeoutException] khi text chua [hangingSubstring]
/// (mo phong chuong 2 timeout tren Web); text khac tra MP3 'ID3' nhu fake
/// mac dinh.
///
/// Dung cho test v12: prefetch chuong 2 timeout (qua retry + backoff cua
/// [prefetchChapterAudio]) nhung chuong hien tai van play.
class _HangingChapterKokoro extends FakeKokoroProvider {
  _HangingChapterKokoro({required this.hangingSubstring})
    : super(voices: defaultKokoroVoices());

  final String hangingSubstring;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (text.contains(hangingSubstring)) {
      // Nem TimeoutException TRUC TIEP (khong treo gio that): mo phong
      // Dio/Web timeout ma test khong can doi; prefetchChapterAudio se
      // retry 1 lan sau backoff roi moi bo qua.
      throw TimeoutException(
        'Kẹt ở tạo audio quá 45 giây (mô phỏng prefetch timeout v12).',
      );
    }
    return super.synthesize(
      text: text,
      voice: voice,
      speed: speed,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

/// Kokoro fake hong han khi text chua 1 trong [failSubstrings] (mo phong
/// chuong ke loi mang/TTS); text khac tra MP3 'ID3' nhu fake mac dinh.
class _SelectiveFailKokoro extends FakeKokoroProvider {
  _SelectiveFailKokoro({required this.failSubstrings})
    : super(voices: defaultKokoroVoices());

  final List<String> failSubstrings;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (failSubstrings.any(text.contains)) {
      throw Exception('TTS hong (mo phong chuong loi v12).');
    }
    return super.synthesize(
      text: text,
      voice: voice,
      speed: speed,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}
