# Plan: Route planting submissions through an Edge Function

## Goal

Make a Supabase Edge Function the only way to write plantings, contacts, and photos. Anonymous clients keep read access to the map but can no longer insert directly with the anon key.

## Why

The current migrations allow anonymous inserts with `with check (true)`. Anyone holding the public anon key can therefore do the following through the REST API, bypassing the site's form:

- Insert unlimited plantings with any title or location (spam).
- Set `photo_path` to any string, including files they never uploaded.
- Attach a `planting_contacts` row to someone else's planting.
- Set `id` and `created_at` themselves.
- Upload any number of files to the `planting-photos` bucket.

After this change:

| Issue | Fix |
| --- | --- |
| Spam through the REST API | Anon insert policies are removed, and every submission needs a valid Cloudflare Turnstile token |
| Forged `photo_path` | The function generates the path |
| Contacts attached to other plantings | The planting and contact are inserted together in one transaction |
| Client-set `id` and `created_at` | The function passes through only allowed fields |
| Unlimited uploads | Uploads happen only inside a verified submission |

## Architecture

```
Browser (Astro form + Turnstile widget)
   │  multipart POST: fields + photo + cf-turnstile-response
   ▼
Edge Function: submit-planting  (service role)
   1. Verify Turnstile token with Cloudflare
   2. Validate fields
   3. Upload photo to planting-photos, with a path the server generates
   4. rpc('submit_planting'), which inserts the planting and contact in one transaction
   5. If step 4 fails, delete the uploaded photo
   ▼
Postgres + Storage
```

Reads are unchanged. The map fetches `public_planting_map` with the anon key once on page load.

## Steps

### 1. Migration: remove anon writes and add a transactional insert function

Create it with `supabase migration new submission_via_edge_function`:

```sql
-- "if exists": the plantings migration was edited to no longer create the first two,
-- but they still exist on the hosted project, where it was applied before the edit
drop policy if exists "Anyone can submit a planting" on plantings;
drop policy if exists "Anyone can submit a contact" on planting_contacts;
drop policy if exists "Anyone can upload planting photos" on storage.objects;

create function public.submit_planting(
  p_title text,
  p_seed_mixture public.seed_mixture,
  p_lat float8,
  p_lng float8,
  p_planted_on date,
  p_nature_connection int2,
  p_photo_path text,
  p_email text
) returns uuid
language plpgsql
set search_path = ''
as $$
declare v_id uuid;
begin
  insert into public.plantings (title, seed_mixture, location, planted_on, nature_connection, photo_path)
  values (p_title, p_seed_mixture,
          extensions.st_point(p_lng, p_lat)::extensions.geography,
          p_planted_on, p_nature_connection, p_photo_path)
  returning id into v_id;

  if p_email is not null then
    insert into public.planting_contacts (planting_id, email) values (v_id, p_email);
  end if;

  return v_id;
end $$;

revoke execute on function public.submit_planting from public, anon, authenticated;
grant execute on function public.submit_planting to service_role;
```

The `revoke` is required. Postgres grants `execute` to `public` by default, and without the revoke anon could call this function directly and skip the Edge Function.

### 2. Edge Function: `submit-planting`

Create it with `supabase functions new submit-planting`, then write `supabase/functions/submit-planting/index.ts`:

```ts
import { createClient } from 'npm:@supabase/supabase-js@2';

const ALLOWED_ORIGINS = ['https://aaronsexton.github.io', 'http://localhost:4321'];
const MAX_PHOTO_BYTES = 15 * 1024 * 1024;
const PHOTO_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // injected automatically; never leaves the server
);

function cors(origin: string | null) {
  return {
    'Access-Control-Allow-Origin': origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

async function verifyTurnstile(token: string, ip: string | null) {
  const body = new FormData();
  body.append('secret', Deno.env.get('TURNSTILE_SECRET')!);
  body.append('response', token);
  if (ip) body.append('remoteip', ip);
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body });
  const json = await res.json();
  return json.success === true;
}

Deno.serve(async (req) => {
  const headers = cors(req.headers.get('origin'));
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers });

  const fail = (msg: string, status = 400) =>
    new Response(JSON.stringify({ error: msg }), { status, headers: { ...headers, 'Content-Type': 'application/json' } });

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return fail('Invalid form data');
  }

  // 1. Bot check
  const ip = req.headers.get('cf-connecting-ip') ?? req.headers.get('x-forwarded-for');
  const token = form.get('cf-turnstile-response');
  if (typeof token !== 'string' || !(await verifyTurnstile(token, ip))) {
    return fail('Verification failed', 403);
  }

  // 2. Validate fields
  const title = String(form.get('title') ?? '').trim();
  const seedMixture = String(form.get('seed_mixture') ?? '');
  const lat = Number(form.get('lat'));
  const lng = Number(form.get('lng'));
  const plantedOn = form.get('planted_on') ? String(form.get('planted_on')) : null;
  const natureConnection = form.get('nature_connection') ? Number(form.get('nature_connection')) : null;
  const email = form.get('email') ? String(form.get('email')).trim() : null;

  if (title.length < 1 || title.length > 100) return fail('Title must be 1–100 characters');
  if (!['full_sun', 'partial_sun'].includes(seedMixture)) return fail('Invalid seed mixture');
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) return fail('Invalid latitude');
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) return fail('Invalid longitude');
  if (plantedOn && !/^\d{4}-\d{2}-\d{2}$/.test(plantedOn)) return fail('Invalid date');
  if (natureConnection !== null && !(Number.isInteger(natureConnection) && natureConnection >= 1 && natureConnection <= 7)) {
    return fail('Invalid nature connection');
  }
  if (email && (email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) return fail('Invalid email');

  // 3. Upload photo (path generated here, not by the client)
  let photoPath: string | null = null;
  const photo = form.get('photo');
  if (photo instanceof File && photo.size > 0) {
    const ext = PHOTO_TYPES[photo.type];
    if (!ext) return fail('Photo must be JPEG, PNG, or WebP');
    if (photo.size > MAX_PHOTO_BYTES) return fail('Photo is too large');

    photoPath = `${crypto.randomUUID()}.${ext}`;
    const { error } = await supabase.storage
      .from('planting-photos')
      .upload(photoPath, photo, { contentType: photo.type });
    if (error) {
      console.error(error);
      return fail('Photo upload failed', 500);
    }
  }

  // 4. Insert planting + contact in one transaction
  const { data: id, error } = await supabase.rpc('submit_planting', {
    p_title: title,
    p_seed_mixture: seedMixture,
    p_lat: lat,
    p_lng: lng,
    p_planted_on: plantedOn,
    p_nature_connection: natureConnection,
    p_photo_path: photoPath,
    p_email: email,
  });

  if (error) {
    console.error(error);
    if (photoPath) await supabase.storage.from('planting-photos').remove([photoPath]); // don't orphan the file
    return fail('Could not save planting', 500);
  }

  return new Response(JSON.stringify({ id }), {
    status: 201,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
});
```

