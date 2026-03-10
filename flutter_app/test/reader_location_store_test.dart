import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store.dart';

void main() {
  test(
    'file reader location store persists and lists recent snapshots',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'sync-reader-location-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final store = FileReaderLocationStore(baseDirectory: tempDir);
      final older = ReaderLocationSnapshot(
        apiBaseUrl: 'https://alpha.example.test/v1',
        authToken: 'alpha-token',
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
        apiBaseUrl: 'https://beta.example.test/v1',
        authToken: 'beta-token',
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

      final loaded = await store.loadProject(
        'book-b',
        apiBaseUrl: 'https://beta.example.test/v1',
      );
      final recent = await store.loadRecent();

      expect(loaded, isNotNull);
      expect(loaded!.positionMs, 5400);
      expect(loaded.authToken, 'beta-token');
      expect(loaded.sectionTitle, 'Middle');
      expect(loaded.shortHost, 'beta.example.test');
      expect(recent.map((item) => item.projectId), ['book-b', 'book-a']);
    },
  );

  test(
    'file reader location store keeps same project id separate by server',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'sync-reader-location-multi-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final store = FileReaderLocationStore(baseDirectory: tempDir);
      final alpha = ReaderLocationSnapshot(
        apiBaseUrl: 'https://alpha.example.test/v1',
        authToken: 'alpha-token',
        projectId: 'shared-book',
        positionMs: 1400,
        totalDurationMs: 8000,
        contentStartMs: 0,
        contentEndMs: 7600,
        progressFraction: 0.18,
        updatedAt: DateTime.utc(2026, 3, 9, 9),
      );
      final beta = ReaderLocationSnapshot(
        apiBaseUrl: 'https://beta.example.test/v1',
        authToken: 'beta-token',
        projectId: 'shared-book',
        positionMs: 6200,
        totalDurationMs: 9000,
        contentStartMs: 100,
        contentEndMs: 8700,
        progressFraction: 0.72,
        updatedAt: DateTime.utc(2026, 3, 9, 13),
      );

      await store.storeProject(alpha);
      await store.storeProject(beta);

      final restoredAlpha = await store.loadProject(
        'shared-book',
        apiBaseUrl: 'https://alpha.example.test/v1',
      );
      final restoredBeta = await store.loadProject(
        'shared-book',
        apiBaseUrl: 'https://beta.example.test/v1',
      );

      expect(restoredAlpha, isNotNull);
      expect(restoredBeta, isNotNull);
      expect(restoredAlpha!.positionMs, 1400);
      expect(restoredAlpha.authToken, 'alpha-token');
      expect(restoredBeta!.positionMs, 6200);
      expect(restoredBeta.authToken, 'beta-token');
    },
  );
}
