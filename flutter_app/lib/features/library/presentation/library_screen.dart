import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/state/library_import_controller.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/state/reader_audio_download_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class LibraryProjectSnapshot {
  const LibraryProjectSnapshot({
    required this.settings,
    required this.title,
    required this.projectStatus,
    required this.assetCount,
    required this.audioAssetCount,
    required this.epubAssetCount,
    required this.totalSizeBytes,
    required this.updatedAt,
    this.language,
    this.latestJobStatus,
    this.latestJobStage,
    this.latestJobPercent,
    this.latestJobAttempt,
    this.latestJobTerminalReason,
    this.lifecyclePhase,
    this.lifecycleNextAction,
    this.lifecycleMissingRequirements = const <String>[],
    this.lifecycleIsReadable = false,
  });

  final RuntimeConnectionSettings settings;
  final String title;
  final String? language;
  final String projectStatus;
  final int assetCount;
  final int audioAssetCount;
  final int epubAssetCount;
  final int totalSizeBytes;
  final DateTime? updatedAt;
  final String? latestJobStatus;
  final String? latestJobStage;
  final int? latestJobPercent;
  final int? latestJobAttempt;
  final String? latestJobTerminalReason;
  final String? lifecyclePhase;
  final String? lifecycleNextAction;
  final List<String> lifecycleMissingRequirements;
  final bool lifecycleIsReadable;

  bool get hasActiveJob =>
      latestJobStatus == 'queued' || latestJobStatus == 'running';
}

abstract class LibraryProjectSummaryLoader {
  const LibraryProjectSummaryLoader();

  Future<LibraryProjectSnapshot> load(RuntimeConnectionSettings settings);
}

class ApiLibraryProjectSummaryLoader implements LibraryProjectSummaryLoader {
  const ApiLibraryProjectSummaryLoader();

  @override
  Future<LibraryProjectSnapshot> load(
    RuntimeConnectionSettings settings,
  ) async {
    final api = SyncApiClient(
      baseUrl: settings.apiBaseUrl,
      authToken: settings.authToken,
    );
    final detail = await api.fetchProjectDetail(settings.projectId);
    final lifecycle = _asMapOrNull(detail['lifecycle']);
    final assets = _asObjectList(detail['assets']);
    final latestJobSummary = _asMapOrNull(detail['latest_job']);
    AlignmentJobResult? latestJob;
    final latestJobId = latestJobSummary?['job_id']?.toString();
    if (latestJobId != null && latestJobId.isNotEmpty) {
      latestJob = await api.fetchJob(
        projectId: settings.projectId,
        jobId: latestJobId,
      );
    }

    var audioAssetCount = 0;
    var epubAssetCount = 0;
    var totalSizeBytes = 0;
    for (final asset in assets) {
      final kind = asset['kind']?.toString();
      if (kind == 'audio') {
        audioAssetCount += 1;
      } else if (kind == 'epub') {
        epubAssetCount += 1;
      }
      totalSizeBytes += (asset['size_bytes'] as num?)?.round() ?? 0;
    }

    return LibraryProjectSnapshot(
      settings: settings,
      title: detail['title']?.toString() ?? settings.normalizedProjectId,
      language: detail['language']?.toString(),
      projectStatus: detail['status']?.toString() ?? 'unknown',
      assetCount: assets.length,
      audioAssetCount: audioAssetCount,
      epubAssetCount: epubAssetCount,
      totalSizeBytes: totalSizeBytes,
      updatedAt: DateTime.tryParse(detail['updated_at']?.toString() ?? ''),
      latestJobStatus:
          latestJob?.status ?? latestJobSummary?['status']?.toString(),
      latestJobStage: latestJob?.stage,
      latestJobPercent: latestJob?.percent,
      latestJobAttempt: latestJob?.attemptNumber,
      latestJobTerminalReason:
          latestJob?.terminalReason ??
          latestJobSummary?['terminal_reason']?.toString(),
      lifecyclePhase: lifecycle?['phase']?.toString(),
      lifecycleNextAction: lifecycle?['next_action']?.toString(),
      lifecycleMissingRequirements: _asStringList(
        lifecycle?['missing_requirements'],
      ),
      lifecycleIsReadable: lifecycle?['is_readable'] == true,
    );
  }
}

final libraryProjectSummaryLoaderProvider =
    Provider<LibraryProjectSummaryLoader>(
      (ref) => const ApiLibraryProjectSummaryLoader(),
    );

final libraryProjectSnapshotProvider = FutureProvider.autoDispose
    .family<LibraryProjectSnapshot, RuntimeConnectionSettings>(
      (ref, settings) =>
          ref.read(libraryProjectSummaryLoaderProvider).load(settings),
    );

final libraryProjectJobsProvider = FutureProvider.autoDispose
    .family<ProjectJobsResult, RuntimeConnectionSettings>((ref, settings) {
      final api = SyncApiClient(
        baseUrl: settings.apiBaseUrl,
        authToken: settings.authToken,
      );
      return api.fetchProjectJobs(settings.projectId);
    });

final libraryProjectRefreshTickProvider = StreamProvider.autoDispose
    .family<int, RuntimeConnectionSettings>(
      (ref, settings) =>
          Stream<int>.periodic(const Duration(seconds: 3), (count) => count),
    );

class LibraryOfflineSnapshot {
  const LibraryOfflineSnapshot({
    required this.hasTextCache,
    required this.cachedAudioAssets,
    required this.cachedAudioBytes,
    this.textCachedAt,
    this.audioCachedAt,
  });

  final bool hasTextCache;
  final int cachedAudioAssets;
  final int cachedAudioBytes;
  final DateTime? textCachedAt;
  final DateTime? audioCachedAt;
}

final libraryOfflineSnapshotProvider = FutureProvider.autoDispose
    .family<LibraryOfflineSnapshot, RuntimeConnectionSettings>((
      ref,
      settings,
    ) async {
      final artifactCache = ref.read(readerArtifactCacheProvider);
      final audioCache = ref.read(readerAudioCacheProvider);
      final cachedBundle = await artifactCache.loadProject(
        settings.normalizedProjectId,
      );
      final cachedAudio = await audioCache.inspectProject(
        settings.normalizedProjectId,
      );
      final cachedAudioBytes = cachedAudio.assetsById.values.fold<int>(
        0,
        (sum, asset) => sum + (asset.sizeBytes ?? 0),
      );
      return LibraryOfflineSnapshot(
        hasTextCache: cachedBundle != null,
        cachedAudioAssets: cachedAudio.assetCount,
        cachedAudioBytes: cachedAudioBytes,
        textCachedAt: cachedBundle?.cachedAt,
        audioCachedAt: cachedAudio.updatedAt,
      );
    });

final libraryServerProjectsProvider =
    FutureProvider.autoDispose<List<ProjectListItem>>((ref) async {
      final settings = await ref.watch(
        runtimeConnectionSettingsProvider.future,
      );
      final api = SyncApiClient(
        baseUrl: settings.apiBaseUrl,
        authToken: settings.authToken,
      );
      return api.fetchProjects();
    });

class LibraryServerConnectionState {
  const LibraryServerConnectionState({
    required this.isReady,
    required this.headline,
    required this.detail,
  });

  final bool isReady;
  final String headline;
  final String detail;
}

final libraryServerConnectionProvider =
    FutureProvider.autoDispose<LibraryServerConnectionState>((ref) async {
      final settings = await ref.watch(
        runtimeConnectionSettingsProvider.future,
      );
      final api = SyncApiClient(
        baseUrl: settings.apiBaseUrl,
        authToken: settings.authToken,
      );

      try {
        await api.fetchProjects();
        return const LibraryServerConnectionState(
          isReady: true,
          headline: 'Server ready',
          detail: 'You can upload the book and start sync.',
        );
      } on ApiClientException catch (error) {
        final baseUrl = settings.apiBaseUrl.trim();
        if (error.code == 'auth_invalid') {
          return const LibraryServerConnectionState(
            isReady: false,
            headline: 'Update the server token',
            detail:
                'This server rejected the saved token. Open Connection and paste the correct token before starting sync.',
          );
        }
        if (baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1')) {
          return const LibraryServerConnectionState(
            isReady: false,
            headline: 'Connect your server first',
            detail:
                'This app is still pointing at a local development server. Open Connection and enter your real server URL before starting sync.',
          );
        }
        if (error.code == null && error.message.contains('could not reach')) {
          return const LibraryServerConnectionState(
            isReady: false,
            headline: 'Check the server address',
            detail:
                'Sync could not reach this server from the app. Check the server URL, token, or Tailscale path in Connection and try again.',
          );
        }
        return LibraryServerConnectionState(
          isReady: false,
          headline: 'Server unavailable',
          detail:
              'Sync cannot use this server yet. ${error.message} Open Connection to fix the address or token.',
        );
      }
    });

