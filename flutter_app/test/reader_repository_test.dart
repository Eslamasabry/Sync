import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
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

class _FakeReaderAudioCache implements ReaderAudioCache {
  CachedProjectAudio cached = const CachedProjectAudio(
    assetsById: {},
    updatedAt: null,
  );

  @override
  Future<CachedProjectAudio> inspectProject(
    String projectId, {
    Iterable<String>? expectedAssetIds,
  }) async => cached;

  @override
  Future<CachedProjectAudio> cacheProjectAudio({
    required String projectId,
    required List<AudioDownloadDescriptor> assets,
    required Future<void> Function(
      AudioDownloadDescriptor asset,
      String destinationPath,
      void Function(int received, int total) reportProgress,
    )
    downloadAsset,
    void Function(AudioDownloadProgress progress)? onProgress,
  }) async => cached;

  @override
  Future<void> removeProject(String projectId) async {}
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

  @override
  Future<Map<String, dynamic>> fetchProjectDetail(String projectId) async {
    return {
      'project_id': projectId,
      'title': demoReaderModel.title,
      'language': 'en',
      'status': 'created',
      'assets': [
        {
          'asset_id': 'audio-demo',
          'kind': 'audio',
          'filename': 'audio-demo.wav',
          'content_type': 'audio/wav',
          'upload_mode': 'multipart',
          'status': 'uploaded',
          'size_bytes': 1024,
          'checksum_sha256': 'a' * 64,
          'duration_ms': 4900,
          'download_url': 'http://localhost/audio-demo.wav',
          'created_at': '2026-03-09T00:00:00Z',
        },
      ],
      'latest_job': null,
    };
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

class _MixedAudioSyncApiClient extends SyncApiClient {
  _MixedAudioSyncApiClient() : super(baseUrl: 'http://localhost');

  @override
  Future<ReaderModel> fetchReaderModel(String projectId) async {
    return demoReaderModel;
  }

  @override
  Future<SyncArtifact> fetchSyncArtifact(String projectId) async {
    return SyncArtifact.fromJson({
      'version': '1.0',
      'book_id': projectId,
      'language': 'en',
      'audio': [
        {'asset_id': 'audio-local', 'offset_ms': 0, 'duration_ms': 2500},
        {'asset_id': 'audio-remote', 'offset_ms': 2500, 'duration_ms': 2400},
      ],
      'content_start_ms': 600,
      'content_end_ms': 4300,
      'tokens': demoSyncArtifact.toJson()['tokens'],
      'gaps': demoSyncArtifact.toJson()['gaps'],
    });
  }

  @override
  Future<Map<String, dynamic>> fetchProjectDetail(String projectId) async {
    return {
      'project_id': projectId,
      'title': demoReaderModel.title,
      'language': 'en',
      'status': 'created',
      'assets': [
        {
          'asset_id': 'audio-local',
          'kind': 'audio',
          'filename': 'audio-local.wav',
          'content_type': 'audio/wav',
          'upload_mode': 'multipart',
          'status': 'uploaded',
          'size_bytes': 1024,
          'checksum_sha256': 'a' * 64,
          'duration_ms': 2500,
          'download_url': 'http://localhost/audio-local.wav',
          'created_at': '2026-03-09T00:00:00Z',
        },
        {
          'asset_id': 'audio-remote',
          'kind': 'audio',
          'filename': 'audio-remote.wav',
          'content_type': 'audio/wav',
          'upload_mode': 'multipart',
          'status': 'uploaded',
          'size_bytes': 2048,
          'checksum_sha256': 'b' * 64,
          'duration_ms': 2400,
          'download_url': 'http://localhost/audio-remote.wav',
          'created_at': '2026-03-09T00:00:00Z',
        },
      ],
      'latest_job': null,
    };
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
      expect(bundle.totalAudioAssets, 1);
      expect(bundle.cachedAudioAssets, 0);
      expect(bundle.audioUrls, isNotEmpty);
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

  test(
    'prefers cached local audio when a project has downloaded files',
    () async {
      final audioCache = _FakeReaderAudioCache()
        ..cached = CachedProjectAudio(
          assetsById: {
            'audio-demo': CachedAudioAsset(
              assetId: 'audio-demo',
              filePath: '/tmp/audio-demo.wav',
              cachedAt: DateTime.utc(2026, 3, 9, 12),
              sizeBytes: 1024,
              checksumSha256: 'a' * 64,
              durationMs: 4900,
            ),
          },
          updatedAt: DateTime.utc(2026, 3, 9, 12),
        );

      final repository = ReaderRepository(
        apiClient: _SuccessfulSyncApiClient(),
        artifactCache: _FakeReaderArtifactCache(),
        audioCache: audioCache,
      );

      final bundle = await repository.loadProject('demo-book');

      expect(bundle.hasCompleteOfflineAudio, isTrue);
      expect(bundle.cachedAudioAssets, 1);
      expect(bundle.audioUrls.single, startsWith('file:///tmp/audio-demo.wav'));
      expect(bundle.statusMessage, contains('offline playback'));
      expect(bundle.audioCachedAt, DateTime.utc(2026, 3, 9, 12));
      expect(
        bundle.playbackSourceMode(usesNativeAudio: true),
        ReaderPlaybackSourceMode.offlineCached,
      );
    },
  );

  test('keeps cached audio first and streams remaining files', () async {
    final audioCache = _FakeReaderAudioCache()
      ..cached = CachedProjectAudio(
        assetsById: {
          'audio-local': CachedAudioAsset(
            assetId: 'audio-local',
            filePath: '/tmp/audio-local.wav',
            cachedAt: DateTime.utc(2026, 3, 9, 12),
            sizeBytes: 1024,
            checksumSha256: 'a' * 64,
            durationMs: 2500,
          ),
        },
        updatedAt: DateTime.utc(2026, 3, 9, 12),
      );

    final repository = ReaderRepository(
      apiClient: _MixedAudioSyncApiClient(),
      artifactCache: _FakeReaderArtifactCache(),
      audioCache: audioCache,
    );

    final bundle = await repository.loadProject('demo-book');

    expect(bundle.totalAudioAssets, 2);
    expect(bundle.cachedAudioAssets, 1);
    expect(bundle.hasCompleteOfflineAudio, isFalse);
    expect(
      bundle.playbackSourceMode(usesNativeAudio: true),
      ReaderPlaybackSourceMode.mixed,
    );
    expect(bundle.audioUrls.first, startsWith('file:///tmp/audio-local.wav'));
    expect(bundle.audioUrls.last, 'http://localhost/audio-remote.wav');
    expect(bundle.audioCachedAt, DateTime.utc(2026, 3, 9, 12));
  });

  test('uses backend audio URLs when no local audio is cached', () async {
    final repository = ReaderRepository(
      apiClient: _SuccessfulSyncApiClient(),
      artifactCache: _FakeReaderArtifactCache(),
      audioCache: _FakeReaderAudioCache(),
    );

    final bundle = await repository.loadProject('demo-book');

    expect(bundle.cachedAudioAssets, 0);
    expect(bundle.totalAudioAssets, 1);
    expect(
      bundle.playbackSourceMode(usesNativeAudio: true),
      ReaderPlaybackSourceMode.remoteStreaming,
    );
    expect(bundle.audioUrls.single, 'http://localhost/audio-demo.wav');
    expect(bundle.audioCachedAt, isNull);
  });
}
