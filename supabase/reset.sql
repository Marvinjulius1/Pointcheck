-- ⚠️ Removes ALL Pointcheck tables, functions and types – including their data.
-- Use only to start over (e.g. after a half-finished first setup), then run the migration again.
-- Supabase's own tables (e.g. auth.users) are not touched.

drop trigger if exists on_auth_user_created on auth.users;

drop view if exists public.open_confirmations;
drop view if exists public.leaderboard;

drop table if exists public.rating_history cascade;
drop table if exists public.match_players cascade;
drop table if exists public.match_claims cascade;
drop table if exists public.matches cascade;
drop table if exists public.friendships cascade;
drop table if exists public.profiles cascade;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.handle_new_match() cascade;
drop function if exists public.apply_match_rating(uuid) cascade;
drop function if exists public.finalize_if_confirmed(uuid) cascade;
drop function if exists public.match_claim_token(uuid) cascade;
drop function if exists public.claim_and_confirm(uuid, text) cascade;
drop function if exists public.confirm_match(uuid) cascade;
drop function if exists public.dispute_match(uuid) cascade;
drop function if exists public.find_profile(text) cascade;
drop function if exists public.can_view_match(uuid) cascade;
drop function if exists public.is_match_player(uuid) cascade;
drop function if exists public.can_view_profile(uuid) cascade;
drop function if exists public.are_friends(uuid, uuid) cascade;

drop type if exists public.match_side cascade;
drop type if exists public.match_status cascade;
drop type if exists public.friendship_status cascade;
drop type if exists public.profile_visibility cascade;
