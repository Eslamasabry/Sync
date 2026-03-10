import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/presentation/library_screen.dart';
import 'package:sync_flutter/features/library/state/library_import_controller.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class _MemoryRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  RuntimeConnectionSettings? saved;

  @override
  Future<void> clear() async {}

  @override
  Future<RuntimeConnectionSettings?> load() async =>
      const RuntimeConnectionSettings(
        apiBaseUrl: 'http://sync.example.test/v1',
        projectId: 'demo-book',
        authToken: '',
      );

  @override
  Future<List<RuntimeConnectionSettings>> loadRecent() async => const [
    RuntimeConnectionSettings(
      apiBaseUrl: 'http://sync.example.test/v1',
      projectId: 'demo-book',
      authToken: '',
    ),
    RuntimeConnectionSettings(
      apiBaseUrl: 'http://sync.example.test/v1',
      projectId: 'mars-book',
      authToken: '',
    ),
  ];

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {
    saved = settings;
  }

  @override
  Future<void> remove(RuntimeConnectionSettings settings) async {}
}

class _MemoryReaderLocationStore implements ReaderLocationStore {
  @override
  Future<ReaderLocationSnapshot?> loadProject(
    String projectId, {
    String? apiBaseUrl,
  }) async => null;

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async => [
    ReaderLocationSnapshot(
      apiBaseUrl: 'http://sync.example.test/v1',
      authToken: 'snapshot-token',
      projectId: 'demo-book',
      positionMs: 2300,
      totalDurationMs: 4000,
      contentStartMs: 500,
      contentEndMs: 3800,
      progressFraction: 0.52,
      updatedAt: DateTime.utc(2026, 3, 9, 12),
      sectionTitle: 'Loomings',
    ),
  ];

  @override
  Future<void> removeProject(String projectId, {String? apiBaseUrl}) async {}

  @override
  Future<void> storeProject(ReaderLocationSnapshot snapshot) async {}
}

class _FakeLibraryProjectSummaryLoader implements LibraryProjectSummaryLoader {
  const _FakeLibraryProjectSummaryLoader();

  @override
  Future<LibraryProjectSnapshot> load(
    RuntimeConnectionSettings settings,
  ) async {
    return LibraryProjectSnapshot(
      settings: settings,
      title: settings.projectId == 'mars-book'
          ? 'Mars Project'
          : 'Demo Project',
      language: 'en',
      projectStatus: 'ready',
      assetCount: 2,
      audioAssetCount: 1,
      epubAssetCount: 1,
      totalSizeBytes: 3 * 1024 * 1024,
      updatedAt: DateTime.utc(2026, 3, 9, 12, 30),
      latestJobStatus: 'running',
      latestJobStage: 'matching',
      latestJobPercent: 72,
      latestJobAttempt: 1,
    );
  }
}

class _MemoryReaderArtifactCache implements ReaderArtifactCache {
  @override
  Future<CachedReaderProject?> loadProject(String projectId) async =>
      CachedReaderProject(
        readerModel: ReaderModel(
          bookId: projectId,
          title: 'Cached Project',
          language: 'en',
          sections: const [],
        ),
        syncArtifact: SyncArtifact(
          version: '1.0',
          bookId: projectId,
          language: 'en',
          audio: const [],
          contentStartMs: 0,
          contentEndMs: 0,
          tokens: const [],
          gaps: const [],
        ),
        cachedAt: DateTime.utc(2026, 3, 9, 10),
      );

  @override
  Future<void> storeProject({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  }) async {}
}

class _MemoryReaderAudioCache implements ReaderAudioCache {
  @override
  Future<CachedProjectAudio> inspectProject(
    String projectId, {
    Iterable<String>? expectedAssetIds,
  }) async {
    return CachedProjectAudio(
      assetsById: {
        'audio-1': CachedAudioAsset(
          assetId: 'audio-1',
          filePath: '/tmp/audio-1.mp3',
          cachedAt: DateTime.utc(2026, 3, 9, 11),
          sizeBytes: 1024 * 1024,
        ),
      },
      updatedAt: DateTime.utc(2026, 3, 9, 11),
    );
  }

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
  }) async => inspectProject(projectId);

  @override
  Future<void> removeProject(String projectId) async {}
}

