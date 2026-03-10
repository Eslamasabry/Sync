import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
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
              title: 'Import Book',
              description:
                  'Start with the book and audio files, then let Sync create the project and queue alignment from this device.',
              icon: Icons.upload_file_rounded,
              child: _ImportComposer(state: importState),
            );
            final currentTargetSection = _LibrarySection(
              title: 'Current Reader Target',
              description:
                  'Keep the active backend target, offline cache state, and the quickest return path into reading in one place.',
              icon: Icons.radio_button_checked_rounded,
              footer: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        ref.read(homeTabProvider.notifier).showReader(),
                    icon: const Icon(Icons.book_online_rounded),
                    label: const Text('Continue Reader'),
                  ),
                  currentSettings.maybeWhen(
                    data: (settings) => OutlinedButton.icon(
                      onPressed: () => _forgetConnection(context, ref, settings),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Forget Target'),
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
                error: (error, _) =>
                    Text('Could not load the current target. $error'),
              ),
            );
            final queueSection = _LibrarySection(
              title: 'Processing Queue',
              description:
                  'Watch projects that are still ingesting, transcribing, or aligning without leaving the library.',
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
                error: (error, _) =>
                    Text('Could not inspect recent projects. $error'),
              ),
            );
            final recentBooksSection = _LibrarySection(
              title: 'Recent Books',
              description:
                  'Device-side reading history so you can resume from the last meaningful spot, not just the last project.',
              icon: Icons.history_edu_rounded,
              child: recentLocations.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'No local reading history yet. Open a book in Reader to start building a device-side library trail.',
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
                error: (error, _) =>
                    Text('Could not read library history. $error'),
              ),
            );
            final recentProjectsSection = _LibrarySection(
              title: 'Recent Server Projects',
              description:
                  'Saved backend targets with alignment state, cached status, and a direct path back into each project.',
              icon: Icons.dns_rounded,
              child: recentConnections.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'Save a backend target from the Reader connection sheet to reuse it here.',
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
                error: (error, _) =>
                    Text('Could not read recent connections. $error'),
              ),
            );

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
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 11,
                              child: Column(
                                children: [
                                  importSection,
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
                        )
                      else ...[
                        importSection,
                        const SizedBox(height: 16),
                        currentTargetSection,
                        const SizedBox(height: 16),
                        queueSection,
                        const SizedBox(height: 16),
                        recentBooksSection,
                        const SizedBox(height: 16),
                        recentProjectsSection,
                      ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(feedback)));
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
      feedback:
          'Opened ${settings.normalizedProjectId} on ${settings.shortHost}.',
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
          'Set ${settings.normalizedProjectId} on ${settings.shortHost} as the current target.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Forgot ${settings.normalizedProjectId} on ${settings.shortHost}.',
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
    if (!context.mounted) {
      return;
    }
    final settings = RuntimeConnectionSettings(
      apiBaseUrl: current.apiBaseUrl,
      projectId: snapshot.projectId,
      authToken: current.authToken,
    );
    await _openConnection(context, ref, settings);
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
                  'Import, align, and reopen books from one calm workspace.',
                  style: theme.textTheme.headlineLarge?.copyWith(height: 0.98),
                ),
                const SizedBox(height: 10),
                Text(
                  'Attach EPUB and audio, monitor jobs, and keep your reader target and offline cache close without turning the app into a generic file manager.',
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
                        label: 'Saved targets',
                        value: '$recentConnectionCount',
                        icon: Icons.cloud_queue_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LibraryMetric(
                        label: 'Resume points',
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
                              ? 'Draft in progress'
                              : 'Workspace ready',
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
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
  const _ImportComposer({required this.state});

  final LibraryImportState state;

  @override
  ConsumerState<_ImportComposer> createState() => _ImportComposerState();
}

class _ImportComposerState extends ConsumerState<_ImportComposer> {
  late final TextEditingController _titleController;
  late final TextEditingController _languageController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.state.title);
    _languageController = TextEditingController(text: widget.state.language);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 860;
            final metadata = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Book Title'),
                  onChanged: actions.setTitle,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _languageController,
                  decoration: const InputDecoration(labelText: 'Language'),
                  onChanged: actions.setLanguage,
                ),
                const SizedBox(height: 16),
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
                            ? 'Choose Audio'
                            : 'Replace Audio',
                      ),
                    ),
                  ],
                ),
                if (!hasDraft) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Attach the book first, then the audiobook files. Multi-file audio is fine.',
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
                children: [
                  metadata,
                  const SizedBox(height: 16),
                  workflow,
                ],
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
        Text('Launch', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.state.isBusy ? null : actions.startImport,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(
                widget.state.isBusy
                    ? 'Working...'
                    : widget.state.canStartImport
                    ? 'Create and Align'
                    : 'Complete Draft',
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
            label: 'Draft',
            description: 'Attach EPUB and audio',
            complete: state.epubFile != null && state.audioFiles.isNotEmpty,
            active:
                state.status == LibraryImportStatus.idle ||
                state.status == LibraryImportStatus.picking ||
                state.status == LibraryImportStatus.ready ||
                state.status == LibraryImportStatus.failed,
          ),
          (
            label: 'Project',
            description: 'Create the project shell',
            complete:
                state.projectId != null &&
                state.status.index > LibraryImportStatus.creatingProject.index,
            active: state.status == LibraryImportStatus.creatingProject,
          ),
          (
            label: 'Upload',
            description: 'Send EPUB and audio assets',
            complete:
                state.status.index > LibraryImportStatus.uploadingAudio.index,
            active:
                state.status == LibraryImportStatus.uploadingEpub ||
                state.status == LibraryImportStatus.uploadingAudio,
          ),
          (
            label: 'Align',
            description: 'Start the sync job',
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
    final importedSnapshot = importedSettings == null
        ? null
        : ref.watch(libraryProjectSnapshotProvider(importedSettings));
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
                  'Alignment queued',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Project ${state.projectId} is ready and job ${state.jobId} has been handed off. Stay here to monitor progress or jump into the reader workspace when you want to inspect it there.',
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
                'Live status unavailable right now. $error',
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
              _LibraryStatusChip(label: 'Project ${state.projectId}'),
              _LibraryStatusChip(label: 'Job ${state.jobId}'),
              if (state.completedAt != null)
                _LibraryStatusChip(label: _formatTimestamp(state.completedAt!)),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onOpenReader,
            icon: const Icon(Icons.chrome_reader_mode_rounded),
            label: const Text('Open Reader'),
          ),
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

class _LibraryBookTile extends StatelessWidget {
  const _LibraryBookTile({required this.snapshot, required this.onResume});

  final ReaderLocationSnapshot snapshot;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _LibraryStatusChip(label: snapshot.projectId),
                    _LibraryStatusChip(
                      label: '${(snapshot.progressFraction * 100).round()}%',
                    ),
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
                child: const Text('Resume'),
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
    final snapshot = ref.watch(libraryProjectSnapshotProvider(settings));
    final offline = ref.watch(libraryOfflineSnapshotProvider(settings));
    return snapshot.when(
      data: (value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${settings.shortHost} • ${settings.normalizedProjectId}'),
          const SizedBox(height: 8),
          Text(
            value.statusNarrative,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ReaderPalette.of(context).textMuted,
            ),
          ),
          if (value.latestJobPercent != null) ...[
            const SizedBox(height: 12),
            _LibraryProgressMeter(
              label: value.latestJobStage == null
                  ? 'Latest job progress'
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
          Text('${settings.shortHost} • ${settings.normalizedProjectId}'),
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${settings.shortHost} • ${settings.normalizedProjectId}'),
          const SizedBox(height: 8),
          Text(
            'Could not fetch project snapshot. $error',
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
    final offline = ref.watch(libraryOfflineSnapshotProvider(settings));

    String message;
    List<Widget> actions = const <Widget>[];

    final bundle = project.asData?.value;
    if (project.isLoading) {
      message =
          'Reader workspace is still connecting for this target. Offline details will sharpen once the project bundle loads.';
    } else if (project.hasError) {
      message =
          'Offline controls are available, but the live reader bundle is not reachable right now. Reopen the reader or refresh once the backend responds.';
    } else if (bundle == null || bundle.totalAudioAssets == 0) {
      message =
          'This target has no playable audiobook assets yet. Text and sync caches can still exist, but there is no audio package to download.';
    } else if (downloadState.status == ReaderAudioDownloadStatus.downloading) {
      message =
          'Downloading audio ${downloadState.completedAssets + 1} of ${downloadState.totalAssets > 0 ? downloadState.totalAssets : bundle.totalAudioAssets} for offline playback.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Downloading'),
        ),
      ];
    } else if (bundle.hasCompleteOfflineAudio) {
      message =
          'All audiobook files for the current target are stored locally. You can remove them here without leaving the library.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: downloadState.isBusy ? null : onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Remove Offline Audio'),
        ),
      ];
    } else {
      message =
          'Audio is still streaming for this target. Download it here to make the current project fully portable on this device.';
      actions = [
        FilledButton.tonalIcon(
          onPressed: downloadState.isBusy ? null : onDownload,
          icon: const Icon(Icons.download_for_offline_rounded),
          label: Text(
            bundle.cachedAudioAssets > 0
                ? 'Download Remaining'
                : 'Download Audio',
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
            'Offline Manager',
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
        'No recent projects yet. Import a book to start an alignment queue.',
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
                          const _LibraryStatusChip(label: 'Current target'),
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
                      child: const Text('Set Target'),
                    ),
                  FilledButton.tonal(
                    onPressed: onOpen,
                    child: const Text('Reader'),
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
        title: Text(settings.normalizedProjectId),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      ),
      error: (error, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_off_rounded),
        title: Text(settings.normalizedProjectId),
        subtitle: Text(
          'Could not load project snapshot. $error',
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
                const _LibraryStatusChip(label: 'Current target'),
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
                child: const Text('Workspace'),
              ),
              if (!isCurrentTarget)
                TextButton(
                  onPressed: onSetTarget,
                  child: const Text('Set Target'),
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
                        ? 'Remove Audio'
                        : offlineValue != null &&
                              offlineValue.cachedAudioAssets > 0
                        ? 'Download Rest'
                        : 'Download Audio',
                  ),
                ),
              TextButton(onPressed: onForget, child: const Text('Forget')),
              FilledButton.tonal(
                onPressed: onOpen,
                child: const Text('Reader'),
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
        label: 'Server payload',
        value: _formatBytes(value.totalSizeBytes),
        hint: '${value.assetCount} assets on backend',
      ),
      _ProjectMicroStat(
        label: 'Offline footprint',
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
        label: 'Last movement',
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
                  '${snapshot.settings.shortHost} • ${snapshot.settings.normalizedProjectId}',
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
                        return const Text(
                          'No alignment attempts recorded yet.',
                        );
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
                    error: (error, _) =>
                        Text('Could not load job history. $error'),
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
                  ? 'Current alignment pass'
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
        hint: 'Reader and alignment language',
      ),
      _ProjectMetaCard(
        label: 'Assets',
        value:
            '${snapshot.epubAssetCount} EPUB / ${snapshot.audioAssetCount} audio',
        hint: _formatBytes(snapshot.totalSizeBytes),
      ),
      _ProjectMetaCard(
        label: 'Project State',
        value: snapshot.projectStatusLabel.replaceFirst('Project ', ''),
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

extension on LibraryProjectSnapshot {
  String get statusHeadline {
    switch (latestJobStatus) {
      case 'running':
        return 'Alignment is actively building the reading timeline.';
      case 'queued':
        return 'This project is waiting for the next alignment worker slot.';
      case 'failed':
        return 'The latest alignment attempt stopped before export.';
      case 'completed':
        return 'Sync is ready for playback-driven reading.';
    }
    if (projectStatus == 'ready') {
      return 'This book is ready to read.';
    }
    return 'Project state is available, but not fully synced yet.';
  }

  String get statusNarrative {
    if (latestJobStatus == 'running') {
      final stage = latestJobStage == null
          ? 'the current stage'
          : _capitalizeLabel(latestJobStage!.replaceAll('_', ' '));
      final percent = latestJobPercent == null ? '' : ' at $latestJobPercent%';
      return 'The latest attempt is moving through $stage$percent. You can stay in the library to monitor progress or open the reader and inspect the live project state.';
    }
    if (latestJobStatus == 'queued') {
      return 'Assets are attached and the job is queued. Nothing is wrong here yet; the project is simply waiting for execution.';
    }
    if (latestJobStatus == 'failed') {
      return latestJobTerminalReason == null
          ? 'The last attempt failed. Open the project workspace and recent attempts to inspect where it stopped.'
          : 'The last attempt failed because "$latestJobTerminalReason". Retry or inspect the recent attempt timeline before reopening the reader.';
    }
    if (latestJobStatus == 'completed') {
      return 'The latest attempt finished successfully. Reader content, sync data, and cached assets can now be reopened with minimal friction.';
    }
    if (projectStatus == 'ready') {
      return 'This project is structurally ready, but there is no recent alignment attempt to summarize yet.';
    }
    return 'This project exists on the backend, but it still needs a successful alignment pass before it becomes a polished reading target.';
  }

  String get projectStatusLabel {
    final normalized = projectStatus.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) {
      return 'Project unknown';
    }
    return 'Project ${_capitalizeLabel(normalized)}';
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
      return 'Set target';
    }
    switch (latestJobStatus) {
      case 'running':
        return 'Monitor alignment';
      case 'queued':
        return 'Hold in queue';
      case 'failed':
        return 'Inspect failure';
      case 'completed':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'Download audio';
        }
        return 'Open reader';
    }
    if (projectStatus == 'ready') {
      return 'Open reader';
    }
    return 'Review workspace';
  }

  String recommendedActionHint({
    required LibraryOfflineSnapshot? offline,
    required bool isCurrentTarget,
  }) {
    if (!isCurrentTarget) {
      return 'Make this the active project first, then reopen Reader or manage offline state from the library.';
    }
    switch (latestJobStatus) {
      case 'running':
        return 'Stay in the library if you want job visibility, or jump into Reader to inspect the live state while the timeline builds.';
      case 'queued':
        return 'No intervention yet. The job is waiting for execution, so keep the project parked here.';
      case 'failed':
        return latestJobTerminalReason == null
            ? 'Read the recent attempt history before trying again.'
            : 'The latest attempt stopped with "$latestJobTerminalReason". Check attempts before reopening the reader.';
      case 'completed':
        if (audioAssetCount > 0 &&
            (offline == null || offline.cachedAudioAssets < audioAssetCount)) {
          return 'The sync is ready. Pull the audiobook onto the device next if you want a resilient offline reading target.';
        }
        return 'Everything needed for a polished reading session is available. Jump straight into Reader.';
    }
    if (projectStatus == 'ready') {
      return 'The structure exists, but there is no recent attempt summary to display. Open the reader or inspect the workspace.';
    }
    return 'This project still needs a successful alignment pass before it becomes a clean reading target.';
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
        return 'Creating project';
      case LibraryImportStatus.uploadingEpub:
        return 'Uploading EPUB';
      case LibraryImportStatus.uploadingAudio:
        return 'Uploading audio';
      case LibraryImportStatus.startingJob:
        return 'Starting job';
      case LibraryImportStatus.completed:
        return 'Alignment queued';
      case LibraryImportStatus.failed:
        return 'Needs attention';
      case LibraryImportStatus.ready:
        return 'Draft ready';
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
            ? 'Everything required for the first alignment pass is attached.'
            : 'The draft has started, but at least one required input is still missing.';
      case LibraryImportStatus.picking:
        return 'Selecting source files on this device.';
      case LibraryImportStatus.creatingProject:
        return 'Creating the backend project shell before uploads begin.';
      case LibraryImportStatus.uploadingEpub:
        return 'The book file is on its way to the backend.';
      case LibraryImportStatus.uploadingAudio:
        return 'Audio files are uploading in sequence so the timeline order stays explicit.';
      case LibraryImportStatus.startingJob:
        return 'Assets are attached. The app is now asking the backend to start alignment.';
      case LibraryImportStatus.completed:
        return 'The backend accepted the job, and this project can now be monitored from the library or opened in Reader.';
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
