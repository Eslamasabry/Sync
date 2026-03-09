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

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accentSoft.withValues(alpha: 0.7),
            palette.backgroundBase,
            palette.backgroundElevated,
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text('Library', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 10),
            Text(
              'Keep recent self-hosted projects, resumed positions, and device-local reading context in one place.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import Book',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a project, upload EPUB plus audiobook files, and start alignment from this device.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ImportComposer(state: importState),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Reader Target',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    currentSettings.when(
                      data: (settings) => _ProjectTargetSummary(
                        settings: settings,
                        onOpen: () =>
                            _activateConnection(context, ref, settings),
                      ),
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                      error: (error, _) =>
                          Text('Could not load the current target. $error'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          ref.read(homeTabProvider.notifier).showReader(),
                      icon: const Icon(Icons.book_online_rounded),
                      label: const Text('Continue Reader'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Processing Queue',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Watch recent projects that are still aligning without leaving the library.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    recentConnections.when(
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Books',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    recentLocations.when(
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Server Projects',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    recentConnections.when(
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
    return Column(
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
      ],
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text('$label • $detail'),
      trailing: trailing,
    );
  }
}

class _LibraryBookTile extends StatelessWidget {
  const _LibraryBookTile({required this.snapshot});

  final ReaderLocationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_rounded),
      title: Text(snapshot.sectionTitle ?? snapshot.projectId),
      subtitle: Text(
        '${snapshot.projectId} • ${(snapshot.progressFraction * 100).round()}% • ${snapshot.updatedAt.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
      ),
      trailing: Text(
        _formatMs(snapshot.positionMs),
        style: Theme.of(context).textTheme.labelLarge,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LibraryStatusChip(label: value.projectStatusLabel),
              if (value.latestJobLabel case final jobLabel?)
                _LibraryStatusChip(label: jobLabel),
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
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sync_rounded),
          title: Text(value.title),
          subtitle: Text(
            '${settings.shortHost} • ${value.latestJobLabel ?? value.projectStatusLabel}',
          ),
          trailing: FilledButton.tonal(
            onPressed: onOpen,
            child: const Text('Open'),
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
      data: (value) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          settings.hasAuthToken
              ? Icons.lock_outline_rounded
              : Icons.cloud_outlined,
        ),
        title: Text(value.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(settings.shortHost),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LibraryStatusChip(label: value.projectStatusLabel),
                if (value.latestJobLabel case final jobLabel?)
                  _LibraryStatusChip(label: jobLabel),
                _LibraryStatusChip(label: _formatBytes(value.totalSizeBytes)),
                ...offline.maybeWhen(
                  data: (offlineValue) =>
                      _offlineStatusChips(offlineValue, value.audioAssetCount),
                  orElse: () => const <Widget>[],
                ),
              ],
            ),
          ],
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _showProjectDetailsSheet(context, value),
              child: const Text('Details'),
            ),
            FilledButton.tonal(onPressed: onOpen, child: const Text('Open')),
          ],
        ),
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
        final theme = Theme.of(context);
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
            ],
          ),
        );
      },
    );
  }
}

String _formatMs(int value) {
  final duration = Duration(milliseconds: value);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
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
