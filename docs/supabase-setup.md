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

```bash
supabase migration new <name>   # creates supabase/migrations/<timestamp>_<name>.sql
```

After editing, apply the changes:

- **Locally:** `supabase db reset` rebuilds the local database from every migration.
- **Hosted, new migration files:** `supabase db push` applies migrations the hosted project hasn't run yet.
- **Hosted, edited migrations:** if you edited a migration that's already been applied (this project has been editing its original migrations), `db push` skips it. Only `supabase db reset --linked` applies the change, and it **deletes all hosted data**.

### After a hosted reset, clear Storage

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
