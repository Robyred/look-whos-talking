from enum import Enum

from pydantic import BaseModel


class JobStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETE = "complete"
    FAILED = "failed"


class SpeakerResponse(BaseModel):
    speaker_id: str
    duration_sec: float
    percentage: float


class TranscriptSegment(BaseModel):
    speaker_id: str
    start: float
    end: float
    text: str


class DiarizationResponse(BaseModel):
    filename: str
    total_duration_sec: float
    speaker_count: int
    speakers: list[SpeakerResponse]
    overlap_sec: float
    speech_sec: float
    silence_sec: float
    timeline: list[tuple[str, float, float]]
    transcript: list[TranscriptSegment] = []


class JobResponse(BaseModel):
    job_id: str
    status: JobStatus


class JobStatusResponse(BaseModel):
    job_id: str
    filename: str
    status: JobStatus
    error: str | None = None
    result: DiarizationResponse | None = None


class ConversationSummary(BaseModel):
    filename: str
    total_duration_sec: float
    speaker_count: int


class ConversationListResponse(BaseModel):
    conversations: list[ConversationSummary]


# --- Insights models ---

class SpeakerNameProposal(BaseModel):
    speaker_id: str
    proposed_name: str | None = None


class ActionItem(BaseModel):
    task: str
    assignee: str | None = None
    deadline: str | None = None


class InsightsRequest(BaseModel):
    speaker_names: dict[str, str] = {}


class InsightsResponse(BaseModel):
    speaker_names: list[SpeakerNameProposal]
    action_items: list[ActionItem]
    minutes: str
