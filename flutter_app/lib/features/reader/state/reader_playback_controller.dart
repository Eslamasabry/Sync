import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readerPlaybackProvider =
    NotifierProvider<ReaderPlaybackController, ReaderPlaybackState>(
      ReaderPlaybackController.new,
    );

class ReaderPlaybackState {
  const ReaderPlaybackState({
    required this.positionMs,
    required this.isPlaying,
    required this.speed,
    required this.themeMode,
  });

  final int positionMs;
  final bool isPlaying;
  final double speed;
  final ThemeMode themeMode;

  ReaderPlaybackState copyWith({
    int? positionMs,
    bool? isPlaying,
    double? speed,
    ThemeMode? themeMode,
  }) {
    return ReaderPlaybackState(
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class ReaderPlaybackController extends Notifier<ReaderPlaybackState> {
  Timer? _timer;

  @override
  ReaderPlaybackState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return const ReaderPlaybackState(
      positionMs: 0,
      isPlaying: false,
      speed: 1.0,
      themeMode: ThemeMode.light,
    );
  }

  void togglePlayback(int totalDurationMs) {
    if (state.isPlaying) {
      _timer?.cancel();
      state = state.copyWith(isPlaying: false);
      return;
    }

    _timer?.cancel();
    state = state.copyWith(isPlaying: true);
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final stepMs = (120 * state.speed).round();
      final nextPosition = state.positionMs + stepMs;
      if (nextPosition >= totalDurationMs) {
        _timer?.cancel();
        state = state.copyWith(isPlaying: false, positionMs: totalDurationMs);
        return;
      }
      state = state.copyWith(positionMs: nextPosition);
    });
  }

  void rewind15Seconds() {
    seekTo(state.positionMs - 15000);
  }

  void seekTo(int positionMs) {
    state = state.copyWith(positionMs: positionMs.clamp(0, 1 << 31));
  }

  void setSpeed(double speed) {
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
    state = state.copyWith(positionMs: 0, isPlaying: false);
  }
}
