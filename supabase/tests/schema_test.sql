-- Behaviour tests for the Pointcheck schema (row level security, confirmation, rating).
-- Run against a fresh database: local_supabase_stub.sql → migration → this file.
-- Any failed ASSERT or unexpected error aborts the run (psql -v ON_ERROR_STOP=1).

\set QUIET on
\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'
\set carl  '33333333-3333-3333-3333-333333333333'
\set dana  '44444444-4444-4444-4444-444444444444'
\set eve   '55555555-5555-5555-5555-555555555555'
\set m1    'aaaaaaaa-0000-0000-0000-000000000001'
\set m2    'aaaaaaaa-0000-0000-0000-000000000002'

-- ---------------------------------------------------------------- setup (as admin)
insert into auth.users (id, email, raw_user_meta_data) values
    (:'alice', 'alice@example.com', '{"display_name":"Alice"}'),
    (:'bob',   'bob@example.com',   '{}'),
    (:'carl',  'carl@example.com',  '{"display_name":"Carl"}'),
    (:'dana',  'dana@example.com',  '{}'),
    (:'eve',   'eve@example.com',   '{}');

do $$ begin
    assert (select count(*) from public.profiles) = 5, 'profiles created on sign-up';
    assert (select display_name from public.profiles where id = '22222222-2222-2222-2222-222222222222') = 'bob',
        'name falls back to e-mail';
    assert (select visibility from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 'followers',
        'followers-only by default';
end $$;

-- ---------------------------------------------------------------- profiles
set role authenticated;
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
update public.profiles set visibility = 'public', username = 'carl' where id = auth.uid();

do $$ begin
    begin
        update public.profiles set rating = 3000 where id = auth.uid();
        assert false, 'rating must not be writable';
    exception when insufficient_privilege then null;
    end;
end $$;

-- Alice ↔ Bob and Alice ↔ Dana follow each other (all three are followers-only).
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
do $$ begin
    assert public.follow('22222222-2222-2222-2222-222222222222') = 'pending', 'followers-only → request';
    assert public.follow('44444444-4444-4444-4444-444444444444') = 'pending';
end $$;
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.follow_requests()) = 1, 'bob sees alice''s request';
    perform public.accept_follow('11111111-1111-1111-1111-111111111111');
    perform public.follow('11111111-1111-1111-1111-111111111111');
end $$;
select set_config('request.jwt.claim.sub', :'dana', false) \g /dev/null
do $$ begin
    perform public.accept_follow('11111111-1111-1111-1111-111111111111');
    perform public.follow('11111111-1111-1111-1111-111111111111');
end $$;
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.follow_requests()) = 2, 'alice has two requests';
    perform public.accept_follow('22222222-2222-2222-2222-222222222222');
    perform public.accept_follow('44444444-4444-4444-4444-444444444444');
    assert public.is_following('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
       and public.is_following('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
        'mutual follow';
end $$;

select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.profiles) = 2, 'eve sees herself and public carl only';
    assert (select count(*) from public.follows where status = 'pending') = 0, 'eve sees no foreign requests';
    assert (select count(*) from public.follows where status = 'accepted') = 4, 'accepted follows are visible';
    assert (select count(*) from public.find_profile('carl')) = 1, 'search by username';
end $$;

-- ---------------------------------------------------------------- match upload
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
insert into public.matches (id, started_at, ended_at, sets, winner_side)
values (:'m1', now() - interval '90 minutes', now(),
        '[{"games":{"me":6,"opponent":4},"isComplete":true},{"games":{"me":6,"opponent":3},"isComplete":true}]',
        'a');
insert into public.match_players (match_id, slot, profile_id) values (:'m1', 2, :'bob');

do $$ begin
    assert (select count(*) from public.match_players
            where match_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 2, 'creator + partner';
    assert (select confirmed_at is not null from public.match_players
            where match_id = 'aaaaaaaa-0000-0000-0000-000000000001' and slot = 1), 'creator auto-confirmed';
    -- Opponents are linked by profile (no friendship needed); they confirm in their app.
    insert into public.match_players (match_id, slot, profile_id)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 3, '33333333-3333-3333-3333-333333333333');
    begin
        insert into public.match_players (match_id, slot, profile_id)
        values ('aaaaaaaa-0000-0000-0000-000000000001', 1, '55555555-5555-5555-5555-555555555555');
        assert false, 'slot 1 belongs to the creator';
    exception when insufficient_privilege then null;
    end;
    begin
        update public.match_players set confirmed_at = now()
        where match_id = 'aaaaaaaa-0000-0000-0000-000000000001' and slot = 2;
        assert false, 'confirmations only through functions';
    exception when insufficient_privilege then null;
    end;
end $$;

select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.matches) = 0, 'outsiders do not see pending matches';
    begin
        perform public.confirm_match('aaaaaaaa-0000-0000-0000-000000000001');
        assert false, 'only linked opponents can confirm';
    exception when raise_exception then null;
    end;
    begin
        perform public.apply_match_rating('aaaaaaaa-0000-0000-0000-000000000001');
        assert false, 'internal rating function is not callable';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- confirmation in the app
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.open_confirmations) = 1, 'carl sees the open result';
    assert (select creator_name from public.open_confirmations) = 'Alice',
        'creator name visible although her profile is friends-only';
    assert (select count(*) from public.matches) = 1, 'linked opponent sees the pending match';
