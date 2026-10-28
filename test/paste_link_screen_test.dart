// Widget test man hinh nhap link (/) — KHONG goi API that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';

import 'fakes/test_app.dart';

/// Helper: nhap text vao o input link/text.
Future<void> _nhapInput(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextFormField), text);
  await tester.pump();
}

void main() {
  group('paste_link_nhap_url_hop_le_dieu_huong_sang_chapters', () {
    testWidgets(
      'paste_link_nhap_url_hop_le_parse_3_chuong_va_sang_man_hinh_chapters',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _nhapInput(tester, 'https://truyen.example.com/truyen-hay');
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        // Dieu huong sang /chapters voi 3 chuong mock.
        expect(find.text('3 chương'), findsOneWidget);
        expect(find.text('Chương 1: Khởi đầu'), findsOneWidget);
        expect(app.container.read(parseResultProvider)?.chapters.length, 3);
      },
    );
  });

  group('paste_link_url_rong_hien_loi_khong_crash', () {
    testWidgets(
      'paste_link_bo_trong_url_bam_tach_hien_loi_khong_chuyen_trang',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.tap(find.text('Tách chương'));
        await tester.pump();

        // Hien loi validation, van o man hinh nhap link, khong crash.
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Vui lòng nhập'), findsOneWidget);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );

    testWidgets(
      'paste_link_nhap_url_thieu_scheme_hien_loi_url_khong_hop_le',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _nhapInput(tester, 'truyen.example.com/khong-co-scheme');
        await tester.tap(find.text('Tách chương'));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('thiếu http/https'), findsOneWidget);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });

  group('paste_link_loi_mang_hien_loi_khong_crash', () {
    testWidgets(
      'paste_link_server_loi_hien_thong_bao_loi_khong_chuyen_trang',
      (tester) async {
        final app = makeTestApp(
          parseClient: makeStubParseClient(
            error: Exception('server sap'),
          ),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _nhapInput(tester, 'https://truyen.example.com/truyen-hay');
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Van o man hinh cu, khong sang chapters.
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
        // Co hien loi (snackbar/error card).
        expect(app.container.read(parseErrorProvider), isNotNull);
      },
    );

    testWidgets(
      'paste_link_parse_ve_rong_hien_loi_khong_tim_thay_chuong',
      (tester) async {
        final app = makeTestApp(
          parseClient: makeStubParseClient(chapters: const [], texts: const []),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _nhapInput(tester, 'https://truyen.example.com/truyen-rong');
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
        expect(app.container.read(parseErrorProvider), isNotNull);
      },
    );
  });

  group('paste_link_che_do_dan_text', () {
    testWidgets(
      'paste_link_chuyen_sang_che_do_dan_text_parse_duoc_chuong',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // Chuyen sang che do dan text.
        await tester.tap(find.text('Dán text'));
        await tester.pump();
        await _nhapInput(
          tester,
          'Chương 1: Mở đầu\nNội dung...\n\nChương 2: Tiếp\nNội dung...',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('3 chương'), findsOneWidget);
      },
    );
  });

  group('paste_link_nut_cai_dat', () {
    testWidgets(
      'paste_link_bam_nut_cai_dat_sang_man_hinh_settings',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.tap(find.byTooltip('Cài đặt'));
        await tester.pumpAndSettle();

        expect(find.text('Cài đặt'), findsWidgets);
        expect(find.text('Thứ tự provider'), findsOneWidget);
      },
    );
  });
}
