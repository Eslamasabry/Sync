import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_session_controller.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(readerSessionProvider);
    final controller = ref.read(readerSessionProvider.notifier);
    final palette = ReaderPalette.of(context);
    final syncIndex = {
      for (final token in session.syncArtifact.tokens)
        token.location.locationKey: token,
    };

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
                          Text(
                            session.readerModel.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: controller.toggleTheme,
                      icon: Icon(
                        session.themeMode == ThemeMode.light
                            ? Icons.nightlight_round
                            : Icons.wb_sunny_outlined,
                      ),
                      label: Text(
                        session.themeMode == ThemeMode.light
                            ? 'Night'
                            : 'Paper',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final section
                              in session.readerModel.sections) ...[
                            if (section.title != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Text(
                                  section.title!,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                              ),
                            for (final paragraph in section.paragraphs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _ParagraphBlock(
                                  section: section,
                                  paragraph: paragraph,
                                  activeLocationKey: session.activeLocationKey,
                                  syncIndex: syncIndex,
                                  onTokenTap: (token) {
                                    if (token != null) {
                                      controller.seekToToken(token);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatMs(session.positionMs),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            Text(
                              '${session.speed.toStringAsFixed(2)}x',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          ],
                        ),
                        Slider(
                          value: session.positionMs
                              .clamp(0, session.syncArtifact.totalDurationMs)
                              .toDouble(),
                          max: session.syncArtifact.totalDurationMs > 0
                              ? session.syncArtifact.totalDurationMs.toDouble()
                              : 1,
                          onChanged: (value) =>
                              controller.seekTo(value.round()),
                        ),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: controller.rewind15Seconds,
                              icon: const Icon(Icons.replay_10_rounded),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: controller.togglePlayback,
                                icon: Icon(
                                  session.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  session.isPlaying ? 'Pause' : 'Play',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            PopupMenuButton<double>(
                              initialValue: session.speed,
                              onSelected: controller.setSpeed,
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 0.8, child: Text('0.8x')),
                                PopupMenuItem(value: 1.0, child: Text('1.0x')),
                                PopupMenuItem(
                                  value: 1.25,
                                  child: Text('1.25x'),
                                ),
                                PopupMenuItem(value: 1.5, child: Text('1.5x')),
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
