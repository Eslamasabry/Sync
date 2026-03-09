import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';

class CachedReaderProject {
  const CachedReaderProject({
    required this.readerModel,
    required this.syncArtifact,
    required this.cachedAt,
  });

  final ReaderModel readerModel;
  final SyncArtifact syncArtifact;
  final DateTime cachedAt;
}

abstract class ReaderArtifactCache {
  Future<CachedReaderProject?> loadProject(String projectId);

  Future<void> storeProject({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  });
}

class NoopReaderArtifactCache implements ReaderArtifactCache {
  const NoopReaderArtifactCache();

  @override
  Future<CachedReaderProject?> loadProject(String projectId) async => null;

  @override
  Future<void> storeProject({
    required String projectId,
    required ReaderModel readerModel,
    required SyncArtifact syncArtifact,
  }) async {}
}
