import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/reader/presentation/reader_screen.dart';
import 'package:sync_flutter/features/reader/state/reader_session_controller.dart';

class SyncApp extends ConsumerWidget {
  const SyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(readerSessionProvider);
    return MaterialApp(
      title: 'Sync',
      debugShowCheckedModeBanner: false,
      theme: SyncTheme.paper(),
      darkTheme: SyncTheme.night(),
      themeMode: session.themeMode,
      home: const ReaderScreen(),
    );
  }
}
