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

Clone all three repos into the same root folder:

```text
git clone https://github.com/divyamojas/project-lumen
cd project-lumen
git clone https://github.com/divyamojas/project-lumen-light
git clone https://github.com/divyamojas/project-lumen-source
chmod +x start.sh
```

## Running the Stack

```text
./start.sh           # start everything
./start.sh --build   # rebuild images (after dependency changes)
./start.sh --down    # stop everything
```

## Service URLs

| Service | URL |
|---|---|
| Frontend | http://localhost:3000 |
| Frontend HTTPS | https://localhost |
| API | http://localhost:8000 |
| API docs (Swagger) | http://localhost:8000/docs |

## Start Order

The frontend must start first — it creates the shared Docker network
called "lumen". The API joins this network. start.sh handles this
automatically including a network readiness check.

## Running Without the Backend

If project-lumen-source is not cloned yet, start.sh starts the
frontend only and skips the API with a clear message.

## Docker Network

All containers share a bridge network named "lumen".
Created by: project-lumen-light/docker-compose.yml
Joined by:  project-lumen/docker-compose.yml (declared as external)

## Deployment

Each sub-repo deploys independently:
- Frontend: push to project-lumen-light → Netlify auto-deploys
- Backend: push to project-lumen-source → Render auto-deploys
- This root repo is for local development only.
