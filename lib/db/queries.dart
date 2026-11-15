import 'projects.dart';

/// Every SQL query HQ runs, in one place, so they're easy to read and check.
/// All of them only READ, and only the columns hq_reader was granted.
/// Days are Sri Lanka days (Asia/Colombo).
class HqQuery {
  const HqQuery(this.key, this.projectId, this.source, this.sql, {this.optional = false});

  final String key; // cache key
  /// true = needs an extra SQL step that may not be run yet; if it fails, screens stay quiet
  /// (no red box) and show what they can without it.
  final bool optional;
  final String projectId; // which database (db/projects.dart)
  final String source; // shown under the numbers: where they come from
  final String sql;

  HqProject get project => hqProjects.firstWhere((p) => p.id == projectId);
}

class Q {
  // ---------------------------------------------------------------- Today
  static const today = HqQuery('today', 'gemstok', 'Gemstok', '''
with b as (
  select (date_trunc('day', now() at time zone 'Asia/Colombo') at time zone 'Asia/Colombo') as today
)
select
  (select count(*) from public.members m, b where m.created_at >= b.today)::int                          as signups_today,
  (select count(*) from public.members m, b where m.created_at >= b.today - interval '6 days')::int      as signups_7d,
  (select count(distinct l.member_id) from public.login_history l, b where l.created_at >= b.today)::int as active_today,
  (select count(distinct l.member_id) from public.login_history l, b
     where l.created_at >= b.today - interval '6 days')::int                                             as active_7d,
  (select coalesce(sum(t.amount), 0) from public.credit_transactions t, b
     where t.type = 'purchase' and t.created_at >= b.today
       and lower(coalesce(t.metadata ->> 'environment', '')) <> 'sandbox')::float8                       as credits_today,
  (select coalesce(sum(t.amount), 0) from public.credit_transactions t, b
     where t.type = 'purchase' and t.created_at >= b.today - interval '6 days'
       and lower(coalesce(t.metadata ->> 'environment', '')) <> 'sandbox')::float8                       as credits_7d,
  (select count(*) from public.credit_transactions t, b
     where t.type = 'purchase' and t.created_at >= b.today - interval '6 days'
       and lower(coalesce(t.metadata ->> 'environment', '')) <> 'sandbox')::int                          as purchases_7d,
  (select count(*) from hq.member_providers() p
     where not exists (select 1 from public.members m where m.id = p.member_id))::int                    as logins_without_member
''');

  // ---------------------------------------------------------------- Joining
  /// One row per (day, app, guessed, sign-in type) with a count. All time.
  /// app: member_signup.app when the app recorded it, else the first app opened (guessed).
  static const joining = HqQuery('joining', 'gemstok', 'Gemstok · members, member_signup, login_history, sign-in type', '''
with first_app as (
  select distinct on (member_id) member_id, app
  from public.login_history
  order by member_id, created_at
), prov as (
  select member_id, provider from hq.member_providers()
)
select (mm.created_at at time zone 'Asia/Colombo')::date      as day,
       coalesce(s.app, fa.app, 'no app yet')                   as app,
       (s.app is null and fa.app is not null)                  as guessed,
       coalesce(s.signin_type, p.provider, 'unknown')          as signin,
       count(*)::int                                           as n
from public.members mm
left join public.member_signup s on s.member_id = mm.id
left join first_app fa           on fa.member_id = mm.id
left join prov p                 on p.member_id = mm.id
where mm.created_at is not null
group by 1, 2, 3, 4
order by 1
''');

  // ---------------------------------------------------------------- Using + staying
  /// People who opened each app in the last 24 h / 7 days / 30 days.
  static const active = HqQuery('active', 'gemstok', 'Gemstok · login_history', '''
select case when grouping(app) = 1 then 'all apps' else app end                                as app,
       count(distinct member_id) filter (where created_at >= now() - interval '1 day')::int   as d1,
       count(distinct member_id) filter (where created_at >= now() - interval '7 days')::int  as d7,
       count(distinct member_id) filter (where created_at >= now() - interval '30 days')::int as d30
from public.login_history
group by rollup(app)
order by grouping(app) desc, d30 desc
''');

  /// Releases: which app version each person used last (last 30 days), per app + device.
  static const appVersions = HqQuery('app_versions', 'gemstok', 'Gemstok · login_history', '''
with latest as (
  select distinct on (member_id, app) app, app_version, device_os, created_at
  from public.login_history
  where created_at >= now() - interval '30 days'
  order by member_id, app, created_at desc
)
select app, coalesce(nullif(app_version, ''), 'unknown') as version, coalesce(device_os, '?') as device,
       count(*)::int as people, max(created_at) as last_seen
from latest
group by 1, 2, 3
order by 1, 5 desc
''');

