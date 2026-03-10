import 'package:sync_flutter/core/import/import_file_picker_types.dart';

class PlatformImportFilePicker implements ImportFilePicker {
  const PlatformImportFilePicker();

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async =>
      const <ImportPickedFile>[];

  @override
  Future<ImportPickedFile?> pickEpub() async => null;

  @override
  Future<List<ImportBookCandidate>> scanDeviceBooks() async =>
      const <ImportBookCandidate>[];

  @override
  Future<List<ImportPickedFile>> findNearbyAudioFiles(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async => const <ImportPickedFile>[];

  @override
  Future<ImportPickedFile?> findNearbyEpubFile(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  }) async => null;
}
