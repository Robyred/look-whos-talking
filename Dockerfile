FROM python:3.11-slim

# System deps for audio processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install CPU-only torch first — keeps the image ~2 GB lighter than the
# CUDA build. Railway Hobby is CPU-only so CUDA would go unused anyway.
RUN pip install --no-cache-dir \
    torch==2.11.0 torchaudio==2.11.0 torchvision==0.26.0 \
    --index-url https://download.pytorch.org/whl/cpu

# Install the rest of the dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code (see .dockerignore for what is excluded)
COPY . .

# Runtime directories — ephemeral, recreated on restart
RUN mkdir -p data/jobs data/uploads data/results

# /model_cache is a Railway persistent volume mounted at deploy time.
# Both HuggingFace (pyannote) and whisperx models are stored here so
# they survive container restarts and don't need to be re-downloaded.
ENV HF_HOME=/model_cache
ENV WHISPER_CACHE=/model_cache/whisper

# Railway injects $PORT. No EXPOSE directive — Railway routes via $PORT
# exclusively and a hardcoded EXPOSE can mislead the platform.
CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8765}"]
