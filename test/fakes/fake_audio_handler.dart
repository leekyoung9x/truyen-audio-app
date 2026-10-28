import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:truyen_audio_app/src/features/player/audio_handler.dart';

/// Gia lap [StoryAudioHandler], KHONG cham just_audio/audio_service that.
///
/// Ghi lai moi cuoc goi de test assert hanh vi UI (play/pause/tua/sleep...).
/// Phat ra [PlayerStateSnapshot] qua [snapshotStream] giong handler that.
class FakeStoryAudioHandler extends StoryAudioHandler {
  FakeStoryAudioHandler()
    : _snapshots = BehaviorSubject<PlayerStateSnapshot>.seeded(
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

  final BehaviorSubject<PlayerStateSnapshot> _snapshots;

  PlayerStateSnapshot get current => _snapshots.value;

  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int forwardCalls = 0;
  int rewindCalls = 0;
  int skipNextCalls = 0;
  int skipPreviousCalls = 0;
  int skipToQueueItemCalls = 0;
  int setSpeedCalls = 0;
  int loadPlaylistCalls = 0;
  int sleepTimerCalls = 0;
  int lastSleepTimerMinutes = -1;

  List<ChapterMediaItem> loadedItems = const [];
  int loadedStartIndex = 0;

  void _emit(PlayerStateSnapshot next) => _snapshots.add(next);

  PlayerStateSnapshot _copy({
    bool? playing,
    Duration? position,
    Duration? Function()? duration,
    double? speed,
    int? Function()? currentIndex,
    int? queueLength,
  }) {
    final c = _snapshots.value;
    return PlayerStateSnapshot(
      playing: playing ?? c.playing,
      processingState: c.processingState,
      position: position ?? c.position,
      duration: duration != null ? duration() : c.duration,
      speed: speed ?? c.speed,
      currentIndex: currentIndex != null ? currentIndex() : c.currentIndex,
      queueLength: queueLength ?? c.queueLength,
    );
  }

  @override
  ValueStream<PlayerStateSnapshot> get snapshotStream => _snapshots;

  @override
  Future<void> play() async {
    playCalls++;
    _emit(_copy(playing: true));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _emit(_copy(playing: false));
  }

  @override
  Future<void> stop() async {
    _emit(_copy(playing: false, position: Duration.zero));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    _emit(
      _copy(
        position: position < Duration.zero ? Duration.zero : position,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    skipNextCalls++;
    final next = (current.currentIndex ?? -1) + 1;
    final max = loadedItems.isEmpty ? 0 : loadedItems.length - 1;
    _emit(_copy(currentIndex: () => next.clamp(0, max).toInt()));
  }

  @override
  Future<void> skipToPrevious() async {
    skipPreviousCalls++;
    final prev = (current.currentIndex ?? 1) - 1;
    final max = loadedItems.isEmpty ? 0 : loadedItems.length - 1;
    _emit(_copy(currentIndex: () => prev.clamp(0, max).toInt()));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    skipToQueueItemCalls++;
    _emit(_copy(currentIndex: () => index));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    setSpeedCalls++;
    _emit(_copy(speed: speed.clamp(0.5, 1.5).toDouble()));
  }

  @override
  Future<void> forward([int seconds = 10]) async {
    forwardCalls++;
    _emit(_copy(position: current.position + Duration(seconds: seconds)));
  }

  @override
  Future<void> rewind([int seconds = 10]) async {
    rewindCalls++;
    final target = current.position - Duration(seconds: seconds);
    _emit(_copy(position: target < Duration.zero ? Duration.zero : target));
  }

  @override
  Future<void> loadPlaylist(
    List<ChapterMediaItem> items, {
    int startIndex = 0,
  }) async {
    loadPlaylistCalls++;
    if (items.isEmpty) {
      throw ArgumentError('Playlist khong duoc rong.');
    }
    loadedItems = List<ChapterMediaItem>.unmodifiable(items);
    loadedStartIndex = startIndex.clamp(0, items.length - 1).toInt();
    _emit(
      _copy(
        currentIndex: () => loadedStartIndex,
        queueLength: items.length,
      ),
    );
  }

  /// v12: prefetch nen chen chuong tiep vao playlist hien tai (giong
  /// cheap-append cua ConcatenatingAudioSource, KHONG nap lai tu dau).
  /// Fake khong co just_audio that nen chi noi list + emit lai queueLength.
  @override
  Future<void> appendToPlaylist(ChapterMediaItem item) async {
    // Giu tinh bat bien kieu StoryAudioHandler that (queue.add).
    loadedItems = List<ChapterMediaItem>.unmodifiable([...loadedItems, item]);
    _emit(_copy(queueLength: loadedItems.length));
  }

  @override
  void setSleepTimer(Duration? duration) {
    sleepTimerCalls++;
    lastSleepTimerMinutes = duration?.inMinutes ?? -1;
  }

  /// Dung de test kiem tra currentIndex sau skip.
  int? get currentIndex => current.currentIndex;

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (!_snapshots.isClosed) await _snapshots.close();
    await super.dispose();
  }
}

/// Handler cho case v10: play() treo vinh vien (mo phong bug Web — promise
/// khong resolve tren just_audio Web). loadPlaylist/speed van xong ngay.
class HangingPlayAudioHandler extends FakeStoryAudioHandler {
  /// Gate de cho phep test tiep tuc ma khong doi 30s timeout that.
  Completer<void>? hangGate;

  @override
  Future<void> play() async {
    playCalls++;
    final gate = hangGate ??= Completer<void>();
    await gate.future; // treo cho den khi timeout (30s) hoac unhang
  }

  void unhang() {
    if (hangGate != null && !hangGate!.isCompleted) {
      hangGate!.complete();
    }
  }
}
