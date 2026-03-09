import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';

final projectIdProvider = FutureProvider<String>((ref) async {
  final settings = await ref.watch(runtimeConnectionSettingsProvider.future);
  return settings.projectId;
});

final syncApiClientProvider = FutureProvider<SyncApiClient>((ref) async {
  final settings = await ref.watch(runtimeConnectionSettingsProvider.future);
  return SyncApiClient(
    baseUrl: settings.apiBaseUrl,
    authToken: settings.authToken,
  );
});

final readerArtifactCacheProvider = Provider<ReaderArtifactCache>(
  (ref) => const FileReaderArtifactCache(),
);

final readerAudioCacheProvider = Provider<ReaderAudioCache>(
  (ref) => const FileReaderAudioCache(),
);

final readerRepositoryProvider = FutureProvider<ReaderRepository>((ref) async {
  final apiClient = await ref.watch(syncApiClientProvider.future);
  return ReaderRepository(
    apiClient: apiClient,
    artifactCache: ref.watch(readerArtifactCacheProvider),
    audioCache: ref.watch(readerAudioCacheProvider),
  );
});

final readerProjectProvider = FutureProvider<ReaderProjectBundle>((ref) async {
  final projectId = await ref.watch(projectIdProvider.future);
  final repository = await ref.watch(readerRepositoryProvider.future);
  final bundle = await repository.loadProject(projectId);
  await ref.read(readerPlaybackProvider.notifier).configureProject(bundle);
  return bundle;
});
