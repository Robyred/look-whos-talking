import json
from pathlib import Path

from backend.models import DiarizationResponse, ConversationSummary

RESULTS_DIR = Path(__file__).parent.parent / "data" / "results"


def _result_path(filename: str) -> Path:
    return RESULTS_DIR / f"{filename}.json"


def save_result(result: DiarizationResponse) -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    _result_path(result.filename).write_text(result.model_dump_json())


def load_result(filename: str) -> DiarizationResponse | None:
    path = _result_path(filename)
    if not path.exists():
        return None
    return DiarizationResponse.model_validate_json(path.read_text())


def list_conversations() -> list[ConversationSummary]:
    if not RESULTS_DIR.exists():
        return []
    summaries = []
    for path in sorted(RESULTS_DIR.glob("*.json")):
        result = DiarizationResponse.model_validate_json(path.read_text())
        summaries.append(ConversationSummary(
            filename=result.filename,
            total_duration_sec=result.total_duration_sec,
            speaker_count=result.speaker_count,
        ))
    return summaries
