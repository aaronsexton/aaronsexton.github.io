# Plantings: data access design

## Goal

Browsers get no direct access to the database. All writes go through one Edge Function, which checks for bots before writing anything. The map reads a static JSON snapshot from a public storage bucket instead of querying Postgres.

## Why

Anything shipped to the browser is public, including any Supabase key in it. So security can't depend on hiding a key. Instead, the `anon` and `authenticated` roles have no privileges on the tables, and the only way in is server-side code that holds the service role key.

This design closes each of the following:

| Risk | Mitigation |
| --- | --- |
| Spam inserts through the REST API | No anon privileges or policies on any table. Every submission needs a valid Cloudflare Turnstile token |
| Forged `photo_path` | The function generates the path |
| A contact attached to someone else's planting | The planting and contact are inserted together in one transaction |
| Client-set `id` or `created_at` | The function passes through only fields it allows |
| Direct uploads to storage | There are no `storage.objects` policies, so only the service role can write |
| Reading emails, photos, or private columns | No anon privileges on `plantings`, `planting_contacts`, or the view, and `planting-photos` is private |
| Floods of reads degrading the database | The map reads a CDN-cached file, so Postgres isn't involved |

## Architecture

```
Submit:  browser ──POST (form + photo + Turnstile token)──▶ submit-planting (service role)
           1. verify Turnstile token with Cloudflare
           2. validate fields (all required) and the photo
           3. upload photo to planting-photos with a server-generated path
           4. rpc('submit_planting'): insert planting + contact in one transaction
              (if this fails, delete the uploaded photo)
           5. rewrite map-data/plantings.json from public_planting_map

Read:    browser ──GET──▶ CDN ──(cache miss)──▶ storage: map-data/plantings.json
```

## Where things live

| Piece | File |
| --- | --- |
| Tables, view, RLS, revoked anon/authenticated privileges | [20261003192327_create_plantings.sql](../supabase/migrations/20261003192327_create_plantings.sql) |
| `planting-photos` (private) and `map-data` (public) buckets, no storage policies | [20261003193456_create_plantings.sql](../supabase/migrations/20261003193456_create_plantings.sql) |
| `submit_planting` RPC, executable only by `service_role` | [20261003202606_create_plantings.sql](../supabase/migrations/20261003202606_create_plantings.sql) |
| Edge Function | [supabase/functions/submit-planting/index.ts](../supabase/functions/submit-planting/index.ts) |
| Function config (`verify_jwt = false`) | [supabase/config.toml](../supabase/config.toml) |
| Site config (URLs, map settings) | [src/lib/config.ts](../src/lib/config.ts) |
| Form, location picker, map | [src/components/](../src/components/) |
| Photo conversion and compression | [src/lib/photo.ts](../src/lib/photo.ts) |

### Notes on the database setup

- **Revoked default grants:** Supabase grants `anon` and `authenticated` full privileges on new tables in `public` by default. The first migration revokes them on both tables and the view, so access doesn't depend on RLS alone. Any new table needs the same treatment: enable RLS and revoke these grants.
- **Required columns:** every submitted field is `not null`: `planted_on`, `photo_path`, `nature_connection` (1–7), and `email` in `planting_contacts`. `submit_planting` always inserts the contact row. A missing email fails the constraint and rolls back the whole submission, so every planting has a contact.
- **RPC privileges:** Postgres grants `execute` on new functions to `public` by default. The RPC migration revokes it. Without that, anon could call `submit_planting` directly and skip the Turnstile check.
- **The view keeps `security_invoker = true`.** Only the service role reads it, and that role bypasses RLS.
- **Buckets:**
  - `planting-photos` is private: only the service role can read it.
  - `map-data` is public, because the map reads `plantings.json` by URL with no key.
  - Neither bucket has policies, so anon can't upload, overwrite, or list files in either.
  - Both bucket inserts use `on conflict (id) do update`. Buckets survive a database reset, so this keeps their settings in line with the migration.

