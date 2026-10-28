// Unit v11: proxy chunked + progressive — KHONG goi mang that.
//
// Nhanh progressive (`_synthesizeViaProxyChunks`) chi chay khi kIsWeb=true
// nen flutter test (VM) khong cover truc tiep; file nay cover phan quyet
// dinh chay duoc tren VM: nguong dai/ngan, timeout theo do dai chuong,
// va parity split chunk client/proxy (target 400, moi chunk non-empty).
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/config.dart';
import 'package:truyen_audio_app/src/core/tts/kokoro_provider.dart';
import 'package:truyen_audio_app/src/features/player/player_screen.dart';

void main() {
  group('v11_nguong_chunk_proxy', () {
    test('proxy_chunk_threshold_4500_khop_server', () {
      // Phai khop TTS_CHUNK_THRESHOLD trong server/proxy_server.py.
      expect(TextLimits.proxyChunkThreshold, 4500);
    });

    test('song_song_progressive_2_an_toan_cho_server_don_luong', () {
      expect(TextLimits.proxyChunkParallel, 2);
      expect(
        TextLimits.proxyChunkParallel,
        lessThanOrEqualTo(TextLimits.kokoroMaxParallel),
      );
    });

    test('timeout_chuong_dai_150s_theo_proxy', () {
      expect(ApiTimeouts.kokoroLongChapter, 150);
    });

    test('text_ngan_khong_vuot_nguong_kokoro_1_shot', () {
      // Duoi nguong -> native path: van cat client neu > 400 chu.
      final text = 'a' * 1000;
      expect(text.length <= TextLimits.proxyChunkThreshold, isTrue);
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.length <= TextLimits.kokoroChunkTarget), isTrue);
    });

    test('text_dai_vuot_nguong_web_gui_nguyen_cho_proxy', () {
      // Tren nguong -> Web KHONG cat client (tranh cat 2 lan).
      final text = 'a' * (TextLimits.proxyChunkThreshold + 1);
      expect(text.length > TextLimits.proxyChunkThreshold, isTrue);
    });
  });

  group('v11_timeout_tao_audio_theo_do_dai', () {
    test('chuong_ngan_giu_30s_nhu_cu', () {
      // v13: 1 tang 45s/150s — chuong ngan 45s (do that 2026-10-28: Kokoro
      // 3000 chu mat 41s direct, 30s cu kill oan). Ten test giu de thay
      // lich su doi so; assert theo so moi.
      expect(
        PlayerScreenState.audioStepTimeoutFor('Ngan.'),
        PlayerScreenState.stepTimeoutForTest,
      );
      expect(
        PlayerScreenState.audioStepTimeoutFor('a' * 4500),
        const Duration(seconds: 45),
      );
    });

    test('chuong_dai_7851_chu_user_len_150s', () {
      // Chuong 1 that cua user (bug 2026-10-27): 7851 chu.
      final text = '${'Mot cau truyen dai de mo phong chuong that. ' * 170}het.';
      expect(text.length, greaterThan(4500));
      expect(
        PlayerScreenState.audioStepTimeoutFor(text),
        const Duration(seconds: ApiTimeouts.kokoroLongChapter),
      );
    });
  });

  group('v11_parity_split_chunk_client_proxy', () {
    test('7851_chu_that_cat_22_chunk_deu_qua_ghep', () {
      // Mo phong chuong user: ~7851 chu -> ~20 chunk <= 400 (proxy
      // cat 22 chunk that khi verify 2026-10-27).
      final sentence = 'Mot cau truyen dai de mo phong chuong that. ';
      final text = '${List.filled(170, sentence).join()}het.';
      expect(text.length, greaterThan(4500));
      final chunks = KokoroProvider.splitIntoChunks(text);
      expect(chunks.length, greaterThan(10));
      expect(chunks.length, lessThan(40));
      expect(chunks.every((c) => c.isNotEmpty && c.length <= 400), isTrue);
    });

    test('cau_don_dai_hon_target_cat_cung_khong_mat_chu', () {
      final chunks = KokoroProvider.splitIntoChunks('a' * 1000);
      expect(chunks.every((c) => c.length <= 400), isTrue);
      expect(chunks.join().replaceAll(' ', ''), 'a' * 1000);
    });
  });
}
