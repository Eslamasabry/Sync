from pathlib import Path
from typing import Any, Protocol

from sync_backend.alignment.audio import PreparedAudioSegment
from sync_backend.alignment.transcription import TranscriptWord


class Transcriber(Protocol):
    def transcribe_segment(self, segment: PreparedAudioSegment) -> list[TranscriptWord]: ...


class TextMatcher(Protocol):
    def match(self, transcript: dict[str, Any], book: dict[str, Any]) -> object: ...


class ForcedAligner(Protocol):
    def align(self, matched_spans: object, audio_source: Path) -> object: ...


class SyncExporter(Protocol):
    def export(self, aligned_tokens: object) -> object: ...
