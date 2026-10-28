import 'package:dio/dio.dart';

/// Tao 1 [Dio] cho 1 host.
///
/// Moi host (Vieneu/Kokoro) giu 1 instance duy nhat de tai su dung
/// connection pool. Huy request: caller tao [CancelToken] rieng cho moi
/// request va truyen vao `cancelToken:` cua `dio.get/post` (Dio truyen
/// token theo-request, khong giu o client).
Dio createDioClient({
  required String baseUrl,
  required int timeoutSeconds,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: Duration(seconds: timeoutSeconds),
      receiveTimeout: Duration(seconds: timeoutSeconds),
      sendTimeout: Duration(seconds: timeoutSeconds),
      headers: const {'Content-Type': 'application/json'},
      // Mac dinh chi chap nhan 2xx; loi se nem DioException.
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );
  return dio;
}
