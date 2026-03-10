import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/features/reader/data/reader_study_store.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

final readerStudyStoreProvider = Provider<ReaderStudyStore>(
  (ref) => const FileReaderStudyStore(),
);

final readerStudyEntriesProvider =
    AsyncNotifierProvider<ReaderStudyEntriesController, List<ReaderStudyEntry>>(
      ReaderStudyEntriesController.new,
    );

class ReaderStudyEntryDraft {
  const ReaderStudyEntryDraft({
    required this.type,
    required this.positionMs,
    required this.excerpt,
    this.sectionId,
    this.sectionTitle,
    this.note,
  });

  final ReaderStudyEntryType type;
  final int positionMs;
  final String excerpt;
  final String? sectionId;
  final String? sectionTitle;
  final String? note;
}

class ReaderStudyEntriesController
    extends AsyncNotifier<List<ReaderStudyEntry>> {
  @override
  Future<List<ReaderStudyEntry>> build() async {
    final projectId = await ref.watch(projectIdProvider.future);
    return ref.watch(readerStudyStoreProvider).loadProject(projectId);
  }

  Future<void> addEntry(ReaderStudyEntryDraft draft) async {
    final projectId = await ref.read(projectIdProvider.future);
    final existing = state.asData?.value ?? const <ReaderStudyEntry>[];
    final next = [
      ReaderStudyEntry(
        id: _entryId(),
        projectId: projectId,
        type: draft.type,
        positionMs: draft.positionMs,
        createdAt: DateTime.now().toUtc(),
        excerpt: draft.excerpt,
        sectionId: draft.sectionId,
        sectionTitle: draft.sectionTitle,
        note: draft.note,
      ),
      ...existing,
    ];
    state = AsyncData(next);
    await ref.read(readerStudyStoreProvider).saveProject(projectId, next);
  }

  Future<void> removeEntry(String id) async {
    final projectId = await ref.read(projectIdProvider.future);
    final existing = state.asData?.value ?? const <ReaderStudyEntry>[];
    final next = existing
        .where((entry) => entry.id != id)
        .toList(growable: false);
    state = AsyncData(next);
    await ref.read(readerStudyStoreProvider).saveProject(projectId, next);
  }

  String _entryId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final randomBits = Random().nextInt(1 << 20).toRadixString(36);
    return '$now$randomBits';
  }
}
