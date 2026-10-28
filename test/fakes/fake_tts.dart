import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/parse/parse_client.dart';
import 'package:truyen_audio_app/src/core/tts/tts_provider.dart';

/// Fake TTS provider dieu khien duoc thanh/bai, KHONG goi mang that.
class FakeTtsProvider implements TtsProvider {
  FakeTtsProvider(
    this._name, {
    this.bytes,
    this.failWith,
    List<VoiceInfo>? voices,
  }) : voices = voices ?? const [];

  final String _name;

  /// Bytes tra ve khi thanh cong (mac dinh la MP3 'ID3').
  Uint8List? bytes;

  /// Neu khac null: synthesize se throw gia tri nay.
  Object? failWith;

  /// Danh sach giong cho listVoices.
  List<VoiceInfo> voices;

  int synthesizeCalls = 0;
  int listVoicesCalls = 0;
  String? lastText;
  String? lastVoice;
  double? lastSpeed;

  @override
  String get name => _name;

  @override
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false}) async {
    listVoicesCalls++;
    if (failWith != null && voices.isEmpty) throw failWith!;
    return voices;
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    synthesizeCalls++;
    lastText = text;
    lastVoice = voice;
    lastSpeed = speed;
    if (failWith != null) throw failWith!;
    onProgress?.call(1.0);
    return bytes ?? Uint8List.fromList(const [0x49, 0x44, 0x33, 0x01, 0x02]);
  }
}

/// Bytes WAV hop le (magic RIFF....WAVE) de test nhan dang 'wav'.
Uint8List fakeWavBytes() {
  final b = Uint8List(16);
  b[0] = 0x52; // R
  b[1] = 0x49; // I
  b[2] = 0x46; // F
  b[3] = 0x46; // F
  b[8] = 0x57; // W
  b[9] = 0x41; // A
  b[10] = 0x56; // V
  b[11] = 0x45; // E
  return b;
}

/// Tao ParseClient voi Dio stub, KHONG goi mang that.
///
/// [chapters]/[texts]: du lieu tra ve cho POST /parse.
/// [paged]: neu khac null, stub hieu che do phan trang v9 — tra [paged] cho
/// GET /toc (theo ?page=) va giu nguyen [chapters]/[texts] cho POST /parse.
/// [error]: neu khac null, moi request se reject voi DioException nay.
ParseClient makeStubParseClient({
  List<Map<String, dynamic>>? chapters,
  List<String>? texts,
  Map<int, Map<String, dynamic>>? paged,
  Object? error,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (error != null) {
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: error,
            ),
          );
        }
        // v9: GET /toc tra page tuong ung (?page=N).
        if (paged != null && options.path == '/toc') {
          final raw = options.queryParameters['page'];
          final n = int.tryParse(raw.toString()) ?? 1;
          final pageJson = paged[n] ?? paged[1]!;
          return handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: pageJson,
            ),
          );
        }
        return handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            // v9: POST /parse dau tien cung tra page 1 co metadata phan trang.
            data: paged?[1] ??
                {
                  'chapters': chapters ??
                      const [
                        {'title': 'Chương 1: Khởi đầu', 'len': 120},
                        {'title': 'Chương 2: Lên đường', 'len': 340},
                        {'title': 'Chương 3: Hồi kết', 'len': 210},
                      ],
                  'texts': texts ??
                      const [
                        'Nội dung chương một. Kể về khởi đầu.',
                        'Nội dung chương hai. Cuộc hành trình tiếp diễn.',
                        'Nội dung chương ba. Hồi kết của câu chuyện.',
                      ],
                },
          ),
        );
      },
    ),
  );
  return ParseClient(dio: dio);
}

/// Ket qua parse mau 3 chuong cho widget test.
ParseResult makeSampleParseResult() {
  return const ParseResult(
    chapters: [
      ChapterInfo(title: 'Chương 1: Khởi đầu', length: 120),
      ChapterInfo(title: 'Chương 2: Lên đường', length: 340),
      ChapterInfo(title: 'Chương 3: Hồi kết', length: 210),
    ],
    texts: [
      'Nội dung chương một. Kể về khởi đầu.',
      'Nội dung chương hai. Cuộc hành trình tiếp diễn.',
      'Nội dung chương ba. Hồi kết của câu chuyện.',
    ],
  );
}

/// Tao Dio stub tong quat cho provider test (dem request, tra bytes tuy y).
Dio makeStubProviderDio({
  required List<int> responseBody,
  void Function(RequestOptions options)? onRequest,
  int statusCode = 200,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        return handler.resolve(
          Response<List<int>>(
            requestOptions: options,
            statusCode: statusCode,
            data: responseBody,
          ),
        );
      },
    ),
  );
  return dio;
}
