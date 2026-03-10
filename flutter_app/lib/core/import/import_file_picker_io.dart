import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';
import 'package:xml/xml.dart';

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
  Future<List<ImportBookCandidate>> scanDeviceBooks() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder with books and audiobooks',
    );
    if (directoryPath == null || directoryPath.isEmpty) {
      return const <ImportBookCandidate>[];
    }

    final root = Directory(directoryPath);
    if (!await root.exists()) {
      return const <ImportBookCandidate>[];
    }

    return scanImportBookCandidates(root);
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

Future<List<ImportBookCandidate>> scanImportBookCandidates(Directory root) async {
  final epubFiles = <ImportPickedFile>[];
  final audioFiles = <ImportPickedFile>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || _isHiddenPath(entity.path)) {
      continue;
    }
    final extension = _extension(entity.path);
    final stat = await entity.stat();
    final file = ImportPickedFile(
      name: entity.uri.pathSegments.isEmpty
          ? entity.path.split(Platform.pathSeparator).last
          : entity.uri.pathSegments.last,
      sizeBytes: stat.size,
      path: entity.path,
    );
    if (_epubExtensions.contains(extension)) {
      epubFiles.add(file);
      continue;
    }
    if (_audioExtensions.contains(extension) &&
        stat.size >= _minimumSuggestedAudioBytes) {
      audioFiles.add(file);
    }
  }

  final candidates = <ImportBookCandidate>[];
  final usedAudioPaths = <String>{};
  for (final epub in epubFiles) {
    final metadata = await _readEpubMetadata(epub);
    final preferredTokens = _normalizedTokens(metadata?.title ?? epub.name);
    final matches = audioFiles.where((audio) {
      final score = _matchingScore(audio.name, preferredTokens);
      return score > 0;
    }).toList(growable: false)
      ..sort((left, right) {
        final leftScore = _matchingScore(left.name, preferredTokens);
        final rightScore = _matchingScore(right.name, preferredTokens);
        return _compareSuggestedAudio(
          (file: left, score: leftScore),
          (file: right, score: rightScore),
        );
      });

    for (final match in matches) {
      if (match.path != null) {
        usedAudioPaths.add(match.path!);
      }
    }

    candidates.add(
      ImportBookCandidate(
        title: metadata?.title ?? _titleFromImportName(epub.name),
        directoryLabel: _directoryLabel(epub.path),
        author: metadata?.author,
        coverBytes: metadata?.coverBytes,
        epubFile: epub,
        audioFiles: matches,
      ),
    );
  }

  final audioOnlyGroups = <String, List<ImportPickedFile>>{};
  for (final audio in audioFiles) {
    final path = audio.path;
    if (path != null && usedAudioPaths.contains(path)) {
      continue;
    }
    final key = _groupingKey(audio.name);
    if (key.isEmpty) {
      continue;
    }
    audioOnlyGroups.putIfAbsent(key, () => <ImportPickedFile>[]).add(audio);
  }

  for (final entry in audioOnlyGroups.entries) {
    final files = entry.value..sort(_naturalAudioOrderCompare);
    candidates.add(
      ImportBookCandidate(
        title: _titleCase(entry.key),
        directoryLabel: _directoryLabel(files.first.path),
        audioFiles: files,
      ),
    );
  }

  candidates.sort((left, right) {
    final leftScore = (left.epubFile != null ? 1000 : 0) + left.audioFiles.length;
    final rightScore =
        (right.epubFile != null ? 1000 : 0) + right.audioFiles.length;
    return rightScore.compareTo(leftScore);
  });
  return candidates.take(12).toList(growable: false);
}

