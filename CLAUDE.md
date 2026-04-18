# Lumen — Shared Context

## What This Is
A local-first journaling PWA with a FastAPI backend. Three repos as siblings:
- `project-lumen/` — Docker orchestrator (this repo)
- `project-lumen-light/` — Frontend: Next.js 14 PWA → deploys to Netlify
- `project-lumen-source/` — Backend: FastAPI → deploys to Render

## Running Locally
```
./start.sh            # start all services
./start.sh --down     # stop all services
./start.sh --build    # rebuild images
```
- Frontend: http://localhost:3000 (container: lumen-app)
- Backend:  http://localhost:8000 (container: lumen-api)
- Docker network: bridge named "lumen"

## Phase Status
- **Phase 1 (active):** Frontend feature-complete. Backend not yet built. Auth not yet wired.
- Phase 2: Wire frontend → backend. Auth. IndexedDB becomes local cache only.
- Phase 3: S3 upload on entry save.
- Phase 4: Lambda + Bedrock Knowledge Base. Natural language journal queries.
- Phase 5: AWS Comprehend → auto-set entry theme from sentiment.

Never implement future phases unless explicitly asked.

## Auth Flow
Google OAuth via Supabase → Supabase issues JWT → FastAPI verifies JWT locally with PyJWT.
- Frontend sends `Authorization: Bearer <token>` on all authenticated requests.
- `user_id` always extracted from the verified JWT — never from the request body.

## Entry Schema (frontend ↔ backend contract)
This is the shared data contract. Both repos must stay in sync with this shape.

```js
{
  id: string,              // stable after creation; frontend uses generateId()
  title: string,           // trimmed, max 100 chars
  body: string,            // trimmed, non-empty
  createdAt: string,       // ISO 8601; written once, never mutated
  updatedAt: string,       // ISO 8601; refreshed on every edit
  accentColor: object,     // never reassigned after creation
  theme: string,           // defaults to "neutral"; Phase 5: auto-set by Comprehend
  tags: string[],          // normalized slug-like strings
  favorite: boolean,
  pinned: boolean,
  collection: string,      // short human-readable label
  checklist: Array<{ id: string, text: string, checked: boolean }>,
  templateId: string,
  promptId: string,
  relatedEntryIds: string[]
}
```

## API Contract (Phase 2 target)
Internal base URL: `http://lumen-api:8000`

| Method | Path            | Description             |
|--------|-----------------|-------------------------|
| POST   | /entries        | Create entry            |
| GET    | /entries        | List entries (paginated)|
| GET    | /entries/{id}   | Get single entry        |
| PATCH  | /entries/{id}   | Update entry            |
| DELETE | /entries/{id}   | Delete entry            |

All endpoints require `Authorization: Bearer <jwt>`.
Return 404 (not 403) when an owned resource is not found — prevents user enumeration.

## Environment Variables
Never hardcode secrets. All values come from `.env` files in each repo.

| Variable                      | Used by  |
|-------------------------------|----------|
| NEXT_PUBLIC_SUPABASE_URL      | frontend |
| NEXT_PUBLIC_SUPABASE_ANON_KEY | frontend |
| NEXT_PUBLIC_API_URL           | frontend |
| SUPABASE_URL                  | backend  |
| SUPABASE_ANON_KEY             | backend  |
| SUPABASE_JWT_SECRET           | backend  |

## Universal Rules
Apply everywhere, no exceptions:
- No TypeScript — JS (frontend) and Python (backend) only.
- No local installs — Docker only. Never suggest running npm/pip/python on host.
- No hardcoded secrets — everything in `.env`.
- `user_id` always from JWT, never from the request body.
- Return 404 not 403 for owned-resource-not-found.
- No ORM — use Supabase client directly.