  /// Week-1 return: of the people who joined in a week, how many opened an app again
  /// on day 1–7 after their join day. Last 12 join weeks.
  static const retention = HqQuery('retention', 'gemstok', 'Gemstok · members, login_history', '''
with m as (
  select id,
         (created_at at time zone 'Asia/Colombo')                    as joined,
         date_trunc('week', created_at at time zone 'Asia/Colombo') as week
  from public.members
  where created_at is not null
)
select m.week::date                        as week,
       count(*)::int                       as joined,
       count(*) filter (where exists (
         select 1 from public.login_history l
         where l.member_id = m.id
           and (l.created_at at time zone 'Asia/Colombo') >= date_trunc('day', m.joined) + interval '1 day'
           and (l.created_at at time zone 'Asia/Colombo') <  date_trunc('day', m.joined) + interval '8 days'
       ))::int                             as returned,
       (m.week + interval '15 days' <= now() at time zone 'Asia/Colombo') as complete
from m
group by m.week
order by m.week desc
limit 12
''');

  // ---------------------------------------------------------------- Doing (credits)
  /// Credit movements per day, app, type and perk — last 90 days, test purchases left out.
  static const credits = HqQuery('credits', 'gemstok', 'Gemstok · credit_transactions · no test buys', '''
select (t.created_at at time zone 'Asia/Colombo')::date as day,
       coalesce(t.metadata ->> 'app', 'unknown')        as app,
       t.type                                            as type,
       coalesce(t.metadata ->> 'perk', '')               as perk,
       count(*)::int                                     as n,
       coalesce(sum(t.amount), 0)::float8                as credits
from public.credit_transactions t
where t.created_at >= now() - interval '90 days'
  and lower(coalesce(t.metadata ->> 'environment', '')) <> 'sandbox'
group by 1, 2, 3, 4
order by 1
''');

  // ---------------------------------------------------------------- People
  static const newestMembers = HqQuery('newest_members', 'gemstok', 'Gemstok · members', '''
select mm.gemstok_id, mm.name, mm.username, mm.created_at, mm.last_seen_at, mm.last_seen_app,
       coalesce(s.app, fa.app)            as app,
       (s.app is null)                    as guessed
from public.members mm
left join public.member_signup s on s.member_id = mm.id
left join lateral (
  select l.app from public.login_history l
  where l.member_id = mm.id order by l.created_at limit 1
) fa on true
order by mm.created_at desc nulls last
limit 30
''');

  /// Names for the Ideas "From" search. Kept in HQ's memory only; never in an ASK snapshot.
  static const memberNames = HqQuery('member_names', 'gemstok', 'Gemstok · members', '''
select id::text as id, gemstok_id, name, username
from public.members
where coalesce(is_deleted, false) = false and gemstok_id like 'GSM-%'
order by name
limit 5000
''');

  /// One person, by GSM ID ($1) or username ($2). Not cached — runs on Search.
  static const personSql = r'''
select mm.id::text as member_id, mm.gemstok_id, mm.name, mm.username, mm.tier, mm.verified, mm.country, mm.created_at,
       mm.last_seen_app, mm.last_seen_at, mm.last_seen_device, mm.last_app_version, mm.login_count,
       mm.is_deleted, mm.deleted_at, mm.private_vault_plan, mm.subscription_status,
       concat_ws(', ',
         case when mm.is_student  then 'student'  end, case when mm.is_miner    then 'miner'    end,
         case when mm.is_agent    then 'agent'    end, case when mm.is_gem_lab  then 'gem lab'  end,
         case when mm.is_cutter   then 'cutter'   end, case when mm.is_consumer then 'consumer' end) as roles,
       s.app as signup_app, s.app_version as signup_version, s.signin_type,
       (select p.provider from hq.member_providers() p where p.member_id = mm.id)            as provider,
       (select string_agg(x.app || ' ×' || x.n, ', ' order by x.n desc)
          from (select l.app, count(*) as n from public.login_history l
                where l.member_id = mm.id group by l.app) x)                               as apps,
       (select min(l.created_at) from public.login_history l where l.member_id = mm.id)    as first_open,
       w.balance::float8                                                                   as balance,
       pk.ad_free_until,
       (select count(*) from public.credit_transactions t
          where t.member_id = mm.id and t.type = 'purchase')::int                         as purchases,
       (select count(*) from public.credit_transactions t
          where t.member_id = mm.id and t.type = 'deduct')::int                           as spends
from public.members mm
left join public.member_signup s  on s.member_id = mm.id
left join public.credit_wallets w on w.member_id = mm.id
left join public.member_perks pk  on pk.member_id = mm.id
where upper(mm.gemstok_id) = upper($1::text)
   or ($2::text <> '' and lower(mm.username) = lower($2::text))
limit 5
''';

