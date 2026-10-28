import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../network/dio_client.dart';

/// 1 chuong sau khi parse.
///
/// v7: proxy co the chi tra TOC (title + url, chua fetch noi dung) —
/// [url] la link chuong tuyet doi (rong neu parse kieu cu khong co url),
/// [length] = 0 khi chua biet do dai that.
@immutable
class ChapterInfo {
  const ChapterInfo({required this.title, required this.length, this.url = ''});

  final String title;
  final int length;

  /// URL tuyet doi cua chuong (v7 TOC); '' neu khong co.
  final String url;

  /// Chuong nay da co text san trong [ParseResult.texts] hay can lazy-fetch.
  bool get hasUrl => url.isNotEmpty;

  factory ChapterInfo.fromJson(Map<String, dynamic> json) {
    return ChapterInfo(
      title: (json['title'] ?? '').toString(),
      length: (json['len'] as num? ?? 0).toInt(),
      url: (json['url'] ?? '').toString(),
    );
  }
}

/// Ket qua `POST /parse`: danh sach chuong + noi dung text tung chuong.
///
/// - Parse kieu cu (text / chuong don): `{"chapters":[{"title","len"}],
///   "texts":[...]}` — `texts[i]` la noi dung cua `chapters[i]`.
/// - Parse v7 (url trang truyen): `{"chapters":[{"title","url","len":0}],
///   "total":N, "texts":[]}` — chi co TOC, app lazy-fetch tung chuong khi
///   mo player qua [fetchMissingText].
@immutable
class ParseResult {
  const ParseResult({
    required this.chapters,
    required this.texts,
    this.page = 1,
    this.maxPage = 1,
    this.totalEstimate = 0,
    this.rid = '',
    this.storyUrl = '',
  });

  final List<ChapterInfo> chapters;
  final List<String> texts;

  /// Trang muc luc hien tai (v9, default 1 = kieu cu / chua phan trang).
  final int page;

  /// Tong so trang muc luc (v9; 1 = chi 1 trang).
  final int maxPage;

  /// Uoc luong tong so chuong toan truyen (v9; 0 = chua biet).
  final int totalEstimate;

  /// Book id cho AJAX phan trang (v9; '' = truyen 1 trang / kieu cu).
  final String rid;

  /// URL trang truyen (v9; '' = parse text/chuong don).
  final String storyUrl;

  /// Co phan trang TOC khong (v9).
  bool get hasPaging => maxPage > 1;

  factory ParseResult.fromJson(Map<String, dynamic> json) {
    final rawChapters = json['chapters'];
    final chapters = rawChapters is List
        ? rawChapters.whereType<Map<String, dynamic>>().map(ChapterInfo.fromJson).toList()
        : const <ChapterInfo>[];
    final rawTexts = json['texts'];
    final texts = rawTexts is List
        ? rawTexts.map((e) => e.toString()).toList()
        : const <String>[];
    int asInt(Object? v, int fallback) =>
        (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? fallback;
    return ParseResult(
      chapters: chapters,
      texts: texts,
      page: asInt(json['page'], 1),
      maxPage: asInt(json['max_page'] ?? json['maxPage'], 1),
      totalEstimate: asInt(
        json['total_estimate'] ?? json['totalEstimate'] ?? json['total'],
        chapters.length,
      ),
      rid: (json['rid'] ?? '').toString(),
      storyUrl: (json['story_url'] ?? json['storyUrl'] ?? '').toString(),
    );
  }

  /// Lay text cua chuong thu [index] (null neu ngoai pham vi).
  String? textOf(int index) =>
      (index >= 0 && index < texts.length) ? texts[index] : null;

  /// Copy voi texts thay doi (dung sau khi lazy-fetch them chuong).
  ParseResult copyWithTexts(List<String> texts) => ParseResult(
        chapters: chapters,
        texts: texts,
        page: page,
        maxPage: maxPage,
        totalEstimate: totalEstimate,
        rid: rid,
        storyUrl: storyUrl,
      );

  /// Copy voi page muc luc moi (v9: giu metadata phan trang, doi chapters).
  ParseResult copyWithPage(List<ChapterInfo> chapters, int page) => ParseResult(
        chapters: chapters,
        texts: const [],
        page: page,
        maxPage: maxPage,
        totalEstimate: totalEstimate,
        rid: rid,
        storyUrl: storyUrl,
      );
}

/// Client goi `POST /parse` tren Vieneu server voi `{url}` hoac `{text}`.
///
/// Web (v6): baseUrl la proxy cung origin (`/api`) de tranh mixed-content
/// + CORS preflight tu page HTTPS. Native: goi thang server that.
class ParseClient {
  ParseClient({Dio? dio})
    : _dio = dio ?? createDioClient(
        baseUrl: kIsWeb ? webProxyBaseUrl : vieneuBaseUrl,
        timeoutSeconds: ApiTimeouts.vieneuParse,
      );

  final Dio _dio;

  /// Parse truyen tu URL do user paste.
  ///
  /// Chi chap nhan URL http/https (guard chong SSRF tu client: khong gui
  /// file://, content:// hay scheme la len server parse).
  /// [cancelToken] de huy request dang bay (vd: user roi man hinh).
  Future<ParseResult> parseUrl(String url, {CancelToken? cancelToken}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL truyen khong duoc rong.');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('URL truyen phai bat dau bang http:// hoac https://.');
    }
    return _post({'url': trimmed}, cancelToken: cancelToken);
  }

  /// Parse doan text do user paste truc tiep.
  Future<ParseResult> parseText(String text, {CancelToken? cancelToken}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Noi dung truyen khong duoc rong.');
    return _post({'text': trimmed}, cancelToken: cancelToken);
  }

  Future<ParseResult> _post(
    Map<String, String> body, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/parse',
      data: body,
      cancelToken: cancelToken,
    );
    return ParseResult.fromJson(res.data ?? const <String, dynamic>{});
  }

  /// Tai 1 trang muc luc (v9 phan trang).
  ///
  /// [storyUrl] la URL trang truyen (lay tu [ParseResult.storyUrl] lan parse
  /// dau). [page] >= 1, qua [ParseResult.maxPage] thi proxy clamp ve max.
  /// Dung GET /toc cho nhe (tuong duong POST /parse {url, page}).
  Future<ParseResult> fetchTocPage(
    String storyUrl, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final trimmed = storyUrl.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL truyen khong duoc rong.');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('URL truyen phai bat dau bang http:// hoac https://.');
    }
    final res = await _dio.get<Map<String, dynamic>>(
      '/toc',
      queryParameters: {'url': trimmed, 'page': '$page'},
      cancelToken: cancelToken,
    );
    return ParseResult.fromJson(res.data ?? const <String, dynamic>{});
  }

  /// Tai noi dung 1 chuong tu [chapterUrl] (v7 TOC lazy-fetch).
  ///
  /// Proxy forward sang 8001 (parse noi dung chuong don — van tot) va tra
  /// `texts[0]`. [cancelToken] de huy khi user roi man hinh doi.
  Future<String> fetchChapterText(
    String chapterUrl, {
    CancelToken? cancelToken,
  }) async {
    final trimmed = chapterUrl.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL chuong khong duoc rong.');
    final res = await _dio.post<Map<String, dynamic>>(
      '/parse',
      data: {'url': trimmed},
      cancelToken: cancelToken,
    );
    final result = ParseResult.fromJson(res.data ?? const <String, dynamic>{});
    final text = result.textOf(0);
    if (text == null || text.trim().isEmpty) {
      throw StateError('Khong tai duoc noi dung chuong.');
    }
    return text;
  }
}