Future<_EpubMetadata?> _readEpubMetadata(ImportPickedFile epub) async {
  final path = epub.path;
  if (path == null || path.isEmpty) {
    return null;
  }

  try {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final containerFile = _findArchiveFile(archive, 'META-INF/container.xml');
    if (containerFile == null) {
      return null;
    }

    final containerDocument = XmlDocument.parse(
      utf8.decode(containerFile.content, allowMalformed: true),
    );
    final rootFile = _firstElementByLocalName(containerDocument, 'rootfile');
    final packagePath = rootFile?.getAttribute('full-path');
    if (packagePath == null || packagePath.isEmpty) {
      return null;
    }

    final normalizedPackagePath = _normalizeArchivePath(packagePath);
    final packageFile = _findArchiveFile(archive, normalizedPackagePath);
    if (packageFile == null) {
      return null;
    }

    final packageDocument = XmlDocument.parse(
      utf8.decode(packageFile.content, allowMalformed: true),
    );
    final metadataElement = _firstElementByLocalName(packageDocument, 'metadata');
    final manifestElement = _firstElementByLocalName(packageDocument, 'manifest');
    final title = _firstElementTextByLocalName(metadataElement, 'title');
    final author = _firstElementTextByLocalName(metadataElement, 'creator');
    final coverPath = _resolveCoverPath(
      packageDocument: packageDocument,
      metadataElement: metadataElement,
      manifestElement: manifestElement,
      packagePath: normalizedPackagePath,
    );
    final coverBytes = coverPath == null
        ? null
        : _findArchiveFile(archive, coverPath)?.content.toList(growable: false);

    if (title == null && author == null && coverBytes == null) {
      return null;
    }

    return _EpubMetadata(title: title, author: author, coverBytes: coverBytes);
  } catch (_) {
    return null;
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

ArchiveFile? _findArchiveFile(Archive archive, String path) {
  final normalizedPath = _normalizeArchivePath(path);
  for (final file in archive) {
    if (_normalizeArchivePath(file.name) == normalizedPath) {
      return file;
    }
  }
  return null;
}

XmlElement? _firstElementByLocalName(XmlNode? node, String localName) {
  if (node == null) {
    return null;
  }
  for (final descendant in node.descendants) {
    if (descendant is XmlElement && descendant.name.local == localName) {
      return descendant;
    }
  }
  return null;
}

String? _firstElementTextByLocalName(XmlNode? node, String localName) {
  final element = _firstElementByLocalName(node, localName);
  final value = element?.innerText.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

String? _resolveCoverPath({
  required XmlDocument packageDocument,
  required XmlElement? metadataElement,
  required XmlElement? manifestElement,
  required String packagePath,
}) {
  if (manifestElement == null) {
    return null;
  }

  String? href;
  for (final item in manifestElement.childElements) {
    if (item.name.local != 'item') {
      continue;
    }
    final properties = item.getAttribute('properties') ?? '';
    if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
      href = item.getAttribute('href');
      break;
    }
  }

  if (href == null || href.isEmpty) {
    final coverId = _findLegacyCoverId(metadataElement);
    if (coverId != null) {
      for (final item in manifestElement.childElements) {
        if (item.name.local == 'item' && item.getAttribute('id') == coverId) {
          href = item.getAttribute('href');
          break;
        }
      }
    }
  }

  if (href == null || href.isEmpty) {
    for (final item in packageDocument.descendants.whereType<XmlElement>()) {
      if (item.name.local != 'item') {
        continue;
      }
      final mediaType = item.getAttribute('media-type') ?? '';
      if (!mediaType.startsWith('image/')) {
        continue;
      }
      final id = item.getAttribute('id') ?? '';
      if (id.toLowerCase().contains('cover')) {
        href = item.getAttribute('href');
        break;
      }
    }
  }

  if (href == null || href.isEmpty) {
    return null;
  }

  return _resolveArchivePath(packagePath, href);
}

String? _findLegacyCoverId(XmlElement? metadataElement) {
  if (metadataElement == null) {
    return null;
  }

  for (final child in metadataElement.childElements) {
    if (child.name.local != 'meta') {
      continue;
    }
    final name = child.getAttribute('name')?.toLowerCase();
    if (name != 'cover') {
      continue;
    }
    final content = child.getAttribute('content')?.trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
  }
  return null;
}

String _resolveArchivePath(String packagePath, String relativePath) {
  if (relativePath.startsWith('/')) {
    return _normalizeArchivePath(relativePath);
  }

  final packageSegments = packagePath.split('/')..removeLast();
  final relativeSegments = Uri.decodeFull(relativePath).split('/');
  return _normalizeArchiveSegments([...packageSegments, ...relativeSegments]);
}

String _normalizeArchivePath(String path) {
  return _normalizeArchiveSegments(Uri.decodeFull(path).split('/'));
}

String _normalizeArchiveSegments(List<String> segments) {
  final normalized = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (normalized.isNotEmpty) {
        normalized.removeLast();
      }
      continue;
    }
    normalized.add(segment);
  }
  return normalized.join('/');
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

int _naturalAudioOrderCompare(ImportPickedFile left, ImportPickedFile right) =>
    _naturalNameCompare(left.name, right.name);

String _directoryLabel(String? path) {
  final directory = _parentDirectory(path);
  if (directory == null) {
    return 'Selected folder';
  }
  final segments = directory.path.split(Platform.pathSeparator);
  return segments.isEmpty ? directory.path : segments.last;
}

class _EpubMetadata {
  const _EpubMetadata({
    required this.title,
    required this.author,
    required this.coverBytes,
  });

  final String? title;
  final String? author;
  final List<int>? coverBytes;
}

String _titleFromImportName(String name) {
  final tokens = _normalizedTokens(name).toList(growable: false);
  if (tokens.isEmpty) {
    return name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }
  return _titleCase(tokens.join(' '));
}

String _groupingKey(String name) {
  final tokens = _normalizedTokens(
    name,
  ).where((token) => int.tryParse(token) == null).take(4).toList(growable: false);
  return tokens.join(' ').trim();
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
