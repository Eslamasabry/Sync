FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libsndfile1 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml README.md Procfile ./
COPY src ./src

RUN pip install --upgrade pip setuptools wheel \
    && pip install ".[alignment]"

EXPOSE 8000

CMD ["sh", "-c", "uvicorn sync_backend.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
