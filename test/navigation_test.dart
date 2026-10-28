// Test dieu huong go_router: full hanh trinh + route la + back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

void main() {
  group('navigation_hanh_trinh_day_du', () {
    testWidgets(
      'navigation_di_qua_4_man_hinh_ve_dung_tieu_de_moi_trang',
      (tester) async {
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // / : PasteLink
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);

        // / -> /settings
        await tester.tap(find.byTooltip('Cài đặt'));
        await tester.pumpAndSettle();
        expect(find.text('Thứ tự provider'), findsOneWidget);

        // /settings -> / (back) -> parse -> /chapters
        await routerGo(tester, '/');
        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();
        expect(find.text('3 chương'), findsOneWidget);

        // /chapters -> /player
        await tester.tap(find.text('Chương 1: Khởi đầu'));
        await tester.pumpAndSettle();
        expect(find.text('Đang phát'), findsWidgets);

        // /player -> /chapters (nut back)
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('3 chương'), findsOneWidget);
      },
    );
  });

  group('navigation_route_sai_hien_error_khong_trang', () {
    testWidgets(
      'navigation_route_khong_ton_tai_hien_trang_loi_khong_crash',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/route-khong-ton-tai');

        expect(tester.takeException(), isNull);
        // go_router mac dinh hien MaterialErrorScreen 'Page Not Found'.
        expect(find.text('Page Not Found'), findsOneWidget);
        // Khong trang xoa: van co Scaffold + nut ve Home.
        expect(find.byType(Scaffold), findsWidgets);
        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets(
      'navigation_tu_trang_loi_bam_home_ve_trang_chu',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/route-khong-ton-tai');
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });
}
