# Look Who's Talking — Claude Context

## Project
Voice diarisation app (cocktail party problem). Upload an audio conversation → identify speakers → show % speaking time per speaker → offer per-speaker transcription.

## Always-active skills
- **learn-with-ai-tutor**: Teach one idea at a time. Explain the *why* behind every design decision. No jargon without definition. Drive with small exercises, not "does that make sense?"
- **test-every-function**: State success criteria before writing a function. Test every function independently. Cover the happy path, empty/zero/one case, boundary, and the silent-failure trap. Never declare done past what can be verified.

## Architecture
```
audio_processor/   # Load and normalise audio → 16kHz mono
diarization/       # Embeddings → clustering → speaker timeline
metrics/           # Speaking time %, DER, overlap detection
backend/           # FastAPI: POST /diarize, GET /conversations
data/samples/      # Pre-downloaded labelled test audio
data/results/      # JSON output from diarization runs
tests/             # Unit tests, one file per module
```

## Stack
- Audio: librosa, soundfile, scipy.signal
- Diarisation: pyannote.audio (PyTorch)
- API: FastAPI + Pydantic
- Testing: pytest
- Containerisation: Docker (for later Flutter backend)

## Conventions
- Python 3.11+
- No comments unless the *why* is non-obvious
- Each layer tested independently before wiring to the next
- Prefer small, single-responsibility functions
- Target metrics: DER (Diarisation Error Rate), JER, speaking time %

## Phase plan
1. Python MVP — backend + API, tested against sample conversations
2. Simple web UI — list samples, then upload
3. Flutter mobile port
4. Rust/C for compute-heavy bottlenecks (profile first)
