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
| Reading emails or private columns | No anon privileges on `plantings`, `planting_contacts`, or the view |
| Floods of reads degrading the database | The map reads a CDN-cached file, so Postgres isn't involved |

## Architecture

```
Submit:  browser ──POST (form + photo + Turnstile token)──▶ submit-planting (service role)
           1. verify Turnstile token with Cloudflare
           2. validate fields
           3. upload photo to planting-photos with a server-generated path
           4. rpc('submit_planting'): insert planting + contact in one transaction
              (if this fails, delete the uploaded photo)
           5. rewrite map-data/plantings.json from public_planting_map

Read:    browser ──GET──▶ CDN ──(cache miss)──▶ storage: map-data/plantings.json
```

## Where things live

| Piece | File |
| --- | --- |
| Tables, view, RLS, and revoked anon/authenticated privileges | [20261003192327_create_plantings.sql](../supabase/migrations/20261003192327_create_plantings.sql) |
| `planting-photos` and `map-data` buckets (no storage policies) | [20261003193456_create_plantings.sql](../supabase/migrations/20261003193456_create_plantings.sql) |
| `submit_planting` RPC, executable only by `service_role` | [20261003202606_create_plantings.sql](../supabase/migrations/20261003202606_create_plantings.sql) |
| Edge Function | [supabase/functions/submit-planting/index.ts](../supabase/functions/submit-planting/index.ts) |
| Function config (`verify_jwt = false`) | [supabase/config.toml](../supabase/config.toml) |

### Notes on the database setup

- **Revoked default grants:** Supabase grants `anon` and `authenticated` full privileges on new tables in `public` by default. The first migration revokes them on both tables and the view, so access doesn't depend on RLS alone. Any new table needs the same treatment: enable RLS and revoke these grants.
- **RPC privileges:** Postgres grants `execute` on new functions to `public` by default. The RPC migration revokes it. Without that, anon could call `submit_planting` directly and skip the Turnstile check.
- **The view keeps `security_invoker = true`.** Only the service role reads it, and that role bypasses RLS.
- **Buckets:** `planting-photos` is private. `map-data` is public, because the map reads `plantings.json` by URL with no key. Neither bucket has policies, so anon can't upload, overwrite, or list files in either.

### Notes on the function

- **Plain handler:** it uses a plain `fetch` handler instead of the CLI template's `withSupabase` wrapper. That wrapper requires an API key on every request, which would break browser CORS preflights and would make the site ship a key.
- **No auth requirement:** `verify_jwt = false` because visitors are anonymous. Turnstile is the gatekeeper.
- **Snapshot failures:** if writing the snapshot fails, the function logs the error and still returns 201, because the planting is already saved. The next successful submission rewrites the file.
- **`ALLOWED_ORIGINS`** lists `https://aaronsexton.github.io` and `http://localhost:4321`. Add any custom domain here and to the Turnstile widget's hostnames.

## Astro client

The site uses no `supabase-js` and no Supabase key. It needs only two env values:

| Variable | Local (`.env.development`) | Production (GitHub repository variable) |
| --- | --- | --- |
| `PUBLIC_SUPABASE_URL` | `http://127.0.0.1:54321` | `https://iiimikqpfwvktlmvfvtj.supabase.co` |
| `PUBLIC_TURNSTILE_SITE_KEY` | `1x00000000000000000000AA` (test key, always passes) | The widget's site key from Cloudflare |

Pass the production values to the build step as `env:` from `${{ vars.* }}`.

**Map:** fetch the snapshot once on page load and give it to MapLibre:

```ts
const res = await fetch(`${import.meta.env.PUBLIC_SUPABASE_URL}/storage/v1/object/public/map-data/plantings.json`);
const data = res.ok ? await res.json() : { type: 'FeatureCollection', features: [] };
map.addSource('plantings', { type: 'geojson', data });
```

A missing file means no submissions have happened yet, so any non-OK response counts as an empty map. Locally, a missing file returns 400, not 404.

**Form:** POST multipart form data straight to the function:

```html
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
<form id="planting-form">
  <!-- title, seed_mixture, lat, lng, planted_on, nature_connection, email, photo -->
  <div class="cf-turnstile" data-sitekey={import.meta.env.PUBLIC_TURNSTILE_SITE_KEY}></div>
  <button type="submit">Submit</button>
</form>
```

