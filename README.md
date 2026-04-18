# project-lumen

Root orchestrator for the Lumen journal app.
Contains no application code — only Docker orchestration and startup scripts.

## Repos

| Repo | Purpose | Deployed To |
|---|---|---|
| project-lumen (this) | Local orchestrator | — |
| project-lumen-light | Next.js PWA frontend | Netlify |
| project-lumen-source | FastAPI backend | Render |

## Prerequisites

- Docker Desktop running
- Git
- Nothing else. No Node, no Python, no package managers.

## First-Time Setup

Fast path:

```text
git clone https://github.com/divyamojas/project-lumen
cd project-lumen
chmod +x start.sh
./start.sh
```

`start.sh` now bootstraps missing sibling repos automatically:
- If `project-lumen-light/` is missing, it clones it
- If `project-lumen-source/` is missing, it clones it
- If a repo exists without `.git`, it initializes git locally and adds the expected `origin`
- If the backend `.env` is missing and `.env.example` exists, it creates `.env` from the example

Manual setup still works too if you prefer cloning everything yourself.

Create and populate the backend env file to enable the API:

```text
cp project-lumen-source/.env.example project-lumen-source/.env
# then fill in SUPABASE_URL, SUPABASE_SECRET_KEY, SUPABASE_PUBLISHABLE_KEY, DATABASE_URL
```

## Running the Stack

```text
./start.sh           # start everything
./start.sh --rebuild # clean, rebuild, and start again
./start.sh --clean   # stop the stack and remove project data
./start.sh --down    # stop everything
./start.sh --status  # show compose status
./start.sh --logs    # follow compose logs
./start.sh --doctor  # run preflight checks only
```

Each run writes a timestamped log to `logs/lumen-<timestamp>.log` containing
startup events and live container output from both services.

`./start.sh --rebuild` now performs a full clean teardown before rebuilding,
so repeated rebuilds start from a fresh stack state.

`./start.sh --doctor` validates Docker availability, repo layout, backend env
requirements, and port availability without changing container state.

If the backend repo is present but `.env` does not have the required values yet,
the script still starts the frontend and HTTPS proxy, then skips the API with a
clear message.

## Command Details

| Command | Behavior |
|---|---|
| `./start.sh` | Bootstrap missing repos if needed, then start the stack |
| `./start.sh --rebuild` | Run the clean path first, then rebuild and start |
| `./start.sh --clean` | Stop the stack and remove Compose-managed volumes and orphans |
| `./start.sh --down` | Stop the stack without deleting data |
| `./start.sh --status` | Show `docker compose ps` for the root app |
| `./start.sh --logs` | Follow logs for all services |
| `./start.sh --logs=<service>` | Follow logs for one service such as `app`, `proxy`, or `api` |
| `./start.sh --doctor` | Run bootstrap plus environment, file, Docker, and port checks without starting containers |

## Bootstrap Behavior

The root script is intentionally self-healing for local setup.

- If `project-lumen-light/` is missing, it clones it from the configured GitHub remote
- If `project-lumen-source/` is missing, it clones it from the configured GitHub remote
- If the current directory does not contain a valid root checkout, it bootstraps a fresh `project-lumen` checkout and re-runs from there
- If a repo exists without `.git`, the script initializes a local git repo and adds the expected `origin`
- If the backend `.env` file is missing and `.env.example` exists, the script creates `.env` from the example

Overrideable environment variables for bootstrap:
- `PROJECT_LUMEN_DEFAULT_BRANCH`
- `PROJECT_LUMEN_ROOT_REPO_URL`
- `PROJECT_LUMEN_FRONTEND_REPO_URL`
- `PROJECT_LUMEN_BACKEND_REPO_URL`

## Service URLs

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Frontend HTTPS | https://localhost |
| API | http://localhost:8000 |
| API docs (Swagger) | http://localhost:8000/docs |

## Compose App

All local services run inside a single Docker Compose app named
`project-lumen`. Docker Desktop will show `lumen-app`, `lumen-proxy`,
and `lumen-api` grouped together under that one app.

## Running Without the Backend

If the backend repo is unavailable or its `.env` is not configured yet,
`start.sh` starts the frontend services only. The backend service is
defined behind the Compose profile `api` and is enabled automatically
once the backend repo and required env values are present.

Required backend env keys before the API is started:
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `DATABASE_URL`

## Docker Network

All containers share the bridge network `lumen`, created by the root
Compose file in this repo.

## Data and Cleanup

The root Compose app owns these local project volumes:
- `project_lumen_node_modules`
- `project_lumen_caddy_data`
- `project_lumen_caddy_config`

Cleanup semantics:
- `--down` preserves those volumes
- `--clean` removes those volumes via `docker compose down --volumes --remove-orphans`
- `--rebuild` includes that clean step before rebuilding

## Deployment

Each sub-repo deploys independently:
- Frontend: push to project-lumen-light → Netlify auto-deploys
- Backend: push to project-lumen-source → Render auto-deploys
- This root repo is for local development only.
