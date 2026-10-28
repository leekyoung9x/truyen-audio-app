import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truyen_audio_app/src/core/convert/queue_client.dart';

/// v14 TDD: boc sach noi dung + queue progress (RED truoc, GREEN sau).
///
/// - Text ban (menu DANH SACH / THE LOAI / nut Chuong truoc-tiep / Tai
///   Ebook) phai duoc loai o proxy (`_sach_noi_dung_chuong`,
///   `server/proxy_server.py`); app Dart chi can biet phan biet text sach
///   vs ban de test guard (khong goi server that o day).
/// - [QueueProgress.fromJson] phai parse dung tien do queue (done/total,
///   chuong_xong, hong, poll_seconds).

/// Mo phong text BAN kieu 8001 cu (ca trang, co menu + nut).
String _textBan() => '''
Cẩu Tại Võ Đạo Thế Giới Thành Thánh (Trọn Bộ) - Chương 02: Khu nhà cũ

 DANH SÁCH

 Tiên Hiệp Kiếm Hiệp Ngôn Tình Đam Mỹ

 THỂ LOẠI

 Tiên Hiệp Kiếm Hiệp Ngôn Tình

Chương 02: Khu nhà cũ

Đẩy ra kẹt kẹt rung động cửa khoang.

《 Chương trước

Chương tiếp 》

Tải Ebook

Cài đặt giao diện
''';

/// Mo phong text SACH kieu proxy v14 (chi title + noi dung).
String _textSach() => '''
Chương 02: Khu nhà cũ

Đẩy ra kẹt kẹt rung động cửa khoang.

Chật chội trong khoang thuyền tràn ngập ẩm ướt đầu gỗ.
''';

/// Guard Dart-side: text con rac menu/nut khong (app co the canh bao
/// user neu proxy tra X-Clean: 0).
bool _conRac(String text) {
  const rac = [
    'DANH SÁCH',
    'THỂ LOẠI',
    'Chương trước',
    'Chương tiếp',
    'Tải Ebook',
    'Cài đặt giao diện',
  ];
  return rac.any(text.contains);
}

void main() {
  group('v14: text ban vs sach', () {
    test('text ban 8001 cu CON rac (baseline de so sanh)', () {
      expect(_conRac(_textBan()), isTrue);
    });

    test('text sach v14 KHONG con rac', () {
      final t = _textSach();
      expect(_conRac(t), isFalse);
      expect(t.contains('Chương 02'), isTrue);
      expect(t.contains('Đẩy ra kẹt kẹt'), isTrue);
    });

    test('text sach giu du title + noi dung, bo nut dieu huong', () {
      final t = _textSach();
      expect(t.contains('《'), isFalse);
      expect(t.contains('》'), isFalse);
      // Noi dung chinh van du (khong cat mat chu).
      expect(t.length, greaterThan(50));
    });
  });

  group('v14: QueueProgress.fromJson', () {
    test('parse dung tien do dang chay', () {
      final p = QueueProgress.fromJson({
        'queue_id': 'abc123',
        'status': 'running',
        'done': 3,
        'total': 5,
        'tien_do': 3,
        'chuong_xong': ['Chương 1', 'Chương 2', 'Chương 3'],
        'hong': [],
        'poll_seconds': 5,
      });
      expect(p.queueId, 'abc123');
      expect(p.status, 'running');
      expect(p.done, 3);
      expect(p.total, 5);
      expect(p.tiLe, closeTo(0.6, 0.001));
      expect(p.hoanTat, isFalse);
      expect(p.chuongXong, hasLength(3));
      expect(p.hong, isEmpty);
    });

    test('hoanTat khi status done', () {
      final p = QueueProgress.fromJson({
        'queue_id': 'abc123',
        'status': 'done',
        'done': 5,
        'total': 5,
        'chuong_xong': ['Chương 1'],
        'hong': ['Chương 4'],
        'poll_seconds': 5,
      });
      expect(p.hoanTat, isTrue);
      expect(p.tiLe, 1.0);
      expect(p.hong, ['Chương 4']);
    });

    test('total=0 khong chia cho 0', () {
      final p = QueueProgress.fromJson({
        'queue_id': 'x',
        'status': 'queued',
        'done': 0,
        'total': 0,
        'chuong_xong': [],
        'hong': [],
      });
      expect(p.tiLe, 0);
      expect(p.hoanTat, isFalse);
    });
  });

  group('v14: QueueClient guard (khong can server that)', () {
    test('taoQueue tu choi URL rong', () {
      final client = QueueClient(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9')),
      );
      expect(() => client.taoQueue('  '), throwsArgumentError);
    });

    test('layTienDo tra QueueProgress (mock Dio)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'queue_id': 'mock1',
                  'status': 'running',
                  'done': 1,
                  'total': 5,
                  'chuong_xong': ['Chương 1'],
                  'hong': [],
                  'poll_seconds': 5,
                },
              ),
            );
          },
        ),
      );
      final client = QueueClient(dio: dio);
      final p = await client.layTienDo('mock1');
      expect(p.done, 1);
      expect(p.total, 5);
      expect(p.tiLe, closeTo(0.2, 0.001));
    });
  });
}