```ts
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const body = new FormData(form); // includes cf-turnstile-response automatically
  // compress/resize the photo (e.g. browser-image-compression, ~2000px long edge),
  // converting HEIC to JPEG, then body.set('photo', compressed)
  const res = await fetch(`${import.meta.env.PUBLIC_SUPABASE_URL}/functions/v1/submit-planting`, {
    method: 'POST',
    body,
  });
  // 201 → { id }: add the point to the map source locally so the submitter sees it
  //   without waiting for the snapshot's 60s cache
  // 4xx/5xx → { error }: show it, then turnstile.reset() before allowing a retry
});
```

The function accepts JPEG, PNG, and WebP up to 15 MB. Compressing on the client keeps uploads fast and keeps storage within the free plan's 1 GB quota.

## Cloudflare Turnstile setup

1. In the Cloudflare dashboard, go to **Turnstile → Add widget**. Set the hostname to `aaronsexton.github.io`, the mode to **Managed**, and pre-clearance to **No**.
2. Give the secret key to the hosted function: `supabase secrets set TURNSTILE_SECRET=<secret key>`.
3. Add the site key as the `PUBLIC_TURNSTILE_SITE_KEY` GitHub repository variable.

For local testing, `supabase/functions/.env` (git-ignored) holds the test secret `1x0000000000000000000000000000000AA`. To test failures, swap in `2x0000000000000000000000000000000AA`, which always fails.

## Rollout

1. Test locally: `supabase start`, `supabase db reset`, `supabase functions serve --env-file supabase/functions/.env`, `astro dev`.
2. Run `supabase secrets set TURNSTILE_SECRET=...` on the hosted project.
3. Run `supabase functions deploy submit-planting`.
4. Apply the migrations to the hosted project. The earlier versions of the original migration files were already applied there before they were edited, so re-pushing won't change anything on its own. Reset the hosted database or apply the differences by hand, then check the result in **Advisors → Security**.
5. Deploy the Astro site with the production env values.
6. The map shows nothing until the first submission creates `plantings.json`.

## Testing checklist

Checked locally on 2026-10-03:

- [x] A valid submission with a photo and email returns 201. The planting, contact, and photo are stored, and the snapshot contains the point.
- [x] All fields are required (title, seed mixture, location, photo, date planted, email, nature connection). Leaving any one out returns 400. Run `scripts/test-local.sh` for the full set of checks.
- [x] The function works with no `apikey` header.
- [x] The snapshot is publicly readable with no key and is served with `cache-control: max-age=60`.
- [x] A missing token returns 403. Each invalid field returns 400, and a GET returns 405.
- [x] Anon requests are denied for: reading the view, `plantings`, or `planting_contacts`; inserting into `plantings`; calling the `submit_planting` RPC; uploading to `planting-photos`; overwriting `map-data/plantings.json`.
- [x] Listing `map-data` as anon returns an empty list.
- [ ] A failed RPC removes the uploaded photo. This hasn't been triggered yet.
- [ ] The function's CORS allowlist on the hosted project. Locally, the gateway answers preflights itself.
- [ ] Whether the hosted gateway accepts requests with no `apikey` header. If it requires one, send the publishable key, which is harmless because anon has no privileges.

## Known limits and follow-ups

- **Snapshot staleness:** other visitors may see data up to about 60 seconds old. Adjust `cacheControl` in `writeMapSnapshot` to change that.
- **Concurrent submissions:** if two submissions land at nearly the same moment, the snapshot written last can miss the other point until the next submission.
- **Deletes and moderation:** removing a planting in the dashboard doesn't update the snapshot. When moderation starts, add a `refresh-map-snapshot` function protected by a secret header, or call it from a trigger with `pg_net`. To review submissions before they appear, add `approved boolean not null default false` and filter the view on it.
- **Human spam:** Turnstile blocks bots, not people submitting by hand. If that becomes a problem, add per-IP rate limiting in the function, for example with a table of hashed IPs and timestamps.
- **Photos are private:** `planting-photos` is a private bucket, so only the service role can read it. Showing photos on the site would need short-lived signed URLs generated by the service role, for example as a field written into the snapshot.
- **Function limits:** Edge Functions have request size and runtime limits. Client-side compression keeps uploads well within them.
