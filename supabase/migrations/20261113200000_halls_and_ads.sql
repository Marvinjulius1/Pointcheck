-- Halls (padel venues), the home hall on a profile, and paid hall campaigns in the feed.
--
-- Privacy: the app never stores a player's location. For "Hallen in der Nähe" and for
-- choosing which ads to show it sends a coarse position with each request (rounded here
-- to ~1 km); without one, the coordinates of the player's home hall are used.
--
-- Halls and campaigns are created by the Pointcheck team in the SQL editor (see
-- supabase/README.md). Hall staff linked in `hall_managers` can read their campaign report.

-- ---------------------------------------------------------------- halls

create table if not exists public.halls (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 2 and 60),
    street text check (char_length(street) <= 100),
    postal_code text check (postal_code ~ '^[0-9]{4,5}$'),
    city text not null check (char_length(city) between 2 and 60),
    latitude double precision not null check (latitude between -90 and 90),
    longitude double precision not null check (longitude between -180 and 180),
    logo_path text,                  -- file in the storage bucket `halls`
    website_url text check (website_url ~ '^https://'),
    booking_url text check (booking_url ~ '^https://'),
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

create index if not exists halls_location_idx on public.halls (latitude, longitude);

alter table public.halls enable row level security;
drop policy if exists "halls: active readable" on public.halls;
create policy "halls: active readable" on public.halls
    for select to authenticated using (is_active);
revoke all on public.halls from anon, authenticated;
grant select on public.halls to authenticated;

-- Great-circle distance in kilometres (haversine; no PostGIS needed at this size).
create or replace function public.distance_km(lat1 double precision, lon1 double precision,
                                              lat2 double precision, lon2 double precision)
