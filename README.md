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