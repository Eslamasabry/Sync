from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from ebooklib import ITEM_DOCUMENT, epub  # type: ignore[import-untyped]
from lxml import html  # type: ignore[import-untyped]

TOKEN_RE = re.compile(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*")
WHITESPACE_RE = re.compile(r"\s+")


def normalize_token(token: str) -> str:
    collapsed = WHITESPACE_RE.sub(" ", token.strip())
    return collapsed.lower()


def _extract_tokens(text: str) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    for index, match in enumerate(TOKEN_RE.finditer(text)):
        display = match.group(0)
        normalized = normalize_token(display)
        if not normalized:
            continue
        tokens.append(
            {
                "index": index,
                "text": display,
                "normalized": normalized,
                "cfi": None,
            }
        )
    return tokens


def build_reader_model(epub_path: Path, *, book_id: str, language: str | None) -> dict[str, Any]:
    book = epub.read_epub(str(epub_path))
    documents = {
        item.get_id(): item
        for item in book.get_items()
        if item.get_type() == ITEM_DOCUMENT
    }

    sections: list[dict[str, Any]] = []
    section_order = 0

    for itemref_id, _ in book.spine:
        item = documents.get(itemref_id)
        if item is None:
            continue

        document = html.fromstring(item.get_body_content())
        paragraph_nodes = document.xpath("//p[normalize-space()]")
        if not paragraph_nodes:
            paragraph_nodes = document.xpath(
                "//body//*[self::div or self::li or self::blockquote][normalize-space()]"
            )

        paragraphs: list[dict[str, Any]] = []
        for paragraph_index, node in enumerate(paragraph_nodes):
            paragraph_text = " ".join(node.itertext()).strip()
            if not paragraph_text:
                continue
            tokens = _extract_tokens(paragraph_text)
            if not tokens:
                continue
            paragraphs.append({"index": paragraph_index, "tokens": tokens})

        if not paragraphs:
            continue

        title_candidates = document.xpath("//h1[normalize-space()] | //h2[normalize-space()]")
        title = (
            " ".join(title_candidates[0].itertext()).strip()
            if title_candidates
            else Path(item.file_name).stem.replace("-", " ").replace("_", " ").title()
        )

        sections.append(
            {
                "id": f"s{section_order + 1}",
                "title": title,
                "order": section_order,
                "paragraphs": paragraphs,
            }
        )
        section_order += 1

    return {
        "book_id": book_id,
        "title": book.title or Path(epub_path).stem,
        "language": language,
        "sections": sections,
    }
