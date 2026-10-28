import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_providers.dart';

/// Man hinh chinh: nhap URL (hoac paste text) -> parse -> qua man hinh chuong.
class PasteLinkScreen extends ConsumerStatefulWidget {
  const PasteLinkScreen({super.key});

  @override
  ConsumerState<PasteLinkScreen> createState() => _PasteLinkScreenState();
}

class _PasteLinkScreenState extends ConsumerState<PasteLinkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _isTextMode = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    ref.read(parsingProvider.notifier).state = true;
    ref.read(parseErrorProvider.notifier).state = null;
    try {
      final client = ref.read(parseClientProvider);
      final input = _urlController.text;
      final result = _isTextMode
          ? await client.parseText(input)
          : await client.parseUrl(input);
      if (result.chapters.isEmpty) {
        ref.read(parseErrorProvider.notifier).state =
            'Khong tim thay chuong nao. Hay kiem tra lai link/noi dung.';
        return;
      }
      ref.read(storyUrlProvider.notifier).state = _isTextMode ? '' : input.trim();
      ref.read(parseResultProvider.notifier).state = result;
      if (mounted) context.go('/chapters');
    } on DioException catch (e) {
      ref.read(parseErrorProvider.notifier).state =
          'Loi mang khi parse: ${e.message ?? e.type.name}';
    } catch (e) {
      ref.read(parseErrorProvider.notifier).state = 'Parse that bai: $e';
    } finally {
      ref.read(parsingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsing = ref.watch(parsingProvider);
    final parseError = ref.watch(parseErrorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Truyện Audio'),
        actions: [
          IconButton(
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon trang tri: an khoi cay semantics (trahn doc man hinh
                  // doc thua ben canh title da ro nghia).
                  Icon(
                    Icons.menu_book_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                    semanticLabel: null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Dán link truyện để nghe',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'App sẽ tách danh sách chương, chuyển thành audio '
                    'và phát cả khi chạy nền.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    label: 'Chọn chế độ nhập',
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Link truyện')),
                        ButtonSegment(value: true, label: Text('Dán text')),
                      ],
                      selected: {_isTextMode},
                      onSelectionChanged: (set) =>
                          setState(() => _isTextMode = set.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _urlController,
                    minLines: _isTextMode ? 6 : 1,
                    maxLines: _isTextMode ? 10 : 1,
                    keyboardType: _isTextMode
                        ? TextInputType.multiline
                        : TextInputType.url,
                    // Goi y trinh duyet tu dien URL (chi o che do link).
                    autofillHints:
                        _isTextMode ? null : const [AutofillHints.url],
                    decoration: InputDecoration(
                      labelText: _isTextMode
                          ? 'Nội dung truyện (có "Chương 1", "Chương 2"... )'
                          : 'URL trang truyện',
                      hintText: _isTextMode
                          ? 'Chương 1: ...\n\nChương 2: ...'
                          : 'https://...',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        _isTextMode ? Icons.article_outlined : Icons.link,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập ${_isTextMode ? 'nội dung' : 'URL'} truyện.';
                      }
                      if (!_isTextMode) {
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null || !uri.hasScheme) {
                          return 'URL chưa hợp lệ (thiếu http/https).';
                        }
                      }
                      return null;
                    },
                    // Bao loi len screen-reader ngay khi xuat hien.
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  if (parseError != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: _ErrorCard(message: parseError),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: parsing ? null : _parse,
                    icon: parsing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_stories),
                    label: Text(parsing ? 'Đang tải trang 1...' : 'Tách chương'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }}
