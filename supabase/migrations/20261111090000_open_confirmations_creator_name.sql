-- Open confirmations also show who entered the result, even if that profile is
-- friends-only: whoever links you in a match reveals their name to you.
--
-- The view now runs with its owner's rights (security_invoker = false) so it can read
-- the creator's name past RLS; the WHERE clause restricts it to the caller's own rows.

create or replace view public.open_confirmations
with (security_invoker = false)
as
select x.id as match_id, x.created_by, x.started_at, x.ended_at, x.sets, x.winner_side,
       x.best_of, x.golden_point, x.super_tiebreak,
       creator.display_name as creator_name
from public.matches x
join public.match_players mp on mp.match_id = x.id
join public.profiles creator on creator.id = x.created_by
where x.status = 'pending' and mp.side = 'b'
  and mp.profile_id = auth.uid() and mp.confirmed_at is null;

revoke all on public.open_confirmations from anon;
grant select on public.open_confirmations to authenticated;
