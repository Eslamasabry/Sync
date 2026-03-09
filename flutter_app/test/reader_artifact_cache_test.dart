import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache.dart';
import 'package:sync_flutter/features/reader/state/sample_reader_data.dart';

void main() {
  test('file cache stores and reloads reader artifacts', () async {
    final tempDir = await Directory.systemTemp.createTemp('sync-reader-cache-');
    addTearDown(() => tempDir.delete(recursive: true));

    final cache = FileReaderArtifactCache(baseDirectory: tempDir);

    await cache.storeProject(
      projectId: 'demo-book',
      readerModel: demoReaderModel,
      syncArtifact: demoSyncArtifact,
    );

    final cached = await cache.loadProject('demo-book');

    expect(cached, isNotNull);
    expect(cached!.readerModel.title, demoReaderModel.title);
    expect(cached.syncArtifact.tokens.length, demoSyncArtifact.tokens.length);
  });
}
