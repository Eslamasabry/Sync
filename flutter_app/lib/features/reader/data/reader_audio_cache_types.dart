class AudioDownloadDescriptor {
  const AudioDownloadDescriptor({
    required this.assetId,
    required this.filename,
    required this.downloadUrl,
    this.sizeBytes,
    this.checksumSha256,
    this.durationMs,
  });

  final String assetId;
  final String filename;
  final String downloadUrl;
  final int? sizeBytes;
  final String? checksumSha256;
  final int? durationMs;
}

class AudioDownloadProgress {
  const AudioDownloadProgress({
    required this.completedAssets,
    required this.totalAssets,
    required this.activeAssetId,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int completedAssets;
  final int totalAssets;
  final String? activeAssetId;
  final int receivedBytes;
  final int totalBytes;

  double get fraction {
    final assetProgress = totalBytes <= 0 ? 0.0 : receivedBytes / totalBytes;
    if (totalAssets <= 0) {
      return assetProgress.clamp(0.0, 1.0);
    }
    return ((completedAssets + assetProgress) / totalAssets).clamp(0.0, 1.0);
  }
}

class CachedAudioAsset {
  const CachedAudioAsset({
    required this.assetId,
    required this.filePath,
    required this.cachedAt,
    this.sizeBytes,
    this.checksumSha256,
    this.durationMs,
  });

  final String assetId;
  final String filePath;
  final DateTime cachedAt;
  final int? sizeBytes;
  final String? checksumSha256;
  final int? durationMs;

  String get fileUri => Uri.file(filePath).toString();
}

class CachedProjectAudio {
  const CachedProjectAudio({required this.assetsById, required this.updatedAt});

  final Map<String, CachedAudioAsset> assetsById;
  final DateTime? updatedAt;

  int get assetCount => assetsById.length;

  bool contains(String assetId) => assetsById.containsKey(assetId);
}

abstract class ReaderAudioCache {
  Future<CachedProjectAudio> inspectProject(
    String projectId, {
    Iterable<String>? expectedAssetIds,
  });

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
  });

  Future<void> removeProject(String projectId);
}

class NoopReaderAudioCache implements ReaderAudioCache {
  const NoopReaderAudioCache();

  @override
  Future<CachedProjectAudio> inspectProject(
    String projectId, {
    Iterable<String>? expectedAssetIds,
  }) async => const CachedProjectAudio(assetsById: {}, updatedAt: null);

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
  }) async => const CachedProjectAudio(assetsById: {}, updatedAt: null);

  @override
  Future<void> removeProject(String projectId) async {}
}
