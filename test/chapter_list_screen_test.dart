// Widget test man hinh danh sach chuong (/chapters) — KHONG goi API that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

/// Di qua flow that: nhap link -> parse mock -> /chapters.
Future<void> _toiManHinhChapters(WidgetTester tester, String url) async {
  await tester.enterText(find.byType(TextFormField), url);
  await tester.tap(find.text('Tách chương'));
  await tester.pumpAndSettle();
}

void main() {
  group('chapter_list_render_list_chuong_mock', () {
    testWidgets(
      'chapter_list_co_du_lieu_hien_dung_3_chuong_va_so_ky_tu',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _toiManHinhChapters(
          tester,
          'https://truyen.example.com/truyen-hay',
        );

        expect(tester.takeException(), isNull);
        expect(find.text('3 chương'), findsOneWidget);
        expect(find.text('Chương 1: Khởi đầu'), findsOneWidget);
        expect(find.text('Chương 2: Lên đường'), findsOneWidget);
        expect(find.text('Chương 3: Hồi kết'), findsOneWidget);
        expect(find.textContaining('120 ký tự'), findsOneWidget);
      },
    );
  });

  group('chapter_list_bam_chuong_dieu_huong_player', () {
    testWidgets(
      'chapter_list_bam_1_chuong_chuyen_sang_player_va_set_index',
      (tester) async {
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _toiManHinhChapters(
          tester,
          'https://truyen.example.com/truyen-hay',
        );

        // Bam chuong 2 (index 1).
        await tester.tap(find.text('Chương 2: Lên đường'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(app.container.read(currentChapterIndexProvider), 1);
        expect(find.text('Đang phát'), findsWidgets);
      },
    );

    testWidgets(
      'chapter_list_bam_nghe_tu_dau_mo_player_tu_chuong_0',
      (tester) async {
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _toiManHinhChapters(
          tester,
          'https://truyen.example.com/truyen-hay',
        );

        await tester.tap(find.byTooltip('Nghe từ đầu'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(app.container.read(currentChapterIndexProvider), 0);
        expect(find.text('Đang phát'), findsWidgets);
      },
    );

    testWidgets(
      'chapter_list_bam_nut_doi_truyen_ve_man_hinh_chu',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await _toiManHinhChapters(
          tester,
          'https://truyen.example.com/truyen-hay',
        );

        await tester.tap(find.byTooltip('Đổi truyện'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });

  group('chapter_list_list_rong_hien_empty_state', () {
    testWidgets(
      'chapter_list_chua_co_du_lieu_hien_huong_dan_ve_trang_chu',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // Dieu huong thang toi /chapters khi chua parse (deep-link).
        await routerGo(tester, '/chapters');
        expect(tester.takeException(), isNull);

        // Empty-state: huong dan + nut ve trang chu.
        expect(find.text('Chưa có dữ liệu. Hãy dán link trước.'), findsOneWidget);
        expect(find.text('Về trang chủ'), findsOneWidget);

        // Bam ve trang chu.
        await tester.tap(find.text('Về trang chủ'));
        await tester.pumpAndSettle();
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });
}
