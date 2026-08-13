import numpy as np
import soundfile as sf
import tempfile
from pathlib import Path


SAMPLE_RATE = 16000


def make_speaker_tone(frequency: float, duration_sec: float) -> np.ndarray:
    t = np.linspace(0, duration_sec, int(SAMPLE_RATE * duration_sec), endpoint=False)
    return (0.3 * np.sin(2 * np.pi * frequency * t)).astype(np.float32)


def make_two_speaker_wav(tmp_path: Path) -> tuple[Path, list[tuple[str, float, float]]]:
    """
    Build a 30-second WAV with two speakers taking strict turns.
    Returns the file path and the ground-truth timeline.

    Speaker A: 440 Hz  (segments 0-5s, 10-15s, 20-25s)
    Speaker B: 880 Hz  (segments 5-10s, 15-20s, 25-30s)
    Silence gaps: none — speakers hand off cleanly at boundaries.
    """
    segments = [
        ("A", 440.0, 0.0,  5.0),
        ("B", 880.0, 5.0,  10.0),
        ("A", 440.0, 10.0, 15.0),
        ("B", 880.0, 15.0, 20.0),
        ("A", 440.0, 20.0, 25.0),
        ("B", 880.0, 25.0, 30.0),
    ]

    audio = np.concatenate([
        make_speaker_tone(freq, end - start)
        for _, freq, start, end in segments
    ])

    path = tmp_path / "two_speakers.wav"
    sf.write(str(path), audio, SAMPLE_RATE)

    ground_truth = [(speaker, start, end) for speaker, _, start, end in segments]
    return path, ground_truth


def make_silent_wav(tmp_path: Path, duration_sec: float = 5.0) -> Path:
    audio = np.zeros(int(SAMPLE_RATE * duration_sec), dtype=np.float32)
    path = tmp_path / "silent.wav"
    sf.write(str(path), audio, SAMPLE_RATE)
    return path


def make_single_speaker_wav(tmp_path: Path, duration_sec: float = 10.0) -> tuple[Path, list[tuple[str, float, float]]]:
    audio = make_speaker_tone(440.0, duration_sec)
    path = tmp_path / "one_speaker.wav"
    sf.write(str(path), audio, SAMPLE_RATE)
    ground_truth = [("A", 0.0, duration_sec)]
    return path, ground_truth
