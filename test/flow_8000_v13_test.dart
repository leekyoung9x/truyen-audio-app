// Widget test v13: chuong 8000 chu di HET flow (KHONG mock timeout).
//
// Nghiem thu brief: "case chuong 8000 chu di het flow, do thoi gian that,
// KHONG mock timeout". Fake TTS tra ngay (khong treo) nen khong can rut
// ngan seam; assert flowTimeoutFor(8000 chu) = 150s + audio hien + khong
// banner do; do wall-clock that cua ca test qua Stopwatch (in ra log).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';
import 'package:truyen_audio_app/src/features/player/player_screen.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

void main() {
  group('v13_chuong_8000_chu_het_flow_khong_mock_timeout', () {
    testWidgets('chuong_dai_8000_chu_phat_duoc_khong_banner_do', (tester) async {
      final sw = Stopwatch()..start();
      // Chuong 1: 8000 chu that (> 4500 -> tang 150s). Khong rut ngan bat
      // ky seam timeout nao — chay dung production timeout.
      final longText = '${'Mot cau truyen dai de mo phong chuong that. ' * 178}het.';
      expect(longText.length, greaterThan(4500));
      expect(PlayerScreenState.flowTimeoutFor(longText),
          const Duration(seconds: 150));

      final app = makeTestApp(
        cacheOverride: FakeAudioCache(),
        parseClient: makeStubParseClient(
          chapters: const [
            {'title': 'Chương 1: Dài 8000 chữ', 'len': 8000},
            {'title': 'Chương 2: Ngắn', 'len': 20},
            {'title': 'Chương 3: Ngắn', 'len': 20},
          ],
          texts: [longText, 'Ngan hai.', 'Ngan ba.'],
        ),
      );
      await pumpRealApp(tester, app);
      addTearDown(app.handler.dispose);

      await tester.enterText(
        find.byType(TextFormField),
        'https://truyen.example.com/truyen-dai',
      );
      await tester.tap(find.text('Tách chương'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chương 1: Dài 8000 chữ'));
      await tester.pumpAndSettle();

      sw.stop();
      // ignore: avoid_print
      print('v13_8000chu_wall_clock_ms=${sw.elapsedMilliseconds}');
      expect(tester.takeException(), isNull);
      // Phat duoc chuong dai (controls + pause), khong man hinh loi day.
      expect(find.text('Chương 1: Dài 8000 chữ'), findsWidgets);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // TTS fake duoc goi voi FULL text dai (khong bi cat o client).
      final kokoro = app.container.read(kokoroProvider);
      expect((kokoro as FakeKokoroProvider).synthesizeCalls, greaterThan(0));
    });

    testWidgets('chuong_ngan_3000_chu_khong_chet_30s_cu', (tester) async {
      // Regression truc tiep bug user: chuong 3000 chu (do that Kokoro
      // 41s) — tang 30s cu kill oan; tang 45s moi song sot.
      final text3000 = 'a ' * 1500; // 3000 chu
      expect(PlayerScreenState.flowTimeoutFor(text3000),
          const Duration(seconds: 45));
      final app = makeTestApp(
        cacheOverride: FakeAudioCache(),
        parseClient: makeStubParseClient(
          chapters: const [
            {'title': 'Chương 1: Ngắn', 'len': 3000},
          ],
          texts: [text3000],
        ),
      );
      await pumpRealApp(tester, app);
      addTearDown(app.handler.dispose);

      await tester.enterText(
        find.byType(TextFormField),
        'https://truyen.example.com/truyen-ngan',
      );
      await tester.tap(find.text('Tách chương'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chương 1: Ngắn'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });
}
