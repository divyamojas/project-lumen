# Lumen Orchestrator — Claude Context

## Current State (as of 2026-04-18)
This repo is the local Docker orchestrator for Lumen. It does not contain application code.

Current sibling repos:
- `project-lumen/` — this repo; starts and stops the local stack
- `project-lumen-light/` — Next.js 14 PWA frontend
- `project-lumen-source/` — FastAPI backend

Current product status across the stack:
- Frontend MVP is feature-complete and still runs primarily against local-first storage
- Backend Phase 1 complete: full entry CRUD, JWT auth, RBAC, admin API, schema introspection, file-based migrations, raw SQL
- Frontend and backend are not wired together yet; that integration belongs to Phase 2

## Repo Boundaries
Keep responsibilities separated:
- Root repo: Docker orchestration, startup flow, shared cross-repo context
- Frontend repo: UI, PWA behavior, client persistence, browser-only logic
- Backend repo: API routes, auth verification, Supabase access, server-side models

Do not move frontend or backend application logic into this repo.
Do not treat this file as a replacement for the more specific `CLAUDE.md` files in the sub-repos.

## Files Owned Here
- `start.sh` — the canonical way to start, rebuild, and stop the local stack
- `docker-compose.yml` — runs the backend container and joins the external `lumen` network
- `README.md` — human-facing local setup and usage notes
- `CLAUDE.md` — shared orchestration rules and cross-repo contract

## Running Locally
Use Docker only.

```bash
./start.sh
./start.sh --build
./start.sh --down
```

Expected local URLs:
- Frontend: `http://localhost:3000`
- Frontend HTTPS: `https://localhost`
- Backend: `http://localhost:8000`
- Backend docs: `http://localhost:8000/docs`

## Startup Behavior
`start.sh` is intentionally opinionated:
- Verifies Docker and `docker compose` are available
- Refuses to start if ports `3000`, `8000`, `80`, or `443` are already in use
- Starts the frontend first so it creates the shared Docker network `lumen`
- Waits for that network before starting the backend
- Starts frontend-only when `project-lumen-source/` is missing
- Requires `project-lumen-source/.env` when the backend repo is present

The root `docker-compose.yml` assumes the `lumen` network already exists and joins it as an external network.

## Phase Status
- **Phase 1:** Frontend MVP complete; backend Phase 1 complete (full entry CRUD, JWT auth, RBAC, admin API, schema introspection, file-based migrations, raw SQL); frontend-backend not yet wired
- **Phase 2:** Wire frontend to backend, wire auth, and make IndexedDB a cache rather than the source of truth
- **Phase 3:** S3 upload on entry save
- **Phase 4:** Lambda plus Bedrock Knowledge Base for natural-language journal queries
- **Phase 5:** AWS Comprehend sets entry theme from sentiment

Never implement future phases unless explicitly asked.

## Shared Auth Contract
Google OAuth via Supabase → Supabase issues JWT → FastAPI verifies JWT.

Backend resolution order:
1. Asymmetric token (RS256/ES256) → verify via JWKS at `SUPABASE_URL/auth/v1/.well-known/jwks.json`
2. HS256 + `SUPABASE_JWT_SECRET` set → verify locally
3. HS256, no secret → verify remotely via `/auth/v1/user` with `SUPABASE_PUBLISHABLE_KEY`

Cross-repo rules:
- Frontend sends `Authorization: Bearer <token>` on all authenticated API requests
- Backend extracts `user_id` from the verified JWT `sub` claim
- Never trust `user_id` from a request body or query param
- Missing or invalid JWT → 401

## RBAC
Backend enforces role-based access via `require_role(minimum_role)`. Hierarchy: `user < admin < superuser`.
Caller role is looked up from the `user_roles` table. Raises 403 on insufficient role.
Frontend has no role concept — all admin endpoints are backend-only.

## Entry Schema (frontend <-> backend contract)
Both application repos must stay aligned with this shape.

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
- `id` is stable after creation
- `title` is trimmed and capped at 100 chars
- `body` is trimmed and non-empty
- `createdAt` is written once and never mutated
- `updatedAt` is refreshed on every edit
- `accentColor` is never reassigned after creation
- `theme` currently defaults to `"neutral"`
- `tags` are normalized slug-like strings
- `collection` is a short human-readable label

## API Contract (Phase 2 target)
Internal base URL: `http://lumen-api:8000`

**User endpoints** (require valid JWT, `user` role minimum):

| Method | Path | Description |
|---|---|---|
| POST | `/entries` | Create entry |
| GET | `/entries` | List entries |
| GET | `/entries/{id}` | Get single entry |
| PATCH | `/entries/{id}` | Update entry |
| DELETE | `/entries/{id}` | Delete entry |
| GET | `/users/me` | Current user info |
| GET | `/health` | Health check (no auth) |

**Admin endpoints** (backend-only; `admin` or `superuser` role required — see backend CLAUDE.md for full matrix):

| Method | Path | Min role |
|---|---|---|
| GET | `/admin/stats` | admin |
| GET | `/admin/users` | admin |
| PATCH | `/admin/users/{id}/role` | superuser |
| DELETE | `/admin/users/{id}` | superuser |
| GET | `/admin/entries` | superuser |
| POST | `/admin/sql` | superuser |

All authenticated endpoints require `Authorization: Bearer <jwt>`.
Return `404`, not `403`, when an owned resource is not found.
Return `401` for missing or invalid JWT.

## Environment Variables
Never hardcode secrets. Values come from repo-local `.env` files.

Frontend:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_API_URL`

Backend (required):
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY` — `sb_secret_...` key, bypasses RLS
- `SUPABASE_PUBLISHABLE_KEY` — `sb_publishable_...` key, used for HS256 fallback auth
- `DATABASE_URL` — direct Postgres connection for asyncpg (URL-encode special chars in password)

Backend (optional/legacy):
- `SUPABASE_JWT_SECRET` — legacy HS256 shared secret
- `SUPABASE_JWKS_URL` — override JWKS endpoint
- `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` — legacy keys

## Universal Rules
Apply everywhere:
- No TypeScript; use JavaScript in frontend code and Python in backend code
- No local installs; use Docker only
- No hardcoded secrets
- `user_id` always comes from JWT verification
- Return `404`, not `403`, for owned-resource-not-found
- No ORM; backend uses the Supabase client directly
