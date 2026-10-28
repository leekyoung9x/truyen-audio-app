import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../network/dio_client.dart';

/// Tien do 1 queue convert nen (tu `GET /queue/{id}`).
@immutable
class QueueProgress {
  const QueueProgress({
    required this.queueId,
    required this.status,
    required this.done,
    required this.total,
    required this.chuongXong,
    required this.hong,
    this.pollSeconds = 5,
  });

  final String queueId;
  final String status;
  final int done;
  final int total;
  final List<String> chuongXong;
  final List<String> hong;
  final int pollSeconds;

  bool get hoanTat => status == 'done';
  double get tiLe => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  factory QueueProgress.fromJson(Map<String, dynamic> json) {
    List<String> asStrings(Object? v) => v is List
        ? v.map((e) => e.toString()).toList()
        : const <String>[];
    int asInt(Object? v) =>
        (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
    return QueueProgress(
      queueId: (json['queue_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      done: asInt(json['done']),
      total: asInt(json['total']),
      chuongXong: asStrings(json['chuong_xong']),
      hong: asStrings(json['hong']),
      pollSeconds: asInt(json['poll_seconds']) == 0
          ? 5
          : asInt(json['poll_seconds']),
    );
  }
}

/// Client goi queue convert nen full truyen (v14).
///
/// - `taoQueue(storyUrl, fromPage, toPage, {limit})` -> queue_id + total.
/// - `layTienDo(queueId)` -> [QueueProgress] (app poll 5s/lan).
/// - `taiAudioChuong(queueId, chapterUrl)` -> bytes MP3 chuong da xong
///   (chuong nao xong nghe ngay, khong doi ca queue).
class QueueClient {
  QueueClient({Dio? dio})
    : _dio = dio ??
          createDioClient(
            baseUrl: kIsWeb ? webProxyBaseUrl : '$kokoroBaseUrl/api',
            // Tao queue chi fetch TOC (nhanh); poll nhe. Timeout ngan.
            timeoutSeconds: ApiTimeouts.vieneuParse,
          );

  final Dio _dio;

  Future<({String queueId, int total})> taoQueue(
    String storyUrl, {
    int fromPage = 1,
    int toPage = 1,
    int limit = 200,
    CancelToken? cancelToken,
  }) async {
    final trimmed = storyUrl.trim();
    if (trimmed.isEmpty) throw ArgumentError('URL truyen khong duoc rong.');
    final res = await _dio.post<Map<String, dynamic>>(
      '/queue',
      data: {
        'story_url': trimmed,
        'from_page': fromPage,
        'to_page': toPage,
        'limit': limit,
      },
      cancelToken: cancelToken,
    );
    final data = res.data ?? const {};
    final qid = (data['queue_id'] ?? '').toString();
    if (qid.isEmpty) {
      throw StateError(
        'Khong tao duoc queue: ${(data['error'] ?? 'loi khong ro').toString()}',
      );
    }
    final total = (data['total'] is num)
        ? (data['total'] as num).toInt()
        : int.tryParse(data['total'].toString()) ?? 0;
    return (queueId: qid, total: total);
  }

  Future<QueueProgress> layTienDo(
    String queueId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/queue/$queueId',
      cancelToken: cancelToken,
    );
    return QueueProgress.fromJson(res.data ?? const <String, dynamic>{});
  }
}