  // ---------------------------------------------------------------- Reports
  /// Report DETAILS — only work after each project's sql/2026-11-14_hq_report_details. Until then they
  /// fail quietly and Reports shows the basic tables.
  static const traderReportDetails = HqQuery('trader_report_details', 'gemstok', 'Gemstok · trader_reports + members', '''
select r.id::text as id, r.details, r.admin_note,
       rp.gemstok_id as reporter_gsm, rp.name as reporter_name,
       rd.gemstok_id as reported_gsm, rd.name as reported_name
from public.trader_reports r
left join public.members rp on rp.id = r.reporter_id
left join public.members rd on rd.id = r.reported_id
order by r.created_at desc
limit 200
''', optional: true);

  static const stoneReportDetails = HqQuery('stone_report_details', 'mkv', 'ManiKVault data · stone_reports', '''
select id::text as id, reporter_id::text as reporter_id, seller_id::text as seller_id, details, admin_note
from public.stone_reports
order by created_at desc
limit 200
''', optional: true);

  static const postReportDetails = HqQuery('post_report_details', 'gemmit', 'Gemmit · post_reports', '''
select id::text as id, reporter_id::text as reporter_id, additional_details as details
from public.post_reports
order by created_at desc
limit 200
''', optional: true);

  /// Reports about PEOPLE (Gemstok) — basic columns (always readable).
  static const traderReports = HqQuery('trader_reports', 'gemstok', 'Gemstok · trader_reports', '''
select id::text as id, reason, source, status, created_at, reviewed_at
from public.trader_reports
order by created_at desc
limit 200
''');

  // ================================================================ ManiKVault data
  /// Market + vault stone counts. "Listed" uses listed_at, or created_at for older market stones.
  static const mkvStones = HqQuery('mkv_stones', 'mkv', 'ManiKVault data · stones', '''
with b as (
  select (date_trunc('day', now() at time zone 'Asia/Colombo') at time zone 'Asia/Colombo') as today
)
select
  count(*) filter (where s.layer = 'market' and s.business_status = 'active')::int                    as market_active,
  count(*) filter (where s.layer = 'market' and coalesce(s.listed_at, s.created_at) >= b.today)::int  as listed_today,
  count(*) filter (where s.layer = 'market'
                     and coalesce(s.listed_at, s.created_at) >= b.today - interval '6 days')::int    as listed_7d,
  count(*) filter (where s.layer = 'vault' and s.business_status <> 'archived')::int                  as vault_cloud,
  count(*) filter (where s.layer = 'trace')::int                                                      as trace,
  count(*) filter (where s.business_status = 'sold')::int                                             as sold,
  count(*) filter (where s.boost_until > now())::int                                                  as boosted_now,
  count(distinct s.owner_id) filter (where s.layer = 'market' and s.business_status = 'active')::int as sellers
from public.stones s, b
''');

  /// Market listings per day, last 90 days.
  static const mkvListingsPerDay = HqQuery('mkv_listings_day', 'mkv', 'ManiKVault data · stones', '''
select (coalesce(listed_at, created_at) at time zone 'Asia/Colombo')::date as day, count(*)::int as n
from public.stones
where layer = 'market' and coalesce(listed_at, created_at) >= now() - interval '90 days'
group by 1 order by 1
''');

  /// Boosted-stone views and taps per day, last 90 days.
  static const mkvBoostViews = HqQuery('mkv_boost_views', 'mkv', 'ManiKVault data · stone_boost_stats', '''
select day, sum(views)::int as views, sum(taps)::int as taps
from public.stone_boost_stats
where day >= current_date - 90
group by day order by day
''');

  static const mkvStoneReports = HqQuery('mkv_stone_reports', 'mkv', 'ManiKVault data · stone_reports', '''
select id::text as id, stone_mkv_id, reason, app, status, created_at, reviewed_at
from public.stone_reports
order by created_at desc
limit 200
''');

  /// One person's stones ($1 = member id). Not cached — People screen.
  static const personStonesSql = r'''
select count(*) filter (where business_status <> 'archived')::int                          as stones,
       count(*) filter (where layer = 'market' and business_status = 'active')::int        as on_market,
       count(*) filter (where business_status = 'sold')::int                               as sold
from public.stones
where owner_id = $1::uuid
''';

