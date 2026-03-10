import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_storage_types.dart';
import 'package:sync_flutter/core/import/import_file_picker.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/features/library/state/library_import_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class _MemoryRuntimeConnectionSettingsStorage
    implements RuntimeConnectionSettingsStorage {
  RuntimeConnectionSettings? _settings = const RuntimeConnectionSettings(
    apiBaseUrl: 'http://sync.example.test/v1',
    projectId: 'demo-book',
    authToken: 'secret',
  );

  @override
  Future<void> clear() async {
    _settings = null;
  }

  @override
  Future<RuntimeConnectionSettings?> load() async => _settings;

  @override
  Future<List<RuntimeConnectionSettings>> loadRecent() async =>
      _settings == null ? const [] : [_settings!];

  @override
  Future<void> store(RuntimeConnectionSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> remove(RuntimeConnectionSettings settings) async {
    if (_settings?.identityKey == settings.identityKey) {
      _settings = null;
    }
  }
}

class _FakeImportFilePicker implements ImportFilePicker {
  _FakeImportFilePicker({
    this.epubResult = const ImportPickedFile(
      name: 'book.epub',
      sizeBytes: 1024,
      bytes: [9, 9, 9],
    ),
    this.audioResults = const [
      ImportPickedFile(
        name: 'chapter-01.mp3',
        sizeBytes: 2048,
        bytes: [1, 2, 3],
      ),
      ImportPickedFile(
        name: 'chapter-02.mp3',
        sizeBytes: 4096,
        bytes: [4, 5, 6],
      ),
    ],
    this.nearbyAudioResults = const [
      ImportPickedFile(
        name: 'book-part-01.mp3',
        sizeBytes: 8192,
        bytes: [7, 7, 7],
      ),
    ],
    this.nearbyEpubResult = const ImportPickedFile(
      name: 'book.epub',
      sizeBytes: 1024,
      bytes: [9, 9, 9],
    ),
  });

  final ImportPickedFile? epubResult;
  final List<ImportPickedFile> audioResults;
  final List<ImportPickedFile> nearbyAudioResults;
  final ImportPickedFile? nearbyEpubResult;

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async => audioResults;

  @override
  Future<ImportPickedFile?> pickEpub() async => epubResult;

  @override
  Future<List<ImportPickedFile>> findNearbyAudioFiles(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async => nearbyAudioResults;

  @override
  Future<ImportPickedFile?> findNearbyEpubFile(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async => nearbyEpubResult;
}

class _FakeSyncApiClient extends SyncApiClient {
  _FakeSyncApiClient() : super(baseUrl: 'http://sync.example.test/v1');

  final List<String> uploadedKinds = [];

  @override
  Future<ProjectCreateResult> createProject({
    required String title,
    required String language,
  }) async {
    return const ProjectCreateResult(
      projectId: 'project-123',
      status: 'created',
    );
  }

  @override
  Future<AssetUploadResult> uploadAsset({
    required String projectId,
    required String kind,
    required ImportPickedFile file,
  }) async {
    uploadedKinds.add(kind);
    return AssetUploadResult(
      assetId: '$kind-asset-${uploadedKinds.length}',
      status: 'uploaded',
      uploadMode: 'multipart',
    );
  }

  @override
  Future<AlignmentJobResult> createAlignmentJob({
    required String projectId,
    required String bookAssetId,
    required List<String> audioAssetIds,
  }) async {
    return const AlignmentJobResult(
      jobId: 'job-123',
      status: 'queued',
      reusedExisting: false,
      attemptNumber: 1,
    );
  }
}

void main() {
  test('pick epub auto-suggests nearby audiobook files', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.pickEpub();

    final state = container.read(libraryImportProvider);
    expect(state.epubFile?.name, 'book.epub');
    expect(state.audioFiles, hasLength(1));
    expect(state.audioFiles.first.name, 'book-part-01.mp3');
    expect(
      state.message,
      'Found audiobook files in the same folder and added them for you.',
    );
    expect(state.flowSummary, 'Ready to start sync');
  });

  test('pick audio auto-suggests nearby epub file', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.pickAudioFiles();

    final state = container.read(libraryImportProvider);
    expect(state.audioFiles, hasLength(2));
    expect(state.epubFile?.name, 'book.epub');
    expect(
      state.message,
      'Found a nearby EPUB in the same folder and added it for you.',
    );
    expect(state.flowSummary, 'Ready to start sync');
  });

  test('cancelled pick keeps the existing draft intact', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(
            epubResult: null,
            audioResults: const [
              ImportPickedFile(
                name: 'disc-01.mp3',
                sizeBytes: 2048,
                bytes: [1, 2, 3],
              ),
            ],
            nearbyAudioResults: const [],
            nearbyEpubResult: null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    controller.setLanguage('en');
    controller.useSuggestedAudioFiles();
    controller.removeAudioFile('book-part-01.mp3');
    await controller.pickAudioFiles();

    final beforeCancel = container.read(libraryImportProvider);
    expect(beforeCancel.audioFiles, hasLength(1));
    expect(beforeCancel.status, LibraryImportStatus.ready);

    await controller.pickEpub();

    final afterCancel = container.read(libraryImportProvider);
    expect(afterCancel.status, LibraryImportStatus.ready);
    expect(afterCancel.title, 'Imported Book');
    expect(afterCancel.audioFiles, hasLength(1));
    expect(afterCancel.epubFile, isNull);
    expect(afterCancel.projectId, isNull);
    expect(afterCancel.jobId, isNull);
    expect(afterCancel.message, isNull);
  });

  test('editing after completion returns to editable draft state', () async {
    final storage = _MemoryRuntimeConnectionSettingsStorage();
    final api = _FakeSyncApiClient();
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(storage),
        importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
        syncApiClientProvider.overrideWith((ref) async => api),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    await controller.pickEpub();
    await controller.startImport();

    final completedState = container.read(libraryImportProvider);
    expect(completedState.status, LibraryImportStatus.completed);
    expect(completedState.projectId, 'project-123');
    expect(completedState.jobId, 'job-123');

    controller.removeAudioFile('book-part-01.mp3');

    final editedState = container.read(libraryImportProvider);
    expect(editedState.status, LibraryImportStatus.ready);
    expect(editedState.projectId, isNull);
    expect(editedState.jobId, isNull);
    expect(editedState.completedAt, isNull);
    expect(
      editedState.message,
      'Audiobook removed. Add another audiobook file to keep going.',
    );
  });

  test('incomplete import explains exactly what is missing', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.startImport();

    final state = container.read(libraryImportProvider);
    expect(state.status, LibraryImportStatus.failed);
    expect(
      state.message,
      'Add the book title, EPUB, and audiobook to keep going.',
    );
  });

  test(
    'library import controller creates project, uploads files, and switches reader target',
    () async {
      final storage = _MemoryRuntimeConnectionSettingsStorage();
      final api = _FakeSyncApiClient();
      final container = ProviderContainer(
        overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(storage),
        importFilePickerProvider.overrideWithValue(
            _FakeImportFilePicker(),
          ),
          syncApiClientProvider.overrideWith((ref) async => api),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(libraryImportProvider.notifier);
      container.read(homeTabProvider.notifier).showLibrary();
      controller.setTitle('Imported Book');
      controller.setLanguage('en');
      await controller.pickEpub();
      await controller.pickAudioFiles();
      await controller.startImport();

      final state = container.read(libraryImportProvider);
      final settings = await container.read(
        runtimeConnectionSettingsProvider.future,
      );

      expect(state.status, LibraryImportStatus.completed);
      expect(state.projectId, 'project-123');
      expect(state.jobId, 'job-123');
      expect(state.completedAt, isNotNull);
      expect(api.uploadedKinds, ['epub', 'audio', 'audio']);
      expect(settings.projectId, 'project-123');
      expect(container.read(homeTabProvider), 0);

      controller.openImportedProject();
      expect(container.read(homeTabProvider), 1);
    },
  );
}
