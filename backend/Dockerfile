FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

ARG PYTORCH_CPU_INDEX_URL=https://download.pytorch.org/whl/cpu

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml README.md Procfile ./
COPY src ./src

RUN pip install --upgrade pip setuptools wheel \
    && pip install --index-url ${PYTORCH_CPU_INDEX_URL} --extra-index-url https://pypi.org/simple torch==2.8.0 torchaudio==2.8.0 \
    && pip install ".[alignment]"

EXPOSE 8000

CMD ["sh", "-c", "uvicorn sync_backend.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