returns double precision
language sql immutable parallel safe set search_path = ''
as $$
    select 2 * 6371 * asin(sqrt(
        power(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
    ));
$$;

-- ---------------------------------------------------------------- home hall on the profile

alter table public.profiles
    add column if not exists home_hall_id uuid references public.halls (id) on delete set null;
create index if not exists profiles_home_hall_idx on public.profiles (home_hall_id);
grant update (home_hall_id) on public.profiles to authenticated;

-- With a home hall, `home_club` shows its name (search, suggestions and the profile page
-- keep working unchanged). Without one, `home_club` stays a free text such as a city.
create or replace function public.sync_home_club()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if new.home_hall_id is not null then
        select h.name into new.home_club from public.halls h where h.id = new.home_hall_id;
    end if;
    return new;
end;
$$;

drop trigger if exists profiles_sync_home_club on public.profiles;
create trigger profiles_sync_home_club
    before insert or update of home_hall_id, home_club on public.profiles
    for each row execute function public.sync_home_club();

-- Where "near me" is: the coarse position from the app, else my home hall.
create or replace function public.reference_point(p_lat double precision, p_lon double precision)
returns table (lat double precision, lon double precision)
language sql stable security definer set search_path = ''
as $$
    select lat, lon from (
        select round(p_lat::numeric, 2)::double precision as lat, round(p_lon::numeric, 2)::double precision as lon, 0 as rank
        where p_lat between -90 and 90 and p_lon between -180 and 180
        union all
        select h.latitude, h.longitude, 1
        from public.profiles p join public.halls h on h.id = p.home_hall_id
        where p.id = auth.uid()
    ) points
    order by rank
    limit 1;
$$;

-- Halls for the picker: by name / city / postal code, or the nearest ones without a query.
create or replace function public.search_halls(p_query text default null,
                                               p_lat double precision default null,
                                               p_lon double precision default null)
returns table (id uuid, name text, city text, postal_code text, logo_path text,
               distance_km double precision, players integer)
language sql stable security definer set search_path = ''
as $$
    with q as (select lower(trim(coalesce(p_query, ''))) as text),
    origin as (select * from public.reference_point(p_lat, p_lon))
    select h.id, h.name, h.city, h.postal_code, h.logo_path,
           round(public.distance_km(o.lat, o.lon, h.latitude, h.longitude)::numeric, 1)::double precision,
           (select count(*)::int from public.profiles p where p.home_hall_id = h.id)
    from public.halls h
    cross join q
    left join origin o on true
    where auth.uid() is not null
      and h.is_active
      and (q.text = ''
           or lower(h.name) like '%' || q.text || '%'
           or lower(h.city) like q.text || '%'
           or h.postal_code like q.text || '%')
      and (q.text <> '' or o.lat is not null)
    order by public.distance_km(o.lat, o.lon, h.latitude, h.longitude) nulls last, h.name
    limit 30;
$$;

-- ---------------------------------------------------------------- campaigns

create table if not exists public.hall_campaigns (
    id uuid primary key default gen_random_uuid(),
    hall_id uuid not null references public.halls (id) on delete cascade,
    headline text not null check (char_length(headline) between 3 and 80),
    body text not null default '' check (char_length(body) <= 300),
    image_path text,                 -- file in the storage bucket `halls`
    cta_label text not null default 'Mehr erfahren' check (char_length(cta_label) between 2 and 24),
    cta_url text not null check (cta_url ~ '^https://'),
    radius_km integer not null default 25 check (radius_km between 1 and 200),
    starts_at timestamptz not null default now(),
    ends_at timestamptz not null,
    -- Paid volume; the campaign stops once it is reached (null = unlimited, e.g. flat fee).
    max_impressions integer check (max_impressions > 0),
    -- How often one player sees this campaign per day at most.
    daily_cap_per_player integer not null default 3 check (daily_cap_per_player between 1 and 20),
    is_paused boolean not null default false,
    price_cents integer check (price_cents >= 0),   -- what the hall pays, for the report
    created_at timestamptz not null default now(),
    check (ends_at > starts_at)
);

create index if not exists hall_campaigns_running_idx on public.hall_campaigns (ends_at) where not is_paused;

alter table public.hall_campaigns enable row level security;
revoke all on public.hall_campaigns from anon, authenticated;
-- No direct access: players get ads through feed_ads(), hall staff through campaign_report().

-- Hall staff accounts (for reports now, a self-service dashboard later).
create table if not exists public.hall_managers (
    hall_id uuid not null references public.halls (id) on delete cascade,
    profile_id uuid not null references public.profiles (id) on delete cascade,
    primary key (hall_id, profile_id)
);
alter table public.hall_managers enable row level security;
revoke all on public.hall_managers from anon, authenticated;

-- Impressions and clicks. The player is stored for frequency caps and unique reach only;
-- nobody reads these rows directly, reports are aggregated.
create table if not exists public.ad_events (
    id bigint generated always as identity primary key,
    campaign_id uuid not null references public.hall_campaigns (id) on delete cascade,
    profile_id uuid not null references public.profiles (id) on delete cascade,
    kind text not null check (kind in ('impression', 'click')),
    created_at timestamptz not null default now()
);
create index if not exists ad_events_campaign_idx on public.ad_events (campaign_id, kind, created_at);
create index if not exists ad_events_player_idx on public.ad_events (profile_id, campaign_id, created_at);
alter table public.ad_events enable row level security;
revoke all on public.ad_events from anon, authenticated;

-- A campaign may be shown right now (dates, pause, paid volume not used up).
create or replace function public.campaign_is_running(p_campaign uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select coalesce((select not c.is_paused
       and now() >= c.starts_at and now() < c.ends_at
       and (c.max_impressions is null
            or (select count(*) from public.ad_events e
                where e.campaign_id = c.id and e.kind = 'impression') < c.max_impressions)
       and exists (select 1 from public.halls h where h.id = c.hall_id and h.is_active)
    from public.hall_campaigns c where c.id = p_campaign), false);
$$;

-- Ads for my feed: running campaigns of halls within their radius of me, not over the
-- daily cap for me. Halls I have not seen today come first, otherwise mixed randomly.
create or replace function public.feed_ads(p_lat double precision default null,
                                           p_lon double precision default null,
                                           p_limit integer default 3)
returns table (campaign_id uuid, hall_id uuid, hall_name text, hall_city text, hall_logo text,
               headline text, body text, image_path text, cta_label text, cta_url text,
               distance_km double precision)
language sql volatile security definer set search_path = ''
as $$
    with origin as (select * from public.reference_point(p_lat, p_lon)),
    candidates as (
        select c.*, h.name as hall_name, h.city as hall_city, h.logo_path as hall_logo,
               public.distance_km(o.lat, o.lon, h.latitude, h.longitude) as km,
               (select count(*) from public.ad_events e
                 where e.campaign_id = c.id and e.profile_id = auth.uid() and e.kind = 'impression'
                   and e.created_at > date_trunc('day', now())) as seen_today
        from public.hall_campaigns c
        join public.halls h on h.id = c.hall_id
        cross join origin o
        -- cheap box first (1° latitude ≈ 111 km), exact distance below
        where h.latitude between o.lat - c.radius_km / 111.0 and o.lat + c.radius_km / 111.0
    )
    select id, hall_id, hall_name, hall_city, hall_logo, headline, body, image_path, cta_label, cta_url,
           round(km::numeric, 1)::double precision
    from candidates c
    where auth.uid() is not null
      and c.km <= c.radius_km
      and c.seen_today < c.daily_cap_per_player
      and public.campaign_is_running(c.id)
    order by (c.seen_today = 0) desc, random()
    limit least(greatest(coalesce(p_limit, 3), 1), 5);
$$;

-- The app reports an impression (ad came on screen) or a click (button tapped).
-- Repeated impressions of the same campaign within 30 minutes count once.
create or replace function public.log_ad_event(p_campaign uuid, p_kind text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
    if auth.uid() is null or p_kind not in ('impression', 'click') then
        raise exception 'not allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from public.hall_campaigns c where c.id = p_campaign) then
        return;
    end if;
    if p_kind = 'impression' and exists (
        select 1 from public.ad_events e
        where e.campaign_id = p_campaign and e.profile_id = auth.uid() and e.kind = 'impression'
          and e.created_at > now() - interval '30 minutes'
    ) then
        return;
    end if;
    insert into public.ad_events (campaign_id, profile_id, kind) values (p_campaign, auth.uid(), p_kind);
end;
$$;

-- Per campaign and day: impressions, players reached, clicks. For the Pointcheck team
-- in the SQL editor (`select * from public.campaign_stats`); not exposed to the app.
create or replace view public.campaign_stats
with (security_invoker = true)
as
select c.id as campaign_id, h.name as hall, c.headline,
       date_trunc('day', e.created_at)::date as day,
       count(*) filter (where e.kind = 'impression') as impressions,
       count(distinct e.profile_id) filter (where e.kind = 'impression') as players_reached,
       count(*) filter (where e.kind = 'click') as clicks
from public.hall_campaigns c
join public.halls h on h.id = c.hall_id
join public.ad_events e on e.campaign_id = c.id
group by c.id, h.name, c.headline, date_trunc('day', e.created_at);
revoke all on public.campaign_stats from anon, authenticated;

-- Report for hall staff: totals of one campaign of a hall they manage.
create or replace function public.campaign_report(p_campaign uuid)
returns table (campaign_id uuid, hall text, headline text, starts_at timestamptz, ends_at timestamptz,
               impressions integer, players_reached integer, clicks integer, click_rate double precision)
language sql stable security definer set search_path = ''
as $$
    select c.id, h.name, c.headline, c.starts_at, c.ends_at,
           count(*) filter (where e.kind = 'impression')::int,
           count(distinct e.profile_id) filter (where e.kind = 'impression')::int,
           count(*) filter (where e.kind = 'click')::int,
           case when count(*) filter (where e.kind = 'impression') = 0 then 0
                else round((count(*) filter (where e.kind = 'click'))::numeric
                           / count(*) filter (where e.kind = 'impression'), 4)::double precision end
    from public.hall_campaigns c
    join public.halls h on h.id = c.hall_id
    left join public.ad_events e on e.campaign_id = c.id
    where c.id = p_campaign
      and exists (select 1 from public.hall_managers m where m.hall_id = c.hall_id and m.profile_id = auth.uid())
    group by c.id, h.name;
$$;

revoke execute on function public.reference_point(double precision, double precision),
    public.campaign_is_running(uuid), public.sync_home_club()
    from public, anon, authenticated;
revoke execute on function public.search_halls(text, double precision, double precision),
    public.feed_ads(double precision, double precision, integer), public.log_ad_event(uuid, text),
    public.campaign_report(uuid)
    from public, anon;
grant execute on function public.search_halls(text, double precision, double precision),
    public.feed_ads(double precision, double precision, integer), public.log_ad_event(uuid, text),
    public.campaign_report(uuid)
    to authenticated;
