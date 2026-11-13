-- Behaviour tests for halls, the home hall and hall campaigns in the feed.
-- Run against a fresh database: local_supabase_stub.sql → migrations → this file.

\set QUIET on
\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'
\set carl  '33333333-3333-3333-3333-333333333333'
\set koeln   'bbbbbbbb-0000-0000-0000-000000000001'
\set duess   'bbbbbbbb-0000-0000-0000-000000000002'
\set berlin  'bbbbbbbb-0000-0000-0000-000000000003'
\set closed  'bbbbbbbb-0000-0000-0000-000000000004'

-- ---------------------------------------------------------------- setup (as admin)
insert into auth.users (id, email, raw_user_meta_data) values
    (:'alice', 'alice@example.com', '{"display_name":"Alice"}'),
    (:'bob',   'bob@example.com',   '{"display_name":"Bob"}'),
    (:'carl',  'carl@example.com',  '{"display_name":"Carl"}');

insert into public.halls (id, name, postal_code, city, latitude, longitude, is_active) values
    (:'koeln',  'Padel Köln',      '50667', 'Köln',       50.9375, 6.9603, true),
    (:'duess',  'Padel Düsseldorf', '40213', 'Düsseldorf', 51.2277, 6.7735, true),   -- ~35 km from Köln
    (:'berlin', 'Padel Berlin',    '10115', 'Berlin',     52.5200, 13.4050, true),
    (:'closed', 'Padel Köln Süd',  '50968', 'Köln',       50.9000, 6.9700, false);

insert into public.hall_campaigns (id, hall_id, headline, cta_url, radius_km, ends_at, is_paused, max_impressions, daily_cap_per_player) values
    ('cccccccc-0000-0000-0000-000000000001', :'koeln',  'Happy Hour Köln',     'https://example.com/k', 25, now() + interval '30 days', false, null, 3),
    ('cccccccc-0000-0000-0000-000000000002', :'duess',  'Turnier Düsseldorf',  'https://example.com/d', 25, now() + interval '30 days', false, null, 3),
    ('cccccccc-0000-0000-0000-000000000003', :'koeln',  'Pausiert',            'https://example.com/p', 25, now() + interval '30 days', true,  null, 3),
    ('cccccccc-0000-0000-0000-000000000004', :'berlin', 'Berlin Challenge',    'https://example.com/b', 25, now() + interval '30 days', false, null, 1),
    ('cccccccc-0000-0000-0000-000000000005', :'koeln',  'Nur ein Mal',         'https://example.com/o', 25, now() + interval '30 days', false, 1,    3),
    ('cccccccc-0000-0000-0000-000000000006', :'closed', 'Geschlossene Halle',  'https://example.com/c', 25, now() + interval '30 days', false, null, 3);
insert into public.hall_campaigns (hall_id, headline, cta_url, starts_at, ends_at) values
    (:'koeln', 'Abgelaufen', 'https://example.com/x', now() - interval '10 days', now() - interval '1 day');

insert into public.hall_managers (hall_id, profile_id) values (:'koeln', :'bob');

do $$ begin
    assert round(public.distance_km(50.9375, 6.9603, 51.2277, 6.7735)) between 34 and 36, 'Köln–Düsseldorf ≈ 35 km';
    begin
        insert into public.hall_campaigns (hall_id, headline, cta_url, ends_at)
        values ('bbbbbbbb-0000-0000-0000-000000000001', 'Unsicher', 'http://example.com', now() + interval '1 day');
        assert false, 'only https links';
    exception when check_violation then null;
    end;
end $$;

-- ---------------------------------------------------------------- players: halls
set role authenticated;
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null

do $$ begin
    assert (select count(*) from public.search_halls(null, null, null)) = 0, 'no query, no position → nothing';
    assert (select count(*) from public.search_halls('köl', null, null)) = 1, 'search by name (inactive hall hidden)';
    assert (select count(*) from public.search_halls('402', null, null)) = 1, 'search by postal code';
    assert (select name from public.search_halls(null, 50.94, 6.96) limit 1) = 'Padel Köln', 'nearest first';
    assert (select count(*) from public.halls) = 3, 'inactive halls are not readable';
    assert (select count(*) from public.feed_ads(null, null, 5)) = 0, 'no position, no home hall → no ads';
end $$;

