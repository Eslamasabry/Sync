import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/playback/playback_driver.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';

final readerPlaybackProvider =
    NotifierProvider<ReaderPlaybackController, ReaderPlaybackState>(
      ReaderPlaybackController.new,
    );

final playbackDriverProvider = Provider<PlaybackDriver>(
  (ref) => JustAudioPlaybackDriver(),
);

enum ReaderPlaybackPreset { custom, study, commute, bedtime }

class ReaderPlaybackState {
  const ReaderPlaybackState({
    required this.positionMs,
    required this.isPlaying,
    required this.speed,
    required this.themeMode,
    required this.fontScale,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.followPlayback,
    required this.distractionFreeMode,
    required this.usesNativeAudio,
    required this.totalDurationMs,
    required this.contentStartMs,
    required this.contentEndMs,
    required this.isScrubbing,
    required this.scrubPositionMs,
    required this.playbackPreset,
    required this.loopStartMs,
    required this.loopEndMs,
    required this.highContrastMode,
    required this.leftHandedMode,
  });

  final int positionMs;
  final bool isPlaying;
  final double speed;
  final ThemeMode themeMode;
  final double fontScale;
  final double lineHeight;
  final double paragraphSpacing;
  final bool followPlayback;
  final bool distractionFreeMode;
  final bool usesNativeAudio;
  final int totalDurationMs;
  final int contentStartMs;
  final int contentEndMs;
  final bool isScrubbing;
  final int? scrubPositionMs;
  final ReaderPlaybackPreset playbackPreset;
  final int? loopStartMs;
  final int? loopEndMs;
  final bool highContrastMode;
  final bool leftHandedMode;

  int get displayedPositionMs => scrubPositionMs ?? positionMs;

  bool get hasLeadingMatter => contentStartMs > 0;

  bool get hasTrailingMatter =>
      contentEndMs > 0 && contentEndMs < totalDurationMs;

  bool get hasLoop =>
      loopStartMs != null && loopEndMs != null && loopEndMs! > loopStartMs!;

  ReaderPlaybackState copyWith({
    int? positionMs,
    bool? isPlaying,
    double? speed,
    ThemeMode? themeMode,
    double? fontScale,
    double? lineHeight,
    double? paragraphSpacing,
    bool? followPlayback,
    bool? distractionFreeMode,
    bool? usesNativeAudio,
    int? totalDurationMs,
    int? contentStartMs,
    int? contentEndMs,
    bool? isScrubbing,
    int? scrubPositionMs,
    ReaderPlaybackPreset? playbackPreset,
    int? loopStartMs,
    int? loopEndMs,
    bool? highContrastMode,
    bool? leftHandedMode,
    bool clearScrubPosition = false,
    bool clearLoopStart = false,
    bool clearLoopEnd = false,
  }) {
    return ReaderPlaybackState(
      positionMs: positionMs ?? this.positionMs,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      followPlayback: followPlayback ?? this.followPlayback,
      distractionFreeMode: distractionFreeMode ?? this.distractionFreeMode,
      usesNativeAudio: usesNativeAudio ?? this.usesNativeAudio,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      contentStartMs: contentStartMs ?? this.contentStartMs,
      contentEndMs: contentEndMs ?? this.contentEndMs,
      isScrubbing: isScrubbing ?? this.isScrubbing,
      scrubPositionMs: clearScrubPosition
          ? null
          : scrubPositionMs ?? this.scrubPositionMs,
      playbackPreset: playbackPreset ?? this.playbackPreset,
      loopStartMs: clearLoopStart ? null : loopStartMs ?? this.loopStartMs,
      loopEndMs: clearLoopEnd ? null : loopEndMs ?? this.loopEndMs,
      highContrastMode: highContrastMode ?? this.highContrastMode,
      leftHandedMode: leftHandedMode ?? this.leftHandedMode,
    );
  }
}

