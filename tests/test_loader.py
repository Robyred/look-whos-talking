import numpy as np
import pytest

from audio_processor.loader import load_audio, SAMPLE_RATE
from tests.fixtures import make_two_speaker_wav, make_silent_wav


def test_returns_float32_array(tmp_path):
    wav, _ = make_two_speaker_wav(tmp_path)
    audio = load_audio(wav)
    assert isinstance(audio, np.ndarray)
    assert audio.dtype == np.float32


def test_output_is_mono(tmp_path):
    wav, _ = make_two_speaker_wav(tmp_path)
    audio = load_audio(wav)
    assert audio.ndim == 1


def test_output_length_matches_duration(tmp_path):
    wav, _ = make_two_speaker_wav(tmp_path)
    audio = load_audio(wav)
    expected_samples = 30 * SAMPLE_RATE
    assert len(audio) == expected_samples


def test_accepts_string_path(tmp_path):
    wav, _ = make_two_speaker_wav(tmp_path)
    audio = load_audio(str(wav))
    assert len(audio) > 0


def test_silent_file_loads_without_error(tmp_path):
    wav = make_silent_wav(tmp_path)
    audio = load_audio(wav)
    assert audio.max() == pytest.approx(0.0)


def test_missing_file_raises_file_not_found(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_audio(tmp_path / "does_not_exist.wav")
