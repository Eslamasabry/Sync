from __future__ import annotations

import contextlib
import shutil
import subprocess
import wave
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

from sync_backend.models import Asset
from sync_backend.storage import FileObjectStore


class AudioProcessingError(RuntimeError):
    pass


@dataclass(slots=True)
class PreparedAudioSegment:
    asset_id: str
    segment_index: int
    storage_path: str
    absolute_path: Path
    start_ms: int
    end_ms: int
    duration_ms: int


class AudioPreprocessor:
    def __init__(
        self,
        *,
        object_store: FileObjectStore,
        ffmpeg_bin: str,
        ffprobe_bin: str,
        chunk_duration_ms: int,
    ) -> None:
        self.object_store = object_store
        self.ffmpeg_bin = ffmpeg_bin
        self.ffprobe_bin = ffprobe_bin
        self.chunk_duration_ms = chunk_duration_ms

    def prepare_asset(self, *, project_id: str, asset: Asset) -> list[PreparedAudioSegment]:
        if asset.storage_path is None:
            raise AudioProcessingError(f"Asset {asset.id} does not have a stored payload")

        source_path = self.object_store.absolute_path(asset.storage_path)
        suffix = source_path.suffix.lower()
        if suffix == ".wav":
            return self._prepare_wav(
                project_id=project_id,
                asset=asset,
                source_path=source_path,
            )
        return self._prepare_with_ffmpeg(
            project_id=project_id,
            asset=asset,
            source_path=source_path,
        )

    def _prepare_wav(
        self,
        *,
        project_id: str,
        asset: Asset,
        source_path: Path,
    ) -> list[PreparedAudioSegment]:
        with contextlib.closing(wave.open(str(source_path), "rb")) as wav_file:
            frame_rate = wav_file.getframerate()
            total_frames = wav_file.getnframes()
            params = wav_file.getparams()

            frames_per_chunk = max(1, int((self.chunk_duration_ms / 1000) * frame_rate))
            segments: list[PreparedAudioSegment] = []
            for segment_index, frame_start in enumerate(range(0, total_frames, frames_per_chunk)):
                wav_file.setpos(frame_start)
                frame_count = min(frames_per_chunk, total_frames - frame_start)
                frames = wav_file.readframes(frame_count)
                duration_ms = int((frame_count / frame_rate) * 1000)
                start_ms = int((frame_start / frame_rate) * 1000)
                end_ms = start_ms + duration_ms

                buffer = BytesIO()
                with contextlib.closing(wave.open(buffer, "wb")) as segment_file:
                    segment_file.setparams(params)
                    segment_file.writeframes(frames)

                storage_path, _ = self.object_store.write_bytes(
                    (
                        f"projects/{project_id}/artifacts/audio/{asset.id}/"
                        f"segment-{segment_index:04d}.wav"
                    ),
                    buffer.getvalue(),
                )
                segments.append(
                    PreparedAudioSegment(
                        asset_id=asset.id,
                        segment_index=segment_index,
                        storage_path=storage_path,
                        absolute_path=self.object_store.absolute_path(storage_path),
                        start_ms=start_ms,
                        end_ms=end_ms,
                        duration_ms=duration_ms,
                    )
                )

        if not segments:
            raise AudioProcessingError(f"Asset {asset.id} did not produce any audio segments")
        return segments

    def _prepare_with_ffmpeg(
        self,
        *,
        project_id: str,
        asset: Asset,
        source_path: Path,
    ) -> list[PreparedAudioSegment]:
        ffmpeg_path = shutil.which(self.ffmpeg_bin)
        ffprobe_path = shutil.which(self.ffprobe_bin)
        if ffmpeg_path is None or ffprobe_path is None:
            raise AudioProcessingError(
                "ffmpeg and ffprobe are required for non-WAV audio preprocessing"
            )

        total_duration_ms = self._probe_duration_ms(
            ffprobe_path=ffprobe_path,
            source_path=source_path,
        )
        segments: list[PreparedAudioSegment] = []
        for segment_index, start_ms in enumerate(
            range(0, total_duration_ms, self.chunk_duration_ms)
        ):
            duration_ms = min(self.chunk_duration_ms, total_duration_ms - start_ms)
            target_path = self.object_store.absolute_path(
                f"projects/{project_id}/artifacts/audio/{asset.id}/"
                f"segment-{segment_index:04d}.wav"
            )
            target_path.parent.mkdir(parents=True, exist_ok=True)

            subprocess.run(
                [
                    ffmpeg_path,
                    "-y",
                    "-i",
                    str(source_path),
                    "-ss",
                    f"{start_ms / 1000:.3f}",
                    "-t",
                    f"{duration_ms / 1000:.3f}",
                    "-ac",
                    "1",
                    "-ar",
                    "16000",
                    str(target_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            storage_path = str(target_path.relative_to(self.object_store.base_path))
            segments.append(
                PreparedAudioSegment(
                    asset_id=asset.id,
                    segment_index=segment_index,
                    storage_path=storage_path,
                    absolute_path=target_path,
                    start_ms=start_ms,
                    end_ms=start_ms + duration_ms,
                    duration_ms=duration_ms,
                )
            )

        return segments

    def _probe_duration_ms(self, *, ffprobe_path: str, source_path: Path) -> int:
        result = subprocess.run(
            [
                ffprobe_path,
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(source_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return int(float(result.stdout.strip()) * 1000)
