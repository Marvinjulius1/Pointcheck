-- Posts (text, optional image, optional match), the home feed and the profile page.

create table if not exists public.posts (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    text text not null default '' check (char_length(text) <= 1000),
    image_path text,
    match_id uuid references public.matches (id) on delete set null,
    created_at timestamptz not null default now(),
    check (char_length(text) > 0 or image_path is not null or match_id is not null)
);

create index if not exists posts_author_idx on public.posts (author_id, created_at desc);
create index if not exists posts_created_idx on public.posts (created_at desc);

alter table public.posts enable row level security;

-- Used inside the insert policy below (answers yes/no only).
grant execute on function public.is_match_player(uuid) to authenticated;

drop policy if exists "posts: visible authors" on public.posts;
create policy "posts: visible authors" on public.posts
    for select to authenticated using (public.can_view_profile(author_id));
drop policy if exists "posts: write own" on public.posts;
create policy "posts: write own" on public.posts
    for insert to authenticated with check (
        author_id = auth.uid()
        and (match_id is null or public.is_match_player(match_id))
    );
drop policy if exists "posts: edit own" on public.posts;
create policy "posts: edit own" on public.posts
    for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
drop policy if exists "posts: delete own" on public.posts;
create policy "posts: delete own" on public.posts
    for delete to authenticated using (author_id = auth.uid());

revoke all on public.posts from anon, authenticated;
grant select, delete on public.posts to authenticated;
grant insert (id, text, image_path, match_id) on public.posts to authenticated;
grant update (text) on public.posts to authenticated;

-- One feed item: a post or a confirmed match of someone I follow (or myself).
-- Match fields are from the author's perspective; `author_side` tells the app which.
create or replace function public.home_feed(p_limit integer default 20, p_before timestamptz default null)
returns table (
    kind text,                    -- 'post' | 'match'
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
    opponent_names text
)
language sql stable security definer set search_path = ''
as $$
    with people as (
        select following_id as id from public.follows where follower_id = auth.uid() and status = 'accepted'
        union select auth.uid()
    ),
    items as (
        select 'post' as kind, po.id, po.created_at, po.author_id, po.text, po.image_path, po.match_id,
               null::uuid as mp_match
        from public.posts po
        where po.author_id in (select id from people)
        union all
        select 'match', x.id, coalesce(x.rated_at, x.created_at), x.created_by, null, null, x.id, x.id
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
             where mp.match_id = x.id and mp.side <> me.side)
    from items i
    join public.profiles a on a.id = i.author_id
    -- Match details only if the reader may see that match; a post stays visible without them.
    left join public.matches x on x.id = i.match_id and public.can_view_match(x.id)
    left join public.match_players me on me.match_id = x.id and me.profile_id = i.author_id
    where auth.uid() is not null
      and (p_before is null or i.created_at < p_before)
      and (i.kind = 'post' or x.id is not null)
    order by i.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

-- Posts of one profile (the "Beiträge" tab).
create or replace function public.profile_posts(p_profile uuid, p_limit integer default 30, p_before timestamptz default null)
returns table (
    id uuid, created_at timestamptz, text text, image_path text, match_id uuid,
    started_at timestamptz, sets jsonb, winner_side public.match_side, author_side public.match_side,
    partner_name text, opponent_names text
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
             where mp.match_id = x.id and mp.side <> me.side)
    from public.posts po
    left join public.matches x on x.id = po.match_id
    left join public.match_players me on me.match_id = x.id and me.profile_id = po.author_id
    where po.author_id = p_profile
      and public.can_view_profile(p_profile)
      and (p_before is null or po.created_at < p_before)
    order by po.created_at desc
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;

