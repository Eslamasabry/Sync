import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_audio_download_controller.dart';

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
          runtimeConnectionSettingsProvider.overrideWith(
            () => _FixedRuntimeConnectionSettingsController(
              const RuntimeConnectionSettings(
                apiBaseUrl: 'http://sync.example.test/v1',
                projectId: 'demo-book',
                authToken: '',
              ),
            ),
          ),
          readerRepositoryFactoryProvider.overrideWithValue(
            (settings) => repository,
          ),
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
      expect(state.projectId, 'demo-book');
      expect(state.activeAssetId, isNull);
      expect(
        state.message,
        contains('Downloaded 2 of 2 audio files for demo-book'),
      );
    },
  );

  test('remove controller resets counts after local audio removal', () async {
    final repository = _FakeDownloadRepository();
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsProvider.overrideWith(
          () => _FixedRuntimeConnectionSettingsController(
            const RuntimeConnectionSettings(
              apiBaseUrl: 'http://sync.example.test/v1',
              projectId: 'demo-book',
              authToken: '',
            ),
          ),
        ),
        readerRepositoryFactoryProvider.overrideWithValue(
          (settings) => repository,
        ),
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
    expect(state.projectId, 'demo-book');
    expect(state.message, contains('Removed downloaded audio for demo-book'));
  });

  test(
    'download controller can operate on an arbitrary saved project',
    () async {
      final container = ProviderContainer(
        overrides: [
          readerRepositoryFactoryProvider.overrideWithValue(
            (settings) => _FakeDownloadRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(readerAudioDownloadProvider.notifier);
      await controller.downloadProject(
        const RuntimeConnectionSettings(
          apiBaseUrl: 'http://sync.example.test/v1',
          projectId: 'mars-book',
          authToken: '',
        ),
      );

      final state = container.read(readerAudioDownloadProvider);
      expect(state.status, ReaderAudioDownloadStatus.succeeded);
      expect(state.projectId, 'mars-book');
      expect(state.message, contains('mars-book'));
    },
  );
}

class _FixedRuntimeConnectionSettingsController
    extends RuntimeConnectionSettingsController {
  _FixedRuntimeConnectionSettingsController(this._settings);

  final RuntimeConnectionSettings _settings;

  @override
  Future<RuntimeConnectionSettings> build() async => _settings;
}
