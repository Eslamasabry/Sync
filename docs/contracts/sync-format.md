# Sync Artifact Contract

## Purpose

`sync.json` is the stable artifact the Flutter reader consumes for highlighting and seeking.

## Rules

- Times use integer milliseconds.
- Tokens are ordered by playback sequence.
- Each token points back to a canonical reading location.
- Confidence data is preserved for debugging and future review tools.

## Example

```json
{
  "version": "1.0",
  "book_id": "uuid",
  "language": "en",
  "audio": [
    {
      "asset_id": "uuid",
      "offset_ms": 0,
      "duration_ms": 3542331
    }
  ],
  "content_start_ms": 13120,
  "content_end_ms": 3539910,
  "tokens": [
    {
      "id": 0,
      "text": "Call",
      "normalized": "call",
      "start_ms": 1200,
      "end_ms": 1440,
      "confidence": 0.98,
      "location": {
        "section_id": "s1",
        "paragraph_index": 0,
        "token_index": 0,
        "cfi": "/6/2/4"
      }
    }
  ],
  "gaps": [
    {
      "start_ms": 442100,
      "end_ms": 446900,
      "reason": "audiobook_front_matter",
      "transcript_start_index": 201,
      "transcript_end_index": 224,
      "word_count": 6
    }
  ]
}
```

## Field Definitions

### Top-level

- `version`: semantic contract version for the sync format
- `book_id`: project or book identifier
- `language`: BCP 47 language tag when known
- `audio`: list of source audio files with offsets for multipart books
- `content_start_ms`: first matched content token on the playback timeline
- `content_end_ms`: last matched content token on the playback timeline
- `tokens`: aligned word tokens
- `gaps`: known mismatch or skipped ranges on the playback timeline

### Token

- `id`: monotonically increasing integer
- `text`: display form for the reader
- `normalized`: normalized form used in matching
- `start_ms`: inclusive token start time
- `end_ms`: exclusive token end time
- `confidence`: 0 to 1 match quality indicator
- `location`: reverse pointer into the canonical reading model

### Gap

- `start_ms`: inclusive playback start of the unmatched span
- `end_ms`: exclusive playback end of the unmatched span
- `reason`: stable mismatch reason code
  - supported MVP codes: `audiobook_front_matter`, `narration_mismatch`, `audiobook_end_matter`
- `transcript_start_index`: first unmatched transcript token index
- `transcript_end_index`: last unmatched transcript token index
- `word_count`: number of unmatched transcript words represented by the span

## Compatibility Policy

- Additive changes are allowed in minor versions.
- Meaning changes require a major version.
- The reader must ignore unknown fields.
