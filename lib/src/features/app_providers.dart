import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache/audio_cache.dart';
import '../core/convert/queue_client.dart';
import '../core/parse/parse_client.dart';
import '../core/tts/fallback_chain.dart';
import '../core/tts/kokoro_provider.dart';
import '../core/tts/vieneu_provider.dart';

// --- Core singletons ---

final parseClientProvider = Provider<ParseClient>((ref) => ParseClient());

/// v14: client queue convert nen full truyen.
final queueClientProvider = Provider<QueueClient>((ref) => QueueClient());

/// v14: tien do queue hien tai (null = chua tao queue). App poll 5s/lan
/// cap nhat provider nay de thanh progress tong (x/200 chuong) hien lien.
final queueProgressProvider = StateProvider<QueueProgress?>((ref) => null);

/// v14: queue_id dang chay (de poll tiep khi chuyen man hinh). '' = khong co.
final queueIdProvider = StateProvider<String>((ref) => '');

final vieneuProvider = Provider<VieneuProvider>((ref) => VieneuProvider());

final kokoroProvider = Provider<KokoroProvider>(
  // v11: truyen giong Vieneu user chon de progressive fallback chunk
  // giu dung giong (watch de doi giong co hieu luc ngay).
  (ref) => KokoroProvider(
    vieneuVoiceForFallback: ref.watch(vieneuVoiceSettingProvider),
  ),
);

final fallbackChainProvider = Provider<FallbackChain>((ref) {
  return FallbackChain(providers: {
    'Vieneu': ref.watch(vieneuProvider),
    'Kokoro': ref.watch(kokoroProvider),
  });
});

final audioCacheProvider = Provider<AudioCache?>((ref) => null);

// --- Settings (persist don gian bang StateProvider; luu Hive o settings_screen) ---

/// Thu tu provider: 'kokoro_first' | 'vieneu_first' (v8: Kokoro primary).
final providerOrderSettingProvider =
    StateProvider<String>((ref) => 'kokoro_first');

/// Voice theo tung provider.
final vieneuVoiceSettingProvider = StateProvider<String>((ref) => 'Trúc Ly');
final kokoroVoiceSettingProvider = StateProvider<String>((ref) => 'diem_trinh');

/// Toc do doc 0.5-1.5.
final speedSettingProvider = StateProvider<double>((ref) => 1.0);

/// v8: Kokoro primary — gia tri la ve Kokoro (khong con ve Vieneu).
ProviderOrder providerOrderFrom(String value) => value == 'vieneu_first'
    ? ProviderOrder.vieneuFirst
    : ProviderOrder.kokoroFirst;

// --- Parse state ---

/// URL truyen hien tai (do user paste).
final storyUrlProvider = StateProvider<String>((ref) => '');

/// Ket qua parse gan nhat.
final parseResultProvider = StateProvider<ParseResult?>((ref) => null);

/// Dang parse (de hien thi loading tren paste_link_screen).
final parsingProvider = StateProvider<bool>((ref) => false);

/// Loi parse gan nhat (de hien thi snackbar).
final parseErrorProvider = StateProvider<String?>((ref) => null);

// --- Synthesize state (theo chuong) ---

/// Tien do tong hop audio: key = index chuong, value = 0.0-1.0 (-1 = loi).
final synthProgressProvider =
    StateProvider<Map<int, double>>((ref) => const {});

/// Buoc tong hop audio hien tai (v13, audit ui-ux-pro-max: progress phai
/// noi DANG LAM GI, khong chi %): vd 'tải nội dung chương 1',
/// 'tạo audio chương 1', 'nạp playlist'. Null = khong co buoc nao.
final synthStepProvider = StateProvider<String?>((ref) => null);

/// Thoi diem bat dau tong hop chuong hien tai (v13): uoc tinh ETA tren
/// loading view (elapsed/progress*(1-progress)). Null = chua bat dau.
final synthStartProvider = StateProvider<DateTime?>((ref) => null);

// --- Player state ---

/// Index chuong dang phat trong playlist (null = chua phat).
final currentChapterIndexProvider = StateProvider<int?>((ref) => null);

/// Hen gio ngu (phut). null = tat.
final sleepTimerMinutesProvider = StateProvider<int?>((ref) => null);
