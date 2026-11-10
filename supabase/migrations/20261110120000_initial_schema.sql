-- Pointcheck – initial schema
--
-- Profiles (public or friends-only), friendships, matches with opponent confirmation
-- (QR code claim), and a doubles Elo rating computed on the server.
--
-- Security model: every table has row level security. Ratings and confirmations can
-- only change through the SECURITY DEFINER functions below, never directly.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.profile_visibility as enum ('public', 'friends');
create type public.friendship_status as enum ('pending', 'accepted');
create type public.match_status as enum ('pending', 'confirmed', 'disputed');
create type public.match_side as enum ('a', 'b');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null check (char_length(display_name) between 1 and 40),
    username text unique check (username ~ '^[a-z0-9_.]{3,20}$'),
    -- Each user chooses: visible to everyone, or to friends only (default, privacy first).
    visibility public.profile_visibility not null default 'friends',
    rating double precision not null default 1500,
    rated_matches integer not null default 0,
    rated_wins integer not null default 0,
    created_at timestamptz not null default now()
);

create table public.friendships (
    requester_id uuid not null references public.profiles (id) on delete cascade,
    addressee_id uuid not null references public.profiles (id) on delete cascade,
    status public.friendship_status not null default 'pending',
    created_at timestamptz not null default now(),
    primary key (requester_id, addressee_id),
    check (requester_id <> addressee_id)
);

-- Only one friendship per pair, regardless of who asked.
create unique index friendships_pair_idx
    on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table public.matches (
    -- Same id as on the watch, so uploads are idempotent.
    id uuid primary key,
    created_by uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    started_at timestamptz not null,
    ended_at timestamptz,
    -- [SetScore] JSON as produced by the app, from side A's perspective ("me" = side A).
    sets jsonb not null default '[]'::jsonb check (jsonb_typeof(sets) = 'array'),
    winner_side public.match_side not null,
    best_of integer not null default 3 check (best_of between 1 and 5),
    golden_point boolean not null default false,
    super_tiebreak boolean not null default false,
    status public.match_status not null default 'pending',
    rated_at timestamptz,
    created_at timestamptz not null default now()
);

create index matches_created_by_idx on public.matches (created_by);

-- Secret token shown as QR code on the creator's device. No policies: only functions read it.
create table public.match_claims (
    match_id uuid primary key references public.matches (id) on delete cascade,
    token text not null default replace(gen_random_uuid()::text, '-', '')
);

-- Slots 1–2: side A (creator's team), slots 3–4: side B (opponents).
create table public.match_players (
    match_id uuid not null references public.matches (id) on delete cascade,
    slot smallint not null check (slot between 1 and 4),
    side public.match_side generated always as (
        case when slot <= 2 then 'a'::public.match_side else 'b'::public.match_side end
    ) stored,
    profile_id uuid references public.profiles (id) on delete set null,
    guest_name text check (char_length(guest_name) <= 40),
    confirmed_at timestamptz,
    primary key (match_id, slot),
    unique (match_id, profile_id)
);

create index match_players_profile_idx on public.match_players (profile_id);

create table public.rating_history (
    id bigint generated always as identity primary key,
    profile_id uuid not null references public.profiles (id) on delete cascade,
    match_id uuid not null references public.matches (id) on delete cascade,
    rating_before double precision not null,
    rating_after double precision not null,
    created_at timestamptz not null default now(),
    unique (profile_id, match_id)
);

-- ---------------------------------------------------------------------------
-- Visibility helpers (SECURITY DEFINER so they can look past RLS, but only answer yes/no)
-- ---------------------------------------------------------------------------

create function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.friendships f
        where f.status = 'accepted'
          and least(f.requester_id, f.addressee_id) = least(a, b)
          and greatest(f.requester_id, f.addressee_id) = greatest(a, b)
    );
$$;