  // ================================================================ Social
  static const socialFollows = HqQuery('social_follows', 'social', 'Social · follows', '''
select count(*)::int                        as follows,
       count(distinct follower_id)::int     as people_following,
       count(distinct following_id)::int    as people_followed
from public.follows
''');

  // ================================================================ Chat (counts only)
  static const chatCounts = HqQuery('chat_counts', 'chat', 'Chat · conversations, messages (counts only)', '''
select
  (select count(*) from public.conversations)::int                                                   as conversations,
  (select count(*) from public.conversations where created_at >= now() - interval '7 days')::int     as started_7d,
  (select count(*) from public.conversations where created_at >= now() - interval '30 days')::int    as started_30d,
  (select count(*) from public.messages where created_at >= now() - interval '7 days')::int          as messages_7d,
  (select count(*) from public.messages where created_at >= now() - interval '30 days')::int         as messages_30d
''');

  // ================================================================ Gemmit
  static const gemmitCounts = HqQuery('gemmit_counts', 'gemmit', 'Gemmit · posts, circles, comments', '''
select
  (select count(*) from public.posts)::int                                                    as posts,
  (select count(*) from public.posts where created_at >= now() - interval '7 days')::int      as posts_7d,
  (select count(*) from public.posts where created_at >= now() - interval '30 days')::int     as posts_30d,
  (select count(*) from public.circles)::int                                                  as circles,
  (select count(*) from public.circles where created_at >= now() - interval '30 days')::int   as circles_30d,
  (select count(*) from public.circle_memberships)::int                                       as memberships,
  (select count(*) from public.comments where created_at >= now() - interval '7 days')::int   as comments_7d
''');

  static const gemmitPostReports = HqQuery('gemmit_post_reports', 'gemmit', 'Gemmit · post_reports', '''
select id::text as id, reason, created_at
from public.post_reports
order by created_at desc
limit 200
''');

  // ================================================================ Websites
  static const siteLeads = HqQuery('site_leads', 'websites', 'IntoGemology · waitlist, subscribers, contacts (counts only)', '''
select
  (select count(*) from public.waitlist)::int                                                    as waitlist,
  (select count(*) from public.waitlist where created_at >= now() - interval '7 days')::int      as waitlist_7d,
  (select count(*) from public.subscribers)::int                                                 as subscribers,
  (select count(*) from public.contacts)::int                                                    as contacts
''');
// subscribers / contacts have no created_at (they use subscribed_at / submitted_at, which hq_reader
// wasn't given) — so only their totals here.

  /// Get-page visits per campaign tag (Websites · campaign_visits).
  static const campaignVisits = HqQuery('campaign_visits', 'websites', 'IntoGemology · campaign_visits', '''
select tag,
       sum(visits)::int                                                                   as visits,
       coalesce(sum(visits) filter (where day >= current_date - 6), 0)::int                as visits_7d
from public.campaign_visits
group by tag
''', optional: true);

  /// Sign-ups per campaign tag (Gemstok · member_signup.from_tag — filled once the apps send it).
  static const campaignSignups = HqQuery('campaign_signups', 'gemstok', 'Gemstok · member_signup', '''
select from_tag as tag, count(*)::int as signups
from public.member_signup
where from_tag is not null
group by from_tag
''');

  // ================================================================ Quvlet video / TraceGems
  /// Quvlet videos (real tables, 14 Nov 2026: videos · video_likes · video_reports). "videos" = ready to watch.
  static const quvletCounts = HqQuery('quvlet_counts', 'quvlet_video', 'Quvlet video · videos, video_likes, video_reports', '''
select count(*) filter (where processing_status = 'ready')::int                                         as videos,
       count(*) filter (where processing_status = 'ready' and created_at >= now() - interval '7 days')::int as videos_7d,
       count(*) filter (where processing_status is distinct from 'ready')::int                           as not_ready,
       coalesce(sum(view_count), 0)::bigint                                                              as views,
       (select count(*) from public.video_likes)::int                                                    as likes,
       (select count(*) from public.video_reports)::int                                                  as reports
from public.videos
''');

  /// TraceGems records (the `tracegems` table — the only real table there, 14 Nov 2026): counts only.
  static const traceCounts = HqQuery('trace_counts', 'tracegems', 'TraceGems · tracegems', '''
select count(*)::int                                                             as records,
       count(*) filter (where minted_at is not null)::int                        as minted,
       count(*) filter (where created_at >= now() - interval '30 days')::int     as last_30d
from public.tracegems
''');