bool _canOpenReaderProject(AsyncValue<ReaderProjectBundle> project) {
  final bundle = project.asData?.value;
  if (bundle == null) {
    return false;
  }

  switch (bundle.source) {
    case ReaderContentSource.api:
    case ReaderContentSource.offlineCache:
    case ReaderContentSource.demoFallback:
      return true;
    case ReaderContentSource.selectionRequired:
    case ReaderContentSource.artifactPending:
    case ReaderContentSource.projectError:
      return false;
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ReaderPalette.of(context);
    final currentSettings = ref.watch(runtimeConnectionSettingsProvider);
    final recentConnections = ref.watch(
      recentRuntimeConnectionSettingsProvider,
    );
    final recentLocations = ref.watch(recentReaderLocationsProvider);
    final importState = ref.watch(libraryImportProvider);
    final currentProject = ref.watch(readerProjectProvider);
    final audioDownload = ref.watch(readerAudioDownloadProvider);
    final audioActions = ref.read(readerAudioDownloadProvider.notifier);
    final serverConnection = ref.watch(libraryServerConnectionProvider);
    final canOpenCurrentReader = _canOpenReaderProject(currentProject);

    final recentConnectionCount = recentConnections.asData?.value.length ?? 0;
    final recentBookCount = recentLocations.asData?.value.length ?? 0;

    final hasDraft =
        importState.epubFile != null || importState.audioFiles.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.backgroundBase),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1120;
            final importSection = _LibrarySection(
              title: 'Add a Book',
              description:
                  'Choose the book, add the audiobook, and start building a synced reading experience from this device.',
              icon: Icons.upload_file_rounded,
              child: _ImportComposer(
                state: importState,
                serverConnection: serverConnection,
                onOpenConnection: () async {
                  final settings = await ref.read(
                    runtimeConnectionSettingsProvider.future,
                  );
                  if (context.mounted) {
                    await _openConnection(context, ref, settings);
                  }
                },
              ),
            );
            final scannedFolderSection = importState.scannedDeviceBooks.isEmpty
                ? null
                : _LibrarySection(
                    title: 'Found in This Folder',
                    description:
                        'Choose a book pair from the folder you scanned and let Sync fill the draft for you.',
                    icon: Icons.folder_special_rounded,
                    child: _ScannedDeviceBookShelf(
                      candidates: importState.scannedDeviceBooks,
                    ),
                  );
            final currentTargetSection = _LibrarySection(
              title: 'Continue Reading',
              description:
                  'Keep the current book, reading progress, and device download state together so resuming stays immediate.',
              icon: Icons.radio_button_checked_rounded,
              footer: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: canOpenCurrentReader
                        ? () => ref.read(homeTabProvider.notifier).showReader()
                        : null,
                    icon: const Icon(Icons.book_online_rounded),
                    label: Text(
                      canOpenCurrentReader
                          ? 'Continue Book'
                          : 'Book not ready yet',
                    ),
                  ),
                  currentSettings.maybeWhen(
                    data: (settings) => settings.projectId.trim().isEmpty
                        ? const SizedBox.shrink()
                        : OutlinedButton.icon(
                            onPressed: () =>
                                _forgetConnection(context, ref, settings),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Remove From Shelf'),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
              child: currentSettings.when(
                data: (settings) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProjectTargetSummary(
                      settings: settings,
                      onOpen: () => _openConnection(context, ref, settings),
                    ),
                    const SizedBox(height: 14),
                    _CurrentTargetOfflineManager(
                      settings: settings,
                      project: currentProject,
                      downloadState: audioDownload,
                      onDownload: audioActions.downloadCurrentProject,
                      onRemove: audioActions.removeCurrentProjectAudio,
                    ),
                  ],
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => Text(
                  'Could not load the current book. ${formatSyncApiError(error)}',
                ),
              ),
            );
            final queueSection = _LibrarySection(
              title: 'Getting Ready',
              description:
                  'Watch books that are still being prepared before they are fully ready to read.',
              icon: Icons.sync_rounded,
              child: recentConnections.when(
                data: (items) => _ProcessingQueueList(
                  connections: items.take(6).toList(growable: false),
                  currentIdentityKey: currentSettings.asData?.value.identityKey,
                  onSetTarget: (settings) =>
                      _setConnectionTarget(context, ref, settings),
                  onOpen: (settings) => _openConnection(context, ref, settings),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Text(
                  'Could not inspect recent projects. ${formatSyncApiError(error)}',
                ),
              ),
            );
            final recentBooksSection = _LibrarySection(
              title: 'Books on This Device',
              description:
                  'Books you have already opened here, with your place and progress kept close.',
              icon: Icons.history_edu_rounded,
              child: recentLocations.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'No books have been opened on this device yet. Start reading once and they will appear here.',
                    );
                  }
                  return Column(
                    children: [
                      for (final item in items.take(6))
                        _LibraryBookTile(
                          snapshot: item,
                          onResume: () => _resumeRecentBook(context, ref, item),
                        ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Text(
                  'Could not read library history. ${formatSyncApiError(error)}',
                ),
              ),
            );
            final recentProjectsSection = _LibrarySection(
              title: 'Your Books',
              description:
                  'Every book on your shelf, with readiness, progress, and device availability in one place.',
              icon: Icons.dns_rounded,
              child: recentConnections.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'Books you choose from the reader will appear here so you can reopen them quickly.',
                    );
                  }
                  return Column(
                    children: [
                      for (final item in items.take(6))
                        _ProjectSnapshotTile(
                          settings: item,
                          currentIdentityKey:
                              currentSettings.asData?.value.identityKey,
                          audioDownloadState: audioDownload,
                          onDownloadAudio: () =>
                              _downloadProjectAudio(context, ref, item),
                          onRemoveAudio: () =>
                              _removeProjectAudio(context, ref, item),
                          onSetTarget: () =>
                              _setConnectionTarget(context, ref, item),
                          onOpen: () => _openConnection(context, ref, item),
                          onForget: () => _forgetConnection(context, ref, item),
                        ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Text(
                  'Could not read recent connections. ${formatSyncApiError(error)}',
                ),
              ),
            );

            if (!isWide) {
              return _LibraryMobileHome(
                importState: importState,
                currentSettings: currentSettings,
                currentProject: currentProject,
                serverConnection: serverConnection,
                recentConnections: recentConnections,
                recentLocations: recentLocations,
                audioDownload: audioDownload,
                onOpenReader: () =>
                    ref.read(homeTabProvider.notifier).showReader(),
                onOpenConnection: (settings) =>
                    _openConnection(context, ref, settings),
                onSetTarget: (settings) =>
                    _setConnectionTarget(context, ref, settings),
                onForgetConnection: (settings) =>
                    _forgetConnection(context, ref, settings),
                onDownloadAudio: (settings) =>
                    _downloadProjectAudio(context, ref, settings),
                onRemoveAudio: (settings) =>
                    _removeProjectAudio(context, ref, settings),
                onResumeRecentBook: (item) =>
                    _resumeRecentBook(context, ref, item),
                onOpenServerProject: (project) =>
                    _setServerProjectTarget(context, ref, project),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LibraryHero(
                        recentConnectionCount: recentConnectionCount,
                        recentBookCount: recentBookCount,
                        hasDraft: hasDraft,
                      ),
                      const SizedBox(height: 18),
                      serverConnection.when(
                        data: (state) => state.isReady
                            ? const SizedBox.shrink()
                            : _LibrarySection(
                                title: 'Connect Your Server',
                                description:
                                    'Sync needs a reachable self-hosted backend before it can start processing books.',
                                icon: Icons.cloud_sync_rounded,
                                child: _ImportServerCallout(
                                  headline: state.headline,
                                  detail: state.detail,
                                  onOpenConnection: () async {
                                    final settings = await ref.read(
                                      runtimeConnectionSettingsProvider.future,
                                    );
                                    if (context.mounted) {
                                      await _openConnection(
                                        context,
                                        ref,
                                        settings,
                                      );
                                    }
                                  },
                                ),
                              ),
                        loading: () => const _LibrarySection(
                          title: 'Connect Your Server',
                          description:
                              'Checking whether the current backend is reachable before Sync starts processing books.',
                          icon: Icons.cloud_sync_rounded,
                          child: _ImportServerCallout(
                            headline: 'Checking server',
                            detail:
                                'Verifying that the current server is reachable before starting sync.',
                          ),
                        ),
                        error: (error, _) => _LibrarySection(
                          title: 'Connect Your Server',
                          description:
                              'Sync needs a reachable self-hosted backend before it can start processing books.',
                          icon: Icons.cloud_sync_rounded,
                          child: _ImportServerCallout(
                            headline: 'Connect your server first',
                            detail: formatSyncApiError(error),
                            onOpenConnection: () async {
                              final settings = await ref.read(
                                runtimeConnectionSettingsProvider.future,
                              );
                              if (context.mounted) {
                                await _openConnection(context, ref, settings);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 11,
                              child: Column(
                                children: [
                                  importSection,
                                  if (scannedFolderSection != null) ...[
                                    const SizedBox(height: 16),
                                    scannedFolderSection,
                                  ],
                                  const SizedBox(height: 16),
                                  currentTargetSection,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 9,
                              child: Column(
                                children: [
                                  queueSection,
                                  const SizedBox(height: 16),
                                  recentProjectsSection,
                                  const SizedBox(height: 16),
                                  recentBooksSection,
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _applyConnection(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings, {
    required bool showReader,
    required String feedback,
  }) async {
    await ref.read(runtimeConnectionSettingsProvider.notifier).save(settings);
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.invalidate(libraryOfflineSnapshotProvider(settings));
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (showReader) {
      ref.read(homeTabProvider.notifier).showReader();
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(feedback)));
    }
  }

  Future<void> _openConnection(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await _applyConnection(
      context,
      ref,
      settings,
      showReader: true,
      feedback: 'Opened the selected book on ${settings.shortHost}.',
    );
  }

  Future<void> _setConnectionTarget(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await _applyConnection(
      context,
      ref,
      settings,
      showReader: false,
      feedback:
          'Set the selected book on ${settings.shortHost} as your current book.',
    );
  }

  Future<void> _forgetConnection(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await ref
        .read(runtimeConnectionSettingsProvider.notifier)
        .removeRecent(settings);
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Removed the saved book from your shelf on ${settings.shortHost}.',
          ),
        ),
      );
    }
  }

  Future<void> _downloadProjectAudio(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await ref
        .read(readerAudioDownloadProvider.notifier)
        .downloadProject(settings);
    ref.invalidate(libraryOfflineSnapshotProvider(settings));
    if (context.mounted) {
      ref.invalidate(libraryProjectSnapshotProvider(settings));
    }
  }

  Future<void> _removeProjectAudio(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await ref
        .read(readerAudioDownloadProvider.notifier)
        .removeProjectAudio(settings);
    ref.invalidate(libraryOfflineSnapshotProvider(settings));
    if (context.mounted) {
      ref.invalidate(libraryProjectSnapshotProvider(settings));
    }
  }

  Future<void> _resumeRecentBook(
    BuildContext context,
    WidgetRef ref,
    ReaderLocationSnapshot snapshot,
  ) async {
    final current = await ref.read(runtimeConnectionSettingsProvider.future);
    final recentSettings = await ref.read(
      recentRuntimeConnectionSettingsProvider.future,
    );
    if (!context.mounted) {
      return;
    }
    final settings =
        recentSettings
            .cast<RuntimeConnectionSettings?>()
            .firstWhere(
              (item) => item?.identityKey == snapshot.identityKey,
              orElse: () => null,
            )
            ?.copyWith(
              authToken: snapshot.authToken.trim().isNotEmpty
                  ? snapshot.authToken
                  : null,
            ) ??
        RuntimeConnectionSettings(
          apiBaseUrl: snapshot.normalizedApiBaseUrl.isEmpty
              ? current.apiBaseUrl
              : snapshot.normalizedApiBaseUrl,
          projectId: snapshot.projectId,
          authToken: snapshot.authToken.trim().isNotEmpty
              ? snapshot.authToken
              : snapshot.normalizedApiBaseUrl.isEmpty ||
                    snapshot.normalizedApiBaseUrl ==
                        current.normalizedApiBaseUrl
              ? current.authToken
              : '',
        );
    await _openConnection(context, ref, settings);
  }

  Future<void> _setServerProjectTarget(
    BuildContext context,
    WidgetRef ref,
    ProjectListItem project,
  ) async {
    final currentSettings = await ref.read(
      runtimeConnectionSettingsProvider.future,
    );
    if (!context.mounted) {
      return;
    }
    final isReadyToOpen =
        project.lifecycle?.isReadable == true ||
        project.latestJob?.status == 'completed';
    await _applyConnection(
      context,
      ref,
      currentSettings.copyWith(projectId: project.projectId),
      showReader: isReadyToOpen,
      feedback: isReadyToOpen
          ? 'Opened ${project.title}.'
          : 'Selected ${project.title}. You can watch progress from the library while sync finishes.',
    );
  }
}

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({
    required this.recentConnectionCount,
    required this.recentBookCount,
    required this.hasDraft,
  });

  final int recentConnectionCount;
  final int recentBookCount;
  final bool hasDraft;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: palette.borderSubtle),
        color: palette.backgroundElevated,
        boxShadow: [
          BoxShadow(
            color: palette.shellShadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accentPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'LIBRARY',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.accentPrimary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Build a shelf that is ready to read, not just uploaded.',
                  style: theme.textTheme.headlineLarge?.copyWith(height: 0.98),
                ),
                const SizedBox(height: 10),
                Text(
                  'Add books, watch sync progress, keep downloads on-device, and jump back into the exact page you left without detouring through setup screens.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _LibraryMetric(
                        label: 'Books on shelf',
                        value: '$recentConnectionCount',
                        icon: Icons.cloud_queue_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LibraryMetric(
                        label: 'Books on device',
                        value: '$recentBookCount',
                        icon: Icons.menu_book_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: palette.backgroundBase.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasDraft ? Icons.edit_note_rounded : Icons.check_circle,
                        color: hasDraft
                            ? palette.accentPrimary
                            : palette.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasDraft
                              ? 'Book draft in progress'
                              : 'Shelf is ready',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryMetric extends StatelessWidget {
  const _LibraryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.accentPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryMobileHome extends ConsumerWidget {
  const _LibraryMobileHome({
    required this.importState,
    required this.currentSettings,
    required this.currentProject,
    required this.serverConnection,
    required this.recentConnections,
    required this.recentLocations,
    required this.audioDownload,
    required this.onOpenReader,
    required this.onOpenConnection,
    required this.onSetTarget,
    required this.onForgetConnection,
    required this.onDownloadAudio,
    required this.onRemoveAudio,
    required this.onResumeRecentBook,
    required this.onOpenServerProject,
  });

  final LibraryImportState importState;
  final AsyncValue<RuntimeConnectionSettings> currentSettings;
  final AsyncValue<ReaderProjectBundle> currentProject;
  final AsyncValue<LibraryServerConnectionState> serverConnection;
  final AsyncValue<List<RuntimeConnectionSettings>> recentConnections;
  final AsyncValue<List<ReaderLocationSnapshot>> recentLocations;
  final ReaderAudioDownloadState audioDownload;
  final VoidCallback onOpenReader;
  final Future<void> Function(RuntimeConnectionSettings settings)
  onOpenConnection;
  final Future<void> Function(RuntimeConnectionSettings settings) onSetTarget;
  final Future<void> Function(RuntimeConnectionSettings settings)
  onForgetConnection;
  final Future<void> Function(RuntimeConnectionSettings settings)
  onDownloadAudio;
  final Future<void> Function(RuntimeConnectionSettings settings) onRemoveAudio;
  final Future<void> Function(ReaderLocationSnapshot item) onResumeRecentBook;
  final Future<void> Function(ProjectListItem project) onOpenServerProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final serverProjects = ref.watch(libraryServerProjectsProvider);
    final canOpenCurrentReader = _canOpenReaderProject(currentProject);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          surfaceTintColor: Colors.transparent,
          backgroundColor: palette.backgroundBase.withValues(alpha: 0.96),
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sync', style: theme.textTheme.headlineSmall),
              Text(
                'Continue reading, add a book, or keep titles offline.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              serverConnection.when(
                data: (state) => state.isReady
                    ? const SizedBox.shrink()
                    : _MobileSectionCard(
                        title: 'Connect Your Server',
                        subtitle:
                            'Sync needs a reachable backend before it can upload files and start processing.',
                        child: _ImportServerCallout(
                          headline: state.headline,
                          detail: state.detail,
                          onOpenConnection: () async {
                            final settings = await ref.read(
                              runtimeConnectionSettingsProvider.future,
                            );
                            if (context.mounted) {
                              await onOpenConnection(settings);
                            }
                          },
                        ),
                      ),
                loading: () => const _MobileSectionCard(
                  title: 'Connect Your Server',
                  subtitle:
                      'Checking whether the current backend is reachable before Sync starts processing.',
                  child: _ImportServerCallout(
                    headline: 'Checking server',
                    detail:
                        'Verifying that the current server is reachable before starting sync.',
                  ),
                ),
                error: (error, _) => _MobileSectionCard(
                  title: 'Connect Your Server',
                  subtitle:
                      'Sync needs a reachable backend before it can upload files and start processing.',
                  child: _ImportServerCallout(
                    headline: 'Connect your server first',
                    detail: formatSyncApiError(error),
                    onOpenConnection: () async {
                      final settings = await ref.read(
                        runtimeConnectionSettingsProvider.future,
                      );
                      if (context.mounted) {
                        await onOpenConnection(settings);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _MobileSectionCard(
                title: 'Continue Reading',
                subtitle:
                    'Return to the book you are already reading, with progress and downloads ready.',
                child: currentSettings.when(
                  data: (settings) {
                    final hasProject = settings.normalizedProjectId.isNotEmpty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProjectTargetSummary(
                          settings: settings,
                          onOpen: () => onOpenConnection(settings),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: hasProject && canOpenCurrentReader
                              ? onOpenReader
                              : null,
                          icon: const Icon(Icons.play_circle_rounded),
                          label: Text(
                            !hasProject
                                ? 'Choose a book first'
                                : canOpenCurrentReader
                                ? 'Continue book'
                                : 'Book not ready yet',
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(formatSyncApiError(error)),
                ),
              ),
              const SizedBox(height: 14),
              _MobileSectionCard(
                title: 'Add a Book',
                subtitle:
                    'Choose the EPUB, add the audiobook files, and let Sync prepare the timeline.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImportProgressRail(state: importState),
                    const SizedBox(height: 12),
                    _ImportComposer(
                      state: importState,
                      serverConnection: serverConnection,
                      onOpenConnection: () async {
                        final settings = await ref.read(
                          runtimeConnectionSettingsProvider.future,
                        );
                        if (context.mounted) {
                          await onOpenConnection(settings);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (importState.scannedDeviceBooks.isNotEmpty) ...[
                const SizedBox(height: 14),
                _MobileSectionCard(
                  title: 'Found in This Folder',
                  subtitle:
                      'Pick one of the matched books from the folder you scanned and Sync will fill the draft.',
                  child: _ScannedDeviceBookShelf(
                    candidates: importState.scannedDeviceBooks,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _MobileSectionCard(
                title: 'Your Books',
                subtitle:
                    'Pick a book from your server. Ready books open directly, and syncing books stay visible here.',
                child: serverProjects.when(
                  data: (projects) {
                    if (projects.isEmpty) {
                      return Text(
                        'No books found yet. Add one above to create your first book on this server.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final project in projects.take(6))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(project.title),
                            subtitle: Text(
                              [
                                if (project.language?.isNotEmpty == true)
                                  project.language,
                                '${project.audioAssetCount} audio',
                                _projectListStatusLabel(project),
                              ].whereType<String>().join(' • '),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => onOpenServerProject(project),
                          ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(formatSyncApiError(error)),
                ),
              ),
              const SizedBox(height: 14),
              _MobileSectionCard(
                title: 'Getting Ready',
                subtitle:
                    'Keep an eye on books that are still being prepared before they move onto your main shelf.',
                child: recentConnections.when(
                  data: (items) => _ProcessingQueueList(
                    connections: items.take(6).toList(growable: false),
                    currentIdentityKey:
                        currentSettings.asData?.value.identityKey,
                    onSetTarget: onSetTarget,
                    onOpen: onOpenConnection,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(formatSyncApiError(error)),
                ),
              ),
              const SizedBox(height: 14),
              _MobileSectionCard(
                title: 'Books on This Device',
                subtitle:
                    'Books you have already opened here, with your place saved.',
                child: recentLocations.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Text(
                        'Once you open a book on this device, it will appear here for quick return.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final item in items.take(4))
                          _LibraryBookTile(
                            snapshot: item,
                            onResume: () => onResumeRecentBook(item),
                          ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(formatSyncApiError(error)),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

String _projectListStatusLabel(ProjectListItem project) {
  final lifecyclePhase = project.lifecycle?.phase;
  if (lifecyclePhase != null && lifecyclePhase.isNotEmpty) {
    return _lifecyclePhaseLabel(lifecyclePhase);
  }
  final status = project.latestJob?.status ?? project.status;
  return switch (status) {
    'completed' => 'Ready',
    'running' => 'Syncing',
    'queued' => 'Waiting',
    'failed' => 'Needs attention',
    'cancelled' => 'Cancelled',
    _ => _capitalizeLabel(status.replaceAll('_', ' ')),
  };
}

String _lifecyclePhaseLabel(String phase) {
  return switch (phase) {
    'draft' => 'Needs files',
    'ready_to_align' => 'Ready to sync',
    'aligning' => 'Syncing',
    'ready_to_read' => 'Ready',
    'attention_needed' => 'Needs attention',
    _ => _capitalizeLabel(phase.replaceAll('_', ' ')),
  };
}

class _MobileSectionCard extends StatelessWidget {
  const _MobileSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    return Material(
      color: palette.backgroundElevated,
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportProgressRail extends StatelessWidget {
  const _ImportProgressRail({required this.state});

  final LibraryImportState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ReaderPalette.of(context);
    final steps = [
      ('Book', state.epubFile != null),
      ('Audio', state.audioFiles.isNotEmpty),
      ('Details', state.title.trim().isNotEmpty),
      ('Sync', state.status == LibraryImportStatus.completed),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final step in steps)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: step.$2
                  ? palette.accentSoft.withValues(alpha: 0.75)
                  : palette.backgroundBase,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Text(
              step.$1,
              style: theme.textTheme.labelMedium?.copyWith(
                color: step.$2 ? palette.textPrimary : palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
    this.footer,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);

    return Material(
      color: palette.backgroundElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: palette.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: palette.accentPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            child,
            if (footer != null) ...[const SizedBox(height: 14), footer!],
          ],
        ),
      ),
    );
  }
}

class _ImportComposer extends ConsumerStatefulWidget {
  const _ImportComposer({
    required this.state,
    required this.serverConnection,
    required this.onOpenConnection,
  });

  final LibraryImportState state;
  final AsyncValue<LibraryServerConnectionState> serverConnection;
  final Future<void> Function() onOpenConnection;

  @override
  ConsumerState<_ImportComposer> createState() => _ImportComposerState();
}

class _ImportComposerState extends ConsumerState<_ImportComposer> {
  late final TextEditingController _titleController;
  late final TextEditingController _languageController;
  late bool _showManualDetails;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.state.title);
    _languageController = TextEditingController(text: widget.state.language);
    _showManualDetails = widget.state.title.trim().isEmpty;
  }

  @override
  void didUpdateWidget(covariant _ImportComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.title != _titleController.text) {
      _titleController.text = widget.state.title;
    }
    if (widget.state.language != _languageController.text) {
      _languageController.text = widget.state.language;
    }
    if (oldWidget.state.title.trim().isEmpty &&
        widget.state.title.trim().isNotEmpty) {
      _showManualDetails = false;
    } else if (widget.state.title.trim().isEmpty) {
      _showManualDetails = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final actions = ref.read(libraryImportProvider.notifier);
    final hasDraft =
        widget.state.epubFile != null || widget.state.audioFiles.isNotEmpty;
    final hasRecognizedTitle = widget.state.title.trim().isNotEmpty;
    final connectionState = widget.serverConnection;
    final isServerReady = connectionState.asData?.value.isReady == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 860;
            final metadata = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasRecognizedTitle) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: palette.backgroundBase,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: palette.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Book details',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.state.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _LibraryStatusChip(
                              label: widget.state.language.trim().isEmpty
                                  ? 'Language not set'
                                  : widget.state.language.trim().toUpperCase(),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showManualDetails = !_showManualDetails;
                                });
                              },
                              icon: Icon(
                                _showManualDetails
                                    ? Icons.expand_less_rounded
                                    : Icons.edit_rounded,
                              ),
                              label: Text(
                                _showManualDetails
                                    ? 'Hide manual details'
                                    : 'Edit details',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!hasRecognizedTitle || _showManualDetails) ...[
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Book Title'),
                    onChanged: actions.setTitle,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _languageController,
                    decoration: const InputDecoration(
                      labelText: 'Language',
                      helperText:
                          'Optional. Leave the default unless you need to change it.',
                    ),
                    onChanged: actions.setLanguage,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Source files',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: widget.state.isBusy ? null : actions.pickEpub,
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: Text(
                        widget.state.epubFile == null
                            ? 'Choose EPUB'
                            : 'Replace EPUB',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: widget.state.isBusy
                          ? null
                          : actions.pickAudioFiles,
                      icon: const Icon(Icons.audiotrack_rounded),
                      label: Text(
                        widget.state.audioFiles.isEmpty
                            ? 'Choose Audiobook'
                            : 'Replace Audiobook',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.state.isBusy
                          ? null
                          : actions.scanDeviceBooks,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Scan a Folder'),
                    ),
                    if (widget.state.epubFile != null ||
                        widget.state.audioFiles.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: widget.state.isBusy
                            ? null
                            : actions.scanNearbyFiles,
                        icon: const Icon(Icons.travel_explore_rounded),
                        label: const Text('Scan Nearby Files'),
                      ),
                  ],
                ),
                if (!hasDraft) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Attach the book or audiobook first. Sync will look nearby for the rest.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ],
              ],
            );
            final workflow = Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                color: palette.backgroundBase.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import workflow',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  _ImportWorkflowRail(state: widget.state),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LibraryStatusChip(
                        label: widget.state.epubFile == null
                            ? 'EPUB missing'
                            : 'EPUB ready',
                      ),
                      _LibraryStatusChip(
                        label: widget.state.audioFiles.isEmpty
                            ? 'Audio missing'
                            : '${widget.state.audioFiles.length} audio ready',
                      ),
                      _LibraryStatusChip(
                        label: widget.state.canStartImport
                            ? 'Ready to align'
                            : 'Draft incomplete',
                      ),
                      if (widget.state.statusLabel != null)
                        _LibraryStatusChip(label: widget.state.statusLabel!),
                    ],
                  ),
                  if (widget.state.statusNarrative != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.state.statusNarrative!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ],
              ),
            );
            if (!split) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [metadata, const SizedBox(height: 16), workflow],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 12, child: metadata),
                const SizedBox(width: 16),
                Expanded(flex: 10, child: workflow),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (widget.state.epubFile != null) ...[
          _ImportFileTile(
            icon: Icons.menu_book_rounded,
            label: 'EPUB',
            name: widget.state.epubFile!.name,
            detail: _formatBytes(widget.state.epubFile!.sizeBytes),
          ),
        ],
        if (widget.state.suggestedEpubFile != null &&
            widget.state.epubFile == null) ...[
          _SuggestedImportTile(
            icon: Icons.menu_book_rounded,
            label: 'Nearby book found',
            name: widget.state.suggestedEpubFile!.name,
            detail: _formatBytes(widget.state.suggestedEpubFile!.sizeBytes),
            actionLabel: 'Use This Book',
            onUse: actions.useSuggestedEpubFile,
          ),
        ],
        if (widget.state.audioFiles.isNotEmpty) ...[
          if (widget.state.epubFile == null) const SizedBox(height: 4),
          for (final audio in widget.state.audioFiles)
            _ImportFileTile(
              icon: Icons.graphic_eq_rounded,
              label: 'Audio',
              name: audio.name,
              detail: _formatBytes(audio.sizeBytes),
              trailing: IconButton(
                onPressed: widget.state.isBusy
                    ? null
                    : () => actions.removeAudioFile(audio.name),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
        if (widget.state.suggestedAudioFiles.isNotEmpty &&
            widget.state.audioFiles.isEmpty) ...[
          _SuggestedImportTile(
            icon: Icons.headphones_rounded,
            label: 'Nearby audiobook found',
            name: widget.state.suggestedAudioFiles.length == 1
                ? widget.state.suggestedAudioFiles.first.name
                : '${widget.state.suggestedAudioFiles.length} audiobook files',
            detail: widget.state.suggestedAudioFiles.length == 1
                ? _formatBytes(widget.state.suggestedAudioFiles.first.sizeBytes)
                : 'Same folder as the selected book',
            actionLabel: 'Use These Files',
            onUse: actions.useSuggestedAudioFiles,
          ),
        ],
        if (widget.state.message != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.state.status == LibraryImportStatus.failed
                  ? palette.accentSoft
                  : palette.backgroundBase,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Text(widget.state.message!),
          ),
        ],
        const SizedBox(height: 16),
        connectionState.when(
          data: (state) => state.isReady
              ? const SizedBox.shrink()
              : _ImportServerCallout(
                  headline: state.headline,
                  detail: state.detail,
                  onOpenConnection: widget.onOpenConnection,
                ),
          loading: () => const _ImportServerCallout(
            headline: 'Checking server',
            detail:
                'Verifying that the current server is reachable before starting sync.',
          ),
          error: (error, _) => _ImportServerCallout(
            headline: 'Connect your server first',
            detail: formatSyncApiError(error),
            onOpenConnection: widget.onOpenConnection,
          ),
        ),
        const SizedBox(height: 16),
        Text('Start Sync', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.state.isBusy || !isServerReady
                  ? null
                  : actions.startImport,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(
                widget.state.isBusy
                    ? 'Starting...'
                    : !isServerReady
                    ? 'Connect Server'
                    : widget.state.canStartImport
                    ? 'Start Sync'
                    : 'Add Missing Files',
              ),
            ),
            if (widget.state.epubFile != null ||
                widget.state.audioFiles.isNotEmpty)
              TextButton(
                onPressed: widget.state.isBusy ? null : actions.clearDraft,
                child: const Text('Clear Draft'),
              ),
          ],
        ),
        if (widget.state.status == LibraryImportStatus.completed &&
            widget.state.projectId != null &&
            widget.state.jobId != null) ...[
          const SizedBox(height: 16),
          _ImportCompletionBanner(
            state: widget.state,
            onOpenReader: actions.openImportedProject,
          ),
        ],
      ],
    );
  }
}

class _ImportWorkflowRail extends StatelessWidget {
  const _ImportWorkflowRail({required this.state});

  final LibraryImportState state;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final steps =
        <({String label, String description, bool complete, bool active})>[
          (
            label: 'Book',
            description: 'Choose the EPUB and title',
            complete: state.epubFile != null && state.title.trim().isNotEmpty,
            active: state.epubFile == null || state.title.trim().isEmpty,
          ),
          (
            label: 'Audiobook',
            description: 'Attach the listening files',
            complete: state.audioFiles.isNotEmpty,
            active:
                state.audioFiles.isEmpty &&
                (state.status == LibraryImportStatus.idle ||
                    state.status == LibraryImportStatus.picking ||
                    state.status == LibraryImportStatus.ready ||
                    state.status == LibraryImportStatus.failed),
          ),
          (
            label: 'Upload',
            description: 'Send the book and audiobook',
            complete:
                state.status.index > LibraryImportStatus.uploadingAudio.index,
            active:
                state.status == LibraryImportStatus.creatingProject ||
                state.status == LibraryImportStatus.uploadingEpub ||
                state.status == LibraryImportStatus.uploadingAudio,
          ),
          (
            label: 'Sync',
            description: 'Prepare synced reading',
            complete: state.status == LibraryImportStatus.completed,
            active: state.status == LibraryImportStatus.startingJob,
          ),
        ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: palette.backgroundBase.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workflow', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final step in steps)
                _ImportWorkflowStep(
                  label: step.label,
                  description: step.description,
                  isComplete: step.complete,
                  isActive: step.active,
                ),
            ],
          ),
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(
              state.message!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportWorkflowStep extends StatelessWidget {
  const _ImportWorkflowStep({
    required this.label,
    required this.description,
    required this.isComplete,
    required this.isActive,
  });

  final String label;
  final String description;
  final bool isComplete;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final tone = isComplete
        ? palette.success
        : isActive
        ? palette.accentPrimary
        : palette.textMuted;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? palette.accentPrimary : palette.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete
                    ? Icons.check_circle_rounded
                    : isActive
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ImportCompletionBanner extends ConsumerWidget {
  const _ImportCompletionBanner({
    required this.state,
    required this.onOpenReader,
  });

  final LibraryImportState state;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ReaderPalette.of(context);
    final connection = ref.watch(runtimeConnectionSettingsProvider);
    final importedSettings =
        connection.asData?.value == null || state.projectId == null
        ? null
        : RuntimeConnectionSettings(
            apiBaseUrl: connection.asData!.value.apiBaseUrl,
            projectId: state.projectId!,
            authToken: connection.asData!.value.authToken,
          );
    if (importedSettings != null) {
      ref.listen<AsyncValue<int>>(
        libraryProjectRefreshTickProvider(importedSettings),
        (_, _) {
          final snapshot = ref.read(
            libraryProjectSnapshotProvider(importedSettings),
          );
          final value = snapshot.asData?.value;
          final status = value?.latestJobStatus;
          final isTerminal =
              value?.lifecycleIsReadable == true ||
              status == 'completed' ||
              status == 'failed' ||
              status == 'cancelled';
          if (!isTerminal) {
            ref.invalidate(libraryProjectSnapshotProvider(importedSettings));
          }
        },
      );
    }
    final importedSnapshot = importedSettings == null
        ? null
        : ref.watch(libraryProjectSnapshotProvider(importedSettings));
    final importedProjectTitle = state.title.trim().isEmpty
        ? 'Your book'
        : state.title.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_rounded, color: palette.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your book is syncing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$importedProjectTitle is uploaded and processing now. Stay here to watch progress, and open the book as soon as synced reading is ready.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          if (importedSnapshot != null) ...[
            const SizedBox(height: 14),
            importedSnapshot.when(
              data: (snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.statusHeadline,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snapshot.statusNarrative,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                  if (snapshot.latestJobPercent != null) ...[
                    const SizedBox(height: 12),
                    _LibraryProgressMeter(
                      label: snapshot.latestJobStage == null
                          ? 'Alignment progress'
                          : _capitalizeLabel(
                              snapshot.latestJobStage!.replaceAll('_', ' '),
                            ),
                      percent: snapshot.latestJobPercent!,
                    ),
                  ],
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Text(
                'Live status unavailable right now. ${formatSyncApiError(error)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LibraryStatusChip(label: 'Sync started'),
              if (state.completedAt != null)
                _LibraryStatusChip(label: _formatTimestamp(state.completedAt!)),
            ],
          ),
          const SizedBox(height: 14),
          importedSnapshot?.maybeWhen(
                data: (snapshot) =>
                    snapshot.lifecycleIsReadable ||
                        snapshot.latestJobStatus == 'completed'
                    ? FilledButton.icon(
                        onPressed: onOpenReader,
                        icon: const Icon(Icons.chrome_reader_mode_rounded),
                        label: const Text('Open Book'),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: palette.backgroundChrome,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: palette.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sync_rounded, color: palette.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Stay in Library while Sync finishes. This book will move into Continue Reading as soon as the reader is ready.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                orElse: () => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: palette.backgroundChrome,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sync_rounded, color: palette.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checking the first sync status now. Stay here and Sync will update this book as soon as processing starts moving.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ) ??
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.backgroundChrome,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sync_rounded, color: palette.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Checking the first sync status now. Stay here and Sync will update this book as soon as processing starts moving.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ImportServerCallout extends StatelessWidget {
  const _ImportServerCallout({
    required this.headline,
    required this.detail,
    this.onOpenConnection,
  });

  final String headline;
  final String detail;
  final Future<void> Function()? onOpenConnection;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          if (onOpenConnection != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                onOpenConnection!();
              },
              icon: const Icon(Icons.settings_ethernet_rounded),
              label: const Text('Open Connection'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportFileTile extends StatelessWidget {
  const _ImportFileTile({
    required this.icon,
    required this.label,
    required this.name,
    required this.detail,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String name;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final trailingWidgets = trailing == null
        ? const <Widget>[]
        : <Widget>[trailing!];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.accentPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '$label • $detail',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          ...trailingWidgets,
        ],
      ),
    );
  }
}

class _SuggestedImportTile extends StatelessWidget {
  const _SuggestedImportTile({
    required this.icon,
    required this.label,
    required this.name,
    required this.detail,
    required this.actionLabel,
    required this.onUse,
  });

  final IconData icon;
  final String label;
  final String name;
  final String detail;
  final String actionLabel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.accentSoft.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: palette.accentPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onUse, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ScannedDeviceBookTile extends StatelessWidget {
  const _ScannedDeviceBookTile({
    required this.candidate,
    required this.actionLabel,
    required this.onUse,
  });

  final ImportBookCandidate candidate;
  final String actionLabel;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final audioLabel = candidate.audioFiles.isEmpty
        ? 'No audiobook found yet'
        : candidate.audioFiles.length == 1
        ? '1 audiobook file'
        : '${candidate.audioFiles.length} audiobook files';
    final coverBytes = candidate.coverBytes;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverBytes != null && coverBytes.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                Uint8List.fromList(coverBytes),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.folder_special_rounded),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.title),
                if (candidate.author?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    candidate.author!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${candidate.directoryLabel} • $audioLabel',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (candidate.epubFile != null)
                      const _LibraryStatusChip(label: 'EPUB found'),
                    _LibraryStatusChip(
                      label: candidate.audioFiles.isEmpty
                          ? 'Audio missing'
                          : 'Audio found',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: onUse,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannedDeviceBookShelf extends ConsumerWidget {
  const _ScannedDeviceBookShelf({required this.candidates});

  final List<ImportBookCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(libraryImportProvider.notifier);
    final readyCandidates = candidates
        .where((candidate) => candidate.epubFile != null)
        .toList(growable: false);
    final incompleteCandidates = candidates
        .where((candidate) => candidate.epubFile == null)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (readyCandidates.isNotEmpty) ...[
          Text(
            'Ready to import',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          for (final candidate in readyCandidates)
            _ScannedDeviceBookTile(
              candidate: candidate,
              actionLabel: 'Use This',
              onUse: () => actions.useScannedDeviceBook(candidate),
            ),
        ],
        if (incompleteCandidates.isNotEmpty) ...[
          if (readyCandidates.isNotEmpty) const SizedBox(height: 12),
          Text(
            'Need the book file',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'These audiobook files look promising, but Sync still needs the matching EPUB.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ReaderPalette.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 10),
          for (final candidate in incompleteCandidates)
            _ScannedDeviceBookTile(
              candidate: candidate,
              actionLabel: 'Use Audiobook Files',
              onUse: () => actions.useScannedDeviceBook(candidate),
            ),
        ],
      ],
    );
  }
}

class _LibraryBookTile extends StatelessWidget {
  const _LibraryBookTile({required this.snapshot, required this.onResume});

  final ReaderLocationSnapshot snapshot;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final progressPercent = (snapshot.progressFraction * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.accentSoft.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.menu_book_rounded, color: palette.textPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snapshot.sectionTitle ?? snapshot.projectId),
                const SizedBox(height: 6),
                _LibraryProgressMeter(
                  label: 'Reading progress',
                  percent: progressPercent,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (snapshot.shortHost.isNotEmpty)
                      _LibraryStatusChip(label: snapshot.shortHost),
                    _LibraryStatusChip(label: '$progressPercent% complete'),
                    _LibraryStatusChip(
                      label: snapshot.updatedAt
                          .toLocal()
                          .toIso8601String()
                          .substring(0, 16)
                          .replaceFirst('T', ' '),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMs(snapshot.positionMs),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onResume,
                child: const Text('Continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectTargetSummary extends ConsumerWidget {
  const _ProjectTargetSummary({required this.settings, required this.onOpen});

  final RuntimeConnectionSettings settings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (settings.projectId.trim().isEmpty) {
      final palette = ReaderPalette.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(settings.shortHost),
          const SizedBox(height: 8),
          Text(
            'No book is selected yet. Add one below or choose one from your shelf, then come back here to continue reading.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Choose a Book'),
          ),
        ],
      );
    }

    final snapshot = ref.watch(libraryProjectSnapshotProvider(settings));
    final offline = ref.watch(libraryOfflineSnapshotProvider(settings));
    return snapshot.when(
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value.title),
          const SizedBox(height: 8),
          Text(
            '${settings.shortHost} • ${value.statusNarrative}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ReaderPalette.of(context).textMuted,
            ),
          ),
          if (value.latestJobPercent != null) ...[
            const SizedBox(height: 12),
            _LibraryProgressMeter(
              label: value.latestJobStage == null
                  ? 'Preparation progress'
                  : _capitalizeLabel(
                      value.latestJobStage!.replaceAll('_', ' '),
                    ),
              percent: value.latestJobPercent!,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LibraryStatusChip(label: value.projectStatusLabel),
              if (value.latestJobLabel case final jobLabel?)
                _LibraryStatusChip(label: jobLabel),
              if (value.latestJobAttempt != null)
                _LibraryStatusChip(label: 'Attempt ${value.latestJobAttempt}'),
              _LibraryStatusChip(label: '${value.audioAssetCount} audio'),
              _LibraryStatusChip(label: '${value.epubAssetCount} EPUB'),
              ...offline.maybeWhen(
                data: (offlineValue) =>
                    _offlineStatusChips(offlineValue, value.audioAssetCount),
                orElse: () => const <Widget>[],
              ),
            ],
          ),
        ],
      ),
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current book'),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current book'),
          const SizedBox(height: 8),
          Text(
            'Could not fetch project snapshot. ${formatSyncApiError(error)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _CurrentTargetOfflineManager extends ConsumerWidget {
  const _CurrentTargetOfflineManager({
    required this.settings,
    required this.project,
    required this.downloadState,
    required this.onDownload,
    required this.onRemove,
  });

  final RuntimeConnectionSettings settings;
  final AsyncValue<ReaderProjectBundle> project;
  final ReaderAudioDownloadState downloadState;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ReaderPalette.of(context);
    if (settings.projectId.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: palette.backgroundBase,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Books on This Device',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Device downloads start after you choose a book. Pick one from your shelf or add a new one first.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      );
    }
    final offline = ref.watch(libraryOfflineSnapshotProvider(settings));

    String message;
    List<Widget> actions = const <Widget>[];

    final bundle = project.asData?.value;
    if (project.isLoading) {
      message =
          'Book details are still loading. Device download options will sharpen as soon as the reading bundle is ready.';
    } else if (project.hasError) {
      message =
          'This book is not reachable live right now. You can still manage device copies here and refresh when the connection comes back.';
    } else if (bundle == null || bundle.totalAudioAssets == 0) {
      message =
          'This book does not have playable audiobook files yet. Text can still load, but there is no audio package to store on the device.';
    } else if (downloadState.status == ReaderAudioDownloadStatus.downloading) {
      message =
          'Saving audio ${downloadState.completedAssets + 1} of ${downloadState.totalAssets > 0 ? downloadState.totalAssets : bundle.totalAudioAssets} to this device for offline reading.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Saving to Device'),
        ),
      ];
    } else if (bundle.hasCompleteOfflineAudio) {
      message =
          'This book is fully stored on this device. You can remove the local audio here whenever you need space.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: downloadState.isBusy ? null : onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Remove From Device'),
        ),
      ];
    } else {
      message =
          'Audio is still streaming for this book. Save it here to make the reading experience available offline.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: downloadState.isBusy ? null : onDownload,
          icon: const Icon(Icons.download_for_offline_rounded),
          label: Text(
            bundle.cachedAudioAssets > 0
                ? 'Save Remaining Audio'
                : 'Save Audio to Device',
          ),
        ),
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Books on This Device',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          if (downloadState.message != null) ...[
            const SizedBox(height: 10),
            Text(
              downloadState.message!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
          if (downloadState.status ==
              ReaderAudioDownloadStatus.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: downloadState.progress),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...offline.maybeWhen(
                data: (value) =>
                    _offlineStatusChips(value, bundle?.totalAudioAssets ?? 0),
                orElse: () => const <Widget>[],
              ),
              if (bundle != null)
                _LibraryStatusChip(
                  label:
                      'Audio ${bundle.cachedAudioAssets}/${bundle.totalAudioAssets}',
                ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
      ),
    );
  }
}

class _ProcessingQueueList extends StatelessWidget {
  const _ProcessingQueueList({
    required this.connections,
    required this.currentIdentityKey,
    required this.onSetTarget,
    required this.onOpen,
  });

  final List<RuntimeConnectionSettings> connections;
  final String? currentIdentityKey;
  final ValueChanged<RuntimeConnectionSettings> onSetTarget;
  final ValueChanged<RuntimeConnectionSettings> onOpen;

  @override
  Widget build(BuildContext context) {
    if (connections.isEmpty) {
      return const Text(
        'No books are getting ready right now. Add one and its progress will appear here.',
      );
    }

    return Column(
      children: [
        for (final connection in connections)
          _QueueSnapshotTile(
            settings: connection,
            isCurrentTarget: connection.identityKey == currentIdentityKey,
            onSetTarget: () => onSetTarget(connection),
            onOpen: () => onOpen(connection),
          ),
      ],
    );
  }
}

class _QueueSnapshotTile extends ConsumerWidget {
  const _QueueSnapshotTile({
    required this.settings,
    required this.isCurrentTarget,
    required this.onSetTarget,
    required this.onOpen,
  });

  final RuntimeConnectionSettings settings;
  final bool isCurrentTarget;
  final VoidCallback onSetTarget;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(libraryProjectSnapshotProvider(settings));
    return snapshot.when(
      data: (value) {
        if (!value.hasActiveJob) {
          return const SizedBox.shrink();
        }
        final palette = ReaderPalette.of(context);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: palette.backgroundBase,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.accentPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.sync_rounded, color: palette.accentPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value.title),
                    const SizedBox(height: 6),
                    Text(
                      '${settings.shortHost} • ${value.latestJobLabel ?? value.projectStatusLabel}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value.statusHeadline,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    if (value.latestJobPercent != null) ...[
                      const SizedBox(height: 10),
                      _LibraryProgressMeter(
                        label: value.latestJobStage == null
                            ? 'Active job'
                            : _capitalizeLabel(
                                value.latestJobStage!.replaceAll('_', ' '),
                              ),
                        percent: value.latestJobPercent!,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isCurrentTarget)
                          const _LibraryStatusChip(label: 'Current book'),
                        _LibraryStatusChip(
                          label:
                              '${value.audioAssetCount} audio • ${value.epubAssetCount} EPUB',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isCurrentTarget)
                    TextButton(
                      onPressed: onSetTarget,
                      child: const Text('Make Current'),
                    ),
                  FilledButton.tonal(
                    onPressed: onOpen,
                    child: const Text('Open Book'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}

class _ProjectSnapshotTile extends ConsumerWidget {
  const _ProjectSnapshotTile({
    required this.settings,
    required this.currentIdentityKey,
    required this.audioDownloadState,
    required this.onDownloadAudio,
    required this.onRemoveAudio,
    required this.onSetTarget,
    required this.onOpen,
    required this.onForget,
  });

  final RuntimeConnectionSettings settings;
  final String? currentIdentityKey;
  final ReaderAudioDownloadState audioDownloadState;
  final Future<void> Function() onDownloadAudio;
  final Future<void> Function() onRemoveAudio;
  final VoidCallback onSetTarget;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(libraryProjectSnapshotProvider(settings));
    final offline = ref.watch(libraryOfflineSnapshotProvider(settings));
    final theme = Theme.of(context);
    return snapshot.when(
      data: (value) => _ProjectSnapshotCard(
        settings: settings,
        value: value,
        offline: offline,
        isCurrentTarget: settings.identityKey == currentIdentityKey,
        audioDownloadState: audioDownloadState,
        onDownloadAudio: onDownloadAudio,
        onRemoveAudio: onRemoveAudio,
        onSetTarget: onSetTarget,
        onOpen: onOpen,
        onForget: onForget,
      ),
      loading: () => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('Saved book'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(settings.shortHost),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ),
      ),
      error: (error, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_off_rounded),
        title: const Text('Saved book'),
        subtitle: Text(
          '${settings.shortHost} • Could not load this saved book. ${formatSyncApiError(error)}',
          style: theme.textTheme.bodyMedium,
        ),
        trailing: FilledButton.tonal(
          onPressed: onOpen,
          child: const Text('Open'),
        ),
      ),
    );
  }
}

class _ProjectSnapshotCard extends StatelessWidget {
  const _ProjectSnapshotCard({
    required this.settings,
    required this.value,
    required this.offline,
    required this.isCurrentTarget,
    required this.audioDownloadState,
    required this.onDownloadAudio,
    required this.onRemoveAudio,
    required this.onSetTarget,
    required this.onOpen,
    required this.onForget,
  });

  final RuntimeConnectionSettings settings;
  final LibraryProjectSnapshot value;
  final AsyncValue<LibraryOfflineSnapshot> offline;
  final bool isCurrentTarget;
  final ReaderAudioDownloadState audioDownloadState;
  final Future<void> Function() onDownloadAudio;
  final Future<void> Function() onRemoveAudio;
  final VoidCallback onSetTarget;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final offlineValue = offline.asData?.value;
    final isActionProject =
        audioDownloadState.projectId == settings.normalizedProjectId;
    final isDownloadingHere =
        isActionProject &&
        audioDownloadState.status == ReaderAudioDownloadStatus.downloading;
    final isRemovingHere =
        isActionProject &&
        audioDownloadState.status == ReaderAudioDownloadStatus.removing;
    final isBusyElsewhere = audioDownloadState.isBusy && !isActionProject;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: settings.hasAuthToken
                      ? palette.accentPrimary.withValues(alpha: 0.12)
                      : palette.accentSoft.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  settings.hasAuthToken
                      ? Icons.lock_outline_rounded
                      : Icons.cloud_outlined,
                  color: settings.hasAuthToken
                      ? palette.accentPrimary
                      : palette.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value.title),
                    const SizedBox(height: 4),
                    Text(
                      settings.shortHost,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value.statusHeadline,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value.statusNarrative,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isCurrentTarget)
                const _LibraryStatusChip(label: 'Current book'),
              _LibraryStatusChip(label: value.projectStatusLabel),
              if (value.latestJobLabel case final jobLabel?)
                _LibraryStatusChip(label: jobLabel),
              if (value.latestJobAttempt != null)
                _LibraryStatusChip(label: 'Attempt ${value.latestJobAttempt}'),
              _LibraryStatusChip(label: _formatBytes(value.totalSizeBytes)),
              ...offline.maybeWhen(
                data: (offlineValue) =>
                    _offlineStatusChips(offlineValue, value.audioAssetCount),
                orElse: () => const <Widget>[],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProjectSnapshotSummaryRow(value: value, offline: offline),
          if (isDownloadingHere) ...[
            const SizedBox(height: 12),
            _LibraryProgressMeter(
              label: audioDownloadState.activeAssetId == null
                  ? 'Downloading audio'
                  : 'Downloading ${audioDownloadState.activeAssetId}',
              percent: (audioDownloadState.progress * 100).round(),
            ),
          ],
          if (isRemovingHere && audioDownloadState.message != null) ...[
            const SizedBox(height: 12),
            Text(
              audioDownloadState.message!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
          if (value.latestJobPercent != null) ...[
            const SizedBox(height: 12),
            _LibraryProgressMeter(
              label: value.latestJobStage == null
                  ? 'Latest job'
                  : _capitalizeLabel(
                      value.latestJobStage!.replaceAll('_', ' '),
                    ),
              percent: value.latestJobPercent!,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => _showProjectDetailsSheet(
                  context,
                  value,
                  isCurrentTarget: isCurrentTarget,
                  onSetTarget: onSetTarget,
                  onOpenReader: onOpen,
                ),
                child: const Text('Book Details'),
              ),
              if (!isCurrentTarget)
                TextButton(
                  onPressed: onSetTarget,
                  child: const Text('Make Current'),
                ),
              if (value.audioAssetCount > 0)
                TextButton(
                  onPressed:
                      isBusyElsewhere || isRemovingHere || isDownloadingHere
                      ? null
                      : offlineValue != null &&
                            offlineValue.cachedAudioAssets >=
                                value.audioAssetCount
                      ? onRemoveAudio
                      : onDownloadAudio,
                  child: Text(
                    offlineValue != null &&
                            offlineValue.cachedAudioAssets >=
                                value.audioAssetCount
                        ? 'Remove From Device'
                        : offlineValue != null &&
                              offlineValue.cachedAudioAssets > 0
                        ? 'Save Remaining'
                        : 'Save to Device',
                  ),
                ),
              TextButton(onPressed: onForget, child: const Text('Remove')),
              FilledButton.tonal(
                onPressed: onOpen,
                child: const Text('Open Book'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectSnapshotSummaryRow extends StatelessWidget {
  const _ProjectSnapshotSummaryRow({
    required this.value,
    required this.offline,
  });

  final LibraryProjectSnapshot value;
  final AsyncValue<LibraryOfflineSnapshot> offline;

  @override
  Widget build(BuildContext context) {
    final offlineValue = offline.asData?.value;
    final cards = <Widget>[
      _ProjectMicroStat(
        label: 'Book size',
        value: _formatBytes(value.totalSizeBytes),
        hint: '${value.assetCount} files saved for this book',
      ),
      _ProjectMicroStat(
        label: 'On this device',
        value: offlineValue == null
            ? 'Checking...'
            : offlineValue.cachedAudioBytes > 0
            ? _formatBytes(offlineValue.cachedAudioBytes)
            : offlineValue.hasTextCache
            ? 'Text only'
            : 'Not cached',
        hint: offlineValue == null
            ? 'Inspecting local device state'
            : offlineValue.offlineNarrative(value.audioAssetCount),
      ),
      _ProjectMicroStat(
        label: 'Last update',
        value: value.updatedAt == null
            ? 'Unknown'
            : _formatTimestamp(value.updatedAt!),
        hint: value.latestJobStatus == null
            ? 'No recorded alignment attempt'
            : value.statusHeadline,
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards
          .map((card) => SizedBox(width: 180, child: card))
          .toList(growable: false),
    );
  }
}

class _ProjectMicroStat extends StatelessWidget {
  const _ProjectMicroStat({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _LibraryStatusChip extends StatelessWidget {
  const _LibraryStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _LibraryProgressMeter extends StatelessWidget {
  const _LibraryProgressMeter({required this.label, required this.percent});

  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final normalizedPercent = percent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
            Text(
              '$normalizedPercent%',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: normalizedPercent / 100,
            minHeight: 8,
            backgroundColor: palette.accentSoft.withValues(alpha: 0.45),
            valueColor: AlwaysStoppedAnimation<Color>(palette.accentPrimary),
          ),
        ),
      ],
    );
  }
}

Future<void> _showProjectDetailsSheet(
  BuildContext context,
  LibraryProjectSnapshot snapshot, {
  required bool isCurrentTarget,
  required VoidCallback onSetTarget,
  required VoidCallback onOpenReader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _ProjectDetailsSheet(
      snapshot: snapshot,
      isCurrentTarget: isCurrentTarget,
      onSetTarget: onSetTarget,
      onOpenReader: onOpenReader,
    ),
  );
}

class _ProjectDetailsSheet extends StatelessWidget {
  const _ProjectDetailsSheet({
    required this.snapshot,
    required this.isCurrentTarget,
    required this.onSetTarget,
    required this.onOpenReader,
  });

  final LibraryProjectSnapshot snapshot;
  final bool isCurrentTarget;
  final VoidCallback onSetTarget;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final palette = ReaderPalette.of(context);
        final offline = ref.watch(
          libraryOfflineSnapshotProvider(snapshot.settings),
        );
        final jobs = ref.watch(libraryProjectJobsProvider(snapshot.settings));
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.84,
          maxChildSize: 0.96,
          minChildSize: 0.56,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snapshot.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  snapshot.settings.shortHost,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                _ProjectDetailHero(snapshot: snapshot),
                const SizedBox(height: 14),
                _ProjectDetailSection(
                  title: 'Next Move',
                  child: _ProjectActionPlan(
                    snapshot: snapshot,
                    offline: offline.asData?.value,
                    isCurrentTarget: isCurrentTarget,
                  ),
                ),
                const SizedBox(height: 14),
                _ProjectDetailSection(
                  title: 'Overview',
                  child: _ProjectMetadataGrid(
                    snapshot: snapshot,
                    offline: offline,
                  ),
                ),
                const SizedBox(height: 14),
                _ProjectDetailSection(
                  title: 'Sync State',
                  child: _ProjectStatusStory(snapshot: snapshot),
                ),
                if (offline case AsyncData<LibraryOfflineSnapshot>(
                  value: final value,
                )) ...[
                  const SizedBox(height: 14),
                  _ProjectDetailSection(
                    title: 'Offline Readiness',
                    child: _ProjectOfflineStory(
                      snapshot: snapshot,
                      offline: value,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _ProjectDetailSection(
                  title: 'Recent Attempts',
                  child: jobs.when(
                    data: (value) {
                      if (value.jobs.isEmpty) {
                        return const Text('No sync attempts yet.');
                      }
                      return Column(
                        children: [
                          for (final job in value.jobs.take(6))
                            _JobHistoryTile(job: job),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => Text(
                      'Could not load sync history. ${formatSyncApiError(error)}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        onOpenReader();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.chrome_reader_mode_rounded),
                      label: const Text('Open In Reader'),
                    ),
                    if (!isCurrentTarget)
                      OutlinedButton.icon(
                        onPressed: () {
                          onSetTarget();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.radio_button_checked_rounded),
                        label: const Text('Set As Current Target'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProjectDetailHero extends StatelessWidget {
  const _ProjectDetailHero({required this.snapshot});

  final LibraryProjectSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.backgroundElevated, palette.backgroundBase],
        ),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LibraryStatusChip(label: snapshot.projectStatusLabel),
              if (snapshot.latestJobLabel case final jobLabel?)
                _LibraryStatusChip(label: jobLabel),
              _LibraryStatusChip(label: '${snapshot.assetCount} assets'),
              if (snapshot.latestJobAttempt != null)
                _LibraryStatusChip(
                  label: 'Attempt ${snapshot.latestJobAttempt}',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            snapshot.statusHeadline,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.statusNarrative,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          if (snapshot.latestJobPercent != null) ...[
            const SizedBox(height: 14),
            _LibraryProgressMeter(
              label: snapshot.latestJobStage == null
                  ? 'Current sync pass'
                  : _capitalizeLabel(
                      snapshot.latestJobStage!.replaceAll('_', ' '),
                    ),
              percent: snapshot.latestJobPercent!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProjectActionPlan extends StatelessWidget {
  const _ProjectActionPlan({
    required this.snapshot,
    required this.offline,
    required this.isCurrentTarget,
  });

  final LibraryProjectSnapshot snapshot;
  final LibraryOfflineSnapshot? offline;
  final bool isCurrentTarget;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _ProjectMetaCard(
        label: 'Current Route',
        value: isCurrentTarget ? 'Active target' : 'Saved target',
        hint: isCurrentTarget
            ? 'This project is already wired into the reader shell.'
            : 'Set it as the current target if you want the library and reader to pivot here.',
      ),
      _ProjectMetaCard(
        label: 'Recommended Next Step',
        value: snapshot.recommendedActionTitle(
          offline: offline,
          isCurrentTarget: isCurrentTarget,
        ),
        hint: snapshot.recommendedActionHint(
          offline: offline,
          isCurrentTarget: isCurrentTarget,
        ),
      ),
      _ProjectMetaCard(
        label: 'Offline Route',
        value:
            offline?.offlineActionLabel(snapshot.audioAssetCount) ?? 'Checking',
        hint: offline == null
            ? 'Inspecting local cache state for this device.'
            : offline!.offlineNarrative(snapshot.audioAssetCount),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((card) => SizedBox(width: 240, child: card))
          .toList(growable: false),
    );
  }
}

class _ProjectDetailSection extends StatelessWidget {
  const _ProjectDetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProjectMetadataGrid extends StatelessWidget {
  const _ProjectMetadataGrid({required this.snapshot, required this.offline});

  final LibraryProjectSnapshot snapshot;
  final AsyncValue<LibraryOfflineSnapshot> offline;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _ProjectMetaCard(
        label: 'Language',
        value: (snapshot.language ?? 'Unknown').toUpperCase(),
        hint: 'Book language',
      ),
      _ProjectMetaCard(
        label: 'Assets',
        value:
            '${snapshot.epubAssetCount} EPUB / ${snapshot.audioAssetCount} audio',
        hint: _formatBytes(snapshot.totalSizeBytes),
      ),
      _ProjectMetaCard(
        label: 'Book State',
        value: snapshot.projectStatusLabel.replaceFirst('Book ', ''),
        hint: snapshot.updatedAt == null
            ? 'No recent update time'
            : 'Updated ${_formatTimestamp(snapshot.updatedAt!)}',
      ),
    ];

    offline.whenData((value) {
      cards.add(
        _ProjectMetaCard(
          label: 'Offline Footprint',
          value: value.cachedAudioBytes > 0
              ? _formatBytes(value.cachedAudioBytes)
              : 'Not downloaded',
          hint: value.hasTextCache
              ? 'Text and sync cached locally'
              : 'Text and sync still live',
        ),
      );
    });

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((card) => SizedBox(width: 240, child: card))
          .toList(growable: false),
    );
  }
}

class _ProjectMetaCard extends StatelessWidget {
  const _ProjectMetaCard({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ProjectStatusStory extends StatelessWidget {
  const _ProjectStatusStory({required this.snapshot});

  final LibraryProjectSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.statusNarrative,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
        if (snapshot.latestJobTerminalReason case final terminalReason?) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: palette.accentSoft.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Text(
              'Latest issue: $terminalReason',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectOfflineStory extends StatelessWidget {
  const _ProjectOfflineStory({required this.snapshot, required this.offline});

  final LibraryProjectSnapshot snapshot;
  final LibraryOfflineSnapshot offline;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final lines = <String>[
      offline.hasTextCache
          ? 'Reader model and sync are saved on this device.'
          : 'Reader model and sync will still come from the backend.',
      if (snapshot.audioAssetCount > 0)
        offline.cachedAudioAssets >= snapshot.audioAssetCount
            ? 'All audiobook files are available offline.'
            : offline.cachedAudioAssets > 0
            ? '${offline.cachedAudioAssets} of ${snapshot.audioAssetCount} audio files are cached.'
            : 'Audio is still streaming only.',
      if (offline.audioCachedAt != null)
        'Last audio cache update: ${_formatTimestamp(offline.audioCachedAt!)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _offlineStatusChips(offline, snapshot.audioAssetCount),
        ),
        const SizedBox(height: 12),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }
}

class _JobHistoryTile extends StatelessWidget {
  const _JobHistoryTile({required this.job});

  final AlignmentJobResult job;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final status = _capitalizeLabel(job.status.replaceAll('_', ' '));
    final stage = job.stage == null
        ? null
        : _capitalizeLabel(job.stage!.replaceAll('_', ' '));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LibraryStatusChip(label: status),
              _LibraryStatusChip(label: 'Attempt ${job.attemptNumber}'),
              if (stage != null) _LibraryStatusChip(label: stage),
              if (job.percent != null)
                _LibraryStatusChip(label: '${job.percent}%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            job.jobId,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          if (job.terminalReason case final reason?) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
          if (job.percent != null) ...[
            const SizedBox(height: 10),
            _LibraryProgressMeter(
              label: stage ?? 'Attempt progress',
              percent: job.percent!,
            ),
          ],
        ],
      ),
    );
  }
}

String _formatMs(int value) {
  final duration = Duration(milliseconds: value);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _formatBytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }
  return '$value B';
}

List<Widget> _offlineStatusChips(
  LibraryOfflineSnapshot snapshot,
  int expectedAudioAssets,
) {
  final chips = <Widget>[
    _LibraryStatusChip(
      label: snapshot.hasTextCache ? 'Text cached' : 'Text live',
    ),
  ];
  if (expectedAudioAssets > 0) {
    if (snapshot.cachedAudioAssets >= expectedAudioAssets) {
      chips.add(const _LibraryStatusChip(label: 'Audio offline'));
    } else if (snapshot.cachedAudioAssets > 0) {
      chips.add(
        _LibraryStatusChip(
          label:
              'Audio ${snapshot.cachedAudioAssets}/$expectedAudioAssets cached',
        ),
      );
    } else {
      chips.add(const _LibraryStatusChip(label: 'Audio streaming'));
    }
  }
  if (snapshot.cachedAudioBytes > 0) {
    chips.add(
      _LibraryStatusChip(label: _formatBytes(snapshot.cachedAudioBytes)),
    );
  }
  return chips;
}

Map<String, dynamic>? _asMapOrNull(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<Map<String, dynamic>> _asObjectList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

extension on LibraryProjectSnapshot {
  String get statusHeadline {
    if (lifecyclePhase == 'draft') {
      if (lifecycleMissingRequirements.contains('epub') &&
          lifecycleMissingRequirements.contains('audio')) {
        return 'This book still needs the EPUB and the audiobook.';
      }
      if (lifecycleMissingRequirements.contains('epub')) {
        return 'This book still needs the EPUB file.';
      }
      if (lifecycleMissingRequirements.contains('audio')) {
        return 'This book still needs the audiobook files.';
      }
    }
    if (lifecyclePhase == 'ready_to_align') {
      return 'Everything is attached. This book is ready to sync.';
    }
    if (lifecyclePhase == 'ready_to_read') {
      return 'This book is ready for playback-driven reading.';
    }
    if (lifecyclePhase == 'attention_needed') {
      return 'This book needs attention before it is ready again.';
    }
    switch (latestJobStatus) {
      case 'running':
        return 'This book is being prepared for synced reading.';
      case 'queued':
        return 'This book is lined up and waiting for its sync pass.';
      case 'failed':
        return 'The latest sync pass stopped before the book was ready.';
      case 'completed':
        return 'This book is ready for playback-driven reading.';
    }
    if (projectStatus == 'ready') {
      return 'This book is ready to read.';
    }
    return 'This book exists, but it is not fully synced yet.';
  }

  String get statusNarrative {
    if (lifecyclePhase == 'draft') {
      if (lifecycleMissingRequirements.contains('epub') &&
          lifecycleMissingRequirements.contains('audio')) {
        return 'Start by attaching the book file and the audiobook. Once both are present, sync can begin.';
      }
      if (lifecycleMissingRequirements.contains('epub')) {
        return 'The audiobook is attached, but the book file is still missing.';
      }
      if (lifecycleMissingRequirements.contains('audio')) {
        return 'The book file is attached, but the audiobook still needs to be added.';
      }
    }
    if (lifecyclePhase == 'ready_to_align') {
      return 'The book file and audiobook are attached. Start the sync pass when you are ready.';
    }
    if (lifecyclePhase == 'ready_to_read') {
      return 'The latest completed reading bundle is ready. Open the book now, or save audio to this device for offline reading.';
    }
    if (latestJobStatus == 'running') {
      final stage = latestJobStage == null
          ? 'the current stage'
          : _capitalizeLabel(latestJobStage!.replaceAll('_', ' '));
      final percent = latestJobPercent == null ? '' : ' at $latestJobPercent%';
      return 'The latest sync pass is moving through $stage$percent. Stay here to watch progress or open the book to inspect the live state.';
    }
    if (latestJobStatus == 'queued') {
      return 'The files are attached and the sync pass is queued. Nothing is wrong yet; the book is simply waiting its turn.';
    }
    if (latestJobStatus == 'failed') {
      return latestJobTerminalReason == null
          ? 'The last sync pass failed. Open the book details and recent attempts to inspect where it stopped.'
          : 'The last sync pass failed because "$latestJobTerminalReason". Retry or inspect recent attempts before reopening the book.';
    }
    if (latestJobStatus == 'completed') {
      return 'The latest sync pass finished successfully. Reader content, timings, and cached assets can now reopen with minimal friction.';
    }
    if (projectStatus == 'ready') {
      return 'This book is structurally ready, but there is no recent sync pass to summarize yet.';
    }
    return 'This book exists on the server, but it still needs a successful sync pass before it becomes a polished reading target.';
  }

  String get projectStatusLabel {
    if (lifecyclePhase != null && lifecyclePhase!.isNotEmpty) {
      return 'Book ${_lifecyclePhaseLabel(lifecyclePhase!)}';
    }
    final normalized = projectStatus.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) {
      return 'Book status unknown';
    }
    return 'Book ${_capitalizeLabel(normalized)}';
  }

  String? get latestJobLabel {
    final status = latestJobStatus;
    if (status == null || status.isEmpty) {
      return null;
    }
    final normalizedStatus = _capitalizeLabel(status.replaceAll('_', ' '));
    final stage = latestJobStage;
    final percent = latestJobPercent;
    if (stage != null && stage.isNotEmpty && percent != null) {
      return '$normalizedStatus • ${_capitalizeLabel(stage.replaceAll('_', ' '))} $percent%';
    }
    if (percent != null) {
      return '$normalizedStatus • $percent%';
    }
    return normalizedStatus;
  }

  String recommendedActionTitle({
    required LibraryOfflineSnapshot? offline,
    required bool isCurrentTarget,
  }) {
    if (!isCurrentTarget) {
      return 'Make current';
    }
    switch (lifecycleNextAction) {
      case 'attach_epub':
        return 'Add EPUB';
      case 'attach_audio':
        return 'Add audiobook';
      case 'start_alignment':
        return 'Start sync';
      case 'monitor_alignment':
        return 'Watch progress';
      case 'open_reader':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'Save audio';
        }
        return 'Open book';
      case 'retry_alignment':
        return 'Inspect issue';
    }
    switch (latestJobStatus) {
      case 'running':
        return 'Watch progress';
      case 'queued':
        return 'Wait here';
      case 'failed':
        return 'Inspect issue';
      case 'completed':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'Save audio';
        }
        return 'Open book';
    }
    if (projectStatus == 'ready') {
      return 'Open book';
    }
    return 'Review details';
  }

  String recommendedActionHint({
    required LibraryOfflineSnapshot? offline,
    required bool isCurrentTarget,
  }) {
    if (!isCurrentTarget) {
      return 'Make this your current book first, then reopen it or manage device downloads from the library.';
    }
    switch (lifecycleNextAction) {
      case 'attach_epub':
        return 'Attach the EPUB first so the app has the text it needs before syncing.';
      case 'attach_audio':
        return 'Attach the audiobook next so the app can build synced reading playback.';
      case 'start_alignment':
        return 'Everything is attached. Start sync when you want the app to build timings and reading data.';
      case 'monitor_alignment':
        return 'The sync pass is already in motion. Stay here for progress or open the book to inspect the live state.';
      case 'open_reader':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'The book is ready. Save the audiobook to this device next if you want resilient offline reading.';
        }
        return 'The synced reading bundle is ready now. Open the book and continue where you left off.';
      case 'retry_alignment':
        return latestJobTerminalReason == null
            ? 'The last sync pass needs a closer look before trying again.'
            : 'The last sync pass needs attention because "$latestJobTerminalReason". Review the recent attempts first.';
    }
    switch (latestJobStatus) {
      case 'running':
        return 'Stay in the library if you want progress visibility, or open the book to inspect the live state while timings build.';
      case 'queued':
        return 'No action yet. The sync pass is waiting to start, so keep the book parked here.';
      case 'failed':
        return latestJobTerminalReason == null
            ? 'Read the recent attempt history before trying again.'
            : 'The latest sync pass stopped with "$latestJobTerminalReason". Check attempts before reopening the book.';
      case 'completed':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'The sync is ready. Save the audiobook to this device next if you want resilient offline reading.';
        }
        return 'Everything needed for a polished reading session is available. Jump straight into the book.';
    }
    if (projectStatus == 'ready') {
      return 'The structure exists, but there is no recent attempt summary to display. Open the book or inspect its details.';
    }
    return 'This book still needs a successful sync pass before it becomes a clean reading target.';
  }
}

extension on LibraryOfflineSnapshot {
  String offlineNarrative(int expectedAudioAssets) {
    if (!hasTextCache && cachedAudioAssets == 0) {
      return 'No device cache yet';
    }
    if (expectedAudioAssets <= 0) {
      return hasTextCache ? 'Reader data saved locally' : 'No audio in project';
    }
    if (cachedAudioAssets >= expectedAudioAssets) {
      return 'Full text and audio offline';
    }
    if (cachedAudioAssets > 0) {
      return '$cachedAudioAssets of $expectedAudioAssets audio files saved';
    }
    return hasTextCache
        ? 'Text saved, audio still streaming'
        : 'Audio still streaming';
  }

  String offlineActionLabel(int expectedAudioAssets) {
    if (!hasTextCache && cachedAudioAssets == 0) {
      return 'Live only';
    }
    if (expectedAudioAssets <= 0) {
      return hasTextCache ? 'Text offline' : 'No audio';
    }
    if (cachedAudioAssets >= expectedAudioAssets) {
      return 'Full offline';
    }
    if (cachedAudioAssets > 0) {
      return 'Mixed offline';
    }
    return hasTextCache ? 'Text offline' : 'Streaming audio';
  }
}

extension on LibraryImportState {
  String? get statusLabel {
    switch (status) {
      case LibraryImportStatus.picking:
        return 'Choosing files';
      case LibraryImportStatus.creatingProject:
        return 'Creating book';
      case LibraryImportStatus.uploadingEpub:
        return 'Uploading EPUB';
      case LibraryImportStatus.uploadingAudio:
        return 'Uploading audio';
      case LibraryImportStatus.startingJob:
        return 'Starting sync';
      case LibraryImportStatus.completed:
        return 'Sync started';
      case LibraryImportStatus.failed:
        return 'Needs attention';
      case LibraryImportStatus.ready:
        return 'Book draft ready';
      case LibraryImportStatus.idle:
        return null;
    }
  }

  String? get statusNarrative {
    switch (status) {
      case LibraryImportStatus.idle:
        return null;
      case LibraryImportStatus.ready:
        return canStartImport
            ? 'Everything required for the first sync pass is attached.'
            : 'The draft has started, but at least one required input is still missing.';
      case LibraryImportStatus.picking:
        return 'Selecting source files on this device.';
      case LibraryImportStatus.creatingProject:
        return 'Creating the book space before uploads begin.';
      case LibraryImportStatus.uploadingEpub:
        return 'The book file is on its way to the server.';
      case LibraryImportStatus.uploadingAudio:
        return 'Audio files are uploading in sequence so reading order stays explicit.';
      case LibraryImportStatus.startingJob:
        return 'Files are attached. The app is now asking the server to start sync.';
      case LibraryImportStatus.completed:
        return 'Your book is uploaded and syncing now. Watch progress here, then open it when synced reading is ready.';
      case LibraryImportStatus.failed:
        return 'The draft is preserved, so you can correct the problem and launch again.';
    }
  }
}

String _capitalizeLabel(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