create function public.can_view_profile(target uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select target = auth.uid()
        or exists (select 1 from public.profiles p where p.id = target and p.visibility = 'public')
        or public.are_friends(auth.uid(), target);
$$;

create function public.is_match_player(m uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.match_players mp where mp.match_id = m and mp.profile_id = auth.uid()
    ) or exists (
        select 1 from public.matches x where x.id = m and x.created_by = auth.uid()
    );
$$;

-- Participants always see their matches. Others see a confirmed match only if they may
-- see every registered player in it (so a private player never shows up in public).
create function public.can_view_match(m uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select public.is_match_player(m)
        or (
            exists (select 1 from public.matches x where x.id = m and x.status = 'confirmed')
            and not exists (
                select 1 from public.match_players mp
                where mp.match_id = m
                  and mp.profile_id is not null
                  and not public.can_view_profile(mp.profile_id)
            )
        );
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- New sign-up → profile (name from sign-up metadata or the e-mail address).
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1), 'Spieler'), 40)
    );
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- New match → creator takes slot 1 (already confirmed) and a claim token is generated.
create function public.handle_new_match()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.match_players (match_id, slot, profile_id, confirmed_at)
    values (new.id, 1, new.created_by, now());
    insert into public.match_claims (match_id) values (new.id);
    return new;
end;
$$;

create trigger on_match_created
    after insert on public.matches
    for each row execute function public.handle_new_match();

-- ---------------------------------------------------------------------------
-- Rating (doubles Elo – mirrors RatingEngine in the app)
-- ---------------------------------------------------------------------------

