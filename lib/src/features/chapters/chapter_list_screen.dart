import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/convert/queue_client.dart';
import '../../core/parse/parse_client.dart';
import '../app_providers.dart';

/// Man hinh danh sach chuong sau khi parse.
///
/// Nhan vao chuong: mo man hinh player; player se tu tai audio
/// (cache truoc, thieu thi tong hop qua fallback chain) va phat
/// lien tuc nhieu chuong. Hien tien do tong hop theo chuong.
///
/// v9: ho tro phan trang TOC — proxy tra ngay page 1 + metadata
/// (page/max_page/total_estimate). Bam trang nao goi
/// [ParseClient.fetchTocPage] trang do (prefetch trang ke khi ranh).
class ChapterListScreen extends ConsumerStatefulWidget {
  const ChapterListScreen({super.key});

  @override
  ConsumerState<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends ConsumerState<ChapterListScreen> {
  /// Cac trang dang tai (tranh bam lap khi request cham ~14s/page).
  final Set<int> _loadingPages = {};

  /// Loi tai trang gan nhat (hien snackbar 1 lan).
  String? _pageError;

  /// Da prefetch trang ke sau lan hien thi dau (tranh lap lai moi build).
  int _prefetchedFor = -1;

  /// v14: dang tao queue convert nen (disable nut tranh bam lap).
  bool _dangTaoQueue = false;

  /// v14: timer poll tien do queue 5s/lan. Huy khi roi man hinh.
  Timer? _pollQueue;

  @override
  void dispose() {
    _pollQueue?.cancel();
    super.dispose();
  }

  /// v14: tao queue convert nen full truyen (toi da 200 chuong/lan) roi
  /// poll 5s/lan cap nhat [queueProgressProvider]. Chuong nao xong nghe
  /// ngay qua player nhu cu (audio da co san trong proxy).
  Future<void> _taiFullTruyenNen(ParseResult result) async {
    if (_dangTaoQueue || result.storyUrl.isEmpty) return;
    setState(() => _dangTaoQueue = true);
    try {
      final queue = ref.read(queueClientProvider);
      // Convert tu trang hien tai den het (toi da 200 chuong/lan — truyen
      // 1k chuong user bam tiep de tai dot sau).
      final tao = await queue.taoQueue(
        result.storyUrl,
        fromPage: result.hasPaging ? result.page : 1,
        toPage: result.hasPaging ? result.maxPage : 1,
        limit: 200,
      );
      ref.read(queueIdProvider.notifier).state = tao.queueId;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã gửi ${tao.total} chương vào hàng đợi nền. '
            'Chương nào xong nghe ngay.',
          ),
        ),
      );
      _pollQueue?.cancel();
      _pollQueue = Timer.periodic(
        Duration(seconds: const QueueProgress(
          queueId: '',
          status: '',
          done: 0,
          total: 0,
          chuongXong: [],
          hong: [],
        ).pollSeconds),
        (_) => _pollMotLan(tao.queueId),
      );
      await _pollMotLan(tao.queueId);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tạo được hàng đợi: ${e.message ?? e.type.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tạo được hàng đợi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _dangTaoQueue = false);
    }
  }

  /// v14: poll 1 lan tien do queue; xong thi dung timer.
  Future<void> _pollMotLan(String queueId) async {
    try {
      final progress =
          await ref.read(queueClientProvider).layTienDo(queueId);
      ref.read(queueProgressProvider.notifier).state = progress;
      if (progress.hoanTat) {
        _pollQueue?.cancel();
        if (mounted) {
          final hong = progress.hong;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hong.isEmpty
                    ? 'Tải nền xong ${progress.done}/${progress.total} chương.'
                    : 'Tải nền xong ${progress.done}/${progress.total} chương '
                        '(${hong.length} chương lỗi, chạm để thử lại từng chương).',
              ),
            ),
          );
        }
      }
    } catch (_) {
      // Poll hong 1 lan -> bo qua, lan sau poll tiep (khong pha UI).
    }
  }

  Future<void> _chuyenTrang(int page) async {
    final result = ref.read(parseResultProvider);
    if (result == null || !result.hasPaging) return;
    final target = page.clamp(1, result.maxPage);
    if (target == result.page || _loadingPages.contains(target)) return;
    if (result.storyUrl.isEmpty) return;

    setState(() => _loadingPages.add(target));
    try {
      final client = ref.read(parseClientProvider);
      final next = await client.fetchTocPage(result.storyUrl, page: target);
      ref.read(parseResultProvider.notifier).state =
          result.copyWithPage(next.chapters, next.page);
      _pageError = null;
    } on DioException catch (e) {
      _pageError = 'Khong tai duoc trang $target: ${e.message ?? e.type.name}';
    } catch (e) {
      _pageError = 'Khong tai duoc trang $target: $e';
    } finally {
      if (mounted) setState(() => _loadingPages.remove(target));
    }
    if (_pageError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pageError!)),
      );
    }
  }

  /// Prefetch trang ke khi ranh (khong block UI, loi thi bo qua am tham).
  Future<void> _prefetchTrangKe(ParseResult result) async {
    final next = result.page + 1;
    if (!result.hasPaging ||
        next > result.maxPage ||
        result.storyUrl.isEmpty ||
        _prefetchedFor == result.page ||
        _loadingPages.contains(next)) {
      return;
    }
    _prefetchedFor = result.page;
    try {
      // Chi prefetch am tham — khong doi trang hien tai.
      await ref.read(parseClientProvider).fetchTocPage(
            result.storyUrl,
            page: next,
          );
    } catch (_) {
      // Bo qua: user bam sang se tai lai co hien thi loi ro rang.
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(parseResultProvider);

    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Danh sách chương')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chưa có dữ liệu. Hãy dán link trước.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Về trang chủ'),
              ),
            ],
          ),
        ),
      );
    }

    final progress = ref.watch(synthProgressProvider);
    final currentIndex = ref.watch(currentChapterIndexProvider);

    // v9: prefetch trang ke sau frame dau (khong block UI).
    if (result.hasPaging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefetchTrangKe(result);
      });
    }

    // v7 TOC: hien tong so lay tu proxy (co the nhieu tram chuong).
    // v9 phan trang: AppBar hien tong uoc luong + trang hien tai.
    final title = result.hasPaging
        ? 'Khoảng ${result.totalEstimate} chương (trang ${result.page}/${result.maxPage})'
        : '${result.chapters.length} chương';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: result.chapters.isNotEmpty && result.chapters.first.hasUrl
            ? const PreferredSize(
                preferredSize: Size.fromHeight(20),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Mở chương để tải nội dung rồi nghe',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              )
            : null,
        leading: IconButton(
          tooltip: 'Đổi truyện',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          // v14: nut tai full truyen nen (queue toi da 200 chuong/lan,
          // poll 5s/lan). Disable khi dang tao hoac chua co storyUrl.
          IconButton(
            tooltip: 'Tải full truyện nền',
            icon: _dangTaoQueue
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            onPressed: (_dangTaoQueue || result.storyUrl.isEmpty)
                ? null
                : () => _taiFullTruyenNen(result),
          ),
          IconButton(
            tooltip: 'Nghe từ đầu',
            icon: const Icon(Icons.playlist_play),
            onPressed: () => _openPlayer(context, ref, 0),
          ),
        ],
      ),
      body: Column(
        children: [
          // v14: thanh progress tong cua queue nen (x/total chuong).
          // Hien ngay khi co queue, an khi xong. Chuong nao xong nghe
          // ngay (audio san trong proxy, player tai nhu cu).
          _QueueProgressBar(),
          if (result.hasPaging) _PhanTrangBar(
            page: result.page,
            maxPage: result.maxPage,
            loadingPages: _loadingPages,
            onChuyenTrang: _chuyenTrang,
          ),
          Expanded(
            child: _loadingPages.contains(result.page)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          'Đang tải trang ${result.page}/${result.maxPage}...',
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: result.chapters.length,
                    // Pre-allocate de khong vo layout khi progress bar xuat hien giua chung.
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ChapterInfo chapter = result.chapters[index];
                      final double? pct = progress[index];
                      final bool isCurrent = currentIndex == index;
                      // Null-safe: chi ve progress bar khi co gia tri 0.0-1.0 that.
                      final double? busyPct =
                          (pct != null && pct >= 0 && pct < 1) ? pct : null;
                      return Semantics(
                        button: true,
                        selected: isCurrent,
                        label:
                            'Chương ${index + 1}: ${chapter.title}'
                            '${chapter.length > 0 ? ', ${chapter.length} ký tự' : ', chưa tải nội dung'}'
                            '${busyPct != null ? ', đang tạo audio ${(busyPct * 100).toStringAsFixed(0)} phần trăm' : ''}',
                        child: ListTile(
                          selected: isCurrent,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(
                            chapter.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Giua subtitle cho progress: tranh nhay layout (CLS) khi
                          // progress bar xuat hien/giua cac cap nhat.
                          // v7 TOC: len=0 (chua fetch noi dung) -> hien goi y thay vi "0 ky tu".
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chapter.length > 0
                                    ? '${chapter.length} ký tự'
                                    : 'Chạm để tải nội dung',
                              ),
                              SizedBox(
                                height: 6,
                                child: busyPct != null
                                    ? LinearProgressIndicator(value: busyPct)
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                          trailing: pct != null && pct < 0
                              ? Icon(
                                  Icons.error_outline,
                                  color: Theme.of(context).colorScheme.error,
                                  semanticLabel: 'Tạo audio thất bại',
                                )
                              : Icon(
                                  isCurrent
                                      ? Icons.play_circle
                                      : Icons.play_circle_fill,
                                  semanticLabel:
                                      isCurrent ? 'Đang phát' : 'Phát từ chương này',
                                ),
                          onTap: () => _openPlayer(context, ref, index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openPlayer(BuildContext context, WidgetRef ref, int index) {
    ref.read(currentChapterIndexProvider.notifier).state = index;
    context.go('/player');
  }
}

/// v14: thanh progress tong cua queue convert nen (audit ui-ux-pro-max:
/// multi-step flow phai hien step + progress + ETA).
///
/// - Chua co queue ([queueProgressProvider] null) -> an (SizedBox.shrink,
///   khong gay nhay layout).
/// - Dang chay: `Đã tải nền x/total chương` + LinearProgressIndicator +
///   so chuong loi (neu co).
/// - Xong: hien 1 dong xac nhan xanh (an sau khi user doi truyen).
class _QueueProgressBar extends ConsumerWidget {
  const _QueueProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(queueProgressProvider);
    if (progress == null) return const SizedBox.shrink();
    final pct = progress.tiLe;
    final pctLabel = (pct * 100).toStringAsFixed(0);
    return Semantics(
      label: 'Tiến độ tải nền: ${progress.done} trên ${progress.total} chương',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: progress.hoanTat
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  progress.hoanTat
                      ? Icons.check_circle_outline
                      : Icons.cloud_download_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.hoanTat
                        ? 'Tải nền xong ${progress.done}/${progress.total} chương'
                        : 'Đang tải nền ${progress.done}/${progress.total} chương ($pctLabel%)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (progress.hong.isNotEmpty)
                  Text(
                    '${progress.hong.length} lỗi',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Giu chieu cao co dinh de khong nhay layout khi % doi.
            SizedBox(
              height: 6,
              child: progress.hoanTat
                  ? const SizedBox.shrink()
                  : LinearProgressIndicator(value: pct),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thanh phan trang TOC (v9): << 1 ... N >> theo kieu web.
///
/// Hien toi da 5 nut so quanh trang hien tai (1 ... p-1 p p+1 ... max),
/// kem nut Dau/Cuoi. Trang dang tai hien spinner thay so.
class _PhanTrangBar extends StatelessWidget {
  const _PhanTrangBar({
    required this.page,
    required this.maxPage,
    required this.loadingPages,
    required this.onChuyenTrang,
  });

  final int page;
  final int maxPage;
  final Set<int> loadingPages;
  final ValueChanged<int> onChuyenTrang;

  /// Danh sach nut: so trang hoac -1 (= dau "...").
  List<int> _nutHienThi() {
    if (maxPage <= 7) return List<int>.generate(maxPage, (i) => i + 1);
    final out = <int>[1];
    if (page > 3) out.add(-1);
    for (var p = page - 1; p <= page + 1; p++) {
      if (p > 1 && p < maxPage) out.add(p);
    }
    if (page < maxPage - 2) out.add(-1);
    out.add(maxPage);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Phân trang mục lục, trang $page trên $maxPage',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Trang đầu',
              icon: const Icon(Icons.first_page),
              onPressed: page > 1 ? () => onChuyenTrang(1) : null,
            ),
            IconButton(
              tooltip: 'Trang trước',
              icon: const Icon(Icons.chevron_left),
              onPressed: page > 1 ? () => onChuyenTrang(page - 1) : null,
            ),
            for (final p in _nutHienThi())
              if (p == -1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Text('...'),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: loadingPages.contains(p)
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : ChoiceChip(
                          label: Text('$p'),
                          selected: p == page,
                          onSelected: p == page ? null : (_) => onChuyenTrang(p),
                        ),
                ),
            IconButton(
              tooltip: 'Trang sau',
              icon: const Icon(Icons.chevron_right),
              onPressed: page < maxPage ? () => onChuyenTrang(page + 1) : null,
            ),
            IconButton(
              tooltip: 'Trang cuối',
              icon: const Icon(Icons.last_page),
              onPressed: page < maxPage ? () => onChuyenTrang(maxPage) : null,
            ),
          ],
        ),
      ),
    );
  }
}
