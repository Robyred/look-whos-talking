FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# torch and torchvision: CPU-only build to avoid the ~2 GB CUDA overhead.
# torchaudio: force-reinstall from PyPI at the exact same version so it
# ships with bundled libsox (_torchaudio_sox.so). The CPU whl omits that
# file but the PyPI wheel includes it. Both are built from the same source
# at the same version so the ABI is compatible.
RUN pip install --no-cache-dir --force-reinstall \
    torch==2.11.0 \
    torchvision==0.26.0 \
    --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir --force-reinstall torchaudio==2.11.0

COPY . .

RUN mkdir -p data/jobs data/uploads data/results

ENV HF_HOME=/model_cache
ENV WHISPER_CACHE=/model_cache/whisper

CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8765}"]
