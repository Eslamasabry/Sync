import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/features/reader/data/reader_location_store_types.dart';

class FileReaderLocationStore implements ReaderLocationStore {
  const FileReaderLocationStore({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<ReaderLocationSnapshot?> loadProject(
    String projectId, {
    String? apiBaseUrl,
  }) async {
    final exactLocationFile = await _locationFile(
      projectId,
      apiBaseUrl: apiBaseUrl,
    );
    if (await exactLocationFile.exists()) {
      final payload = jsonDecode(await exactLocationFile.readAsString());
      if (payload is! Map) {
        return null;
      }
      return ReaderLocationSnapshot.fromJson(Map<String, dynamic>.from(payload));
    }

    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      final legacyLocationFile = await _legacyLocationFile(projectId);
      if (await legacyLocationFile.exists()) {
        final payload = jsonDecode(await legacyLocationFile.readAsString());
        if (payload is! Map) {
          return null;
        }
        return ReaderLocationSnapshot.fromJson(Map<String, dynamic>.from(payload));
      }
    }

    final snapshots = await loadRecent();
    for (final snapshot in snapshots) {
      if (snapshot.normalizedProjectId == projectId.trim()) {
        if (apiBaseUrl == null ||
            apiBaseUrl.trim().isEmpty ||
            snapshot.normalizedApiBaseUrl.toLowerCase() ==
                apiBaseUrl.trim().toLowerCase()) {
          return snapshot;
        }
      }
    }
    return null;
  }

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async {
    final projectsDirectory = await _projectsDirectory();
    if (!await projectsDirectory.exists()) {
      return const <ReaderLocationSnapshot>[];
    }

    final snapshots = <ReaderLocationSnapshot>[];
    await for (final entity in projectsDirectory.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final locationFile = File('${entity.path}/reading_location.json');
      if (!await locationFile.exists()) {
        continue;
      }
      try {
        final payload = jsonDecode(await locationFile.readAsString());
        if (payload is Map) {
          snapshots.add(
            ReaderLocationSnapshot.fromJson(Map<String, dynamic>.from(payload)),
          );
        }
      } catch (_) {
        continue;
      }
    }

    snapshots.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return snapshots;
  }

  @override
  Future<void> storeProject(ReaderLocationSnapshot snapshot) async {
    final locationFile = await _locationFile(
      snapshot.projectId,
      apiBaseUrl: snapshot.apiBaseUrl,
    );
    await locationFile.parent.create(recursive: true);
    await locationFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
  }

  @override
  Future<void> removeProject(String projectId, {String? apiBaseUrl}) async {
    final locationFile = await _locationFile(projectId, apiBaseUrl: apiBaseUrl);
    if (await locationFile.exists()) {
      await locationFile.delete();
    }
    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      final legacyLocationFile = await _legacyLocationFile(projectId);
      if (await legacyLocationFile.exists()) {
        await legacyLocationFile.delete();
      }
    }
  }

  Future<File> _locationFile(String projectId, {String? apiBaseUrl}) async {
    final normalizedProjectId = projectId.trim();
    final normalizedApiBaseUrl = apiBaseUrl?.trim() ?? '';
    if (normalizedApiBaseUrl.isEmpty) {
      return _legacyLocationFile(normalizedProjectId);
    }
    final projectsDirectory = await _projectsDirectory();
    final encodedIdentityKey = Uri.encodeComponent(
      '${normalizedApiBaseUrl.toLowerCase()}|$normalizedProjectId',
    );
    return File(
      '${projectsDirectory.path}/$encodedIdentityKey/reading_location.json',
    );
  }

  Future<File> _legacyLocationFile(String projectId) async {
    final projectsDirectory = await _projectsDirectory();
    return File('${projectsDirectory.path}/${projectId.trim()}/reading_location.json');
  }

  Future<Directory> _projectsDirectory() async {
    final root = await _cacheRoot();
    return Directory('${root.path}/projects');
  }

  Future<Directory> _cacheRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_reader_cache');
  }
}
