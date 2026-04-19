# Lumen — Local Orchestrator

> **Your journal. Your AWS. Your AI.**
> A private, calm journal suite where your data lives on your own cloud —
> and where AI works *on your data*, not on someone else's servers.

Lumen is a journaling suite for six use cases: personal reflection, science
and research logging, travel, fitness, work, and creative writing. Each type
gets purpose-built fields and prompts. All entries sync to your own AWS S3
bucket. An AI layer (in progress) will let you query your journal in natural
language using Bedrock — without your data ever leaving your infrastructure.

**Status:** Phase 1 (core journaling) complete. Phase 2 (S3 sync) in progress.
Phases 3–5 (Bedrock, NL query, sentiment) on the roadmap.

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
