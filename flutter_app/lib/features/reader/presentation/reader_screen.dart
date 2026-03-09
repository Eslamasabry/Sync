import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(readerProjectProvider);
    final bundle = project.asData?.value;
    final playback = ref.watch(readerPlaybackProvider);
    final controller = ref.read(readerPlaybackProvider.notifier);
    final latestEvent = ref.watch(latestProjectEventProvider);
    final palette = ReaderPalette.of(context);
    final currentPositionMs = playback.displayedPositionMs;

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

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.backgroundBase, palette.backgroundElevated],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sync',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          project.when(
                            data: (bundle) => Text(
                              bundle.readerModel.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: palette.textMuted),
                            ),
                            loading: () => Text(
                              'Loading project',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: palette.textMuted),
                            ),
                            error: (_, _) => Text(
                              'Project unavailable',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: palette.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: controller.toggleTheme,
                      icon: Icon(
                        playback.themeMode == ThemeMode.light
                            ? Icons.nightlight_round
                            : Icons.wb_sunny_outlined,
                      ),
                      label: Text(
                        playback.themeMode == ThemeMode.light
                            ? 'Night'
                            : 'Paper',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: project.when(
                  data: (bundle) => _ReaderLoadedView(
                    bundle: bundle,
                    playback: playback,
                    onTokenTap: (token) => controller.seekTo(token.startMs),
                  ),
                  loading: () => const _ReaderLoadingView(),
                  error: (error, _) => _ReaderErrorView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(readerProjectProvider),
                  ),
                ),
              ),
              SizedBox(
                height: bundle != null ? 220 : 180,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Card(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      child: Column(
                        children: [
                          if (bundle != null)
                            _SourceBanner(
                              source: bundle.source,
                              message: bundle.statusMessage,
                              onRefresh: () =>
                                  ref.invalidate(readerProjectProvider),
                            ),
                          if (bundle != null) const SizedBox(height: 12),
                          if (bundle != null &&
                              bundle.syncArtifact.hasLeadingMatter &&
                              currentPositionMs <
                                  bundle.syncArtifact.contentStartMs) ...[
                            _ContentWindowBanner(
                              syncArtifact: bundle.syncArtifact,
                              currentPositionMs: currentPositionMs,
                              onStartBook: controller.seekToContentStart,
                              onJumpToOutro:
                                  bundle.syncArtifact.hasTrailingMatter
                                  ? controller.seekToContentEnd
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (latestEvent != null)
                            _JobEventBanner(event: latestEvent),
                          if (latestEvent != null) const SizedBox(height: 12),
                          if (bundle != null) ...[
                            _GapStatusBanner(
                              gap: bundle.syncArtifact.activeGapAt(
                                currentPositionMs,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _PlaybackStatusBanner(
                              playback: playback,
                              currentPositionMs: currentPositionMs,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatMs(currentPositionMs),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              if (bundle != null)
                                Text(
                                  _formatMs(
                                    bundle.syncArtifact.totalDurationMs,
                                  ),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: palette.textMuted),
                                ),
                              if (bundle != null) const SizedBox(width: 12),
                              Text(
                                '${playback.speed.toStringAsFixed(2)}x',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: palette.textMuted),
                              ),
                            ],
                          ),
                          Slider(
                            value: currentPositionMs
                                .clamp(
                                  0,
                                  bundle?.syncArtifact.totalDurationMs ?? 0,
                                )
                                .toDouble(),
                            max: (bundle?.syncArtifact.totalDurationMs ?? 0) > 0
                                ? bundle!.syncArtifact.totalDurationMs
                                      .toDouble()
                                : 1,
                            label: _formatMs(currentPositionMs),
                            onChangeStart: controller.beginScrub,
                            onChanged: controller.updateScrub,
                            onChangeEnd: controller.commitScrub,
                          ),
                          if (bundle != null)
                            _ContentWindowRow(
                              playback: playback,
                              currentPositionMs: currentPositionMs,
                              onJumpToStart: playback.hasLeadingMatter
                                  ? controller.seekToContentStart
                                  : null,
                              onJumpToEnd: playback.hasTrailingMatter
                                  ? controller.seekToContentEnd
                                  : null,
                            ),
                          if (bundle != null) const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: controller.rewind15Seconds,
                                icon: const Icon(Icons.replay_10_rounded),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                onPressed: controller.forward15Seconds,
                                icon: const Icon(Icons.forward_10_rounded),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed:
                                      bundle != null &&
                                          bundle.syncArtifact.totalDurationMs >
                                              0
                                      ? () => controller.togglePlayback(
                                          bundle.syncArtifact.totalDurationMs,
                                        )
                                      : null,
                                  icon: Icon(
                                    playback.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    playback.isPlaying ? 'Pause' : 'Play',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              PopupMenuButton<double>(
                                initialValue: playback.speed,
                                onSelected: controller.setSpeed,
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMs(int value) {
    final duration = Duration(milliseconds: value);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ReaderLoadedView extends StatelessWidget {
  const _ReaderLoadedView({
    required this.bundle,
    required this.playback,
    required this.onTokenTap,
  });

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  Widget build(BuildContext context) {
    if (bundle.readerModel.sections.isEmpty) {
      final palette = ReaderPalette.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bundle.statusMessage ??
                        'Reader content is not available yet.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The backend is reachable, but there is no normalized reader model to render yet.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final syncIndex = {
      for (final token in bundle.syncArtifact.tokens)
        token.location.locationKey: token,
    };
    final activeLocationKey = _activeToken(
      bundle.syncArtifact,
      playback.displayedPositionMs,
    )?.location.locationKey;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in bundle.readerModel.sections) ...[
                if (section.title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      section.title!,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                for (final paragraph in section.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _ParagraphBlock(
                      section: section,
                      paragraph: paragraph,
                      activeLocationKey: activeLocationKey,
                      syncIndex: syncIndex,
                      onTokenTap: (token) {
                        if (token != null) {
                          onTokenTap(token);
                        }
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static SyncToken? _activeToken(SyncArtifact artifact, int positionMs) {
    for (final token in artifact.tokens) {
      if (positionMs >= token.startMs && positionMs < token.endMs) {
        return token;
      }
    }
    if (artifact.tokens.isNotEmpty &&
        positionMs >= artifact.tokens.last.endMs) {
      return artifact.tokens.last;
    }
    return null;
  }
}

class _ReaderLoadingView extends StatelessWidget {
  const _ReaderLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Reader failed to load',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
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
    final isFallback = source == ReaderContentSource.demoFallback;
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              message ??
                  switch (source) {
                    ReaderContentSource.api => 'Backend project loaded.',
                    ReaderContentSource.artifactPending =>
                      'Backend project is available, but reader artifacts are still processing.',
                    ReaderContentSource.projectError =>
                      'Backend project loaded, but the latest reader artifacts are incomplete.',
                    ReaderContentSource.demoFallback =>
                      'Demo data loaded because the API is unavailable.',
                  },
            ),
          ),
          TextButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Intro detected before the book starts at '
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$positionLabel • $phase',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Text(
            playback.isPlaying ? 'Playing' : 'Paused',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
          ),
        ],
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

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({
    required this.section,
    required this.paragraph,
    required this.activeLocationKey,
    required this.syncIndex,
    required this.onTokenTap,
  });

  final ReaderSection section;
  final ReaderParagraph paragraph;
  final String? activeLocationKey;
  final Map<String, SyncToken> syncIndex;
  final ValueChanged<SyncToken?> onTokenTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 12,
      children: [
        for (final token in paragraph.tokens)
          _TokenPill(
            token: token,
            syncToken:
                syncIndex['${section.id}:${paragraph.index}:${token.index}'],
            isActive:
                activeLocationKey ==
                '${section.id}:${paragraph.index}:${token.index}',
            onTap: onTokenTap,
            palette: palette,
          ),
      ],
    );
  }
}

class _TokenPill extends StatelessWidget {
  const _TokenPill({
    required this.token,
    required this.syncToken,
    required this.isActive,
    required this.onTap,
    required this.palette,
  });

  final ReaderToken token;
  final SyncToken? syncToken;
  final bool isActive;
  final ValueChanged<SyncToken?> onTap;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTap(syncToken),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? palette.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? palette.accentPrimary : Colors.transparent,
          ),
        ),
        child: Text(
          token.text,
          style: textTheme.bodyLarge?.copyWith(
            color: isActive ? palette.accentPrimary : palette.textPrimary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            decoration: isActive ? TextDecoration.underline : null,
            decorationColor: palette.accentPrimary,
          ),
        ),
      ),
    );
  }
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