class _ScannedLibraryImportController extends LibraryImportController {
  @override
  LibraryImportState build() {
    return LibraryImportState(
      status: LibraryImportStatus.ready,
      title: '',
      language: 'en',
      audioFiles: const <ImportPickedFile>[],
      scannedDeviceBooks: [
        ImportBookCandidate(
          title: 'The Time Machine',
          author: 'H. G. Wells',
          directoryLabel: 'Audiobooks',
          coverBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=',
          ),
          epubFile: const ImportPickedFile(
            name: 'The Time Machine.epub',
            sizeBytes: 1200,
            path: '/books/The Time Machine.epub',
          ),
          audioFiles: const [
            ImportPickedFile(
              name: 'The Time Machine - Chapter 01.m4b',
              sizeBytes: 3 * 1024 * 1024,
              path: '/books/The Time Machine - Chapter 01.m4b',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'library screen shows import workspace and recent local history',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConnectionSettingsStorageProvider.overrideWithValue(
              _MemoryRuntimeConnectionSettingsStorage(),
            ),
            libraryProjectSummaryLoaderProvider.overrideWithValue(
              const _FakeLibraryProjectSummaryLoader(),
            ),
            readerArtifactCacheProvider.overrideWithValue(
              _MemoryReaderArtifactCache(),
            ),
            readerAudioCacheProvider.overrideWithValue(
              _MemoryReaderAudioCache(),
            ),
            readerLocationStoreProvider.overrideWithValue(
              _MemoryReaderLocationStore(),
            ),
            libraryServerConnectionProvider.overrideWith(
              (ref) async => const LibraryServerConnectionState(
                isReady: true,
                headline: 'Server ready',
                detail: 'Ready for uploads.',
              ),
            ),
            libraryServerProjectsProvider.overrideWith(
              (ref) async => const [
                ProjectListItem(
                  projectId: 'demo-book',
                  title: 'Demo Project',
                  status: 'created',
                  assetCount: 2,
                  audioAssetCount: 1,
                  language: 'en',
                  latestJob: AlignmentJobResult(
                    jobId: 'job-1',
                    status: 'completed',
                    reusedExisting: false,
                    attemptNumber: 1,
                  ),
                ),
                ProjectListItem(
                  projectId: 'mars-book',
                  title: 'Mars Project',
                  status: 'created',
                  assetCount: 2,
                  audioAssetCount: 1,
                  language: 'en',
                  latestJob: AlignmentJobResult(
                    jobId: 'job-2',
                    status: 'running',
                    reusedExisting: false,
                    attemptNumber: 1,
                  ),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: SyncTheme.paper(),
            home: const Scaffold(body: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final gettingReady = find.text('Getting Ready', skipOffstage: false);
      final yourBooks = find.text('Your Books', skipOffstage: false);
      final booksOnDevice = find.text(
        'Books on This Device',
        skipOffstage: false,
      );

      expect(
        find.text('Add a Book', skipOffstage: false),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.text('Continue Reading', skipOffstage: false),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Choose EPUB', skipOffstage: false), findsOneWidget);
      await tester.scrollUntilVisible(yourBooks, 220, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(yourBooks, findsOneWidget);
      expect(find.text('Demo Project'), findsWidgets);
      expect(find.textContaining('Ready'), findsWidgets);
      await tester.scrollUntilVisible(
        gettingReady,
        220,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(gettingReady, findsOneWidget);
      await tester.scrollUntilVisible(
        booksOnDevice,
        220,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(booksOnDevice, findsOneWidget);
      expect(find.textContaining('Loomings'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('Running'), findsWidgets);
    },
  );

  testWidgets('library surfaces scanned folder books as a top-level section', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryImportProvider.overrideWith(
            _ScannedLibraryImportController.new,
          ),
          runtimeConnectionSettingsStorageProvider.overrideWithValue(
            _MemoryRuntimeConnectionSettingsStorage(),
          ),
          libraryProjectSummaryLoaderProvider.overrideWithValue(
            const _FakeLibraryProjectSummaryLoader(),
          ),
          readerArtifactCacheProvider.overrideWithValue(
            _MemoryReaderArtifactCache(),
          ),
          readerAudioCacheProvider.overrideWithValue(_MemoryReaderAudioCache()),
          readerLocationStoreProvider.overrideWithValue(
            _MemoryReaderLocationStore(),
          ),
          libraryServerConnectionProvider.overrideWith(
            (ref) async => const LibraryServerConnectionState(
              isReady: true,
              headline: 'Server ready',
              detail: 'Ready for uploads.',
            ),
          ),
          libraryServerProjectsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: SyncTheme.paper(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final scannedShelf = find.text('Found in This Folder', skipOffstage: false);
    await tester.scrollUntilVisible(scannedShelf, 220, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(scannedShelf, findsOneWidget);
    expect(find.text('The Time Machine'), findsWidgets);
    expect(find.text('H. G. Wells'), findsOneWidget);
    expect(find.text('Use This'), findsOneWidget);
  });

  testWidgets('library promotes server setup before import when backend is not ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConnectionSettingsStorageProvider.overrideWithValue(
            _MemoryRuntimeConnectionSettingsStorage(),
          ),
          libraryProjectSummaryLoaderProvider.overrideWithValue(
            const _FakeLibraryProjectSummaryLoader(),
          ),
          readerArtifactCacheProvider.overrideWithValue(
            _MemoryReaderArtifactCache(),
          ),
          readerAudioCacheProvider.overrideWithValue(_MemoryReaderAudioCache()),
          readerLocationStoreProvider.overrideWithValue(
            _MemoryReaderLocationStore(),
          ),
          libraryServerConnectionProvider.overrideWith(
            (ref) async => const LibraryServerConnectionState(
              isReady: false,
              headline: 'Connect your server first',
              detail: 'Point the app at your self-hosted backend before importing.',
            ),
          ),
          libraryServerProjectsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: SyncTheme.paper(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Your Server', skipOffstage: false), findsWidgets);
    expect(find.text('Connect your server first'), findsWidgets);
    expect(find.text('Open Connection'), findsWidgets);
  });

  testWidgets(
    'recent book resume restores the saved auth token for its original server',
    (tester) async {
      final settingsStorage = _MemoryRuntimeConnectionSettingsStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConnectionSettingsStorageProvider.overrideWithValue(
              settingsStorage,
            ),
            libraryProjectSummaryLoaderProvider.overrideWithValue(
              const _FakeLibraryProjectSummaryLoader(),
            ),
            readerArtifactCacheProvider.overrideWithValue(
              _MemoryReaderArtifactCache(),
            ),
            readerAudioCacheProvider.overrideWithValue(
              _MemoryReaderAudioCache(),
            ),
            readerLocationStoreProvider.overrideWithValue(
              _MemoryReaderLocationStore(),
            ),
            libraryServerConnectionProvider.overrideWith(
              (ref) async => const LibraryServerConnectionState(
                isReady: true,
                headline: 'Server ready',
                detail: 'Ready for uploads.',
              ),
            ),
            libraryServerProjectsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: SyncTheme.paper(),
            home: const Scaffold(body: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final booksOnDevice = find.text(
        'Books on This Device',
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        booksOnDevice,
        220,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Continue'),
        220,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      expect(settingsStorage.saved, isNotNull);
      expect(settingsStorage.saved!.apiBaseUrl, 'http://sync.example.test/v1');
      expect(settingsStorage.saved!.projectId, 'demo-book');
      expect(settingsStorage.saved!.authToken, 'snapshot-token');
    },
  );
}
