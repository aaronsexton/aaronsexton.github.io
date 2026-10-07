create extension if not exists postgis with schema extensions;

create type seed_mixture as enum ('full_sun', 'partial_sun');

create table plantings (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  planted_on         date not null,
  title              text not null check (char_length(title) between 1 and 100),
  seed_mixture       seed_mixture not null,
  location           extensions.geography(Point, 4326) not null,
  photo_path         text not null,
  nature_connection  int2 not null check (nature_connection between 1 and 7)
);
create index plantings_location_idx on plantings using gist (location);

-- pii isolated from plantings
create table planting_contacts (
  planting_id  uuid primary key references plantings(id) on delete cascade,
  email        text not null check (email like '%_@_%._%')
);

-- what the public map shows; read only by the submit-planting Edge Function,
-- which writes it to the map-data bucket as plantings.json
create view public_planting_map
  with (security_invoker = true) as
  -- we may need to only select points created in the last 30 days, but for now we want to see all points
  -- ergo created_at is not used in the where clause currently
select id, title, created_at,
       extensions.st_y(location::extensions.geometry) as lat,
       extensions.st_x(location::extensions.geometry) as lng
from plantings;

-- row-level security policies
-- no policies for anon or authenticated: every read and write goes through the
-- submit-planting Edge Function, which uses the service role
alter table plantings enable row level security;
alter table planting_contacts enable row level security;

-- supabase grants anon and authenticated full privileges on public tables by default;
-- revoke them so access doesn't depend on RLS alone
revoke all on plantings, planting_contacts, public_planting_map from anon, authenticated;