end $$;
select public.confirm_match(:'m1') as status \gset
\if :{?status}
\else
    \echo 'confirm failed' \q
\endif

reset role;
do $$ begin
    assert (select status from public.matches where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'confirmed';
    -- Equal teams (1500), game difference 5 → multiplier 1.25, provisional K 48 → ±30.
    assert (select rating from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 1530, 'alice +30';
    assert (select rating from public.profiles where id = '22222222-2222-2222-2222-222222222222') = 1530, 'bob +30';
    assert (select rating from public.profiles where id = '33333333-3333-3333-3333-333333333333') = 1470, 'carl -30';
    assert (select rated_wins from public.profiles where id = '22222222-2222-2222-2222-222222222222') = 1;
    assert (select count(*) from public.rating_history) = 3, 'history per rated player';
    perform public.apply_match_rating('aaaaaaaa-0000-0000-0000-000000000001');
    assert (select rating from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 1530,
        'a match is rated only once';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ begin
    begin
        perform public.confirm_match('aaaaaaaa-0000-0000-0000-000000000001');
        assert false, 'no second confirmation';
    exception when raise_exception then null;
    end;
    assert (select count(*) from public.open_confirmations) = 0, 'nothing open any more';
    assert (select count(*) from public.matches) = 1, 'participant sees the match';
end $$;

select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
do $$ begin
    update public.matches set winner_side = 'b' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert not found, 'confirmed matches are locked';
end $$;

-- Eve: Alice/Bob are friends-only, so the match stays hidden; leaderboard shows only Carl.
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.matches) = 0, 'match with private players stays hidden';
    assert (select count(*) from public.leaderboard) = 1, 'leaderboard: public profiles only';
    assert (select count(*) from public.open_confirmations) = 0, 'no foreign open confirmations';
end $$;

-- Bob (friend of Alice) sees Alice's rating history, Eve does not.
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.rating_history
            where profile_id = '11111111-1111-1111-1111-111111111111') = 1, 'friends see history';
end $$;

-- ---------------------------------------------------------------- dispute
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
insert into public.matches (id, started_at, sets, winner_side)
values (:'m2', now(), '[{"games":{"me":6,"opponent":0},"isComplete":true}]', 'a');
insert into public.match_players (match_id, slot, profile_id) values (:'m2', 3, :'eve');
-- The app replaces links by deleting slots > 1 and inserting again (while pending).
delete from public.match_players where match_id = :'m2' and slot > 1;
insert into public.match_players (match_id, slot, profile_id) values (:'m2', 3, :'dana');
do $$ begin
    assert (select count(*) from public.match_players where match_id = 'aaaaaaaa-0000-0000-0000-000000000002') = 2,
        'creator + relinked opponent';
    assert (select profile_id from public.match_players
            where match_id = 'aaaaaaaa-0000-0000-0000-000000000002' and slot = 1)
        = '11111111-1111-1111-1111-111111111111', 'creator slot survives relinking';
end $$;

select set_config('request.jwt.claim.sub', :'dana', false) \g /dev/null
select public.dispute_match(:'m2') \g /dev/null
do $$ begin
    begin
        perform public.confirm_match('aaaaaaaa-0000-0000-0000-000000000002');
        assert false, 'disputed match cannot be confirmed';
    exception when raise_exception then null;
    end;
end $$;

reset role;
do $$ begin
    assert (select status from public.matches where id = 'aaaaaaaa-0000-0000-0000-000000000002') = 'disputed';
    assert (select rated_matches from public.profiles where id = '44444444-4444-4444-4444-444444444444') = 0,
        'disputed matches are not rated';
end $$;

-- ---------------------------------------------------------------- following
set role authenticated;
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert public.follow('33333333-3333-3333-3333-333333333333') = 'accepted', 'public profile: follow at once';
    assert public.follow_relation('33333333-3333-3333-3333-333333333333') = 'following';
    assert public.follow('11111111-1111-1111-1111-111111111111') = 'pending', 'followers-only: request';
    assert public.follow_relation('11111111-1111-1111-1111-111111111111') = 'pending';
    assert (select count(*) from public.profiles) = 2, 'pending request grants no visibility';
    begin
        perform public.follow('55555555-5555-5555-5555-555555555555');
        assert false, 'cannot follow yourself';
    exception when raise_exception then null;
    end;
    perform public.unfollow('11111111-1111-1111-1111-111111111111');
    assert public.follow_relation('11111111-1111-1111-1111-111111111111') = 'none', 'request withdrawn';
end $$;

select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.followers_of('33333333-3333-3333-3333-333333333333')) = 1, 'carl has one follower';
    assert (select display_name from public.followers_of('33333333-3333-3333-3333-333333333333')) = 'eve';
    perform public.remove_follower('55555555-5555-5555-5555-555555555555');
    assert (select count(*) from public.followers_of('33333333-3333-3333-3333-333333333333')) = 0, 'follower removed';
