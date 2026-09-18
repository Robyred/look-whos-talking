# Look Who's Talking

Voice diarisation for the cocktail party problem. Upload an audio conversation,
identify who spoke when, get the percentage of speaking time per speaker, then
optionally transcribe each speaker separately.

## What it does

1. Load and normalise audio to 16 kHz mono
2. Generate speaker embeddings and cluster them into a speaker timeline
3. Compute metrics — speaking time %, diarisation error rate (DER), overlap
4. Serve results over a FastAPI backend, with an optional per-speaker transcript

## Requirements

**System packages** (from the `Dockerfile`):

| Package | Why |
|---|---|
| `ffmpeg` | Audio decoding for WhisperX |
| `libsndfile1` | Backing library for `soundfile` |
| `git` | Dependency installs |

On Debian/Ubuntu:

```bash
sudo apt-get update && sudo apt-get install -y ffmpeg libsndfile1 git
```

**Other requirements:**

- Python 3.11 (the project is pinned to 3.11.11; 3.12+ is untested)
- A HuggingFace account with access to the gated diarisation model (below)
- Flutter SDK `^3.13.1` — only needed for the mobile app

## Setup

```bash
git clone git@github.com:Robyred/look-whos-talking.git
cd look-whos-talking

python3.11 -m venv .venv
source .venv/bin/activate

pip install --no-deps -r requirements.lock.txt   # see "Which requirements file?" below

cp .env.example .env
# then fill in HF_TOKEN and DEEPSEEK_API_KEY
```

### Which requirements file?

| File | Use when |
|---|---|
| `requirements-ci.txt` | **Recommended for most installs.** CPU-only PyTorch, 145 pinned packages, resolves cleanly with no flags. Used by CI and the Dockerfile |
| `requirements.lock.txt` | Exact record of the dev machine, including its CUDA PyTorch build. Requires `--no-deps` |
| `requirements.txt` | macOS, ARM, or deliberate upgrades — loose `>=` ranges |

**Start with `requirements-ci.txt`.** It is the full application dependency set
(not a trimmed test-only list), just with CPU instead of CUDA PyTorch:

```bash
pip install -r requirements-ci.txt
```

This works because it pins the one combination every library agrees on —
`torch 2.8.0+cpu`, `torchvision 0.23.0+cpu`, `torchcodec 0.7.0` — so pip's
resolver can solve it. It also drops about 5 GB of `nvidia-*` CUDA wheels that do
nothing without an NVIDIA GPU.

### The lock file (exact dev record)

| File | Use when |
|---|---|
| `requirements.lock.txt` | You need byte-for-byte parity with the original dev machine |

Two things about the lock file are **not optional**:

**1. Install it with `--no-deps`.**

```bash
pip install --no-deps -r requirements.lock.txt
```

A plain `pip install -r` fails with `ResolutionImpossible`, because the recorded
set cannot be solved by pip's resolver:

| Package | whisperx 3.8.6 wants | pyannote-audio 4.0.7 wants | Actually installed |
|---|---|---|---|
| `torch` | `~=2.8.0` | `>=2.8.0` | `2.11.0+cu130` |
| `torchvision` | `~=0.23.0` | — | `0.26.0+cu130` |
| `torchcodec` | `>=0.6.0,<0.8.0` | `>=0.7.0` | `0.16.0` |

The environment satisfies pyannote but violates whisperx's pins. It was built
incrementally and works at runtime, because Python does not enforce packaging
metadata at import time. `--no-deps` installs the recorded set verbatim, which is
complete because `pip freeze` captures the entire transitive closure.

**2. Do not strip the `--extra-index-url` line.**

`torch`, `torchaudio` and `torchvision` are pinned to `+cu130` CUDA builds, which
are **not on PyPI**. Without that line pip fails with
`No matching distribution found for torch==2.11.0+cu130`.

**On macOS or ARM**, use `requirements.txt` instead — the `+cu130` wheels are
Linux x86_64 only.

**On a machine with no NVIDIA GPU** those CUDA wheels are inert anyway — see
`requirements-ci.txt` above, which is the CPU-only equivalent of this file.

### HuggingFace model access (required)

`diarization/embedder.py` reads `HF_TOKEN` and raises `EnvironmentError` if it is
missing. The token must belong to an account that has accepted the conditions
for the gated model:

