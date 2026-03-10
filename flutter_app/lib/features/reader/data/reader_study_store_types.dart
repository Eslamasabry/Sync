enum ReaderStudyEntryType { bookmark, highlight, note }

class ReaderStudyEntry {
  const ReaderStudyEntry({
    required this.id,
    required this.projectId,
    required this.type,
    required this.positionMs,
    required this.createdAt,
    required this.excerpt,
    this.sectionId,
    this.sectionTitle,
    this.note,
  });

  final String id;
  final String projectId;
  final ReaderStudyEntryType type;
  final int positionMs;
  final DateTime createdAt;
  final String excerpt;
  final String? sectionId;
  final String? sectionTitle;
  final String? note;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_id': projectId,
      'type': type.name,
      'position_ms': positionMs,
      'created_at': createdAt.toUtc().toIso8601String(),
      'excerpt': excerpt,
      'section_id': sectionId,
      'section_title': sectionTitle,
      'note': note,
    };
  }

  factory ReaderStudyEntry.fromJson(Map<String, dynamic> json) {
    final typeName =
        json['type'] as String? ?? ReaderStudyEntryType.bookmark.name;
    return ReaderStudyEntry(
      id: json['id'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      type: ReaderStudyEntryType.values.firstWhere(
        (candidate) => candidate.name == typeName,
        orElse: () => ReaderStudyEntryType.bookmark,
      ),
      positionMs: _asInt(json['position_ms']),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      excerpt: json['excerpt'] as String? ?? '',
      sectionId: json['section_id'] as String?,
      sectionTitle: json['section_title'] as String?,
      note: json['note'] as String?,
    );
  }
}

abstract class ReaderStudyStore {
  Future<List<ReaderStudyEntry>> loadProject(String projectId);

  Future<void> saveProject(String projectId, List<ReaderStudyEntry> entries);
}

class NoopReaderStudyStore implements ReaderStudyStore {
  const NoopReaderStudyStore();

  @override
  Future<List<ReaderStudyEntry>> loadProject(String projectId) async =>
      const <ReaderStudyEntry>[];

  @override
  Future<void> saveProject(
    String projectId,
    List<ReaderStudyEntry> entries,
  ) async {}
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
