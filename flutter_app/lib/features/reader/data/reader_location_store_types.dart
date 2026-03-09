class ReaderLocationSnapshot {
  const ReaderLocationSnapshot({
    required this.projectId,
    required this.positionMs,
    required this.totalDurationMs,
    required this.contentStartMs,
    required this.contentEndMs,
    required this.progressFraction,
    required this.updatedAt,
    this.sectionId,
    this.sectionTitle,
  });

  final String projectId;
  final int positionMs;
  final int totalDurationMs;
  final int contentStartMs;
  final int contentEndMs;
  final double progressFraction;
  final DateTime updatedAt;
  final String? sectionId;
  final String? sectionTitle;

  Map<String, dynamic> toJson() {
    return {
      'project_id': projectId,
      'position_ms': positionMs,
      'total_duration_ms': totalDurationMs,
      'content_start_ms': contentStartMs,
      'content_end_ms': contentEndMs,
      'progress_fraction': progressFraction,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'section_id': sectionId,
      'section_title': sectionTitle,
    };
  }

  factory ReaderLocationSnapshot.fromJson(Map<String, dynamic> json) {
    return ReaderLocationSnapshot(
      projectId: json['project_id'] as String? ?? '',
      positionMs: _asInt(json['position_ms']),
      totalDurationMs: _asInt(json['total_duration_ms']),
      contentStartMs: _asInt(json['content_start_ms']),
      contentEndMs: _asInt(json['content_end_ms']),
      progressFraction: _asDouble(json['progress_fraction']),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      sectionId: json['section_id'] as String?,
      sectionTitle: json['section_title'] as String?,
    );
  }
}

abstract class ReaderLocationStore {
  Future<ReaderLocationSnapshot?> loadProject(String projectId);

  Future<List<ReaderLocationSnapshot>> loadRecent();

  Future<void> storeProject(ReaderLocationSnapshot snapshot);

  Future<void> removeProject(String projectId);
}

class NoopReaderLocationStore implements ReaderLocationStore {
  const NoopReaderLocationStore();

  @override
  Future<ReaderLocationSnapshot?> loadProject(String projectId) async => null;

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async =>
      const <ReaderLocationSnapshot>[];

  @override
  Future<void> removeProject(String projectId) async {}

  @override
  Future<void> storeProject(ReaderLocationSnapshot snapshot) async {}
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return 0;
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}
