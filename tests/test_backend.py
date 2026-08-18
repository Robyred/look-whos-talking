import io
import time
from unittest.mock import patch, MagicMock

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from backend.main import app
from backend.models import DiarizationResponse, JobStatus
import diarization.embedder as embedder_module
import backend.storage as storage_module
import backend.jobs as jobs_module

client = TestClient(app)

SAMPLE_RATE = 16_000


def make_wav_bytes(duration_sec: float = 10.0) -> bytes:
    audio = (0.3 * np.sin(
        2 * np.pi * 440 * np.linspace(0, duration_sec, int(SAMPLE_RATE * duration_sec))
    )).astype(np.float32)
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
def patch_dirs(tmp_path):
    with patch.object(storage_module, "RESULTS_DIR", tmp_path / "results"):
        with patch.object(jobs_module, "JOBS_DIR", tmp_path / "jobs"):
            with patch.object(jobs_module, "UPLOADS_DIR", tmp_path / "uploads"):
                yield


def submit_file(filename="test.wav", duration=10.0):
    return client.post(
        "/api/diarize",
        files={"file": (filename, make_wav_bytes(duration), "audio/wav")},
    )


def wait_for_terminal(job_id: str, timeout: float = 10.0) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = client.get(f"/api/jobs/{job_id}")
        body = r.json()
        if body["status"] in ("complete", "failed"):
            return body
        time.sleep(0.05)
    raise TimeoutError(f"Job {job_id} did not complete within {timeout}s")


# --- submission ---

def test_diarize_returns_202():
    r = submit_file()
    assert r.status_code == 202


def test_diarize_returns_job_id():
    r = submit_file()
    body = r.json()
    assert "job_id" in body
    assert body["status"] == "pending"


# --- polling ---

def test_job_reaches_complete():
    job_id = submit_file().json()["job_id"]
    result = wait_for_terminal(job_id)
    assert result["status"] == "complete"


def test_complete_job_has_result():
    job_id = submit_file().json()["job_id"]
    result = wait_for_terminal(job_id)
    assert result["result"] is not None
    assert result["result"]["speaker_count"] == 2


def test_complete_job_has_filename():
    job_id = submit_file("convo.wav").json()["job_id"]
    result = wait_for_terminal(job_id)
    assert result["filename"] == "convo.wav"


def test_unknown_job_returns_404():
    r = client.get("/api/jobs/does-not-exist")
    assert r.status_code == 404


# --- failed job ---

def test_failed_job_has_error_message():
    with patch("backend.routes.diarise", side_effect=RuntimeError("model crash")):
        job_id = submit_file().json()["job_id"]
        result = wait_for_terminal(job_id)
    assert result["status"] == "failed"
    assert "model crash" in result["error"]


# --- conversations list ---

def test_conversations_lists_completed_jobs():
    submit_file("a.wav")
    submit_file("b.wav")
    # wait for both
    time.sleep(1.0)
    r = client.get("/api/conversations")
    assert r.status_code == 200
    names = {c["filename"] for c in r.json()["conversations"]}
    assert "a.wav" in names
    assert "b.wav" in names


def test_silent_audio_fails_job():
    silent = np.zeros(int(SAMPLE_RATE * 10), dtype=np.float32)
    buf = io.BytesIO()
    sf.write(buf, silent, SAMPLE_RATE, format="WAV")
    r = client.post(
        "/api/diarize",
        files={"file": ("silent.wav", buf.getvalue(), "audio/wav")},
    )
    job_id = r.json()["job_id"]
    result = wait_for_terminal(job_id)
    assert result["status"] == "failed"
    assert "silent" in result["error"].lower()
