import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/playback/playback_driver.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';

final readerPlaybackProvider =
    NotifierProvider<ReaderPlaybackController, ReaderPlaybackState>(
      ReaderPlaybackController.new,
    );

final playbackDriverProvider = Provider<PlaybackDriver>(
  (ref) => JustAudioPlaybackDriver(),
);

class ReaderPlaybackState {
  const ReaderPlaybackState({
    required this.positionMs,
    required this.isPlaying,
    required this.speed,
    required this.themeMode,
    required this.usesNativeAudio,
    required this.totalDurationMs,
    required this.contentStartMs,
    required this.contentEndMs,
    required this.isScrubbing,
    required this.scrubPositionMs,
  });

  final int positionMs;
  final bool isPlaying;
  final double speed;
  final ThemeMode themeMode;
  final bool usesNativeAudio;
  final int totalDurationMs;
  final int contentStartMs;
  final int contentEndMs;
  final bool isScrubbing;
  final int? scrubPositionMs;

  int get displayedPositionMs => scrubPositionMs ?? positionMs;

  bool get hasLeadingMatter => contentStartMs > 0;

  bool get hasTrailingMatter =>
      contentEndMs > 0 && contentEndMs < totalDurationMs;

  ReaderPlaybackState copyWith({
    int? positionMs,
    bool? isPlaying,
    double? speed,
    ThemeMode? themeMode,
    bool? usesNativeAudio,
    int? totalDurationMs,
    int? contentStartMs,
    int? contentEndMs,
    bool? isScrubbing,
    int? scrubPositionMs,
    bool clearScrubPosition = false,
  }) {
    return ReaderPlaybackState(
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      themeMode: themeMode ?? this.themeMode,
      usesNativeAudio: usesNativeAudio ?? this.usesNativeAudio,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      contentStartMs: contentStartMs ?? this.contentStartMs,
      contentEndMs: contentEndMs ?? this.contentEndMs,
      isScrubbing: isScrubbing ?? this.isScrubbing,
      scrubPositionMs: clearScrubPosition
          ? null
          : scrubPositionMs ?? this.scrubPositionMs,
    );
  }
}

class ReaderPlaybackController extends Notifier<ReaderPlaybackState> {
  Timer? _timer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;

  @override
  ReaderPlaybackState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _positionSubscription?.cancel();
      _playingSubscription?.cancel();
    });
    return const ReaderPlaybackState(
      positionMs: 0,
      isPlaying: false,
      speed: 1.0,
      themeMode: ThemeMode.light,
      usesNativeAudio: false,
      totalDurationMs: 0,
      contentStartMs: 0,
      contentEndMs: 0,
      isScrubbing: false,
      scrubPositionMs: null,
    );
  }

  Future<void> configureProject(ReaderProjectBundle bundle) async {
    resetForProject();
    if (bundle.source != ReaderContentSource.api || bundle.audioUrls.isEmpty) {
      state = state.copyWith(
        usesNativeAudio: false,
        totalDurationMs: bundle.syncArtifact.totalDurationMs,
        contentStartMs: bundle.syncArtifact.contentStartMs,
        contentEndMs: bundle.syncArtifact.contentEndMs,
      );
      return;
    }

    final driver = ref.read(playbackDriverProvider);
    _positionSubscription ??= driver.positionStream.listen((position) {
      state = state.copyWith(positionMs: position.inMilliseconds);
    });
    _playingSubscription ??= driver.playingStream.listen((isPlaying) {
      state = state.copyWith(isPlaying: isPlaying);
    });

    await driver.setUrls(bundle.audioUrls);
    await driver.setSpeed(state.speed);
    state = state.copyWith(
      usesNativeAudio: true,
      positionMs: 0,
      totalDurationMs: bundle.syncArtifact.totalDurationMs,
      contentStartMs: bundle.syncArtifact.contentStartMs,
      contentEndMs: bundle.syncArtifact.contentEndMs,
    );
  }

  Future<void> togglePlayback(int totalDurationMs) async {
    if (state.usesNativeAudio) {
      final driver = ref.read(playbackDriverProvider);
      if (state.isPlaying) {
        await driver.pause();
      } else {
        await driver.play();
      }
      return;
    }

    if (state.isPlaying) {
      _timer?.cancel();
      state = state.copyWith(isPlaying: false);
      return;
    }

    _timer?.cancel();
    state = state.copyWith(isPlaying: true);
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final stepMs = (120 * state.speed).round();
      final nextPosition = state.displayedPositionMs + stepMs;
      if (nextPosition >= totalDurationMs) {
        _timer?.cancel();
        state = state.copyWith(
          isPlaying: false,
          positionMs: totalDurationMs,
          isScrubbing: false,
          clearScrubPosition: true,
        );
        return;
      }
      state = state.copyWith(
        positionMs: nextPosition,
        clearScrubPosition: true,
      );
    });
  }

  void rewind15Seconds() {
    seekTo(state.displayedPositionMs - 15000);
  }

  void forward15Seconds() {
    seekTo(state.displayedPositionMs + 15000);
  }

  Future<void> seekToContentStart() async {
    await seekTo(state.contentStartMs);
  }

  Future<void> seekToContentEnd() async {
    await seekTo(state.contentEndMs);
  }

  void beginScrub(double value) {
    state = state.copyWith(isScrubbing: true, scrubPositionMs: value.round());
  }

  void updateScrub(double value) {
    state = state.copyWith(isScrubbing: true, scrubPositionMs: value.round());
  }

  Future<void> commitScrub(double value) async {
    final nextPosition = value.round();
    state = state.copyWith(isScrubbing: false, scrubPositionMs: nextPosition);
    await seekTo(nextPosition);
  }

  void cancelScrub() {
    state = state.copyWith(isScrubbing: false, clearScrubPosition: true);
  }

  Future<void> seekTo(int positionMs) async {
    final maxPosition = state.totalDurationMs > 0
        ? state.totalDurationMs
        : 1 << 31;
    final nextPosition = positionMs.clamp(0, maxPosition);
    if (state.usesNativeAudio) {
      await ref
          .read(playbackDriverProvider)
          .seek(Duration(milliseconds: nextPosition));
    }
    state = state.copyWith(
      positionMs: nextPosition,
      isScrubbing: false,
      clearScrubPosition: true,
    );
  }

  Future<void> setSpeed(double speed) async {
    if (state.usesNativeAudio) {
      await ref.read(playbackDriverProvider).setSpeed(speed);
    }
    state = state.copyWith(speed: speed);
  }

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light,
    );
  }

  void resetForProject() {
    _timer?.cancel();
    state = state.copyWith(
      positionMs: 0,
      isPlaying: false,
      usesNativeAudio: false,
      totalDurationMs: 0,
      contentStartMs: 0,
      contentEndMs: 0,
      isScrubbing: false,
      clearScrubPosition: true,
    );
  }
}
