import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';

final projectIdProvider = Provider<String>((ref) => defaultProjectId);

final syncApiClientProvider = Provider<SyncApiClient>(
  (ref) =>
      SyncApiClient(baseUrl: defaultApiBaseUrl, authToken: defaultApiAuthToken),
);

final readerArtifactCacheProvider = Provider<ReaderArtifactCache>(
  (ref) => const FileReaderArtifactCache(),
);

final readerAudioCacheProvider = Provider<ReaderAudioCache>(
  (ref) => const FileReaderAudioCache(),
);

final readerRepositoryProvider = Provider<ReaderRepository>(
  (ref) => ReaderRepository(
    apiClient: ref.watch(syncApiClientProvider),
    artifactCache: ref.watch(readerArtifactCacheProvider),
    audioCache: ref.watch(readerAudioCacheProvider),
  ),
);

final readerProjectProvider = FutureProvider<ReaderProjectBundle>((ref) async {
  final projectId = ref.watch(projectIdProvider);
  final repository = ref.watch(readerRepositoryProvider);
  final bundle = await repository.loadProject(projectId);
  await ref.read(readerPlaybackProvider.notifier).configureProject(bundle);
  return bundle;
});
