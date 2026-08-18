import uuid
from pathlib import Path

from backend.models import DiarizationResponse, JobStatus, JobStatusResponse

JOBS_DIR = Path(__file__).parent.parent / "data" / "jobs"
UPLOADS_DIR = Path(__file__).parent.parent / "data" / "uploads"


def create_job(filename: str) -> JobStatusResponse:
    JOBS_DIR.mkdir(parents=True, exist_ok=True)
    UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    job = JobStatusResponse(
        job_id=str(uuid.uuid4()),
        filename=filename,
        status=JobStatus.PENDING,
    )
    _save(job)
    return job


def get_job(job_id: str) -> JobStatusResponse | None:
    path = JOBS_DIR / f"{job_id}.json"
    if not path.exists():
        return None
    return JobStatusResponse.model_validate_json(path.read_text())


def update_job(
    job_id: str,
    status: JobStatus,
    result: DiarizationResponse | None = None,
    error: str | None = None,
) -> None:
    job = get_job(job_id)
    if job is None:
        return
    job.status = status
    job.result = result
    job.error = error
    _save(job)


def upload_path(job_id: str, suffix: str) -> Path:
    return UPLOADS_DIR / f"{job_id}{suffix}"


def _save(job: JobStatusResponse) -> None:
    (JOBS_DIR / f"{job.job_id}.json").write_text(job.model_dump_json())
