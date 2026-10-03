insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'planting-photos',
  'planting-photos',
  true,                                   -- public read via URL
  15 * 1024 * 1024,                       -- 15 MB cap
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do nothing;

-- anon can upload, but only into this bucket
create policy "Anyone can upload planting photos"
  on storage.objects for insert to anon
  with check (bucket_id = 'planting-photos');
