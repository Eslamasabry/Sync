import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

class _FakeReaderArtifactCache implements ReaderArtifactCache {
  CachedReaderProject? cached;
  int storeCount = 0;

  @override
  Future<CachedReaderProject?> loadProject(String projectId) async => cached;

  @override
  Future<void> storeProject({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  }) async {
    storeCount += 1;
    cached = CachedReaderProject(
      readerModel: readerModel,
      syncArtifact: syncArtifact,
      cachedAt: DateTime.utc(2026, 3, 9, 12),
    );
  }
}

class _SuccessfulSyncApiClient extends SyncApiClient {
  _SuccessfulSyncApiClient() : super(baseUrl: 'http://localhost');

  @override
  Future<ReaderModel> fetchReaderModel(String projectId) async {
    return demoReaderModel;
  }

  @override
  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
    return demoSyncArtifact;
  }
}

class _OfflineSyncApiClient extends SyncApiClient {
  _OfflineSyncApiClient() : super(baseUrl: 'http://localhost');

  DioException _error(String path) {
    return DioException(
      requestOptions: RequestOptions(path: path),
      message: 'Connection failed',
      type: DioExceptionType.connectionError,
    );
  }

  @override
  Future<ReaderModel> fetchReaderModel(String projectId) async {
    throw _error('/projects/$projectId/reader-model');
  }

  @override
  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
    throw _error('/projects/$projectId/sync');
  }
}

void main() {
  test(
    'writes normalized artifacts into cache after a successful load',
    () async {
      final cache = _FakeReaderArtifactCache();
      final repository = ReaderRepository(
        apiClient: _SuccessfulSyncApiClient(),
        artifactCache: cache,
      );

      final bundle = await repository.loadProject('demo-book');

      expect(bundle.source, ReaderContentSource.api);
      expect(cache.storeCount, 1);
      expect(cache.cached, isNotNull);
      expect(cache.cached!.readerModel.title, demoReaderModel.title);
      expect(cache.cached!.syncArtifact.tokens, isNotEmpty);
    },
  );

  test('returns cached offline data when the backend is unavailable', () async {
    final cache = _FakeReaderArtifactCache()
      ..cached = CachedReaderProject(
        readerModel: demoReaderModel,
        syncArtifact: demoSyncArtifact,
        cachedAt: DateTime.utc(2026, 3, 9, 12),
      );
    final repository = ReaderRepository(
      apiClient: _OfflineSyncApiClient(),
      artifactCache: cache,
    );

    final bundle = await repository.loadProject('demo-book');

    expect(bundle.source, ReaderContentSource.offlineCache);
    expect(bundle.audioUrls, isEmpty);
    expect(bundle.readerModel.title, demoReaderModel.title);
    expect(bundle.statusMessage, contains('Cached reader artifacts loaded'));
  });
}
