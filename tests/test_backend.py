import io
from unittest.mock import patch, MagicMock

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from backend.main import app
from backend.models import DiarizationResponse
import diarization.embedder as embedder_module
import backend.storage as storage_module

client = TestClient(app)

SAMPLE_RATE = 16_000


def make_wav_bytes(duration_sec: float = 10.0) -> bytes:
    audio = (0.3 * np.sin(2 * np.pi * 440 * np.linspace(0, duration_sec, int(SAMPLE_RATE * duration_sec)))).astype(np.float32)
    buf = io.BytesIO()
    sf.write(buf, audio, SAMPLE_RATE, format="WAV")
    return buf.getvalue()


def fake_diarise(audio):
    return [("SPEAKER_00", 0.0, 5.0), ("SPEAKER_01", 5.0, 10.0)]


@pytest.fixture(autouse=True)
def patch_embedder():
    with patch.object(embedder_module, "_pipeline", MagicMock()):
        with patch("backend.routes.diarise", side_effect=fake_diarise):
            yield


@pytest.fixture(autouse=True)
def patch_storage(tmp_path):
    with patch.object(storage_module, "RESULTS_DIR", tmp_path):
        yield


def test_diarize_returns_200():
    response = client.post(
        "/diarize",
        files={"file": ("test.wav", make_wav_bytes(), "audio/wav")},
    )
    assert response.status_code == 200


def test_diarize_response_shape():
    response = client.post(
        "/diarize",
        files={"file": ("test.wav", make_wav_bytes(), "audio/wav")},
    )
    body = response.json()
    assert "speakers" in body
    assert "timeline" in body
    assert "speaker_count" in body
    assert body["speaker_count"] == 2


def test_diarize_saves_result(tmp_path):
    with patch.object(storage_module, "RESULTS_DIR", tmp_path):
        client.post(
            "/diarize",
            files={"file": ("convo.wav", make_wav_bytes(), "audio/wav")},
        )
        assert (tmp_path / "convo.wav.json").exists()


def test_get_conversations_empty():
    response = client.get("/conversations")
    assert response.status_code == 200
    assert response.json() == {"conversations": []}


def test_get_conversations_after_upload(tmp_path):
    with patch.object(storage_module, "RESULTS_DIR", tmp_path):
        client.post(
            "/diarize",
            files={"file": ("convo.wav", make_wav_bytes(), "audio/wav")},
        )
        response = client.get("/conversations")
        assert response.status_code == 200
        assert len(response.json()["conversations"]) == 1
        assert response.json()["conversations"][0]["filename"] == "convo.wav"


def test_diarize_rejects_silent_audio():
    silent = np.zeros(int(SAMPLE_RATE * 10), dtype=np.float32)
    buf = io.BytesIO()
    sf.write(buf, silent, SAMPLE_RATE, format="WAV")
    response = client.post(
        "/diarize",
        files={"file": ("silent.wav", buf.getvalue(), "audio/wav")},
    )
    assert response.status_code == 400
    assert "silent" in response.json()["detail"].lower()
