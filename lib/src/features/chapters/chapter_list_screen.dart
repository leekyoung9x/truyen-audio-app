import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
          IconButton(
            tooltip: 'Nghe từ đầu',
            icon: const Icon(Icons.playlist_play),
            onPressed: () => _openPlayer(context, ref, 0),
          ),
        ],
      ),
      body: Column(
        children: [
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