-- Confirmed results of one profile (the "Ergebnisse" tab), from that player's side.
create or replace function public.profile_results(p_profile uuid, p_limit integer default 30, p_before timestamptz default null)
returns table (
    match_id uuid, started_at timestamptz, ended_at timestamptz, sets jsonb,
    winner_side public.match_side, player_side public.match_side,
    partner_name text, opponent_names text
)
language sql stable security definer set search_path = ''
as $$
    select x.id, x.started_at, x.ended_at, x.sets, x.winner_side, me.side,
           (select coalesce(p.display_name, mp.guest_name)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side = me.side and mp.slot <> me.slot
             order by mp.slot limit 1),
           (select string_agg(coalesce(p.display_name, mp.guest_name), ' & ' order by mp.slot)
              from public.match_players mp left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side <> me.side)
    from public.matches x
    join public.match_players me on me.match_id = x.id and me.profile_id = p_profile
    where x.status = 'confirmed'
      and public.can_view_profile(p_profile)
      and public.can_view_match(x.id)
      and (p_before is null or x.started_at < p_before)
    order by x.started_at desc
    limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;

-- Activity: new followers (last 30 days) and follow requests, for the Aktivität tab.
create or replace function public.recent_followers()
returns table (profile_id uuid, display_name text, username text, avatar_path text, followed_at timestamptz, relation text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path, f.created_at, public.follow_relation(p.id)
    from public.follows f
    join public.profiles p on p.id = f.follower_id
    where f.following_id = auth.uid() and f.status = 'accepted'
      and f.created_at > now() - interval '30 days'
    order by f.created_at desc
    limit 50;
$$;

-- Everything the profile screen needs in one call. Private details (rating, stats, bio)
-- only when the viewer may see the profile; name, photo and counters always, so a
-- followers-only profile still shows a header with a "Folgen" button.
create or replace function public.profile_page(p_profile uuid)
returns table (
    id uuid,
    display_name text,
    username text,
    avatar_path text,
    bio text,
    home_club text,
    visibility public.profile_visibility,
    is_visible boolean,
    relation text,
    follows_me boolean,
    followers integer,
    following integer,
    posts integer,
    rating double precision,
    rated_matches integer,
    rated_wins integer,
    current_streak integer
)
language sql stable security definer set search_path = ''
as $$
    with visible as (select public.can_view_profile(p_profile) as ok),
    results as (
        select (x.winner_side = mp.side) as won,
               row_number() over (order by x.started_at desc) as rn
        from public.matches x
        join public.match_players mp on mp.match_id = x.id and mp.profile_id = p_profile
        where x.status = 'confirmed'
    ),
    latest as (select won from results where rn = 1),
    streak as (
        -- Number of newest results equal to the latest one; negative for losses.
        select case
            when not exists (select 1 from latest) then 0
            else (select count(*) from results r
                  where r.rn < coalesce((select min(rn) from results where won <> (select won from latest)), 2147483647))
                 * (case when (select won from latest) then 1 else -1 end)
        end as value
    )
    select p.id, p.display_name, p.username, p.avatar_path,
           case when v.ok then p.bio end,
           p.home_club,
           p.visibility,
           v.ok,
           public.follow_relation(p.id),
           public.is_following(p.id, auth.uid()),
           (select count(*)::int from public.follows f where f.following_id = p.id and f.status = 'accepted'),
           (select count(*)::int from public.follows f where f.follower_id = p.id and f.status = 'accepted'),
           case when v.ok then (select count(*)::int from public.posts po where po.author_id = p.id) else 0 end,
           case when v.ok then p.rating end,
           case when v.ok then p.rated_matches end,
           case when v.ok then p.rated_wins end,
           case when v.ok then (select value::int from streak) end
    from public.profiles p, visible v
    where p.id = p_profile;
$$;

revoke execute on function public.home_feed(integer, timestamptz), public.profile_posts(uuid, integer, timestamptz),
    public.profile_results(uuid, integer, timestamptz), public.recent_followers(), public.profile_page(uuid)
    from public, anon;
grant execute on function public.home_feed(integer, timestamptz), public.profile_posts(uuid, integer, timestamptz),
    public.profile_results(uuid, integer, timestamptz), public.recent_followers(), public.profile_page(uuid)
    to authenticated;
