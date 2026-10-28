// Unit v13: 1 TANG TIMEOUT DUY NHAT theo do dai chuong (RED: viet truoc fix).
//
// Bug goc (user 2026-10-28): "Ket o tao audio chuong 2/3 qua 30 giay" du
// proxy v11 da nang chuong dai len 150s. Root cause: 2 tang timeout chong
// nhau — tang tao audio (audioStepTimeoutFor: 30s ngan / 150s dai) bi tang
// step ngoai 30s kill truoc; do that 2026-10-28: Kokoro 3000 chu mat 41s
// (direct) nen ngay ca chuong NGAN cung chet oan o tang 30s.
//
// Spec v13: 1 tang duy nhat cho CA flow: text <= 4500 chu = 45s; > 4500 chu
// = 150s. Cam moi `.timeout(30s)` cung trong player_screen / chapter_audio
// / audio_handler. Prefetch loi: im lang retry nen 1 lan (backoff 2s),
// khong set _error (da co tu v12, giu nguyen).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/config.dart';
import 'package:truyen_audio_app/src/features/player/player_screen.dart';

void main() {
  group('v13_mot_tang_timeout_theo_do_dai', () {
    test('chuong_ngan_3000_chu_di_het_flow_45s', () {
      // Chuong 2 that cua user: 3000 chu, do that Kokoro direct = 41s.
      // 1 tang 45s phai song sot (30s cu kill oan).
      expect(PlayerScreenState.flowTimeoutFor('a' * 3000),
          const Duration(seconds: 45));
    });

    test('bien_4500_chu_van_tang_ngan_45s', () {
      expect(PlayerScreenState.flowTimeoutFor('a' * 4500),
          const Duration(seconds: 45));
    });

    test('qua_nguong_4501_chu_len_tang_dai_150s', () {
      expect(PlayerScreenState.flowTimeoutFor('a' * 4501),
          const Duration(seconds: 150));
    });

    test('chuong_dai_8000_chu_di_het_flow_150s', () {
      // Khong mock timeout: selector thuan tuy, chay that < 1ms.
      final text = 'Mot cau truyen dai de mo phong chuong that. ' * 178;
      expect(text.length, greaterThan(4500));
      expect(PlayerScreenState.flowTimeoutFor(text),
          const Duration(seconds: 150));
    });

    test('audio_va_prefetch_dong_nhat_mot_tang', () {
      // 2 duong cu (audioStepTimeoutFor / prefetchTimeoutFor) phai cho
      // CUNG 1 so nhu flowTimeoutFor — khong con 2 tang lech nhau.
      for (final n in const [100, 3000, 4500, 4501, 8000]) {
        final text = 'a' * n;
        final flow = PlayerScreenState.flowTimeoutFor(text);
        expect(PlayerScreenState.audioStepTimeoutFor(text), flow,
            reason: 'audioStepTimeoutFor lech tang o $n chu');
        expect(PlayerScreenState.prefetchTimeoutFor(text), flow,
            reason: 'prefetchTimeoutFor lech tang o $n chu');
      }
    });

    test('hang_so_tang_ngan_45s_dai_150s', () {
      expect(ApiTimeouts.flowShortChapter, 45);
      expect(ApiTimeouts.kokoroLongChapter, 150);
    });

    test('khong_con_timeout_30s_cung_trong_3_file_player', () {
      // Regression guard doc that source (tien le app_startup_test):
      // cam `.timeout(...30...)` / `Duration(seconds: 30)` cung trong
      // flow tao audio (player_screen, chapter_audio, audio_handler).
      // Rieng test seam `stepTimeoutForTest` default phai la 45s.
      for (final path in const [
        'lib/src/features/player/player_screen.dart',
        'lib/src/core/convert/chapter_audio.dart',
        'lib/src/features/player/audio_handler.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('Duration(seconds: 30)'), isFalse,
            reason: '$path van con Duration(seconds: 30) cung');
      }
      expect(PlayerScreenState.stepTimeoutForTest,
          const Duration(seconds: 45));
    });
  });
}