class ReaderPlaybackController extends Notifier<ReaderPlaybackState> {
  Timer? _timer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  String? _currentProjectId;
  String? _currentApiBaseUrl;
  ReaderModel? _currentReaderModel;
  SyncArtifact? _currentSyncArtifact;
  int _lastPersistedPositionMs = -1;
  DateTime? _lastPersistedAt;

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
      fontScale: 1.0,
      lineHeight: 1.55,
      paragraphSpacing: 1.0,
      followPlayback: true,
      distractionFreeMode: false,
      usesNativeAudio: false,
      totalDurationMs: 0,
      contentStartMs: 0,
      contentEndMs: 0,
      isScrubbing: false,
      scrubPositionMs: null,
      playbackPreset: ReaderPlaybackPreset.custom,
      loopStartMs: null,
      loopEndMs: null,
      highContrastMode: false,
      leftHandedMode: false,
    );
  }

  Future<void> configureProject(ReaderProjectBundle bundle) async {
    await _persistReadingLocation(force: true);
    final settings = await ref.read(runtimeConnectionSettingsProvider.future);
    _currentProjectId = bundle.projectId;
    _currentApiBaseUrl = settings.apiBaseUrl;
    _currentReaderModel = bundle.readerModel;
    _currentSyncArtifact = bundle.syncArtifact;
    resetForProject(persistLocation: false);
    if (bundle.audioUrls.isEmpty) {
      state = state.copyWith(
        usesNativeAudio: false,
        totalDurationMs: bundle.syncArtifact.totalDurationMs,
        contentStartMs: bundle.syncArtifact.contentStartMs,
        contentEndMs: bundle.syncArtifact.contentEndMs,
      );
      await _restoreReadingLocation(
        bundle.projectId,
        apiBaseUrl: settings.apiBaseUrl,
      );
      return;
    }

    final driver = ref.read(playbackDriverProvider);
    _positionSubscription ??= driver.positionStream.listen((position) {
      state = state.copyWith(positionMs: position.inMilliseconds);
      final loopStartMs = state.loopStartMs;
      final loopEndMs = state.loopEndMs;
      if (loopStartMs != null &&
          loopEndMs != null &&
          loopEndMs > loopStartMs &&
          position.inMilliseconds >= loopEndMs) {
        unawaited(_seekWithinLoop(loopStartMs));
        return;
      }
      unawaited(_maybePersistReadingLocation());
    });
    _playingSubscription ??= driver.playingStream.listen((isPlaying) {
      state = state.copyWith(isPlaying: isPlaying);
      if (!isPlaying) {
        unawaited(_persistReadingLocation(force: true));
      }
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
    await _restoreReadingLocation(bundle.projectId, apiBaseUrl: settings.apiBaseUrl);
  }

  Future<void> togglePlayback(int totalDurationMs) async {
    if (state.usesNativeAudio) {
      final driver = ref.read(playbackDriverProvider);
      if (state.isPlaying) {
        await driver.pause();
      } else {
        if (state.hasLoop) {
          final loopStartMs = state.loopStartMs!;
          final loopEndMs = state.loopEndMs!;
          final currentPosition = state.displayedPositionMs;
          if (currentPosition < loopStartMs || currentPosition >= loopEndMs) {
            await _seekWithinLoop(loopStartMs);
          }
        }
        await driver.play();
      }
      return;
    }

    if (state.isPlaying) {
      _timer?.cancel();
      state = state.copyWith(isPlaying: false);
      await _persistReadingLocation(force: true);
      return;
    }

    _timer?.cancel();
    if (state.hasLoop) {
      final loopStartMs = state.loopStartMs!;
      final loopEndMs = state.loopEndMs!;
      final currentPosition = state.displayedPositionMs;
      if (currentPosition < loopStartMs || currentPosition >= loopEndMs) {
        state = state.copyWith(
          positionMs: loopStartMs,
          clearScrubPosition: true,
        );
      }
    }
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
      final loopStartMs = state.loopStartMs;
      final loopEndMs = state.loopEndMs;
      if (loopStartMs != null &&
          loopEndMs != null &&
          loopEndMs > loopStartMs &&
          nextPosition >= loopEndMs) {
        state = state.copyWith(
          positionMs: loopStartMs,
          clearScrubPosition: true,
        );
        unawaited(_maybePersistReadingLocation());
        return;
      }
      state = state.copyWith(
        positionMs: nextPosition,
        clearScrubPosition: true,
      );
      unawaited(_maybePersistReadingLocation());
    });
  }

  void rewind15Seconds() {
    unawaited(seekTo(_smartSkipPosition(forward: false)));
  }

  void forward15Seconds() {
    unawaited(seekTo(_smartSkipPosition(forward: true)));
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
    await _persistReadingLocation(force: true);
  }

  Future<void> setSpeed(double speed) async {
    if (state.usesNativeAudio) {
      await ref.read(playbackDriverProvider).setSpeed(speed);
    }
    state = state.copyWith(
      speed: speed,
      playbackPreset: ReaderPlaybackPreset.custom,
    );
  }

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light,
    );
  }

  void setFontScale(double value) {
    state = state.copyWith(fontScale: value);
  }

  void setLineHeight(double value) {
    state = state.copyWith(lineHeight: value);
  }

  void setParagraphSpacing(double value) {
    state = state.copyWith(paragraphSpacing: value);
  }

  void toggleFollowPlayback() {
    state = state.copyWith(followPlayback: !state.followPlayback);
  }

  void toggleDistractionFreeMode() {
    state = state.copyWith(distractionFreeMode: !state.distractionFreeMode);
  }

  void toggleHighContrastMode() {
    state = state.copyWith(highContrastMode: !state.highContrastMode);
  }

  void toggleLeftHandedMode() {
    state = state.copyWith(leftHandedMode: !state.leftHandedMode);
  }

  Future<void> applyPreset(ReaderPlaybackPreset preset) async {
    switch (preset) {
      case ReaderPlaybackPreset.custom:
        break;
      case ReaderPlaybackPreset.study:
        await setSpeed(0.9);
        state = state.copyWith(
          followPlayback: true,
          distractionFreeMode: false,
          playbackPreset: ReaderPlaybackPreset.study,
        );
      case ReaderPlaybackPreset.commute:
        await setSpeed(1.25);
        state = state.copyWith(
          followPlayback: true,
          distractionFreeMode: false,
          playbackPreset: ReaderPlaybackPreset.commute,
        );
      case ReaderPlaybackPreset.bedtime:
        await setSpeed(0.85);
        state = state.copyWith(
          followPlayback: false,
          distractionFreeMode: true,
          playbackPreset: ReaderPlaybackPreset.bedtime,
        );
    }
  }

  void markLoopStart() {
    final currentPosition = state.displayedPositionMs;
    final preservedLoopEnd = state.loopEndMs;
    state = state.copyWith(
      loopStartMs: currentPosition,
      loopEndMs: preservedLoopEnd != null && preservedLoopEnd > currentPosition
          ? preservedLoopEnd
          : null,
      playbackPreset: ReaderPlaybackPreset.custom,
    );
  }

  void markLoopEnd() {
    final currentPosition = state.displayedPositionMs;
    final loopStart = state.loopStartMs;
    if (loopStart == null) {
      state = state.copyWith(loopStartMs: currentPosition);
      return;
    }
    final orderedStart = currentPosition < loopStart
        ? currentPosition
        : loopStart;
    var orderedEnd = currentPosition < loopStart ? loopStart : currentPosition;
    final minimumDuration = _minimumLoopDurationMs();
    final maximumEnd = _maxLoopBoundaryMs();
    if (orderedEnd - orderedStart < minimumDuration) {
      orderedEnd = (orderedStart + minimumDuration).clamp(
        orderedStart,
        maximumEnd,
      );
    }
    state = state.copyWith(
      loopStartMs: orderedStart,
      loopEndMs: orderedEnd,
      playbackPreset: ReaderPlaybackPreset.custom,
    );
  }

  void clearLoop() {
    state = state.copyWith(clearLoopStart: true, clearLoopEnd: true);
  }

  void resetForProject({bool persistLocation = true}) {
    if (persistLocation) {
      unawaited(_persistReadingLocation(force: true));
    }
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
      playbackPreset: ReaderPlaybackPreset.custom,
      clearLoopStart: true,
      clearLoopEnd: true,
      highContrastMode: false,
      leftHandedMode: false,
    );
    _lastPersistedPositionMs = -1;
    _lastPersistedAt = null;
  }

  Future<void> _seekWithinLoop(int positionMs) async {
    if (state.usesNativeAudio) {
      await ref
          .read(playbackDriverProvider)
          .seek(Duration(milliseconds: positionMs));
    }
    state = state.copyWith(positionMs: positionMs, clearScrubPosition: true);
  }

  int _smartSkipPosition({required bool forward}) {
    final currentPosition = state.displayedPositionMs;
    final loopStart = state.loopStartMs;
    final loopEnd = state.loopEndMs;
    final loopAwareStart =
        state.hasLoop &&
            loopStart != null &&
            loopEnd != null &&
            currentPosition >= loopStart &&
            currentPosition <= loopEnd
        ? loopStart
        : state.contentStartMs;
    final loopAwareEnd =
        state.hasLoop &&
            loopStart != null &&
            loopEnd != null &&
            currentPosition >= loopStart &&
            currentPosition <= loopEnd
        ? loopEnd
        : (state.contentEndMs > state.contentStartMs
              ? state.contentEndMs
              : state.totalDurationMs);

    final artifact = _currentSyncArtifact;
    if (artifact == null || artifact.tokens.isEmpty) {
      final fallbackTarget = currentPosition + (forward ? 15000 : -15000);
      return fallbackTarget.clamp(loopAwareStart, loopAwareEnd);
    }

    final desiredTarget = currentPosition + (forward ? 12000 : -12000);
    if (forward) {
      for (final token in artifact.tokens) {
        if (token.startMs > currentPosition + 500 &&
            token.startMs >= desiredTarget) {
          return token.startMs.clamp(loopAwareStart, loopAwareEnd);
        }
      }
      return loopAwareEnd.clamp(loopAwareStart, loopAwareEnd);
    }

    for (var index = artifact.tokens.length - 1; index >= 0; index -= 1) {
      final token = artifact.tokens[index];
      if (token.startMs < currentPosition - 500 &&
          token.startMs <= desiredTarget) {
        return token.startMs.clamp(loopAwareStart, loopAwareEnd);
      }
    }
    return loopAwareStart.clamp(loopAwareStart, loopAwareEnd);
  }

  int _minimumLoopDurationMs() {
    final artifact = _currentSyncArtifact;
    if (artifact == null || artifact.tokens.isEmpty) {
      return 1200;
    }

    final currentPosition = state.displayedPositionMs;
    final activeToken = _activeTokenAt(artifact, currentPosition);
    if (activeToken == null) {
      return 1200;
    }

    return (activeToken.endMs - activeToken.startMs).clamp(1200, 6000);
  }

  int _maxLoopBoundaryMs() {
    final contentEnd = state.contentEndMs > state.contentStartMs
        ? state.contentEndMs
        : state.totalDurationMs;
    return contentEnd > 0 ? contentEnd : state.totalDurationMs;
  }

  Future<void> _restoreReadingLocation(String projectId, {String? apiBaseUrl}) async {
    final snapshot = await ref
        .read(readerLocationStoreProvider)
        .loadProject(projectId, apiBaseUrl: apiBaseUrl);
    if (snapshot == null) {
      return;
    }
    await seekTo(snapshot.positionMs);
  }

  Future<void> _maybePersistReadingLocation() async {
    final currentPosition = state.displayedPositionMs;
    final now = DateTime.now().toUtc();
    final elapsed = _lastPersistedAt == null
        ? null
        : now.difference(_lastPersistedAt!);
    final movedEnough =
        (currentPosition - _lastPersistedPositionMs).abs() >= 5000;
    if (_lastPersistedAt != null &&
        !movedEnough &&
        elapsed != null &&
        elapsed.inSeconds < 8) {
      return;
    }
    await _persistReadingLocation(force: false);
  }

  Future<void> _persistReadingLocation({required bool force}) async {
    final projectId = _currentProjectId;
    final apiBaseUrl = _currentApiBaseUrl;
    final syncArtifact = _currentSyncArtifact;
    final readerModel = _currentReaderModel;
    if (projectId == null ||
        apiBaseUrl == null ||
        syncArtifact == null ||
        readerModel == null) {
      return;
    }

    final currentPosition = state.displayedPositionMs;
    if (!force && currentPosition == _lastPersistedPositionMs) {
      return;
    }

    final activeToken = _activeTokenAt(syncArtifact, currentPosition);
    final currentSection = _sectionForToken(readerModel, activeToken);
    final contentStart = syncArtifact.contentStartMs;
    final contentEnd = syncArtifact.contentEndMs > contentStart
        ? syncArtifact.contentEndMs
        : syncArtifact.totalDurationMs;
    final clampedPosition = currentPosition.clamp(
      contentStart,
      contentEnd > 0 ? contentEnd : currentPosition,
    );
    final progressFraction = contentEnd <= contentStart
        ? 0.0
        : ((clampedPosition - contentStart) / (contentEnd - contentStart))
              .clamp(0.0, 1.0);

    final snapshot = ReaderLocationSnapshot(
      apiBaseUrl: apiBaseUrl,
      projectId: projectId,
      positionMs: currentPosition,
      totalDurationMs: syncArtifact.totalDurationMs,
      contentStartMs: syncArtifact.contentStartMs,
      contentEndMs: syncArtifact.contentEndMs,
      progressFraction: progressFraction,
      sectionId: currentSection?.id,
      sectionTitle: currentSection?.title,
      updatedAt: DateTime.now().toUtc(),
    );
    await ref.read(readerLocationStoreProvider).storeProject(snapshot);
    ref.read(readerLocationRevisionProvider.notifier).bump();
    _lastPersistedPositionMs = currentPosition;
    _lastPersistedAt = snapshot.updatedAt;
  }
}

SyncToken? _activeTokenAt(SyncArtifact artifact, int positionMs) {
  for (final token in artifact.tokens) {
    if (positionMs >= token.startMs && positionMs < token.endMs) {
      return token;
    }
  }
  if (artifact.tokens.isNotEmpty && positionMs >= artifact.tokens.last.endMs) {
    return artifact.tokens.last;
  }
  return null;
}

ReaderSection? _sectionForToken(ReaderModel readerModel, SyncToken? token) {
  if (token == null) {
    return null;
  }
  for (final section in readerModel.sections) {
    if (section.id == token.location.sectionId) {
      return section;
    }
  }
  return null;
}
