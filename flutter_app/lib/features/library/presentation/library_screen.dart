import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/state/library_import_controller.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_location_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ReaderPalette.of(context);
    final currentSettings = ref.watch(runtimeConnectionSettingsProvider);
    final recentConnections = ref.watch(recentRuntimeConnectionSettingsProvider);
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
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
                    Text(
                      currentSettings.maybeWhen(
                        data: (settings) =>
                            '${settings.shortHost} • ${settings.normalizedProjectId}',
                        orElse: () => 'Loading current connection...',
                      ),
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
                      error: (error, _) => Text('Could not read library history. $error'),
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
                      'Recent Connections',
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
                              _ConnectionTile(
                                settings: item,
                                onOpen: () => _activateConnection(
                                  context,
                                  ref,
                                  item,
                                ),
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
            if (widget.state.epubFile != null || widget.state.audioFiles.isNotEmpty)
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

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.settings, required this.onOpen});

  final RuntimeConnectionSettings settings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        settings.hasAuthToken
            ? Icons.lock_outline_rounded
            : Icons.cloud_outlined,
      ),
      title: Text(settings.normalizedProjectId),
      subtitle: Text(settings.shortHost),
      trailing: FilledButton.tonal(
        onPressed: onOpen,
        child: const Text('Open'),
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

String _formatBytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }
  return '$value B';
}
