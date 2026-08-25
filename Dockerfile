FROM python:3.11-slim

# System deps for audio processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies first, then force-reinstall our pinned CPU torch build
# on top. whisperx declares a torch version constraint that pip would otherwise
# satisfy by downgrading torch — which breaks torchaudio (ABI mismatch).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir --force-reinstall \
    torch==2.11.0 torchaudio==2.11.0 torchvision==0.26.0 \
    --index-url https://download.pytorch.org/whl/cpu

# The CPU whl for torchaudio does not ship _torchaudio_sox.so, but
# torchaudio's Python code still tries to load it and raises RuntimeError
# when the file is absent. Patch every .py file in torchaudio that
# references _torchaudio_sox to replace that line with a no-op comment.
RUN python3 -c "
import os, re
base = '/usr/local/lib/python3.11/site-packages/torchaudio'
for root, _, files in os.walk(base):
    for fname in files:
        if not fname.endswith('.py'):
            continue
        fpath = os.path.join(root, fname)
        with open(fpath) as f:
            content = f.read()
        if '_torchaudio_sox' not in content:
            continue
        patched = re.sub(r'[^\n]*_torchaudio_sox[^\n]*\n', '# sox disabled (CPU whl has no _torchaudio_sox.so)\n', content)
        if patched != content:
            with open(fpath, 'w') as f:
                f.write(patched)
            print('Patched:', fpath)
"

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
