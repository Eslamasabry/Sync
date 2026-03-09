class SyncArtifact {
  SyncArtifact({
    required this.version,
    required this.bookId,
    required this.language,
    required this.audio,
    required this.contentStartMs,
    required this.contentEndMs,
    required this.tokens,
    required this.gaps,
  });

  factory SyncArtifact.fromJson(Map<String, dynamic> json) {
    final tokens = _asObjectList(
      json['tokens'],
    ).map(SyncToken.fromJson).toList(growable: false);
    final contentStartMs =
        _asInt(json['content_start_ms']) ??
        (tokens.isNotEmpty ? tokens.first.startMs : 0);
    final contentEndMs =
        _asInt(json['content_end_ms']) ??
        (tokens.isNotEmpty ? tokens.last.endMs : 0);
    return SyncArtifact(
      version: _asString(json['version']) ?? '1.0',
      bookId: _asString(json['book_id']) ?? '',
      language: _asString(json['language']),
      audio: _asObjectList(
        json['audio'],
      ).map(AudioManifestItem.fromJson).toList(growable: false),
      contentStartMs: contentStartMs < 0 ? 0 : contentStartMs,
      contentEndMs: contentEndMs < contentStartMs
          ? contentStartMs
          : contentEndMs,
      tokens: tokens,
      gaps: _asObjectList(
        json['gaps'],
      ).map(SyncGap.fromJson).toList(growable: false),
    );
  }

  final String version;
  final String bookId;
  final String? language;
  final List<AudioManifestItem> audio;
  final int contentStartMs;
  final int contentEndMs;
  final List<SyncToken> tokens;
  final List<SyncGap> gaps;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'book_id': bookId,
      'language': language,
      'audio': audio.map((item) => item.toJson()).toList(),
      'content_start_ms': contentStartMs,
      'content_end_ms': contentEndMs,
      'tokens': tokens.map((token) => token.toJson()).toList(),
      'gaps': gaps.map((gap) => gap.toJson()).toList(),
    };
  }

  int get totalDurationMs {
    if (audio.isNotEmpty) {
      return audio
          .map((item) => item.offsetMs + item.durationMs)
          .fold<int>(
            0,
            (maxDuration, value) => value > maxDuration ? value : maxDuration,
          );
    }
    if (tokens.isNotEmpty) {
      return tokens.last.endMs;
    }
    return 0;
  }

  bool get hasLeadingMatter => contentStartMs > 0;

  bool get hasTrailingMatter =>
      contentEndMs > 0 && contentEndMs < totalDurationMs;

  double get coverage {
    if (tokens.isEmpty) {
      return 0;
    }
    final contentDuration = (contentEndMs - contentStartMs).clamp(
      0,
      totalDurationMs,
    );
    if (contentDuration == 0) {
      return 0;
    }
    var coveredDuration = 0;
    for (final token in tokens) {
      coveredDuration += (token.endMs - token.startMs).clamp(
        0,
        totalDurationMs,
      );
    }
    return (coveredDuration / contentDuration).clamp(0, 1).toDouble();
  }

  double get matchConfidence {
    if (tokens.isEmpty) {
      return 0;
    }
    final totalConfidence = tokens.fold<double>(
      0,
      (sum, token) => sum + token.confidence,
    );
    return (totalConfidence / tokens.length).clamp(0, 1).toDouble();
  }

  SyncGap? activeGapAt(int positionMs) {
    for (final gap in gaps) {
      if (positionMs >= gap.startMs && positionMs < gap.endMs) {
        return gap;
      }
    }
    return null;
  }
}

class AudioManifestItem {
  AudioManifestItem({
    required this.assetId,
    required this.offsetMs,
    required this.durationMs,
  });

  factory AudioManifestItem.fromJson(Map<String, dynamic> json) {
    return AudioManifestItem(
      assetId: _asString(json['asset_id']) ?? '',
      offsetMs: _asInt(json['offset_ms']) ?? 0,
      durationMs: _asInt(json['duration_ms']) ?? 0,
    );
  }

  final String assetId;
  final int offsetMs;
  final int durationMs;

  Map<String, dynamic> toJson() {
    return {
      'asset_id': assetId,
      'offset_ms': offsetMs,
      'duration_ms': durationMs,
    };
  }
}

class SyncToken {
  SyncToken({
    required this.id,
    required this.text,
    required this.normalized,
    required this.startMs,
    required this.endMs,
    required this.confidence,
    required this.location,
  });

  factory SyncToken.fromJson(Map<String, dynamic> json) {
    final text = _asString(json['text']) ?? '';
    return SyncToken(
      id: _asInt(json['id']) ?? 0,
      text: text,
      normalized: _asString(json['normalized']) ?? text.toLowerCase(),
      startMs: _asInt(json['start_ms']) ?? 0,
      endMs: _asInt(json['end_ms']) ?? 0,
      confidence: _asDouble(json['confidence']) ?? 0,
      location: SyncTokenLocation.fromJson(_asObject(json['location'])),
    );
  }

  final int id;
  final String text;
  final String normalized;
  final int startMs;
  final int endMs;
  final double confidence;
  final SyncTokenLocation location;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'normalized': normalized,
      'start_ms': startMs,
      'end_ms': endMs,
      'confidence': confidence,
      'location': location.toJson(),
    };
  }
}

class SyncTokenLocation {
  SyncTokenLocation({
    required this.sectionId,
    required this.paragraphIndex,
    required this.tokenIndex,
    this.cfi,
  });

  factory SyncTokenLocation.fromJson(Map<String, dynamic> json) {
    return SyncTokenLocation(
      sectionId: _asString(json['section_id']) ?? '',
      paragraphIndex: _asInt(json['paragraph_index']) ?? 0,
      tokenIndex: _asInt(json['token_index']) ?? 0,
      cfi: _asString(json['cfi']),
    );
  }

  final String sectionId;
  final int paragraphIndex;
  final int tokenIndex;
  final String? cfi;

  String get locationKey => '$sectionId:$paragraphIndex:$tokenIndex';

  Map<String, dynamic> toJson() {
    return {
      'section_id': sectionId,
      'paragraph_index': paragraphIndex,
      'token_index': tokenIndex,
      'cfi': cfi,
    };
  }
}

class SyncGap {
  SyncGap({
    required this.startMs,
    required this.endMs,
    required this.reason,
    required this.transcriptStartIndex,
    required this.transcriptEndIndex,
    required this.wordCount,
  });

  factory SyncGap.fromJson(Map<String, dynamic> json) {
    return SyncGap(
      startMs: _asInt(json['start_ms']) ?? 0,
      endMs: _asInt(json['end_ms']) ?? 0,
      reason: _asString(json['reason']) ?? 'narration_mismatch',
      transcriptStartIndex: _asInt(json['transcript_start_index']) ?? 0,
      transcriptEndIndex: _asInt(json['transcript_end_index']) ?? 0,
      wordCount: _asInt(json['word_count']) ?? 0,
    );
  }

  final int startMs;
  final int endMs;
  final String reason;
  final int transcriptStartIndex;
  final int transcriptEndIndex;
  final int wordCount;

  Map<String, dynamic> toJson() {
    return {
      'start_ms': startMs,
      'end_ms': endMs,
      'reason': reason,
      'transcript_start_index': transcriptStartIndex,
      'transcript_end_index': transcriptEndIndex,
      'word_count': wordCount,
    };
  }
}

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asObjectList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.map((item) => _asObject(item)).toList(growable: false);
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
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

double? _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
