import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_audio_download_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class _FakeDownloadRepository extends ReaderRepository {
  _FakeDownloadRepository()
    : super(apiClient: SyncApiClient(baseUrl: 'http://localhost'));

  bool removed = false;

  @override
  Future<AudioDownloadResult> downloadAudio({
    required String projectId,
    void Function(AudioDownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const AudioDownloadProgress(
        completedAssets: 0,
        totalAssets: 2,
        activeAssetId: 'audio-part-1',
        receivedBytes: 50,
        totalBytes: 100,
      ),
    );
    onProgress?.call(
      const AudioDownloadProgress(
        completedAssets: 1,
        totalAssets: 2,
        activeAssetId: 'audio-part-2',
        receivedBytes: 100,
        totalBytes: 100,
      ),
    );
    return const AudioDownloadResult(downloadedAssets: 2, totalAssets: 2);
  }

  @override
  Future<void> removeDownloadedAudio(String projectId) async {
    removed = true;
  }
}

void main() {
  test(
    'download controller tracks active asset and final completion',
    () async {
      final repository = _FakeDownloadRepository();
      final container = ProviderContainer(
        overrides: [
          projectIdProvider.overrideWith((ref) async => 'demo-book'),
          readerRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(readerAudioDownloadProvider.notifier);
      await controller.downloadCurrentProject();

      final state = container.read(readerAudioDownloadProvider);
      expect(state.status, ReaderAudioDownloadStatus.succeeded);
      expect(state.progress, 1);
      expect(state.completedAssets, 2);
      expect(state.totalAssets, 2);
      expect(state.activeAssetId, isNull);
      expect(state.message, contains('Downloaded 2 of 2 audio files'));
    },
  );

  test('remove controller resets counts after local audio removal', () async {
    final repository = _FakeDownloadRepository();
    final container = ProviderContainer(
      overrides: [
        projectIdProvider.overrideWith((ref) async => 'demo-book'),
        readerRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(readerAudioDownloadProvider.notifier);
    await controller.removeCurrentProjectAudio();

    final state = container.read(readerAudioDownloadProvider);
    expect(repository.removed, isTrue);
    expect(state.status, ReaderAudioDownloadStatus.succeeded);
    expect(state.completedAssets, 0);
    expect(state.totalAssets, 0);
    expect(state.message, contains('Removed downloaded audio'));
  });
}
