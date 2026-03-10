import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/network/sync_api_client.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/data/reader_study_store.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_audio_download_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_study_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(readerProjectProvider);
    final bundle = project.asData?.value;
    final connectionSettings = ref.watch(runtimeConnectionSettingsProvider);
    final recentConnections = ref.watch(
      recentRuntimeConnectionSettingsProvider,
    );
    final activeSettings =
        connectionSettings.asData?.value ?? defaultConnectionSettings;
    final playback = ref.watch(readerPlaybackProvider);
    final controller = ref.read(readerPlaybackProvider.notifier);
    final latestEvent = ref.watch(latestProjectEventProvider);
    final audioDownload = ref.watch(readerAudioDownloadProvider);
    final audioActions = ref.read(readerAudioDownloadProvider.notifier);
    final studyEntries = ref.watch(readerStudyEntriesProvider);
    final studyActions = ref.read(readerStudyEntriesProvider.notifier);
    final palette = ReaderPalette.of(context);

    ref.listen(projectEventsProvider, (_, next) {
      final event = next.asData?.value;
      if (event == null) {
        return;
      }

      ref.read(latestProjectEventProvider.notifier).setEvent(event);
      final type = event['type'] as String?;
      if (type == 'job.completed' ||
          type == 'job.failed' ||
          type == 'job.cancelled') {
        ref.invalidate(readerProjectProvider);
      }
    });

    final isCompact = MediaQuery.sizeOf(context).width < 1180;
    if (isCompact) {
      return _ReaderMobileScaffold(
        project: project,
        bundle: bundle,
        settings: activeSettings,
        playback: playback,
        latestEvent: latestEvent,
        audioDownload: audioDownload,
        studyEntries: studyEntries.asData?.value ?? const [],
        onRefresh: () => ref.invalidate(readerProjectProvider),
        onOpenConnectionSettings: () => _showConnectionSettingsSheet(
          context,
          activeSettings,
          recentConnections.asData?.value ?? const [],
        ),
        onOpenNavigation: bundle == null
            ? null
            : () => _showNavigationSheet(context, bundle, controller.seekTo),
        onOpenGapInspector: bundle == null
            ? null
            : () => _showGapInspectorSheet(
                context,
                bundle,
                playback.displayedPositionMs,
                controller.seekTo,
              ),
        onToggleTheme: controller.toggleTheme,
        onTogglePlayback: bundle == null
            ? null
            : () => controller.togglePlayback(
                bundle.syncArtifact.totalDurationMs,
              ),
        onSeekStart: controller.beginScrub,
        onSeekUpdate: controller.updateScrub,
        onSeekCommit: controller.commitScrub,
        onRewind: controller.rewind15Seconds,
        onForward: controller.forward15Seconds,
        onSetSpeed: controller.setSpeed,
        onSetFontScale: controller.setFontScale,
        onSetLineHeight: controller.setLineHeight,
        onSetParagraphSpacing: controller.setParagraphSpacing,
        onToggleFollowPlayback: controller.toggleFollowPlayback,
        onToggleHighContrast: controller.toggleHighContrastMode,
        onToggleLeftHanded: controller.toggleLeftHandedMode,
        onStartBook: controller.seekToContentStart,
        onDownload: audioActions.downloadCurrentProject,
        onRemove: audioActions.removeCurrentProjectAudio,
        onTokenTap: (token) => controller.seekTo(token.startMs),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: palette.backgroundBase),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: Column(
                      children: [
                        if (!playback.distractionFreeMode) ...[
                          _ReaderHeroBar(
                            project: project,
                            settings: activeSettings,
                            playback: playback,
                            bundle: bundle,
                            onToggleTheme: controller.toggleTheme,
                            onToggleDistractionFree:
                                controller.toggleDistractionFreeMode,
                            onOpenNavigation: bundle == null
                                ? null
                                : () => _showNavigationSheet(
                                    context,
                                    bundle,
                                    controller.seekTo,
                                  ),
                            onOpenGapInspector: bundle == null
                                ? null
                                : () => _showGapInspectorSheet(
                                    context,
                                    bundle,
                                    playback.displayedPositionMs,
                                    controller.seekTo,
                                  ),
                            onOpenConnectionSettings: () =>
                                _showConnectionSettingsSheet(
                                  context,
                                  activeSettings,
                                  recentConnections.asData?.value ?? const [],
                                ),
                          ),
                          const SizedBox(height: 12),
                          _ReaderStateStrip(
                            project: project,
                            settings: activeSettings,
                            onRefresh: () =>
                                ref.invalidate(readerProjectProvider),
                            onOpenConnectionSettings: () =>
                                _showConnectionSettingsSheet(
                                  context,
                                  activeSettings,
                                  recentConnections.asData?.value ?? const [],
                                ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Expanded(
                          child: playback.distractionFreeMode
                              ? Stack(
                                  children: [
                                    Positioned.fill(
                                      child: _ReaderStage(
                                        project: project,
                                        playback: playback,
                                        onRetry: () => ref.invalidate(
                                          readerProjectProvider,
                                        ),
                                        settings: activeSettings,
                                        onOpenConnectionSettings: () =>
                                            _showConnectionSettingsSheet(
                                              context,
                                              activeSettings,
                                              recentConnections.asData?.value ??
                                                  const [],
                                            ),
                                        onTokenTap: (token) =>
                                            controller.seekTo(token.startMs),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 16,
                                      left: playback.leftHandedMode ? 16 : null,
                                      right: playback.leftHandedMode
                                          ? null
                                          : 16,
                                      child: _ReaderFocusOverlay(
                                        playback: playback,
                                        hasPlayableContent:
                                            bundle != null &&
                                            bundle
                                                    .syncArtifact
                                                    .totalDurationMs >
                                                0,
                                        onTogglePlayback: bundle == null
                                            ? null
                                            : () => controller.togglePlayback(
                                                bundle
                                                    .syncArtifact
                                                    .totalDurationMs,
                                              ),
                                        onToggleDistractionFree: controller
                                            .toggleDistractionFreeMode,
                                        onRewind: controller.rewind15Seconds,
                                        onForward: controller.forward15Seconds,
                                      ),
                                    ),
                                  ],
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isWide = constraints.maxWidth >= 1180;
                                    final controlPanel = _ControlDock(
                                      bundle: bundle,
                                      playback: playback,
                                      latestEvent: latestEvent,
                                      audioDownload: audioDownload,
                                      onDownload:
                                          audioActions.downloadCurrentProject,
                                      onRemove: audioActions
                                          .removeCurrentProjectAudio,
                                      onRefresh: () =>
                                          ref.invalidate(readerProjectProvider),
                                      onStartBook:
                                          controller.seekToContentStart,
                                      onJumpToOutro:
                                          controller.seekToContentEnd,
                                      onSeekStart: controller.beginScrub,
                                      onSeekUpdate: controller.updateScrub,
                                      onSeekCommit: controller.commitScrub,
                                      onRewind: controller.rewind15Seconds,
                                      onForward: controller.forward15Seconds,
                                      onTogglePlayback: bundle == null
                                          ? null
                                          : () => controller.togglePlayback(
                                              bundle
                                                  .syncArtifact
                                                  .totalDurationMs,
                                            ),
                                      onSetSpeed: controller.setSpeed,
                                      onJumpToStart: playback.hasLeadingMatter
                                          ? controller.seekToContentStart
                                          : null,
                                      onJumpToEnd: playback.hasTrailingMatter
                                          ? controller.seekToContentEnd
                                          : null,
                                      onSetFontScale: controller.setFontScale,
                                      onSetLineHeight: controller.setLineHeight,
                                      onSetParagraphSpacing:
                                          controller.setParagraphSpacing,
                                      onToggleFollowPlayback:
                                          controller.toggleFollowPlayback,
                                      onToggleDistractionFree:
                                          controller.toggleDistractionFreeMode,
                                      onToggleHighContrast:
                                          controller.toggleHighContrastMode,
                                      onToggleLeftHanded:
                                          controller.toggleLeftHandedMode,
                                      onOpenGapInspector: bundle == null
                                          ? null
                                          : () => _showGapInspectorSheet(
                                              context,
                                              bundle,
                                              playback.displayedPositionMs,
                                              controller.seekTo,
                                            ),
                                      onJumpToNextConfidentSpan: bundle == null
                                          ? null
                                          : () {
                                              final nextStart =
                                                  _nextConfidentSpanStartMs(
                                                    bundle.syncArtifact,
                                                    playback
                                                        .displayedPositionMs,
                                                  );
                                              if (nextStart != null) {
                                                controller.seekTo(nextStart);
                                              }
                                            },
                                      studyEntries:
                                          studyEntries.asData?.value ??
                                          const [],
                                      onAddBookmark: bundle == null
                                          ? null
                                          : () => studyActions.addEntry(
                                              _studyDraftForPosition(
                                                bundle,
                                                playback.displayedPositionMs,
                                                ReaderStudyEntryType.bookmark,
                                              ),
                                            ),
                                      onAddHighlight: bundle == null
                                          ? null
                                          : () => studyActions.addEntry(
                                              _studyDraftForPosition(
                                                bundle,
                                                playback.displayedPositionMs,
                                                ReaderStudyEntryType.highlight,
                                              ),
                                            ),
                                      onAddNote: bundle == null
                                          ? null
                                          : () => _showNoteComposerSheet(
                                              context,
                                              onSave: (note) =>
                                                  studyActions.addEntry(
                                                    _studyDraftForPosition(
                                                      bundle,
                                                      playback
                                                          .displayedPositionMs,
                                                      ReaderStudyEntryType.note,
                                                      note: note,
                                                    ),
                                                  ),
                                            ),
                                      onOpenReviewTray: bundle == null
                                          ? null
                                          : () => _showReviewTraySheet(
                                              context,
                                              studyEntries.asData?.value ??
                                                  const [],
                                              controller.seekTo,
                                              studyActions.removeEntry,
                                            ),
                                      onApplyPreset: controller.applyPreset,
                                      onMarkLoopStart: controller.markLoopStart,
                                      onMarkLoopEnd: controller.markLoopEnd,
                                      onClearLoop: controller.clearLoop,
                                    );

                                    if (isWide) {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 15,
                                            child: _ReaderStage(
                                              project: project,
                                              playback: playback,
                                              onRetry: () => ref.invalidate(
                                                readerProjectProvider,
                                              ),
                                              settings: activeSettings,
                                              onOpenConnectionSettings: () =>
                                                  _showConnectionSettingsSheet(
                                                    context,
                                                    activeSettings,
                                                    recentConnections
                                                            .asData
                                                            ?.value ??
                                                        const [],
                                                  ),
                                              onTokenTap: (token) => controller
                                                  .seekTo(token.startMs),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          SizedBox(
                                            width: 320,
                                            child: controlPanel,
                                          ),
                                        ],
                                      );
                                    }

                                    final readerHeight =
                                        (constraints.maxHeight * 0.68)
                                            .clamp(360.0, 680.0)
                                            .toDouble();

                                    return _ReaderMobileLayout(
                                      project: project,
                                      bundle: bundle,
                                      settings: activeSettings,
                                      playback: playback,
                                      stageHeight: readerHeight,
                                      stage: _ReaderStage(
                                        project: project,
                                        playback: playback,
                                        onRetry: () => ref.invalidate(
                                          readerProjectProvider,
                                        ),
                                        settings: activeSettings,
                                        onOpenConnectionSettings: () =>
                                            _showConnectionSettingsSheet(
                                              context,
                                              activeSettings,
                                              recentConnections.asData?.value ??
                                                  const [],
                                            ),
                                        onTokenTap: (token) =>
                                            controller.seekTo(token.startMs),
                                      ),
                                      controlPanel: controlPanel,
                                      onToggleTheme: controller.toggleTheme,
                                      onOpenConnectionSettings: () =>
                                          _showConnectionSettingsSheet(
                                            context,
                                            activeSettings,
                                            recentConnections.asData?.value ??
                                                const [],
                                          ),
                                      onOpenNavigation: bundle == null
                                          ? null
                                          : () => _showNavigationSheet(
                                              context,
                                              bundle,
                                              controller.seekTo,
                                            ),
                                      onOpenGapInspector: bundle == null
                                          ? null
                                          : () => _showGapInspectorSheet(
                                              context,
                                              bundle,
                                              playback.displayedPositionMs,
                                              controller.seekTo,
                                            ),
                                      onTogglePlayback: bundle == null
                                          ? null
                                          : () => controller.togglePlayback(
                                              bundle
                                                  .syncArtifact
                                                  .totalDurationMs,
                                            ),
                                      onRewind: controller.rewind15Seconds,
                                      onForward: controller.forward15Seconds,
                                      onSeekStart: controller.beginScrub,
                                      onSeekUpdate: controller.updateScrub,
                                      onSeekCommit: controller.commitScrub,
                                      onStartBook: playback.hasLeadingMatter
                                          ? controller.seekToContentStart
                                          : null,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMs(int value) {
    final duration = Duration(milliseconds: value);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

Future<void> _showConnectionSettingsSheet(
  BuildContext context,
  RuntimeConnectionSettings settings,
  List<RuntimeConnectionSettings> recentConnections,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _ConnectionSettingsSheet(
      initialSettings: settings,
      recentConnections: recentConnections,
    ),
  );
}

Future<void> _showNoteComposerSheet(
  BuildContext context, {
  required Future<void> Function(String note) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _NoteComposerSheet(onSave: onSave),
  );
}

Future<void> _showNavigationSheet(
  BuildContext context,
  ReaderProjectBundle bundle,
  Future<void> Function(int positionMs) onNavigate,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) =>
        _BookNavigationSheet(bundle: bundle, onNavigate: onNavigate),
  );
}

Future<void> _showGapInspectorSheet(
  BuildContext context,
  ReaderProjectBundle bundle,
  int currentPositionMs,
  Future<void> Function(int positionMs) onNavigate,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _GapInspectorSheet(
      bundle: bundle,
      currentPositionMs: currentPositionMs,
      onNavigate: onNavigate,
    ),
  );
}

class _ReaderStateStrip extends StatelessWidget {
  const _ReaderStateStrip({
    required this.project,
    required this.settings,
    required this.onRefresh,
    required this.onOpenConnectionSettings,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final RuntimeConnectionSettings settings;
  final VoidCallback onRefresh;
  final VoidCallback onOpenConnectionSettings;

  @override
  Widget build(BuildContext context) {
    return project.when(
      data: (bundle) {
        final summary = _stateSummary(bundle);
        if (summary == null) {
          return const SizedBox.shrink();
        }
        final palette = ReaderPalette.of(context);
        final tone = summary.isProblem
            ? palette.accentSoft
            : palette.backgroundElevated;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary.message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (summary.canRefresh)
                    FilledButton.tonal(
                      onPressed: onRefresh,
                      child: const Text('Refresh'),
                    ),
                  FilledButton.tonal(
                    onPressed: onOpenConnectionSettings,
                    child: const Text('Connection'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => _ReaderTransitionCard(
        title: 'Opening reader',
        message:
            'Connecting to ${settings.shortHost} and loading ${settings.normalizedProjectId}.',
        chips: const ['Backend', 'Reader model', 'Sync timeline'],
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  static _ReaderStateSummary? _stateSummary(ReaderProjectBundle bundle) {
    final fallback = switch (bundle.source) {
      ReaderContentSource.selectionRequired => _ReaderStateSummary(
        title: 'Choose a project first',
        message:
            bundle.statusMessage ??
            'Pick a backend target or import a book before opening the reader.',
        canRefresh: false,
        isProblem: false,
      ),
      ReaderContentSource.offlineCache => null,
      ReaderContentSource.artifactPending => _ReaderStateSummary(
        title: 'Artifacts still processing',
        message:
            bundle.statusMessage ??
            'The project exists, but the latest reader artifacts are not ready yet.',
        canRefresh: true,
        isProblem: false,
      ),
      ReaderContentSource.projectError => _ReaderStateSummary(
        title: 'Latest reader artifacts are incomplete',
        message:
            bundle.statusMessage ??
            'The project loaded, but the last artifact pass did not leave a usable reading model.',
        canRefresh: true,
        isProblem: true,
      ),
      ReaderContentSource.demoFallback => null,
      ReaderContentSource.api => null,
    };

    if (fallback != null) {
      return fallback;
    }
    return null;
  }
}

class _ReaderStateSummary {
  const _ReaderStateSummary({
    required this.title,
    required this.message,
    required this.canRefresh,
    required this.isProblem,
  });

  final String title;
  final String message;
  final bool canRefresh;
  final bool isProblem;
}

class _ReaderMobileScaffold extends StatelessWidget {
  const _ReaderMobileScaffold({
    required this.project,
    required this.bundle,
    required this.settings,
    required this.playback,
    required this.latestEvent,
    required this.audioDownload,
    required this.studyEntries,
    required this.onRefresh,
    required this.onOpenConnectionSettings,
    required this.onOpenNavigation,
    required this.onOpenGapInspector,
    required this.onToggleTheme,
    required this.onTogglePlayback,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekCommit,
    required this.onRewind,
    required this.onForward,
    required this.onSetSpeed,
    required this.onSetFontScale,
    required this.onSetLineHeight,
    required this.onSetParagraphSpacing,
    required this.onToggleFollowPlayback,
    required this.onToggleHighContrast,
    required this.onToggleLeftHanded,
    required this.onStartBook,
    required this.onDownload,
    required this.onRemove,
    required this.onTokenTap,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final ReaderProjectBundle? bundle;
  final RuntimeConnectionSettings settings;
  final ReaderPlaybackState playback;
  final Map<String, dynamic>? latestEvent;
  final ReaderAudioDownloadState audioDownload;
  final List<ReaderStudyEntry> studyEntries;
  final VoidCallback onRefresh;
  final VoidCallback onOpenConnectionSettings;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onOpenGapInspector;
  final VoidCallback onToggleTheme;
  final VoidCallback? onTogglePlayback;
  final void Function(double) onSeekStart;
  final void Function(double) onSeekUpdate;
  final Future<void> Function(double) onSeekCommit;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final ValueChanged<double> onSetSpeed;
  final ValueChanged<double> onSetFontScale;
  final ValueChanged<double> onSetLineHeight;
  final ValueChanged<double> onSetParagraphSpacing;
  final VoidCallback onToggleFollowPlayback;
  final VoidCallback onToggleHighContrast;
  final VoidCallback onToggleLeftHanded;
  final Future<void> Function() onStartBook;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final currentBundle = bundle;
    final title =
        currentBundle != null &&
            currentBundle.readerModel.title.trim().isNotEmpty
        ? currentBundle.readerModel.title
        : 'Reader';
    final subtitle = switch (currentBundle?.source) {
      ReaderContentSource.selectionRequired =>
        'Connect to a server, then choose or import a book from Library.',
      ReaderContentSource.offlineCache =>
        'Offline cache loaded on this device.',
      ReaderContentSource.artifactPending =>
        'Sync is still processing. You can leave this screen and come back later.',
      ReaderContentSource.projectError =>
        'This project needs attention before it can be read cleanly.',
      ReaderContentSource.demoFallback => 'Demo content is active.',
      ReaderContentSource.api || null => settings.shortHost,
    };
    void showReaderSettingsSheet() {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reader settings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              _CompactSliderRow(
                label: 'Text size',
                value: playback.fontScale,
                min: 0.85,
                max: 1.5,
                onChanged: onSetFontScale,
              ),
              _CompactSliderRow(
                label: 'Line height',
                value: playback.lineHeight,
                min: 1.3,
                max: 2.0,
                onChanged: onSetLineHeight,
              ),
              _CompactSliderRow(
                label: 'Paragraph spacing',
                value: playback.paragraphSpacing,
                min: 0.8,
                max: 1.8,
                onChanged: onSetParagraphSpacing,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: playback.followPlayback,
                onChanged: (_) => onToggleFollowPlayback(),
                title: const Text('Follow playback'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: playback.highContrastMode,
                onChanged: (_) => onToggleHighContrast(),
                title: const Text('High contrast'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: playback.leftHandedMode,
                onChanged: (_) => onToggleLeftHanded(),
                title: const Text('Left-handed controls'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    void showReaderDetailsSheet() {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Project details', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (currentBundle != null)
                  _ReaderDiagnosticsBanner(
                    bundle: currentBundle,
                    playback: playback,
                  ),
                const SizedBox(height: 12),
                if (currentBundle != null && currentBundle.totalAudioAssets > 0)
                  _AudioDownloadBanner(
                    bundle: currentBundle,
                    downloadState: audioDownload,
                    onDownload: onDownload,
                    onRemove: onRemove,
                  ),
                if (latestEvent != null) ...[
                  const SizedBox(height: 12),
                  _JobEventBanner(event: latestEvent!),
                ],
                if (onOpenGapInspector != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onOpenGapInspector,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Open sync inspector'),
                  ),
                ],
                if (studyEntries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${studyEntries.length} saved study items on this device.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.backgroundBase,
      appBar: AppBar(
        backgroundColor: palette.backgroundBase,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: onOpenNavigation,
            icon: const Icon(Icons.toc_rounded),
            tooltip: 'Contents',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'connection':
                  onOpenConnectionSettings();
                case 'details':
                  showReaderDetailsSheet();
                case 'settings':
                  showReaderSettingsSheet();
                case 'theme':
                  onToggleTheme();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'settings', child: Text('Reader settings')),
              PopupMenuItem(value: 'details', child: Text('Project details')),
              PopupMenuItem(value: 'connection', child: Text('Connection')),
              PopupMenuItem(value: 'theme', child: Text('Toggle theme')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (currentBundle != null &&
                currentBundle.source != ReaderContentSource.api)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: _SourceBanner(
                  source: currentBundle.source,
                  message: currentBundle.statusMessage,
                  onRefresh: onRefresh,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _ReaderStage(
                  project: project,
                  playback: playback,
                  onRetry: onRefresh,
                  settings: settings,
                  onOpenConnectionSettings: onOpenConnectionSettings,
                  onTokenTap: onTokenTap,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.backgroundElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: onRewind,
                        icon: const Icon(Icons.replay_10_rounded),
                      ),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onTogglePlayback,
                          icon: Icon(
                            playback.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                          label: Text(playback.isPlaying ? 'Pause' : 'Play'),
                        ),
                      ),
                      IconButton(
                        onPressed: onForward,
                        icon: const Icon(Icons.forward_10_rounded),
                      ),
                    ],
                  ),
                  Slider(
                    value: playback.totalDurationMs == 0
                        ? 0
                        : playback.displayedPositionMs
                              .clamp(0, playback.totalDurationMs)
                              .toDouble(),
                    min: 0,
                    max: playback.totalDurationMs <= 0
                        ? 1
                        : playback.totalDurationMs.toDouble(),
                    onChangeStart: onSeekStart,
                    onChanged: onSeekUpdate,
                    onChangeEnd: (value) => onSeekCommit(value),
                  ),
                  Row(
                    children: [
                      Text(
                        ReaderScreen._formatMs(playback.displayedPositionMs),
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        ReaderScreen._formatMs(playback.totalDurationMs),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _DiagnosticsChip(
                        label: '${playback.speed.toStringAsFixed(1)}x pace',
                      ),
                      if (playback.hasLeadingMatter)
                        FilledButton.tonalIcon(
                          onPressed: () => onStartBook(),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Start book'),
                        ),
                      IconButton(
                        onPressed: showReaderDetailsSheet,
                        icon: const Icon(Icons.info_outline_rounded),
                        tooltip: 'Project details',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSliderRow extends StatelessWidget {
  const _CompactSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ReaderTransitionCard extends StatelessWidget {
  const _ReaderTransitionCard({
    required this.title,
    required this.message,
    required this.chips,
  });

  final String title;
  final String message;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final chip in chips) _DiagnosticsChip(label: chip)],
          ),
        ],
      ),
    );
  }
}

class _ReaderHeroBar extends StatelessWidget {
  const _ReaderHeroBar({
    required this.project,
    required this.settings,
    required this.playback,
    required this.bundle,
    required this.onToggleTheme,
    required this.onToggleDistractionFree,
    required this.onOpenNavigation,
    required this.onOpenGapInspector,
    required this.onOpenConnectionSettings,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final RuntimeConnectionSettings settings;
  final ReaderPlaybackState playback;
  final ReaderProjectBundle? bundle;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleDistractionFree;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onOpenGapInspector;
  final VoidCallback onOpenConnectionSettings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final title = project.maybeWhen(
      data: (bundle) => bundle.readerModel.title,
      orElse: () => 'Reader',
    );
    final subtitle = project.when(
      data: (bundle) => bundle.source == ReaderContentSource.demoFallback
          ? 'Demo reader loaded while the backend is unavailable.'
          : bundle.source == ReaderContentSource.selectionRequired
          ? 'Choose a project from Library before opening the reader.'
          : bundle.readerModel.sections.isEmpty
          ? 'The project is connected, but reader artifacts are still thin.'
          : 'Synchronized reading for ${bundle.projectId}.',
      loading: () => 'Connecting to ${settings.shortHost}',
      error: (_, _) =>
          'The app can start from GitHub releases and point at your own backend at runtime.',
    );
    final sync = bundle?.syncArtifact;
    final coverage = sync == null ? '--' : '${(sync.coverage * 100).round()}%';
    final confidence = sync == null
        ? '--'
        : '${(sync.matchConfidence * 100).round()}%';
    final audioState = bundle == null
        ? 'Connecting'
        : bundle!.hasCompleteOfflineAudio
        ? 'Offline audio'
        : bundle!.audioUrls.isNotEmpty
        ? 'Streaming audio'
        : 'Text sync only';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderSubtle),
        color: palette.backgroundElevated,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DiagnosticsChip(label: audioState),
                      _DiagnosticsChip(label: settings.shortHost),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: palette.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Coverage $coverage  •  Confidence $confidence',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onOpenNavigation,
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('Navigate'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onOpenConnectionSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Connection'),
                ),
                if (onOpenGapInspector != null)
                  FilledButton.tonalIcon(
                    onPressed: onOpenGapInspector,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Inspector'),
                  ),
                IconButton.filledTonal(
                  onPressed: onToggleTheme,
                  icon: Icon(
                    playback.themeMode == ThemeMode.light
                        ? Icons.nightlight_round
                        : Icons.wb_sunny_outlined,
                  ),
                  tooltip: playback.themeMode == ThemeMode.light
                      ? 'Switch to night theme'
                      : 'Switch to paper theme',
                ),
                IconButton.filledTonal(
                  onPressed: onToggleDistractionFree,
                  icon: Icon(
                    playback.distractionFreeMode
                        ? Icons.center_focus_strong_rounded
                        : Icons.center_focus_weak_rounded,
                  ),
                  tooltip: playback.distractionFreeMode
                      ? 'Exit focus mode'
                      : 'Enter focus mode',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderStage extends StatelessWidget {
  const _ReaderStage({
    required this.project,
    required this.playback,
    required this.onRetry,
    required this.settings,
    required this.onOpenConnectionSettings,
    required this.onTokenTap,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final ReaderPlaybackState playback;
  final VoidCallback onRetry;
  final RuntimeConnectionSettings settings;
  final VoidCallback onOpenConnectionSettings;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 1180;
    final stageRadius = BorderRadius.circular(isCompact ? 22 : 28);
    return Semantics(
      container: true,
      label: 'Reader stage',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: stageRadius,
          border: isCompact ? null : Border.all(color: palette.borderSubtle),
          color: isCompact
              ? palette.backgroundBase
              : palette.backgroundElevated,
          boxShadow: isCompact
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: stageRadius,
          child: project.when(
            data: (bundle) => _ReaderLoadedView(
              bundle: bundle,
              playback: playback,
              onTokenTap: onTokenTap,
            ),
            loading: () => _ReaderLoadingView(settings: settings),
            error: (error, _) => _ReaderErrorView(
              message: formatSyncApiError(error),
              settings: settings,
              onRetry: onRetry,
              onOpenConnectionSettings: onOpenConnectionSettings,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderMobileLayout extends StatelessWidget {
  const _ReaderMobileLayout({
    required this.project,
    required this.bundle,
    required this.settings,
    required this.playback,
    required this.stageHeight,
    required this.stage,
    required this.controlPanel,
    required this.onToggleTheme,
    required this.onOpenConnectionSettings,
    required this.onOpenNavigation,
    required this.onOpenGapInspector,
    required this.onTogglePlayback,
    required this.onRewind,
    required this.onForward,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekCommit,
    required this.onStartBook,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final ReaderProjectBundle? bundle;
  final RuntimeConnectionSettings settings;
  final ReaderPlaybackState playback;
  final double stageHeight;
  final Widget stage;
  final Widget controlPanel;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnectionSettings;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onOpenGapInspector;
  final VoidCallback? onTogglePlayback;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final void Function(double) onSeekStart;
  final void Function(double) onSeekUpdate;
  final Future<void> Function(double) onSeekCommit;
  final Future<void> Function()? onStartBook;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final title = project.maybeWhen(
      data: (value) => value.readerModel.title,
      orElse: () => settings.normalizedProjectId,
    );
    final subtitle = bundle == null
        ? 'Connect a project, then read and listen from one focused mobile surface.'
        : switch (bundle!.source) {
            ReaderContentSource.selectionRequired =>
              'Choose a project from Library before opening the reader',
            ReaderContentSource.api => 'Live sync from ${settings.shortHost}',
            ReaderContentSource.offlineCache =>
              'Offline cache from this device',
            ReaderContentSource.artifactPending =>
              'Artifacts are still processing',
            ReaderContentSource.projectError =>
              'Latest artifacts need attention',
            ReaderContentSource.demoFallback =>
              'Demo content while the backend is unavailable',
          };

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: palette.backgroundElevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleTheme,
                    icon: Icon(
                      playback.themeMode == ThemeMode.light
                          ? Icons.nightlight_round
                          : Icons.wb_sunny_outlined,
                    ),
                  ),
                  IconButton(
                    onPressed: onOpenConnectionSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DiagnosticsChip(label: settings.shortHost),
                  if (bundle != null)
                    _DiagnosticsChip(
                      label: _ReaderDiagnosticsBanner._artifactSourceLabel(
                        bundle!.source,
                      ),
                    ),
                  if (bundle?.hasAnyAudio == true)
                    _DiagnosticsChip(
                      label: bundle!.hasCompleteOfflineAudio
                          ? 'Offline audio'
                          : bundle!.audioUrls.isNotEmpty
                          ? 'Audio ready'
                          : 'Text only',
                    ),
                ],
              ),
              if (onStartBook != null &&
                  bundle != null &&
                  playback.displayedPositionMs <
                      bundle!.syncArtifact.contentStartMs) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onStartBook == null ? null : () => onStartBook!(),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Skip Intro'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(height: stageHeight, child: stage),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: palette.backgroundElevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ReaderScreen._formatMs(playback.displayedPositionMs),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (bundle != null)
                    Text(
                      ReaderScreen._formatMs(
                        bundle!.syncArtifact.totalDurationMs,
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
              if (bundle != null) ...[
                Slider(
                  value: playback.displayedPositionMs
                      .clamp(0, bundle!.syncArtifact.totalDurationMs)
                      .toDouble(),
                  max: bundle!.syncArtifact.totalDurationMs > 0
                      ? bundle!.syncArtifact.totalDurationMs.toDouble()
                      : 1,
                  onChangeStart: onSeekStart,
                  onChanged: onSeekUpdate,
                  onChangeEnd: onSeekCommit,
                ),
              ],
              Row(
                children: [
                  IconButton(
                    onPressed: onRewind,
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTogglePlayback,
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(playback.isPlaying ? 'Pause' : 'Play'),
                    ),
                  ),
                  IconButton(
                    onPressed: onForward,
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onOpenNavigation,
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: const Text('Navigate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: theme.colorScheme.surface,
                        builder: (context) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: controlPanel,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Tools'),
                    ),
                  ),
                ],
              ),
              if (onOpenGapInspector != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpenGapInspector,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Inspect sync quality'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({
    required this.bundle,
    required this.playback,
    required this.latestEvent,
    required this.audioDownload,
    required this.onDownload,
    required this.onRemove,
    required this.onRefresh,
    required this.onStartBook,
    required this.onJumpToOutro,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekCommit,
    required this.onRewind,
    required this.onForward,
    required this.onTogglePlayback,
    required this.onSetSpeed,
    required this.onJumpToStart,
    required this.onJumpToEnd,
    required this.onSetFontScale,
    required this.onSetLineHeight,
    required this.onSetParagraphSpacing,
    required this.onToggleFollowPlayback,
    required this.onToggleDistractionFree,
    required this.onToggleHighContrast,
    required this.onToggleLeftHanded,
    required this.onOpenGapInspector,
    required this.onJumpToNextConfidentSpan,
    required this.studyEntries,
    required this.onAddBookmark,
    required this.onAddHighlight,
    required this.onAddNote,
    required this.onOpenReviewTray,
    required this.onApplyPreset,
    required this.onMarkLoopStart,
    required this.onMarkLoopEnd,
    required this.onClearLoop,
  });

  final ReaderProjectBundle? bundle;
  final ReaderPlaybackState playback;
  final Map<String, dynamic>? latestEvent;
  final ReaderAudioDownloadState audioDownload;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;
  final VoidCallback onRefresh;
  final Future<void> Function() onStartBook;
  final Future<void> Function() onJumpToOutro;
  final void Function(double) onSeekStart;
  final void Function(double) onSeekUpdate;
  final Future<void> Function(double) onSeekCommit;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback? onTogglePlayback;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onJumpToStart;
  final VoidCallback? onJumpToEnd;
  final ValueChanged<double> onSetFontScale;
  final ValueChanged<double> onSetLineHeight;
  final ValueChanged<double> onSetParagraphSpacing;
  final VoidCallback onToggleFollowPlayback;
  final VoidCallback onToggleDistractionFree;
  final VoidCallback onToggleHighContrast;
  final VoidCallback onToggleLeftHanded;
  final VoidCallback? onOpenGapInspector;
  final VoidCallback? onJumpToNextConfidentSpan;
  final List<ReaderStudyEntry> studyEntries;
  final VoidCallback? onAddBookmark;
  final VoidCallback? onAddHighlight;
  final VoidCallback? onAddNote;
  final VoidCallback? onOpenReviewTray;
  final Future<void> Function(ReaderPlaybackPreset preset) onApplyPreset;
  final VoidCallback onMarkLoopStart;
  final VoidCallback onMarkLoopEnd;
  final VoidCallback onClearLoop;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final currentPositionMs = playback.displayedPositionMs;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: palette.backgroundElevated.withValues(alpha: 0.92),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DockHeader(
              bundle: bundle,
              playback: playback,
              currentPositionMs: currentPositionMs,
            ),
            const SizedBox(height: 16),
            if (bundle != null)
              _DockSection(
                title: 'Source',
                icon: Icons.travel_explore_rounded,
                child: _SourceBanner(
                  source: bundle!.source,
                  message: bundle!.statusMessage,
                  onRefresh: onRefresh,
                ),
              ),
            if (bundle != null) const SizedBox(height: 12),
            if (bundle != null && bundle!.totalAudioAssets > 0) ...[
              _DockSection(
                title: 'Offline audio',
                icon: Icons.download_for_offline_rounded,
                child: _AudioDownloadBanner(
                  bundle: bundle!,
                  downloadState: audioDownload,
                  onDownload: onDownload,
                  onRemove: onRemove,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (bundle != null) ...[
              _DockExpansionSection(
                title: 'Diagnostics',
                icon: Icons.podcasts_rounded,
                child: _ReaderDiagnosticsBanner(
                  bundle: bundle!,
                  playback: playback,
                ),
              ),
              const SizedBox(height: 12),
              _DockExpansionSection(
                title: 'Progress',
                icon: Icons.timeline_rounded,
                child: _ReadingProgressBanner(
                  bundle: bundle!,
                  currentPositionMs: currentPositionMs,
                ),
              ),
              const SizedBox(height: 12),
              _DockExpansionSection(
                title: 'Listen',
                icon: Icons.play_circle_outline_rounded,
                initiallyExpanded: true,
                child: _PlaybackPowerCard(
                  playback: playback,
                  onApplyPreset: onApplyPreset,
                  onMarkLoopStart: onMarkLoopStart,
                  onMarkLoopEnd: onMarkLoopEnd,
                  onClearLoop: onClearLoop,
                ),
              ),
              const SizedBox(height: 12),
              _DockExpansionSection(
                title: 'Reading surface',
                icon: Icons.format_size_rounded,
                child: _ReaderPreferencesCard(
                  playback: playback,
                  onSetFontScale: onSetFontScale,
                  onSetLineHeight: onSetLineHeight,
                  onSetParagraphSpacing: onSetParagraphSpacing,
                  onToggleFollowPlayback: onToggleFollowPlayback,
                  onToggleDistractionFree: onToggleDistractionFree,
                  onToggleHighContrast: onToggleHighContrast,
                  onToggleLeftHanded: onToggleLeftHanded,
                ),
              ),
              const SizedBox(height: 12),
              _DockExpansionSection(
                title: 'Study',
                icon: Icons.edit_note_rounded,
                initiallyExpanded: true,
                child: _StudyWorkflowCard(
                  entries: studyEntries,
                  onAddBookmark: onAddBookmark,
                  onAddHighlight: onAddHighlight,
                  onAddNote: onAddNote,
                  onOpenReviewTray: onOpenReviewTray,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (bundle != null &&
                bundle!.syncArtifact.hasLeadingMatter &&
                currentPositionMs < bundle!.syncArtifact.contentStartMs) ...[
              _DockSection(
                title: 'Content window',
                icon: Icons.skip_next_rounded,
                child: _ContentWindowBanner(
                  syncArtifact: bundle!.syncArtifact,
                  currentPositionMs: currentPositionMs,
                  onStartBook: () => onStartBook(),
                  onJumpToOutro: bundle!.syncArtifact.hasTrailingMatter
                      ? () => onJumpToOutro()
                      : null,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (bundle != null) ...[
              _DockSection(
                title: 'Sync intelligence',
                icon: Icons.radar_rounded,
                child: _SyncIntelligenceBanner(
                  bundle: bundle!,
                  currentPositionMs: currentPositionMs,
                  onOpenGapInspector: onOpenGapInspector,
                  onJumpToNextConfidentSpan: onJumpToNextConfidentSpan,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (latestEvent != null) ...[
              _DockExpansionSection(
                title: 'Live job state',
                icon: Icons.sync_rounded,
                child: _JobEventBanner(event: latestEvent!),
              ),
              const SizedBox(height: 12),
            ],
            if (bundle != null) ...[
              _DockExpansionSection(
                title: 'Current gap',
                icon: Icons.linear_scale_rounded,
                child: _GapStatusBanner(
                  gap: bundle!.syncArtifact.activeGapAt(currentPositionMs),
                ),
              ),
              const SizedBox(height: 12),
              _DockExpansionSection(
                title: 'Playback state',
                icon: Icons.equalizer_rounded,
                child: _PlaybackStatusBanner(
                  playback: playback,
                  currentPositionMs: currentPositionMs,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: palette.backgroundBase,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ReaderScreen._formatMs(currentPositionMs),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          ReaderScreen._formatMs(
                            bundle!.syncArtifact.totalDurationMs,
                          ),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${playback.speed.toStringAsFixed(2)}x',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                    Slider(
                      value: currentPositionMs
                          .clamp(0, bundle!.syncArtifact.totalDurationMs)
                          .toDouble(),
                      max: bundle!.syncArtifact.totalDurationMs > 0
                          ? bundle!.syncArtifact.totalDurationMs.toDouble()
                          : 1,
                      label: ReaderScreen._formatMs(currentPositionMs),
                      onChangeStart: onSeekStart,
                      onChanged: onSeekUpdate,
                      onChangeEnd: onSeekCommit,
                    ),
                    _ContentWindowRow(
                      playback: playback,
                      currentPositionMs: currentPositionMs,
                      onJumpToStart: onJumpToStart,
                      onJumpToEnd: onJumpToEnd,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 340;
                        final playButton = compact
                            ? FilledButton(
                                onPressed: onTogglePlayback,
                                child: Icon(
                                  playback.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: onTogglePlayback,
                                icon: Icon(
                                  playback.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  playback.isPlaying ? 'Pause' : 'Play',
                                ),
                              );

                        return Column(
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: onRewind,
                                  icon: const Icon(Icons.replay_10_rounded),
                                ),
                                IconButton.filledTonal(
                                  onPressed: onForward,
                                  icon: const Icon(Icons.forward_10_rounded),
                                ),
                                PopupMenuButton<double>(
                                  initialValue: playback.speed,
                                  onSelected: onSetSpeed,
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 0.8,
                                      child: Text('0.8x'),
                                    ),
                                    PopupMenuItem(
                                      value: 1.0,
                                      child: Text('1.0x'),
                                    ),
                                    PopupMenuItem(
                                      value: 1.25,
                                      child: Text('1.25x'),
                                    ),
                                    PopupMenuItem(
                                      value: 1.5,
                                      child: Text('1.5x'),
                                    ),
                                  ],
                                  child: const _SpeedChip(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(width: double.infinity, child: playButton),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DockHeader extends StatelessWidget {
  const _DockHeader({
    required this.bundle,
    required this.playback,
    required this.currentPositionMs,
  });

  final ReaderProjectBundle? bundle;
  final ReaderPlaybackState playback;
  final int currentPositionMs;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accentPrimary.withValues(alpha: 0.10),
            palette.backgroundBase,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Playback and reading controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            bundle == null
                ? 'Connect a project to unlock playback, diagnostics, and study controls.'
                : 'Keep transport, sync quality, and reading adjustments close without overwhelming the page.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(
                label: playback.isPlaying ? 'Playing' : 'Paused',
              ),
              _DiagnosticsChip(
                label: '${playback.speed.toStringAsFixed(2)}x pace',
              ),
              _DiagnosticsChip(
                label: 'At ${ReaderScreen._formatMs(currentPositionMs)}',
              ),
              if (bundle != null)
                _DiagnosticsChip(
                  label: '${bundle!.syncArtifact.tokens.length} synced words',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DockSection extends StatelessWidget {
  const _DockSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: palette.backgroundBase.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: palette.accentPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: palette.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DockExpansionSection extends StatelessWidget {
  const _DockExpansionSection({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.backgroundBase.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, size: 18, color: palette.accentPrimary),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: palette.textPrimary),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _ReaderPageHeader extends StatelessWidget {
  const _ReaderPageHeader({required this.bundle, required this.playback});

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final activeToken = _activeTokenAtPosition(
      bundle.syncArtifact,
      playback.displayedPositionMs,
    );
    final activeWord = activeToken?.text ?? 'Waiting for audio';
    final activeSection =
        bundle.readerModel.sections
            .where((section) => section.id == activeToken?.location.sectionId)
            .map((section) => section.title ?? 'Current section')
            .cast<String?>()
            .firstWhere(
              (value) => value != null && value.isNotEmpty,
              orElse: () => null,
            ) ??
        'Current section';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.borderSubtle)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 10,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Now reading',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.accentPrimary,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                activeSection,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(label: activeWord),
              _DiagnosticsChip(
                label:
                    '${(bundle.syncArtifact.coverage * 100).round()}% aligned',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionSettingsSheet extends ConsumerStatefulWidget {
  const _ConnectionSettingsSheet({
    required this.initialSettings,
    required this.recentConnections,
  });

  final RuntimeConnectionSettings initialSettings;
  final List<RuntimeConnectionSettings> recentConnections;

  @override
  ConsumerState<_ConnectionSettingsSheet> createState() =>
      _ConnectionSettingsSheetState();
}

class _ConnectionSettingsSheetState
    extends ConsumerState<_ConnectionSettingsSheet> {
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _projectIdController;
  late final TextEditingController _authTokenController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _showAdvancedTarget = false;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController(
      text: widget.initialSettings.apiBaseUrl,
    );
    _projectIdController = TextEditingController(
      text: widget.initialSettings.projectId,
    );
    _authTokenController = TextEditingController(
      text: widget.initialSettings.authToken,
    );
    _showAdvancedTarget = widget.initialSettings.projectId.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _projectIdController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final currentDraft = RuntimeConnectionSettings(
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      projectId: _projectIdController.text.trim(),
      authToken: _authTokenController.text.trim(),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Connect to your server',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'These values stay on this device only. For normal use, just connect to the server and pick a book from Library.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_connectionHint(currentDraft) case final hint?) ...[
                const SizedBox(height: 16),
                _ConnectionHintBanner(message: hint),
              ],
              if (widget.recentConnections.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Recent Servers', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final recent in widget.recentConnections)
                      InputChip(
                        label: Text(recent.shortHost),
                        avatar: Icon(
                          recent.hasAuthToken
                              ? Icons.lock_outline_rounded
                              : Icons.public_outlined,
                          size: 18,
                        ),
                        onPressed: () => _applyRecent(recent),
                        onDeleted: () => _removeRecent(recent),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _apiBaseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'https://your-host/v1',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  final candidate = value?.trim() ?? '';
                  if (candidate.isEmpty) {
                    return 'Backend URL is required.';
                  }
                  final uri = Uri.tryParse(candidate);
                  if (uri == null ||
                      !(uri.hasScheme &&
                          (uri.scheme == 'http' || uri.scheme == 'https'))) {
                    return 'Use a full http:// or https:// URL.';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _authTokenController,
                decoration: const InputDecoration(
                  labelText: 'Auth Token',
                  hintText: 'Optional bearer token',
                ),
                obscureText: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _showAdvancedTarget,
                title: const Text('Advanced: open one book directly'),
                subtitle: const Text(
                  'Most people can ignore this. After connecting, choose a book from Library instead.',
                ),
                onChanged: (value) =>
                    setState(() => _showAdvancedTarget = value),
              ),
              if (_showAdvancedTarget) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _projectIdController,
                  decoration: const InputDecoration(
                    labelText: 'Project ID',
                    hintText: 'Optional advanced target',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Privacy: server URL, token, and any optional direct-book target stay on this device. They are never committed or uploaded by the app.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.cloud_done_rounded),
                    label: Text(_isSaving ? 'Saving...' : 'Save and Reload'),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _resetToDefaults,
                    child: const Text('Reset to Release Defaults'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _applyRecent(RuntimeConnectionSettings recent) {
    _apiBaseUrlController.text = recent.normalizedApiBaseUrl;
    _projectIdController.text = recent.normalizedProjectId;
    _authTokenController.text = recent.authToken;
    _showAdvancedTarget = recent.normalizedProjectId.isNotEmpty;
    setState(() {});
  }

  Future<void> _removeRecent(RuntimeConnectionSettings recent) async {
    await ref
        .read(runtimeConnectionSettingsProvider.notifier)
        .removeRecent(recent);
    final replacement = await ref.read(
      runtimeConnectionSettingsProvider.future,
    );
    if (!mounted) {
      return;
    }
    _applyRecent(replacement);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final settings = RuntimeConnectionSettings(
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      projectId: _showAdvancedTarget ? _projectIdController.text.trim() : '',
      authToken: _authTokenController.text.trim(),
    );
    await ref.read(runtimeConnectionSettingsProvider.notifier).save(settings);
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() => _isSaving = true);
    await ref.read(runtimeConnectionSettingsProvider.notifier).reset();
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

String? _connectionHint(RuntimeConnectionSettings settings) {
  if (settings.normalizedApiBaseUrl.isEmpty) {
    return null;
  }
  if (settings.isLocalhostTarget) {
    return 'This target uses localhost. On a physical phone, localhost points to the phone itself, not your laptop. Use your LAN or Tailscale host instead.';
  }
  if (settings.usesHttp) {
    return 'This target uses HTTP. That is fine for local development, but deployed environments should use HTTPS so WebSocket traffic upgrades to WSS.';
  }
  return null;
}

String _errorHelp(RuntimeConnectionSettings settings) {
  if (settings.isLocalhostTarget) {
    return 'If this is a physical device, replace localhost with your laptop host or Tailscale address, then retry.';
  }
  if (!settings.hasAuthToken) {
    return 'Check that the backend URL and project ID are correct. If your server is protected, add the auth token in Connection settings.';
  }
  return 'Check that the backend URL, project ID, and auth token are all correct, then retry the request.';
}

class _ReaderLoadedView extends StatefulWidget {
  const _ReaderLoadedView({
    required this.bundle,
    required this.playback,
    required this.onTokenTap,
  });

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  State<_ReaderLoadedView> createState() => _ReaderLoadedViewState();
}

class _ReaderLoadedViewState extends State<_ReaderLoadedView> {
  final Map<String, GlobalKey> _paragraphKeys = <String, GlobalKey>{};
  String? _lastFollowedParagraphKey;

  @override
  void didUpdateWidget(covariant _ReaderLoadedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeLocationKey = _activeTokenAtPosition(
      widget.bundle.syncArtifact,
      widget.playback.displayedPositionMs,
    )?.location.locationKey;
    final activeParagraphKey = _paragraphKeyForLocation(activeLocationKey);

    if (!widget.playback.followPlayback ||
        widget.playback.isScrubbing ||
        activeParagraphKey == null ||
        activeParagraphKey == _lastFollowedParagraphKey) {
      return;
    }

    _lastFollowedParagraphKey = activeParagraphKey;
    final targetContext = _paragraphKeys[activeParagraphKey]?.currentContext;
    if (targetContext == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.22,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final playback = widget.playback;
    final palette = ReaderPalette.of(context);

    if (bundle.readerModel.sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
          decoration: BoxDecoration(
            color: palette.backgroundElevated,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                bundle.statusMessage ?? 'Reader content is not available yet.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'The backend is reachable, but there is no normalized reader model to render yet. This usually means alignment is still processing or the latest artifact is incomplete.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final syncIndex = {
      for (final token in bundle.syncArtifact.tokens)
        token.location.locationKey: token,
    };
    final activeLocationKey = _activeTokenAtPosition(
      bundle.syncArtifact,
      playback.displayedPositionMs,
    )?.location.locationKey;
    final maxWidth = playback.distractionFreeMode ? 720.0 : 760.0;
    final accessibilityAnnouncement = _readerAccessibilityAnnouncement(
      bundle,
      playback.displayedPositionMs,
    );

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReaderPageHeader(bundle: bundle, playback: playback),
                    const SizedBox(height: 22),
                    for (final section in bundle.readerModel.sections) ...[
                      if (section.title != null)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: 20 * playback.paragraphSpacing,
                          ),
                          child: Semantics(
                            header: true,
                            label: 'Section ${section.title}',
                            child: Text(
                              section.title!,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                        ),
                      for (final paragraph in section.paragraphs)
                        Padding(
                          key: _paragraphKeys.putIfAbsent(
                            '${section.id}:${paragraph.index}',
                            GlobalKey.new,
                          ),
                          padding: EdgeInsets.only(
                            bottom: 18 * playback.paragraphSpacing,
                          ),
                          child: _ParagraphBlock(
                            section: section,
                            paragraph: paragraph,
                            activeLocationKey: activeLocationKey,
                            syncIndex: syncIndex,
                            onTokenTap: (token) {
                              if (token != null) {
                                widget.onTokenTap(token);
                              }
                            },
                            fontScale: playback.fontScale,
                            lineHeight: playback.lineHeight,
                            paragraphSpacing: playback.paragraphSpacing,
                            highContrastMode: playback.highContrastMode,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: accessibilityAnnouncement,
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
      ],
    );
  }

  static String? _paragraphKeyForLocation(String? locationKey) {
    if (locationKey == null) {
      return null;
    }
    final parts = locationKey.split(':');
    if (parts.length != 3) {
      return null;
    }
    return '${parts[0]}:${parts[1]}';
  }
}

class _ReaderLoadingView extends StatelessWidget {
  const _ReaderLoadingView({required this.settings});

  final RuntimeConnectionSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
        decoration: BoxDecoration(
          color: palette.backgroundElevated,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text('Preparing your book', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                'We are opening ${settings.normalizedProjectId} from ${settings.shortHost} and checking whether synced audio is ready.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Container(
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
                    Text(
                      'What happens next',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    const _StatusStep(
                      step: '1',
                      title: 'Open your book',
                      detail: 'Load the reader copy and progress state.',
                    ),
                    const SizedBox(height: 10),
                    const _StatusStep(
                      step: '2',
                      title: 'Attach sync data',
                      detail: 'Check whether word timings are ready.',
                    ),
                    const SizedBox(height: 10),
                    const _StatusStep(
                      step: '3',
                      title: 'Unlock playback',
                      detail: 'Use local or streamed audio when available.',
                    ),
                  ],
                ),
              ),
              if (_connectionHint(settings) case final hint?) ...[
                const SizedBox(height: 16),
                _ConnectionHintBanner(message: hint),
              ],
              const SizedBox(height: 14),
              Text(
                'If you just imported this book, it is normal for the first open to take a moment.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({
    required this.message,
    required this.settings,
    required this.onRetry,
    required this.onOpenConnectionSettings,
  });

  final String message;
  final RuntimeConnectionSettings settings;
  final VoidCallback onRetry;
  final VoidCallback onOpenConnectionSettings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
        decoration: BoxDecoration(
          color: palette.backgroundElevated,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Reader failed to load',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Current target: ${settings.shortHost} • ${settings.normalizedProjectId}',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: palette.backgroundBase,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.borderSubtle),
              ),
              child: Text(message),
            ),
            const SizedBox(height: 16),
            Text(
              _errorHelp(settings),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            if (_connectionHint(settings) case final hint?) ...[
              const SizedBox(height: 16),
              _ConnectionHintBanner(message: hint),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                FilledButton.tonal(
                  onPressed: onOpenConnectionSettings,
                  child: const Text('Open Connection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHintBanner extends StatelessWidget {
  const _ConnectionHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ReaderPreferencesCard extends StatelessWidget {
  const _ReaderPreferencesCard({
    required this.playback,
    required this.onSetFontScale,
    required this.onSetLineHeight,
    required this.onSetParagraphSpacing,
    required this.onToggleFollowPlayback,
    required this.onToggleDistractionFree,
    required this.onToggleHighContrast,
    required this.onToggleLeftHanded,
  });

  final ReaderPlaybackState playback;
  final ValueChanged<double> onSetFontScale;
  final ValueChanged<double> onSetLineHeight;
  final ValueChanged<double> onSetParagraphSpacing;
  final VoidCallback onToggleFollowPlayback;
  final VoidCallback onToggleDistractionFree;
  final VoidCallback onToggleHighContrast;
  final VoidCallback onToggleLeftHanded;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reading Surface',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          _PreferenceRow(
            label: 'Text size',
            value: _PreferenceChipGroup<double>(
              current: playback.fontScale,
              options: const [0.92, 1.0, 1.12, 1.24],
              labelFor: (value) => switch (value) {
                < 1.0 => 'Compact',
                1.0 => 'Standard',
                < 1.2 => 'Large',
                _ => 'XL',
              },
              onSelected: onSetFontScale,
            ),
          ),
          const SizedBox(height: 10),
          _PreferenceRow(
            label: 'Line height',
            value: _PreferenceChipGroup<double>(
              current: playback.lineHeight,
              options: const [1.4, 1.55, 1.7],
              labelFor: (value) => switch (value) {
                < 1.5 => 'Tight',
                < 1.6 => 'Balanced',
                _ => 'Open',
              },
              onSelected: onSetLineHeight,
            ),
          ),
          const SizedBox(height: 10),
          _PreferenceRow(
            label: 'Paragraph space',
            value: _PreferenceChipGroup<double>(
              current: playback.paragraphSpacing,
              options: const [0.85, 1.0, 1.25],
              labelFor: (value) => switch (value) {
                < 0.9 => 'Tight',
                < 1.1 => 'Standard',
                _ => 'Spacious',
              },
              onSelected: onSetParagraphSpacing,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            value: playback.followPlayback,
            contentPadding: EdgeInsets.zero,
            title: const Text('Follow playback'),
            subtitle: const Text(
              'Keep the active reading region in view while audio advances.',
            ),
            onChanged: (_) => onToggleFollowPlayback(),
          ),
          SwitchListTile.adaptive(
            value: playback.distractionFreeMode,
            contentPadding: EdgeInsets.zero,
            title: const Text('Focus mode'),
            subtitle: const Text(
              'Hide the full reader dock and keep a minimal floating playback HUD.',
            ),
            onChanged: (_) => onToggleDistractionFree(),
          ),
          SwitchListTile.adaptive(
            value: playback.highContrastMode,
            contentPadding: EdgeInsets.zero,
            title: const Text('Enhanced contrast'),
            subtitle: const Text(
              'Increase contrast and confidence cues for tougher lighting and lower-precision spans.',
            ),
            onChanged: (_) => onToggleHighContrast(),
          ),
          SwitchListTile.adaptive(
            value: playback.leftHandedMode,
            contentPadding: EdgeInsets.zero,
            title: const Text('Left-handed HUD'),
            subtitle: const Text(
              'Pin the floating focus controls to the lower-left corner.',
            ),
            onChanged: (_) => onToggleLeftHanded(),
          ),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        value,
      ],
    );
  }
}

class _PreferenceChipGroup<T extends num> extends StatelessWidget {
  const _PreferenceChipGroup({
    required this.current,
    required this.options,
    required this.labelFor,
    required this.onSelected,
  });

  final T current;
  final List<T> options;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(labelFor(option)),
            selected: option == current,
            onSelected: (_) => onSelected(option),
          ),
      ],
    );
  }
}

class _ReaderFocusOverlay extends StatelessWidget {
  const _ReaderFocusOverlay({
    required this.playback,
    required this.hasPlayableContent,
    required this.onTogglePlayback,
    required this.onToggleDistractionFree,
    required this.onRewind,
    required this.onForward,
  });

  final ReaderPlaybackState playback;
  final bool hasPlayableContent;
  final VoidCallback? onTogglePlayback;
  final VoidCallback onToggleDistractionFree;
  final VoidCallback onRewind;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundElevated.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onRewind,
              icon: const Icon(Icons.replay_10_rounded),
            ),
            IconButton.filled(
              onPressed: hasPlayableContent ? onTogglePlayback : null,
              icon: Icon(
                playback.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            IconButton(
              onPressed: onForward,
              icon: const Icon(Icons.forward_10_rounded),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              onPressed: onToggleDistractionFree,
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('Exit Focus'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookNavigationSheet extends StatefulWidget {
  const _BookNavigationSheet({required this.bundle, required this.onNavigate});

  final ReaderProjectBundle bundle;
  final Future<void> Function(int positionMs) onNavigate;

  @override
  State<_BookNavigationSheet> createState() => _BookNavigationSheetState();
}

class _BookNavigationSheetState extends State<_BookNavigationSheet> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final sectionAnchors = _sectionAnchors(widget.bundle);
    final searchResults = query.isEmpty
        ? const <_SearchResult>[]
        : _searchReaderModel(widget.bundle, query);

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
          Text('Navigate Book', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Jump by section or search the normalized reader text.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search text',
              hintText: 'Find a word or phrase',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (query.isEmpty) ...[
                  Text('Contents', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  for (final anchor in sectionAnchors)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(anchor.label),
                      subtitle: anchor.startMs == null
                          ? const Text('No synced start found yet')
                          : Text(
                              'Starts at ${ReaderScreen._formatMs(anchor.startMs!)}',
                            ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: anchor.startMs == null
                          ? null
                          : () => _jump(anchor.startMs!),
                    ),
                ] else ...[
                  Text('Search Results', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  if (searchResults.isEmpty)
                    const Text('No matching text found in this book.')
                  else
                    for (final result in searchResults)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(result.sectionLabel),
                        subtitle: Text(result.preview),
                        trailing: result.startMs == null
                            ? const Icon(Icons.schedule_rounded)
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: result.startMs == null
                            ? null
                            : () => _jump(result.startMs!),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _jump(int positionMs) async {
    await widget.onNavigate(positionMs);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _SectionAnchor {
  const _SectionAnchor({required this.label, this.startMs});

  final String label;
  final int? startMs;
}

class _SearchResult {
  const _SearchResult({
    required this.sectionLabel,
    required this.preview,
    required this.startMs,
  });

  final String sectionLabel;
  final String preview;
  final int? startMs;
}

List<_SectionAnchor> _sectionAnchors(ReaderProjectBundle bundle) {
  final tokensBySection = <String, SyncToken>{};
  for (final token in bundle.syncArtifact.tokens) {
    tokensBySection.putIfAbsent(token.location.sectionId, () => token);
  }

  return [
    for (final section in bundle.readerModel.sections)
      _SectionAnchor(
        label: section.title ?? 'Section ${section.order + 1}',
        startMs: tokensBySection[section.id]?.startMs,
      ),
  ];
}

List<_SearchResult> _searchReaderModel(
  ReaderProjectBundle bundle,
  String query,
) {
  final firstTokenByParagraph = <String, SyncToken>{};
  for (final token in bundle.syncArtifact.tokens) {
    final key = '${token.location.sectionId}:${token.location.paragraphIndex}';
    firstTokenByParagraph.putIfAbsent(key, () => token);
  }

  final results = <_SearchResult>[];
  for (final section in bundle.readerModel.sections) {
    for (final paragraph in section.paragraphs) {
      final text = paragraph.tokens.map((token) => token.text).join(' ');
      if (!text.toLowerCase().contains(query)) {
        continue;
      }
      final key = '${section.id}:${paragraph.index}';
      results.add(
        _SearchResult(
          sectionLabel: section.title ?? 'Section ${section.order + 1}',
          preview: text,
          startMs: firstTokenByParagraph[key]?.startMs,
        ),
      );
    }
  }
  return results.take(12).toList(growable: false);
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({
    required this.source,
    required this.onRefresh,
    this.message,
  });

  final ReaderContentSource source;
  final VoidCallback onRefresh;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final isFallback =
        source == ReaderContentSource.demoFallback ||
        source == ReaderContentSource.offlineCache;
    final isProblem =
        source == ReaderContentSource.artifactPending ||
        source == ReaderContentSource.projectError;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isFallback
            ? palette.accentSoft
            : isProblem
            ? palette.backgroundElevated
            : palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.backgroundElevated.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _sourceIcon(source),
                  size: 18,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sourceHeadline(source),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message ?? _sourceDetail(source),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_sourceFootnote(source) case final footnote?) ...[
            const SizedBox(height: 10),
            Text(
              footnote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRefresh,
              child: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _sourceIcon(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.api => Icons.check_circle_outline_rounded,
      ReaderContentSource.selectionRequired => Icons.menu_book_rounded,
      ReaderContentSource.offlineCache => Icons.offline_pin_rounded,
      ReaderContentSource.artifactPending => Icons.hourglass_top_rounded,
      ReaderContentSource.projectError => Icons.error_outline_rounded,
      ReaderContentSource.demoFallback => Icons.wifi_off_rounded,
    };
  }

  static String _sourceHeadline(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.api => 'Ready to read',
      ReaderContentSource.selectionRequired => 'Choose a book first',
      ReaderContentSource.offlineCache => 'Offline copy opened',
      ReaderContentSource.artifactPending => 'Your book is still syncing',
      ReaderContentSource.projectError => 'This book needs another sync pass',
      ReaderContentSource.demoFallback => 'Demo book is open for now',
    };
  }

  static String _sourceDetail(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.api =>
        'Everything needed for reading is loaded from your backend.',
      ReaderContentSource.selectionRequired =>
        'Pick a project from Library to bring the reader to life.',
      ReaderContentSource.offlineCache =>
        'You can keep reading from this device even if the backend is offline.',
      ReaderContentSource.artifactPending =>
        'The upload finished, but the reader text or sync timeline is not ready yet.',
      ReaderContentSource.projectError =>
        'The latest artifacts are incomplete, so this screen cannot render the finished book yet.',
      ReaderContentSource.demoFallback =>
        'Connect your own backend to replace the demo content with a real project.',
    };
  }

  static String? _sourceFootnote(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.artifactPending =>
        'You can stay here and refresh, or return from Library after the worker finishes.',
      ReaderContentSource.projectError =>
        'Open the project again after a retry or a fresh alignment run.',
      _ => null,
    };
  }
}

class _JobEventBanner extends StatelessWidget {
  const _JobEventBanner({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final type = event['type'] as String? ?? 'job.progress';
    final payload = (event['payload'] as Map<Object?, Object?>?) ?? const {};
    final stage = payload['stage'] as String? ?? 'unknown';
    final percent = payload['percent'] as int? ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(
        '$type • $stage • $percent%',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _AudioDownloadBanner extends StatelessWidget {
  const _AudioDownloadBanner({
    required this.bundle,
    required this.downloadState,
    required this.onDownload,
    required this.onRemove,
  });

  final ReaderProjectBundle bundle;
  final ReaderAudioDownloadState downloadState;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final message = switch (downloadState.status) {
      ReaderAudioDownloadStatus.downloading =>
        'Downloading audio ${downloadState.completedAssets + 1} of '
            '${downloadState.totalAssets > 0 ? downloadState.totalAssets : bundle.totalAudioAssets} for offline playback...',
      ReaderAudioDownloadStatus.removing =>
        'Removing downloaded audio from this device...',
      ReaderAudioDownloadStatus.failed =>
        downloadState.message ?? 'Audio download failed.',
      _ when bundle.hasCompleteOfflineAudio =>
        'Offline audio is ready on this device.',
      _ when bundle.cachedAudioAssets > 0 =>
        'Partial offline audio: ${bundle.cachedAudioAssets} of ${bundle.totalAudioAssets} files downloaded.',
      _ =>
        'You can start reading now. Download audio when you want full offline playback.',
    };

    final trailingMessage = switch (downloadState.status) {
      ReaderAudioDownloadStatus.succeeded => downloadState.message,
      ReaderAudioDownloadStatus.failed => null,
      ReaderAudioDownloadStatus.downloading =>
        '${downloadState.activeAssetId ?? 'current file'} • ${(downloadState.progress * 100).round()}%',
      _ => null,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(
                label: bundle.hasCompleteOfflineAudio
                    ? 'Offline listening ready'
                    : bundle.cachedAudioAssets > 0
                    ? '${bundle.cachedAudioAssets}/${bundle.totalAudioAssets} files saved'
                    : 'Streaming by default',
              ),
              if (bundle.totalAudioAssets > 0)
                _DiagnosticsChip(
                  label: '${bundle.totalAudioAssets} audio files',
                ),
            ],
          ),
          if (trailingMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              trailingMessage,
              style: theme.textTheme.labelMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          if (downloadState.status ==
              ReaderAudioDownloadStatus.downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: downloadState.progress),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: downloadState.isBusy ? null : onDownload,
                child: Text(
                  bundle.cachedAudioAssets > 0 &&
                          !bundle.hasCompleteOfflineAudio
                      ? 'Download Remaining'
                      : bundle.hasCompleteOfflineAudio
                      ? 'Re-download Audio'
                      : 'Download Audio',
                ),
              ),
              if (bundle.cachedAudioAssets > 0 ||
                  bundle.hasCompleteOfflineAudio)
                TextButton(
                  onPressed: downloadState.isBusy ? null : onRemove,
                  child: const Text('Remove Local Copy'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentWindowBanner extends StatelessWidget {
  const _ContentWindowBanner({
    required this.syncArtifact,
    required this.currentPositionMs,
    required this.onStartBook,
    this.onJumpToOutro,
  });

  final SyncArtifact syncArtifact;
  final int currentPositionMs;
  final VoidCallback onStartBook;
  final VoidCallback? onJumpToOutro;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final remainingMs = syncArtifact.contentStartMs - currentPositionMs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Audiobook intro detected before the book starts at '
              '${ReaderScreen._formatMs(syncArtifact.contentStartMs)}'
              ' (${ReaderScreen._formatMs(remainingMs)} away).',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(onPressed: onStartBook, child: const Text('Start Book')),
          if (onJumpToOutro != null)
            TextButton(onPressed: onJumpToOutro, child: const Text('Outro')),
        ],
      ),
    );
  }
}

class _StatusStep extends StatelessWidget {
  const _StatusStep({
    required this.step,
    required this.title,
    required this.detail,
  });

  final String step;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Text(step, style: theme.textTheme.labelLarge),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderDiagnosticsBanner extends StatelessWidget {
  const _ReaderDiagnosticsBanner({
    required this.bundle,
    required this.playback,
  });

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_headline(bundle, playback), style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            _detail(bundle, playback),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(label: _artifactSourceLabel(bundle.source)),
              _DiagnosticsChip(
                label:
                    'Local audio ${bundle.cachedAudioAssets}/${bundle.totalAudioAssets}',
              ),
              if (bundle.streamingAudioAssets > 0)
                _DiagnosticsChip(
                  label: 'Streaming ${bundle.streamingAudioAssets}',
                ),
              _DiagnosticsChip(
                label: playback.usesNativeAudio
                    ? 'Native audio active'
                    : 'Text timeline mode',
              ),
              if (bundle.audioCachedAt != null)
                _DiagnosticsChip(
                  label:
                      'Audio cache ${ReaderScreen.formatTimestamp(bundle.audioCachedAt!)}',
                ),
              if (bundle.cachedAt != null)
                _DiagnosticsChip(
                  label:
                      'Artifacts cache ${ReaderScreen.formatTimestamp(bundle.cachedAt!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _headline(
    ReaderProjectBundle bundle,
    ReaderPlaybackState playback,
  ) {
    return switch (bundle.playbackSourceMode(
      usesNativeAudio: playback.usesNativeAudio,
    )) {
      ReaderPlaybackSourceMode.offlineCached =>
        'Playback source: local cached audio.',
      ReaderPlaybackSourceMode.mixed =>
        'Playback source: mixed local and backend audio.',
      ReaderPlaybackSourceMode.remoteStreaming =>
        'Playback source: streaming from the backend.',
      ReaderPlaybackSourceMode.textOnly =>
        bundle.hasAnyAudio
            ? 'Playback source: text timeline only.'
            : 'Playback source: no audio source available.',
    };
  }

  static String _detail(
    ReaderProjectBundle bundle,
    ReaderPlaybackState playback,
  ) {
    final sourceMode = bundle.playbackSourceMode(
      usesNativeAudio: playback.usesNativeAudio,
    );
    if (sourceMode == ReaderPlaybackSourceMode.offlineCached) {
      return 'All project audio is downloaded on this device and native playback can run without backend access.';
    }
    if (sourceMode == ReaderPlaybackSourceMode.mixed) {
      return '${bundle.cachedAudioAssets} of ${bundle.totalAudioAssets} audio files are local. The rest will stream from the backend when needed.';
    }
    if (sourceMode == ReaderPlaybackSourceMode.remoteStreaming) {
      return 'Audio will stream from the backend. Download it on this device to enable offline playback.';
    }
    if (bundle.hasAnyAudio) {
      return playback.usesNativeAudio
          ? 'Native audio is active for the currently available files.'
          : 'This project has audio metadata, but no playable local or remote source is active right now.';
    }
    return 'Word highlighting follows the sync timeline, but there is no playable audiobook source for this project yet.';
  }

  static String _artifactSourceLabel(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.selectionRequired => 'Artifacts: choose project',
      ReaderContentSource.api => 'Artifacts: live API',
      ReaderContentSource.offlineCache => 'Artifacts: offline cache',
      ReaderContentSource.artifactPending => 'Artifacts: pending',
      ReaderContentSource.projectError => 'Artifacts: incomplete',
      ReaderContentSource.demoFallback => 'Artifacts: demo data',
    };
  }
}

class _ReadingProgressBanner extends StatelessWidget {
  const _ReadingProgressBanner({
    required this.bundle,
    required this.currentPositionMs,
  });

  final ReaderProjectBundle bundle;
  final int currentPositionMs;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final progress = _readingProgress(bundle, currentPositionMs);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reading Progress', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            progress.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(label: progress.bookLabel),
              if (progress.sectionLabel != null)
                _DiagnosticsChip(label: progress.sectionLabel!),
              _DiagnosticsChip(label: progress.remainingLabel),
              if (progress.sectionTitle != null)
                _DiagnosticsChip(label: progress.sectionTitle!),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudyWorkflowCard extends StatelessWidget {
  const _StudyWorkflowCard({
    required this.entries,
    required this.onAddBookmark,
    required this.onAddHighlight,
    required this.onAddNote,
    required this.onOpenReviewTray,
  });

  final List<ReaderStudyEntry> entries;
  final VoidCallback? onAddBookmark;
  final VoidCallback? onAddHighlight;
  final VoidCallback? onAddNote;
  final VoidCallback? onOpenReviewTray;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final bookmarkCount = entries
        .where((entry) => entry.type == ReaderStudyEntryType.bookmark)
        .length;
    final highlightCount = entries
        .where((entry) => entry.type == ReaderStudyEntryType.highlight)
        .length;
    final noteCount = entries
        .where((entry) => entry.type == ReaderStudyEntryType.note)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Study Workflow', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            'Save the current sync position as a bookmark, highlight the active phrase, or attach a note for later review.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(label: 'Bookmarks $bookmarkCount'),
              _DiagnosticsChip(label: 'Highlights $highlightCount'),
              _DiagnosticsChip(label: 'Notes $noteCount'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: onAddBookmark,
                child: const Text('Save Bookmark'),
              ),
              FilledButton.tonal(
                onPressed: onAddHighlight,
                child: const Text('Highlight Span'),
              ),
              FilledButton.tonal(
                onPressed: onAddNote,
                child: const Text('Add Note'),
              ),
              TextButton(
                onPressed: onOpenReviewTray,
                child: const Text('Review Tray'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaybackPowerCard extends StatelessWidget {
  const _PlaybackPowerCard({
    required this.playback,
    required this.onApplyPreset,
    required this.onMarkLoopStart,
    required this.onMarkLoopEnd,
    required this.onClearLoop,
  });

  final ReaderPlaybackState playback;
  final Future<void> Function(ReaderPlaybackPreset preset) onApplyPreset;
  final VoidCallback onMarkLoopStart;
  final VoidCallback onMarkLoopEnd;
  final VoidCallback onClearLoop;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Playback Modes', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            'Switch between study, commute, and bedtime playback, or loop a precise A/B span.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: 'Study',
                isActive: playback.playbackPreset == ReaderPlaybackPreset.study,
                onTap: () => onApplyPreset(ReaderPlaybackPreset.study),
              ),
              _PresetChip(
                label: 'Commute',
                isActive:
                    playback.playbackPreset == ReaderPlaybackPreset.commute,
                onTap: () => onApplyPreset(ReaderPlaybackPreset.commute),
              ),
              _PresetChip(
                label: 'Bedtime',
                isActive:
                    playback.playbackPreset == ReaderPlaybackPreset.bedtime,
                onTap: () => onApplyPreset(ReaderPlaybackPreset.bedtime),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: onMarkLoopStart,
                child: Text(
                  playback.loopStartMs == null
                      ? 'Set Loop A'
                      : 'Loop A ${ReaderScreen._formatMs(playback.loopStartMs!)}',
                ),
              ),
              FilledButton.tonal(
                onPressed: onMarkLoopEnd,
                child: Text(
                  playback.loopEndMs == null
                      ? 'Set Loop B'
                      : 'Loop B ${ReaderScreen._formatMs(playback.loopEndMs!)}',
                ),
              ),
              if (playback.hasLoop)
                TextButton(
                  onPressed: onClearLoop,
                  child: const Text('Clear Loop'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      onSelected: (_) => onTap(),
    );
  }
}

class _DiagnosticsChip extends StatelessWidget {
  const _DiagnosticsChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _PlaybackStatusBanner extends StatelessWidget {
  const _PlaybackStatusBanner({
    required this.playback,
    required this.currentPositionMs,
  });

  final ReaderPlaybackState playback;
  final int currentPositionMs;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final phase = _phaseLabel(playback, currentPositionMs);
    final positionLabel = playback.isScrubbing ? 'Scrubbing' : 'Playback';
    final semanticsLabel =
        '$positionLabel. $phase. ${playback.isPlaying ? 'Playing' : 'Paused'}. '
        '${playback.usesNativeAudio ? 'Native audio active.' : 'Text timeline active.'}';

    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.backgroundBase,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(
              '$positionLabel • $phase',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              '${playback.isPlaying ? 'Playing' : 'Paused'} • '
              '${playback.usesNativeAudio ? 'Native audio' : 'Text timeline'}',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(
    ReaderPlaybackState playback,
    int currentPositionMs,
  ) {
    if (playback.hasLeadingMatter &&
        currentPositionMs < playback.contentStartMs) {
      return 'Intro before book';
    }
    if (playback.hasTrailingMatter &&
        currentPositionMs > playback.contentEndMs) {
      return 'Outro after book';
    }
    if (playback.totalDurationMs == 0) {
      return 'No timeline';
    }
    return 'Inside book content';
  }
}

class _ContentWindowRow extends StatelessWidget {
  const _ContentWindowRow({
    required this.playback,
    required this.currentPositionMs,
    required this.onJumpToStart,
    required this.onJumpToEnd,
  });

  final ReaderPlaybackState playback;
  final int currentPositionMs;
  final VoidCallback? onJumpToStart;
  final VoidCallback? onJumpToEnd;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (onJumpToStart != null) {
      items.add(
        _WindowChip(
          label:
              'Book Start ${ReaderScreen._formatMs(playback.contentStartMs)}',
          isActive:
              currentPositionMs >= playback.contentStartMs &&
              currentPositionMs <= playback.contentEndMs,
          onTap: onJumpToStart!,
        ),
      );
    }

    if (onJumpToEnd != null) {
      items.add(
        _WindowChip(
          label: 'Book End ${ReaderScreen._formatMs(playback.contentEndMs)}',
          isActive:
              playback.hasTrailingMatter &&
              currentPositionMs >= playback.contentEndMs,
          onTap: onJumpToEnd!,
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 8, runSpacing: 8, children: items),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return ActionChip(
      label: Text(label),
      avatar: Icon(
        isActive ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: 18,
        color: isActive ? palette.accentPrimary : palette.textMuted,
      ),
      onPressed: onTap,
      side: BorderSide(color: palette.borderSubtle),
      backgroundColor: isActive ? palette.accentSoft : palette.backgroundBase,
    );
  }
}

class _GapStatusBanner extends StatelessWidget {
  const _GapStatusBanner({required this.gap});

  final SyncGap? gap;

  @override
  Widget build(BuildContext context) {
    if (gap == null) {
      return const SizedBox.shrink();
    }

    final palette = ReaderPalette.of(context);
    final message = switch (gap!.reason) {
      'audiobook_front_matter' =>
        'This portion is audiobook intro and is outside the EPUB text.',
      'audiobook_end_matter' =>
        'This portion is audiobook outro and is outside the EPUB text.',
      _ => 'Playback is in an unmatched narration span.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(message, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SyncIntelligenceBanner extends StatelessWidget {
  const _SyncIntelligenceBanner({
    required this.bundle,
    required this.currentPositionMs,
    required this.onOpenGapInspector,
    required this.onJumpToNextConfidentSpan,
  });

  final ReaderProjectBundle bundle;
  final int currentPositionMs;
  final VoidCallback? onOpenGapInspector;
  final VoidCallback? onJumpToNextConfidentSpan;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final gap = bundle.syncArtifact.activeGapAt(currentPositionMs);
    final token = _activeTokenAtPosition(
      bundle.syncArtifact,
      currentPositionMs,
    );
    final confidence = token?.confidence ?? 1.0;
    final nextStrongSpan = _nextConfidentSpanStartMs(
      bundle.syncArtifact,
      currentPositionMs,
    );

    final headline = gap != null
        ? switch (gap.reason) {
            'audiobook_front_matter' =>
              'Audiobook intro sits outside the book.',
            'audiobook_end_matter' => 'Audiobook outro sits outside the book.',
            _ => 'Narration drift detected in this span.',
          }
        : confidence < 0.72
        ? 'Weak alignment around the current phrase.'
        : confidence < 0.86
        ? 'Alignment is usable but a little soft here.'
        : 'Alignment looks confident in the current reading span.';

    final detail = gap != null
        ? 'This gap covers ${ReaderScreen._formatMs(gap.startMs)} to ${ReaderScreen._formatMs(gap.endMs)} and contains ${gap.wordCount} unmatched transcript words.'
        : token == null
        ? 'No synced token is active at this exact position yet.'
        : 'Current token confidence: ${(confidence * 100).round()}% at ${ReaderScreen._formatMs(token.startMs)}.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: gap != null ? palette.accentSoft : palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (gap != null)
                _DiagnosticsChip(label: _gapReasonLabel(gap.reason)),
              if (token != null)
                _DiagnosticsChip(
                  label: 'Confidence ${(confidence * 100).round()}%',
                ),
              if (token != null && token.confidence < 0.86)
                _DiagnosticsChip(label: 'Hint: verify by ear here'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (nextStrongSpan != null)
                FilledButton.tonal(
                  onPressed: onJumpToNextConfidentSpan,
                  child: const Text('Next Strong Span'),
                ),
              if (onOpenGapInspector != null)
                TextButton(
                  onPressed: onOpenGapInspector,
                  child: const Text('Inspect Gaps'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({
    required this.section,
    required this.paragraph,
    required this.activeLocationKey,
    required this.syncIndex,
    required this.onTokenTap,
    required this.fontScale,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.highContrastMode,
  });

  final ReaderSection section;
  final ReaderParagraph paragraph;
  final String? activeLocationKey;
  final Map<String, SyncToken> syncIndex;
  final ValueChanged<SyncToken?> onTokenTap;
  final double fontScale;
  final double lineHeight;
  final double paragraphSpacing;
  final bool highContrastMode;

  @override
  Widget build(BuildContext context) {
    final paragraphLabel = paragraph.tokens
        .map((token) => token.text)
        .join(' ');
    final isActiveParagraph =
        activeLocationKey != null &&
        activeLocationKey!.startsWith('${section.id}:${paragraph.index}:');
    return Semantics(
      container: true,
      label: 'Paragraph ${paragraph.index + 1}. $paragraphLabel',
      hint: isActiveParagraph
          ? 'Contains the current reading phrase.'
          : 'Double tap a word to jump playback.',
      child: Text.rich(
        TextSpan(
          children: [
            for (var index = 0; index < paragraph.tokens.length; index++)
              _buildTokenSpan(
                context,
                token: paragraph.tokens[index],
                syncToken:
                    syncIndex['${section.id}:${paragraph.index}:${paragraph.tokens[index].index}'],
                isActive:
                    activeLocationKey ==
                    '${section.id}:${paragraph.index}:${paragraph.tokens[index].index}',
                isLast: index == paragraph.tokens.length - 1,
              ),
          ],
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize:
              (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 22) *
              fontScale,
          height: lineHeight * 1.03,
        ),
      ),
    );
  }

  InlineSpan _buildTokenSpan(
    BuildContext context, {
    required ReaderToken token,
    required SyncToken? syncToken,
    required bool isActive,
    required bool isLast,
  }) {
    final palette = ReaderPalette.of(context);
    final confidence = syncToken?.confidence ?? 1.0;
    final isSoftConfidence = confidence < 0.86;
    final isWeakConfidence = confidence < 0.72;
    final foregroundColor = highContrastMode
        ? isActive
              ? palette.backgroundBase
              : isWeakConfidence
              ? palette.textPrimary
              : palette.textPrimary
        : isActive
        ? palette.accentPrimary
        : isWeakConfidence
        ? palette.textMuted
        : palette.textPrimary;
    final backgroundColor = highContrastMode
        ? isActive
              ? palette.textPrimary
              : isWeakConfidence
              ? palette.accentSoft.withValues(alpha: 0.72)
              : palette.backgroundBase
        : isActive
        ? palette.accentSoft
        : isWeakConfidence
        ? palette.accentSoft.withValues(alpha: 0.28)
        : Colors.transparent;
    return TextSpan(
      text: '${token.text}${isLast ? '' : ' '}',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize:
            (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 22) * fontScale,
        height: lineHeight * 1.03,
        color: foregroundColor,
        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
        fontStyle: isWeakConfidence ? FontStyle.italic : FontStyle.normal,
        backgroundColor: backgroundColor,
        decoration: isActive || isSoftConfidence
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: isActive ? palette.accentPrimary : palette.textMuted,
        decorationStyle: isActive
            ? TextDecorationStyle.solid
            : TextDecorationStyle.dotted,
      ),
      recognizer: syncToken == null
          ? null
          : (TapGestureRecognizer()..onTap = () => onTokenTap(syncToken)),
    );
  }
}

class _GapInspectorSheet extends StatelessWidget {
  const _GapInspectorSheet({
    required this.bundle,
    required this.currentPositionMs,
    required this.onNavigate,
  });

  final ReaderProjectBundle bundle;
  final int currentPositionMs;
  final Future<void> Function(int positionMs) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeGap = bundle.syncArtifact.activeGapAt(currentPositionMs);

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
          Text('Sync Inspector', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Review weak or unmatched audiobook spans without leaving the reader.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (bundle.syncArtifact.gaps.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('No gap metadata for this project.'),
                  )
                else
                  for (final gap in bundle.syncArtifact.gaps)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        activeGap == gap
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                      ),
                      title: Text(_gapReasonLabel(gap.reason)),
                      subtitle: Text(
                        '${ReaderScreen._formatMs(gap.startMs)} → ${ReaderScreen._formatMs(gap.endMs)} • ${gap.wordCount} words',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await onNavigate(gap.endMs);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteComposerSheet extends StatefulWidget {
  const _NoteComposerSheet({required this.onSave});

  final Future<void> Function(String note) onSave;

  @override
  State<_NoteComposerSheet> createState() => _NoteComposerSheetState();
}

class _NoteComposerSheetState extends State<_NoteComposerSheet> {
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Add Note', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Attach a short note to the current sync position on this device.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Why did this span matter?',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save Note'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final note = _controller.text.trim();
    if (note.isEmpty) {
      return;
    }
    setState(() => _isSaving = true);
    await widget.onSave(note);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _ReviewTraySheet extends StatelessWidget {
  const _ReviewTraySheet({
    required this.entries,
    required this.onNavigate,
    required this.onRemove,
  });

  final List<ReaderStudyEntry> entries;
  final Future<void> Function(int positionMs) onNavigate;
  final Future<void> Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
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
          Text('Review Tray', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Revisit saved bookmarks, highlights, and notes from this device.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: entries.isEmpty
                ? const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('No saved study items yet.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in entries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            entry.sectionTitle ?? _studyTypeLabel(entry.type),
                          ),
                          subtitle: Text(
                            '${_studyTypeLabel(entry.type)} • ${ReaderScreen._formatMs(entry.positionMs)}\n${entry.excerpt}${entry.note == null ? '' : '\n${entry.note}'}',
                          ),
                          isThreeLine: entry.note != null,
                          trailing: IconButton(
                            onPressed: () => onRemove(entry.id),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                          onTap: () async {
                            await onNavigate(entry.positionMs);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReadingProgressSnapshot {
  const _ReadingProgressSnapshot({
    required this.summary,
    required this.bookLabel,
    required this.remainingLabel,
    this.sectionLabel,
    this.sectionTitle,
  });

  final String summary;
  final String bookLabel;
  final String remainingLabel;
  final String? sectionLabel;
  final String? sectionTitle;
}

_ReadingProgressSnapshot _readingProgress(
  ReaderProjectBundle bundle,
  int currentPositionMs,
) {
  final syncArtifact = bundle.syncArtifact;
  final activeToken = _activeTokenAtPosition(syncArtifact, currentPositionMs);
  final contentStart = syncArtifact.contentStartMs;
  final contentEnd = syncArtifact.contentEndMs > contentStart
      ? syncArtifact.contentEndMs
      : syncArtifact.totalDurationMs;
  final clampedPosition = currentPositionMs.clamp(
    contentStart,
    contentEnd > 0 ? contentEnd : currentPositionMs,
  );
  final contentSpan = (contentEnd - contentStart).clamp(1, 1 << 30);
  final bookProgress = (((clampedPosition - contentStart) / contentSpan) * 100)
      .clamp(0.0, 100.0);
  final remainingMs = (contentEnd - clampedPosition).clamp(0, contentEnd);

  String? sectionLabel;
  String? sectionTitle;
  if (activeToken != null) {
    ReaderSection? section;
    for (final candidate in bundle.readerModel.sections) {
      if (candidate.id == activeToken.location.sectionId) {
        section = candidate;
        break;
      }
    }
    final sectionTokens = bundle.syncArtifact.tokens
        .where(
          (token) => token.location.sectionId == activeToken.location.sectionId,
        )
        .toList(growable: false);
    if (sectionTokens.isNotEmpty) {
      final sectionStart = sectionTokens.first.startMs;
      final sectionEnd = sectionTokens.last.endMs > sectionStart
          ? sectionTokens.last.endMs
          : sectionStart + 1;
      final sectionProgress =
          (((currentPositionMs.clamp(sectionStart, sectionEnd) - sectionStart) /
                      (sectionEnd - sectionStart)) *
                  100)
              .clamp(0.0, 100.0);
      sectionLabel = 'Section ${sectionProgress.round()}%';
      sectionTitle = section?.title;
    }
  }

  return _ReadingProgressSnapshot(
    summary:
        'Book ${bookProgress.round()}% complete with ${ReaderScreen._formatMs(remainingMs)} left in synced content.',
    bookLabel: 'Book ${bookProgress.round()}%',
    sectionLabel: sectionLabel,
    remainingLabel: '${ReaderScreen._formatMs(remainingMs)} left',
    sectionTitle: sectionTitle,
  );
}

SyncToken? _activeTokenAtPosition(SyncArtifact artifact, int positionMs) {
  for (final token in artifact.tokens) {
    if (positionMs >= token.startMs && positionMs < token.endMs) {
      return token;
    }
  }
  if (artifact.tokens.isNotEmpty && positionMs >= artifact.tokens.last.endMs) {
    return artifact.tokens.last;
  }
  return null;
}

int? _nextConfidentSpanStartMs(
  SyncArtifact artifact,
  int currentPositionMs, {
  double minConfidence = 0.88,
}) {
  for (final token in artifact.tokens) {
    if (token.startMs <= currentPositionMs + 250) {
      continue;
    }
    if (token.confidence >= minConfidence) {
      return token.startMs;
    }
  }
  return null;
}

String _readerAccessibilityAnnouncement(
  ReaderProjectBundle bundle,
  int currentPositionMs,
) {
  final progress = _readingProgress(bundle, currentPositionMs);
  final gap = bundle.syncArtifact.activeGapAt(currentPositionMs);
  if (gap != null) {
    return 'Reader update. ${_gapReasonAccessibilityLabel(gap.reason)}. ${progress.summary}';
  }

  final activeToken = _activeTokenAtPosition(
    bundle.syncArtifact,
    currentPositionMs,
  );
  if (activeToken == null) {
    return 'Reader update. No synced phrase is active. ${progress.summary}';
  }

  ReaderSection? section;
  for (final candidate in bundle.readerModel.sections) {
    if (candidate.id == activeToken.location.sectionId) {
      section = candidate;
      break;
    }
  }
  final phrase = _phraseExcerptForToken(bundle, activeToken);
  final confidence = (activeToken.confidence * 100).round();
  final sectionLabel = section?.title == null
      ? ''
      : ' Section ${section!.title}.';

  return 'Current reading phrase.$sectionLabel $phrase Confidence $confidence percent. ${progress.summary}';
}

String _phraseExcerptForToken(
  ReaderProjectBundle bundle,
  SyncToken activeToken,
) {
  ReaderParagraph? paragraph;
  for (final section in bundle.readerModel.sections) {
    if (section.id != activeToken.location.sectionId) {
      continue;
    }
    for (final candidate in section.paragraphs) {
      if (candidate.index == activeToken.location.paragraphIndex) {
        paragraph = candidate;
        break;
      }
    }
    if (paragraph != null) {
      break;
    }
  }

  if (paragraph == null || paragraph.tokens.isEmpty) {
    return activeToken.text;
  }

  final centerIndex = activeToken.location.tokenIndex;
  final start = (centerIndex - 3).clamp(0, paragraph.tokens.length - 1);
  final end = (centerIndex + 3).clamp(start, paragraph.tokens.length - 1);
  return paragraph.tokens
      .sublist(start, end + 1)
      .map((token) => token.text)
      .join(' ');
}

String _gapReasonLabel(String reason) {
  return switch (reason) {
    'audiobook_front_matter' => 'Audiobook intro',
    'audiobook_end_matter' => 'Audiobook outro',
    _ => 'Narration mismatch',
  };
}

String _gapReasonAccessibilityLabel(String reason) {
  return switch (reason) {
    'audiobook_front_matter' => 'Audiobook introduction outside the book text',
    'audiobook_end_matter' => 'Audiobook ending outside the book text',
    _ => 'Narration mismatch span',
  };
}

Future<void> _showReviewTraySheet(
  BuildContext context,
  List<ReaderStudyEntry> entries,
  Future<void> Function(int positionMs) onNavigate,
  Future<void> Function(String id) onRemove,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _ReviewTraySheet(
      entries: entries,
      onNavigate: onNavigate,
      onRemove: onRemove,
    ),
  );
}

ReaderStudyEntryDraft _studyDraftForPosition(
  ReaderProjectBundle bundle,
  int positionMs,
  ReaderStudyEntryType type, {
  String? note,
}) {
  final activeToken = _activeTokenAtPosition(bundle.syncArtifact, positionMs);
  ReaderSection? section;
  if (activeToken != null) {
    for (final candidate in bundle.readerModel.sections) {
      if (candidate.id == activeToken.location.sectionId) {
        section = candidate;
        break;
      }
    }
  }
  final excerpt = _studyExcerptForPosition(bundle, activeToken);
  return ReaderStudyEntryDraft(
    type: type,
    positionMs: activeToken?.startMs ?? positionMs,
    excerpt: excerpt,
    sectionId: activeToken?.location.sectionId,
    sectionTitle: section?.title,
    note: note,
  );
}

String _studyExcerptForPosition(
  ReaderProjectBundle bundle,
  SyncToken? activeToken,
) {
  if (activeToken == null) {
    return bundle.readerModel.title;
  }

  for (final section in bundle.readerModel.sections) {
    if (section.id != activeToken.location.sectionId) {
      continue;
    }
    for (final paragraph in section.paragraphs) {
      if (paragraph.index != activeToken.location.paragraphIndex) {
        continue;
      }
      final text = paragraph.tokens.map((token) => token.text).join(' ').trim();
      if (text.length <= 132) {
        return text;
      }
      return '${text.substring(0, 129)}...';
    }
  }

  return activeToken.text;
}

String _studyTypeLabel(ReaderStudyEntryType type) {
  return switch (type) {
    ReaderStudyEntryType.bookmark => 'Bookmark',
    ReaderStudyEntryType.highlight => 'Highlight',
    ReaderStudyEntryType.note => 'Note',
  };
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip();

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Speed'),
            SizedBox(width: 6),
            Icon(Icons.tune_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