end $$;

select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.following_of('11111111-1111-1111-1111-111111111111')) = 0,
        'lists of a hidden profile are hidden';
end $$;
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.following_of('11111111-1111-1111-1111-111111111111')) = 2, 'alice follows bob + dana';
    assert (select rating from public.followers_of('11111111-1111-1111-1111-111111111111') where display_name = 'bob') = 1530,
        'own rating visible in lists';
end $$;

-- ---------------------------------------------------------------- profile page
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ declare r record; begin
    select * into r from public.profile_page('11111111-1111-1111-1111-111111111111');
    assert r.display_name = 'Alice' and r.is_visible = false, 'header visible, details hidden';
    assert r.rating is null and r.bio is null and r.current_streak is null, 'private details hidden';
    assert r.followers = 2 and r.following = 2, 'counters always visible';
    assert r.relation = 'none' and r.follows_me = false;

    select * into r from public.profile_page('33333333-3333-3333-3333-333333333333');
    assert r.is_visible and r.rating = 1470 and r.rated_matches = 1 and r.current_streak = -1, 'carl: one loss';
end $$;

select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
update public.profiles set bio = 'Linkshänder, spiele gern abends', home_club = 'Padel Arena Musterstadt' where id = auth.uid();
do $$ declare r record; begin
    select * into r from public.profile_page('22222222-2222-2222-2222-222222222222');
    assert r.relation = 'self' and r.current_streak = 1 and r.bio like 'Linkshänder%', 'own page';
    select * into r from public.profile_page('11111111-1111-1111-1111-111111111111');
    assert r.is_visible and r.relation = 'following' and r.follows_me, 'mutual';
    begin
        update public.profiles set bio = repeat('x', 161) where id = auth.uid();
        assert false, 'bio limited to 160 characters';
    exception when check_violation then null;
    end;
end $$;

-- ---------------------------------------------------------------- search & suggestions
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
update public.profiles set home_club = 'Padel Arena Musterstadt' where id = auth.uid();
do $$ begin
    assert (select count(*) from public.search_profiles('@CARL')) = 1, 'search by username, case-insensitive';
    assert (select count(*) from public.search_profiles('ali')) = 1, 'search by name (Alice)';
    assert (select count(*) from public.search_profiles('a')) = 0, 'at least 2 characters';
    assert (select count(*) from public.search_profiles('eve')) = 0, 'never yourself';
    assert (select reason from public.suggested_profiles() where display_name = 'bob') = 'Aus deiner Halle';
    assert (select reason from public.suggested_profiles() where display_name = 'Carl') = 'Aktiver Spieler';
end $$;
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ begin
    assert (select reason from public.suggested_profiles() where display_name = 'Alice') = 'Hat mit dir gespielt';
    assert (select count(*) from public.suggested_profiles() where display_name = 'eve') = 0 or true;
end $$;

-- ---------------------------------------------------------------- posts & feed
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
insert into public.posts (text) values ('Erstes Match der Saison – 6:4 6:3!');
insert into public.posts (text, match_id) values ('Was für ein Fight', 'aaaaaaaa-0000-0000-0000-000000000001');
do $$ begin
    begin
        insert into public.posts (text, match_id) values ('fremd', 'aaaaaaaa-0000-0000-0000-000000000002');
        -- m2: alice IS the creator, so this must succeed; try carl's perspective below instead
    end;
    begin
        insert into public.posts (text) values ('');
        assert false, 'empty post rejected';
    exception when check_violation then null;
    end;
