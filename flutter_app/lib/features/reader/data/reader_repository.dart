import 'package:dio/dio.dart';
import 'package:sync_flutter/core/config/app_config.dart' show defaultProjectId;
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

enum ReaderContentSource {
  api,
  offlineCache,
  artifactPending,
  projectError,
  demoFallback,
}

enum ReaderPlaybackSourceMode {
  textOnly,
  remoteStreaming,
  mixed,
  offlineCached,
}

class ReaderProjectBundle {
  const ReaderProjectBundle({
    required this.projectId,
    required this.readerModel,
    required this.syncArtifact,
    required this.source,
    required this.audioUrls,
    required this.totalAudioAssets,
    required this.cachedAudioAssets,
    required this.hasCompleteOfflineAudio,
    this.statusMessage,
    this.cachedAt,
    this.audioCachedAt,
  });

  final String projectId;
  final ReaderModel readerModel;
  final SyncArtifact syncArtifact;
  final ReaderContentSource source;
  final List<String> audioUrls;
  final int totalAudioAssets;
  final int cachedAudioAssets;
  final bool hasCompleteOfflineAudio;
  final String? statusMessage;
  final DateTime? cachedAt;
  final DateTime? audioCachedAt;

  int get streamingAudioAssets {
    final remaining = totalAudioAssets - cachedAudioAssets;
    return remaining > 0 ? remaining : 0;
  }

  bool get hasAnyAudio => totalAudioAssets > 0;

  ReaderPlaybackSourceMode playbackSourceMode({required bool usesNativeAudio}) {
    if (!usesNativeAudio || audioUrls.isEmpty) {
      return ReaderPlaybackSourceMode.textOnly;
    }
    if (hasCompleteOfflineAudio) {
      return ReaderPlaybackSourceMode.offlineCached;
    }
    if (cachedAudioAssets > 0) {
      return ReaderPlaybackSourceMode.mixed;
    }
    return ReaderPlaybackSourceMode.remoteStreaming;
  }
}

class AudioDownloadResult {
  const AudioDownloadResult({
    required this.downloadedAssets,
    required this.totalAssets,
  });

  final int downloadedAssets;
  final int totalAssets;
}

