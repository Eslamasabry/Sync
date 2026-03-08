# Regression Runs

## Purpose

The project needs a repeatable quality gate that runs against real public-domain content, not only synthetic samples.

## Public-Domain Regression Script

Use [run_public_domain_regression.sh](/home/eslam/Storage/Code/Sync/scripts/local/run_public_domain_regression.sh) to:

- download a Project Gutenberg EPUB
- download a matching public-domain audiobook excerpt
- upload both to the local API
- execute an alignment job
- print coverage and mismatch metrics from the resulting artifacts

Default corpus:

- EPUB: *The Yellow Wallpaper* from Project Gutenberg
- Audio: public-domain human narration hosted on Wikimedia Commons

## Prerequisites

- PostgreSQL running
- Redis running
- API running on `127.0.0.1:8000`
- Celery worker running
- `ffmpeg` available on the host

## Run

```bash
cd /home/eslam/Storage/Code/Sync
./scripts/local/run_public_domain_regression.sh
```

Optional shorter excerpt:

```bash
./scripts/local/run_public_domain_regression.sh --excerpt-seconds 120
```

## Metrics to Watch

- `STATUS`: must be `completed`
- `MATCH_CONFIDENCE`: should trend upward over time
- `COVERAGE`: matched tokens divided by transcript words
- `GAP_RANGES`: should drop as front matter trimming and matching improve
- `CONTENT_START_MS`: should jump past audiobook disclaimers and intros when present

## Current Interpretation

- `audiobook_front_matter` and `audiobook_end_matter` are expected boundary gaps
- `narration_mismatch` inside the content window is the main signal of transcript or matching drift
