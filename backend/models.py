from pydantic import BaseModel


class SpeakerResponse(BaseModel):
    speaker_id: str
    duration_sec: float
    percentage: float


class DiarizationResponse(BaseModel):
    filename: str
    total_duration_sec: float
    speaker_count: int
    speakers: list[SpeakerResponse]
    overlap_sec: float
    speech_sec: float
    silence_sec: float
    timeline: list[tuple[str, float, float]]


class ConversationSummary(BaseModel):
    filename: str
    total_duration_sec: float
    speaker_count: int


class ConversationListResponse(BaseModel):
    conversations: list[ConversationSummary]
