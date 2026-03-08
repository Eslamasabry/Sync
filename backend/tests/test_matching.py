from sync_backend.alignment.matching import (
    match_transcript_to_reader_model,
    normalize_transcript_word,
)
from sync_backend.alignment.sync_export import build_sync_payload


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
    assert payload["matches"][0]["word"] == "The"
    assert payload["matches"][-1]["word"] == "wallpaper"


def test_matching_anchors_across_inserted_narration_drift() -> None:
    reader_model = {
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
                            {"index": 3, "text": "was", "normalized": "was", "cfi": None},
                            {
                                "index": 4,
                                "text": "strangely",
                                "normalized": "strangely",
                                "cfi": None,
                            },
                            {"index": 5, "text": "faded", "normalized": "faded", "cfi": None},
                        ],
                    }
                ],
            }
        ],
    }
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
                "end_ms": 1400,
                "words": [
                    {"text": "The", "start_ms": 0, "end_ms": 80, "confidence": 0.9},
                    {"text": "yellow", "start_ms": 90, "end_ms": 190, "confidence": 0.9},
                    {"text": "wallpaper", "start_ms": 200, "end_ms": 360, "confidence": 0.9},
                    {"text": "briefly", "start_ms": 370, "end_ms": 470, "confidence": 0.9},
                    {"text": "was", "start_ms": 480, "end_ms": 560, "confidence": 0.9},
                    {"text": "strangely", "start_ms": 570, "end_ms": 760, "confidence": 0.9},
                    {"text": "faded", "start_ms": 770, "end_ms": 940, "confidence": 0.9},
                ],
            }
        ],
    }

    payload = match_transcript_to_reader_model(
        transcript_payload=transcript_payload,
        reader_model=reader_model,
    )

    assert payload["match_count"] == 6
    assert payload["gap_count"] == 1
    assert payload["gaps"] == [
        {
            "transcript_index": 3,
            "word": "briefly",
            "start_ms": 370,
            "end_ms": 470,
            "reason": "narration_mismatch",
        }
    ]
    assert [match["word"] for match in payload["matches"]] == [
        "The",
        "yellow",
        "wallpaper",
        "was",
        "strangely",
        "faded",
    ]


def test_build_sync_payload_exposes_quality_stats_and_content_window() -> None:
    transcript_payload = {
        "segments": [
            {
                "asset_id": "asset-1",
                "segment_index": 0,
                "start_ms": 0,
                "end_ms": 1200,
                "words": [],
            }
        ]
    }
    match_payload = {
        "average_confidence": 0.875,
        "matches": [
            {
                "word": "The",
                "normalized": "the",
                "start_ms": 100,
                "end_ms": 180,
                "confidence": 1.0,
                "location": {
                    "section_id": "s1",
                    "paragraph_index": 0,
                    "token_index": 0,
                    "cfi": None,
                },
            },
            {
                "word": "yellow",
                "normalized": "yellow",
                "start_ms": 200,
                "end_ms": 320,
                "confidence": 0.75,
                "location": {
                    "section_id": "s1",
                    "paragraph_index": 0,
                    "token_index": 1,
                    "cfi": None,
                },
            },
        ],
        "gaps": [
            {
                "transcript_index": 2,
                "word": "intro",
                "start_ms": 0,
                "end_ms": 80,
                "reason": "audiobook_front_matter",
            },
            {
                "transcript_index": 3,
                "word": "noise",
                "start_ms": 330,
                "end_ms": 430,
                "reason": "narration_mismatch",
            },
        ],
    }

    payload = build_sync_payload(
        project_id="project-1",
        language="en",
        transcript_payload=transcript_payload,
        match_payload=match_payload,
    )

    assert payload["content_start_ms"] == 100
    assert payload["content_end_ms"] == 320
    assert payload["stats"] == {
        "matched_word_count": 2,
        "unmatched_word_count": 2,
        "transcript_word_count": 4,
        "coverage_ratio": 0.5,
        "average_confidence": 0.875,
        "low_confidence_token_count": 1,
        "content_duration_ms": 220,
    }
