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
      "start_token_id": 201,
      "end_token_id": 224,
      "reason": "narration_mismatch"
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
- `tokens`: aligned word tokens
- `gaps`: known mismatch or skipped ranges

### Token

- `id`: monotonically increasing integer
- `text`: display form for the reader
- `normalized`: normalized form used in matching
- `start_ms`: inclusive token start time
- `end_ms`: exclusive token end time
- `confidence`: 0 to 1 match quality indicator
- `location`: reverse pointer into the canonical reading model

## Compatibility Policy

- Additive changes are allowed in minor versions.
- Meaning changes require a major version.
- The reader must ignore unknown fields.
