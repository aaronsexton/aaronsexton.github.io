insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'planting-photos',
  'planting-photos',
  false,                                  -- private: only the service role can read
  15 * 1024 * 1024,                       -- 15 MB cap
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
-- buckets survive db reset, so overwrite existing settings instead of skipping
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- map snapshot (plantings.json) written by the submit-planting Edge Function
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'map-data',
  'map-data',
  true,                                   -- public read via URL, served through the CDN
  5 * 1024 * 1024,                        -- 5 MB cap
  array['application/json']
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- no storage.objects policies: anon can't read private files, upload, list, or delete.
-- map-data is public so its file is served by URL without a policy; only the service role writes
