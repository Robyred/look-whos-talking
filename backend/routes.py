from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, HTTPException, UploadFile

from audio_processor.loader import load_audio, SAMPLE_RATE
from audio_processor.preprocessor import preprocess
from backend.jobs import create_job, get_job, update_job, upload_path
from backend.models import (
    ConversationListResponse,
    DiarizationResponse,
    JobResponse,
    JobStatus,
    JobStatusResponse,
    SpeakerResponse,
)
from backend.storage import list_conversations, save_result
from diarization.embedder import diarise
from metrics.calculator import calculate_metrics

router = APIRouter()


def _run_pipeline(job_id: str, audio_path: Path, filename: str) -> None:
    update_job(job_id, JobStatus.PROCESSING)
    try:
        audio = load_audio(audio_path)
        audio = preprocess(audio)
        timeline = diarise(audio)
        total_duration = len(audio) / SAMPLE_RATE
        metrics = calculate_metrics(timeline, total_duration)

        result = DiarizationResponse(
            filename=filename,
            total_duration_sec=metrics.total_duration_sec,
            speaker_count=metrics.speaker_count,
            speakers=[
                SpeakerResponse(
                    speaker_id=s.speaker_id,
                    duration_sec=s.duration_sec,
                    percentage=s.percentage,
                )
                for s in metrics.speakers
            ],
            overlap_sec=metrics.overlap_sec,
            speech_sec=metrics.speech_sec,
            silence_sec=metrics.silence_sec,
            timeline=timeline,
        )
        save_result(result)
        update_job(job_id, JobStatus.COMPLETE, result=result)
    except Exception as exc:
        update_job(job_id, JobStatus.FAILED, error=str(exc))
    finally:
        audio_path.unlink(missing_ok=True)


@router.post("/diarize", response_model=JobResponse, status_code=202)
async def diarize_audio(
    file: UploadFile, background_tasks: BackgroundTasks
) -> JobResponse:
    filename = file.filename or "upload.wav"
    job = create_job(filename)

    suffix = Path(filename).suffix or ".wav"
    path = upload_path(job.job_id, suffix)
    path.write_bytes(await file.read())

    background_tasks.add_task(_run_pipeline, job.job_id, path, filename)
    return JobResponse(job_id=job.job_id, status=job.status)


@router.get("/jobs/{job_id}", response_model=JobStatusResponse)
async def get_job_status(job_id: str) -> JobStatusResponse:
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    return job


@router.get("/conversations", response_model=ConversationListResponse)
async def get_conversations() -> ConversationListResponse:
    return ConversationListResponse(conversations=list_conversations())
