import 'dart:io';

import 'package:sync_flutter/features/reader/data/reader_study_store_types.dart';

class FileReaderStudyStore implements ReaderStudyStore {
  const FileReaderStudyStore({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<List<ReaderStudyEntry>> loadProject(String projectId) async =>
      const <ReaderStudyEntry>[];

  @override
  Future<void> saveProject(
    String projectId,
    List<ReaderStudyEntry> entries,
  ) async {}
}