### Notes on the function

- **Plain handler:** it uses a plain `fetch` handler instead of the CLI template's `withSupabase` wrapper. That wrapper requires an API key on every request, which would break browser CORS preflights and would make the site ship a key.
- **No auth requirement:** `verify_jwt = false` because visitors are anonymous. Turnstile is the gatekeeper. The hosted gateway accepts requests with no API key.
- **Validation before upload:** all fields are required. The photo (JPEG, PNG, or WebP, up to 15 MB) is checked before anything is uploaded, so a rejected submission never leaves a file behind.
- **Snapshot failures:** if writing the snapshot fails, the function logs the error and still returns 201, because the planting is already saved. The next successful submission rewrites the file.
- **`ALLOWED_ORIGINS`** lists `https://aaronsexton.github.io` and `http://localhost:4321`. Add any custom domain here and to the Turnstile widget's hostnames.

## Astro client

The site uses no `supabase-js` and no Supabase key. It needs only two env values:

| Variable | Local (`.env.development`) | Production (GitHub repository secret) |
| --- | --- | --- |
| `PUBLIC_SUPABASE_URL` | `http://127.0.0.1:54321` | `https://iiimikqpfwvktlmvfvtj.supabase.co` |
| `PUBLIC_TURNSTILE_SITE_KEY` | `1x00000000000000000000AA` (test key, always passes) | The widget's site key from Cloudflare |

Both values are public; they're embedded in the built site. They're stored as GitHub secrets, and [deploy.yml](../.github/workflows/deploy.yml) passes them to the build with `${{ secrets.* }}`. [config.ts](../src/lib/config.ts) fails the build if either is missing. See [environment-and-secrets.md](environment-and-secrets.md).

- **Map** ([PlantingMap.astro](../src/components/PlantingMap.astro)): fetches `plantings.json` once on page load. Any non-OK response counts as an empty map, since a missing file just means no submissions yet. Locally, a missing file returns 400, not 404. The map is display-only: clicking a planting opens a popup, and a toggle switches to satellite view.
- **Location** ([LocationPicker.astro](../src/components/LocationPicker.astro)): a smaller map inside the form, where the visitor taps or uses "Use my location" to drop a draggable pin. It fills hidden `lat` and `lng` fields.
- **Photo** ([photo.ts](../src/lib/photo.ts)): converted and compressed as soon as it's selected, so the form can show a preview.
  - HEIC is detected from the file's contents and converted to JPEG with `heic-to`. The decoder is loaded only when needed.
  - Every photo is resized to 2000 px on the long edge and compressed to roughly 1 MB of JPEG.
  - Submission reuses the converted file.
- **Submit** ([PlantingForm.astro](../src/components/PlantingForm.astro)): checks every field, then POSTs multipart form data, including `cf-turnstile-response`, to `/functions/v1/submit-planting`.
  - On 201, the new point is added to the map straight away, so the submitter doesn't wait out the snapshot's 60-second cache. The form and location picker then reset.
  - On an error, the form shows the message.
  - In both cases, it calls `turnstile.reset()`, because tokens are single-use.

## Cloudflare Turnstile setup

