import 'package:file_picker/file_picker.dart';
import 'package:sync_flutter/core/import/import_file_picker_types.dart';

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
    if (file == null) {
      return null;
    }
    return ImportPickedFile(
      name: file.name,
      sizeBytes: file.size,
      path: file.path,
      bytes: file.bytes,
    );
  }

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'ogg', 'aac'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) {
      return const <ImportPickedFile>[];
    }

    return result.files
        .map(
          (file) => ImportPickedFile(
            name: file.name,
            sizeBytes: file.size,
            path: file.path,
            bytes: file.bytes,
          ),
        )
        .toList(growable: false);
  }
}
