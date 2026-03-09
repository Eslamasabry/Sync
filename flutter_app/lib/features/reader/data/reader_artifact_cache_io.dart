import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/features/reader/data/reader_artifact_cache_types.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

class FileReaderArtifactCache implements ReaderArtifactCache {
  const FileReaderArtifactCache({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<CachedReaderProject?> loadProject(String projectId) async {
    final bundleFile = await _bundleFile(projectId);
    if (!await bundleFile.exists()) {
      return null;
    }

    final payload = jsonDecode(await bundleFile.readAsString());
    if (payload is! Map) {
      return null;
    }

    final bundle = Map<String, dynamic>.from(payload);
    final readerModelPayload = _asMap(bundle['reader_model']);
    final syncArtifactPayload = _asMap(bundle['sync_artifact']);
    if (readerModelPayload.isEmpty || syncArtifactPayload.isEmpty) {
      return null;
    }

    final cachedAtValue = bundle['cached_at']?.toString();
    final cachedAt =
        DateTime.tryParse(cachedAtValue ?? '')?.toUtc() ??
        DateTime.now().toUtc();

    return CachedReaderProject(
      readerModel: ReaderModel.fromJson(readerModelPayload),
      syncArtifact: SyncArtifact.fromJson(syncArtifactPayload),
      cachedAt: cachedAt,
    );
  }

  @override
  Future<void> storeProject({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  }) async {
    final bundleFile = await _bundleFile(projectId);
    await bundleFile.parent.create(recursive: true);
    final payload = {
      'project_id': projectId,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'reader_model': readerModel.toJson(),
      'sync_artifact': syncArtifact.toJson(),
    };
    await bundleFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<File> _bundleFile(String projectId) async {
    final root = await _cacheRoot();
    return File('${root.path}/projects/$projectId/reader_bundle.json');
  }

  Future<Directory> _cacheRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_reader_cache');
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}
