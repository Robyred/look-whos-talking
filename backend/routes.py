import logging
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Form, HTTPException, UploadFile

logger = logging.getLogger(__name__)

from audio_processor.loader import load_audio, SAMPLE_RATE
from audio_processor.preprocessor import preprocess
from backend.insights import ask_question, generate_insights
from backend.jobs import create_job, get_job, update_job, upload_path
from backend.models import (
    AskRequest,
    AskResponse,
    ConversationListResponse,
    DiarizationResponse,
    InsightsRequest,
    InsightsResponse,
    JobResponse,
    JobStatus,
    JobStatusResponse,
    SpeakerResponse,
    TranscriptSegment,
)
from backend.storage import list_conversations, save_result
from diarization.embedder import diarise
from metrics.calculator import calculate_metrics
from transcription.transcriber import transcribe

router = APIRouter()


def _run_pipeline(
    job_id: str,
    audio_path: Path,
    filename: str,
    min_speakers: int | None = None,
    max_speakers: int | None = None,
) -> None:
    logger.info("[%s] pipeline start: %s", job_id[:8], filename)
    update_job(job_id, JobStatus.PROCESSING)
    try:
        logger.info("[%s] loading audio", job_id[:8])
        audio = load_audio(audio_path)
        audio = preprocess(audio)
        logger.info(
            "[%s] diarizing (%.1f s audio, min_speakers=%s, max_speakers=%s)",
            job_id[:8], len(audio) / SAMPLE_RATE, min_speakers, max_speakers,
        )
        timeline = diarise(audio, min_speakers=min_speakers, max_speakers=max_speakers)
        total_duration = len(audio) / SAMPLE_RATE
        metrics = calculate_metrics(timeline, total_duration)
        logger.info("[%s] diarization done: %d speaker(s)", job_id[:8], metrics.speaker_count)

        logger.info("[%s] transcribing", job_id[:8])
        utterances = transcribe(audio, timeline)
        logger.info("[%s] transcription done: %d segments", job_id[:8], len(utterances))

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
            transcript=[
                TranscriptSegment(
                    speaker_id=u["speaker_id"],
                    start=u["start"],
                    end=u["end"],
                    text=u["text"],
                )
                for u in utterances
            ],
        )
        save_result(result)
        update_job(job_id, JobStatus.COMPLETE, result=result)
        logger.info("[%s] complete", job_id[:8])
    except Exception as exc:
        logger.exception("[%s] pipeline failed: %s", job_id[:8], exc)
        update_job(job_id, JobStatus.FAILED, error=str(exc))
    finally:
        audio_path.unlink(missing_ok=True)


@router.post("/diarize", response_model=JobResponse, status_code=202)
async def diarize_audio(
    file: UploadFile,
    background_tasks: BackgroundTasks,
    min_speakers: int | None = Form(None),
    max_speakers: int | None = Form(None),
) -> JobResponse:
    filename = file.filename or "upload.wav"
    job = create_job(filename)

    suffix = Path(filename).suffix or ".wav"
    path = upload_path(job.job_id, suffix)
    path.write_bytes(await file.read())

    background_tasks.add_task(
        _run_pipeline, job.job_id, path, filename, min_speakers, max_speakers
    )
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


@router.post("/jobs/{job_id}/insights", response_model=InsightsResponse)
async def get_insights(job_id: str, body: InsightsRequest) -> InsightsResponse:
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    if job.status != JobStatus.COMPLETE or job.result is None:
        raise HTTPException(status_code=400, detail="Job is not complete")
    try:
        return await generate_insights(job.result, body.speaker_names)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Insights generation failed: {exc}")


@router.post("/jobs/{job_id}/ask", response_model=AskResponse)
async def ask_about_job(job_id: str, body: AskRequest) -> AskResponse:
    job = get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    if job.status != JobStatus.COMPLETE or job.result is None:
        raise HTTPException(status_code=400, detail="Job is not complete")
    try:
        return await ask_question(job.result, body.messages, body.speaker_names)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Chat failed: {exc}")
