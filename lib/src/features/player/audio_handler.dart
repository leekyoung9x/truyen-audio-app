import 'dart:async';
import 'dart:io' show File;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show Uint8List, immutable, kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/config.dart';

/// Media item mo rong: giu duong dan file local (native) hoac bytes audio
/// (Web — vi Web khong co file that).
class ChapterMediaItem extends MediaItem {
  ChapterMediaItem({
    required super.id,
    required super.title,
    this.filePath,
    this.audioBytes,
    this.mimeType,
    super.album,
    super.artist,
    super.duration,
  }) : assert(
          filePath != null || audioBytes != null,
          'ChapterMediaItem can filePath (native) hoac audioBytes (Web).',
        );

  final String? filePath;

  /// Bytes audio day du — Web phat qua [AudioSource.uri] data: URI.
  final Uint8List? audioBytes;

  /// MIME cua audio ('audio/wav' | 'audio/mpeg') — dung cho data: URI tren Web.
  final String? mimeType;
}

/// Trang thai phat tong hop cho UI (gop tu just_audio + audio_service).
@immutable
class PlayerStateSnapshot {
  const PlayerStateSnapshot({
    required this.playing,
    required this.processingState,
    required this.position,
    required this.duration,
    required this.speed,
    required this.currentIndex,
    required this.queueLength,
  });

  final bool playing;
  final AudioProcessingState processingState;
  final Duration position;
  final Duration? duration;
  final double speed;
  final int? currentIndex;
  final int queueLength;
}

