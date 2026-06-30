# Grams of Health — PDF renderer

Self-hosted headless-Chrome service that prints the Lovable app's print routes to
A4 PDFs (vector text, correct pagination, fonts + Supabase images load properly).
The card layout stays in the React app; this only drives Chrome.

## Endpoint

`POST /render`
```json
{ "type": "recipe", "id": "<uuid>", "filename": "lentil-tuna-salad",
  "access_token": "<supabase access token>", "refresh_token": "<...>" }
```
`type` is `recipe` (→ `/recipes/$id/print`) or `plan` (→ `/plans/$id/print`).
Returns `application/pdf`. Rejects unless `access_token` is a valid Supabase user.

## Env vars
| Var | Value |
| --- | --- |
| `SUPABASE_URL` | `https://xtbjbaliyrswleggezkm.supabase.co` |
| `SUPABASE_ANON_KEY` | the anon/publishable key |
| `APP_BASE_URL` | the deployed Lovable app URL (e.g. `https://grams-recipe-editor.lovable.app`) |
| `ALLOWED_ORIGIN` | the app origin, for CORS (same as `APP_BASE_URL`) |

## Deploy (Render example)
1. Push this repo (or just `pdf-renderer/`) to GitHub.
2. Render → New → **Web Service** → pick the repo, root dir `pdf-renderer/`,
   environment **Docker**.
3. Add the four env vars above. Deploy.
4. Note the service URL (e.g. `https://goh-pdf-renderer.onrender.com`) — the app
   calls `POST <thatURL>/render`. Health check: `GET /healthz`.

Railway/Fly are equivalent — any host that builds the Dockerfile.

## Notes
- The print routes are auth-gated; the service seeds the user's Supabase session
  into the headless page's localStorage so data loads under that user (RLS intact,
  no service-role in the browser).
- `preferCSSPageSize` honours an `@page { size: A4 }` rule if the print route sets
  one; otherwise A4 is forced.
- For meal-plan booklets, the app needs a `/plans/$id/print` route that stacks each
  recipe's A4 card (one per page) — see the Lovable prompt.
