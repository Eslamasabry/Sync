import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';

const _audioExtensions = <String>{
  'mp3',
  'm4a',
  'wav',
  'ogg',
  'aac',
  'm4b',
  'flac',
};
const _epubExtensions = <String>{'epub'};
const _minimumSuggestedAudioBytes = 2 * 1024 * 1024;
const _ignoredFilenameTokens = <String>{
  'audiobook',
  'audio',
  'book',
  'books',
  'chapter',
  'chapters',
  'part',
  'parts',
  'disc',
  'disk',
  'track',
  'tracks',
  'cd',
  'mp3',
  'm4b',
  'm4a',
  'flac',
  'ogg',
  'wav',
  'aac',
  'unabridged',
  'abridged',
  'narrated',
  'narrator',
  'read',
  'reading',
  'version',
  'vol',
  'volume',
};
const _likelyJunkFilenameTokens = <String>{
  'sample',
  'preview',
  'trailer',
  'excerpt',
  'demo',
  'test',
};

class PlatformImportFilePicker implements ImportFilePicker {
  const PlatformImportFilePicker();

  @override
  Future<ImportPickedFile?> pickEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    return file == null ? null : _fromPlatformFile(file);
  }

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'wav',
        'ogg',
        'aac',
        'm4b',
        'flac',
      ],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return const <ImportPickedFile>[];
    }

    return result.files.map(_fromPlatformFile).toList(growable: false);
  }

  @override
  Future<List<ImportPickedFile>> findNearbyAudioFiles(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async {
    final directory = _parentDirectory(seedFile.path);
    if (directory == null || !await directory.exists()) {
      return const <ImportPickedFile>[];
    }

    final normalizedTitle = _normalizedTokens(preferredTitle ?? seedFile.name);
    final candidates = <({ImportPickedFile file, int score})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (_isHiddenPath(entity.path)) {
        continue;
      }
      final extension = _extension(entity.path);
      if (!_audioExtensions.contains(extension)) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.size < _minimumSuggestedAudioBytes) {
        continue;
      }
      final file = ImportPickedFile(
        name: entity.uri.pathSegments.isEmpty
            ? entity.path.split(Platform.pathSeparator).last
            : entity.uri.pathSegments.last,
        sizeBytes: stat.size,
        path: entity.path,
      );
      candidates.add((
        file: file,
        score: _matchingScore(file.name, normalizedTitle),
      ));
    }

    candidates.sort((left, right) => _compareSuggestedAudio(left, right));

    return candidates.map((entry) => entry.file).toList(growable: false);
  }

  @override
  Future<ImportPickedFile?> findNearbyEpubFile(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async {
    final directory = _parentDirectory(seedFile.path);
    if (directory == null || !await directory.exists()) {
      return null;
    }

    final normalizedTitle = _normalizedTokens(preferredTitle ?? seedFile.name);
    ({ImportPickedFile file, int score})? bestMatch;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (_isHiddenPath(entity.path)) {
        continue;
      }
      final extension = _extension(entity.path);
      if (!_epubExtensions.contains(extension)) {
        continue;
      }
      final stat = await entity.stat();
      final file = ImportPickedFile(
        name: entity.uri.pathSegments.isEmpty
            ? entity.path.split(Platform.pathSeparator).last
            : entity.uri.pathSegments.last,
        sizeBytes: stat.size,
        path: entity.path,
      );
      final score = _matchingScore(file.name, normalizedTitle);
      if (bestMatch == null || score > bestMatch.score) {
        bestMatch = (file: file, score: score);
      }
    }
    return bestMatch?.file;
  }
}

ImportPickedFile _fromPlatformFile(PlatformFile file) {
  return ImportPickedFile(
    name: file.name,
    sizeBytes: file.size,
    path: file.path,
    bytes: file.bytes,
  );
}

Directory? _parentDirectory(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  return File(path).parent;
}

String _extension(String path) {
  final lastDot = path.lastIndexOf('.');
  if (lastDot == -1 || lastDot == path.length - 1) {
    return '';
  }
  return path.substring(lastDot + 1).toLowerCase();
}

Set<String> _normalizedTokens(String raw) {
  final withoutExtension = raw.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExtension
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length >= 2)
      .where((token) => !_ignoredFilenameTokens.contains(token))
      .toSet();
}

int _matchingScore(String filename, Set<String> preferredTokens) {
  final fileTokens = _normalizedTokens(filename);
  final lowercaseFilename = filename.toLowerCase();
  if (fileTokens.isEmpty) {
    return 0;
  }
  if (preferredTokens.isEmpty) {
    return _containsLikelyJunkToken(fileTokens) ? -20 : 0;
  }

  final overlapTokens = fileTokens.intersection(preferredTokens);
  final overlap = overlapTokens.length;
  final preferredStem = _preferredStem(preferredTokens);
  final containsPreferredStem =
      preferredStem.isNotEmpty && lowercaseFilename.contains(preferredStem);
  final startsWithPreferred = preferredTokens.any(
    (token) => lowercaseFilename.startsWith(token),
  );
  final hasJunkPenalty = _containsLikelyJunkToken(fileTokens);
  return overlap * 10 +
      (containsPreferredStem ? 12 : 0) +
      (startsWithPreferred ? 4 : 0) +
      (hasJunkPenalty ? -20 : 0);
}

int _compareSuggestedAudio(
  ({ImportPickedFile file, int score}) left,
  ({ImportPickedFile file, int score}) right,
) {
  final scoreCompare = right.score.compareTo(left.score);
  if (scoreCompare != 0) {
    return scoreCompare;
  }

  final chapterCompare = _extractTrailingNumber(
    left.file.name,
  ).compareTo(_extractTrailingNumber(right.file.name));
  if (chapterCompare != 0) {
    return chapterCompare;
  }

  return _naturalNameCompare(left.file.name, right.file.name);
}

bool _isHiddenPath(String path) {
  final segments = path.split(Platform.pathSeparator);
  return segments.any(
    (segment) => segment.startsWith('.') && segment.length > 1,
  );
}

bool _containsLikelyJunkToken(Set<String> tokens) {
  return tokens.any(_likelyJunkFilenameTokens.contains);
}

String _preferredStem(Set<String> preferredTokens) {
  final sorted = preferredTokens.toList()..sort();
  return sorted.join(' ');
}

int _extractTrailingNumber(String filename) {
  final match = RegExp(r'(\d+)(?!.*\d)').firstMatch(filename);
  return match == null ? -1 : int.parse(match.group(1)!);
}

int _naturalNameCompare(String left, String right) {
  final leftParts = RegExp(
    r'\d+|\D+',
  ).allMatches(left).map((m) => m.group(0)!).toList();
  final rightParts = RegExp(
    r'\d+|\D+',
  ).allMatches(right).map((m) => m.group(0)!).toList();
  final limit = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < limit; index += 1) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    if (leftNumber != null && rightNumber != null) {
      final numberCompare = leftNumber.compareTo(rightNumber);
      if (numberCompare != 0) {
        return numberCompare;
      }
      continue;
    }

    final textCompare = leftPart.toLowerCase().compareTo(
      rightPart.toLowerCase(),
    );
    if (textCompare != 0) {
      return textCompare;
    }
  }
  return leftParts.length.compareTo(rightParts.length);
}
