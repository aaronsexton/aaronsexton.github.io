# Supabase CLI setup

This guide covers installing the Supabase CLI and connecting this repo to the hosted project, SprinklingSeeds (ref `iiimikqpfwvktlmvfvtj`). To run Supabase on your own machine, see [local-development.md](local-development.md).

## Install

macOS (see the Supabase docs for other platforms):

```bash
brew install supabase/tap/supabase
supabase --version
```

Running Supabase locally also needs **Docker Desktop**. Logging in and linking don't.

## Connect to the hosted project

```bash
cd aaronsexton.github.io
supabase login                                   # opens a browser to authorize the CLI
supabase link --project-ref iiimikqpfwvktlmvfvtj # prompts for the database password
```

Linking saves the project ref in `supabase/.temp/`, which is git-ignored. Each person links their own checkout.

### How the repo was first set up

Don't repeat this; `supabase/` is already committed.

```bash
supabase init                           # created supabase/config.toml
supabase migration new create_plantings # created a timestamped file in supabase/migrations/
supabase db push                        # applied it to the hosted project
```

## Changing the database

The hosted database holds real submissions. **Never edit a migration that's already been applied.** `db push` skips edited files, and the only way to apply an edit is a hosted reset, which deletes all data. Make every change in a new migration file instead.

CI doesn't apply migrations. [deploy.yml](../.github/workflows/deploy.yml) deploys only the site and the Edge Function, so a person runs `db push` by hand.

### 1. Write and test it locally

Run all commands from the repo root.

```bash
supabase migration new <name>   # creates supabase/migrations/<timestamp>_<name>.sql
```

Write the SQL, then apply and test it on the local stack (see [local-development.md](local-development.md)):

```bash
supabase db reset               # local only: rebuilds from every migration
scripts/test-local.sh
```

Before pushing, read the new file for `drop`, `truncate`, `delete`, `alter ... type`, or anything else that removes or rewrites data. `create or replace function` and adding a column or table are safe.

### 2. Back up the hosted database

The project has no point-in-time recovery, so these dumps may be the only backup. Save them **outside the repo**, because the data dump contains contributors' emails:

```bash
supabase db dump --linked -f ~/sprinkling-seeds-schema-backup-$(date +%F).sql
supabase db dump --linked --data-only -f ~/sprinkling-seeds-data-backup-$(date +%F).sql
```

### 3. Preview the push

```bash
supabase db push --dry-run
```

It should list **only** the new migration file or files. If it lists anything else, stop and run `supabase migration list` to find out why before pushing.

### 4. Apply it

```bash
supabase db push
supabase migration list         # the new migration now shows on both Local and Remote
```

### 5. Deploy the code that depends on it

Push the migration **before** merging to `main` if the Edge Function or site relies on it. CI deploys them on merge, and new code running against the old database can fail. For example, the optional-email change (`20261111201752_make_email_optional.sql`) needed the new `submit_planting` live before the function started sending null emails.

### Hosted reset (deletes all data)

`supabase db reset --linked` drops the hosted database and reapplies every migration. **It deletes every planting and contact.** Don't use it now that the site has real submissions. Write a new migration instead.

#### After a hosted reset, clear Storage

A reset doesn't touch Storage files. The map would keep showing plantings from `map-data/plantings.json` that no longer exist, and old photos would keep using quota. Delete them in the dashboard (**Storage → map-data** and **Storage → planting-photos**) or with the CLI:

```bash
supabase storage rm ss:///map-data/plantings.json --linked --experimental
supabase storage rm -r ss:///planting-photos --linked --experimental
```

The site treats a missing snapshot as an empty map, and the next submission recreates it.

Run `supabase migration list` to compare local migrations with those applied to the linked project.

## Useful commands

| Command | Does |
| --- | --- |
| `supabase status` | Local URLs and keys (local stack only) |
| `supabase migration list` | Which migrations the linked project has applied |
| `supabase secrets list` | Edge Function secret names (values are never shown) |
| `supabase secrets set NAME=value` | Set an Edge Function secret on the linked project |
| `scripts/deploy-function.sh` | Type-check, deploy and smoke-test the Edge Function |

Secrets and tokens are covered in [environment-and-secrets.md](environment-and-secrets.md).
