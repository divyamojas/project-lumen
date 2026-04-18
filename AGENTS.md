# Lumen Orchestrator — Agent Notes

## Project Summary
This repository is the local Docker orchestrator for Lumen.
It owns the top-level startup flow, Docker Compose app, local HTTPS proxy wiring, and cross-repo bootstrap behavior.
It does not own frontend UI logic or backend API implementation.

Sibling repos expected beside this root:
- `project-lumen/` — this repo
- `project-lumen-light/` — Next.js frontend
- `project-lumen-source/` — FastAPI backend

## Files That Matter Here
- `start.sh` — canonical local entrypoint for bootstrap, doctor checks, start, stop, clean, rebuild, status, and logs
- `docker-compose.yml` — single Compose app for `app`, `proxy`, and optional `api`
- `README.md` — human-facing setup and operations guide
- `CLAUDE.md` — shared orchestration contract and architecture context
- `AGENTS.md` — lean execution guide for coding agents in this root repo

## What `start.sh` Does
- Bootstraps missing sibling repos via git clone
- Initializes git metadata and expected `origin` remotes when a repo exists without `.git`
- Seeds `project-lumen-source/.env` from `.env.example` when available
- Starts the single root Docker Compose app
- Enables the backend `api` profile only when the backend repo exists and its required env keys are populated
- Waits for frontend, HTTPS proxy, and API readiness before declaring success
- Writes run logs to `logs/lumen-<timestamp>.log`

Supported commands:
- `./start.sh`
- `./start.sh --rebuild`
- `./start.sh --clean`
- `./start.sh --down`
- `./start.sh --status`
- `./start.sh --logs`
- `./start.sh --logs=app`
- `./start.sh --doctor`
- `./start.sh --help`

Command semantics:
- `--down` stops the stack only
- `--clean` stops the stack and removes Compose-managed project volumes and orphans
- `--rebuild` runs the clean path first, then `docker compose up -d --build`

## Repo Responsibilities
- Keep orchestration logic in this repo only
- Keep frontend application logic in `project-lumen-light`
- Keep backend application logic in `project-lumen-source`
- Do not copy app code into this root repo just to “make startup easier”

## Safety Rules
- Never hardcode secrets
- Do not commit populated `.env` files
- Treat `--clean` as destructive local-data removal
- Prefer updating `start.sh`, `README.md`, `CLAUDE.md`, and `docker-compose.yml` together when behavior changes
- Keep the normal happy path fast; bootstrap and repair work should only happen when required

## Known Operational Expectations
- Frontend direct URL: `http://localhost:3000`
- Frontend HTTPS URL: `https://localhost`
- API URL: `http://localhost:8000`
- API docs URL: `http://localhost:8000/docs`
- Shared Docker network: `lumen`
- Compose app name: `project-lumen`

## Out of Scope
- Frontend features
- Backend endpoints or auth implementation details beyond orchestration contracts
- Future roadmap phases unless explicitly requested
