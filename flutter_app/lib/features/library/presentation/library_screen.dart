import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/state/library_import_controller.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
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

    final recentConnectionCount = recentConnections.asData?.value.length ?? 0;
    final recentBookCount = recentLocations.asData?.value.length ?? 0;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.backgroundBase,
                  palette.backgroundElevated,
                  palette.backgroundBase,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -70,
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.accentSoft.withValues(alpha: 0.50),
                    palette.accentSoft.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              _LibraryHero(
                recentConnectionCount: recentConnectionCount,
                recentBookCount: recentBookCount,
                hasDraft:
                    importState.epubFile != null ||
                    importState.audioFiles.isNotEmpty,
              ),
              const SizedBox(height: 18),
              _LibrarySection(
                title: 'Import Book',
                description:
                    'Create a project, attach EPUB plus audiobook files, and start alignment from this device without leaving the library.',
                icon: Icons.upload_file_rounded,
                child: _ImportComposer(state: importState),
              ),
              const SizedBox(height: 16),
              _LibrarySection(
                title: 'Current Reader Target',
                description:
                    'Your active project connection, local cache state, and the fastest path back into the reader.',
                icon: Icons.radio_button_checked_rounded,
                footer: FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.read(homeTabProvider.notifier).showReader(),
                  icon: const Icon(Icons.book_online_rounded),
                  label: const Text('Continue Reader'),
                ),
                child: currentSettings.when(
                  data: (settings) => _ProjectTargetSummary(
                    settings: settings,
                    onOpen: () => _activateConnection(context, ref, settings),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) =>
                      Text('Could not load the current target. $error'),
                ),
              ),
              const SizedBox(height: 16),
              _LibrarySection(
                title: 'Processing Queue',
                description:
                    'Watch recent projects that are still aligning without leaving the library.',
                icon: Icons.sync_rounded,
                child: recentConnections.when(
                  data: (items) => _ProcessingQueueList(
                    connections: items.take(6).toList(growable: false),
                    onOpen: (settings) =>
                        _activateConnection(context, ref, settings),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) =>
                      Text('Could not inspect recent projects. $error'),
                ),
              ),
              const SizedBox(height: 16),
              _LibrarySection(
                title: 'Recent Books',
                description:
                    'Device-side reading history so you can jump back into the last meaningful spot, not just the last project.',
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
                          _LibraryBookTile(snapshot: item),
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
              ),
              const SizedBox(height: 16),
              _LibrarySection(
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
                            onOpen: () =>
                                _activateConnection(context, ref, item),
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
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _activateConnection(
    BuildContext context,
    WidgetRef ref,
    RuntimeConnectionSettings settings,
  ) async {
    await ref.read(runtimeConnectionSettingsProvider.notifier).save(settings);
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    ref.read(homeTabProvider.notifier).showReader();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opened ${settings.normalizedProjectId} on ${settings.shortHost}.',
          ),
        ),
      );
    }
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: palette.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.backgroundElevated.withValues(alpha: 0.96),
            palette.backgroundBase.withValues(alpha: 0.98),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shellShadow.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 18),
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
                  'Keep import, cache, and reading state in one serious workspace.',
                  style: theme.textTheme.displaySmall?.copyWith(height: 1.0),
                ),
                const SizedBox(height: 10),
                Text(
                  'This is the operational side of Sync: attach books, watch jobs, reopen projects, and keep your local reading trail without turning the screen into a generic file manager.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
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
                        label: 'Recent projects',
                        value: '$recentConnectionCount',
                        icon: Icons.cloud_queue_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LibraryMetric(
                        label: 'Recent books',
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
                    color: palette.backgroundBase,
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
                              ? 'Import draft in progress'
                              : 'Import workspace ready',
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
      color: palette.backgroundElevated.withValues(alpha: 0.94),
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
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: palette.backgroundBase,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Draft status',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 10),
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
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
        Text('Source files', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: widget.state.isBusy ? null : actions.pickEpub,
              icon: const Icon(Icons.auto_stories_rounded),
              label: Text(
                widget.state.epubFile == null ? 'Choose EPUB' : 'Replace EPUB',
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: widget.state.isBusy ? null : actions.pickAudioFiles,
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
        if (widget.state.epubFile != null) ...[
          const SizedBox(height: 12),
          _ImportFileTile(
            icon: Icons.menu_book_rounded,
            label: 'EPUB',
            name: widget.state.epubFile!.name,
            detail: _formatBytes(widget.state.epubFile!.sizeBytes),
          ),
        ],
        if (widget.state.audioFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
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

class _ImportCompletionBanner extends StatelessWidget {
  const _ImportCompletionBanner({
    required this.state,
    required this.onOpenReader,
  });

  final LibraryImportState state;
  final VoidCallback onOpenReader;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
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
            'Project ${state.projectId} is ready and job ${state.jobId} is running. Stay in the library to watch queue state or jump into the reader workspace when you want to inspect progress there.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
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
  const _LibraryBookTile({required this.snapshot});

  final ReaderLocationSnapshot snapshot;

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
          Text(
            _formatMs(snapshot.positionMs),
            style: Theme.of(context).textTheme.labelLarge,
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

class _ProcessingQueueList extends StatelessWidget {
  const _ProcessingQueueList({required this.connections, required this.onOpen});

  final List<RuntimeConnectionSettings> connections;
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
            onOpen: () => onOpen(connection),
          ),
      ],
    );
  }
}

class _QueueSnapshotTile extends ConsumerWidget {
  const _QueueSnapshotTile({required this.settings, required this.onOpen});

  final RuntimeConnectionSettings settings;
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
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(onPressed: onOpen, child: const Text('Open')),
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
  const _ProjectSnapshotTile({required this.settings, required this.onOpen});

  final RuntimeConnectionSettings settings;
  final VoidCallback onOpen;

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
        onOpen: onOpen,
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
    required this.onOpen,
  });

  final RuntimeConnectionSettings settings;
  final LibraryProjectSnapshot value;
  final AsyncValue<LibraryOfflineSnapshot> offline;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);

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
          Row(
            children: [
              TextButton(
                onPressed: () => _showProjectDetailsSheet(context, value),
                child: const Text('Details'),
              ),
              const Spacer(),
              FilledButton.tonal(onPressed: onOpen, child: const Text('Open')),
            ],
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
  LibraryProjectSnapshot snapshot,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _ProjectDetailsSheet(snapshot: snapshot),
  );
}

