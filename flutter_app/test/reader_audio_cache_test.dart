import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache.dart';

void main() {
  test('audio cache downloads and reloads local audio metadata', () async {
    final tempDir = await Directory.systemTemp.createTemp('sync-audio-cache-');
    addTearDown(() => tempDir.delete(recursive: true));

    final cache = FileReaderAudioCache(baseDirectory: tempDir);
    final result = await cache.cacheProjectAudio(
      projectId: 'demo-book',
      assets: const [
        AudioDownloadDescriptor(
          assetId: 'audio-demo',
          filename: 'audio-demo.wav',
          downloadUrl: 'http://localhost/audio-demo.wav',
          sizeBytes: 4,
          checksumSha256:
              '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
          durationMs: 1000,
        ),
      ],
      downloadAsset: (asset, destinationPath, reportProgress) async {
        final file = File(destinationPath);
        await file.writeAsBytes(const [1, 2, 3, 4]);
        reportProgress(4, 4);
      },
    );

    expect(result.assetCount, 1);
    expect(result.assetsById['audio-demo'], isNotNull);

    final inspected = await cache.inspectProject(
      'demo-book',
      expectedAssetIds: const ['audio-demo'],
    );
    expect(inspected.assetCount, 1);
    expect(
      inspected.assetsById['audio-demo']!.filePath,
      contains('audio-demo'),
    );
  });
}
