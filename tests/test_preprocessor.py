import numpy as np
import pytest

from audio_processor.preprocessor import preprocess, validate_audio, normalise_audio, SAMPLE_RATE, MIN_DURATION_SEC


def make_tone(duration_sec: float, amplitude: float = 0.5) -> np.ndarray:
    samples = int(SAMPLE_RATE * duration_sec)
    t = np.linspace(0, duration_sec, samples, endpoint=False)
    return (amplitude * np.sin(2 * np.pi * 440 * t)).astype(np.float32)


def test_valid_audio_passes_validation():
    audio = make_tone(10.0)
    validate_audio(audio)  # must not raise


def test_too_short_raises_value_error():
    audio = make_tone(MIN_DURATION_SEC - 0.1)
    with pytest.raises(ValueError, match="too short"):
        validate_audio(audio)


def test_silent_audio_raises_value_error():
    audio = np.zeros(SAMPLE_RATE * 10, dtype=np.float32)
    with pytest.raises(ValueError, match="silent"):
        validate_audio(audio)


def test_exactly_minimum_duration_passes():
    audio = make_tone(MIN_DURATION_SEC)
    validate_audio(audio)  # boundary: must not raise


def test_normalise_scales_peak_to_one():
    audio = make_tone(10.0, amplitude=0.3)
    result = normalise_audio(audio)
    assert np.max(np.abs(result)) == pytest.approx(1.0, abs=1e-5)


def test_normalise_all_zeros_returns_zeros():
    audio = np.zeros(SAMPLE_RATE * 10, dtype=np.float32)
    result = normalise_audio(audio)
    assert np.all(result == 0.0)


def test_preprocess_returns_normalised_array():
    audio = make_tone(10.0, amplitude=0.2)
    result = preprocess(audio)
    assert np.max(np.abs(result)) == pytest.approx(1.0, abs=1e-5)


def test_preprocess_rejects_silent_audio():
    audio = np.zeros(SAMPLE_RATE * 10, dtype=np.float32)
    with pytest.raises(ValueError):
        preprocess(audio)
