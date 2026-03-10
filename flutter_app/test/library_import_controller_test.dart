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
    this.deviceBooks = const [
      ImportBookCandidate(
        title: 'The Time Machine',
        directoryLabel: 'Audiobooks',
        epubFile: ImportPickedFile(
          name: 'The Time Machine.epub',
          sizeBytes: 1024,
          bytes: [9, 9, 9],
        ),
        audioFiles: [
          ImportPickedFile(
            name: 'The Time Machine - Chapter 01.m4b',
            sizeBytes: 4096,
            bytes: [1, 1, 1],
          ),
        ],
      ),
    ],
  });

  final ImportPickedFile? epubResult;
  final List<ImportPickedFile> audioResults;
  final List<ImportPickedFile> nearbyAudioResults;
  final ImportPickedFile? nearbyEpubResult;
  final List<ImportBookCandidate> deviceBooks;

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async => audioResults;

  @override
  Future<ImportPickedFile?> pickEpub() async => epubResult;

  @override
  Future<List<ImportBookCandidate>> scanDeviceBooks() async => deviceBooks;

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
  _FakeSyncApiClient({this.uploadError, this.jobError, this.createProjectError})
    : super(baseUrl: 'http://sync.example.test/v1');

  final List<String> uploadedKinds = [];
  final Object? uploadError;
  final Object? jobError;
  final Object? createProjectError;

  @override
  Future<ProjectCreateResult> createProject({
    required String title,
    required String language,
  }) async {
    if (createProjectError case final error?) {
      throw error;
    }
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
    if (uploadError case final error?) {
      throw error;
    }
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
    if (jobError case final error?) {
      throw error;
    }
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
          _FakeImportFilePicker(deviceBooks: const <ImportBookCandidate>[]),
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
          _FakeImportFilePicker(deviceBooks: const <ImportBookCandidate>[]),
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

  test(
    'device scan can fill the draft from one local book candidate',
    () async {
      final container = ProviderContainer(
        overrides: [
          importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(libraryImportProvider.notifier);
      await controller.scanDeviceBooks();

      final scanned = container.read(libraryImportProvider);
      expect(scanned.scannedDeviceBooks, hasLength(1));
      expect(scanned.message, contains('Found 1 books'));

      controller.useScannedDeviceBook(scanned.scannedDeviceBooks.first);
      final selected = container.read(libraryImportProvider);
      expect(selected.title, 'The Time Machine');
      expect(selected.epubFile?.name, 'The Time Machine.epub');
      expect(selected.audioFiles, hasLength(1));
      expect(selected.scannedDeviceBooks, isEmpty);
    },
  );

  test('audio-only scanned candidate tells the user to add the epub', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(
            deviceBooks: const [
              ImportBookCandidate(
                title: 'Standalone Story',
                directoryLabel: 'Downloads',
                audioFiles: [
                  ImportPickedFile(
                    name: 'Standalone Story - Part 01.mp3',
                    sizeBytes: 4096,
                    bytes: [1, 1, 1],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.scanDeviceBooks();
    controller.useScannedDeviceBook(
      container.read(libraryImportProvider).scannedDeviceBooks.first,
    );

    final state = container.read(libraryImportProvider);
    expect(state.epubFile, isNull);
    expect(state.audioFiles, hasLength(1));
    expect(state.message, contains('Add the EPUB to finish the setup.'));
  });

  test('audio-only scanned candidate clears any previous epub draft', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(
            deviceBooks: const [
              ImportBookCandidate(
                title: 'Standalone Story',
                directoryLabel: 'Downloads',
                audioFiles: [
                  ImportPickedFile(
                    name: 'Standalone Story - Part 01.mp3',
                    sizeBytes: 4096,
                    bytes: [1, 1, 1],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.pickEpub();
    expect(container.read(libraryImportProvider).epubFile, isNotNull);

    await controller.scanDeviceBooks();
    controller.useScannedDeviceBook(
      container.read(libraryImportProvider).scannedDeviceBooks.first,
    );

    final state = container.read(libraryImportProvider);
    expect(state.epubFile, isNull);
    expect(state.audioFiles.map((file) => file.name).toList(), [
      'Standalone Story - Part 01.mp3',
    ]);
  });

  test('picked audiobook files are sorted in natural chapter order', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(
            deviceBooks: const <ImportBookCandidate>[],
            audioResults: const [
              ImportPickedFile(
                name: 'chapter-10.mp3',
                sizeBytes: 4096,
                bytes: [4, 5, 6],
              ),
              ImportPickedFile(
                name: 'chapter-2.mp3',
                sizeBytes: 2048,
                bytes: [1, 2, 3],
              ),
              ImportPickedFile(
                name: 'chapter-1.mp3',
                sizeBytes: 1024,
                bytes: [7, 8, 9],
              ),
            ],
            nearbyEpubResult: null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    await controller.pickAudioFiles();

    final state = container.read(libraryImportProvider);
    expect(state.audioFiles.map((file) => file.name).toList(), [
      'chapter-1.mp3',
      'chapter-2.mp3',
      'chapter-10.mp3',
    ]);
  });

  test('language can be blank without blocking import readiness', () async {
    final container = ProviderContainer(
      overrides: [
        importFilePickerProvider.overrideWithValue(
          _FakeImportFilePicker(deviceBooks: const <ImportBookCandidate>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    controller.setLanguage('');
    await controller.pickEpub();

    final state = container.read(libraryImportProvider);
    expect(state.language, '');
    expect(state.canStartImport, isTrue);
    expect(state.flowSummary, 'Ready to start sync');
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
          importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
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

  test('asset upload size errors return plain recovery guidance', () async {
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(
          _MemoryRuntimeConnectionSettingsStorage(),
        ),
        importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
        syncApiClientProvider.overrideWith(
          (ref) async => _FakeSyncApiClient(
            uploadError: const ApiClientException(
              'Uploaded asset exceeds the configured size limit',
              code: 'asset_too_large',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    await controller.pickEpub();
    await controller.startImport();

    final state = container.read(libraryImportProvider);
    expect(state.status, LibraryImportStatus.failed);
    expect(
      state.message,
      'One of the files is larger than this server currently allows. Try a smaller file, or raise the upload limit on your server and try again.',
    );
  });

  test('job dispatch failures explain that sync never started', () async {
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(
          _MemoryRuntimeConnectionSettingsStorage(),
        ),
        importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
        syncApiClientProvider.overrideWith(
          (ref) async => _FakeSyncApiClient(
            jobError: const ApiClientException(
              'Alignment job dispatch failed',
              code: 'job_dispatch_failed',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    await controller.pickEpub();
    await controller.startImport();

    final state = container.read(libraryImportProvider);
    expect(state.status, LibraryImportStatus.failed);
    expect(
      state.message,
      'The files uploaded, but the server could not start syncing yet. Try again in a moment.',
    );
  });

  test('unreadable audio uploads explain which file types to try next', () async {
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(
          _MemoryRuntimeConnectionSettingsStorage(),
        ),
        importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
        syncApiClientProvider.overrideWith(
          (ref) async => _FakeSyncApiClient(
            uploadError: const ApiClientException(
              'Sync could not read this audiobook file.',
              code: 'audio_processing_failed',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    await controller.pickEpub();
    await controller.startImport();

    final state = container.read(libraryImportProvider);
    expect(state.status, LibraryImportStatus.failed);
    expect(
      state.message,
      'Sync could not read one of the audiobook files. Try an MP3, M4B, M4A, OGG, WAV, or FLAC file for this book.',
    );
  });

  test(
    'auth failures ask the user to update server connection details',
    () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConnectionSettingsStorageProvider.overrideWithValue(
            _MemoryRuntimeConnectionSettingsStorage(),
          ),
          importFilePickerProvider.overrideWithValue(_FakeImportFilePicker()),
          syncApiClientProvider.overrideWith(
            (ref) async => _FakeSyncApiClient(
              createProjectError: const ApiClientException(
                'The server rejected the token',
                code: 'auth_invalid',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(libraryImportProvider.notifier);
      controller.setTitle('Imported Book');
      await controller.pickEpub();
      await controller.startImport();

      final state = container.read(libraryImportProvider);
      expect(state.status, LibraryImportStatus.failed);
      expect(
        state.message,
        'The server rejected the current token. Update the server connection details and try again.',
      );
    },
  );
}