  // ================================================================ Money
  /// Store purchases (Gem Broker's Apple + Google credit packs), last 365 days, per day / store / product.
  /// ManiKVault's older Android purchase function doesn't write store_purchases — its buys show under credits.
  static const storePurchases = HqQuery('store_purchases', 'gemstok', 'Gemstok · store_purchases', '''
select (p.created_at at time zone 'Asia/Colombo')::date as day,
       p.store, p.app, p.product_id,
       lower(coalesce(p.environment, '')) as environment,
       count(*)::int                        as n,
       coalesce(sum(p.credits), 0)::float8  as credits
from public.store_purchases p
where p.created_at >= now() - interval '365 days'
group by 1, 2, 3, 4, 5
order by 1
''');

  // ================================================================ Storage
  /// Database size + the 5 biggest tables. Size functions need no table rights, so hq_reader can run it.
  static const _sizeSql = '''
select pg_database_size(current_database())::bigint as bytes,
  (select json_agg(t) from (
     select c.relname as name, pg_total_relation_size(c.oid)::bigint as bytes
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
     order by 2 desc limit 5) t)::text as top
''';

  static const dbSizes = [
    HqQuery('size_gemstok', 'gemstok', 'Gemstok · database size', _sizeSql),
    HqQuery('size_mkv', 'mkv', 'ManiKVault data · database size', _sizeSql),
    HqQuery('size_social', 'social', 'Social · database size', _sizeSql),
    HqQuery('size_chat', 'chat', 'Chat · database size', _sizeSql),
    HqQuery('size_gemmit', 'gemmit', 'Gemmit · database size', _sizeSql),
    HqQuery('size_quvlet_video', 'quvlet_video', 'Quvlet video · database size', _sizeSql),
    HqQuery('size_tracegems', 'tracegems', 'TraceGems · database size', _sizeSql),
    HqQuery('size_websites', 'websites', 'IntoGemology · database size', _sizeSql),
  ];

  // ================================================================ Cron jobs (needs all-projects/sql/2026-11-14_hq_cron)
  static const _cronSql = '''
select jobid, jobname, schedule, active, last_status, last_start, last_end, last_message, runs_24h, failed_24h
from hq.cron_jobs()
''';

  static const cronJobs = [
    HqQuery('cron_gemstok', 'gemstok', 'Gemstok · cron jobs', _cronSql, optional: true),
    HqQuery('cron_mkv', 'mkv', 'ManiKVault data · cron jobs', _cronSql, optional: true),
    HqQuery('cron_social', 'social', 'Social · cron jobs', _cronSql, optional: true),
    HqQuery('cron_chat', 'chat', 'Chat · cron jobs', _cronSql, optional: true),
    HqQuery('cron_gemmit', 'gemmit', 'Gemmit · cron jobs', _cronSql, optional: true),
    HqQuery('cron_quvlet_video', 'quvlet_video', 'Quvlet video · cron jobs', _cronSql, optional: true),
    HqQuery('cron_tracegems', 'tracegems', 'TraceGems · cron jobs', _cronSql, optional: true),
    HqQuery('cron_websites', 'websites', 'IntoGemology · cron jobs', _cronSql, optional: true),
  ];

  // ================================================================ App switches (needs gemstok/sql/2026-11-14_app_config_operator)
  static const appConfig = HqQuery('app_config', 'gemstok', 'Gemstok · app_config', '''
select app, maintenance, message, min_app_version, updated_at
from public.app_config
order by app
''', optional: true);

  // ================================================================ Keep alive
  /// A real read per project (count of its main table) — what "Ping now" and the daily ping run.
  static const pingSql = <String, String>{
    'gemstok': 'select count(*)::int from public.members',
    'mkv': 'select count(*)::int from public.stones',
    'social': 'select count(*)::int from public.follows',
    'chat': 'select count(*)::int from public.conversations',
    'gemmit': 'select count(*)::int from public.posts',
    'quvlet_video': 'select count(*)::int from public.videos',
    'tracegems': 'select count(*)::int from public.tracegems',
    'websites': 'select count(*)::int from public.waitlist',
  };

  static const pingTable = <String, String>{
    'gemstok': 'members', 'mkv': 'stones', 'social': 'follows', 'chat': 'conversations',
    'gemmit': 'posts', 'quvlet_video': 'videos', 'tracegems': 'tracegems', 'websites': 'waitlist',
  };
}
