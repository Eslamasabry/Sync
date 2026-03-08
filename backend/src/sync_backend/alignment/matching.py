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


def _build_unique_window_index(
    norms: list[str],
    *,
    start: int,
    end: int,
    window_size: int,
) -> dict[tuple[str, ...], int]:
    occurrences: dict[tuple[str, ...], list[int]] = {}
    for index in range(start, end - window_size + 1):
        key = tuple(norms[index : index + window_size])
        occurrences.setdefault(key, []).append(index)
    return {
        key: offsets[0]
        for key, offsets in occurrences.items()
        if len(offsets) == 1
    }


def _find_anchor_window(
    transcript_norms: list[str],
    reader_norms: list[str],
    *,
    transcript_start: int,
    transcript_end: int,
    reader_start: int,
    reader_end: int,
    search_from_end: bool,
) -> tuple[int, int, int] | None:
    for window_size in range(6, 2, -1):
        if transcript_end - transcript_start < window_size:
            continue
        if reader_end - reader_start < window_size:
            continue

        reader_index = _build_unique_window_index(
            reader_norms,
            start=reader_start,
            end=reader_end,
            window_size=window_size,
        )
        if not reader_index:
            continue

        if search_from_end:
            transcript_range = range(transcript_end - window_size, transcript_start - 1, -1)
        else:
            transcript_range = range(transcript_start, transcript_end - window_size + 1)

        for transcript_index in transcript_range:
            key = tuple(transcript_norms[transcript_index : transcript_index + window_size])
            reader_index_match = reader_index.get(key)
            if reader_index_match is not None:
                return transcript_index, reader_index_match, window_size

    return None


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


def _append_exact_matches(
    *,
    matches: list[dict[str, Any]],
    transcript_words: list[dict[str, Any]],
    reader_tokens: list[ReaderTokenRef],
    transcript_start: int,
    reader_start: int,
    window_size: int,
) -> None:
    for transcript_index, reader_index in zip(
        range(transcript_start, transcript_start + window_size),
        range(reader_start, reader_start + window_size),
        strict=False,
    ):
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


def _find_internal_anchor_window(
    transcript_norms: list[str],
    reader_norms: list[str],
    *,
    transcript_start: int,
    transcript_end: int,
    reader_start: int,
    reader_end: int,
) -> tuple[int, int, int] | None:
    max_window_size = min(5, transcript_end - transcript_start, reader_end - reader_start)
    for window_size in range(max_window_size, 1, -1):
        transcript_index = _build_unique_window_index(
            transcript_norms,
            start=transcript_start,
            end=transcript_end,
            window_size=window_size,
        )
        if not transcript_index:
            continue

        reader_index = _build_unique_window_index(
            reader_norms,
            start=reader_start,
            end=reader_end,
            window_size=window_size,
        )
        if not reader_index:
            continue

        candidates: list[tuple[int, int, int]] = []
        for key, transcript_offset in transcript_index.items():
            reader_offset = reader_index.get(key)
            if reader_offset is None:
                continue
            diagonal_distance = abs(
                (transcript_offset - transcript_start) - (reader_offset - reader_start)
            )
            candidates.append((diagonal_distance, transcript_offset, reader_offset))

        if candidates:
            _, transcript_offset, reader_offset = min(candidates)
            return transcript_offset, reader_offset, window_size

    return None


def _match_replace_region(
    transcript_words: list[dict[str, Any]],
    reader_tokens: list[ReaderTokenRef],
    transcript_norms: list[str],
    reader_norms: list[str],
    *,
    transcript_start: int,
    transcript_end: int,
    reader_start: int,
    reader_end: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if transcript_start >= transcript_end:
        return [], []

    internal_anchor = _find_internal_anchor_window(
        transcript_norms,
        reader_norms,
        transcript_start=transcript_start,
        transcript_end=transcript_end,
        reader_start=reader_start,
        reader_end=reader_end,
    )
    if internal_anchor is None:
        return _local_fuzzy_match(
            transcript_words,
            reader_tokens,
            transcript_start=transcript_start,
            transcript_end=transcript_end,
            reader_start=reader_start,
            reader_end=reader_end,
        )

    anchor_transcript_index, anchor_reader_index, anchor_window_size = internal_anchor
    matches: list[dict[str, Any]] = []
    gaps: list[dict[str, Any]] = []

    left_matches, left_gaps = _match_replace_region(
        transcript_words,
        reader_tokens,
        transcript_norms,
        reader_norms,
        transcript_start=transcript_start,
        transcript_end=anchor_transcript_index,
        reader_start=reader_start,
        reader_end=anchor_reader_index,
    )
    matches.extend(left_matches)
    gaps.extend(left_gaps)

    _append_exact_matches(
        matches=matches,
        transcript_words=transcript_words,
        reader_tokens=reader_tokens,
        transcript_start=anchor_transcript_index,
        reader_start=anchor_reader_index,
        window_size=anchor_window_size,
    )

    right_matches, right_gaps = _match_replace_region(
        transcript_words,
        reader_tokens,
        transcript_norms,
        reader_norms,
        transcript_start=anchor_transcript_index + anchor_window_size,
        transcript_end=transcript_end,
        reader_start=anchor_reader_index + anchor_window_size,
        reader_end=reader_end,
    )
    matches.extend(right_matches)
    gaps.extend(right_gaps)

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

    matches: list[dict[str, Any]] = []
    gaps: list[dict[str, Any]] = []
    transcript_start = 0
    transcript_end = len(transcript_words)
    reader_start = 0
    reader_end = len(reader_tokens)

    start_anchor = _find_anchor_window(
        transcript_norms,
        reader_norms,
        transcript_start=transcript_start,
        transcript_end=transcript_end,
        reader_start=reader_start,
        reader_end=reader_end,
        search_from_end=False,
    )
    if start_anchor is not None:
        transcript_start, reader_start, _ = start_anchor
        for transcript_index in range(0, transcript_start):
            transcript_word = transcript_words[transcript_index]
            gaps.append(
                {
                    "transcript_index": transcript_index,
                    "word": transcript_word["text"],
                    "start_ms": transcript_word["start_ms"],
                    "end_ms": transcript_word["end_ms"],
                    "reason": "audiobook_front_matter",
                }
            )

    end_anchor = _find_anchor_window(
        transcript_norms,
        reader_norms,
        transcript_start=transcript_start,
        transcript_end=transcript_end,
        reader_start=reader_start,
        reader_end=reader_end,
        search_from_end=True,
    )
    if end_anchor is not None:
        end_transcript_index, end_reader_index, end_window_size = end_anchor
        transcript_end = end_transcript_index + end_window_size
        reader_end = end_reader_index + end_window_size
        for transcript_index in range(transcript_end, len(transcript_words)):
            transcript_word = transcript_words[transcript_index]
            gaps.append(
                {
                    "transcript_index": transcript_index,
                    "word": transcript_word["text"],
                    "start_ms": transcript_word["start_ms"],
                    "end_ms": transcript_word["end_ms"],
                    "reason": "audiobook_end_matter",
                }
            )

    matcher = SequenceMatcher(
        a=transcript_norms[transcript_start:transcript_end],
        b=reader_norms[reader_start:reader_end],
        autojunk=False,
    )

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        i1 += transcript_start
        i2 += transcript_start
        j1 += reader_start
        j2 += reader_start
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
            local_matches, local_gaps = _match_replace_region(
                transcript_words,
                reader_tokens,
                transcript_norms,
                reader_norms,
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
