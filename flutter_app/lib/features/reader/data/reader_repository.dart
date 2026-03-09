import 'package:dio/dio.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
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

class ReaderProjectBundle {
  const ReaderProjectBundle({
    required this.projectId,
    required this.readerModel,
    required this.syncArtifact,
    required this.source,
    required this.audioUrls,
    this.statusMessage,
    this.cachedAt,
  });

  final String projectId;
  final ReaderModel readerModel;
  final SyncArtifact syncArtifact;
  final ReaderContentSource source;
  final List<String> audioUrls;
  final String? statusMessage;
  final DateTime? cachedAt;
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
  }) : _apiClient = apiClient,
       _artifactCache = artifactCache;

  final SyncApiClient _apiClient;
  final ReaderArtifactCache _artifactCache;

  Future<ReaderProjectBundle> loadProject(String projectId) async {
    ReaderModel readerModel;
    SyncArtifact syncArtifact;

    try {
      readerModel = await _apiClient.fetchReaderModel(projectId);
      syncArtifact = await _apiClient.fetchSyncArtifact(projectId);
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

    final audioUrls = [
      for (final item in syncArtifact.audio)
        _apiClient.assetContentUrl(projectId: projectId, assetId: item.assetId),
    ];

    return ReaderProjectBundle(
      projectId: projectId,
      readerModel: readerModel,
      syncArtifact: syncArtifact,
      source: ReaderContentSource.api,
      audioUrls: audioUrls,
      statusMessage: audioUrls.isEmpty
          ? 'Synced text is available, but no playable audio asset was returned by the backend.'
          : null,
    );
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

    return ReaderProjectBundle(
      projectId: projectId,
      readerModel: cached.readerModel,
      syncArtifact: cached.syncArtifact,
      source: ReaderContentSource.offlineCache,
      audioUrls: const [],
      cachedAt: cached.cachedAt,
      statusMessage: _offlineCacheMessage(cached.cachedAt),
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
}

String _offlineCacheMessage(DateTime cachedAt) {
  final timestamp = cachedAt.toLocal().toIso8601String();
  return 'Cached reader artifacts loaded from this device. Audio streaming stays disabled until the backend is reachable again. Cached at $timestamp.';
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

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}