-- Choosing a home hall fills home_club with its name; free text cannot override it.
update public.profiles set home_hall_id = 'bbbbbbbb-0000-0000-0000-000000000001' where id = auth.uid();
update public.profiles set home_club = 'Irgendwas' where id = auth.uid();
do $$ begin
    assert (select home_club from public.profiles where id = auth.uid()) = 'Padel Köln', 'home_club follows the hall';
    assert (select players from public.search_halls('köln', null, null) where name = 'Padel Köln') = 1, 'player count';
    assert (select distance_km from public.search_halls('düssel', null, null)) between 34 and 36,
        'distance from the home hall without a position';
end $$;

-- ---------------------------------------------------------------- players: ads
do $$
declare headlines text[];
begin
    select array_agg(headline order by headline) into headlines from public.feed_ads(null, null, 5);
    assert headlines = array['Happy Hour Köln', 'Nur ein Mal'],
        'only running campaigns within the radius of the home hall: ' || coalesce(headlines::text, 'none');
    select array_agg(headline) into headlines from public.feed_ads(52.52, 13.40, 5);
    assert headlines = array['Berlin Challenge'], 'a position overrides the home hall';
    assert (select count(*) from public.feed_ads(null, null, 1)) = 1, 'limit';
end $$;

do $$ begin
    begin
        perform * from public.hall_campaigns;
        assert false, 'campaigns are not directly readable';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.ad_events (campaign_id, profile_id, kind)
        values ('cccccccc-0000-0000-0000-000000000001', auth.uid(), 'click');
        assert false, 'events only through log_ad_event';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.log_ad_event('cccccccc-0000-0000-0000-000000000001', 'like');
        assert false, 'unknown event kind';
    exception when insufficient_privilege then null;
    end;
end $$;

-- Impressions within 30 minutes count once; clicks always.
select public.log_ad_event('cccccccc-0000-0000-0000-000000000001', 'impression') \g /dev/null
select public.log_ad_event('cccccccc-0000-0000-0000-000000000001', 'impression') \g /dev/null
select public.log_ad_event('cccccccc-0000-0000-0000-000000000001', 'click') \g /dev/null
-- Uses up the paid volume (1) of "Nur ein Mal"; Berlin has a daily cap of 1.
select public.log_ad_event('cccccccc-0000-0000-0000-000000000005', 'impression') \g /dev/null
select public.log_ad_event('cccccccc-0000-0000-0000-000000000004', 'impression') \g /dev/null

do $$ begin
    assert (select array_agg(headline) from public.feed_ads(null, null, 5)) = array['Happy Hour Köln'],
        'campaign stops when the paid impressions are used up';
    assert (select count(*) from public.feed_ads(52.52, 13.40, 5)) = 0, 'daily cap per player';
    assert (select count(*) from public.campaign_report('cccccccc-0000-0000-0000-000000000001')) = 0,
        'players do not get reports';
end $$;

-- A second player in Köln: "Nur ein Mal" is used up for everybody.
select set_config('request.jwt.claim.sub', :'carl', false) \g /dev/null
do $$ begin
    assert (select array_agg(headline) from public.feed_ads(50.94, 6.96, 5)) = array['Happy Hour Köln'],
        'paid volume is global';
end $$;
select public.log_ad_event('cccccccc-0000-0000-0000-000000000001', 'impression') \g /dev/null

-- ---------------------------------------------------------------- hall staff report
select set_config('request.jwt.claim.sub', :'bob', false) \g /dev/null
do $$
declare r record;
begin
    select * into r from public.campaign_report('cccccccc-0000-0000-0000-000000000001');
    assert r.impressions = 2, 'impressions: ' || r.impressions;
    assert r.players_reached = 2, 'players reached';
    assert r.clicks = 1, 'clicks';
    assert r.click_rate = 0.5, 'click rate';
    assert (select count(*) from public.campaign_report('cccccccc-0000-0000-0000-000000000002')) = 0,
        'no report for another hall';
end $$;

-- Clearing the hall keeps a free-text home club.
select set_config('request.jwt.claim.sub', :'alice', false) \g /dev/null
update public.profiles set home_hall_id = null, home_club = 'Köln' where id = auth.uid();
do $$ begin
    assert (select home_club from public.profiles where id = auth.uid()) = 'Köln', 'free text without a hall';
end $$;

reset role;
do $$ begin
    assert (select sum(impressions) from public.campaign_stats) = 4, 'stats view for the team';
end $$;

\echo 'All hall and ad tests passed.'
