import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/navigation/home_shell_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/library/presentation/library_screen.dart';
import 'package:sync_flutter/features/reader/presentation/reader_screen.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';

class SyncApp extends ConsumerWidget {
  const SyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(readerPlaybackProvider);
    final homeTab = ref.watch(homeTabProvider);
    return MaterialApp(
      title: 'Sync',
      debugShowCheckedModeBanner: false,
      theme: SyncTheme.paper(),
      darkTheme: SyncTheme.night(),
      themeMode: playback.themeMode,
      home: Scaffold(
        body: IndexedStack(
          index: homeTab,
          children: const [LibraryScreen(), ReaderScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: homeTab,
          onDestinationSelected: (index) {
            if (index == 0) {
              ref.read(homeTabProvider.notifier).showLibrary();
            } else {
              ref.read(homeTabProvider.notifier).showReader();
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books_rounded),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.chrome_reader_mode_outlined),
              selectedIcon: Icon(Icons.chrome_reader_mode_rounded),
              label: 'Reader',
            ),
          ],
        ),
      ),
    );
  }
}
