import tempfile
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile

from audio_processor.loader import load_audio, SAMPLE_RATE
from audio_processor.preprocessor import preprocess
from backend.models import ConversationListResponse, DiarizationResponse, SpeakerResponse
from backend.storage import list_conversations, save_result
from diarization.embedder import diarise
from metrics.calculator import calculate_metrics

router = APIRouter()


@router.post("/diarize", response_model=DiarizationResponse)
async def diarize_audio(file: UploadFile) -> DiarizationResponse:
    suffix = Path(file.filename).suffix if file.filename else ".wav"

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as tmp:
        tmp.write(await file.read())
        tmp.flush()
        try:
            audio = load_audio(tmp.name)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        audio = preprocess(audio)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        timeline = diarise(audio)
    except EnvironmentError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    total_duration = len(audio) / SAMPLE_RATE
    metrics = calculate_metrics(timeline, total_duration)

    result = DiarizationResponse(
        filename=file.filename or "upload",
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
    return result


@router.get("/conversations", response_model=ConversationListResponse)
async def get_conversations() -> ConversationListResponse:
    return ConversationListResponse(conversations=list_conversations())
