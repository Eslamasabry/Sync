import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

enum ReaderAudioDownloadStatus {
  idle,
  downloading,
  succeeded,
  failed,
  removing,
}

class ReaderAudioDownloadState {
  const ReaderAudioDownloadState({
    required this.status,
    required this.progress,
    this.message,
  });

  final ReaderAudioDownloadStatus status;
  final double progress;
  final String? message;

  bool get isBusy =>
      status == ReaderAudioDownloadStatus.downloading ||
      status == ReaderAudioDownloadStatus.removing;

  ReaderAudioDownloadState copyWith({
    ReaderAudioDownloadStatus? status,
    double? progress,
    String? message,
    bool clearMessage = false,
  }) {
    return ReaderAudioDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

final readerAudioDownloadProvider =
    NotifierProvider<ReaderAudioDownloadController, ReaderAudioDownloadState>(
      ReaderAudioDownloadController.new,
    );

class ReaderAudioDownloadController extends Notifier<ReaderAudioDownloadState> {
  @override
  ReaderAudioDownloadState build() {
    return const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.idle,
      progress: 0,
    );
  }

  Future<void> downloadCurrentProject() async {
    final projectId = await ref.read(projectIdProvider.future);
    final repository = await ref.read(readerRepositoryProvider.future);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.downloading,
      progress: 0,
    );
    try {
      final result = await repository.downloadAudio(
        projectId: projectId,
        onProgress: (progress) {
          state = state.copyWith(progress: progress.fraction);
        },
      );
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 1,
        message:
            'Downloaded ${result.downloadedAssets} of ${result.totalAssets} audio files for offline playback.',
      );
      ref.invalidate(readerProjectProvider);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        message: 'Audio download failed. $error',
      );
    }
  }

  Future<void> removeCurrentProjectAudio() async {
    final projectId = await ref.read(projectIdProvider.future);
    final repository = await ref.read(readerRepositoryProvider.future);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.removing,
      progress: 0,
    );
    try {
      await repository.removeDownloadedAudio(projectId);
      state = const ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 0,
        message: 'Removed downloaded audio from this device.',
      );
      ref.invalidate(readerProjectProvider);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        message: 'Could not remove downloaded audio. $error',
      );
    }
  }

  void clearMessage() {
    state = state.copyWith(
      status: ReaderAudioDownloadStatus.idle,
      progress: 0,
      clearMessage: true,
    );
  }
}
