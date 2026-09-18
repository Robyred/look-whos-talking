FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# CPU PyTorch. This image runs on hosts with no NVIDIA GPU (Railway, CI), where
# the CUDA build only adds ~5 GB of inert nvidia-* wheels. requirements-ci.txt is
# the full runtime set pinned to CPU builds, and it resolves without --no-deps.
COPY requirements-ci.txt .
RUN pip install --no-cache-dir -r requirements-ci.txt

COPY . .

RUN mkdir -p data/jobs data/uploads data/results

ENV HF_HOME=/model_cache
ENV WHISPER_CACHE=/model_cache/whisper

CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8765}"]
