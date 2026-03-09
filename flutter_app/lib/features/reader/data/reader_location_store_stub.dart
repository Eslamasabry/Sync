import 'dart:io';

import 'package:sync_flutter/features/reader/data/reader_location_store_types.dart';

class FileReaderLocationStore implements ReaderLocationStore {
  const FileReaderLocationStore({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<ReaderLocationSnapshot?> loadProject(String projectId) async => null;

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async =>
      const <ReaderLocationSnapshot>[];

  @override
  Future<void> removeProject(String projectId) async {}

  @override
  Future<void> storeProject(ReaderLocationSnapshot snapshot) async {}
}