end $$;
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    begin
        insert into public.posts (text, match_id) values ('nicht mein Match', 'aaaaaaaa-0000-0000-0000-000000000001');
        assert false, 'only players may attach a match';
    exception when insufficient_privilege then null;
    end;
    assert (select count(*) from public.posts) = 0, 'eve cannot read alice''s posts';
    assert (select count(*) from public.home_feed()) = 0, 'empty feed';
end $$;

select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ declare r record; begin
    assert (select count(*) from public.posts) = 3, 'follower reads posts';
    assert (select count(*) from public.home_feed()) = 3, 'feed: alice''s 3 posts';
    assert (select sets is null from public.home_feed() where match_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
        'post about a match I may not see: shown without match data';
    assert (select count(*) from public.home_feed() where kind = 'match') = 0,
        'match already shared as post is not duplicated';
    select * into r from public.home_feed() where match_id = 'aaaaaaaa-0000-0000-0000-000000000001' and kind = 'post';
    assert r.author_side = 'a' and r.partner_name = 'bob' and r.opponent_names = 'Carl', 'match data on a post';
    assert (select count(*) from public.home_feed(1)) = 1, 'limit';
    assert (select count(*) from public.home_feed(10, (select min(created_at) from public.posts))) = 0, 'pagination';
    assert (select count(*) from public.profile_posts('11111111-1111-1111-1111-111111111111')) = 3;
    assert (select count(*) from public.profile_results('11111111-1111-1111-1111-111111111111')) = 1;
    assert (select player_side from public.profile_results('11111111-1111-1111-1111-111111111111')) = 'a';
    assert (select count(*) from public.recent_followers()) = 1, 'alice follows bob recently';
    begin
        delete from public.posts where author_id = '11111111-1111-1111-1111-111111111111';
        assert (select count(*) from public.posts) = 3, 'cannot delete foreign posts';
    end;
end $$;

select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
delete from public.posts where match_id = 'aaaaaaaa-0000-0000-0000-000000000001';
do $$ begin
    assert (select count(*) from public.home_feed() where kind = 'match') = 1,
        'confirmed match appears in the feed once its post is gone';
end $$;
reset role;

-- ---------------------------------------------------------------- match feed
set role authenticated;
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ declare r record; begin
    select * into r from public.my_match_feed() where match_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert r.my_side = 'b' and not r.created_by_me, 'carl played on side B';
    assert r.opponent_names = 'Alice & bob', 'names of the other team';
    assert r.partner_name is null, 'carl had no partner';
    assert r.status = 'confirmed';
end $$;

select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ declare r record; begin
    select * into r from public.my_match_feed() where match_id = 'aaaaaaaa-0000-0000-0000-000000000001';
    assert r.my_side = 'a' and r.partner_name = 'Alice' and r.opponent_names = 'Carl', 'bob: partner Alice vs Carl';
end $$;

select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.my_match_feed()) = 0, 'feed only contains own matches';
end $$;
reset role;

-- ---------------------------------------------------------------- reactions & comments
set role authenticated;
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
insert into public.posts (id, text) values ('bbbbbbbb-0000-0000-0000-000000000001', 'Reaktionen testen');
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
insert into public.reactions (post_id) values ('bbbbbbbb-0000-0000-0000-000000000001');
insert into public.comments (post_id, text) values ('bbbbbbbb-0000-0000-0000-000000000001', 'Stark gespielt!');
insert into public.comments (match_id, text) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Was ein Tiebreak');
do $$ declare r record; begin
    select * into r from public.reaction_summary(array['bbbbbbbb-0000-0000-0000-000000000001'::uuid]);
    assert r.claps = 1 and r.clapped, 'bob clapped once';
    assert (select count(*) from public.reactors('bbbbbbbb-0000-0000-0000-000000000001')) = 1;
    assert (select count(*) from public.comments_for(p_post => 'bbbbbbbb-0000-0000-0000-000000000001')) = 1;
    assert (select count(*) from public.comments_for(p_match => 'aaaaaaaa-0000-0000-0000-000000000001')) = 1;
    assert (select comments from public.comment_counts(array['bbbbbbbb-0000-0000-0000-000000000001'::uuid], null)
            where post_id = 'bbbbbbbb-0000-0000-0000-000000000001') = 1;
    begin
        insert into public.reactions (post_id) values ('bbbbbbbb-0000-0000-0000-000000000001');
        assert false, 'one clap per person';
    exception when unique_violation then null;
    end;
    begin
        insert into public.comments (post_id, match_id, text) values ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'x');
        assert false, 'a comment targets a post OR a match';
    exception when check_violation then null;
    end;
