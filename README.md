# aaronsexton.github.io

## Supabase

```bash
# Install the CLI (macOS shown; see Supabase docs for other platforms)
brew install supabase/tap/supabase

cd aaronsexton.github.io
supabase init
supabase login
supabase link --project-ref iiimikqpfwvktlmvfvtj

# Create a timestamped migration file in migrations
supabase migration new create_plantings

supabase db push
```

### Deploy Edge Function

```bash
supabase secrets set TURNSTILE_SECRET=xxx
# verify secret key appears
supabase secrets list
# deploy function (type-checks, confirms the secret, deploys, then smoke-tests)
scripts/deploy-function.sh
# or run the checks without deploying
scripts/deploy-function.sh --dry-run
```