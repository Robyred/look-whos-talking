from collections import defaultdict
from dataclasses import dataclass


@dataclass
class SpeakerStats:
    speaker_id: str
    duration_sec: float
    percentage: float


@dataclass
class ConversationMetrics:
    total_duration_sec: float
    speaker_count: int
    speakers: list[SpeakerStats]
    overlap_sec: float
    speech_sec: float
    silence_sec: float


def _overlap_duration(timeline: list[tuple[str, float, float]]) -> float:
    events = []
    for _, start, end in timeline:
        events.append((start, +1))
        events.append((end, -1))
    events.sort()

    overlap = 0.0
    active = 0
    prev_time = 0.0

    for time, delta in events:
        if active >= 2:
            overlap += time - prev_time
        prev_time = time
        active += delta

    return overlap


def _speech_duration(timeline: list[tuple[str, float, float]]) -> float:
    if not timeline:
        return 0.0
    intervals = sorted((start, end) for _, start, end in timeline)
    merged_end = intervals[0][1]
    speech = 0.0
    prev_start = intervals[0][0]

    for start, end in intervals[1:]:
        if start >= merged_end:
            speech += merged_end - prev_start
            prev_start = start
            merged_end = end
        else:
            merged_end = max(merged_end, end)

    speech += merged_end - prev_start
    return speech


def calculate_metrics(
    timeline: list[tuple[str, float, float]],
    total_duration_sec: float,
) -> ConversationMetrics:
    raw_durations: dict[str, float] = defaultdict(float)
    for speaker, start, end in timeline:
        raw_durations[speaker] += end - start

    speakers = sorted(
        [
            SpeakerStats(
                speaker_id=speaker_id,
                duration_sec=round(duration, 3),
                percentage=round(100.0 * duration / total_duration_sec, 1),
            )
            for speaker_id, duration in raw_durations.items()
        ],
        key=lambda s: s.duration_sec,
        reverse=True,
    )

    speech_sec = _speech_duration(timeline)

    return ConversationMetrics(
        total_duration_sec=round(total_duration_sec, 3),
        speaker_count=len(speakers),
        speakers=speakers,
        overlap_sec=round(_overlap_duration(timeline), 3),
        speech_sec=round(speech_sec, 3),
        silence_sec=round(total_duration_sec - speech_sec, 3),
    )
