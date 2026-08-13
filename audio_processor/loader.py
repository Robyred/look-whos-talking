from pathlib import Path

import librosa
import numpy as np

SAMPLE_RATE = 16_000


def load_audio(path: str | Path) -> np.ndarray:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Audio file not found: {path}")
    audio, _ = librosa.load(str(path), sr=SAMPLE_RATE, mono=True)
    return audio
