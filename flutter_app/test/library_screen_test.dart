import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/presentation/library_screen.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';

class _MemoryRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
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
  ];

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {}
}

class _MemoryReaderLocationStore implements ReaderLocationStore {
  @override
  Future<ReaderLocationSnapshot?> loadProject(String projectId) async => null;

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async => [
    ReaderLocationSnapshot(
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
  Future<void> removeProject(String projectId) async {}

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
      title: 'Demo Project',
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
            readerLocationStoreProvider.overrideWithValue(
              _MemoryReaderLocationStore(),
            ),
          ],
          child: MaterialApp(
            theme: SyncTheme.paper(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Import Book'), findsOneWidget);
      expect(find.text('Choose EPUB'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Processing Queue'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Processing Queue'), findsOneWidget);
      expect(find.text('Recent Server Projects'), findsOneWidget);
      expect(find.textContaining('Running'), findsWidgets);
      expect(find.text('Details'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Recent Books'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent Books'), findsOneWidget);
      expect(find.textContaining('Loomings'), findsOneWidget);
    },
  );
}
