-- Player search and follow suggestions.

-- Search by name or username (prefix / contains, case-insensitive). Minimal data only.
create or replace function public.search_profiles(p_query text)
returns table (profile_id uuid, display_name text, username text, avatar_path text, home_club text, relation text)
language sql stable security definer set search_path = ''
as $$
    with q as (select lower(trim(both '@ ' from coalesce(p_query, ''))) as text)
    select p.id, p.display_name, p.username, p.avatar_path, p.home_club, public.follow_relation(p.id)
    from public.profiles p, q
    where auth.uid() is not null
      and length(q.text) >= 2
      and p.id <> auth.uid()
      and (p.username like q.text || '%' or lower(p.display_name) like '%' || q.text || '%')
    order by (p.username = q.text) desc, (p.username like q.text || '%') desc, p.display_name
    limit 30;
$$;

-- People to follow: co-players from my matches I do not follow yet, then players of my
-- home club, then the most active public players.
create or replace function public.suggested_profiles()
returns table (profile_id uuid, display_name text, username text, avatar_path text, home_club text, reason text)
language sql stable security definer set search_path = ''
as $$
    with me as (select home_club from public.profiles where id = auth.uid()),
    coplayers as (
        select distinct mp2.profile_id
        from public.match_players mp
        join public.match_players mp2 on mp2.match_id = mp.match_id
        where mp.profile_id = auth.uid() and mp2.profile_id is not null and mp2.profile_id <> auth.uid()
    ),
    candidates as (
        select c.profile_id, 'Hat mit dir gespielt' as reason, 0 as rank from coplayers c
        union all
        select p.id, 'Aus deiner Halle', 1
        from public.profiles p, me
        where me.home_club is not null and p.home_club = me.home_club and p.id <> auth.uid()
        union all
        select p.id, 'Aktiver Spieler', 2
        from public.profiles p
        where p.visibility = 'public' and p.rated_matches > 0 and p.id <> auth.uid()
    )
    select p.id, p.display_name, p.username, p.avatar_path, p.home_club, c.reason
    from (
        select profile_id, min(rank) as rank, min(reason) as reason from candidates group by profile_id
    ) c
    join public.profiles p on p.id = c.profile_id
    where auth.uid() is not null
      and not exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = p.id)
    order by c.rank, p.rated_matches desc, p.display_name
    limit 20;
$$;

revoke execute on function public.search_profiles(text), public.suggested_profiles() from public, anon;
grant execute on function public.search_profiles(text), public.suggested_profiles() to authenticated;
