// Unit + widget test phan trang TOC (v9) — KHONG goi mang that.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/parse/parse_client.dart';
import 'package:truyen_audio_app/src/features/app_providers.dart';

import 'fakes/fake_audio_cache.dart';
import 'fakes/test_app.dart';

/// Du lieu 2 page TOC gia lap (moi page 2 chuong, max_page=2).
Map<int, Map<String, dynamic>> _pagedToc() => {
      1: {
        'chapters': [
          {'title': 'Chương 1', 'len': 0, 'url': 'https://x/c1'},
          {'title': 'Chương 2', 'len': 0, 'url': 'https://x/c2'},
        ],
        'texts': [],
        'total': 400,
        'total_estimate': 400,
        'page': 1,
        'max_page': 2,
        'rid': '999',
        'story_url': 'https://truyen.example.com/truyen-hay',
      },
      2: {
        'chapters': [
          {'title': 'Chương 3', 'len': 0, 'url': 'https://x/c3'},
          {'title': 'Chương 4', 'len': 0, 'url': 'https://x/c4'},
        ],
        'texts': [],
        'total': 400,
        'total_estimate': 400,
        'page': 2,
        'max_page': 2,
        'rid': '999',
        'story_url': 'https://truyen.example.com/truyen-hay',
      },
    };

void main() {
  group('parse_result_phan_trang_v9', () {
    test('from_json_doc_du_metadata_page', () {
      final r = ParseResult.fromJson(_pagedToc()[1]!);
      expect(r.chapters.length, 2);
      expect(r.page, 1);
      expect(r.maxPage, 2);
      expect(r.totalEstimate, 400);
      expect(r.rid, '999');
      expect(r.hasPaging, isTrue);
    });

    test('from_json_kieu_cu_default_1_trang', () {
      const r = ParseResult(chapters: [], texts: []);
      expect(r.page, 1);
      expect(r.maxPage, 1);
      expect(r.hasPaging, isFalse);
      expect(r.storyUrl, isEmpty);
    });

    test('copy_with_page_giu_metadata_doi_chapters', () {
      final r = ParseResult.fromJson(_pagedToc()[1]!);
      final p2 = ParseResult.fromJson(_pagedToc()[2]!);
      final next = r.copyWithPage(p2.chapters, p2.page);
      expect(next.page, 2);
      expect(next.maxPage, 2);
      expect(next.chapters.first.title, 'Chương 3');
      expect(next.texts, isEmpty);
    });
  });

  group('fetch_toc_page_stub', () {
    test('fetch_toc_page_gui_dung_page_va_tra_page_do', () async {
      int? seenPage;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seenPage = int.tryParse(
              (options.queryParameters['page'] ?? '1').toString(),
            );
            return handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: _pagedToc()[seenPage ?? 1]!,
              ),
            );
          },
        ),
      );
      final client = ParseClient(dio: dio);
      final p2 = await client.fetchTocPage(
        'https://truyen.example.com/truyen-hay',
        page: 2,
      );
      expect(seenPage, 2);
      expect(p2.page, 2);
      expect(p2.chapters.first.title, 'Chương 3');
    });

    test('fetch_toc_page_tu_choi_scheme_la', () {
      final client =
          ParseClient(dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')));
      expect(
        () => client.fetchTocPage('file:///etc/passwd', page: 2),
        throwsArgumentError,
      );
    });
  });

  group('chapter_list_phan_trang_widget', () {
    testWidgets(
      'chapter_list_hien_thanh_phan_trang_va_chuyen_trang',
      (tester) async {
        final app = makeTestApp(
          cacheOverride: FakeAudioCache(),
          parseClient: makeStubParseClient(paged: _pagedToc()),
        );
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        // Cau chao phan trang: AppBar hien tong uoc luong + trang 1/2.
        expect(find.textContaining('trang 1/2'), findsOneWidget);
        expect(find.byTooltip('Trang sau'), findsOneWidget);

        // Bam sang trang 2 -> list doi sang chuong 3/4, AppBar cap nhat.
        await tester.tap(find.byTooltip('Trang sau'));
        await tester.pumpAndSettle();
        expect(find.text('Chương 3'), findsOneWidget);
        expect(find.textContaining('trang 2/2'), findsOneWidget);
        expect(
          app.container.read(parseResultProvider)?.page,
          2,
        );
      },
    );

    testWidgets(
      'chapter_list_kieu_cu_khong_hien_phan_trang',
      (tester) async {
        final app = makeTestApp(cacheOverride: FakeAudioCache());
        await pumpRealApp(tester, app);
        addTearDown(app.handler.dispose);

        await tester.enterText(
          find.byType(TextFormField),
          'https://truyen.example.com/truyen-hay',
        );
        await tester.tap(find.text('Tách chương'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Trang sau'), findsNothing);
        expect(find.text('3 chương'), findsOneWidget);
      },
    );
  });
}
