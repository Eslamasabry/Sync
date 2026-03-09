import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sync_flutter/features/reader/data/reader_audio_cache_types.dart';

class FileReaderAudioCache implements ReaderAudioCache {
  const FileReaderAudioCache({this.baseDirectory});

  final Directory? baseDirectory;

  @override
  Future<CachedProjectAudio> inspectProject(
    String projectId, {
    Iterable<String>? expectedAssetIds,
  }) async {
    final manifestFile = await _manifestFile(projectId);
    if (!await manifestFile.exists()) {
      return const CachedProjectAudio(assetsById: {}, updatedAt: null);
    }

    final payload = jsonDecode(await manifestFile.readAsString());
    if (payload is! Map) {
      return const CachedProjectAudio(assetsById: {}, updatedAt: null);
    }

    final manifest = Map<String, dynamic>.from(payload);
    final assetsPayload = manifest['assets'];
    if (assetsPayload is! List) {
      return const CachedProjectAudio(assetsById: {}, updatedAt: null);
    }

    final expectedIds = expectedAssetIds?.toSet();
    final assetsById = <String, CachedAudioAsset>{};
    DateTime? updatedAt;

    for (final item in assetsPayload) {
      final asset = _parseAsset(item);
      if (asset == null) {
        continue;
      }
      if (expectedIds != null && !expectedIds.contains(asset.assetId)) {
        continue;
      }
      final file = File(asset.filePath);
      if (!await file.exists()) {
        continue;
      }
      if (asset.sizeBytes != null && await file.length() != asset.sizeBytes) {
        continue;
      }
      assetsById[asset.assetId] = asset;
      if (updatedAt == null || asset.cachedAt.isAfter(updatedAt)) {
        updatedAt = asset.cachedAt;
      }
    }

    return CachedProjectAudio(assetsById: assetsById, updatedAt: updatedAt);
  }

  @override
  Future<CachedProjectAudio> cacheProjectAudio({
    required String projectId,
    required List<AudioDownloadDescriptor> assets,
    required Future<void> Function(
      AudioDownloadDescriptor asset,
      String destinationPath,
      void Function(int received, int total) reportProgress,
    )
    downloadAsset,
    void Function(AudioDownloadProgress progress)? onProgress,
  }) async {
    final projectDirectory = await _projectDirectory(projectId);
    await projectDirectory.create(recursive: true);

    final cachedAssets = <CachedAudioAsset>{};
    var completedAssets = 0;

    for (final asset in assets) {
      final safeFilename = _safeFilename(asset.assetId, asset.filename);
      final targetFile = File('${projectDirectory.path}/$safeFilename');
      final partialFile = File('${targetFile.path}.part');
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      await downloadAsset(asset, partialFile.path, (received, total) {
        onProgress?.call(
          AudioDownloadProgress(
            completedAssets: completedAssets,
            totalAssets: assets.length,
            activeAssetId: asset.assetId,
            receivedBytes: received,
            totalBytes: total,
          ),
        );
      });

      if (asset.sizeBytes != null) {
        final fileLength = await partialFile.length();
        if (fileLength != asset.sizeBytes) {
          await partialFile.delete();
          throw StateError(
            'Downloaded audio size mismatch for ${asset.assetId}. Expected ${asset.sizeBytes}, got $fileLength.',
          );
        }
      }

      if (asset.checksumSha256 != null) {
        final checksum = await _sha256ForFile(partialFile);
        if (checksum != asset.checksumSha256) {
          await partialFile.delete();
          throw StateError(
            'Downloaded audio checksum mismatch for ${asset.assetId}.',
          );
        }
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partialFile.rename(targetFile.path);

      final cachedAt = DateTime.now().toUtc();
      cachedAssets.add(
        CachedAudioAsset(
          assetId: asset.assetId,
          filePath: targetFile.path,
          cachedAt: cachedAt,
          sizeBytes: asset.sizeBytes,
          checksumSha256: asset.checksumSha256,
          durationMs: asset.durationMs,
        ),
      );
      completedAssets += 1;
      onProgress?.call(
        AudioDownloadProgress(
          completedAssets: completedAssets,
          totalAssets: assets.length,
          activeAssetId: asset.assetId,
          receivedBytes: asset.sizeBytes ?? 0,
          totalBytes: asset.sizeBytes ?? 0,
        ),
      );
    }

    await _writeManifest(projectId, cachedAssets.toList(growable: false));
    return inspectProject(
      projectId,
      expectedAssetIds: [for (final asset in assets) asset.assetId],
    );
  }

  @override
  Future<void> removeProject(String projectId) async {
    final directory = await _projectDirectory(projectId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _writeManifest(
    String projectId,
    List<CachedAudioAsset> assets,
  ) async {
    final manifestFile = await _manifestFile(projectId);
    await manifestFile.parent.create(recursive: true);
    final payload = {
      'project_id': projectId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'assets': [
        for (final asset in assets)
          {
            'asset_id': asset.assetId,
            'file_path': asset.filePath,
            'cached_at': asset.cachedAt.toIso8601String(),
            'size_bytes': asset.sizeBytes,
            'checksum_sha256': asset.checksumSha256,
            'duration_ms': asset.durationMs,
          },
      ],
    };
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<Directory> _cacheRoot() async {
    if (baseDirectory != null) {
      return baseDirectory!;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/sync_audio_cache');
  }

  Future<Directory> _projectDirectory(String projectId) async {
    final root = await _cacheRoot();
    return Directory('${root.path}/projects/$projectId');
  }

  Future<File> _manifestFile(String projectId) async {
    final directory = await _projectDirectory(projectId);
    return File('${directory.path}/audio_manifest.json');
  }
}

CachedAudioAsset? _parseAsset(Object? value) {
  if (value is! Map) {
    return null;
  }
  final map = Map<String, dynamic>.from(value);
  final assetId = map['asset_id']?.toString();
  final filePath = map['file_path']?.toString();
  if (assetId == null ||
      assetId.isEmpty ||
      filePath == null ||
      filePath.isEmpty) {
    return null;
  }
  final cachedAt =
      DateTime.tryParse(map['cached_at']?.toString() ?? '')?.toUtc() ??
      DateTime.now().toUtc();
  return CachedAudioAsset(
    assetId: assetId,
    filePath: filePath,
    cachedAt: cachedAt,
    sizeBytes: _asInt(map['size_bytes']),
    checksumSha256: map['checksum_sha256']?.toString(),
    durationMs: _asInt(map['duration_ms']),
  );
}

String _safeFilename(String assetId, String filename) {
  final cleaned = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return '${assetId}_$cleaned';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Future<String> _sha256ForFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
