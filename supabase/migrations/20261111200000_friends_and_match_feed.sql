-- Friends list with names (also for friends-only profiles) and a personal match feed
-- (every match I play in, from my side, with the other players' names).

-- ---------------------------------------------------------------------------
-- Friends
-- ---------------------------------------------------------------------------

-- My friends and open requests. Rating only for accepted friends.
create function public.my_friends()
returns table (
    profile_id uuid,
    display_name text,
    username text,
    rating double precision,
    rated_matches integer,
    status public.friendship_status,
    incoming boolean
)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.display_name, p.username,
           case when f.status = 'accepted' then p.rating end,
           case when f.status = 'accepted' then p.rated_matches end,
           f.status,
           f.addressee_id = auth.uid()
    from public.friendships f
    join public.profiles p
      on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    where auth.uid() in (f.requester_id, f.addressee_id)
    order by p.display_name;
$$;

-- Sends a request – or accepts directly if the other person already asked me.
create function public.request_friend(p_profile uuid)
returns public.friendship_status
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null or p_profile is null or p_profile = v_uid then
        raise exception 'invalid friend request';
    end if;
    if not exists (select 1 from public.profiles where id = p_profile) then
        raise exception 'unknown player';
    end if;

    update public.friendships set status = 'accepted'
    where requester_id = p_profile and addressee_id = v_uid and status = 'pending';
    if found then
        return 'accepted';
    end if;

    insert into public.friendships (requester_id, addressee_id)
    values (v_uid, p_profile)
    on conflict do nothing;

    return (select status from public.friendships
            where least(requester_id, addressee_id) = least(v_uid, p_profile)
              and greatest(requester_id, addressee_id) = greatest(v_uid, p_profile));
end;
$$;

create function public.accept_friend(p_profile uuid)
returns void
language sql security definer set search_path = ''
as $$
    update public.friendships set status = 'accepted'
    where requester_id = p_profile and addressee_id = auth.uid();
$$;

-- Declines a request, withdraws my own request, or ends a friendship.
create function public.remove_friend(p_profile uuid)
returns void
language sql security definer set search_path = ''
as $$
    delete from public.friendships
    where least(requester_id, addressee_id) = least(auth.uid(), p_profile)
      and greatest(requester_id, addressee_id) = greatest(auth.uid(), p_profile);
$$;

-- ---------------------------------------------------------------------------
-- Match feed
-- ---------------------------------------------------------------------------

-- Every match I take part in. Co-players' names are shown to participants even if
-- their profile is friends-only (they played together). Sets are stored from side A.
create function public.my_match_feed()
returns table (
    match_id uuid,
    started_at timestamptz,
    ended_at timestamptz,
    sets jsonb,
    winner_side public.match_side,
    status public.match_status,
    my_side public.match_side,
    created_by_me boolean,
    best_of integer,
    golden_point boolean,
    super_tiebreak boolean,
    partner_name text,
    opponent_names text
)
language sql stable security definer set search_path = ''
as $$
    select x.id, x.started_at, x.ended_at, x.sets, x.winner_side, x.status, me.side,
           x.created_by = auth.uid(), x.best_of, x.golden_point, x.super_tiebreak,
           (select coalesce(p.display_name, mp.guest_name)
              from public.match_players mp
              left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side = me.side and mp.slot <> me.slot
             order by mp.slot limit 1),
           (select string_agg(coalesce(p.display_name, mp.guest_name), ' & ' order by mp.slot)
              from public.match_players mp
              left join public.profiles p on p.id = mp.profile_id
             where mp.match_id = x.id and mp.side <> me.side)
    from public.matches x
    join public.match_players me on me.match_id = x.id and me.profile_id = auth.uid()
    order by x.started_at desc;
$$;

revoke execute on function public.my_friends(), public.request_friend(uuid), public.accept_friend(uuid),
    public.remove_friend(uuid), public.my_match_feed() from public, anon;
grant execute on function public.my_friends(), public.request_friend(uuid), public.accept_friend(uuid),
    public.remove_friend(uuid), public.my_match_feed() to authenticated;
