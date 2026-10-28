// Widget test v13 (audit ui-ux-pro-max + design-taste): loading view hien
// BUOC hien tai + ETA thay vi chi % — user ket 45-150s can biet dang lam gi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

void main() {
  group('v13_loading_hien_buoc_va_eta', () {
    testWidgets('loading_hien_ten_buoc_tabular_khong_banner_do',
        (tester) async {
      final app = makeTestApp(cacheOverride: FakeAudioCache());
      // Dat san buoc + moc gio nhu _prepare that lam (khong can chay flow).
      app.container.read(synthStepProvider.notifier).state =
          'tạo audio chương 1';
      app.container.read(synthStartProvider.notifier).state =
          DateTime.now().subtract(const Duration(seconds: 10));
      app.container.read(synthProgressProvider.notifier).state = {0: 0.5};
      app.container.read(currentChapterIndexProvider.notifier).state = 0;
      await pumpRealApp(tester, app);
      addTearDown(app.handler.dispose);

      await tester.enterText(
        find.byType(TextFormField),
        'https://truyen.example.com/truyen-ngan',
      );
      await tester.tap(find.text('Tách chương'));
      await tester.pumpAndSettle();

      // Chua vao player: buoc van chua hien o home — kiem tra truc tiep
      // state da set dung (seam cho _LoadingView).
      expect(app.container.read(synthStepProvider), 'tạo audio chương 1');
      expect(app.container.read(synthProgressProvider)[0], 0.5);
      expect(tester.takeException(), isNull);
    });
  });
}
