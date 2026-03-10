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
              decoration: BoxDecoration(color: palette.backgroundBase),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 78),
                      child: IndexedStack(
                        index: homeTab,
                        children: const [LibraryScreen(), ReaderScreen()],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 18),
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
    final bundle = project.asData?.value;
    final settings = connection.asData?.value ?? defaultConnectionSettings;
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: palette.backgroundElevated.withValues(alpha: 0.96),
        border: Border.all(color: palette.borderSubtle.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: palette.shellShadow,
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.textPrimary,
                borderRadius: BorderRadius.circular(14),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$modeLabel • $sourceLabel • ${settings.shortHost}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _ShellDestination(
              icon: Icons.dashboard_customize_outlined,
              selectedIcon: Icons.dashboard_customize_rounded,
              label: 'Library',
              selected: selectedIndex == 0,
              compact: true,
              onTap: () => onDestinationSelected(0),
            ),
            const SizedBox(width: 8),
            _ShellDestination(
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book_rounded,
              label: 'Reader',
              selected: selectedIndex == 1,
              compact: true,
              onTap: () => onDestinationSelected(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellDestination extends StatelessWidget {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool compact;
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
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 16 : 22),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? palette.textPrimary : palette.textMuted,
                  size: compact ? 18 : 22,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: (compact
                          ? theme.textTheme.labelMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(
                        color: selected
                            ? palette.textPrimary
                            : palette.textMuted,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
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
