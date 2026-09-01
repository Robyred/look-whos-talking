import logging
import os

import numpy as np
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

_pipeline = None


def _get_pipeline():
    global _pipeline
    if _pipeline is None:
        import torch
        from pyannote.audio import Pipeline

        token = os.getenv("HF_TOKEN")
        if not token:
            raise EnvironmentError("HF_TOKEN not set — check your .env file")
        logger.info("Loading pyannote speaker-diarization-3.1 (downloading if not cached)…")
        _pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            token=token,
        )
        logger.info("pyannote pipeline ready")
    return _pipeline


def warmup() -> None:
    """Load the pipeline at startup so the first job isn't slow."""
    _get_pipeline()


def diarise(
    audio: np.ndarray,
    sample_rate: int = 16_000,
    min_speakers: int | None = None,
    max_speakers: int | None = None,
) -> list[tuple[str, float, float]]:
    import torch

    pipeline = _get_pipeline()

    waveform = torch.from_numpy(audio).unsqueeze(0)
    kwargs: dict = {}
    if min_speakers is not None:
        kwargs["min_speakers"] = min_speakers
    if max_speakers is not None:
        kwargs["max_speakers"] = max_speakers
    output = pipeline({"waveform": waveform, "sample_rate": sample_rate}, **kwargs)
    annotation = output.speaker_diarization

    return [
        (str(speaker), round(segment.start, 3), round(segment.end, 3))
        for segment, _, speaker in annotation.itertracks(yield_label=True)
    ]
