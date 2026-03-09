import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/features/reader/data/reader_study_store.dart';

void main() {
  test('file study store persists entries per project', () async {
    final tempDir = await Directory.systemTemp.createTemp('sync-reader-study-');
    addTearDown(() => tempDir.delete(recursive: true));

    final store = FileReaderStudyStore(baseDirectory: tempDir);
    final entries = [
      ReaderStudyEntry(
        id: 'mark-1',
        projectId: 'demo-book',
        type: ReaderStudyEntryType.bookmark,
        positionMs: 940,
        createdAt: DateTime.utc(2026, 3, 9, 12),
        excerpt: 'Call me Ishmael.',
        sectionId: 's1',
        sectionTitle: 'Loomings',
      ),
      ReaderStudyEntry(
        id: 'note-1',
        projectId: 'demo-book',
        type: ReaderStudyEntryType.note,
        positionMs: 2600,
        createdAt: DateTime.utc(2026, 3, 9, 13),
        excerpt: 'Some years ago never mind how long precisely.',
        note: 'Narration becomes denser here.',
        sectionId: 's1',
        sectionTitle: 'Loomings',
      ),
    ];

    await store.saveProject('demo-book', entries);
    final loaded = await store.loadProject('demo-book');

    expect(loaded, hasLength(2));
    expect(loaded.first.id, 'note-1');
    expect(loaded.first.note, 'Narration becomes denser here.');
    expect(loaded.last.type, ReaderStudyEntryType.bookmark);
  });
}