1. In the [Cloudflare Turnstile dashboard](https://dash.cloudflare.com/6164219a5ca0f9a5998e563bb6782ca4/turnstile), click **Add widget**. Name it `sprinklingseeds - planting form`, and set the hostname to `aaronsexton.github.io`, the mode to **Managed**, and pre-clearance to **No**.
2. Give the secret key to the hosted function: `supabase secrets set TURNSTILE_SECRET=<secret key>`.
3. Add the site key as a GitHub repository secret: `gh secret set PUBLIC_TURNSTILE_SITE_KEY -R aaronsexton/aaronsexton.github.io`.

For local testing, `supabase/functions/.env` (git-ignored) holds the test secret `1x0000000000000000000000000000000AA`. To test failures, swap in `2x0000000000000000000000000000000AA`, which always fails.

## Rollout

1. **Test locally:** `supabase start`, `supabase db reset`, `supabase functions serve --env-file supabase/functions/.env`, `npm run dev`, then `scripts/test-local.sh`. See [local-development.md](local-development.md).
2. **Secrets:** set `TURNSTILE_SECRET` on the hosted project once. Add `PUBLIC_SUPABASE_URL`, `PUBLIC_TURNSTILE_SITE_KEY` and `SUPABASE_ACCESS_TOKEN` as GitHub secrets.
3. **Database:** run `supabase db reset --linked`. The original migration files were edited after they were first applied, so `db push` won't pick up the changes. **This deletes all hosted data.** Then:
   - clear `map-data/plantings.json` and the files in `planting-photos`, because a reset leaves Storage in place (see [supabase-setup.md](supabase-setup.md));
   - check **Advisors → Security** in the dashboard.
4. **Function:** run `scripts/deploy-function.sh`, which type-checks, checks the secret, deploys, and smoke-tests. CI also runs it on every push to `main`.
5. **Site:** push to `main`. [deploy.yml](../.github/workflows/deploy.yml) builds and publishes it to GitHub Pages. Pages is still set to deploy from a branch, so check that https://aaronsexton.github.io/ shows the map, not the README. See [environment-and-secrets.md](environment-and-secrets.md#github).
6. **First submission:** the map shows nothing until the first submission creates `plantings.json`.

## Testing checklist

`scripts/test-local.sh` checks all of the following locally (30 checks, last run 2026-10-06):

- [x] A valid submission returns 201. The planting, contact, and photo are stored, and the snapshot contains the point.
- [x] Every field is required. Leaving out the title, seed mixture, location, photo, date, nature connection, or email returns 400, and so does an invalid value for any of them.
- [x] A missing Turnstile token returns 403, and a GET returns 405.
- [x] The function works with no API key header.
- [x] The snapshot is publicly readable with no key.
- [x] Anon requests are denied for:
  - reading the view, `plantings`, or `planting_contacts`;
  - inserting into `plantings`;
  - calling the `submit_planting` RPC;
  - uploading to `planting-photos`;
  - overwriting `map-data/plantings.json`;
  - listing `planting-photos`.
- [x] `planting-photos` is private: an existing photo's public URL returns "Bucket not found".

Checked on the hosted project:

- [x] The function is reachable with no API key. A GET returns the function's own 405, and a submission without a token returns 403. `scripts/deploy-function.sh` checks both after every deploy.

Not yet verified:

- [ ] A failed RPC removes the uploaded photo. This hasn't been triggered.
- [ ] The function's CORS allowlist on the hosted project. Locally, the gateway answers preflights itself.
- [ ] HEIC conversion with `heic-to` on real iPhone photos.

## Known limits and follow-ups

- **Snapshot staleness:** other visitors may see data up to about 60 seconds old. Adjust `cacheControl` in `writeMapSnapshot` to change that.
- **Concurrent submissions:** if two submissions land at nearly the same moment, the snapshot written last can miss the other point until the next submission.
- **Deletes, resets, and moderation:** removing a planting in the dashboard, or resetting the database, doesn't update the snapshot. When moderation starts, add a `refresh-map-snapshot` function protected by a secret header, or call it from a trigger with `pg_net`. To review submissions before they appear, add `approved boolean not null default false` and filter the view on it.
- **Human spam and quota:** Turnstile blocks bots, not people submitting by hand. A flood of invalid requests writes nothing, but each one still counts as a function invocation. If either becomes a problem, move submissions to a Cloudflare Worker with per-IP rate limiting in front of the database.
- **Photos are private:** showing photos on the site would need short-lived signed URLs generated by the service role, for example written into the snapshot and refreshed regularly.
- **Function limits:** Edge Functions have request size and runtime limits. Client-side compression keeps uploads well within them.
