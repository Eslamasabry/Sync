import 'package:sync_flutter/core/import/import_file_picker_types.dart';

class PlatformImportFilePicker implements ImportFilePicker {
  const PlatformImportFilePicker();

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async =>
      const <ImportPickedFile>[];

  @override
  Future<ImportPickedFile?> pickEpub() async => null;
}
