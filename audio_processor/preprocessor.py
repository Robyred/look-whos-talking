import numpy as np

MIN_DURATION_SEC = 5.0
SILENCE_THRESHOLD = 1e-4
SAMPLE_RATE = 16_000


def validate_audio(audio: np.ndarray) -> None:
    duration = len(audio) / SAMPLE_RATE
    if duration < MIN_DURATION_SEC:
        raise ValueError(f"Audio too short: {duration:.2f}s (minimum {MIN_DURATION_SEC}s)")
    if np.max(np.abs(audio)) < SILENCE_THRESHOLD:
        raise ValueError("Audio appears silent — no speech to diarise")


def normalise_audio(audio: np.ndarray) -> np.ndarray:
    peak = np.max(np.abs(audio))
    if peak == 0:
        return audio
    return audio / peak


def preprocess(audio: np.ndarray) -> np.ndarray:
    validate_audio(audio)
    return normalise_audio(audio)
