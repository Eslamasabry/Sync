from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any

from sync_backend.alignment.epub import TOKEN_RE, normalize_token


@dataclass(slots=True)
class ReaderTokenRef:
    section_id: str
    paragraph_index: int
    token_index: int
    text: str
    normalized: str
    cfi: str | None


def flatten_reader_model(reader_model: dict[str, Any]) -> list[ReaderTokenRef]:
    tokens: list[ReaderTokenRef] = []
    for section in reader_model.get("sections", []):
        for paragraph in section.get("paragraphs", []):
            for token in paragraph.get("tokens", []):
                tokens.append(
                    ReaderTokenRef(
                        section_id=section["id"],
                        paragraph_index=paragraph["index"],
                        token_index=token["index"],
                        text=token["text"],
                        normalized=token["normalized"],
                        cfi=token.get("cfi"),
                    )
                )
    return tokens


def flatten_transcript_words(transcript_payload: dict[str, Any]) -> list[dict[str, Any]]:
    words: list[dict[str, Any]] = []
    for segment in transcript_payload.get("segments", []):
        for word in segment.get("words", []):
            words.append(
                {
                    "asset_id": segment["asset_id"],
                    "segment_index": segment["segment_index"],
                    "text": word["text"],
                    "normalized": normalize_transcript_word(str(word["text"])),
                    "start_ms": word["start_ms"],
                    "end_ms": word["end_ms"],
                    "confidence": word["confidence"],
                }
            )
    return words


def normalize_transcript_word(word: str) -> str:
    matches = TOKEN_RE.findall(word)
    if not matches:
        return normalize_token(word)
    return " ".join(normalize_token(match) for match in matches)


def _ratio(left: str, right: str) -> float:
    return SequenceMatcher(a=left, b=right, autojunk=False).ratio()


def _local_fuzzy_match(
    transcript_words: list[dict[str, Any]],
    reader_tokens: list[ReaderTokenRef],
    *,
    transcript_start: int,
    transcript_end: int,
    reader_start: int,
    reader_end: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    matches: list[dict[str, Any]] = []
    gaps: list[dict[str, Any]] = []
    reader_cursor = reader_start

    for transcript_index in range(transcript_start, transcript_end):
        transcript_word = transcript_words[transcript_index]
        best_index: int | None = None
        best_score = 0.0

        for candidate_index in range(reader_cursor, reader_end):
            score = _ratio(
                transcript_word["normalized"],
                reader_tokens[candidate_index].normalized,
            )
            if score > best_score:
                best_score = score
                best_index = candidate_index

            if score == 1.0:
                break

        if best_index is not None and best_score >= 0.72:
            token = reader_tokens[best_index]
            matches.append(
                {
                    "transcript_index": transcript_index,
                    "word": transcript_word["text"],
                    "normalized": transcript_word["normalized"],
                    "start_ms": transcript_word["start_ms"],
                    "end_ms": transcript_word["end_ms"],
                    "confidence": round(best_score, 4),
                    "location": {
                        "section_id": token.section_id,
                        "paragraph_index": token.paragraph_index,
                        "token_index": token.token_index,
                        "cfi": token.cfi,
                    },
                }
            )
            reader_cursor = best_index + 1
        else:
            gaps.append(
                {
                    "transcript_index": transcript_index,
                    "word": transcript_word["text"],
                    "start_ms": transcript_word["start_ms"],
                    "end_ms": transcript_word["end_ms"],
                    "reason": "narration_mismatch",
                }
            )

    return matches, gaps


def match_transcript_to_reader_model(
    *,
    transcript_payload: dict[str, Any],
    reader_model: dict[str, Any],
) -> dict[str, Any]:
    transcript_words = flatten_transcript_words(transcript_payload)
    reader_tokens = flatten_reader_model(reader_model)
    transcript_norms = [word["normalized"] for word in transcript_words]
    reader_norms = [token.normalized for token in reader_tokens]

    matcher = SequenceMatcher(a=transcript_norms, b=reader_norms, autojunk=False)
    matches: list[dict[str, Any]] = []
    gaps: list[dict[str, Any]] = []

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            for transcript_index, reader_index in zip(range(i1, i2), range(j1, j2), strict=False):
                transcript_word = transcript_words[transcript_index]
                token = reader_tokens[reader_index]
                matches.append(
                    {
                        "transcript_index": transcript_index,
                        "word": transcript_word["text"],
                        "normalized": transcript_word["normalized"],
                        "start_ms": transcript_word["start_ms"],
                        "end_ms": transcript_word["end_ms"],
                        "confidence": 1.0,
                        "location": {
                            "section_id": token.section_id,
                            "paragraph_index": token.paragraph_index,
                            "token_index": token.token_index,
                            "cfi": token.cfi,
                        },
                    }
                )
        elif tag == "delete":
            for transcript_index in range(i1, i2):
                transcript_word = transcript_words[transcript_index]
                gaps.append(
                    {
                        "transcript_index": transcript_index,
                        "word": transcript_word["text"],
                        "start_ms": transcript_word["start_ms"],
                        "end_ms": transcript_word["end_ms"],
                        "reason": "narration_mismatch",
                    }
                )
        elif tag == "replace":
            local_matches, local_gaps = _local_fuzzy_match(
                transcript_words,
                reader_tokens,
                transcript_start=i1,
                transcript_end=i2,
                reader_start=j1,
                reader_end=j2,
            )
            matches.extend(local_matches)
            gaps.extend(local_gaps)

    matches.sort(key=lambda item: item["start_ms"])
    gaps.sort(key=lambda item: item["start_ms"])
    _classify_boundary_gaps(matches=matches, gaps=gaps)
    average_confidence = (
        sum(match["confidence"] for match in matches) / len(matches) if matches else None
    )

    return {
        "version": "1.0",
        "project_id": transcript_payload["project_id"],
        "job_id": transcript_payload["job_id"],
        "match_count": len(matches),
        "gap_count": len(gaps),
        "average_confidence": average_confidence,
        "matches": matches,
        "gaps": gaps,
    }


def _classify_boundary_gaps(
    *,
    matches: list[dict[str, Any]],
    gaps: list[dict[str, Any]],
) -> None:
    if not matches:
        return

    first_match_index = min(int(match["transcript_index"]) for match in matches)
    last_match_index = max(int(match["transcript_index"]) for match in matches)

    for gap in gaps:
        transcript_index = int(gap["transcript_index"])
        if transcript_index < first_match_index:
            gap["reason"] = "audiobook_front_matter"
        elif transcript_index > last_match_index:
            gap["reason"] = "audiobook_end_matter"
