# Lumen Orchestrator — Claude Context

## Current State (as of 2026-04-19)
This repo is the local Docker orchestrator for Lumen. It does not contain application code.

Current sibling repos:
- `project-lumen/` — this repo; bootstraps and runs the local stack
- `project-lumen-light/` — Next.js frontend
- `project-lumen-source/` — FastAPI backend

Current product status across the stack:
- Frontend and backend are now wired together for backend-managed authentication and authenticated API access
- Frontend journal UX still keeps client-side persistence in IndexedDB/local cache
- Backend owns auth verification, entry CRUD, RBAC, admin APIs, schema introspection, migrations, and raw SQL
- The admin UI currently uses the backend for stats, user management, entry inspection, schema, migrations, and SQL console access

## Repo Boundaries
Keep responsibilities separated:
- Root repo: Docker orchestration, startup flow, local HTTPS proxy, shared cross-repo context
- Frontend repo: UI, client routing, client persistence, session state, admin screens
- Backend repo: auth endpoints, token verification, Supabase access, models, admin APIs

Do not move frontend or backend app logic into this repo.
Do not treat this file as a replacement for the more specific `CLAUDE.md` files in the sub-repos.

## Files Owned Here
- `start.sh` — canonical local entrypoint for bootstrap, checks, clean/rebuild/start, logs, attached runs, and tests
- `docker-compose.yml` — single Compose app named `project-lumen` for `app`, `proxy`, and optional `api`
- `README.md` — human-facing setup and operations guide
- `CLAUDE.md` — cross-repo orchestration contract
- `AGENTS.md` — lean execution guide for coding agents in this repo

## Running Locally
Use Docker only.

```bash
./start.sh
./start.sh --rebuild
./start.sh --clean
./start.sh --down
./start.sh --status
./start.sh --logs
./start.sh --logs=app
./start.sh --doctor
./start.sh --test
./start.sh --rebuild -v
./start.sh --clean -a
./start.sh --rebuild --attach
```

Expected local URLs:
- Frontend: `http://localhost:3000`
- Frontend HTTPS: `https://localhost`
- Backend: `http://localhost:8000`
- Backend docs: `http://localhost:8000/docs`

## Startup Behavior
`start.sh` is intentionally opinionated:
- Bootstraps missing sibling repos from the configured Git remotes
- Initializes local git metadata and expected `origin` remotes when a repo exists without `.git`
- Seeds backend `.env` from `.env.example` when possible
- Verifies Docker and `docker compose` are available
- Refuses to start if ports `3000`, `8000`, `80`, or `443` are already in use
- Starts the single root Compose app from this repo
- Enables the backend `api` profile automatically only when the backend repo exists and the required env keys are populated
- Starts frontend-only when the backend repo is missing or its `.env` is not ready
- Prints numbered startup phases and readiness progress while waiting
- Waits for frontend, HTTPS proxy, and API readiness before printing success

Command semantics:
- `--down` stops the stack only
- `--clean` stops the stack and can remove volumes/images/orphans/cache depending on flags
- `--rebuild` rebuilds and starts the stack, and cleanup flags can be layered onto it
- `--doctor` runs bootstrap plus preflight checks without starting containers
- `--test` delegates to backend tests via `test.sh`
- `--attach` runs `docker compose up` attached instead of detached

Cleanup flags:
- `-v` / `--volumes`
- `-i` / `--images`
- `-o` / `--orphans`
- `-c` / `--cache`
- `-a` / `--all`

The root `docker-compose.yml` owns the shared `lumen` bridge network for all local services.

## Shared Auth Contract
Auth is backend-managed.

Current flow:
1. Frontend calls backend auth endpoints such as `/auth/login`, `/auth/sign-up`, or `/auth/google/start`
2. Backend talks to Supabase Auth
3. Frontend stores the returned bearer token locally
4. Frontend sends `Authorization: Bearer <token>` on authenticated API requests
5. Backend verifies the JWT and resolves `user_id` from `sub`

Backend verification order:
1. Asymmetric token (RS256/ES256) → verify via JWKS at `SUPABASE_URL/auth/v1/.well-known/jwks.json`
2. HS256 + `SUPABASE_JWT_SECRET` set → verify locally
3. HS256, no secret → verify remotely via `/auth/v1/user` with `SUPABASE_PUBLISHABLE_KEY`

Cross-repo rules:
- Never trust `user_id` from request body or query params
- Missing or invalid JWT → 401
- Owned-resource miss → 404, not 403

## RBAC
Backend enforces role-based access via `require_role(minimum_role)`.
Hierarchy: `user < admin < superuser`.

Frontend has no independent role system. It derives admin access from backend responses and bearer-authenticated requests.

## Entry Contract
Both application repos should stay aligned with this shape:

```js
{
  id: string,
  title: string,
  body: string,
  createdAt: string,
  updatedAt: string,
  accentColor: object,
  theme: string,
  tags: string[],
  favorite: boolean,
  pinned: boolean,
  collection: string,
  checklist: Array<{ id: string, text: string, checked: boolean }>,
  templateId: string,
  promptId: string,
  relatedEntryIds: string[]
}
```

Field expectations:
- `title` is trimmed and capped at 100 chars
- `body` is trimmed and non-empty
- `createdAt` is write-once
- `updatedAt` is refreshed on edit
- `accentColor` is stable after creation
- `theme` currently defaults to `"neutral"`
- `tags` are normalized slug-like strings

## API Contract
Internal base URL inside Docker: `http://lumen-api:8000`

Key backend routes used today:
- Auth: `/auth/login`, `/auth/sign-up`, `/auth/reset-password`, `/auth/google/start`, `/auth/logout`
- User: `/users/me`
- Entries: `/entries`
- Health: `/health`
- Admin UI: `/admin/stats`, `/admin/users`, `/admin/entries`, `/admin/schema`, `/admin/schema/migrations`, `/admin/sql`

Broader superuser APIs also exist for direct auth-user and generic table management; see backend context for the full list.

## Environment Variables
Never hardcode secrets. Values come from repo-local `.env` files.

Frontend:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_API_URL`

Backend (required):
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `DATABASE_URL`

Backend (optional/legacy):
- `SUPABASE_JWT_SECRET`
- `SUPABASE_JWKS_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `CORS_ORIGINS`

## Universal Rules
Apply everywhere:
- No TypeScript; frontend is JavaScript, backend is Python
- No local installs; use Docker only
- No hardcoded secrets
- `user_id` always comes from JWT verification
- Return `404`, not `403`, for owned-resource-not-found
- No ORM; backend uses Supabase client plus asyncpg only

## Future Phases
- Keep future roadmap work opt-in only
- Do not automatically implement AWS/S3/Lambda/Bedrock/Comprehend work unless explicitly requested
