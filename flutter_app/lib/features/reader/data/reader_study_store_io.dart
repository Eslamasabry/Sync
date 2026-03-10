import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/features/reader/data/reader_study_store_types.dart';

class FileReaderStudyStore implements ReaderStudyStore {
  const FileReaderStudyStore({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<List<ReaderStudyEntry>> loadProject(String projectId) async {
    final studyFile = await _studyFile(projectId);
    if (!await studyFile.exists()) {
      return const <ReaderStudyEntry>[];
    }

    final payload = jsonDecode(await studyFile.readAsString());
    if (payload is! List) {
      return const <ReaderStudyEntry>[];
    }

    return payload
        .whereType<Map>()
        .map(
          (item) => ReaderStudyEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  @override
  Future<void> saveProject(
    String projectId,
    List<ReaderStudyEntry> entries,
  ) async {
    final studyFile = await _studyFile(projectId);
    await studyFile.parent.create(recursive: true);
    final payload = entries
        .map((entry) => entry.toJson())
        .toList(growable: false);
    await studyFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<File> _studyFile(String projectId) async {
    final root = await _cacheRoot();
    return File('${root.path}/projects/$projectId/study_entries.json');
  }

  Future<Directory> _cacheRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_reader_cache');
  }
}
