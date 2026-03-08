# Contributing

## Before You Start

- Read [README.md](/home/eslam/Storage/Code/Sync/README.md).
- Read [AGENTS.md](/home/eslam/Storage/Code/Sync/AGENTS.md).
- Check the contracts before changing API, reader model, or sync output.

## Development Rules

- Keep changes small and reviewable.
- Update docs in the same change when contracts or behavior change.
- Do not break the `sync.json` contract silently.
- Add or update tests when changing matching, normalization, export, or playback behavior.

## Pull Requests

- Explain the user-visible or developer-visible effect.
- Link any changed contract docs.
- Call out risks, assumptions, and follow-up work.

## Good First Areas

- EPUB tokenization and normalization
- sync schema tooling
- Flutter reader rendering
- playback and highlight behavior
- job progress and error handling