### 3. Config and secrets

In `supabase/config.toml`:

```toml
[functions.submit-planting]
verify_jwt = false
```

Turnstile is the gatekeeper instead of a JWT. Visitors are anonymous, so requiring a JWT would only prove that the caller has the public anon key.

Set up Turnstile in the Cloudflare dashboard (free) to get a site key and a secret key.

| Setting | Local | Hosted |
| --- | --- | --- |
| `TURNSTILE_SECRET` | `1x0000000000000000000000000000000AA` (Cloudflare's test secret, which always passes) in `supabase/functions/.env` | `supabase secrets set TURNSTILE_SECRET=<secret>` |
| `PUBLIC_TURNSTILE_SITE_KEY` | `1x00000000000000000000AA` in `.env.development` | GitHub repository variable, passed to the Astro build |

`supabase/functions/.env` must be listed in `.gitignore`.

### 4. Astro form

```html
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
<form id="planting-form">
  <!-- title, seed_mixture, lat/lng, planted_on, nature_connection, email, photo inputs -->
  <div class="cf-turnstile" data-sitekey={import.meta.env.PUBLIC_TURNSTILE_SITE_KEY}></div>
  <button type="submit">Submit</button>
</form>
```

```ts
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const data = new FormData(form); // includes cf-turnstile-response automatically
  // Compress/resize the photo first (e.g. browser-image-compression), converting HEIC to JPEG,
  // then data.set('photo', compressed)
  const { data: result, error } = await supabase.functions.invoke('submit-planting', { body: data });
  // Show success or error; call turnstile.reset() before allowing a retry
});
```

Compress the photo on the client, resizing to about 2000 px on the long edge. This keeps uploads fast, keeps usage within the free plan's 1 GB storage quota, and converts iPhone HEIC photos to JPEG so they display in all browsers.

## Rollout order

The migration removes the anon insert policies, so any client that still writes directly will break once it's applied. No such client is live yet, so the order is mostly about testing:

1. Build and test everything locally (`supabase start`, `supabase db reset`, `supabase functions serve`, `astro dev`).
2. Set `TURNSTILE_SECRET` on the hosted project.
3. Deploy the function: `supabase functions deploy submit-planting`.
4. Push the migration: `supabase db push`.
5. Deploy the Astro site with the production Turnstile site key.

## Testing checklist

Locally:

- [ ] A valid submission with a photo returns 201, the planting appears on the map, and the photo is in the bucket.
- [ ] A valid submission without a photo or email succeeds.
- [ ] A missing or invalid Turnstile token returns 403. To test, swap in Cloudflare's always-fails test secret, `2x0000000000000000000000000000000AA`.
- [ ] Each invalid field (empty title, out-of-range lat, bad email, `nature_connection = 9`) returns 400.
- [ ] A HEIC photo or an oversized file is rejected.
- [ ] Forcing the RPC to fail removes the uploaded photo.
- [ ] Direct anon inserts are rejected: `supabase.from('plantings').insert(...)`, inserts on `planting_contacts`, and `storage.from('planting-photos').upload(...)`.
- [ ] A direct anon `supabase.rpc('submit_planting', ...)` call is rejected.
- [ ] The map still loads from `public_planting_map` using the anon key.

## Known limits and follow-ups

- **Human spam:** Turnstile blocks bots, not people submitting by hand. If that becomes a problem, add per-IP rate limiting, for example a table of hashed IPs and timestamps checked in the function before inserting.
- **Moderation:** submissions appear on the map immediately. To review them first, add `approved boolean not null default false` to `plantings` and filter `public_planting_map` on it.
- **Public base-table reads:** `plantings` still has `select using (true)` for anon, so exact coordinates, `photo_path`, `planted_on`, and `nature_connection` can be read directly, not just through the view. Decide whether that's acceptable. If it isn't, remove the anon select policy and expose only the view, for example by dropping `security_invoker`.
- **Function limits:** Edge Functions have request size and runtime limits. Client-side compression keeps uploads well within them.
