FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir --force-reinstall \
    torch==2.11.0 torchaudio==2.11.0 torchvision==0.26.0 \
    --index-url https://download.pytorch.org/whl/cpu

# The CPU whl omits _torchaudio_sox.so but torchaudio's loader requires
# the file to exist and be dlopen-able. Compile a no-op stub so the load
# succeeds. Our pipeline never calls sox I/O so no sox symbols are needed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && mkdir -p /usr/local/lib/python3.11/site-packages/torchaudio/lib \
    && printf 'void __sox_stub(void){}\n' | gcc -x c - -shared -fPIC \
       -o /usr/local/lib/python3.11/site-packages/torchaudio/lib/_torchaudio_sox.so \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN mkdir -p data/jobs data/uploads data/results

ENV HF_HOME=/model_cache
ENV WHISPER_CACHE=/model_cache/whisper

CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8765}"]
