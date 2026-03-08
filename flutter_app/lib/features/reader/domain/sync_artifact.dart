class SyncArtifact {
  SyncArtifact({
    required this.version,
    required this.bookId,
    required this.language,
    required this.audio,
    required this.tokens,
    required this.gaps,
  });

  factory SyncArtifact.fromJson(Map<String, dynamic> json) {
    return SyncArtifact(
      version: json['version'] as String,
      bookId: json['book_id'] as String,
      language: json['language'] as String?,
      audio: (json['audio'] as List<dynamic>)
          .map(
            (item) => AudioManifestItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      tokens: (json['tokens'] as List<dynamic>)
          .map((item) => SyncToken.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      gaps: (json['gaps'] as List<dynamic>)
          .map((item) => SyncGap.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String version;
  final String bookId;
  final String? language;
  final List<AudioManifestItem> audio;
  final List<SyncToken> tokens;
  final List<SyncGap> gaps;

  int get totalDurationMs {
    if (audio.isNotEmpty) {
      return audio.last.offsetMs + audio.last.durationMs;
    }
    if (tokens.isNotEmpty) {
      return tokens.last.endMs;
    }
    return 0;
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
      assetId: json['asset_id'] as String,
      offsetMs: json['offset_ms'] as int,
      durationMs: json['duration_ms'] as int,
    );
  }

  final String assetId;
  final int offsetMs;
  final int durationMs;
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
    return SyncToken(
      id: json['id'] as int,
      text: json['text'] as String,
      normalized: json['normalized'] as String,
      startMs: json['start_ms'] as int,
      endMs: json['end_ms'] as int,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      location: SyncTokenLocation.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
    );
  }

  final int id;
  final String text;
  final String normalized;
  final int startMs;
  final int endMs;
  final double confidence;
  final SyncTokenLocation location;
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
      sectionId: json['section_id'] as String,
      paragraphIndex: json['paragraph_index'] as int,
      tokenIndex: json['token_index'] as int,
      cfi: json['cfi'] as String?,
    );
  }

  final String sectionId;
  final int paragraphIndex;
  final int tokenIndex;
  final String? cfi;

  String get locationKey => '$sectionId:$paragraphIndex:$tokenIndex';
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
      startMs: json['start_ms'] as int,
      endMs: json['end_ms'] as int,
      reason: json['reason'] as String,
      transcriptStartIndex: json['transcript_start_index'] as int,
      transcriptEndIndex: json['transcript_end_index'] as int,
      wordCount: json['word_count'] as int,
    );
  }

  final int startMs;
  final int endMs;
  final String reason;
  final int transcriptStartIndex;
  final int transcriptEndIndex;
  final int wordCount;
}
