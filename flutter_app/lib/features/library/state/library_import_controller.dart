import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/import/import_file_picker.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => const PlatformImportFilePicker(),
);

enum LibraryImportStatus {
  idle,
  picking,
  ready,
  creatingProject,
  uploadingEpub,
  uploadingAudio,
  startingJob,
  completed,
  failed,
}

class LibraryImportState {
  const LibraryImportState({
    required this.status,
    required this.title,
    required this.language,
    required this.audioFiles,
    this.epubFile,
    this.message,
    this.projectId,
    this.jobId,
  });

  final LibraryImportStatus status;
  final String title;
  final String language;
  final ImportPickedFile? epubFile;
  final List<ImportPickedFile> audioFiles;
  final String? message;
  final String? projectId;
  final String? jobId;

  bool get canStartImport =>
      title.trim().isNotEmpty &&
      language.trim().isNotEmpty &&
      epubFile != null &&
      audioFiles.isNotEmpty;

  bool get isBusy =>
      status == LibraryImportStatus.picking ||
      status == LibraryImportStatus.creatingProject ||
      status == LibraryImportStatus.uploadingEpub ||
      status == LibraryImportStatus.uploadingAudio ||
      status == LibraryImportStatus.startingJob;

  LibraryImportState copyWith({
    LibraryImportStatus? status,
    String? title,
    String? language,
    ImportPickedFile? epubFile,
    List<ImportPickedFile>? audioFiles,
    String? message,
    String? projectId,
    String? jobId,
    bool clearMessage = false,
    bool clearProjectId = false,
    bool clearJobId = false,
    bool clearEpub = false,
  }) {
    return LibraryImportState(
      status: status ?? this.status,
      title: title ?? this.title,
      language: language ?? this.language,
      epubFile: clearEpub ? null : epubFile ?? this.epubFile,
      audioFiles: audioFiles ?? this.audioFiles,
      message: clearMessage ? null : message ?? this.message,
      projectId: clearProjectId ? null : projectId ?? this.projectId,
      jobId: clearJobId ? null : jobId ?? this.jobId,
    );
  }
}

final libraryImportProvider =
    NotifierProvider<LibraryImportController, LibraryImportState>(
      LibraryImportController.new,
    );

class LibraryImportController extends Notifier<LibraryImportState> {
  @override
  LibraryImportState build() {
    return const LibraryImportState(
      status: LibraryImportStatus.idle,
      title: '',
      language: 'en',
      audioFiles: <ImportPickedFile>[],
    );
  }

  void setTitle(String value) {
    state = state.copyWith(title: value);
  }

  void setLanguage(String value) {
    state = state.copyWith(language: value);
  }

  Future<void> pickEpub() async {
    state = state.copyWith(
      status: LibraryImportStatus.picking,
      clearMessage: true,
    );
    final file = await ref.read(importFilePickerProvider).pickEpub();
    state = state.copyWith(
      status: file == null ? LibraryImportStatus.idle : LibraryImportStatus.ready,
      epubFile: file,
    );
  }

  Future<void> pickAudioFiles() async {
    state = state.copyWith(
      status: LibraryImportStatus.picking,
      clearMessage: true,
    );
    final files = await ref.read(importFilePickerProvider).pickAudioFiles();
    state = state.copyWith(
      status: files.isEmpty ? LibraryImportStatus.idle : LibraryImportStatus.ready,
      audioFiles: files,
    );
  }

  void removeAudioFile(String name) {
    state = state.copyWith(
      audioFiles: state.audioFiles
          .where((file) => file.name != name)
          .toList(growable: false),
    );
  }

  Future<void> startImport() async {
    if (!state.canStartImport) {
      state = state.copyWith(
        status: LibraryImportStatus.failed,
        message: 'Choose an EPUB, at least one audio file, and enter a title first.',
      );
      return;
    }

    final settings = await ref.read(runtimeConnectionSettingsProvider.future);
    final api = await ref.read(syncApiClientProvider.future);

    try {
      state = state.copyWith(
        status: LibraryImportStatus.creatingProject,
        message: 'Creating project shell...',
        clearProjectId: true,
        clearJobId: true,
      );
      final project = await api.createProject(
        title: state.title.trim(),
        language: state.language.trim(),
      );

      state = state.copyWith(
        status: LibraryImportStatus.uploadingEpub,
        projectId: project.projectId,
        message: 'Uploading EPUB...',
      );
      final epubAsset = await api.uploadAsset(
        projectId: project.projectId,
        kind: 'epub',
        file: state.epubFile!,
      );

      final audioAssetIds = <String>[];
      for (var index = 0; index < state.audioFiles.length; index += 1) {
        final audioFile = state.audioFiles[index];
        state = state.copyWith(
          status: LibraryImportStatus.uploadingAudio,
          message: 'Uploading audio ${index + 1} of ${state.audioFiles.length}...',
        );
        final asset = await api.uploadAsset(
          projectId: project.projectId,
          kind: 'audio',
          file: audioFile,
        );
        audioAssetIds.add(asset.assetId);
      }

      state = state.copyWith(
        status: LibraryImportStatus.startingJob,
        message: 'Starting alignment job...',
      );
      final job = await api.createAlignmentJob(
        projectId: project.projectId,
        bookAssetId: epubAsset.assetId,
        audioAssetIds: audioAssetIds,
      );

      await ref.read(runtimeConnectionSettingsProvider.notifier).save(
        RuntimeConnectionSettings(
          apiBaseUrl: settings.apiBaseUrl,
          projectId: project.projectId,
          authToken: settings.authToken,
        ),
      );
      ref.invalidate(projectIdProvider);
      ref.invalidate(syncApiClientProvider);
      ref.invalidate(projectEventsClientProvider);
      ref.invalidate(readerRepositoryProvider);
      ref.invalidate(readerProjectProvider);
      ref.invalidate(projectEventsProvider);
      ref.invalidate(latestProjectEventProvider);
      ref.read(readerPlaybackProvider.notifier).resetForProject();
      ref.read(homeTabProvider.notifier).showReader();

      state = state.copyWith(
        status: LibraryImportStatus.completed,
        projectId: project.projectId,
        jobId: job.jobId,
        message: 'Project created and alignment started.',
      );
    } catch (error) {
      state = state.copyWith(
        status: LibraryImportStatus.failed,
        message: 'Import failed. $error',
      );
    }
  }

  void clearDraft() {
    state = const LibraryImportState(
      status: LibraryImportStatus.idle,
      title: '',
      language: 'en',
      audioFiles: <ImportPickedFile>[],
    );
  }
}
