import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/presentation/library_screen.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/presentation/reader_screen.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class SyncApp extends ConsumerStatefulWidget {
  const SyncApp({super.key});

  @override
  ConsumerState<SyncApp> createState() => _SyncAppState();
}

class _SyncAppState extends ConsumerState<SyncApp> {
  bool? _lastEntryHasBook;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(readerPlaybackProvider);
    final homeTab = ref.watch(homeTabProvider);
    final connection = ref.watch(runtimeConnectionSettingsProvider);
    final project = ref.watch(readerProjectProvider);
    final settings = connection.asData?.value;
    final bundle = project.asData?.value;
    final hasReaderTarget = _hasReaderTarget(
      settings: settings,
      bundle: bundle,
    );

    _syncEntryPreference(hasReaderTarget);

    return MaterialApp(
      title: 'Sync',
      debugShowCheckedModeBanner: false,
      theme: SyncTheme.paper(),
      darkTheme: SyncTheme.night(),
      themeMode: playback.themeMode,
      home: Builder(
        builder: (context) {
          final palette = ReaderPalette.of(context);
          return Scaffold(
            backgroundColor: palette.backgroundBase,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.backgroundChrome,
                    palette.backgroundBase,
                    palette.backgroundBase,
                  ],
                  stops: const [0, 0.34, 1],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -72,
                    right: -40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: palette.shellGlow.withValues(alpha: 0.16),
                              blurRadius: 110,
                              spreadRadius: 14,
                            ),
                          ],
                        ),
                        child: const SizedBox(width: 180, height: 180),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _HomeTabViewport(),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _ReadingShellBar(
                selectedIndex: homeTab,
                connection: connection,
                project: project,
                onDestinationSelected: (index) {
                  final controller = ref.read(homeTabProvider.notifier);
                  if (index == HomeTabDestination.library.index) {
                    controller.showLibrary();
                  } else {
                    controller.showReader();
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  bool _hasReaderTarget({
    required RuntimeConnectionSettings? settings,
    required ReaderProjectBundle? bundle,
  }) {
    if (bundle != null) {
      return bundle.source != ReaderContentSource.selectionRequired;
    }
    return (settings?.normalizedProjectId ?? '').isNotEmpty;
  }

  void _syncEntryPreference(bool hasReaderTarget) {
    if (_lastEntryHasBook == hasReaderTarget) {
      return;
    }
    _lastEntryHasBook = hasReaderTarget;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(homeTabProvider.notifier)
          .syncEntryPreference(hasReaderTarget: hasReaderTarget);
    });
  }
}

class _HomeTabViewport extends ConsumerWidget {
  const _HomeTabViewport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(homeTabProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        _ShellPane(
          visible: selectedIndex == HomeTabDestination.library.index,
          restingOffset: const Offset(-0.035, 0),
          child: const LibraryScreen(),
        ),
        _ShellPane(
          visible: selectedIndex == HomeTabDestination.reader.index,
          restingOffset: const Offset(0.035, 0),
          child: const ReaderScreen(),
        ),
      ],
    );
  }
}

class _ShellPane extends StatelessWidget {
  const _ShellPane({
    required this.visible,
    required this.restingOffset,
    required this.child,
  });

  final bool visible;
  final Offset restingOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: TickerMode(
        enabled: visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : restingOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: visible ? 1 : 0.985,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingShellBar extends StatelessWidget {
  const _ReadingShellBar({
    required this.selectedIndex,
    required this.connection,
    required this.project,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final AsyncValue<RuntimeConnectionSettings> connection;
  final AsyncValue<ReaderProjectBundle> project;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final settings = connection.asData?.value;
    final bundle = project.asData?.value;
    final hasReaderTarget = bundle != null
        ? bundle.source != ReaderContentSource.selectionRequired
        : (settings?.normalizedProjectId ?? '').isNotEmpty;
    final readerTitle = _readerTitle(bundle, settings);
    final libraryTitle = hasReaderTarget ? 'Library' : 'Import';
    final librarySubtitle = hasReaderTarget ? 'Shelf and queue' : 'Start here';
    final readerSubtitle = hasReaderTarget ? 'Continue reading' : 'Open a book';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundElevated.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.borderSubtle.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: palette.shellShadow.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _ShellContextLine(
                key: ValueKey<String>(
                  '$selectedIndex:$hasReaderTarget:${readerTitle ?? 'empty'}',
                ),
                icon: selectedIndex == HomeTabDestination.reader.index
                    ? Icons.auto_stories_rounded
                    : Icons.collections_bookmark_rounded,
                label: selectedIndex == HomeTabDestination.reader.index
                    ? hasReaderTarget
                          ? readerTitle ?? 'Open book'
                          : 'Open a saved project or import a book to begin.'
                    : hasReaderTarget
                    ? 'Your current book stays one tap away while you manage imports.'
                    : 'Start with an EPUB and audiobook import.',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ShellDestinationButton(
                    icon: hasReaderTarget
                        ? Icons.local_library_outlined
                        : Icons.upload_file_outlined,
                    selectedIcon: hasReaderTarget
                        ? Icons.local_library_rounded
                        : Icons.upload_file_rounded,
                    title: libraryTitle,
                    subtitle: librarySubtitle,
                    selected: selectedIndex == HomeTabDestination.library.index,
                    onTap: () =>
                        onDestinationSelected(HomeTabDestination.library.index),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ShellDestinationButton(
                    icon: Icons.menu_book_outlined,
                    selectedIcon: Icons.menu_book_rounded,
                    title: hasReaderTarget ? 'Read' : 'Open Book',
                    subtitle: readerSubtitle,
                    selected: selectedIndex == HomeTabDestination.reader.index,
                    accentLabel: hasReaderTarget ? 'Live' : null,
                    onTap: () =>
                        onDestinationSelected(HomeTabDestination.reader.index),
                  ),
                ),
              ],
            ),
            if (hasReaderTarget && readerTitle != null) ...[
              const SizedBox(height: 8),
              Text(
                readerTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _readerTitle(
    ReaderProjectBundle? bundle,
    RuntimeConnectionSettings? settings,
  ) {
    final projectTitle = bundle?.readerModel.title.trim();
    if (projectTitle != null && projectTitle.isNotEmpty) {
      return projectTitle;
    }
    final projectId = settings?.normalizedProjectId ?? '';
    if (projectId.isEmpty) {
      return null;
    }
    return projectId;
  }
}

class _ShellContextLine extends StatelessWidget {
  const _ShellContextLine({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.backgroundBase.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle.withValues(alpha: 0.75)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.accentPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellDestinationButton extends StatelessWidget {
  const _ShellDestinationButton({
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.accentLabel,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? accentLabel;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? palette.accentSoft.withValues(alpha: 0.84)
            : palette.backgroundBase.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected
              ? palette.accentPrimary.withValues(alpha: 0.28)
              : palette.borderSubtle.withValues(alpha: 0.72),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.textPrimary.withValues(alpha: 0.08)
                        : palette.backgroundElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 22,
                    color: selected ? palette.textPrimary : palette.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: selected
                                    ? palette.textPrimary
                                    : palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (accentLabel != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: palette.backgroundElevated,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                accentLabel!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.accentPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? palette.textPrimary.withValues(alpha: 0.78)
                              : palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
