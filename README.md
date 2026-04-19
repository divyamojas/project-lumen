# Lumen — Local Orchestrator

> **Your journal. Private backup. Future AI.**
> A private, calm journal suite where your data stays under your Lumen deployment —
> and where AI works *on your data*, not on someone else's servers.

Lumen is a journaling suite for six use cases: personal reflection, science
and research logging, travel, fitness, work, and creative writing. Each type
gets purpose-built fields and prompts. Entries can be backed up to an
AWS S3 bucket configured for the Lumen deployment. An AI layer (in progress)
will let you query your journal in natural language using Bedrock.

**Status:** Phase 1 (core journaling) is usable but still being hardened.
Phase 2 (deployment-managed S3 backup) is partially implemented and still in progress.
Phases 3–5 (Bedrock, NL query, sentiment) remain on the roadmap.

---

> **Note: This repository is the v1 prototype and Docker orchestrator.**
> Active application development has moved to
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

## Helpful Scripts

```bash
./push.sh
```

Pushes the current branch in `project-lumen`, `project-lumen-light`, and
`project-lumen-source` in sequence. Any extra arguments are passed through to
each `git push`, for example `./push.sh --force-with-lease`.

The root `./start.sh` orchestrator in `project-lumen/` now reports actionable
startup failures for common local issues such as no internet/DNS resolution,
Docker access problems, port conflicts, Docker Hub rate limits, and services
that start but never become ready.
