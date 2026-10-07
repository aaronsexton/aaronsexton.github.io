# Environment configuration and secrets

This doc lists every configuration value and secret the project uses: where each one lives, how it was created, how it was uploaded, and how to rotate it. **It contains no secret values. Never add any.**

## Summary

| Name | What it is | Sensitive? | Where it lives | Used by |
| --- | --- | --- | --- | --- |
| `PUBLIC_SUPABASE_URL` | Supabase project URL | No (embedded in the site) | GitHub repo secret; `.env.development` locally | Astro build |
| `PUBLIC_TURNSTILE_SITE_KEY` | Cloudflare Turnstile site key | No (embedded in the site) | GitHub repo secret; `.env.development` locally | Astro build |
| `TURNSTILE_SECRET` | Cloudflare Turnstile secret key | **Yes** | Supabase Edge Function secret; `supabase/functions/.env` locally (test value) | `submit-planting` function |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token | **Yes**: deploys functions | GitHub repo secret | `deploy-function` job in `deploy.yml` |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, … | Set by Supabase | **Yes** (service role) | Injected into Edge Functions by Supabase | `submit-planting` function |

**Why the public values are safe:** anything with the `PUBLIC_` prefix is built into the site's JavaScript and is visible to every visitor. That's expected. The site never queries the database; it only calls the Edge Function and reads the public map snapshot. Security comes from database permissions and the Edge Function, not from hiding these values. See [submission-edge-function-plan.md](submission-edge-function-plan.md).

## Cloudflare Turnstile

Turnstile is Cloudflare's bot check on the submission form.

