-- Instagram-style following replaces mutual friendships.
--
-- * follows(follower_id, following_id, status): following a public profile is accepted at
--   once; a profile set to "followers" (formerly "friends") must accept the request.
-- * Visibility: a followers-only profile is visible to its accepted followers.
-- * Existing accepted friendships become mutual follows; pending requests become
--   pending follow requests.

-- ---------------------------------------------------------------------------
-- Profile columns used by the lists below (photo, bio, home club)
-- ---------------------------------------------------------------------------

alter table public.profiles
    add column if not exists avatar_path text,
    add column if not exists bio text check (char_length(bio) <= 160),
    add column if not exists home_club text check (char_length(home_club) <= 60);

grant update (display_name, username, visibility, avatar_path, bio, home_club) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Visibility enum: friends → followers
-- ---------------------------------------------------------------------------

do $$ begin
    if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
               where t.typname = 'profile_visibility' and e.enumlabel = 'friends') then
        alter type public.profile_visibility rename value 'friends' to 'followers';
    end if;
end $$;

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists public.follows (
    follower_id uuid not null references public.profiles (id) on delete cascade,
    following_id uuid not null references public.profiles (id) on delete cascade,
    status public.friendship_status not null default 'accepted',
    created_at timestamptz not null default now(),
    primary key (follower_id, following_id),
    check (follower_id <> following_id)
);

create index if not exists follows_following_idx on public.follows (following_id, status);

do $$ begin
    if to_regclass('public.friendships') is not null then
        insert into public.follows (follower_id, following_id, status, created_at)
        select requester_id, addressee_id, status, created_at from public.friendships
        union all
        select addressee_id, requester_id, 'accepted', created_at from public.friendships where status = 'accepted'
        on conflict do nothing;
    end if;
end $$;

alter table public.follows enable row level security;

-- Everyone signed in may see who follows whom (counts and lists on profiles); pending
-- requests only concern the two people involved.
drop policy if exists "follows: accepted are public" on public.follows;
create policy "follows: accepted are public" on public.follows
    for select to authenticated
    using (status = 'accepted' or auth.uid() in (follower_id, following_id));

revoke all on public.follows from anon, authenticated;
grant select on public.follows to authenticated;

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_following(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.follows f
        where f.follower_id = a and f.following_id = b and f.status = 'accepted'
    );
$$;

create or replace function public.can_view_profile(target uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select target = auth.uid()
        or exists (select 1 from public.profiles p where p.id = target and p.visibility = 'public')
        or public.is_following(auth.uid(), target);
$$;

-- Old helper kept for compatibility: "friends" now means mutual follows.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select public.is_following(a, b) and public.is_following(b, a);
$$;

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

-- Follow a profile. Returns the resulting status ('accepted' or 'pending').
create or replace function public.follow(p_profile uuid)
returns public.friendship_status
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_visibility public.profile_visibility;
    v_status public.friendship_status;
begin
    if v_uid is null or p_profile is null or p_profile = v_uid then
        raise exception 'invalid follow';
    end if;
    select visibility into v_visibility from public.profiles where id = p_profile;
    if v_visibility is null then
        raise exception 'unknown player';
    end if;
    v_status := case when v_visibility = 'public' then 'accepted' else 'pending' end;

    insert into public.follows (follower_id, following_id, status)
    values (v_uid, p_profile, v_status)
    on conflict (follower_id, following_id) do nothing;

    return (select status from public.follows where follower_id = v_uid and following_id = p_profile);
end;
$$;

-- Unfollow, or withdraw a pending request.
create or replace function public.unfollow(p_profile uuid)
returns void
language sql security definer set search_path = ''
as $$
    delete from public.follows where follower_id = auth.uid() and following_id = p_profile;
$$;

create or replace function public.accept_follow(p_follower uuid)
returns void
language sql security definer set search_path = ''
as $$
    update public.follows set status = 'accepted'
    where follower_id = p_follower and following_id = auth.uid() and status = 'pending';
$$;

-- Decline a request, or remove an existing follower.
create or replace function public.remove_follower(p_follower uuid)
returns void
language sql security definer set search_path = ''
as $$
    delete from public.follows where follower_id = p_follower and following_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Lists
-- ---------------------------------------------------------------------------

-- Compact profile rows for lists (followers, following, requests, search).
-- `relation` is how *I* relate to that person: 'none', 'pending', 'following', 'self'.
create or replace function public.follow_relation(p_profile uuid)
returns text
language sql stable security definer set search_path = ''
as $$
    select case
        when p_profile = auth.uid() then 'self'
        else coalesce((select case status when 'accepted' then 'following' else 'pending' end
                       from public.follows where follower_id = auth.uid() and following_id = p_profile), 'none')
    end;
$$;

create or replace function public.followers_of(p_profile uuid)
returns table (profile_id uuid, display_name text, username text, avatar_path text, rating double precision, relation text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path,
           case when public.can_view_profile(p.id) then p.rating end,
           public.follow_relation(p.id)
    from public.follows f
    join public.profiles p on p.id = f.follower_id
    where f.following_id = p_profile and f.status = 'accepted'
      and public.can_view_profile(p_profile)
    order by f.created_at desc;
$$;

create or replace function public.following_of(p_profile uuid)
returns table (profile_id uuid, display_name text, username text, avatar_path text, rating double precision, relation text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path,
           case when public.can_view_profile(p.id) then p.rating end,
           public.follow_relation(p.id)
    from public.follows f
    join public.profiles p on p.id = f.following_id
    where f.follower_id = p_profile and f.status = 'accepted'
      and public.can_view_profile(p_profile)
    order by f.created_at desc;
$$;

-- People who asked to follow me.
create or replace function public.follow_requests()
returns table (profile_id uuid, display_name text, username text, avatar_path text, requested_at timestamptz)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username, p.avatar_path, f.created_at
    from public.follows f
    join public.profiles p on p.id = f.follower_id
    where f.following_id = auth.uid() and f.status = 'pending'
    order by f.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Retire friendships
-- ---------------------------------------------------------------------------

drop function if exists public.my_friends();
drop function if exists public.request_friend(uuid);
drop function if exists public.accept_friend(uuid);
drop function if exists public.remove_friend(uuid);
drop table if exists public.friendships;

revoke execute on function public.is_following(uuid, uuid), public.follow(uuid), public.unfollow(uuid),
    public.accept_follow(uuid), public.remove_follower(uuid), public.follow_relation(uuid),
    public.followers_of(uuid), public.following_of(uuid), public.follow_requests()
    from public, anon;
grant execute on function public.follow(uuid), public.unfollow(uuid), public.accept_follow(uuid),
    public.remove_follower(uuid), public.follow_relation(uuid), public.followers_of(uuid),
    public.following_of(uuid), public.follow_requests(), public.is_following(uuid, uuid)
    to authenticated;