class _ProjectDetailsSheet extends StatelessWidget {
  const _ProjectDetailsSheet({required this.snapshot});

  final LibraryProjectSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final offline = ref.watch(
          libraryOfflineSnapshotProvider(snapshot.settings),
        );
        final jobs = ref.watch(libraryProjectJobsProvider(snapshot.settings));
        final theme = Theme.of(context);
        final homeTab = ref.read(homeTabProvider.notifier);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(snapshot.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '${snapshot.settings.shortHost} • ${snapshot.settings.normalizedProjectId}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _LibraryStatusChip(label: snapshot.projectStatusLabel),
                  if (snapshot.latestJobLabel case final jobLabel?)
                    _LibraryStatusChip(label: jobLabel),
                  _LibraryStatusChip(label: '${snapshot.assetCount} assets'),
                  _LibraryStatusChip(
                    label: _formatBytes(snapshot.totalSizeBytes),
                  ),
                ],
              ),
              if (offline case AsyncData<LibraryOfflineSnapshot>(
                value: final value,
              )) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _offlineStatusChips(
                    value,
                    snapshot.audioAssetCount,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Language: ${snapshot.language ?? 'Unknown'}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Assets: ${snapshot.epubAssetCount} EPUB • ${snapshot.audioAssetCount} audio',
                style: theme.textTheme.bodyMedium,
              ),
              if (offline case AsyncData<LibraryOfflineSnapshot>(
                value: final value,
              )) ...[
                const SizedBox(height: 8),
                Text(
                  'Offline footprint: ${_formatBytes(value.cachedAudioBytes)} audio cached',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (snapshot.updatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Updated: ${snapshot.updatedAt!.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (snapshot.latestJobTerminalReason case final terminalReason?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Latest issue: $terminalReason',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
              Text('Recent attempts', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              jobs.when(
                data: (value) {
                  if (value.jobs.isEmpty) {
                    return const Text('No alignment attempts recorded yet.');
                  }
                  return Column(
                    children: [
                      for (final job in value.jobs.take(5))
                        _JobHistoryTile(job: job),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => Text('Could not load job history. $error'),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await ref
                      .read(runtimeConnectionSettingsProvider.notifier)
                      .save(snapshot.settings);
                  ref.invalidate(projectIdProvider);
                  ref.invalidate(syncApiClientProvider);
                  ref.invalidate(projectEventsClientProvider);
                  ref.invalidate(readerRepositoryProvider);
                  ref.invalidate(readerProjectProvider);
                  ref.invalidate(projectEventsProvider);
                  ref.invalidate(latestProjectEventProvider);
                  ref.read(readerPlaybackProvider.notifier).resetForProject();
                  homeTab.showReader();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.chrome_reader_mode_rounded),
                label: const Text('Open In Reader'),
              ),
            ],
          ),
        );
      },
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
}

String _capitalizeLabel(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
