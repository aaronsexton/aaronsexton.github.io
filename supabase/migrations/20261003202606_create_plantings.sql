-- inserts a planting and its optional contact in one transaction
-- called only by the submit-planting Edge Function with the service role
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

-- postgres grants execute to public by default; without this, anon could call it directly
revoke execute on function public.submit_planting from public, anon, authenticated;
grant execute on function public.submit_planting to service_role;
