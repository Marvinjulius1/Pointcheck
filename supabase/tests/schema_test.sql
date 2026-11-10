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
    assert (select visibility from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 'friends',
        'friends-only by default';
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

-- Alice ↔ Bob and Alice ↔ Dana become friends.
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
insert into public.friendships (requester_id, addressee_id) values (:'alice', :'bob'), (:'alice', :'dana');
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
update public.friendships set status = 'accepted' where requester_id = :'alice';
select set_config('request.jwt.claim.sub', :'dana', false) \g /dev/null
update public.friendships set status = 'accepted' where requester_id = :'alice';

select set_config('request.jwt.claim.sub', :'eve', false) \g /dev/null
do $$ begin
    assert (select count(*) from public.profiles) = 2, 'eve sees herself and public carl only';
    assert (select count(*) from public.friendships) = 0, 'eve sees no foreign friendships';
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
insert into public.match_players (match_id, slot, profile_id) values (:'m2', 3, :'dana');

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

\echo 'All schema tests passed.'