/// AudioHandler chay nen: playlist just_audio + audio_service.
///
/// - Phat lien tuc nhieu chuong (playlist tu file da cache).
/// - Toc do 0.5-1.5x, tua ±10s, hen gio ngu (sleep timer).
class StoryAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  StoryAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _init();
  }

  final AudioPlayer _player;
  Timer? _sleepTimer;
  bool _disposed = false;

  void _init() {
    // Dong bo playbackState tu just_audio sang audio_service (notification/lock screen).
    _player.playbackEventStream.listen((event) {
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (_player.playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: _toProcessingState(_player.processingState),
          playing: _player.playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _player.currentIndex,
        ),
      );
    });

    // Dong bo mediaItem hien tai theo index playlist.
    _player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= queue.value.length) {
        mediaItem.add(null);
      } else {
        mediaItem.add(queue.value[index]);
      }
    });

    // Stream tong hop cho UI.
    Rx.combineLatest4<bool, Duration, Duration?, double, PlayerStateSnapshot>(
      _player.playingStream,
      _player.positionStream,
      _player.durationStream,
      _player.speedStream,
      (playing, position, duration, speed) => PlayerStateSnapshot(
        playing: playing,
        processingState: _toProcessingState(_player.processingState),
        position: position,
        duration: duration,
        speed: speed,
        currentIndex: _player.currentIndex,
        queueLength: queue.value.length,
      ),
    ).listen(_snapshot.add);
  }

  final _snapshot = BehaviorSubject<PlayerStateSnapshot>.seeded(
    const PlayerStateSnapshot(
      playing: false,
      processingState: AudioProcessingState.idle,
      position: Duration.zero,
      duration: null,
      speed: 1.0,
      currentIndex: null,
      queueLength: 0,
    ),
  );

  /// Stream cho UI (thay cho nhieu stream rieng le cua just_audio).
  ValueStream<PlayerStateSnapshot> get snapshotStream => _snapshot;

  AudioProcessingState _toProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// Nap playlist tu danh sach chuong da cache (phat lien tuc).
  ///
  /// - Native: [ChapterMediaItem.filePath] phai ton tai that (just_audio
  ///   se throw neu path ao) -> kiem tra truoc khi nap.
  /// - Web: khong co file that -> phat tu [ChapterMediaItem.audioBytes].
  /// [startIndex] duoc clamp ve pham vi hop le.
  Future<void> loadPlaylist(List<ChapterMediaItem> items, {int startIndex = 0}) async {
    if (items.isEmpty) {
      throw ArgumentError('Playlist khong duoc rong.');
    }
    if (kIsWeb) {
      for (final item in items) {
        if (item.audioBytes == null || item.audioBytes!.isEmpty) {
          throw ArgumentError('Thieu audioBytes cho ${item.id} (Web).');
        }
      }
    } else {
      for (final item in items) {
        final path = item.filePath;
        if (path == null || !await File(path).exists()) {
          throw ArgumentError('File audio khong ton tai: $path');
        }
      }
    }
    // QueueHandler + just_audio deu duoc dong bo theo cung thu tu nay.
    queue.add(List<MediaItem>.unmodifiable(items));
    final sources = items.map((item) {
      if (kIsWeb) {
        // Web: phat bytes qua data: URI (khong co file that).
        return AudioSource.uri(
          Uri.dataFromBytes(item.audioBytes!, mimeType: _mimeFor(item)),
          tag: item,
        );
      }
      return AudioSource.file(item.filePath!, tag: item);
    }).toList();
    await _player
        .setAudioSource(
          ConcatenatingAudioSource(children: sources),
          initialIndex: startIndex.clamp(0, items.length - 1).toInt(),
        )
        // v10: Web treo o AudioSource.uri(data:) khong resolve (bytes co
        // nhung promise treo) -> timeout ro rang thay vi ket vinh vien.
        // v13: 1 tang duy nhat — [ApiTimeouts.flowShortChapter] (45s) thay
        // vi 30s cung (do that 2026-10-28: Kokoro 3000 chu mat 41s direct,
        // 30s kill oan). Caller (player_screen) boc them 1 lop + hien
        // controls ngay.
        .timeout(
          const Duration(seconds: ApiTimeouts.flowShortChapter),
          onTimeout: () => throw StateError(
            'Nạp audio quá ${ApiTimeouts.flowShortChapter} giây (Web: data: '
            'URI có thể quá lớn hoặc trình duyệt chặn). Hãy bấm Thử lại.',
          ),
        );
  }

  /// v12: prefetch nen chen chuong tiep vao playlist hien tai (cheap-append,
  /// KHONG nap lai tu dau — giu vi tri dang phat, khong giat audio).
  ///
  /// - Native: them file source vao [ConcatenatingAudioSource] hien tai.
  /// - Web: them data: URI source (bytes san trong memory).
  /// - [ChapterMediaItem.id] phai duy nhat trong playlist (vd 'chapter-2');
  ///   trung id -> nem [ArgumentError] de caller bo qua chuong do.
  Future<void> appendToPlaylist(ChapterMediaItem item) async {
    if (queue.value.any((m) => m.id == item.id)) {
      throw ArgumentError('Chuong ${item.id} da co trong playlist.');
    }
    final source = item.filePath != null
        ? AudioSource.file(item.filePath!, tag: item)
        : (kIsWeb
              ? AudioSource.uri(
                  Uri.dataFromBytes(item.audioBytes!, mimeType: _mimeFor(item)),
                  tag: item,
                )
              : throw ArgumentError('Thieu audioBytes cho ${item.id} (Web).'));
    if (!kIsWeb && item.filePath != null && !await File(item.filePath!).exists()) {
      throw ArgumentError('File audio khong ton tai: ${item.filePath}');
    }
    queue.add(List<MediaItem>.unmodifiable([...queue.value, item]));
    final current = _player.audioSource;
    if (current is ConcatenatingAudioSource) {
      await current.add(source);
    } else {
      // Playlist chua nap (chua loadPlaylist) -> rollback + nem de caller biet.
      queue.add(List<MediaItem>.unmodifiable(
        queue.value.where((m) => m.id != item.id).toList(),
      ));
      throw StateError('Chua co playlist de chen ${item.id}.');
    }
  }
  /// Doan MIME tu duoi file de dung voi data: URI tren Web.
  static String _mimeFor(ChapterMediaItem item) {
    return item.mimeType ??
        (item.id.endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav');
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _cancelSleepTimer();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) => _player.seek(Duration.zero, index: index);

  /// Doi toc do phat (0.5-1.5).
  Future<void> setPlaybackSpeed(double speed) =>
      _player.setSpeed(speed.clamp(0.5, 1.5).toDouble());

  /// Tua tien [seconds] giay (mac dinh 10s).
  Future<void> forward([int seconds = 10]) async {
    final target = _player.position + Duration(seconds: seconds);
    final max = _player.duration;
    await _player.seek(max != null && target > max ? max : target);
  }

  /// Tua lui [seconds] giay (mac dinh 10s).
  @override
  Future<void> rewind([int seconds = 10]) async {
    final target = _player.position - Duration(seconds: seconds);
    await _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  /// Hen gio ngu: dung phat sau [duration]. Goi lai voi null de huy.
  void setSleepTimer(Duration? duration) {
    _cancelSleepTimer();
    if (duration == null) return;
    _sleepTimer = Timer(duration, () async {
      await pause();
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  /// Giai phong: huy timer, dong stream snapshot, giai phong player.
  /// Goi 1 lan khi app dispose handler (test / hot-restart).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelSleepTimer();
    await _snapshot.close();
    await _player.dispose();
  }

  /// Cau hinh audio session (Android/iOS): uu tien speech, xu ly ngat quang.
  ///
  /// Web: audio_session khong ho tro -> bo qua, khong throw.
  static Future<void> configureSession() async {
    if (kIsWeb) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }
}
