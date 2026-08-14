import os
from dotenv import load_dotenv

import numpy as np
import torch
from pyannote.audio import Pipeline

load_dotenv()

_pipeline = None


def _get_pipeline() -> Pipeline:
    global _pipeline
    if _pipeline is None:
        token = os.getenv("HF_TOKEN")
        if not token:
            raise EnvironmentError("HF_TOKEN not set — check your .env file")
        _pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1",
            token=token,
        )
    return _pipeline


def diarise(audio: np.ndarray, sample_rate: int = 16_000) -> list[tuple[str, float, float]]:
    pipeline = _get_pipeline()

    waveform = torch.from_numpy(audio).unsqueeze(0)
    output = pipeline({"waveform": waveform, "sample_rate": sample_rate})
    annotation = output.speaker_diarization

    return [
        (str(speaker), round(segment.start, 3), round(segment.end, 3))
        for segment, _, speaker in annotation.itertracks(yield_label=True)
    ]
