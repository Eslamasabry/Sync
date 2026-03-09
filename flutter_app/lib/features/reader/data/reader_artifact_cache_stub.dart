// Web and other non-IO targets intentionally fall back to a no-op cache.
import 'package:sync_flutter/features/reader/data/reader_artifact_cache_types.dart';

class FileReaderArtifactCache extends NoopReaderArtifactCache {
  const FileReaderArtifactCache({Object? baseDirectory});
}
