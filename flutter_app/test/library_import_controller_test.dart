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
}

class _FakeImportFilePicker implements ImportFilePicker {
  const _FakeImportFilePicker();

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async => const [
    ImportPickedFile(name: 'chapter-01.mp3', sizeBytes: 2048, bytes: [1, 2, 3]),
    ImportPickedFile(name: 'chapter-02.mp3', sizeBytes: 4096, bytes: [4, 5, 6]),
  ];

  @override
  Future<ImportPickedFile?> pickEpub() async => const ImportPickedFile(
    name: 'book.epub',
    sizeBytes: 1024,
    bytes: [9, 9, 9],
  );
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
  test('library import controller creates project, uploads files, and switches reader target', () async {
    final storage = _MemoryRuntimeConnectionSettingsStorage();
    final api = _FakeSyncApiClient();
    final container = ProviderContainer(
      overrides: [
        runtimeConnectionSettingsStorageProvider.overrideWithValue(storage),
        importFilePickerProvider.overrideWithValue(const _FakeImportFilePicker()),
        syncApiClientProvider.overrideWith((ref) async => api),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(libraryImportProvider.notifier);
    controller.setTitle('Imported Book');
    controller.setLanguage('en');
    await controller.pickEpub();
    await controller.pickAudioFiles();
    await controller.startImport();

    final state = container.read(libraryImportProvider);
    final settings = await container.read(runtimeConnectionSettingsProvider.future);

    expect(state.status, LibraryImportStatus.completed);
    expect(state.projectId, 'project-123');
    expect(state.jobId, 'job-123');
    expect(api.uploadedKinds, ['epub', 'audio', 'audio']);
    expect(settings.projectId, 'project-123');
    expect(container.read(homeTabProvider), 1);
  });
}
