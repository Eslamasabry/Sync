import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

typedef ReaderRepositoryFactory =
    ReaderRepository Function(RuntimeConnectionSettings settings);

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
    this.projectId,
    this.activeAssetId,
  });

  final ReaderAudioDownloadStatus status;
  final double progress;
  final int completedAssets;
  final int totalAssets;
  final String? message;
  final String? projectId;
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
    String? projectId,
    String? activeAssetId,
    bool clearMessage = false,
    bool clearProjectId = false,
    bool clearActiveAssetId = false,
  }) {
    return ReaderAudioDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      completedAssets: completedAssets ?? this.completedAssets,
      totalAssets: totalAssets ?? this.totalAssets,
      message: clearMessage ? null : message ?? this.message,
      projectId: clearProjectId ? null : projectId ?? this.projectId,
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

final readerRepositoryFactoryProvider = Provider<ReaderRepositoryFactory>((
  ref,
) {
  return (settings) => ReaderRepository(
    apiClient: SyncApiClient(
      baseUrl: settings.apiBaseUrl,
      authToken: settings.authToken,
    ),
    artifactCache: ref.read(readerArtifactCacheProvider),
    audioCache: ref.read(readerAudioCacheProvider),
  );
});

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
    final settings = await ref.read(runtimeConnectionSettingsProvider.future);
    await downloadProject(settings);
  }

  Future<void> downloadProject(RuntimeConnectionSettings settings) async {
    final projectId = settings.projectId;
    final repository = ref.read(readerRepositoryFactoryProvider)(settings);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.downloading,
      progress: 0,
      completedAssets: 0,
      totalAssets: 0,
      projectId: null,
    );
    try {
      final result = await repository.downloadAudio(
        projectId: projectId,
        onProgress: (progress) {
          state = state.copyWith(
            progress: progress.fraction,
            completedAssets: progress.completedAssets,
            totalAssets: progress.totalAssets,
            projectId: projectId,
            activeAssetId: progress.activeAssetId,
          );
        },
      );
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 1,
        completedAssets: result.downloadedAssets,
        totalAssets: result.totalAssets,
        projectId: projectId,
        message:
            'Downloaded ${result.downloadedAssets} of ${result.totalAssets} audio files for $projectId.',
        activeAssetId: null,
      );
      _invalidateProjectCaches(settings);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        completedAssets: state.completedAssets,
        totalAssets: state.totalAssets,
        projectId: projectId,
        message: 'Audio download failed for $projectId. $error',
        activeAssetId: state.activeAssetId,
      );
    }
  }

  Future<void> removeCurrentProjectAudio() async {
    final settings = await ref.read(runtimeConnectionSettingsProvider.future);
    await removeProjectAudio(settings);
  }

  Future<void> removeProjectAudio(RuntimeConnectionSettings settings) async {
    final projectId = settings.projectId;
    final repository = ref.read(readerRepositoryFactoryProvider)(settings);
    state = const ReaderAudioDownloadState(
      status: ReaderAudioDownloadStatus.removing,
      progress: 0,
      completedAssets: 0,
      totalAssets: 0,
      projectId: null,
    );
    try {
      await repository.removeDownloadedAudio(projectId);
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.succeeded,
        progress: 0,
        completedAssets: 0,
        totalAssets: 0,
        projectId: projectId,
        message: 'Removed downloaded audio for $projectId from this device.',
        activeAssetId: null,
      );
      _invalidateProjectCaches(settings);
    } catch (error) {
      state = ReaderAudioDownloadState(
        status: ReaderAudioDownloadStatus.failed,
        progress: 0,
        completedAssets: 0,
        totalAssets: 0,
        projectId: projectId,
        message: 'Could not remove downloaded audio for $projectId. $error',
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
      clearProjectId: true,
      clearActiveAssetId: true,
    );
  }

  void _invalidateProjectCaches(RuntimeConnectionSettings _) {
    ref.invalidate(readerProjectProvider);
  }
}
