import json
import os

from openai import AsyncOpenAI

from backend.models import (
    ActionItem,
    AskResponse,
    ChatMessage,
    DiarizationResponse,
    InsightsResponse,
    SpeakerNameProposal,
)

_BASE_URL = "https://api.deepseek.com"
_MODEL = "deepseek-chat"

_SYSTEM = (
    "You are a meeting analysis assistant. "
    "Always respond with a valid JSON object and nothing else."
)


def _format_transcript(
    result: DiarizationResponse, speaker_names: dict[str, str]
) -> str:
    lines = []
    for seg in result.transcript:
        label = speaker_names.get(seg.speaker_id, seg.speaker_id)
        lines.append(f"{label}: {seg.text.strip()}")
    return "\n".join(lines)


def _build_prompt(
    result: DiarizationResponse, speaker_names: dict[str, str]
) -> str:
    speaker_ids = [s.speaker_id for s in result.speakers]
    transcript = _format_transcript(result, speaker_names)

    return f"""Analyse the following conversation transcript and return a JSON object with exactly these three fields:

"speaker_names": array of objects with "speaker_id" and "proposed_name" (string or null). \
Identify each speaker's real name if it is mentioned anywhere in the conversation. \
Speaker IDs are: {", ".join(speaker_ids)}.

"action_items": array of objects with "task" (string), "assignee" (string or null), \
"deadline" (string or null). Include every task, to-do, commitment, or follow-up action mentioned.

"minutes": string. A structured meeting summary covering: main topics discussed, \
key decisions made, important points raised, any dates or deadlines mentioned, \
and open questions left unresolved.

Transcript:
{transcript}"""


async def generate_insights(
    result: DiarizationResponse,
    speaker_names: dict[str, str],
) -> InsightsResponse:
    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise ValueError("DEEPSEEK_API_KEY environment variable is not configured")

    client = AsyncOpenAI(api_key=api_key, base_url=_BASE_URL)
    completion = await client.chat.completions.create(
        model=_MODEL,
        messages=[
            {"role": "system", "content": _SYSTEM},
            {"role": "user", "content": _build_prompt(result, speaker_names)},
        ],
        response_format={"type": "json_object"},
        temperature=0.2,
    )

    data = json.loads(completion.choices[0].message.content)

    return InsightsResponse(
        speaker_names=[
            SpeakerNameProposal(
                speaker_id=item.get("speaker_id", ""),
                proposed_name=item.get("proposed_name"),
            )
            for item in data.get("speaker_names", [])
        ],
        action_items=[
            ActionItem(
                task=item.get("task", ""),
                assignee=item.get("assignee"),
                deadline=item.get("deadline"),
            )
            for item in data.get("action_items", [])
        ],
        minutes=data.get("minutes", ""),
    )


_CHAT_SYSTEM_TEMPLATE = (
    "You are a helpful assistant answering questions about a conversation transcript. "
    "Answer concisely and only from what is in the transcript. "
    "If the answer cannot be found in the transcript, say so clearly.\n\n"
    "Transcript:\n{transcript}"
)


async def ask_question(
    result: DiarizationResponse,
    messages: list[ChatMessage],
    speaker_names: dict[str, str],
) -> AskResponse:
    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise ValueError("DEEPSEEK_API_KEY environment variable is not configured")

    transcript = _format_transcript(result, speaker_names)
    system = _CHAT_SYSTEM_TEMPLATE.format(transcript=transcript)

    client = AsyncOpenAI(api_key=api_key, base_url=_BASE_URL)
    completion = await client.chat.completions.create(
        model=_MODEL,
        messages=[{"role": "system", "content": system}]
        + [{"role": m.role, "content": m.content} for m in messages],
        temperature=0.3,
    )
    return AskResponse(answer=completion.choices[0].message.content)
