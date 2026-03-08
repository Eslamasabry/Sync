# Regression Runs

## Purpose

The project needs a repeatable quality gate that runs against real public-domain content, not only synthetic samples.

## Single-Case Regression Script

Use [run_public_domain_regression.sh](/home/eslam/Storage/Code/Sync/scripts/local/run_public_domain_regression.sh) to:

- download a Project Gutenberg EPUB
- download a matching public-domain audiobook excerpt
- upload both to the local API
- execute an alignment job
- print coverage and mismatch metrics from the resulting artifacts

Default case:

- EPUB: *The Yellow Wallpaper* from Project Gutenberg
- Audio: public-domain human narration hosted on Wikimedia Commons

Use this path when you want to debug one title in isolation.

## Real Regression Corpus

Use [run_regression_corpus.sh](/home/eslam/Storage/Code/Sync/scripts/local/run_regression_corpus.sh) to execute the current multi-title public-domain corpus defined in [public_domain_regression_corpus.json](/home/eslam/Storage/Code/Sync/scripts/local/public_domain_regression_corpus.json).

Current corpus:

- `yellow-wallpaper`: Project Gutenberg EPUB + Wikimedia-hosted LibriVox audio
- `princess-of-mars`: Project Gutenberg EPUB + Project Gutenberg MP3 chapter audio
- `time-machine`: Project Gutenberg EPUB + Project Gutenberg MP3 chapter audio

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

Threshold-gated single-case run:

```bash
make local-regression-gate
```

That target fails the command if any of these baselines regress:

- match confidence below `0.9`
- coverage below `0.85`
- gap ranges above `80`

Override thresholds directly from the script when tuning the gate:

```bash
./scripts/local/run_public_domain_regression.sh \
  --min-match-confidence 0.92 \
  --min-coverage 0.88 \
  --max-gap-ranges 60
```

Corpus run:

```bash
make local-regression-corpus
```

Corpus gate:

```bash
make local-regression-corpus-gate
```

The plain corpus run records metrics for all titles without failing on thresholds.
The gate variant enforces each case's thresholds from the corpus manifest.

Run a specific title only:

```bash
./scripts/local/run_regression_corpus.sh --case-id yellow-wallpaper
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

## Artifacts

The single-case script saves:

- `job-status.json`
- `sync.json`
- `transcript.json`
- `metrics.json`

`metrics.json` is the machine-readable output intended for trend tracking and regression gating.

The corpus runner saves:

- per-case artifacts under `tmp/regression-corpus/<case-id>/`
- aggregate summary under `tmp/regression-corpus/summary.json`
