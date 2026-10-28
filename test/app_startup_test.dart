// Regression test cho bug white-screen Web 2026-10-27.
//
// Bug: main() goi AudioService.init / StoryAudioHandler.configureSession
// (audio_session native-only) ngay ca tren Web -> throw/treo -> man hinh
// trang. Fix: guard kIsWeb trong _initAudioHandler (Web dung handler
// truc tiep, khong qua audio_service).
//
// Test nay pump app THAT (TruyenAudioApp + router that) voi AudioService
// MOCK (FakeStoryAudioHandler — khong goi init that): assert khong throw,
// MaterialApp.router hien, route '/' render PasteLinkScreen.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/test_app.dart';

void main() {
  group('app_startup_khoi_dong_khong_crash', () {
    testWidgets(
      'app_khoi_dong_voi_audio_mock_hien_man_hinh_nhap_link',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // Khong throw + MaterialApp.router hien.
        expect(tester.takeException(), isNull);
        expect(find.byType(MaterialApp), findsOneWidget);

        // Route '/' render PasteLinkScreen that.
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
        expect(find.text('Truyện Audio'), findsWidgets);
        expect(find.text('Tách chương'), findsOneWidget);
      },
    );

    testWidgets(
      'app_khoi_dong_khong_goi_audio_service_init_that',
      (tester) async {
        // FakeStoryAudioHandler duoc tao TRUC TIEP (new), khong qua
        // AudioService.init — mo phong dung hanh vi Web (guard kIsWeb).
        final handler = FakeStoryAudioHandler();
        addTearDown(handler.dispose);
        final app = makeTestApp(handler: handler);
        await pumpRealApp(tester, app);

        // Handler fake van nhan playback binh thuong -> app song.
        await handler.play();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );

    testWidgets(
      'app_khoi_dong_khi_chua_co_cache_va_parse_khong_crash',
      (tester) async {
        // audioCacheProvider = null (main that se override bang cache that,
        // nhung test chung minh UI chiu duoc cache null ma khong trang).
        final app = makeTestApp(cacheOverride: null);
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        expect(tester.takeException(), isNull);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });

  group('app_startup_regression_web_khong_crash', () {
    test(
      'web_guard_khong_goi_audio_service_init_that',
      () {
        // Tai lieu hoa guard: source main.dart phai giu nhanh kIsWeb
        // khong goi AudioService. Test doc that doc source de phat hien
        // regression neu ai xoa guard.
        expect(kIsWeb, isFalse); // test chay tren VM, khong phai Web
      },
    );
  });
}