1. Sign in at [huggingface.co](https://huggingface.co)
2. Visit [`pyannote/speaker-diarization-3.1`](https://huggingface.co/pyannote/speaker-diarization-3.1)
   and accept the user conditions
3. Create a **read** token at <https://huggingface.co/settings/tokens>
4. Put it in `.env` as `HF_TOKEN=hf_...`

Accepting the conditions in step 2 with a *different* account than the token's
owner is the most common cause of a 401 on first run.

## Running

**API server:**

```bash
source .venv/bin/activate
uvicorn backend.main:app --reload --port 8765
```

Endpoints: `GET /health`, `GET /`, `POST /diarize`, `GET /conversations`,
`GET /jobs/{job_id}`, `POST /jobs/{job_id}/insights`, `POST /jobs/{job_id}/ask`.

**Tests:**

```bash
pytest
```

The suite takes about 12 seconds and needs no credentials or network access —
`HF_TOKEN` and `DEEPSEEK_API_KEY` are not required. The pyannote pipeline, the
diarisation call and the WhisperX transcriber are all replaced with test doubles,
so no models are downloaded.

> Transcription itself is **not** covered by these tests: the uploads are
> synthetic tones containing no speech. Real transcription needs a separate test
> driven by actual speech audio.

**Web UI:** open `frontend/index.html`.

**Flutter app:**

```bash
cd flutter_app && flutter run
```

## Project structure

```
audio_processor/   Load and normalise audio → 16kHz mono
diarization/       Embeddings → clustering → speaker timeline
metrics/           Speaking time %, DER, overlap detection
transcription/     WhisperX per-speaker transcription
backend/           FastAPI app: routes, jobs, storage
frontend/          Single-file web UI
flutter_app/       Flutter mobile port (Dart SDK ^3.13.1)
specs/             Design specs and review briefs
scripts/           check_install.sh — dry-run a pip install before committing to it
tests/             One test file per module
data/              Runtime data — NOT in git (see below)
```

## What is not in git

`git clone` gives you 5.4 MB of source, specs and editor config. It does **not**
give you the runtime environment:

| Path | Size | Why it is excluded |
|---|---|---|
| `.venv/` | 8.2 GB | Build artifact — recreate with pip. Platform-specific binaries |
| `data/` | 4.1 GB | Sample audio, uploads, results |
| `.dsh/` | 2.7 GB | Local Flutter SDK + caches |
| `flutter_app/build/` | 1.5 GB | Flutter build output |
| `.env` | 4 KB | Contains `HF_TOKEN` — never commit |

Rebuild the virtualenv rather than copying it. The `nvidia` and `torch` wheels
inside are compiled for Linux x86_64 and will not work on another platform.

`data/` directories (`jobs`, `results`, `samples`, `uploads`) are created at
runtime; sample audio must be re-downloaded on a fresh machine.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `HF_TOKEN` | Yes | HuggingFace read token for the gated diarisation model |
| `DEEPSEEK_API_KEY` | Yes | `POST /jobs/{id}/insights` and `/ask`. Pointed at `api.deepseek.com`, model `deepseek-chat` |
| `WHISPER_CACHE` | No | Cache directory for WhisperX models |
| `PORT` | No | Server port for the Docker entrypoint (default 8765) |

## Continuous integration

`.github/workflows/tests.yml` runs the suite on every push and pull request, using
`requirements-ci.txt`.

| | |
|---|---|
| Test time | ~12 seconds, plus dependency install |
| Secrets needed | None — the workflow has no configuration |
| Runner | `ubuntu-latest`, Python 3.11 |

Superseded runs on the same branch are cancelled automatically so they do not
consume Actions minutes. On a private repo, GitHub Free includes 2,000 Actions
minutes per month.

## Deployment

`Dockerfile` builds a Python 3.11 slim image with `ffmpeg` and `libsndfile1`
preinstalled, and starts `uvicorn backend.main:app`. Model caches are directed
to `/model_cache` via `HF_HOME` and `WHISPER_CACHE`.

It installs from `requirements-ci.txt` — CPU PyTorch — because the container runs
on hosts with no NVIDIA GPU, where the CUDA build would add ~5 GB for nothing.

`.dockerignore` excludes `.venv/`, `data/`, `.dsh/` and `flutter_app/build/`.
Without those exclusions `COPY . .` would add several GB to the build context.

> **Not yet verified:** the CPU Dockerfile change has not been built — Docker is
> not installed on the machine where it was made. Verify with
> `docker build -t lwt .` and check the resulting size.

`railway.toml` configures Railway deployment with a `/health` healthcheck.
If this repository is private, confirm Railway's GitHub app still has access to
it, or auto-deploy will silently stop.

## Working on this project from a second machine

See `docs/SSH_AND_GITHUB_KEYS.md` for setting up clone access without a password.
