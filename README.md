# Sprinkling Seeds

A project of the [LUPE Lab](https://aaronsexton.com/).

A community map of wildflower plantings across the New York City metro area. People submit where they planted seeds, with a photo, the seed mixture and a few short questions, and every planting appears on a shared map.

The site is a single page with a submission form above an interactive map. It's published at https://aaronsexton.github.io/ and embedded in a WordPress site through an iframe; see [docs/wordpress-embed.md](docs/wordpress-embed.md).

## How it works

```
Browser (Astro site on GitHub Pages)
  ├─ submit ─▶ Supabase Edge Function `submit-planting`
  │             checks Turnstile → validates → stores photo → inserts rows → rewrites map snapshot
  └─ map ────▶ Supabase Storage: map-data/plantings.json (public, CDN-cached)
```

- **Frontend:** [Astro](https://astro.build) with Tailwind CSS and [MapLibre](https://maplibre.org). The base map comes from OpenFreeMap, with an optional satellite layer. HEIC photos are converted to JPEG in the browser.
- **Backend:** Supabase (Postgres, Storage and one Edge Function). Browsers have no direct database access: every write goes through the Edge Function, which is protected by Cloudflare Turnstile, and the map reads a static snapshot file.
- **Deploys:** a push to `main` builds and publishes the site and deploys the Edge Function, via [.github/workflows/deploy.yml](.github/workflows/deploy.yml).

The full data-access design is in [docs/submission-edge-function-plan.md](docs/submission-edge-function-plan.md).

## Repo layout

| Path | Contents |
| --- | --- |
| `src/` | Astro site: page, form, location picker, map |
| `supabase/migrations/` | Database schema, permissions, storage buckets and the insert function |
| `supabase/functions/submit-planting/` | The Edge Function |
| `scripts/` | `test-local.sh` (local tests), `deploy-function.sh` (function deploy) |
| `docs/` | Setup, design and operations docs |

## Run it locally

You'll need Docker Desktop, the Supabase CLI (`brew install supabase/tap/supabase`) and Node 22.12 or newer (`.nvmrc` pins Node 24).

**One-time setup.** Create two git-ignored env files that hold test values only, then install dependencies.

`supabase/functions/.env`:

```bash
TURNSTILE_SECRET=1x0000000000000000000000000000000AA
```

`.env.development`:

```bash
PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
PUBLIC_TURNSTILE_SITE_KEY=1x00000000000000000000AA
```

```bash
nvm use
npm install
```

**Start everything.** Each long-running command needs its own terminal.

```bash
supabase start                                              # local Supabase (Docker)
supabase db reset                                           # apply migrations
supabase functions serve --env-file supabase/functions/.env # serve the Edge Function
npm run dev                                                 # site at http://localhost:4321
```

**Test.**

```bash
scripts/test-local.sh   # submissions, validation, snapshot, and anon lockdown checks
```

Local Studio runs at http://127.0.0.1:54323. Full details and troubleshooting are in [docs/local-development.md](docs/local-development.md).

## Supabase

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref iiimikqpfwvktlmvfvtj   # SprinklingSeeds
```

`supabase/` is already initialized, so there's no need to run `supabase init`.

**Database changes**

- **New migration:** create it with `supabase migration new <name>`, then apply it with `supabase db push`.
- **Edited migration** that's already applied: run `supabase db reset --linked`. This **deletes all hosted data**. Afterwards, clear `map-data/plantings.json` and the photos from Storage, because a reset leaves them in place.

**Edge Function**

```bash
supabase secrets set TURNSTILE_SECRET=<Cloudflare Turnstile secret key>   # once
scripts/deploy-function.sh             # type-check, deploy, smoke-test
scripts/deploy-function.sh --dry-run   # checks only
```

CI also deploys the function on every push to `main`. More detail: [docs/supabase-setup.md](docs/supabase-setup.md).

## Configuration and secrets

| Name | Where | Notes |
| --- | --- | --- |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_TURNSTILE_SITE_KEY` | GitHub repo secrets | Public values, embedded in the site at build time |
| `SUPABASE_ACCESS_TOKEN` | GitHub repo secret | Lets CI deploy the Edge Function |
| `TURNSTILE_SECRET` | Supabase Edge Function secret | Verifies the bot check |

How each was created, and how to rotate it: [docs/environment-and-secrets.md](docs/environment-and-secrets.md).

## Docs

- [Local development](docs/local-development.md)
- [Supabase CLI setup](docs/supabase-setup.md)
- [Data access design](docs/submission-edge-function-plan.md)
- [Environment and secrets](docs/environment-and-secrets.md)
- [WordPress embed](docs/wordpress-embed.md)

## Credits

Sprinkling Seeds is a project of the [Lupe Lab](https://aaronsexton.com/).