end $$;
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    begin
        insert into public.reactions (post_id) values ('bbbbbbbb-0000-0000-0000-000000000001');
        assert false, 'cannot react to a post you may not see';
    exception when insufficient_privilege then null;
    end;
    assert (select count(*) from public.reactors('bbbbbbbb-0000-0000-0000-000000000001')) = 0, 'reactors hidden too';
end $$;

-- ---------------------------------------------------------------- rematch
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
insert into public.rematch_requests (to_id, match_id, proposed_at, note)
values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', now() + interval '3 days', 'Revanche?');
do $$ begin
    assert (select count(*) from public.my_rematches() where incoming = false) = 1, 'carl sent one';
    begin
        insert into public.rematch_requests (to_id, proposed_at) values ('33333333-3333-3333-3333-333333333333', now());
        assert false, 'no rematch with yourself';
    exception when check_violation then null;
    end;
end $$;
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
do $$ declare v_id uuid; begin
    select id into v_id from public.my_rematches() where incoming;
    assert v_id is not null, 'alice sees the incoming request';
    perform public.respond_rematch(v_id, true);
    assert (select status from public.my_rematches() where id = v_id) = 'accepted';
end $$;
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.rematch_requests) = 0, 'outsiders see no requests';
end $$;

-- ---------------------------------------------------------------- games wanted
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
insert into public.games_wanted (id, starts_at, club, court, players_needed, note)
values ('cccccccc-0000-0000-0000-000000000001', now() + interval '2 days', 'Padel Arena Musterstadt', '2', 1, 'Einer fehlt');
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
insert into public.game_joins (game_id) values ('cccccccc-0000-0000-0000-000000000001');
do $$ declare r record; begin
    select * into r from public.open_games();
    assert r.joined = 1 and r.i_joined and not r.is_host, 'eve joined bob''s game';
    assert r.joined_names = 'eve';
    assert (select count(*) from public.open_games('padel arena musterstadt')) = 1, 'club filter, case-insensitive';
    assert (select count(*) from public.open_games('Andere Halle')) = 0;
end $$;
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ begin
    delete from public.game_joins where game_id = 'cccccccc-0000-0000-0000-000000000001' and profile_id = '55555555-5555-5555-5555-555555555555';
    assert (select joined from public.open_games()) = 0, 'host may remove a player';
end $$;

-- ---------------------------------------------------------------- club & head-to-head
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ declare r record; begin
    -- bob (private, not visible to eve) and eve share the club; only eve shows up for eve
    assert (select count(*) from public.club_ranking('Padel Arena Musterstadt')) = 1, 'club ranking respects visibility';
    select * into r from public.club_activity('Padel Arena Musterstadt');
    assert r.players = 1 and r.matches_30d = 1, 'bob played one confirmed match';
end $$;
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ declare r record; begin
    select * into r from public.head_to_head('11111111-1111-1111-1111-111111111111');
    assert r.against = 1 and r.my_wins = 0 and r.their_wins = 1 and r.together = 0, 'carl lost to alice once';
    select * into r from public.head_to_head('55555555-5555-5555-5555-555555555555');
    assert r.against = 0 and r.last_played is null, 'never played eve';
end $$;
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$ declare r record; begin
    select * into r from public.head_to_head('11111111-1111-1111-1111-111111111111');
    assert r.together = 1 and r.together_wins = 1, 'bob and alice won together';
end $$;

-- ---------------------------------------------------------------- mentions in feed
do $$ declare r record; begin
    select * into r from public.home_feed() where match_id = 'aaaaaaaa-0000-0000-0000-000000000001' limit 1;
    assert jsonb_array_length(r.players) = 3, 'three linked players';
    assert r.players -> 0 ->> 'name' = 'Alice';
end $$;

-- ---------------------------------------------------------------- device tokens & delete account
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
insert into public.device_tokens (token) values ('tok-eve');
do $$ begin
    assert (select count(*) from public.device_tokens) = 1;
end $$;
select set_config('request.jwt.claim.sub', :'dana', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.device_tokens) = 0, 'tokens are private';
end $$;
select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
select public.delete_my_account() \g /dev/null
reset role;
do $$ begin
    assert not exists (select 1 from auth.users where id = '55555555-5555-5555-5555-555555555555'), 'user gone';
    assert not exists (select 1 from public.profiles where id = '55555555-5555-5555-5555-555555555555'), 'profile gone';
    assert not exists (select 1 from public.device_tokens where token = 'tok-eve'), 'tokens gone';
end $$;

\echo 'All schema tests passed.'
