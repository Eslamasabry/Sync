from typing import Protocol


class Transcriber(Protocol):
    def transcribe(self, source_path: str) -> object: ...


class TextMatcher(Protocol):
    def match(self, transcript: object, book: object) -> object: ...


class ForcedAligner(Protocol):
    def align(self, matched_spans: object, audio_source: str) -> object: ...


class SyncExporter(Protocol):
    def export(self, aligned_tokens: object) -> object: ...
