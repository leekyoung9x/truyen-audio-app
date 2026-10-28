import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cache/audio_cache.dart';
import '../../core/config.dart';
import '../../core/convert/chapter_audio.dart';
import '../../core/parse/parse_client.dart';
import '../../core/tts/fallback_chain.dart';
import '../app_providers.dart';
import 'audio_handler.dart';

/// Provider giu AudioHandler chay nen (khoi tao 1 lan tu main).
final audioHandlerProvider = Provider<StoryAudioHandler>((_) {
  throw UnimplementedError('audioHandlerProvider chua duoc override trong main().');
});

/// Man hinh phat audio.
///
/// - Mo len: tai audio cho chuong hien tai (cache -> fallback chain),
///   dong thoi prefetch 2 chuong ke tiep de phat lien tuc.
/// - Dieu khien: play/pause, next/prev, tua ±10s, toc do 0.5-1.5x,
///   hen gio ngu, thanh truot tien do (stream tu handler).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => PlayerScreenState();
}

/// State public chi de widget test rut ngan [stepTimeoutForTest]
/// (mo phong play() treo ma khong doi 45s that). Khong dung truc tiep.
@visibleForTesting
class PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _loading = true;
  String? _error;
  // v10: tach 2 trang thai — co audio (list items da load) vs dang phat.
  // Co audio la hien _ControlsView ngay, ke ca play() chua xong/treo.
  // items duoc luu rieng de build da co playslist ma khong phai load lai.
  List<ChapterMediaItem> _items = const [];
  int _loadToken = 0;

  /// v12: chuong prefetch that bai (timeout/mang) — KHONG vao playlist nen
  /// nut Next tu nhien bo qua. Chi hien notice nhe, khong phai loi do.
  Set<int> _failedChapters = const {};

  /// v12: thong bao nhe ve prefetch nen (vd: chuong 2 tai hong, se bo qua).
  /// Null = khong co gi de bao. KHONG chan phat chuong hien tai.
  String? _prefetchNotice;

  /// v12: fetch noi dung chuong ke o che do nen cung can timeout rieng
  /// (45s, dong bo [ApiTimeouts.flowShortChapter]) thay vi storm 45s
  /// cua step chinh. De public de test rut ngan khi can.
  @visibleForTesting
  static Duration prefetchFetchTimeout = const Duration(
    seconds: ApiTimeouts.flowShortChapter,
  );

  /// Timeout moi buoc _prepare (v10: Web treo o ensure/load/play khong
  /// resolve — phai bao ket chu khong ket vinh vien).
  /// De public de widget test co the rut ngan (vd 2s thay vi 45s
  /// production). Production LUON la [ApiTimeouts.flowShortChapter] (45s).
  @visibleForTesting
  static Duration stepTimeoutForTest = const Duration(
    seconds: ApiTimeouts.flowShortChapter,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  /// v13: 1 TANG TIMEOUT DUY NHAT cho ca flow theo do dai text (fix bug
  /// 2 tang chong nhau v11/v12: tang tao audio trong 150s bi tang step
  /// ngoai 30s kill truoc; do that 2026-10-28: Kokoro 3000 chu mat 41s
  /// direct nen 30s cu kill oan ca chuong ngan).
  /// - Chuong ngan (<= [TextLimits.proxyChunkThreshold]): 45s.
  /// - Chuong dai: [ApiTimeouts.kokoroLongChapter] (150s).
  /// [audioStepTimeoutFor]/[prefetchTimeoutFor] giu lai chi de uy thac ve
  /// day (khong con 2 so lech nhau); test/seam moi dung truc tiep ham nay.
  @visibleForTesting
  static Duration flowTimeoutFor(String text) {
    return text.trim().length > TextLimits.proxyChunkThreshold
        ? const Duration(seconds: ApiTimeouts.kokoroLongChapter)
        : const Duration(seconds: ApiTimeouts.flowShortChapter);
  }

  /// Timeout tao audio theo do dai text (v13: uy thac ve [flowTimeoutFor],
  /// 1 tang duy nhat 45s/150s; giu ten de khong vo test/caller cu).
  @visibleForTesting
  static Duration audioStepTimeoutFor(String text) => flowTimeoutFor(text);

  /// Timeout prefetch NEN theo do dai text (v13: uy thac ve [flowTimeoutFor],
  /// 1 tang duy nhat 45s/150s; giu ten de khong vo test/caller cu).
  @visibleForTesting
  static Duration prefetchTimeoutFor(String text) => flowTimeoutFor(text);

  Future<T> _step<T>(
    String stepLabel,
    Future<T> Function() run, {
    Duration? timeoutOverride,
  }) {
    final timeout = timeoutOverride ?? stepTimeoutForTest;
    // v13: hien buoc hien tai len loading view (audit ui-ux-pro-max:
    // progress phai noi DANG LAM GI). Set truoc, xoa sau moi ket qua.
    ref.read(synthStepProvider.notifier).state = _v13Buoc(stepLabel);
    return run().timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Kẹt ở $stepLabel quá ${timeout.inSeconds} giây '
        '(kịch bản Web đã biết). Hãy bấm Thử lại.',
      ),
    ).whenComplete(() {
      ref.read(synthStepProvider.notifier).state = null;
    });
  }

  /// Ten buoc hien thi v13: ngan gon, dung tu ngu UI ('tải nội dung...',
  /// 'tạo audio...', 'nạp playlist', ...) thay vi label noi bo cua _step.
  static String _v13Buoc(String stepLabel) => stepLabel;

  Future<void> _prepare() async {
    final token = ++_loadToken;
    bool alive() => mounted && token == _loadToken;
    final result = ref.read(parseResultProvider);
    final cache = ref.read(audioCacheProvider);
    // v10: vao thang #/player thieu state (parseResult null) -> thong bao
    // + ve / ngay, khong trang trang.
    if (result == null) {
      if (alive()) {
        // Hien snackbar TRUOC khi go (context con trong cay) — Snackbar
        // nam tren Router nen van hien sau khi ve /.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa có truyện nào. Hãy dán link truyện trước.'),
          ),
        );
        context.go('/');
      }
      return;
    }
    if (cache == null) {
      if (alive()) {
        setState(() {
          _loading = false;
          _error = 'Thiếu cache audio. Hãy khởi động lại app.';
        });
      }
      return;
    }
    final startIndex = ref.read(currentChapterIndexProvider) ?? 0;
    final chain = ref.read(fallbackChainProvider);
    final order = providerOrderFrom(ref.read(providerOrderSettingProvider));
    final vieneuVoice = ref.read(vieneuVoiceSettingProvider);
    final kokoroVoice = ref.read(kokoroVoiceSettingProvider);
    String voiceFor(String p) => p == 'Vieneu' ? vieneuVoice : kokoroVoice;
    double speedFor(String p) =>
        p == 'Vieneu' ? 1.0 : ref.read(speedSettingProvider);

    String chapterUrlOf(int i) {
      // v7 TOC: moi chuong co url that rieng (dung cho cache key).
      final info = result.chapters[i];
      if (info.hasUrl) return info.url;
      final base = ref.read(storyUrlProvider);
      return base.isEmpty ? 'text:$i' : '$base#chapter=$i';
    }

    // v7: TOC chua co text -> lazy-fetch tung chuong qua proxy (/parse
    // forward 8001 cho url chuong cu the), roi luu lai vao parseResult de
    // lan sau khong phai tai lai.
    Future<String?> textOf(int i) async {
      final cached = result.textOf(i);
      if (cached != null && cached.trim().isNotEmpty) return cached;
      final info = result.chapters[i];
      if (!info.hasUrl) return null;
      final fetched = await ref
          .read(parseClientProvider)
          .fetchChapterText(info.url);
      if (fetched.trim().isEmpty) return null;
      final texts = List<String>.of(result.texts);
      // texts co the ngan hon chapters (TOC: texts=[]). Dem day bang ''.
      while (texts.length < result.chapters.length) {
        texts.add('');
      }
      texts[i] = fetched;
      ref.read(parseResultProvider.notifier).state = result.copyWithTexts(texts);
      return fetched;
    }

    setState(() {
      _loading = true;
      _error = null;
      _items = const [];
      _failedChapters = const {};
      _prefetchNotice = null;
    });
    try {
      // v12: chi chuong HIEN TAI la blocking (tai -> nap playlist -> phat).
      // 2 chuong ke prefetch NEN (unawaited): loi chi log + notice nhe,
      // KHONG duoc set _error do hay chan chuong dang phat.
      //
      // v12: reset synthProgress ve chi con chuong hien tai (tranh leak
      // state chuong cu sang chuong moi khi chuyen chuong trong cung
      // vi doi widget — _prepare chay lai voi startIndex moi).
      ref.read(synthProgressProvider.notifier).state = {startIndex: 0.0};
      // v13: moc ETA cho loading view (audit ui-ux-pro-max).
      ref.read(synthStartProvider.notifier).state = DateTime.now();
      final file = await _buildOneChapter(
        index: startIndex,
        textOf: textOf,
        chapterUrlOf: chapterUrlOf,
        cache: cache,
        chain: chain,
        order: order,
        voiceFor: voiceFor,
        speedFor: speedFor,
        alive: alive,
        progressSeed: 0.0,
      );
      if (file == null) {
        // Chuong hien tai hong -> loi do nhu cu (khong co gi de phat).
        if (alive()) {
          setState(() {
            _loading = false;
            _error = 'Không tải được audio chương ${startIndex + 1}.';
          });
        }
        return;
      }
      final handler = ref.read(audioHandlerProvider);
      final currentItem = _toMediaItem(
        index: startIndex,
        file: file,
        title: result.chapters[startIndex].title,
        storyUrl: ref.read(storyUrlProvider),
      );
      // v10: co audio la hien controls NGAY (ke ca play() chua xong).
      if (alive()) {
        setState(() {
          _items = List<ChapterMediaItem>.unmodifiable([currentItem]);
          _loading = false;
        });
        // v13: het loading chuong hien tai -> xoa moc ETA + buoc.
        ref.read(synthStartProvider.notifier).state = null;
        ref.read(synthStepProvider.notifier).state = null;
      }
      await _step('nạp playlist', () => handler.loadPlaylist([currentItem]));
      await _step(
        'đặt tốc độ phát',
        () => handler.setPlaybackSpeed(ref.read(speedSettingProvider)),
      );
      // v12: prefetch chay NEN ngay sau khi playlist da nap (khong doi
      // play xong) — dung unawaited + try/catch rieng, khong await.
      unawaited(
        _prefetchNext(
          handler: handler,
          ref: ref,
          result: result,
          startIndex: startIndex,
          textOf: textOf,
          chapterUrlOf: chapterUrlOf,
          cache: cache,
          chain: chain,
          order: order,
          voiceFor: voiceFor,
          speedFor: speedFor,
          alive: alive,
          loadToken: token,
        ),
      );
      try {
        await _step('phát audio', handler.play);
      } on TimeoutException {
        // v10: play() treo sau khi playlist da nap -> audio san sang.
        // Controls da hien o tren (state paused); user bam phat lai.
        // Giu loi lam notice (khong chan UI) thay vi man hinh loi.
        if (alive()) {
          setState(() {
            _error = 'Audio đã sẵn sàng nhưng tự phát thất bại. '
                'Hãy bấm nút Phát.';
          });
        }
      }
    } on TtsAllFailedException catch (e) {
      if (alive()) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } catch (e) {
      if (alive()) {
        setState(() {
          _loading = false;
          _error = 'Tải audio thất bại: $e';
        });
      }
    } finally {
      if (alive() && (_error != null || _items.isEmpty)) {
        setState(() => _loading = false);
      }
    }
  }

  /// Tai + tao audio cho 1 chuong (blocking, cho chuong HIEN TAI).
  ///
  /// - Thanh cong -> tra [CachedAudio].
  /// - Chuong loi (fetch hong, trong, timeout, TTS hong het) -> tra null
  ///   (caller quyet dinh: chuong hien tai null = loi do; prefetch null
  ///   = danh dau failed, KHONG bao gio throw ra _prepare tu prefetch).
  /// - [isPrefetch]: true -> dung timeout prefetch rieng 45s/150s
  ///   ([prefetchTimeoutFor]) thay vi timeout step chinh 45s/150s —
  ///   cam dung so cung khac tang flow (bug v12).
  Future<CachedAudio?> _buildOneChapter({
    required int index,
    required Future<String?> Function(int i) textOf,
    required String Function(int i) chapterUrlOf,
    required AudioCache cache,
    required FallbackChain chain,
    required ProviderOrder order,
    required String Function(String p) voiceFor,
    required double Function(String p) speedFor,
    required bool Function() alive,
    bool isPrefetch = false,
    Duration retryDelay = const Duration(seconds: 2),
    double progressSeed = -1.0,
  }) async {
    if (!alive()) return null;
    String? text;
    try {
      // v12: chuong hien tai van hien buoc ro rang khi fetch treo;
      // prefetch fetch treo cung KHONG throw — tra null de danh dau failed.
      final fetchFut = textOf(index);
      text = isPrefetch
          ? await fetchFut.timeout(
              prefetchFetchTimeout,
              onTimeout: () => throw TimeoutException(
                'Kẹt ở tải nội dung chương ${index + 1} quá '
                '${prefetchFetchTimeout.inSeconds} giây (prefetch nền).',
              ),
            )
          : await _step(
              'tải nội dung chương ${index + 1}',
              () => fetchFut,
            );
    } on Exception {
      return null; // chuong loi: bo qua, van phat chuong tai duoc
    }
    if (text == null || text.trim().isEmpty) return null;
    if (progressSeed >= 0 && alive()) {
      ref.read(synthProgressProvider.notifier).state = {
        ...ref.read(synthProgressProvider),
        index: progressSeed,
      };
    }
    CachedAudio? file;
    try {
      if (isPrefetch) {
        // v12: prefetch — timeout rieng 45s/150s + retry 1 lan + backoff 2s.
        file = await prefetchChapterAudio(
          cache: cache,
          chain: chain,
          text: text,
          chapterUrl: chapterUrlOf(index),
          order: order,
          voiceFor: voiceFor,
          speedFor: speedFor,
          onProgress: (p) {
            if (alive()) {
              ref.read(synthProgressProvider.notifier).state = {
                ...ref.read(synthProgressProvider),
                index: p,
              };
            }
          },
          timeout: prefetchTimeoutFor(text),
          retryDelay: retryDelay,
        );
      } else {
        file = await _step(
          'tạo audio chương ${index + 1}',
          timeoutOverride: audioStepTimeoutFor(text),
          () => ensureChapterAudio(
            cache: cache,
            chain: chain,
            text: text!,
            chapterUrl: chapterUrlOf(index),
            order: order,
            voiceFor: voiceFor,
            speedFor: speedFor,
            onProgress: (p) {
              ref.read(synthProgressProvider.notifier).state = {
                ...ref.read(synthProgressProvider),
                index: p,
              };
            },
          ),
        );
      }
    } on Exception {
      return null; // timeout/TTS hong -> caller danh dau failed
    }
    if (file != null && alive()) {
      ref.read(synthProgressProvider.notifier).state = {
        ...ref.read(synthProgressProvider),
        index: 1.0,
      };
    }
    return file;
  }

  /// Prefetch 2 chuong ke sau khi chuong hien tai da play (v12): chay NEN,
  /// KHONG BAO GIO throw, KHONG set _error do.
  ///
  /// - Moi chuong: tai qua [_buildOneChapter] (isPrefetch: true).
  /// - Thanh cong -> hien progress 1.0 (da san sang).
  /// - That bai -> progress -1 + [_failedChapters] + [_prefetchNotice] nhe
  ///   (user biet chuong do se bi bo qua khi bam Next).
  /// - [loadToken]: token cua _prepare da kich hoat; token lech (user
  ///   chuyen chuong giua chung) -> dung ngay, khong cap nhat UI cu.
  Future<void> _prefetchNext({
    required StoryAudioHandler handler,
    required WidgetRef ref,
    required ParseResult result,
    required int startIndex,
    required Future<String?> Function(int i) textOf,
    required String Function(int i) chapterUrlOf,
    required AudioCache cache,
    required FallbackChain chain,
    required ProviderOrder order,
    required String Function(String p) voiceFor,
    required double Function(String p) speedFor,
    required bool Function() alive,
    required int loadToken,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    final end = (startIndex + 3).clamp(0, result.chapters.length).toInt();
    for (var i = startIndex + 1; i < end; i++) {
      // Token lech = user da chuyen chuong -> prefetch cu dung ngay.
      if (!alive() || loadToken != _loadToken) return;
      final file = await _buildOneChapter(
        index: i,
        textOf: textOf,
        chapterUrlOf: chapterUrlOf,
        cache: cache,
        chain: chain,
        order: order,
        voiceFor: voiceFor,
        speedFor: speedFor,
        alive: alive,
        isPrefetch: true,
        retryDelay: retryDelay,
      );
      if (!alive() || loadToken != _loadToken) return;
      setState(() {
        if (file == null) {
          _failedChapters = {..._failedChapters, i};
          ref.read(synthProgressProvider.notifier).state = {
            ...ref.read(synthProgressProvider),
            i: -1.0,
          };
          _prefetchNotice =
              'Chương ${i + 1} tải nền thất bại (sẽ bỏ qua khi bấm Chương sau).';
        }
      });
      if (file == null) continue;
      // Chen vao playlist hien tai qua cheap-append (khong nap lai tu dau,
      // khong giat audio dang phat). Loi chen cung chi la notice nhe.
      try {
        final item = _toMediaItem(
          index: i,
          file: file,
          title: result.chapters[i].title,
          storyUrl: ref.read(storyUrlProvider),
        );
        await handler.appendToPlaylist(item);
        // Giu _items dong bo voi playlist that de UI biet so luong.
        if (_items.isNotEmpty && _items.first.id == 'chapter-$startIndex') {
          final items = List<ChapterMediaItem>.of(_items)..add(item);
          setState(() {
            _items = List<ChapterMediaItem>.unmodifiable(items);
          });
        }
      } catch (e) {
        // Ghep playlist loi (hiem) -> cung chi la notice nhe.
        debugPrint('prefetch: chen playlist loi ($e).');
      }
    }
  }

  /// Tao [ChapterMediaItem] tu audio 1 chuong (dung chung cho chuong
  /// hien tai va prefetch).
  ///
  /// - Native truyen filePath; Web truyen bytes (khong co file that).
  ChapterMediaItem _toMediaItem({
    required int index,
    required CachedAudio file,
    required String title,
    required String storyUrl,
  }) {
    return ChapterMediaItem(
      id: 'chapter-$index',
      title: title,
      album: storyUrl,
      filePath: file.filePath,
      audioBytes: file.filePath != null ? null : file.bytes,
      mimeType: 'audio/${file.extension}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final result = ref.watch(parseResultProvider);
    final startIndex = ref.watch(currentChapterIndexProvider) ?? 0;
    final title = (result != null && startIndex < result.chapters.length)
        ? result.chapters[startIndex].title
        : 'Đang phát';

    // v10: co audio (_items) la hien controls NGAY — ke ca _loading van
    // true (play() chua xong) hay co notice nhe. Chi hien loading khi chua
    // co item nao; chi hien loi day man hinh khi chua co item nao.
    //
    // v12: notice uu tien: loi do chuong hien tai (_error) truoc, roi den
    // notice nhe ve prefetch nen (_prefetchNotice). ca 2 deu khong chan
    // controls khi da co audio.
    final String? notice = _error ?? _prefetchNotice;
    final VoidCallback? onDismissNotice = _loading
        ? null
        : () => setState(() {
              _error = null;
              _prefetchNotice = null;
            });
    final Widget body;
    if (_items.isNotEmpty) {
      body = _ControlsView(
        handler: handler,
        title: title,
        notice: notice,
        onDismissNotice: onDismissNotice,
      );
    } else if (_loading) {
      body = const _LoadingView();
    } else if (_error != null) {
      body = _ErrorView(message: _error!, onRetry: _prepare);
    } else {
      body = const _LoadingView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đang phát'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chapters'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends ConsumerWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(synthProgressProvider);
    final step = ref.watch(synthStepProvider);
    final started = ref.watch(synthStartProvider);
    final current = ref.watch(currentChapterIndexProvider) ?? 0;
    final pct = progress[current];
    // v13 (audit ui-ux-pro-max + design-taste): loading phai noi DANG
    // LAM GI + ETA thay vi chi % — user kẹt 45-150s can biet buoc nao.
    String? eta;
    if (pct != null && started != null && pct > 0.02 && pct < 1.0) {
      final elapsed = DateTime.now().difference(started);
      final remain = elapsed * ((1 - pct) / pct);
      final s = remain.inSeconds;
      eta = s >= 60 ? 'còn ~${s ~/ 60}p${s % 60}s' : 'còn ~${s}s';
    }
    final stepLabel = step ?? 'Đang chuẩn bị audio...';
    final pctLabel = pct == null
        ? stepLabel
        : 'Đang tạo audio... ${(pct * 100).toStringAsFixed(0)}%'
            '${eta == null ? '' : ' ($eta)'}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        // Tabular figures: % dem khong nhay chieu rong (audit ui-ux-pro-max).
        Text(
          pctLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (step != null && pct != null) ...[
          const SizedBox(height: 4),
          Text(
            step,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (pct != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: pct.clamp(0.0, 1.0).toDouble()),
        ],
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    );
  }
}

class _ControlsView extends ConsumerStatefulWidget {
  const _ControlsView({
    required this.handler,
    required this.title,
    this.notice,
    this.onDismissNotice,
  });

  final StoryAudioHandler handler;
  final String title;

  /// v10: thong bao nhe (vd: play() treo da nuot) — hien ben tren controls,
  /// khong chan UI. Null = khong co thong bao.
  final String? notice;
  final VoidCallback? onDismissNotice;

  @override
  ConsumerState<_ControlsView> createState() => _ControlsViewState();
}

class _ControlsViewState extends ConsumerState<_ControlsView> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerStateSnapshot>(
      stream: widget.handler.snapshotStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final position = state?.position ?? Duration.zero;
        final duration = state?.duration;
        final speed = state?.speed ?? 1.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // v10: notice (vd: play() treo da nuot) — hien nhung khong chan
            // controls. Khong dismiss duoc khi van dang loading.
            if (widget.notice != null) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.notice!)),
                      if (widget.onDismissNotice != null)
                        IconButton(
                          tooltip: 'Đóng',
                          iconSize: 20,
                          icon: const Icon(Icons.close),
                          onPressed: widget.onDismissNotice,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Icon trang tri: an khoi screen-reader (title ben duoi da ro nghia).
            Icon(
              Icons.headphones,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
              semanticLabel: null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            // Vung keo min 48dp de dat WCAG touch-target.
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value:
                    duration != null && duration.inMilliseconds > 0
                        ? position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble()
                        : 0,
                max: duration != null && duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: duration == null
                    ? null
                    : (v) => widget.handler.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tabular figures: so khong nhay chieu rong khi dem giay.
                Text(
                  _fmt(position),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _fmt(duration ?? Duration.zero),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Lùi 10s',
                  iconSize: 32,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => widget.handler.rewind(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Chương trước',
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => widget.handler.skipToPrevious(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    // Hit-area >= 48x48 (MD min) ma van giu vong tron.
                    minimumSize: const Size(72, 72),
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: () => playing
                      ? widget.handler.pause()
                      : widget.handler.play(),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 36,
                    semanticLabel: playing ? 'Tạm dừng' : 'Phát',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Chương sau',
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => widget.handler.skipToNext(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Tiến 10s',
                  iconSize: 32,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => widget.handler.forward(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Tốc độ'),
                Expanded(
                  child: Slider(
                    value: speed.clamp(0.5, 1.5).toDouble(),
                    min: 0.5,
                    max: 1.5,
                    divisions: 10,
                    label: '${speed.toStringAsFixed(1)}x',
                    onChanged: (v) async {
                      ref.read(speedSettingProvider.notifier).state = v;
                      await widget.handler.setPlaybackSpeed(v);
                    },
                  ),
                ),
                Text('${speed.toStringAsFixed(1)}x'),
              ],
            ),
            const SizedBox(height: 8),
            _SleepTimerRow(handler: widget.handler),
          ],
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _SleepTimerRow extends ConsumerWidget {
  const _SleepTimerRow({required this.handler});

  final StoryAudioHandler handler;

  static const options = [null, 15, 30, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(sleepTimerMinutesProvider);
    return Row(
      children: [
        const Icon(Icons.bedtime_outlined),
        const SizedBox(width: 8),
        const Text('Hẹn giờ ngủ'),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((minutes) {
                final label = minutes == null ? 'Tắt' : '${minutes}p';
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: selected == minutes,
                    onSelected: (_) {
                      ref.read(sleepTimerMinutesProvider.notifier).state = minutes;
                      handler.setSleepTimer(
                        minutes == null ? null : Duration(minutes: minutes),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
