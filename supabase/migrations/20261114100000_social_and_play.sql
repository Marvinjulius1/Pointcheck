-- Reactions (👏), comments, rematch requests, "Spieler gesucht" games, club page,
-- head-to-head, device tokens for push, account deletion, and mentions in the feed.
-- Re-runnable.

-- ---------------------------------------------------------------------------
-- Reactions
-- ---------------------------------------------------------------------------

create table if not exists public.reactions (
    post_id uuid not null references public.posts (id) on delete cascade,
    profile_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, profile_id)
);
create index if not exists reactions_post_idx on public.reactions (post_id);

alter table public.reactions enable row level security;
drop policy if exists "reactions: visible posts" on public.reactions;
create policy "reactions: visible posts" on public.reactions
    for select to authenticated
    using (exists (select 1 from public.posts p where p.id = post_id and public.can_view_profile(p.author_id)));
drop policy if exists "reactions: own" on public.reactions;
create policy "reactions: own" on public.reactions
    for insert to authenticated
    with check (profile_id = auth.uid()
                and exists (select 1 from public.posts p where p.id = post_id and public.can_view_profile(p.author_id)));
drop policy if exists "reactions: remove own" on public.reactions;
create policy "reactions: remove own" on public.reactions
    for delete to authenticated using (profile_id = auth.uid());

revoke all on public.reactions from anon, authenticated;
grant select, delete on public.reactions to authenticated;
grant insert (post_id) on public.reactions to authenticated;

-- Counts and my own reaction for a set of posts.
create or replace function public.reaction_summary(p_posts uuid[])
returns table (post_id uuid, claps integer, clapped boolean)
language sql stable security definer set search_path = ''
as $$
    select p.id,
           (select count(*)::int from public.reactions r where r.post_id = p.id),
           exists (select 1 from public.reactions r where r.post_id = p.id and r.profile_id = auth.uid())
    from unnest(p_posts) as p(id);
$$;

