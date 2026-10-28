// Widget test man hinh cai dat (/settings) — voice API FAKE, KHONG goi mang.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/config.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';

import 'fakes/test_app.dart';

void main() {
  group('settings_doi_provider_order', () {
    testWidgets(
      'settings_chon_kokoro_truoc_cap_nhat_provider_order',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/settings');
        // v8 default: Kokoro primary.
        expect(app.container.read(providerOrderSettingProvider), 'kokoro_first');

        await tester.tap(find.text('Vieneu trước'));
        await tester.pump();

        expect(app.container.read(providerOrderSettingProvider), 'vieneu_first');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'settings_chon_kokoro_truoc_cap_nhat_provider_order',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // Dat truoc vieneu_first roi doi lai kokoro_first (default v8).
        app.container.read(providerOrderSettingProvider.notifier).state =
            'vieneu_first';
        await routerGo(tester, '/settings');

        await tester.tap(find.text('Kokoro trước'));
        await tester.pump();

        expect(
          app.container.read(providerOrderSettingProvider),
          'kokoro_first',
        );
      },
    );
  });

  group('settings_chon_voice', () {
    testWidgets(
      'settings_hien_danh_sach_giong_fake_va_doi_duoc_voice',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/settings');
        // Dropdown hien voice mac dinh dang chon.
        expect(find.text('Trúc Ly (nữ Bắc)'), findsWidgets);
        expect(find.text('diem_trinh'), findsWidgets);
      },
    );

    testWidgets(
      'settings_voice_la_hien_mac_dinh_va_tu_reset_ve_mac_dinh',
      (tester) async {
        final app = makeTestApp(
          vieneu: FakeVieneuProvider(voices: defaultVieneuVoices()),
          kokoro: FakeKokoroProvider(voices: defaultKokoroVoices()),
        );
        // Seed voice rac (khong co trong list that) truoc khi vao settings.
        app.container.read(vieneuVoiceSettingProvider.notifier).state = 'Giong Rac';
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/settings');

        // Voice rac bi reset ve mac dinh (guard tranh gui voice id rac).
        expect(
          app.container.read(vieneuVoiceSettingProvider),
          DefaultVoice.vieneu,
        );
      },
    );

    testWidgets(
      'settings_api_voice_loi_hien_loi_va_nut_thu_lai',
      (tester) async {
        final app = makeTestApp(
          vieneu: FakeVieneuProvider(failWith: Exception('mang sap')),
          kokoro: FakeKokoroProvider(failWith: Exception('mang sap')),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/settings');

        expect(
          find.textContaining('Không tải được danh sách giọng'),
          findsOneWidget,
        );
        expect(find.text('Thử lại'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('settings_doi_toc_do', () {
    testWidgets(
      'settings_keo_slider_toc_do_cap_nhat_provider',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await routerGo(tester, '/settings');
        expect(app.container.read(speedSettingProvider), 1.0);

        final slider = find.byType(Slider);
        expect(slider, findsOneWidget);
        final center = tester.getCenter(slider);
        final size = tester.getSize(slider);
        await tester.tapAt(center + Offset(size.width * 0.25, 0));
        await tester.pump();

        expect(app.container.read(speedSettingProvider), isNot(1.0));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('settings_nut_back_ve_truoc', () {
    testWidgets(
      'settings_bam_back_ve_man_hinh_truoc_do',
      (tester) async {
        final app = makeTestApp();
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        // Di: / -> /settings bang nut Cai dat (co lich su) roi back.
        await tester.tap(find.byTooltip('Cài đặt'));
        await tester.pumpAndSettle();
        expect(find.text('Thứ tự provider'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('Dán link truyện để nghe'), findsOneWidget);
      },
    );
  });
}
