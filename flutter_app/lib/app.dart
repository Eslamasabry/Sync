import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/presentation/library_screen.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/presentation/reader_screen.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class SyncApp extends ConsumerWidget {
  const SyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(readerPlaybackProvider);
    final homeTab = ref.watch(homeTabProvider);
    final connection = ref.watch(runtimeConnectionSettingsProvider);
    final project = ref.watch(readerProjectProvider);
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
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.backgroundChrome,
                    palette.backgroundBase,
                    palette.backgroundChrome,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -120,
                    left: -40,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: palette.shellGlow.withValues(alpha: 0.34),
                              blurRadius: 140,
                              spreadRadius: 28,
                            ),
                          ],
                        ),
                        child: const SizedBox(width: 220, height: 220),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 104),
                      child: IndexedStack(
                        index: homeTab,
                        children: const [LibraryScreen(), ReaderScreen()],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _ShellDock(
                        selectedIndex: homeTab,
                        connection: connection,
                        project: project,
                        onDestinationSelected: (index) {
                          if (index == 0) {
                            ref.read(homeTabProvider.notifier).showLibrary();
                          } else {
                            ref.read(homeTabProvider.notifier).showReader();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShellDock extends StatelessWidget {
  const _ShellDock({
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.backgroundElevated.withValues(alpha: 0.96),
            palette.backgroundChrome.withValues(alpha: 0.96),
          ],
        ),
        border: Border.all(color: palette.borderSubtle.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: palette.shellShadow,
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShellSessionRail(
              connection: connection,
              project: project,
              selectedIndex: selectedIndex,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ShellDestination(
                    icon: Icons.dashboard_customize_outlined,
                    selectedIcon: Icons.dashboard_customize_rounded,
                    label: 'Library',
                    selected: selectedIndex == 0,
                    onTap: () => onDestinationSelected(0),
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: palette.borderSubtle.withValues(alpha: 0.7),
                ),
                Expanded(
                  child: _ShellDestination(
                    icon: Icons.menu_book_outlined,
                    selectedIcon: Icons.menu_book_rounded,
                    label: 'Reader',
                    selected: selectedIndex == 1,
                    onTap: () => onDestinationSelected(1),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.textPrimary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'S',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: palette.backgroundElevated,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellSessionRail extends StatelessWidget {
  const _ShellSessionRail({
    required this.connection,
    required this.project,
    required this.selectedIndex,
  });

  final AsyncValue<RuntimeConnectionSettings> connection;
  final AsyncValue<ReaderProjectBundle> project;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final settings =
        connection.asData?.value ?? defaultConnectionSettings;
    final bundle = project.asData?.value;
    final sourceLabel = switch (bundle?.source) {
      ReaderContentSource.api => 'Live API',
      ReaderContentSource.offlineCache => 'Offline cache',
      ReaderContentSource.artifactPending => 'Pending artifacts',
      ReaderContentSource.projectError => 'Incomplete artifacts',
      ReaderContentSource.demoFallback => 'Demo content',
      null => 'Connecting',
    };
    final title = bundle?.readerModel.title ?? settings.normalizedProjectId;
    final modeLabel = selectedIndex == 0 ? 'Library' : 'Reader';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Session',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textMuted,
            ),
          ),
          _ShellRailChip(label: modeLabel),
          _ShellRailChip(label: settings.shortHost),
          _ShellRailChip(label: sourceLabel),
          Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _ShellRailChip extends StatelessWidget {
  const _ShellRailChip({required this.label});

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

class _ShellDestination extends StatelessWidget {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? palette.accentSoft.withValues(alpha: 0.9)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? palette.textPrimary : palette.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? palette.textPrimary : palette.textMuted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
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
