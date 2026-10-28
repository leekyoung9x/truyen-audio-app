import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Dinh danh 1 giong doc cua bat ky provider nao.
@immutable
class VoiceInfo {
  const VoiceInfo({required this.id, required this.label});

  /// Id gui len server trong body /tts (vd: 'Trúc Ly', 'diem_trinh').
  final String id;

  /// Chuoi hien thi tren UI (co the kem mo ta vung mien/phong cach).
  final String label;

  factory VoiceInfo.fromJson(Map<String, dynamic> json) {
    return VoiceInfo(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? json['id'] ?? '').toString(),
    );
  }
}

/// Hop dong chung cho moi TTS provider.
///
/// [synthesize] tra ve bytes am thanh hoan chinh cua [text]:
/// - Vieneu: 1 request -> file WAV 48kHz.
/// - Kokoro: tu cat chunk trong provider roi noi bytes lai -> MP3.
abstract class TtsProvider {
  /// Ten hien thi (vd: 'Vieneu', 'Kokoro').
  String get name;

  /// Lay danh sach giong doc tu `GET /voices`.
  Future<List<VoiceInfo>> listVoices({bool forceRefresh = false});

  /// Tong hop [text] thanh audio bytes.
  ///
  /// [voice]: id giong doc cua provider nay.
  /// [speed]: toc do doc (Kokoro ho tro 0.5-1.5; Vieneu giu 1.0).
  /// [onProgress]: tien do 0.0-1.0 (Kokoro bao cao theo chunk).
  /// [cancelToken]: huy request dang bay (vd: user doi chuong giua chung).
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    double speed = 1.0,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });
}
