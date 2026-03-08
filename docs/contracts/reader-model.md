# Reader Model Contract

## Purpose

The reader model is the canonical text structure the Flutter app renders. It is derived from the EPUB by the backend and is separate from `sync.json`.

This contract exists because token highlighting needs stable structure and indices. Raw EPUB HTML is too inconsistent to use as the runtime source of truth in MVP.

## Structure

```json
{
  "book_id": "uuid",
  "title": "Moby-Dick",
  "language": "en",
  "sections": [
    {
      "id": "s1",
      "title": "Loomings",
      "order": 0,
      "paragraphs": [
        {
          "index": 0,
          "tokens": [
            {
              "index": 0,
              "text": "Call",
              "normalized": "call",
              "cfi": "/6/2/4"
            }
          ]
        }
      ]
    }
  ]
}
```

## Rules

- Section and paragraph order are stable.
- Token indices are stable within each paragraph.
- `normalized` follows the same normalization rules used by alignment.
- `cfi` is optional but preferred when available.
- The client must not re-tokenize visible text for sync logic.

## Relationship to Sync Artifact

- The reader model owns visual structure.
- `sync.json` owns timing.
- Sync tokens point back into the reader model by section, paragraph, and token index.

## API Access

The current backend serves the reader model through:

- `GET /v1/projects/{project_id}/reader-model`
