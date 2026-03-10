import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/core/import/import_file_picker_io.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';

void main() {
  const picker = PlatformImportFilePicker();

  group('PlatformImportFilePicker nearby discovery', () {
    test('scanDeviceBooks builds local book candidates from a selected folder', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sync-import-device-books-',
      );
      addTearDown(() => directory.delete(recursive: true));

      await _writeFile(directory, 'The Time Machine.epub', 1200);
      await _writeFile(
        directory,
        'The Time Machine - Chapter 01.m4b',
        3 * 1024 * 1024,
      );
      await _writeFile(
        directory,
        'The Time Machine - Chapter 02.m4b',
        3 * 1024 * 1024,
      );
      await _writeFile(
        directory,
        'Standalone Story - Part 01.mp3',
        3 * 1024 * 1024,
      );

      final results = await scanImportBookCandidatesInDirectory(directory);

      expect(results, isNotEmpty);
      expect(results.first.title, 'The Time Machine');
      expect(results.first.epubFile?.name, 'The Time Machine.epub');
      expect(results.first.audioFiles, hasLength(2));
      expect(results.any((candidate) => candidate.title == 'Standalone Story'), isTrue);
    });

    test(
      'findNearbyAudioFiles filters hidden and tiny files, and keeps chapter order',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'sync-import-audio-',
        );
        addTearDown(() => directory.delete(recursive: true));

        await _writeFile(directory, 'The Time Machine.epub', 1200);
        await _writeFile(
          directory,
          'The Time Machine - Chapter 10.m4b',
          3 * 1024 * 1024,
        );
        await _writeFile(
          directory,
          'The Time Machine - Chapter 02.m4b',
          3 * 1024 * 1024,
        );
        await _writeFile(
          directory,
          'The Time Machine - Preview.mp3',
          3 * 1024 * 1024,
        );
        await _writeFile(
          directory,
          'Random Podcast Episode.mp3',
          3 * 1024 * 1024,
        );
        await _writeFile(
          directory,
          '.The Time Machine - Chapter 01.m4b',
          3 * 1024 * 1024,
        );
        await _writeFile(directory, 'The Time Machine - tiny.mp3', 128);

        final results = await picker.findNearbyAudioFiles(
          ImportPickedFile(
            name: 'The Time Machine.epub',
            sizeBytes: 1200,
            path: '${directory.path}/The Time Machine.epub',
          ),
          preferredTitle: 'The Time Machine',
        );

        expect(
          results.map((file) => file.name),
          containsAllInOrder(<String>[
            'The Time Machine - Chapter 02.m4b',
            'The Time Machine - Chapter 10.m4b',
          ]),
        );
        expect(
          results.map((file) => file.name),
          isNot(contains('.The Time Machine - Chapter 01.m4b')),
        );
        expect(
          results.map((file) => file.name),
          isNot(contains('The Time Machine - tiny.mp3')),
        );
        expect(results.first.name, 'The Time Machine - Chapter 02.m4b');
      },
    );

    test(
      'findNearbyAudioFiles strips audiobook noise tokens when ranking',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'sync-import-audio-noise-',
        );
        addTearDown(() => directory.delete(recursive: true));

        await _writeFile(directory, 'The Time Machine.epub', 1200);
        await _writeFile(
          directory,
          'The Time Machine unabridged disc 1 narrated by reader.m4b',
          3 * 1024 * 1024,
        );
        await _writeFile(
          directory,
          'Completely Different Novel.m4b',
          3 * 1024 * 1024,
        );

        final results = await picker.findNearbyAudioFiles(
          ImportPickedFile(
            name: 'The Time Machine.epub',
            sizeBytes: 1200,
            path: '${directory.path}/The Time Machine.epub',
          ),
          preferredTitle: 'The Time Machine',
        );

        expect(results, isNotEmpty);
        expect(
          results.first.name,
          'The Time Machine unabridged disc 1 narrated by reader.m4b',
        );
      },
    );

    test(
      'findNearbyEpubFile prefers the closest matching book in the same directory',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'sync-import-epub-',
        );
        addTearDown(() => directory.delete(recursive: true));

        await _writeFile(directory, 'Collected Stories.epub', 1200);
        await _writeFile(directory, 'The Yellow Wallpaper.epub', 1200);
        await _writeFile(directory, '.The Yellow Wallpaper.epub', 1200);
        await _writeFile(
          directory,
          'The Yellow Wallpaper - Chapter 01.mp3',
          3 * 1024 * 1024,
        );

        final result = await picker.findNearbyEpubFile(
          ImportPickedFile(
            name: 'The Yellow Wallpaper - Chapter 01.mp3',
            sizeBytes: 3 * 1024 * 1024,
            path: '${directory.path}/The Yellow Wallpaper - Chapter 01.mp3',
          ),
          preferredTitle: 'The Yellow Wallpaper',
        );

        expect(result, isNotNull);
        expect(result!.name, 'The Yellow Wallpaper.epub');
      },
    );

    test(
      'nearby discovery returns nothing when the seed file has no usable path',
      () async {
        const seed = ImportPickedFile(name: 'Missing.epub', sizeBytes: 0);

        final audioResults = await picker.findNearbyAudioFiles(seed);
        final epubResult = await picker.findNearbyEpubFile(seed);

        expect(audioResults, isEmpty);
        expect(epubResult, isNull);
      },
    );
  });
}

Future<List<ImportBookCandidate>> scanImportBookCandidatesInDirectory(
  Directory directory,
) {
  return scanImportBookCandidates(directory);
}

Future<void> _writeFile(Directory directory, String name, int sizeBytes) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(List<int>.filled(sizeBytes, 1), flush: true);
}
