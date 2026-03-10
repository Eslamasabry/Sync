import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/import/import_file_picker.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
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
    this.scannedDeviceBooks = const <ImportBookCandidate>[],
    this.epubFile,
    this.suggestedEpubFile,
    this.suggestedAudioFiles = const <ImportPickedFile>[],
    this.message,
    this.projectId,
    this.jobId,
    this.completedAt,
  });

  final LibraryImportStatus status;
  final String title;
  final String language;
  final List<ImportBookCandidate> scannedDeviceBooks;
  final ImportPickedFile? epubFile;
  final ImportPickedFile? suggestedEpubFile;
  final List<ImportPickedFile> audioFiles;
  final List<ImportPickedFile> suggestedAudioFiles;
  final String? message;
  final String? projectId;
  final String? jobId;
  final DateTime? completedAt;

  bool get hasDraftSelection => epubFile != null || audioFiles.isNotEmpty;
  bool get hasSuggestions =>
      suggestedEpubFile != null ||
      suggestedAudioFiles.isNotEmpty ||
      scannedDeviceBooks.isNotEmpty;

  bool get canStartImport =>
      title.trim().isNotEmpty &&
      epubFile != null &&
      audioFiles.isNotEmpty;

  bool get isBusy =>
      status == LibraryImportStatus.picking ||
      status == LibraryImportStatus.creatingProject ||
      status == LibraryImportStatus.uploadingEpub ||
      status == LibraryImportStatus.uploadingAudio ||
      status == LibraryImportStatus.startingJob;

  String? get missingRequirementsMessage {
    final missing = <String>[];
    if (title.trim().isEmpty) {
      missing.add('book title');
    }
    if (epubFile == null) {
      missing.add('EPUB');
    }
    if (audioFiles.isEmpty) {
      missing.add('audiobook');
    }
    if (missing.isEmpty) {
      return null;
    }
    if (missing.length == 1) {
      return 'Add the ${missing.single} to keep going.';
    }
    if (missing.length == 2) {
      return 'Add the ${missing.first} and ${missing.last} to keep going.';
    }
    return 'Add the ${missing[0]}, ${missing[1]}, and ${missing[2]} to keep going.';
  }

  String get flowSummary {
    return switch (status) {
      LibraryImportStatus.creatingProject => 'Creating your book space',
      LibraryImportStatus.uploadingEpub => 'Uploading the book file',
      LibraryImportStatus.uploadingAudio => 'Uploading audiobook files',
      LibraryImportStatus.startingJob => 'Starting sync',
      LibraryImportStatus.completed => 'Sync started',
      LibraryImportStatus.failed => 'Needs attention',
      LibraryImportStatus.picking => 'Looking at files',
      LibraryImportStatus.ready || LibraryImportStatus.idle =>
        canStartImport
            ? 'Ready to start sync'
            : missingRequirementsMessage ?? 'Add your book and audiobook',
    };
  }

  LibraryImportState copyWith({
    LibraryImportStatus? status,
    String? title,
    String? language,
    ImportPickedFile? epubFile,
    ImportPickedFile? suggestedEpubFile,
    List<ImportPickedFile>? audioFiles,
    List<ImportBookCandidate>? scannedDeviceBooks,
    List<ImportPickedFile>? suggestedAudioFiles,
    String? message,
    String? projectId,
    String? jobId,
    DateTime? completedAt,
    bool clearMessage = false,
    bool clearProjectId = false,
    bool clearJobId = false,
    bool clearCompletedAt = false,
    bool clearEpub = false,
    bool clearSuggestedEpub = false,
    bool clearSuggestedAudio = false,
    bool clearScannedDeviceBooks = false,
  }) {
    return LibraryImportState(
      status: status ?? this.status,
      title: title ?? this.title,
      language: language ?? this.language,
      scannedDeviceBooks: clearScannedDeviceBooks
          ? const <ImportBookCandidate>[]
          : scannedDeviceBooks ?? this.scannedDeviceBooks,
      epubFile: clearEpub ? null : epubFile ?? this.epubFile,
      suggestedEpubFile: clearSuggestedEpub
          ? null
          : suggestedEpubFile ?? this.suggestedEpubFile,
      audioFiles: audioFiles ?? this.audioFiles,
      suggestedAudioFiles: clearSuggestedAudio
          ? const <ImportPickedFile>[]
          : suggestedAudioFiles ?? this.suggestedAudioFiles,
      message: clearMessage ? null : message ?? this.message,
      projectId: clearProjectId ? null : projectId ?? this.projectId,
      jobId: clearJobId ? null : jobId ?? this.jobId,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
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
      scannedDeviceBooks: <ImportBookCandidate>[],
    );
  }

  void setTitle(String value) {
    state = _draftUpdate(title: value);
  }

  void setLanguage(String value) {
    state = _draftUpdate(language: value);
  }

  Future<void> pickEpub() async {
    final previousDraft = _draftUpdate();
    state = previousDraft.copyWith(
      status: LibraryImportStatus.picking,
      clearMessage: true,
    );
    final file = await ref.read(importFilePickerProvider).pickEpub();
    if (file == null) {
      state = previousDraft.copyWith(clearMessage: true);
      return;
    }
    final derivedTitle = _titleFromFilename(file.name);
    final suggestedAudio = _sortedAudioFiles(
      await ref
          .read(importFilePickerProvider)
          .findNearbyAudioFiles(file, preferredTitle: derivedTitle),
    );
    final shouldAutofillAudio =
        previousDraft.audioFiles.isEmpty && suggestedAudio.isNotEmpty;
    state = state.copyWith(
      status: _draftStatusFor(
        title: previousDraft.title.trim().isEmpty
            ? derivedTitle
            : previousDraft.title,
        epubFile: file,
        audioFiles: shouldAutofillAudio
            ? suggestedAudio
            : previousDraft.audioFiles,
      ),
      epubFile: file,
      suggestedAudioFiles: shouldAutofillAudio
          ? const <ImportPickedFile>[]
          : suggestedAudio,
      audioFiles: shouldAutofillAudio
          ? suggestedAudio
          : previousDraft.audioFiles,
      title: previousDraft.title.trim().isEmpty
          ? derivedTitle
          : previousDraft.title,
      message: shouldAutofillAudio
          ? 'Found audiobook files in the same folder and added them for you.'
          : suggestedAudio.isNotEmpty
          ? 'Book added. I also found audiobook files nearby.'
          : previousDraft.audioFiles.isEmpty
          ? 'Book added. Next, add the audiobook to start sync.'
          : 'Book replaced. Your audiobook files are still attached.',
      clearSuggestedEpub: true,
    );
  }

  Future<void> pickAudioFiles() async {
    final previousDraft = _draftUpdate();
    state = previousDraft.copyWith(
      status: LibraryImportStatus.picking,
      clearMessage: true,
    );
    final files = await ref.read(importFilePickerProvider).pickAudioFiles();
    if (files.isEmpty) {
      state = previousDraft.copyWith(clearMessage: true);
      return;
    }
    final sortedFiles = _sortedAudioFiles(files);
    final suggestedEpub = previousDraft.epubFile != null
        ? null
        : await ref
              .read(importFilePickerProvider)
              .findNearbyEpubFile(
                sortedFiles.first,
                preferredTitle: previousDraft.title,
              );
    final shouldAutofillEpub =
        previousDraft.epubFile == null && suggestedEpub != null;
    state = state.copyWith(
      status: _draftStatusFor(
        title: previousDraft.title,
        epubFile: shouldAutofillEpub ? suggestedEpub : previousDraft.epubFile,
        audioFiles: sortedFiles,
      ),
      audioFiles: sortedFiles,
      epubFile: shouldAutofillEpub ? suggestedEpub : previousDraft.epubFile,
      suggestedEpubFile: shouldAutofillEpub ? null : suggestedEpub,
      clearSuggestedAudio: true,
      title: previousDraft.title.trim().isEmpty && shouldAutofillEpub
          ? _titleFromFilename(suggestedEpub.name)
          : previousDraft.title,
      message: shouldAutofillEpub
          ? 'Found a nearby EPUB in the same folder and added it for you.'
          : suggestedEpub != null
          ? 'Audiobook added. I also found a nearby EPUB.'
          : previousDraft.epubFile == null
          ? 'Audiobook added. Next, add the EPUB to start sync.'
          : 'Audiobook updated. Your book file is still attached.',
    );
  }

  void useSuggestedAudioFiles() {
    if (state.suggestedAudioFiles.isEmpty) {
      return;
    }
    state = _draftUpdate(
      audioFiles: _sortedAudioFiles(state.suggestedAudioFiles),
      clearSuggestedAudio: true,
      message: 'Added nearby audiobook files to your import.',
    );
  }

  void useSuggestedEpubFile() {
    final suggested = state.suggestedEpubFile;
    if (suggested == null) {
      return;
    }
    state = _draftUpdate(
      epubFile: suggested,
      clearSuggestedEpub: true,
      title: state.title.trim().isEmpty
          ? _titleFromFilename(suggested.name)
          : state.title,
      message: 'Added the nearby EPUB to your import.',
    );
  }

  Future<void> scanNearbyFiles() async {
    final previousDraft = _draftUpdate();
    final picker = ref.read(importFilePickerProvider);
    final baseTitle = previousDraft.title.trim().isEmpty
        ? (previousDraft.epubFile != null
              ? _titleFromFilename(previousDraft.epubFile!.name)
              : null)
        : previousDraft.title.trim();
    final suggestedAudio = previousDraft.epubFile == null
        ? const <ImportPickedFile>[]
        : _sortedAudioFiles(
            await picker.findNearbyAudioFiles(
              previousDraft.epubFile!,
              preferredTitle: baseTitle,
            ),
          );
    final suggestedEpub =
        previousDraft.epubFile == null && previousDraft.audioFiles.isNotEmpty
        ? await picker.findNearbyEpubFile(
            previousDraft.audioFiles.first,
            preferredTitle: baseTitle,
          )
        : null;

    final shouldAutofillAudio =
        previousDraft.audioFiles.isEmpty && suggestedAudio.isNotEmpty;
    final shouldAutofillEpub =
        previousDraft.epubFile == null && suggestedEpub != null;

    state = previousDraft.copyWith(
      status: _draftStatusFor(
        title: previousDraft.title,
        epubFile: shouldAutofillEpub ? suggestedEpub : previousDraft.epubFile,
        audioFiles: shouldAutofillAudio
            ? suggestedAudio
            : previousDraft.audioFiles,
      ),
      audioFiles: shouldAutofillAudio
          ? suggestedAudio
          : previousDraft.audioFiles,
      epubFile: shouldAutofillEpub ? suggestedEpub : previousDraft.epubFile,
      suggestedAudioFiles: shouldAutofillAudio
          ? const <ImportPickedFile>[]
          : suggestedAudio,
      suggestedEpubFile: shouldAutofillEpub ? null : suggestedEpub,
      clearScannedDeviceBooks: true,
      message: _nearbyScanMessage(
        suggestedAudioCount: suggestedAudio.length,
        foundEpub: suggestedEpub != null,
        autoAppliedAudio: shouldAutofillAudio,
        autoAppliedEpub: shouldAutofillEpub,
      ),
    );
  }

  Future<void> scanDeviceBooks() async {
    final previousDraft = _draftUpdate();
    state = previousDraft.copyWith(
      status: LibraryImportStatus.picking,
      clearMessage: true,
    );
    final candidates = await ref
        .read(importFilePickerProvider)
        .scanDeviceBooks();
    state = previousDraft.copyWith(
      status: previousDraft.status,
      scannedDeviceBooks: candidates,
      clearSuggestedAudio: true,
      clearSuggestedEpub: true,
      message: candidates.isEmpty
          ? 'No likely book and audiobook pairs were found in that folder.'
          : 'Found ${candidates.length} books in that folder. Choose one to fill the draft.',
    );
  }

  void useScannedDeviceBook(ImportBookCandidate candidate) {
    state = _draftUpdate(
      title: candidate.title,
      epubFile: candidate.epubFile,
      audioFiles: _sortedAudioFiles(candidate.audioFiles),
      clearEpub: candidate.epubFile == null,
      clearScannedDeviceBooks: true,
      message: candidate.epubFile != null
          ? 'Loaded ${candidate.title} from ${candidate.directoryLabel}. Review it, then start sync.'
          : 'Loaded audiobook files for ${candidate.title} from ${candidate.directoryLabel}. Add the EPUB to finish the setup.',
    );
  }

  void removeAudioFile(String name) {
    final nextAudioFiles = state.audioFiles
        .where((file) => file.name != name)
        .toList(growable: false);
    state = _draftUpdate(
      audioFiles: nextAudioFiles,
      message: nextAudioFiles.isEmpty
          ? 'Audiobook removed. Add another audiobook file to keep going.'
          : 'Audiobook selection updated.',
    );
  }

  Future<void> startImport() async {
    if (!state.canStartImport) {
      state = state.copyWith(
        status: LibraryImportStatus.failed,
        message:
            state.missingRequirementsMessage ??
            'Complete the book setup before starting sync.',
      );
      return;
    }

    final settings = await ref.read(runtimeConnectionSettingsProvider.future);
    final api = await ref.read(syncApiClientProvider.future);

    try {
      state = state.copyWith(
        status: LibraryImportStatus.creatingProject,
        message: 'Creating the book project...',
        clearProjectId: true,
        clearJobId: true,
        clearCompletedAt: true,
      );
      final project = await api.createProject(
        title: state.title.trim(),
        language: state.language.trim(),
      );

      state = state.copyWith(
        status: LibraryImportStatus.uploadingEpub,
        projectId: project.projectId,
        message: 'Uploading the book file...',
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
          message:
              'Uploading audio ${index + 1} of ${state.audioFiles.length}...',
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
        message: 'Starting sync...',
      );
      final job = await api.createAlignmentJob(
        projectId: project.projectId,
        bookAssetId: epubAsset.assetId,
        audioAssetIds: audioAssetIds,
      );

      await ref
          .read(runtimeConnectionSettingsProvider.notifier)
          .save(
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

      state = state.copyWith(
        status: LibraryImportStatus.completed,
        projectId: project.projectId,
        jobId: job.jobId,
        message:
            'Everything is uploaded. Sync is running now, and this book will be ready to open as soon as processing finishes.',
        completedAt: DateTime.now().toUtc(),
      );
    } catch (error) {
      final failedStage = state.status;
      state = state.copyWith(
        status: LibraryImportStatus.failed,
        message: _importFailureMessage(
          error,
          stage: failedStage,
          projectId: state.projectId,
        ),
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

  void openImportedProject() {
    if (state.projectId == null || state.jobId == null) {
      return;
    }
    ref.read(homeTabProvider.notifier).showReader();
  }

  LibraryImportState _draftUpdate({
    String? title,
    String? language,
    ImportPickedFile? epubFile,
    List<ImportPickedFile>? audioFiles,
    ImportPickedFile? suggestedEpubFile,
    List<ImportBookCandidate>? scannedDeviceBooks,
    List<ImportPickedFile>? suggestedAudioFiles,
    String? message,
    bool clearMessage = false,
    bool clearEpub = false,
    bool clearSuggestedEpub = false,
    bool clearSuggestedAudio = false,
    bool clearScannedDeviceBooks = false,
  }) {
    final nextTitle = title ?? state.title;
    final nextLanguage = language ?? state.language;
    final nextEpub = clearEpub ? null : epubFile ?? state.epubFile;
    final nextAudioFiles = audioFiles ?? state.audioFiles;
    return state.copyWith(
      status: _draftStatusFor(
        title: nextTitle,
        epubFile: nextEpub,
        audioFiles: nextAudioFiles,
      ),
      title: nextTitle,
      language: nextLanguage,
      epubFile: clearEpub ? null : epubFile,
      audioFiles: nextAudioFiles,
      clearEpub: clearEpub,
      scannedDeviceBooks: scannedDeviceBooks,
      suggestedEpubFile: suggestedEpubFile,
      suggestedAudioFiles: suggestedAudioFiles,
      message: message,
      clearMessage: clearMessage,
      clearProjectId: true,
      clearJobId: true,
      clearCompletedAt: true,
      clearSuggestedEpub: clearSuggestedEpub,
      clearSuggestedAudio: clearSuggestedAudio,
      clearScannedDeviceBooks: clearScannedDeviceBooks,
    );
  }
}

List<ImportPickedFile> _sortedAudioFiles(List<ImportPickedFile> files) {
  final sorted = List<ImportPickedFile>.from(files);
  sorted.sort((left, right) => _naturalFileNameCompare(left.name, right.name));
  return sorted;
}

int _naturalFileNameCompare(String left, String right) {
  final leftParts = _naturalNameParts(left);
  final rightParts = _naturalNameParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < maxLength; index += 1) {
    if (index >= leftParts.length) {
      return -1;
    }
    if (index >= rightParts.length) {
      return 1;
    }

    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    if (leftNumber != null && rightNumber != null) {
      final comparison = leftNumber.compareTo(rightNumber);
      if (comparison != 0) {
        return comparison;
      }
      continue;
    }

    final comparison = leftPart.toLowerCase().compareTo(
      rightPart.toLowerCase(),
    );
    if (comparison != 0) {
      return comparison;
    }
  }

  return 0;
}

List<String> _naturalNameParts(String value) {
  final matches = RegExp(r'\d+|\D+').allMatches(value);
  return [for (final match in matches) match.group(0) ?? ''];
}

LibraryImportStatus _draftStatusFor({
  required String title,
  required ImportPickedFile? epubFile,
  required List<ImportPickedFile> audioFiles,
}) {
  return title.trim().isEmpty && epubFile == null && audioFiles.isEmpty
      ? LibraryImportStatus.idle
      : LibraryImportStatus.ready;
}

String _titleFromFilename(String name) {
  final withoutExtension = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExtension
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _importFailureMessage(
  Object error, {
  required LibraryImportStatus stage,
  required String? projectId,
}) {
  if (error is ApiClientException) {
    switch (error.code) {
      case 'asset_too_large':
        return 'One of the files is larger than this server currently allows. Try a smaller file, or raise the upload limit on your server and try again.';
      case 'audio_processing_failed':
        return 'Sync could not read one of the audiobook files. Try an MP3, M4B, M4A, OGG, WAV, or FLAC file for this book.';
      case 'asset_upload_failed':
        return 'The server could not save one of the files right now. Try again in a moment.';
      case 'epub_processing_failed':
        return 'The selected EPUB could not be read. Try a different EPUB file for this book.';
      case 'job_dispatch_failed':
        return 'The files uploaded, but the server could not start syncing yet. Try again in a moment.';
      case 'auth_invalid':
        return 'The server rejected the current token. Update the server connection details and try again.';
      case 'project_not_found':
        return 'This server could not find the book project anymore. Start the import again to rebuild it cleanly.';
    }
  }
  final detail = formatSyncApiError(error);
  final prefix = switch (stage) {
    LibraryImportStatus.creatingProject =>
      'Could not create the project shell.',
    LibraryImportStatus.uploadingEpub =>
      'The project was created, but the EPUB upload failed.',
    LibraryImportStatus.uploadingAudio =>
      'The project exists, but one of the audio uploads failed.',
    LibraryImportStatus.startingJob =>
      'The files uploaded, but the alignment job could not start.',
    _ => 'Import failed.',
  };
  if (projectId != null &&
      projectId.isNotEmpty &&
      stage != LibraryImportStatus.creatingProject) {
    return '$prefix $detail Your draft is still here, so you can retry without reselecting everything.';
  }
  return '$prefix $detail';
}

String? _nearbyScanMessage({
  required int suggestedAudioCount,
  required bool foundEpub,
  required bool autoAppliedAudio,
  required bool autoAppliedEpub,
}) {
  if (!autoAppliedAudio &&
      !autoAppliedEpub &&
      suggestedAudioCount == 0 &&
      !foundEpub) {
    return 'No likely nearby book or audiobook files were found.';
  }
  if (autoAppliedAudio && autoAppliedEpub) {
    return 'Found matching book and audiobook files nearby and added them for you.';
  }
  if (autoAppliedAudio) {
    return 'Found nearby audiobook files and added them for you.';
  }
  if (autoAppliedEpub) {
    return 'Found a nearby EPUB and added it for you.';
  }
  if (suggestedAudioCount > 0 && foundEpub) {
    return 'Found nearby book and audiobook candidates. Review them below.';
  }
  if (suggestedAudioCount > 0) {
    return 'Found nearby audiobook candidates. Review them below.';
  }
  if (foundEpub) {
    return 'Found a nearby EPUB candidate. Review it below.';
  }
  return null;
}
