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
    required this.completedAssets,
    required this.totalAssets,
    this.message,
    this.activeAssetId,
  });

  final ReaderAudioDownloadStatus status;
  final double progress;
  final int completedAssets;
  final int totalAssets;
  final String? message;
  final String? activeAssetId;

  bool get isBusy =>
      status == ReaderAudioDownloadStatus.downloading ||
      status == ReaderAudioDownloadStatus.removing;

  ReaderAudioDownloadState copyWith({
    ReaderAudioDownloadStatus? status,
    double? progress,
    int? completedAssets,
    int? totalAssets,
    String? message,
    String? activeAssetId,
    bool clearMessage = false,
    bool clearActiveAssetId = false,
  }) {
    return ReaderAudioDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      completedAssets: completedAssets ?? this.completedAssets,
      totalAssets: totalAssets ?? this.totalAssets,
      message: clearMessage ? null : message ?? this.message,
      activeAssetId: clearActiveAssetId
          ? null
          : activeAssetId ?? this.activeAssetId,
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
      completedAssets: 0,
      totalAssets: 0,
    );
  }

  Future<void> downloadCurrentProject() async {
    final projectId = await ref.read(projectIdProvider.future);
    final repository = await ref.read(readerRepositoryProvider.future);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.downloading,
      progress: 0,
      completedAssets: 0,
      totalAssets: 0,
    );
    try {
      final result = await repository.downloadAudio(
        projectId: projectId,
        onProgress: (progress) {
          state = state.copyWith(
            progress: progress.fraction,
            completedAssets: progress.completedAssets,
            totalAssets: progress.totalAssets,
            activeAssetId: progress.activeAssetId,
          );
        },
      );
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 1,
        completedAssets: result.downloadedAssets,
        totalAssets: result.totalAssets,
        message:
            'Downloaded ${result.downloadedAssets} of ${result.totalAssets} audio files for offline playback.',
        activeAssetId: null,
      );
      ref.invalidate(readerProjectProvider);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        completedAssets: state.completedAssets,
        totalAssets: state.totalAssets,
        message: 'Audio download failed. $error',
        activeAssetId: state.activeAssetId,
      );
    }
  }

  Future<void> removeCurrentProjectAudio() async {
    final projectId = await ref.read(projectIdProvider.future);
    final repository = await ref.read(readerRepositoryProvider.future);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.removing,
      progress: 0,
      completedAssets: 0,
      totalAssets: 0,
    );
    try {
      await repository.removeDownloadedAudio(projectId);
      state = const ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 0,
        completedAssets: 0,
        totalAssets: 0,
        message: 'Removed downloaded audio from this device.',
        activeAssetId: null,
      );
      ref.invalidate(readerProjectProvider);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        completedAssets: 0,
        totalAssets: 0,
        message: 'Could not remove downloaded audio. $error',
        activeAssetId: null,
      );
    }
  }

  void clearMessage() {
    state = state.copyWith(
      status: ReaderAudioDownloadStatus.idle,
      progress: 0,
      completedAssets: 0,
      totalAssets: 0,
      clearMessage: true,
      clearActiveAssetId: true,
    );
  }
}