class ReaderProjectLoadException implements Exception {
  const ReaderProjectLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReaderRepository {
  const ReaderRepository({
    required SyncApiClient apiClient,
    ReaderArtifactCache artifactCache = const NoopReaderArtifactCache(),
    ReaderAudioCache audioCache = const NoopReaderAudioCache(),
  }) : _apiClient = apiClient,
       _artifactCache = artifactCache,
       _audioCache = audioCache;

  final SyncApiClient _apiClient;
  final ReaderArtifactCache _artifactCache;
  final ReaderAudioCache _audioCache;

  Future<ReaderProjectBundle> loadProject(String projectId) async {
    ReaderModel readerModel;
    SyncArtifact syncArtifact;
    Map<String, dynamic>? projectDetail;

    try {
      readerModel = await _apiClient.fetchReaderModel(projectId);
      syncArtifact = await _apiClient.fetchSyncArtifact(projectId);
      projectDetail = await _apiClient.fetchProjectDetail(projectId);
    } on DioException catch (error) {
      final cachedBundle = await _loadCachedBundleIfAvailable(
        projectId: projectId,
        error: error,
      );
      if (cachedBundle != null) {
        return cachedBundle;
      }

      if (_shouldUseDemoFallback(projectId: projectId, error: error)) {
        return _demoFallbackBundle();
      }

      return _buildBackendStateBundle(projectId: projectId, error: error);
    }

    await _storeCachedArtifacts(
      projectId: projectId,
      readerModel: readerModel,
      syncArtifact: syncArtifact,
    );

    final resolvedAudio = await _resolveAudioSources(
      projectId: projectId,
      syncArtifact: syncArtifact,
      projectDetail: projectDetail,
      allowRemoteFallback: true,
    );

    return ReaderProjectBundle(
      projectId: projectId,
      readerModel: readerModel,
      syncArtifact: syncArtifact,
      source: ReaderContentSource.api,
      audioUrls: resolvedAudio.audioUrls,
      totalAudioAssets: resolvedAudio.totalAudioAssets,
      cachedAudioAssets: resolvedAudio.cachedAudioAssets,
      hasCompleteOfflineAudio: resolvedAudio.hasCompleteOfflineAudio,
      statusMessage: _apiAudioStatusMessage(resolvedAudio),
      audioCachedAt: resolvedAudio.updatedAt,
    );
  }

  Future<AudioDownloadResult> downloadAudio({
    required String projectId,
    void Function(AudioDownloadProgress progress)? onProgress,
  }) async {
    final projectDetail = await _apiClient.fetchProjectDetail(projectId);
    final syncArtifact = await _apiClient.fetchSyncArtifact(projectId);
    final descriptors =
        _audioDescriptorsFromProject(
          projectDetail: projectDetail,
          syncArtifact: syncArtifact,
        ).map(
          (assetId, descriptor) => MapEntry(
            assetId,
            descriptor.downloadUrl.isNotEmpty
                ? descriptor
                : AudioDownloadDescriptor(
                    assetId: descriptor.assetId,
                    filename: descriptor.filename,
                    downloadUrl: _apiClient.assetContentUrl(
                      projectId: projectId,
                      assetId: descriptor.assetId,
                    ),
                    sizeBytes: descriptor.sizeBytes,
                    checksumSha256: descriptor.checksumSha256,
                    durationMs: descriptor.durationMs,
                  ),
          ),
        );
    if (descriptors.isEmpty) {
      return const AudioDownloadResult(downloadedAssets: 0, totalAssets: 0);
    }

    final cachedAudio = await _audioCache.cacheProjectAudio(
      projectId: projectId,
      assets: descriptors.values.toList(growable: false),
      downloadAsset: (asset, destinationPath, reportProgress) async {
        await _apiClient.downloadFile(
          url: asset.downloadUrl,
          savePath: destinationPath,
          onReceiveProgress: reportProgress,
        );
      },
      onProgress: onProgress,
    );
    return AudioDownloadResult(
      downloadedAssets: cachedAudio.assetCount,
      totalAssets: descriptors.length,
    );
  }

  Future<void> removeDownloadedAudio(String projectId) {
    return _audioCache.removeProject(projectId);
  }

  Future<ReaderProjectBundle?> _loadCachedBundleIfAvailable({
    required String projectId,
    required DioException error,
  }) async {
    if (!_shouldUseCachedOffline(error)) {
      return null;
    }

    final cached = await _readCachedProject(projectId);
    if (cached == null) {
      return null;
    }

    final resolvedAudio = await _resolveAudioSources(
      projectId: projectId,
      syncArtifact: cached.syncArtifact,
      projectDetail: null,
      allowRemoteFallback: false,
    );

    return ReaderProjectBundle(
      projectId: projectId,
      readerModel: cached.readerModel,
      syncArtifact: cached.syncArtifact,
      source: ReaderContentSource.offlineCache,
      audioUrls: resolvedAudio.audioUrls,
      totalAudioAssets: resolvedAudio.totalAudioAssets,
      cachedAudioAssets: resolvedAudio.cachedAudioAssets,
      hasCompleteOfflineAudio: resolvedAudio.hasCompleteOfflineAudio,
      cachedAt: cached.cachedAt,
      audioCachedAt: resolvedAudio.updatedAt,
      statusMessage: _offlineCacheMessage(
        cached.cachedAt,
        hasCompleteOfflineAudio: resolvedAudio.hasCompleteOfflineAudio,
        cachedAudioAssets: resolvedAudio.cachedAudioAssets,
        totalAudioAssets: resolvedAudio.totalAudioAssets,
      ),
    );
  }

  Future<CachedReaderProject?> _readCachedProject(String projectId) async {
    try {
      return await _artifactCache.loadProject(projectId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeCachedArtifacts({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  }) async {
    try {
      await _artifactCache.storeProject(
        projectId: projectId,
        readerModel: readerModel,
        syncArtifact: syncArtifact,
      );
    } catch (_) {
      // Cache failures should not block the live API path.
    }
  }

  ReaderProjectBundle _demoFallbackBundle() {
    return ReaderProjectBundle(
      projectId: 'demo-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
      source: ReaderContentSource.demoFallback,
      audioUrls: const [],
      totalAudioAssets: 0,
      cachedAudioAssets: 0,
      hasCompleteOfflineAudio: false,
      statusMessage: 'Demo data loaded because the API is unavailable.',
    );
  }

  Future<ReaderProjectBundle> _buildBackendStateBundle({
    required String projectId,
    required DioException error,
  }) async {
    try {
      final project = await _apiClient.fetchProjectDetail(projectId);
      final title = project['title']?.toString() ?? 'Sync project';
      final latestJob = _asMap(project['latest_job']);
      final latestStatus = latestJob['status']?.toString();
      final source = _sourceFromProjectState(
        error: error,
        latestStatus: latestStatus,
      );
      return ReaderProjectBundle(
        projectId: projectId,
        readerModel: _placeholderReaderModel(
          projectId: projectId,
          title: title,
        ),
        syncArtifact: _emptySyncArtifact(projectId),
        source: source,
        audioUrls: const [],
        totalAudioAssets: 0,
        cachedAudioAssets: 0,
        hasCompleteOfflineAudio: false,
        statusMessage: _statusMessage(
          error: error,
          latestStatus: latestStatus,
          projectTitle: title,
        ),
      );
    } on DioException catch (projectError) {
      throw ReaderProjectLoadException(_userFacingMessage(projectError));
    }
  }

  Future<_ResolvedAudioSources> _resolveAudioSources({
    required String projectId,
    required SyncArtifact syncArtifact,
    required Map<String, dynamic>? projectDetail,
    required bool allowRemoteFallback,
  }) async {
    final descriptors = _audioDescriptorsFromProject(
      projectDetail: projectDetail,
      syncArtifact: syncArtifact,
    );
    final expectedIds = [for (final item in syncArtifact.audio) item.assetId];
    final cachedAudio = await _audioCache.inspectProject(
      projectId,
      expectedAssetIds: expectedIds,
    );

    final audioUrls = <String>[];
    var cachedCount = 0;
    for (final item in syncArtifact.audio) {
      final cachedAsset = cachedAudio.assetsById[item.assetId];
      if (cachedAsset != null) {
        audioUrls.add(cachedAsset.fileUri);
        cachedCount += 1;
        continue;
      }
      if (!allowRemoteFallback) {
        continue;
      }
      final descriptor = descriptors[item.assetId];
      if (descriptor != null) {
        audioUrls.add(descriptor.downloadUrl);
      } else {
        audioUrls.add(
          _apiClient.assetContentUrl(
            projectId: projectId,
            assetId: item.assetId,
          ),
        );
      }
    }

    return _ResolvedAudioSources(
      audioUrls: audioUrls,
      totalAudioAssets: syncArtifact.audio.length,
      cachedAudioAssets: cachedCount,
      hasCompleteOfflineAudio:
          syncArtifact.audio.isNotEmpty &&
          cachedCount == syncArtifact.audio.length,
      updatedAt: cachedAudio.updatedAt,
    );
  }
}

String _offlineCacheMessage(
  DateTime cachedAt, {
  required bool hasCompleteOfflineAudio,
  required int cachedAudioAssets,
  required int totalAudioAssets,
}) {
  final timestamp = cachedAt.toLocal().toIso8601String();
  if (hasCompleteOfflineAudio) {
    return 'Cached reader artifacts and downloaded audio loaded from this device. Cached at $timestamp.';
  }
  if (totalAudioAssets > 0 && cachedAudioAssets > 0) {
    return 'Cached reader artifacts loaded from this device. $cachedAudioAssets of $totalAudioAssets audio files are downloaded locally. Cached at $timestamp.';
  }
  return 'Cached reader artifacts loaded from this device. Audio streaming stays disabled until the backend is reachable again. Cached at $timestamp.';
}

String? _apiAudioStatusMessage(_ResolvedAudioSources audio) {
  if (audio.totalAudioAssets == 0) {
    return 'Synced text is available, but no playable audio asset was returned by the backend.';
  }
  if (audio.hasCompleteOfflineAudio) {
    return 'Downloaded audio is available for offline playback on this device.';
  }
  if (audio.cachedAudioAssets > 0) {
    return '${audio.cachedAudioAssets} of ${audio.totalAudioAssets} audio files are downloaded locally. The rest will stream from the backend.';
  }
  return null;
}

bool _shouldUseCachedOffline(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.unknown:
      return true;
    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode ?? 0;
      return statusCode >= 500;
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
      return false;
  }
}

bool _shouldUseDemoFallback({
  required String projectId,
  required DioException error,
}) {
  if (projectId != defaultProjectId) {
    return false;
  }

  switch (error.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.unknown:
      return true;
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
  }
}

String _userFacingMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode == 404) {
    return 'Project artifacts are not ready yet. Upload the EPUB and finish an alignment job first.';
  }
  if (statusCode == 409) {
    return 'Project assets exist, but the requested reader or sync artifact is not available yet.';
  }
  return 'The backend project could not be loaded. ${error.message ?? 'Retry after the API finishes processing.'}';
}

ReaderContentSource _sourceFromProjectState({
  required DioException error,
  required String? latestStatus,
}) {
  if (latestStatus == 'queued' || latestStatus == 'running') {
    return ReaderContentSource.artifactPending;
  }
  if (latestStatus == 'failed' || latestStatus == 'cancelled') {
    return ReaderContentSource.projectError;
  }

  final statusCode = error.response?.statusCode;
  if (statusCode == 404 || statusCode == 409) {
    return ReaderContentSource.artifactPending;
  }
  return ReaderContentSource.projectError;
}

String _statusMessage({
  required DioException error,
  required String? latestStatus,
  required String projectTitle,
}) {
  if (latestStatus == 'queued' || latestStatus == 'running') {
    return '$projectTitle is still processing. Keep this screen open or refresh after alignment completes.';
  }
  if (latestStatus == 'failed') {
    return 'The latest alignment job for $projectTitle failed. Re-run the job after checking backend logs.';
  }
  if (latestStatus == 'cancelled') {
    return 'The latest alignment job for $projectTitle was cancelled before artifacts were generated.';
  }

  final statusCode = error.response?.statusCode;
  if (statusCode == 404) {
    return 'The backend project exists, but reader artifacts are not ready yet. Upload the EPUB and finish an alignment job first.';
  }
  if (statusCode == 409) {
    return 'The project is present, but the requested reader or sync artifact has not been generated yet.';
  }
  return 'The backend project could not provide reader data yet. Retry after the API finishes processing.';
}

ReaderModel _placeholderReaderModel({
  required String projectId,
  required String title,
}) {
  return ReaderModel(
    bookId: projectId,
    title: title,
    language: null,
    sections: const [],
  );
}

SyncArtifact _emptySyncArtifact(String projectId) {
  return SyncArtifact(
    version: '1.0',
    bookId: projectId,
    language: null,
    audio: const [],
    contentStartMs: 0,
    contentEndMs: 0,
    tokens: const [],
    gaps: const [],
  );
}

Map<String, AudioDownloadDescriptor> _audioDescriptorsFromProject({
  required Map<String, dynamic>? projectDetail,
  required SyncArtifact syncArtifact,
}) {
  final assets = _assetMaps(projectDetail?['assets']);
  final assetsById = {
    for (final asset in assets)
      if (asset['asset_id']?.toString().isNotEmpty ?? false)
        asset['asset_id']!.toString(): asset,
  };

  final descriptors = <String, AudioDownloadDescriptor>{};
  for (final item in syncArtifact.audio) {
    final asset = assetsById[item.assetId];
    if (asset == null) {
      continue;
    }
    descriptors[item.assetId] = AudioDownloadDescriptor(
      assetId: item.assetId,
      filename: asset['filename']?.toString() ?? '${item.assetId}.bin',
      downloadUrl: asset['download_url']?.toString() ?? '',
      sizeBytes: _asInt(asset['size_bytes']),
      checksumSha256: asset['checksum_sha256']?.toString(),
      durationMs: _asInt(asset['duration_ms']),
    );
  }
  return descriptors;
}

List<Map<String, dynamic>> _assetMaps(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map(_asMap).toList(growable: false);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

class _ResolvedAudioSources {
  const _ResolvedAudioSources({
    required this.audioUrls,
    required this.totalAudioAssets,
    required this.cachedAudioAssets,
    required this.hasCompleteOfflineAudio,
    required this.updatedAt,
  });

  final List<String> audioUrls;
  final int totalAudioAssets;
  final int cachedAudioAssets;
  final bool hasCompleteOfflineAudio;
  final DateTime? updatedAt;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
