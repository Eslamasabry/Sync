import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

final readerSessionProvider =
    NotifierProvider<ReaderSessionController, ReaderSessionState>(
      ReaderSessionController.new,
    );

class ReaderSessionState {
  const ReaderSessionState({
    required this.readerModel,
    required this.syncArtifact,
    required this.positionMs,
    required this.isPlaying,
    required this.speed,
    required this.themeMode,
  });

  final ReaderModel readerModel;
  final SyncArtifact syncArtifact;
  final int positionMs;
  final bool isPlaying;
  final double speed;
  final ThemeMode themeMode;

  SyncToken? get activeToken {
    for (final token in syncArtifact.tokens) {
      if (positionMs >= token.startMs && positionMs < token.endMs) {
        return token;
      }
    }
    if (syncArtifact.tokens.isEmpty) {
      return null;
    }
    if (positionMs >= syncArtifact.tokens.last.endMs) {
      return syncArtifact.tokens.last;
    }
    return null;
  }

  String? get activeLocationKey => activeToken?.location.locationKey;

  ReaderSessionState copyWith({
    int? positionMs,
    bool? isPlaying,
    double? speed,
    ThemeMode? themeMode,
  }) {
    return ReaderSessionState(
      readerModel: readerModel,
      syncArtifact: syncArtifact,
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class ReaderSessionController extends Notifier<ReaderSessionState> {
  Timer? _timer;

  @override
  ReaderSessionState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return ReaderSessionState(
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      positionMs: 0,
      isPlaying: false,
      speed: 1.0,
      themeMode: ThemeMode.light,
    );
  }

  void togglePlayback() {
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
      if (nextPosition >= state.syncArtifact.totalDurationMs) {
        _timer?.cancel();
        state = state.copyWith(
          isPlaying: false,
          positionMs: state.syncArtifact.totalDurationMs,
        );
        return;
      }
      state = state.copyWith(positionMs: nextPosition);
    });
  }

  void rewind15Seconds() {
    seekTo(
      (state.positionMs - 15000).clamp(0, state.syncArtifact.totalDurationMs),
    );
  }

  void seekTo(int positionMs) {
    state = state.copyWith(positionMs: positionMs);
  }

  void seekToToken(SyncToken token) {
    seekTo(token.startMs);
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
}
