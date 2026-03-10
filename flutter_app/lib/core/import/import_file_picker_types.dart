class ImportPickedFile {
  const ImportPickedFile({
    required this.name,
    required this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? path;
  final List<int>? bytes;
}

abstract class ImportFilePicker {
  Future<ImportPickedFile?> pickEpub();

  Future<List<ImportPickedFile>> pickAudioFiles();

  Future<List<ImportPickedFile>> findNearbyAudioFiles(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  });

  Future<ImportPickedFile?> findNearbyEpubFile(
    ImportPickedFile seedFile, {
    String? preferredTitle,
  });
}

class NoopImportFilePicker implements ImportFilePicker {
  const NoopImportFilePicker();

  @override
  Future<List<ImportPickedFile>> pickAudioFiles() async =>
      const <ImportPickedFile>[];

  @override
  Future<ImportPickedFile?> pickEpub() async => null;

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
