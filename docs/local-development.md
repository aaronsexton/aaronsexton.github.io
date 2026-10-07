# Local development

This guide covers running Supabase (database, storage, and the `submit-planting` Edge Function) and the Astro site on your own machine, and testing them. Nothing here touches the hosted project.

## Prerequisites

- **Docker Desktop**, running. Local Supabase runs in containers.
- **Supabase CLI:** `brew install supabase/tap/supabase`
- **Node 22.12 or newer.** The repo pins Node 24 in `.nvmrc`. With nvm, run `nvm install` once, then `nvm use`.

## One-time setup

Both of these env files are git-ignored, so create them yourself. They contain only local and test values.

`supabase/functions/.env`:

```bash
# Cloudflare Turnstile test secret: accepts any token
TURNSTILE_SECRET=1x0000000000000000000000000000000AA
```

`.env.development`:

```bash
PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
# Cloudflare Turnstile test site key: always passes
PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA
```

Then install the site's dependencies:

```bash
npm install
```

## Start Supabase

```bash
supabase start      # first run downloads images and takes a few minutes
supabase db reset   # rebuilds the local database from supabase/migrations/
```

`db reset` drops the local database and reapplies every migration. Run it again whenever a migration changes. **Never add `--linked`** unless you mean to wipe the hosted database.

In a separate terminal, serve the Edge Function and leave it running. It reloads automatically when `index.ts` changes.

```bash
supabase functions serve --env-file supabase/functions/.env
```

| Service | URL |
| --- | --- |
| API, including the function at `/functions/v1/submit-planting` | http://127.0.0.1:54321 |
| Studio (tables, storage, logs) | http://127.0.0.1:54323 |

`supabase status` prints these URLs and the local keys.

## Run the tests

With Supabase started and the function being served:

```bash
scripts/test-local.sh
```

It checks:

- valid submissions succeed;
- each missing or invalid field is rejected;
- the map snapshot (`map-data/plantings.json`) is public and updates after submissions;
- anon can't read or write the tables, call the RPC, or upload files;
- `planting-photos` is private.

It exits non-zero if anything fails. Each run adds test plantings to the local database, and `supabase db reset` clears them.

## Run the site

```bash
nvm use
npm run dev         # http://localhost:4321
```

The site talks to local Supabase through `.env.development`. Submitting the form works end to end: the Turnstile test key always passes, and the new planting appears on the map.

## Stop

```bash
# Ctrl+C in the functions-serve and npm run dev terminals, then:
supabase stop       # keeps local data for the next supabase start
```

## Troubleshooting

- **`Cannot connect to the Docker daemon`:** start Docker Desktop.
- **"Edge Function isn't being served" from the test script:** `supabase functions serve` isn't running.
- **Every submission returns 403 "Verification failed":** `supabase/functions/.env` is missing, or you started `serve` without `--env-file`.
- **The site fails with `Missing PUBLIC_SUPABASE_URL`:** `.env.development` is missing.
- **Changes to the database or bucket settings aren't showing:** you edited a migration but haven't run `supabase db reset` since.
- **The map shows "Worker failed to load":** hard-refresh the page. If that doesn't help, restart `npm run dev`.
