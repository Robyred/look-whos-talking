import numpy as np
import whisperx

SAMPLE_RATE = 16_000
_model = None


def _get_model():
    global _model
    if _model is None:
        # "small" is accurate enough for clean speech and fits in ~1 GB RAM.
        # device="cpu" works everywhere; change to "cuda" if a GPU is available.
        _model = whisperx.load_model("small", device="cpu", compute_type="int8")
    return _model


def transcribe(
    audio: np.ndarray,
    timeline: list[tuple[str, float, float]],
    language: str | None = None,
) -> list[dict]:
    """
    Return a list of utterance dicts: {speaker_id, start, end, text}.

    language: ISO 639-1 code (e.g. "en", "fr"). Pass None to auto-detect.
      Auto-detection is unreliable on short clips — accented English is
      frequently misclassified as Welsh, Irish, etc. Pass an explicit
      language code whenever it is known.

    Steps:
      1. Run faster-whisper to get word-level transcription.
      2. Run forced alignment to pin each word to a precise timestamp.
      3. Assign each word to a speaker using the diarization timeline.
      4. Group consecutive same-speaker words into utterances.
    """
    model = _get_model()

    # whisperx expects float32 numpy audio
    audio_f32 = audio.astype(np.float32)
    kwargs = {"batch_size": 8}
    if language:
        kwargs["language"] = language
    result = model.transcribe(audio_f32, **kwargs)

    # Step 2: align to get word-level timestamps.
    # Falls back to segment-level timestamps if no alignment model exists for
    # the detected language (e.g. Welsh, minority languages).
    try:
        align_model, metadata = whisperx.load_align_model(
            language_code=result["language"], device="cpu"
        )
        aligned = whisperx.align(
            result["segments"], align_model, metadata, audio_f32, device="cpu"
        )
        word_segments = aligned["word_segments"]
    except ValueError:
        # No alignment model for this language — synthesise word entries from
        # segment-level timestamps so the rest of the pipeline still works.
        word_segments = [
            {"word": w, "start": seg["start"], "end": seg["end"]}
            for seg in result["segments"]
            for w in seg["text"].strip().split()
        ]

    # Step 3: assign each word to a speaker from the timeline
    words_with_speakers = _assign_speakers(word_segments, timeline)

    # Step 4: group into utterances
    return _group_utterances(words_with_speakers)


def _assign_speakers(
    word_segments: list[dict],
    timeline: list[tuple[str, float, float]],
) -> list[dict]:
    """
    For each word, find the speaker whose segment overlaps it most.
    Falls back to nearest speaker if no overlap exists.
    """
    labelled = []
    for word in word_segments:
        start = word.get("start", 0.0)
        end = word.get("end", start + 0.1)
        text = word.get("word", "").strip()
        if not text:
            continue

        best_speaker = _find_speaker(start, end, timeline)
        labelled.append({"speaker_id": best_speaker, "start": start, "end": end, "word": text})

    return labelled


def _find_speaker(
    word_start: float,
    word_end: float,
    timeline: list[tuple[str, float, float]],
) -> str:
    best_speaker = "UNKNOWN"
    best_overlap = -1.0

    for speaker, seg_start, seg_end in timeline:
        overlap = min(word_end, seg_end) - max(word_start, seg_start)
        if overlap > best_overlap:
            best_overlap = overlap
            best_speaker = speaker

    return best_speaker


def _group_utterances(words: list[dict]) -> list[dict]:
    """
    Merge consecutive words from the same speaker into single utterance dicts.
    """
    if not words:
        return []

    utterances = []
    current = {
        "speaker_id": words[0]["speaker_id"],
        "start": words[0]["start"],
        "end": words[0]["end"],
        "words": [words[0]["word"]],
    }

    for w in words[1:]:
        if w["speaker_id"] == current["speaker_id"]:
            current["words"].append(w["word"])
            current["end"] = w["end"]
        else:
            utterances.append(_finalise(current))
            current = {
                "speaker_id": w["speaker_id"],
                "start": w["start"],
                "end": w["end"],
                "words": [w["word"]],
            }

    utterances.append(_finalise(current))
    return utterances


def _finalise(current: dict) -> dict:
    return {
        "speaker_id": current["speaker_id"],
        "start": round(current["start"], 3),
        "end": round(current["end"], 3),
        "text": " ".join(current["words"]),
    }
