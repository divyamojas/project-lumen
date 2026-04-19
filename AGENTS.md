# Lumen Orchestrator — Agent Notes

## Project Summary
This repository is the local Docker orchestrator for Lumen.
It owns the top-level startup flow, the single Compose app, local HTTPS proxy wiring, and shared cross-repo expectations.
It does not own frontend UI logic or backend API implementation.

Sibling repos expected beside this root:
- `project-lumen/` — this repo
- `project-lumen-light/` — Next.js frontend
- `project-lumen-source/` — FastAPI backend

## Files That Matter Here
- `start.sh` — canonical local entrypoint for bootstrap, checks, start/stop, rebuild, logs, status, doctor, and test
- `docker-compose.yml` — single Compose app named `project-lumen` for `app`, `proxy`, and optional `api`
- `README.md` — human-facing local setup and operations guide
- `CLAUDE.md` — shared orchestration contract
- `AGENTS.md` — lean execution guide for this repo

## What `start.sh` Does
- Bootstraps missing sibling repos via git clone
- Initializes git metadata and expected `origin` remotes when a repo exists without `.git`
- Seeds `project-lumen-source/.env` from `.env.example` when available
- Starts the single root Docker Compose app
- Enables the backend `api` profile only when the backend repo exists and its required env keys are populated
- Prints numbered startup phases and readiness progress while waiting
- Waits for frontend, HTTPS proxy, and API readiness before declaring success
- Captures failing compose/bootstrap output into the run log and surfaces clearer diagnostics for offline/DNS, Docker access, port conflicts, rate limits, and readiness timeouts
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
- `./start.sh --test`
- `./start.sh --help`
- `./start.sh --rebuild -a`
- `./start.sh --clean -v`
- `./start.sh --rebuild --attach`

## Repo Responsibilities
- Keep orchestration logic in this repo only
- Keep frontend application logic in `project-lumen-light`
- Keep backend application logic in `project-lumen-source`
- Do not copy app code into this repo just to make startup easier

## Current Cross-Repo Reality
- Frontend and backend are wired for backend-managed auth
- Frontend stores bearer tokens client-side and calls the backend directly
- Backend owns JWT verification, RBAC, auth endpoints, schema/migration APIs, and admin APIs
- The admin UI currently consumes backend stats/users/entries/schema/migrations/sql APIs

## Safety Rules
- Never hardcode secrets
- Do not commit populated `.env` files
- Treat `--clean` as potentially destructive local-data removal
- Treat `-a` / `--all` as the most destructive local cleanup path
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
- Backend internals beyond orchestration contracts
- Future roadmap phases unless explicitly requested