create or replace function public.reactors(p_post uuid)
returns table (profile_id uuid, display_name text, username text, avatar_path text, relation text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path, public.follow_relation(p.id)
    from public.reactions r
    join public.profiles p on p.id = r.profile_id
    join public.posts po on po.id = r.post_id
    where r.post_id = p_post and public.can_view_profile(po.author_id)
    order by r.created_at desc
    limit 100;
$$;

-- ---------------------------------------------------------------------------
-- Comments (on posts or on confirmed matches)
-- ---------------------------------------------------------------------------

create table if not exists public.comments (
    id uuid primary key default gen_random_uuid(),
    post_id uuid references public.posts (id) on delete cascade,
    match_id uuid references public.matches (id) on delete cascade,
    author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    text text not null check (char_length(text) between 1 and 500),
    created_at timestamptz not null default now(),
    check ((post_id is null) <> (match_id is null))
);
create index if not exists comments_post_idx on public.comments (post_id, created_at);
create index if not exists comments_match_idx on public.comments (match_id, created_at);

alter table public.comments enable row level security;

create or replace function public.can_view_comment_target(p_post uuid, p_match uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select case
        when p_post is not null then exists (select 1 from public.posts p where p.id = p_post and public.can_view_profile(p.author_id))
        when p_match is not null then public.can_view_match(p_match)
        else false
    end;
$$;
grant execute on function public.can_view_comment_target(uuid, uuid) to authenticated;

drop policy if exists "comments: visible targets" on public.comments;
create policy "comments: visible targets" on public.comments
    for select to authenticated using (public.can_view_comment_target(post_id, match_id));
drop policy if exists "comments: write own" on public.comments;
create policy "comments: write own" on public.comments
    for insert to authenticated
    with check (author_id = auth.uid() and public.can_view_comment_target(post_id, match_id));
drop policy if exists "comments: delete own" on public.comments;
create policy "comments: delete own" on public.comments
    for delete to authenticated using (author_id = auth.uid());

revoke all on public.comments from anon, authenticated;
grant select, delete on public.comments to authenticated;
grant insert (id, post_id, match_id, text) on public.comments to authenticated;

create or replace function public.comments_for(p_post uuid default null, p_match uuid default null)
returns table (id uuid, author_id uuid, author_name text, author_avatar text, text text, created_at timestamptz)
language sql stable security definer set search_path = ''
as $$
    select c.id, c.author_id, p.display_name, p.avatar_path, c.text, c.created_at
    from public.comments c
    join public.profiles p on p.id = c.author_id
    where ((p_post is not null and c.post_id = p_post) or (p_match is not null and c.match_id = p_match))
      and public.can_view_comment_target(c.post_id, c.match_id)
    order by c.created_at
    limit 200;
$$;

create or replace function public.comment_counts(p_posts uuid[], p_matches uuid[])
returns table (post_id uuid, match_id uuid, comments integer)
language sql stable security definer set search_path = ''
as $$
    select c.post_id, c.match_id, count(*)::int
    from public.comments c
    where c.post_id = any(coalesce(p_posts, '{}')) or c.match_id = any(coalesce(p_matches, '{}'))
    group by c.post_id, c.match_id;
$$;

-- ---------------------------------------------------------------------------
-- Rematch requests
-- ---------------------------------------------------------------------------

do $$ begin
    if not exists (select 1 from pg_type where typname = 'request_status') then
        create type public.request_status as enum ('pending', 'accepted', 'declined');
    end if;
end $$;

create table if not exists public.rematch_requests (
    id uuid primary key default gen_random_uuid(),
    from_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    to_id uuid not null references public.profiles (id) on delete cascade,
    match_id uuid references public.matches (id) on delete set null,
    proposed_at timestamptz not null,
    note text check (char_length(note) <= 200),
    status public.request_status not null default 'pending',
    created_at timestamptz not null default now(),
    check (from_id <> to_id)
);
create index if not exists rematch_to_idx on public.rematch_requests (to_id, status);

alter table public.rematch_requests enable row level security;
drop policy if exists "rematch: involved" on public.rematch_requests;
create policy "rematch: involved" on public.rematch_requests
    for select to authenticated using (auth.uid() in (from_id, to_id));
drop policy if exists "rematch: propose" on public.rematch_requests;
create policy "rematch: propose" on public.rematch_requests
    for insert to authenticated with check (from_id = auth.uid() and status = 'pending');
drop policy if exists "rematch: withdraw" on public.rematch_requests;
create policy "rematch: withdraw" on public.rematch_requests
    for delete to authenticated using (from_id = auth.uid());

revoke all on public.rematch_requests from anon, authenticated;
grant select, delete on public.rematch_requests to authenticated;
grant insert (to_id, match_id, proposed_at, note) on public.rematch_requests to authenticated;

create or replace function public.respond_rematch(p_request uuid, p_accept boolean)
returns void
language sql security definer set search_path = ''
as $$
    update public.rematch_requests
    set status = case when p_accept then 'accepted'::public.request_status else 'declined'::public.request_status end
    where id = p_request and to_id = auth.uid() and status = 'pending';
$$;

create or replace function public.my_rematches()
returns table (
    id uuid, from_id uuid, to_id uuid, other_name text, other_avatar text, incoming boolean,
    proposed_at timestamptz, note text, status public.request_status, created_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
    select r.id, r.from_id, r.to_id, p.display_name, p.avatar_path, r.to_id = auth.uid(),
           r.proposed_at, r.note, r.status, r.created_at
    from public.rematch_requests r
    join public.profiles p on p.id = case when r.from_id = auth.uid() then r.to_id else r.from_id end
    where auth.uid() in (r.from_id, r.to_id)
      and (r.status = 'pending' or r.proposed_at > now() - interval '1 day')
    order by r.proposed_at;
$$;

-- ---------------------------------------------------------------------------
-- "Spieler gesucht"
-- ---------------------------------------------------------------------------

create table if not exists public.games_wanted (
    id uuid primary key default gen_random_uuid(),
    host_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    starts_at timestamptz not null,
    club text check (char_length(club) <= 60),
    court text check (char_length(court) <= 20),
    players_needed integer not null default 1 check (players_needed between 1 and 3),
    note text check (char_length(note) <= 200),
    created_at timestamptz not null default now()
);
create index if not exists games_wanted_start_idx on public.games_wanted (starts_at);

create table if not exists public.game_joins (
    game_id uuid not null references public.games_wanted (id) on delete cascade,
    profile_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (game_id, profile_id)
);

alter table public.games_wanted enable row level security;
alter table public.game_joins enable row level security;

-- Everyone signed in sees open games (that is the point); hosts manage their own.
drop policy if exists "games: read" on public.games_wanted;
create policy "games: read" on public.games_wanted for select to authenticated using (true);
drop policy if exists "games: host" on public.games_wanted;
create policy "games: host" on public.games_wanted for insert to authenticated with check (host_id = auth.uid());
drop policy if exists "games: host delete" on public.games_wanted;
create policy "games: host delete" on public.games_wanted for delete to authenticated using (host_id = auth.uid());

drop policy if exists "joins: read" on public.game_joins;
create policy "joins: read" on public.game_joins for select to authenticated using (true);
drop policy if exists "joins: own" on public.game_joins;
create policy "joins: own" on public.game_joins for insert to authenticated with check (profile_id = auth.uid());
drop policy if exists "joins: leave" on public.game_joins;
create policy "joins: leave" on public.game_joins for delete to authenticated
    using (profile_id = auth.uid() or exists (select 1 from public.games_wanted g where g.id = game_id and g.host_id = auth.uid()));

revoke all on public.games_wanted, public.game_joins from anon, authenticated;
grant select, delete on public.games_wanted to authenticated;
grant insert (id, starts_at, club, court, players_needed, note) on public.games_wanted to authenticated;
grant select, delete on public.game_joins to authenticated;
grant insert (game_id) on public.game_joins to authenticated;

-- Upcoming games, optionally for one club; with host, joined count and whether I joined.
create or replace function public.open_games(p_club text default null)
returns table (
    id uuid, host_id uuid, host_name text, host_avatar text, starts_at timestamptz, club text, court text,
    players_needed integer, note text, joined integer, joined_names text, i_joined boolean, is_host boolean
)
language sql stable security definer set search_path = ''
as $$
    select g.id, g.host_id, p.display_name, p.avatar_path, g.starts_at, g.club, g.court, g.players_needed, g.note,
           (select count(*)::int from public.game_joins j where j.game_id = g.id),
           (select string_agg(pp.display_name, ', ' order by j.created_at)
              from public.game_joins j join public.profiles pp on pp.id = j.profile_id where j.game_id = g.id),
           exists (select 1 from public.game_joins j where j.game_id = g.id and j.profile_id = auth.uid()),
           g.host_id = auth.uid()
    from public.games_wanted g
    join public.profiles p on p.id = g.host_id
    where auth.uid() is not null
      and g.starts_at > now() - interval '2 hours'
      and (p_club is null or lower(g.club) = lower(p_club))
    order by g.starts_at
    limit 100;
$$;

-- ---------------------------------------------------------------------------
-- Club page
-- ---------------------------------------------------------------------------

-- Ranking of a club: public profiles plus everyone I may see, with rated matches.
create or replace function public.club_ranking(p_club text)
returns table (profile_id uuid, display_name text, username text, avatar_path text, rating double precision, rated_matches integer, relation text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path, p.rating, p.rated_matches, public.follow_relation(p.id)
    from public.profiles p
    where auth.uid() is not null
      and lower(coalesce(p.home_club, '')) = lower(p_club)
      and public.can_view_profile(p.id)
    order by p.rating desc, p.rated_matches desc
    limit 100;
$$;

-- Active players of a club: at least one confirmed match in the last 30 days.
create or replace function public.club_activity(p_club text)
returns table (players integer, matches_30d integer)
language sql stable security definer set search_path = ''
as $$
    with members as (
        select id from public.profiles where lower(coalesce(home_club, '')) = lower(p_club)
    ),
    recent as (
        select distinct x.id as match_id, mp.profile_id
        from public.matches x
        join public.match_players mp on mp.match_id = x.id
        where x.status = 'confirmed' and x.started_at > now() - interval '30 days'
          and mp.profile_id in (select id from members)
    )
    select (select count(distinct profile_id)::int from recent), (select count(distinct match_id)::int from recent);
$$;

-- ---------------------------------------------------------------------------
-- Head-to-head
-- ---------------------------------------------------------------------------

create or replace function public.head_to_head(p_other uuid)
returns table (against integer, my_wins integer, their_wins integer, together integer, together_wins integer, last_played timestamptz)
language sql stable security definer set search_path = ''
as $$
    with shared as (
        select x.id, x.started_at, x.winner_side, me.side as my_side, o.side as other_side
        from public.matches x
        join public.match_players me on me.match_id = x.id and me.profile_id = auth.uid()
        join public.match_players o on o.match_id = x.id and o.profile_id = p_other
        where x.status = 'confirmed'
    )
    select
        (select count(*)::int from shared where my_side <> other_side),
        (select count(*)::int from shared where my_side <> other_side and winner_side = my_side),
        (select count(*)::int from shared where my_side <> other_side and winner_side = other_side),
        (select count(*)::int from shared where my_side = other_side),
        (select count(*)::int from shared where my_side = other_side and winner_side = my_side),
        (select max(started_at) from shared);
$$;

-- ---------------------------------------------------------------------------
-- Device tokens (push – active once the Apple Developer Program is set up)
-- ---------------------------------------------------------------------------

create table if not exists public.device_tokens (
    token text primary key,
    profile_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    platform text not null default 'ios',
    updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
drop policy if exists "tokens: own" on public.device_tokens;
create policy "tokens: own" on public.device_tokens for all to authenticated
    using (profile_id = auth.uid()) with check (profile_id = auth.uid());
revoke all on public.device_tokens from anon, authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- Delete my account (App Store requirement)
-- ---------------------------------------------------------------------------

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not signed in';
    end if;
    -- Profile rows cascade from auth.users; matches created by me go with the profile.
    delete from auth.users where id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Mentions: feed and profile posts carry the linked players of an attached match
-- (return type changes → drop and recreate)
-- ---------------------------------------------------------------------------

create or replace function public.match_players_json(p_match uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
               'id', mp.profile_id, 'name', coalesce(p.display_name, mp.guest_name), 'side', mp.side, 'slot', mp.slot
           ) order by mp.slot), '[]'::jsonb)
    from public.match_players mp
    left join public.profiles p on p.id = mp.profile_id
    where mp.match_id = p_match;
$$;

drop function if exists public.home_feed(integer, timestamptz);
create function public.home_feed(p_limit integer default 20, p_before timestamptz default null)
returns table (
    kind text,
    id uuid,
    created_at timestamptz,
    author_id uuid,
    author_name text,
    author_username text,
    author_avatar text,
    text text,
    image_path text,
    match_id uuid,
    started_at timestamptz,
    sets jsonb,
    winner_side public.match_side,
    author_side public.match_side,
    partner_name text,
    opponent_names text,
    players jsonb
)
language sql stable security definer set search_path = ''
as $$
    with people as (
        select following_id as id from public.follows where follower_id = auth.uid() and status = 'accepted'
        union select auth.uid()
    ),
    items as (
        select 'post' as kind, po.id, po.created_at, po.author_id, po.text, po.image_path, po.match_id
        from public.posts po
        where po.author_id in (select id from people)
        union all
        select 'match', x.id, coalesce(x.rated_at, x.created_at), x.created_by, null, null, x.id
        from public.matches x
        where x.status = 'confirmed' and x.created_by in (select id from people)
          and not exists (select 1 from public.posts po where po.match_id = x.id and po.author_id = x.created_by)
    )
    select i.kind, i.id, i.created_at, i.author_id, a.display_name, a.username, a.avatar_path,
           i.text, i.image_path, i.match_id, x.started_at, x.sets, x.winner_side, me.side,
           (select coalesce(p.display_name, mp.guest_name)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side = me.side and mp.slot <> me.slot
             order by mp.slot limit 1),
           (select string_agg(coalesce(p.display_name, mp.guest_name), ' & ' order by mp.slot)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side <> me.side),
           case when x.id is not null then public.match_players_json(x.id) end
    from items i
    join public.profiles a on a.id = i.author_id
    left join public.matches x on x.id = i.match_id and public.can_view_match(x.id)
    left join public.match_players me on me.match_id = x.id and me.profile_id = i.author_id
    where auth.uid() is not null
      and (p_before is null or i.created_at < p_before)
      and (i.kind = 'post' or x.id is not null)
    order by i.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

drop function if exists public.profile_posts(uuid, integer, timestamptz);
create function public.profile_posts(p_profile uuid, p_limit integer default 30, p_before timestamptz default null)
returns table (
    id uuid, created_at timestamptz, text text, image_path text, match_id uuid,
    started_at timestamptz, sets jsonb, winner_side public.match_side, author_side public.match_side,
    partner_name text, opponent_names text, players jsonb
)
language sql stable security definer set search_path = ''
as $$
    select po.id, po.created_at, po.text, po.image_path, po.match_id,
           x.started_at, x.sets, x.winner_side, me.side,
           (select coalesce(p.display_name, mp.guest_name)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side = me.side and mp.slot <> me.slot
             order by mp.slot limit 1),
           (select string_agg(coalesce(p.display_name, mp.guest_name), ' & ' order by mp.slot)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side <> me.side),
           case when x.id is not null then public.match_players_json(x.id) end
    from public.posts po
    left join public.matches x on x.id = po.match_id
    left join public.match_players me on me.match_id = x.id and me.profile_id = po.author_id
    where po.author_id = p_profile
      and public.can_view_profile(p_profile)
      and (p_before is null or po.created_at < p_before)
    order by po.created_at desc
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function
    public.reaction_summary(uuid[]), public.reactors(uuid), public.comments_for(uuid, uuid),
    public.comment_counts(uuid[], uuid[]), public.respond_rematch(uuid, boolean), public.my_rematches(),
    public.open_games(text), public.club_ranking(text), public.club_activity(text), public.head_to_head(uuid),
    public.delete_my_account(), public.match_players_json(uuid),
    public.home_feed(integer, timestamptz), public.profile_posts(uuid, integer, timestamptz)
    from public, anon;
grant execute on function
    public.reaction_summary(uuid[]), public.reactors(uuid), public.comments_for(uuid, uuid),
    public.comment_counts(uuid[], uuid[]), public.respond_rematch(uuid, boolean), public.my_rematches(),
    public.open_games(text), public.club_ranking(text), public.club_activity(text), public.head_to_head(uuid),
    public.delete_my_account(),
    public.home_feed(integer, timestamptz), public.profile_posts(uuid, integer, timestamptz)
    to authenticated;
