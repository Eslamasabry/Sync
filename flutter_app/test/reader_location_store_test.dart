import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';

void main() {
  test('file reader location store persists and lists recent snapshots', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'sync-reader-location-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final store = FileReaderLocationStore(baseDirectory: tempDir);
    final older = ReaderLocationSnapshot(
      projectId: 'book-a',
      positionMs: 1200,
      totalDurationMs: 8000,
      contentStartMs: 200,
      contentEndMs: 7600,
      progressFraction: 0.14,
      sectionId: 's1',
      sectionTitle: 'Opening',
      updatedAt: DateTime.utc(2026, 3, 9, 10),
    );
    final newer = ReaderLocationSnapshot(
      projectId: 'book-b',
      positionMs: 5400,
      totalDurationMs: 11000,
      contentStartMs: 600,
      contentEndMs: 10400,
      progressFraction: 0.51,
      sectionId: 's4',
      sectionTitle: 'Middle',
      updatedAt: DateTime.utc(2026, 3, 9, 12),
    );

    await store.storeProject(older);
    await store.storeProject(newer);

    final loaded = await store.loadProject('book-b');
    final recent = await store.loadRecent();

    expect(loaded, isNotNull);
    expect(loaded!.positionMs, 5400);
    expect(loaded.sectionTitle, 'Middle');
    expect(recent.map((item) => item.projectId), ['book-b', 'book-a']);
  });
}