create function public.apply_match_rating(m uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_match public.matches;
    v_rating_a double precision;
    v_rating_b double precision;
    v_expected_a double precision;
    v_score_a double precision;
    v_game_diff integer;
    v_multiplier double precision;
begin
    select * into v_match from public.matches where id = m for update;
    if v_match.id is null or v_match.rated_at is not null then
        return;
    end if;

    -- Team strength = average of its players; guests count with 1500.
    select coalesce(avg(coalesce(p.rating, 1500)), 1500) into v_rating_a
    from public.match_players mp left join public.profiles p on p.id = mp.profile_id
    where mp.match_id = m and mp.side = 'a';

    select coalesce(avg(coalesce(p.rating, 1500)), 1500) into v_rating_b
    from public.match_players mp left join public.profiles p on p.id = mp.profile_id
    where mp.match_id = m and mp.side = 'b';

    v_expected_a := 1 / (1 + power(10, (v_rating_b - v_rating_a) / 400));
    v_score_a := case when v_match.winner_side = 'a' then 1 else 0 end;

    select coalesce(sum((s -> 'games' ->> 'me')::int - (s -> 'games' ->> 'opponent')::int), 0)
    into v_game_diff
    from jsonb_array_elements(v_match.sets) s;

    v_multiplier := least(1 + 0.05 * abs(v_game_diff), 1.5);

    with deltas as (
        select
            p.id as profile_id,
            p.rating as rating_before,
            (case when p.rated_matches < 10 then 48 else 32 end) * v_multiplier
                * (case when mp.side = 'a' then v_score_a - v_expected_a
                        else (1 - v_score_a) - (1 - v_expected_a) end) as delta,
            (mp.side = 'a') = (v_match.winner_side = 'a') as won
        from public.match_players mp
        join public.profiles p on p.id = mp.profile_id
        where mp.match_id = m
    ),
    updated as (
        update public.profiles p
        set rating = d.rating_before + d.delta,
            rated_matches = p.rated_matches + 1,
            rated_wins = p.rated_wins + case when d.won then 1 else 0 end
        from deltas d
        where p.id = d.profile_id
        returning p.id, d.rating_before, p.rating
    )
    insert into public.rating_history (profile_id, match_id, rating_before, rating_after)
    select u.id, m, u.rating_before, u.rating from updated u;

    update public.matches set rated_at = now() where id = m;
end;
$$;

-- Confirmed as soon as one registered opponent confirmed; then the rating is applied once.
create function public.finalize_if_confirmed(m uuid)
returns public.match_status
language plpgsql security definer set search_path = ''
as $$
declare
    v_status public.match_status;
begin
    select status into v_status from public.matches where id = m;
    if v_status = 'pending' and exists (
        select 1 from public.match_players
        where match_id = m and side = 'b' and profile_id is not null and confirmed_at is not null
    ) then
        update public.matches set status = 'confirmed' where id = m;
        perform public.apply_match_rating(m);
        v_status := 'confirmed';
    end if;
    return v_status;
end;
$$;

-- ---------------------------------------------------------------------------
-- Client API
-- ---------------------------------------------------------------------------

-- Creator only: token for the QR code.
create function public.match_claim_token(m uuid)
returns text
language sql stable security definer set search_path = ''
as $$
    select c.token
    from public.match_claims c
    join public.matches x on x.id = c.match_id
    where c.match_id = m and x.created_by = auth.uid();
$$;

-- Opponent scans the QR code: takes a free slot on side B (or keeps theirs) and confirms.
create function public.claim_and_confirm(m uuid, claim_token text)
returns public.match_status
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_slot smallint;
begin
    if v_uid is null then
        raise exception 'not signed in';
    end if;
    if not exists (select 1 from public.match_claims where match_id = m and token = claim_token) then
        raise exception 'invalid code';
    end if;
    if not exists (select 1 from public.matches where id = m and status = 'pending') then
        raise exception 'match is not open for confirmation';
    end if;
    if exists (select 1 from public.match_players where match_id = m and side = 'a' and profile_id = v_uid) then
        raise exception 'you played on the other side';
    end if;

    select slot into v_slot from public.match_players
    where match_id = m and side = 'b' and profile_id = v_uid;

    if v_slot is null then
        -- First free side-B slot (an empty or guest-only row, or a missing one).
        select s into v_slot
        from generate_series(3, 4) s
        where not exists (
            select 1 from public.match_players
            where match_id = m and slot = s and profile_id is not null
        )
        order by s
        limit 1;
        if v_slot is null then
            raise exception 'both opponent places are taken';
        end if;
        insert into public.match_players (match_id, slot, profile_id)
        values (m, v_slot, v_uid)
        on conflict (match_id, slot) do update set profile_id = excluded.profile_id;
    end if;

    update public.match_players set confirmed_at = now()
    where match_id = m and slot = v_slot;

    return public.finalize_if_confirmed(m);
end;
$$;

-- Opponent who was added by name (friend) confirms without a QR code.
create function public.confirm_match(m uuid)
returns public.match_status
language plpgsql security definer set search_path = ''
as $$
begin
    update public.match_players set confirmed_at = now()
    where match_id = m and side = 'b' and profile_id = auth.uid()
      and exists (select 1 from public.matches where id = m and status = 'pending');
    if not found then
        raise exception 'nothing to confirm';
    end if;
    return public.finalize_if_confirmed(m);
end;
$$;

-- Opponent rejects the result. A disputed match is never rated.
create function public.dispute_match(m uuid)
returns public.match_status
language plpgsql security definer set search_path = ''
as $$
begin
    update public.matches set status = 'disputed'
    where id = m and status = 'pending'
      and exists (
          select 1 from public.match_players
          where match_id = m and side = 'b' and profile_id = auth.uid()
      );
    if not found then
        raise exception 'nothing to dispute';
    end if;
    return 'disputed';
end;
$$;

-- Find someone to add as a friend, even if their profile is friends-only (minimal data).
create function public.find_profile(p_username text)
returns table (id uuid, display_name text, username text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username
    from public.profiles p
    where p.username = lower(trim(p_username)) and auth.uid() is not null;
$$;

-- ---------------------------------------------------------------------------
-- Public leaderboard (only public profiles with at least one rated match)
-- ---------------------------------------------------------------------------

create view public.leaderboard
with (security_invoker = true)
as
select p.id, p.display_name, p.username, p.rating, p.rated_matches, p.rated_wins
from public.profiles p
where p.visibility = 'public' and p.rated_matches > 0
order by p.rating desc;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.matches enable row level security;
alter table public.match_claims enable row level security;
alter table public.match_players enable row level security;
alter table public.rating_history enable row level security;

-- profiles
create policy "profiles: visible ones" on public.profiles
    for select to authenticated using (public.can_view_profile(id));
create policy "profiles: edit own" on public.profiles
    for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- friendships
create policy "friendships: own" on public.friendships
    for select to authenticated using (auth.uid() in (requester_id, addressee_id));
create policy "friendships: request" on public.friendships
    for insert to authenticated with check (requester_id = auth.uid() and status = 'pending');
create policy "friendships: accept" on public.friendships
    for update to authenticated using (addressee_id = auth.uid()) with check (addressee_id = auth.uid());
create policy "friendships: remove" on public.friendships
    for delete to authenticated using (auth.uid() in (requester_id, addressee_id));

-- matches
create policy "matches: visible ones" on public.matches
    for select to authenticated using (public.can_view_match(id));
create policy "matches: upload own" on public.matches
    for insert to authenticated with check (created_by = auth.uid() and status = 'pending');
create policy "matches: edit own while pending" on public.matches
    for update to authenticated using (created_by = auth.uid() and status = 'pending')
    with check (created_by = auth.uid() and status = 'pending');
create policy "matches: delete own while pending" on public.matches
    for delete to authenticated using (created_by = auth.uid() and status = 'pending');

-- match_players (the creator fills in partner/opponents while the match is pending)
create policy "match_players: visible matches" on public.match_players
    for select to authenticated using (public.can_view_match(match_id));
create policy "match_players: creator adds" on public.match_players
    for insert to authenticated with check (
        slot > 1 and confirmed_at is null
        -- Only friends can be added by name; everyone else joins via the QR code.
        and (profile_id is null or public.are_friends(auth.uid(), profile_id))
        and exists (select 1 from public.matches x
                    where x.id = match_id and x.created_by = auth.uid() and x.status = 'pending')
    );
create policy "match_players: creator edits" on public.match_players
    for update to authenticated using (
        slot > 1 and exists (select 1 from public.matches x
                             where x.id = match_id and x.created_by = auth.uid() and x.status = 'pending')
    ) with check (
        slot > 1 and confirmed_at is null
        and (profile_id is null or public.are_friends(auth.uid(), profile_id))
    );
create policy "match_players: creator removes" on public.match_players
    for delete to authenticated using (
        slot > 1 and exists (select 1 from public.matches x
                             where x.id = match_id and x.created_by = auth.uid() and x.status = 'pending')
    );

-- rating_history
create policy "rating_history: visible profiles" on public.rating_history
    for select to authenticated using (public.can_view_profile(profile_id));

-- ---------------------------------------------------------------------------
-- Privileges: columns that must only change through the functions above
-- ---------------------------------------------------------------------------

revoke all on public.profiles, public.friendships, public.matches, public.match_claims,
    public.match_players, public.rating_history, public.leaderboard from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, username, visibility) on public.profiles to authenticated;

grant select, delete on public.friendships to authenticated;
grant insert (requester_id, addressee_id) on public.friendships to authenticated;
grant update (status) on public.friendships to authenticated;

grant select, delete on public.matches to authenticated;
grant insert (id, started_at, ended_at, sets, winner_side, best_of, golden_point, super_tiebreak)
    on public.matches to authenticated;
grant update (started_at, ended_at, sets, winner_side, best_of, golden_point, super_tiebreak)
    on public.matches to authenticated;

grant select, delete on public.match_players to authenticated;
grant insert (match_id, slot, profile_id, guest_name) on public.match_players to authenticated;
grant update (profile_id, guest_name) on public.match_players to authenticated;

grant select on public.rating_history to authenticated;
grant select on public.leaderboard to authenticated;

-- Internal functions are not callable by clients.
revoke execute on function public.apply_match_rating(uuid), public.finalize_if_confirmed(uuid),
    public.handle_new_user(), public.handle_new_match() from public, anon, authenticated;
revoke execute on function public.match_claim_token(uuid), public.claim_and_confirm(uuid, text),
    public.confirm_match(uuid), public.dispute_match(uuid), public.find_profile(text),
    public.are_friends(uuid, uuid), public.can_view_profile(uuid), public.is_match_player(uuid),
    public.can_view_match(uuid) from public, anon, authenticated;
-- Client API.
grant execute on function public.match_claim_token(uuid), public.claim_and_confirm(uuid, text),
    public.confirm_match(uuid), public.dispute_match(uuid), public.find_profile(text)
    to authenticated;
-- Used directly inside policies, so the caller needs EXECUTE (they only answer yes/no).
grant execute on function public.can_view_profile(uuid), public.can_view_match(uuid),
    public.are_friends(uuid, uuid) to authenticated;
