from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from diarization.embedder import diarise
import diarization.embedder as embedder_module


def make_fake_pipeline_result(segments):
    """
    Build a mock object that behaves like pyannote's Annotation.
    segments: list of (speaker_label, start, end)
    """
    mock_result = MagicMock()
    mock_result.itertracks.return_value = [
        (MagicMock(start=start, end=end), None, speaker)
        for speaker, start, end in segments
    ]
    return mock_result


def make_audio(duration_sec: float = 30.0) -> np.ndarray:
    return np.random.randn(int(16_000 * duration_sec)).astype(np.float32)


@pytest.fixture(autouse=True)
def patch_pipeline():
    fake_pipeline = MagicMock()
    fake_pipeline.return_value = make_fake_pipeline_result([
        ("SPEAKER_00", 0.0, 5.0),
        ("SPEAKER_01", 5.0, 10.0),
        ("SPEAKER_00", 10.0, 15.0),
    ])
    with patch.object(embedder_module, "_pipeline", fake_pipeline):
        yield fake_pipeline


def test_returns_list_of_tuples():
    result = diarise(make_audio())
    assert isinstance(result, list)
    assert all(isinstance(item, tuple) and len(item) == 3 for item in result)


def test_tuple_types_are_str_float_float():
    result = diarise(make_audio())
    for speaker, start, end in result:
        assert isinstance(speaker, str)
        assert isinstance(start, float)
        assert isinstance(end, float)


def test_segments_are_non_negative():
    result = diarise(make_audio())
    for _, start, end in result:
        assert start >= 0.0
        assert end >= 0.0


def test_segment_end_is_after_start():
    result = diarise(make_audio())
    for _, start, end in result:
        assert end > start


def test_speaker_labels_are_strings():
    result = diarise(make_audio())
    speakers = {speaker for speaker, _, _ in result}
    assert all(isinstance(s, str) for s in speakers)


def test_correct_number_of_segments_returned():
    result = diarise(make_audio())
    assert len(result) == 3


def test_missing_hf_token_raises(monkeypatch):
    monkeypatch.setattr(embedder_module, "_pipeline", None)
    monkeypatch.setenv("HF_TOKEN", "")
    with pytest.raises(EnvironmentError, match="HF_TOKEN"):
        diarise(make_audio())
