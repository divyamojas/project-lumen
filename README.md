# Lumen v1 — Archived

> **This repository is archived.** Active development has moved to
> [`project-lumen-light`](https://github.com/divyamojas/project-lumen-light)
> (frontend) and
> [`project-lumen-source`](https://github.com/divyamojas/project-lumen-source)
> (backend).

## What this was

Lumen v1 was a localStorage-only PWA journal — no backend, no accounts, no
sync. Entries lived entirely in the browser.

It served as the prototype for proving the core UX direction: calm writing
experience, mobile-first layout, PWA installability.

## Why it was replaced

localStorage has a hard ceiling: no cross-device sync, no AI features, and
no path to the planned S3/Bedrock pipeline. v2 introduced a real backend and
retained everything that worked from v1.

## Running v1 (not recommended)

```bash
docker compose up
# Open http://localhost:3000
```

All features from v1 are present and improved in v2.
