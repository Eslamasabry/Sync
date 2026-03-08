from sync_backend.alignment.matching import (
    match_transcript_to_reader_model,
    normalize_transcript_word,
)


def _reader_model() -> dict[str, object]:
    return {
        "book_id": "book-1",
        "title": "Test Book",
        "language": "en",
        "sections": [
            {
                "id": "s1",
                "title": "Chapter 1",
                "order": 0,
                "paragraphs": [
                    {
                        "index": 0,
                        "tokens": [
                            {"index": 0, "text": "The", "normalized": "the", "cfi": None},
                            {"index": 1, "text": "yellow", "normalized": "yellow", "cfi": None},
                            {
                                "index": 2,
                                "text": "wallpaper",
                                "normalized": "wallpaper",
                                "cfi": None,
                            },
                        ],
                    }
                ],
            }
        ],
    }


def test_normalize_transcript_word_strips_punctuation() -> None:
    assert normalize_transcript_word("recording.") == "recording"
    assert normalize_transcript_word("I'll") == "i'll"
    assert normalize_transcript_word("wallpaper,") == "wallpaper"


def test_matching_classifies_leading_and_trailing_audiobook_matter() -> None:
    transcript_payload = {
        "version": "1.0",
        "project_id": "project-1",
        "job_id": "job-1",
        "language": "en",
        "segments": [
            {
                "asset_id": "asset-1",
                "segment_index": 0,
                "start_ms": 0,
                "end_ms": 1500,
                "words": [
                    {"text": "This", "start_ms": 0, "end_ms": 100, "confidence": 0.9},
                    {"text": "recording.", "start_ms": 120, "end_ms": 220, "confidence": 0.9},
                    {"text": "The", "start_ms": 300, "end_ms": 380, "confidence": 0.9},
                    {"text": "yellow", "start_ms": 400, "end_ms": 520, "confidence": 0.9},
                    {"text": "wallpaper", "start_ms": 540, "end_ms": 720, "confidence": 0.9},
                    {"text": "thanks.", "start_ms": 900, "end_ms": 1100, "confidence": 0.9},
                ],
            }
        ],
    }

    payload = match_transcript_to_reader_model(
        transcript_payload=transcript_payload,
        reader_model=_reader_model(),
    )

    assert payload["match_count"] == 3
    assert payload["gap_count"] == 3
    gap_reasons = [gap["reason"] for gap in payload["gaps"]]
    assert gap_reasons == [
        "audiobook_front_matter",
        "audiobook_front_matter",
        "audiobook_end_matter",
    ]
