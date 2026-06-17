# Licensing philosophy filename

## What landed

- Renamed `LICENSE-PHILOSOPHY.md` to `LICENSING-PHILOSOPHY.md`.
- Updated the README link to the new filename.

## Decisions

- **Avoid `LICENSE-*` for non-license prose.** GitHub/Licensee treats
  `LICENSE-*` names as candidate license files, which can make the
  philosophy document appear as an unknown license. `LICENSING-*`
  preserves the meaning while staying out of that filename pattern.
- **Direct root-level rename over moving into `docs/`.** A docs
  directory would also avoid detection, but the direct rename is the
  smallest fix and keeps the README link visible beside `LICENSE`.

## Deferred

- No broader docs directory layout change.
