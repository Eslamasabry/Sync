class ReaderLocationSnapshot {
  const ReaderLocationSnapshot({
    required this.apiBaseUrl,
    required this.authToken,
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

  final String apiBaseUrl;
  final String authToken;
  final String projectId;
  final int positionMs;
  final int totalDurationMs;
  final int contentStartMs;
  final int contentEndMs;
  final double progressFraction;
  final DateTime updatedAt;
  final String? sectionId;
  final String? sectionTitle;

  String get normalizedApiBaseUrl => apiBaseUrl.trim();

  String get normalizedProjectId => projectId.trim();

  String get identityKey =>
      '${normalizedApiBaseUrl.toLowerCase()}|$normalizedProjectId';

  String get shortHost {
    final uri = Uri.tryParse(normalizedApiBaseUrl);
    if (uri == null || uri.host.isEmpty) {
      return normalizedApiBaseUrl;
    }
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Map<String, dynamic> toJson() {
    return {
      'api_base_url': apiBaseUrl,
      'auth_token': authToken,
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
      apiBaseUrl: json['api_base_url'] as String? ?? '',
      authToken: json['auth_token'] as String? ?? '',
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
  Future<ReaderLocationSnapshot?> loadProject(
    String projectId, {
    String? apiBaseUrl,
  });

  Future<List<ReaderLocationSnapshot>> loadRecent();

  Future<void> storeProject(ReaderLocationSnapshot snapshot);

  Future<void> removeProject(String projectId, {String? apiBaseUrl});
}

class NoopReaderLocationStore implements ReaderLocationStore {
  const NoopReaderLocationStore();

  @override
  Future<ReaderLocationSnapshot?> loadProject(
    String projectId, {
    String? apiBaseUrl,
  }) async => null;

  @override
  Future<List<ReaderLocationSnapshot>> loadRecent() async =>
      const <ReaderLocationSnapshot>[];

  @override
  Future<void> removeProject(String projectId, {String? apiBaseUrl}) async {}

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