**Dashboard:** [Cloudflare Turnstile](https://dash.cloudflare.com/6164219a5ca0f9a5998e563bb6782ca4/turnstile). Sign in to the Cloudflare account that owns the widget.

**Created** in the Cloudflare dashboard under **Turnstile → Add widget**:

- Widget name: `sprinklingseeds - planting form`
- Hostname: `aaronsexton.github.io`
- Widget mode: Managed
- Pre-clearance: No

This produces two keys:

- **Site key**, which is public. It's uploaded to GitHub as `PUBLIC_TURNSTILE_SITE_KEY`. At build time it's embedded in the form.
- **Secret key**, which is sensitive. It's uploaded to Supabase as `TURNSTILE_SECRET`. The Edge Function uses it to verify each submission's token with Cloudflare.

**Uploaded:**

```bash
supabase secrets set --project-ref iiimikqpfwvktlmvfvtj TURNSTILE_SECRET=<secret key>
gh secret set PUBLIC_TURNSTILE_SITE_KEY -R aaronsexton/aaronsexton.github.io   # prompts for the value
```

`TURNSTILE_SECRET` was set on 2026-10-03, and `PUBLIC_TURNSTILE_SITE_KEY` was added to GitHub the same day.

**Local development** uses Cloudflare's test keys, which always pass:

- site key `1x00000000000000000000AA`
- secret `1x0000000000000000000000000000000AA`

To test failures, swap in `2x00000000000000000000AB` and `2x0000000000000000000000000000000AA`, which always fail.

**Rotate** from the widget's settings in Cloudflare:

1. Run `supabase secrets set` with the new secret.
2. Update the GitHub secret if the site key changed, then redeploy the site.

**If the site moves to a custom domain:** add the domain to the widget's hostnames, and to `ALLOWED_ORIGINS` in [supabase/functions/submit-planting/index.ts](../supabase/functions/submit-planting/index.ts).

## Supabase project

- **Project:** SprinklingSeeds, ref `iiimikqpfwvktlmvfvtj`
- **URL:** `https://iiimikqpfwvktlmvfvtj.supabase.co`. Use the base URL only; `supabase-js` and the site add `/rest/v1`, `/functions/v1` and so on.

`PUBLIC_SUPABASE_URL` was uploaded to GitHub on 2026-10-03 with `gh secret set PUBLIC_SUPABASE_URL -R aaronsexton/aaronsexton.github.io`.

The project ref is also hardcoded in [scripts/deploy-function.sh](../scripts/deploy-function.sh), so deploys can only target this project.

### Keys Supabase injects

Supabase supplies `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` and related values to every Edge Function. Nobody sets them. The service role key bypasses all database permissions, so it must never leave the function, and must never appear in the site, the repo or a `PUBLIC_` variable.

### Anon / publishable key

The anon key isn't used. The site doesn't query Supabase directly, and anon has no database privileges. A leftover `PUBLIC_SUPABASE_ANON_KEY` GitHub secret from 2026-10-03 was deleted on 2026-10-07.

## Supabase access token (CI deploys)

This token lets the `deploy-function` job in [deploy.yml](../.github/workflows/deploy.yml) deploy the Edge Function. The Supabase CLI reads it from the `SUPABASE_ACCESS_TOKEN` environment variable, so CI never runs `supabase login`.

**Created** in the Supabase dashboard under **Account preferences → Access Tokens → Generate new token**, with:

- **Edge Functions:** read and write, for `supabase functions deploy`.
- **Edge Function secrets:** read, for the script's check that `TURNSTILE_SECRET` exists. This only returns secret names and hashes, never values.
- Nothing else: no database, auth, storage, billing or organization access.
- Limited to the SprinklingSeeds project, with an expiry date.

**Uploaded** on 2026-10-07 as a repository secret:

```bash
gh secret set SUPABASE_ACCESS_TOKEN -R aaronsexton/aaronsexton.github.io   # prompts for the value
```

**Verify a new token locally before relying on it.** Don't paste tokens into chats or commit them.

```bash
SUPABASE_ACCESS_TOKEN=<token> scripts/deploy-function.sh --dry-run   # secrets read
SUPABASE_ACCESS_TOKEN=<token> scripts/deploy-function.sh             # deploy (same code, harmless)
```

**Security notes:**

- **Any workflow can read it.** It's a repository secret rather than an environment secret, because creating environments needs admin access and the maintainer uploading it is a collaborator. Anyone with write access can read it through a workflow, so keep write access to trusted people. If an admin creates a protected environment later, move the token there.
- **Forks can't read it.** GitHub doesn't give secrets to pull-request runs from forks.

**Rotate** before it expires, or immediately if it's exposed:

1. Generate a new token with the same permissions.
2. Run `gh secret set` again.
3. Delete the old token in Supabase.

## GitHub

Repo: `aaronsexton/aaronsexton.github.io`, which is public.

- **Repository secrets:** `PUBLIC_SUPABASE_URL`, `PUBLIC_TURNSTILE_SITE_KEY` and `SUPABASE_ACCESS_TOKEN`.
- **The public values are stored as secrets, not variables.** The workflow reads them with `${{ secrets.* }}`. GitHub masks them in logs, which is harmless.
- **Collaborators** can't see secrets in the settings UI, but can manage them with `gh secret set`, `gh secret list` and `gh secret delete`. Run `gh secret list -R aaronsexton/aaronsexton.github.io` to see names and update dates.
- **Pages setting:** Pages is set to deploy from the `main` branch root ("legacy" mode), and the Actions workflow also deploys. Both run on every push, and whichever finishes last is what the site shows. An admin can remove that race under **Settings → Pages → Source → GitHub Actions**.

## Local files

Both of these files are git-ignored by the `.env*` rule, and both contain only local and test values. Setup steps are in [local-development.md](local-development.md).

| File | Contents |
| --- | --- |
| `.env.development` | `PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` and the Turnstile test site key. Read by `npm run dev`. |
| `supabase/functions/.env` | The Turnstile test secret. Loaded by `supabase functions serve --env-file supabase/functions/.env`. |

Local Supabase keys, such as the anon and service role keys, are fixed defaults printed by `supabase status`. They only work against the local instance.

## Settings in code

These values live in the code, not in environment variables:

| Setting | Where |
| --- | --- |
| Project ref for deploys | `scripts/deploy-function.sh` |
| Origins allowed to call the function (`ALLOWED_ORIGINS`) | `supabase/functions/submit-planting/index.ts` |
| Map style, satellite tiles, starting center and zoom | `src/lib/config.ts` |
| Bucket privacy, size limits and allowed file types | `supabase/migrations/20261003193456_create_plantings.sql` |
| Function JWT setting (`verify_jwt = false`) | `supabase/config.toml` |

## If a secret leaks

| Leaked | Do this |
| --- | --- |
| `TURNSTILE_SECRET` | Rotate the secret key in Cloudflare, then `supabase secrets set` the new one |
| `SUPABASE_ACCESS_TOKEN` | Delete the token in Supabase now, create a new one, then `gh secret set` it |
| Service role key | Rotate it under Supabase **Project Settings → API Keys**, then redeploy the function |
| Database password | Reset it under Supabase **Project Settings → Database** |
