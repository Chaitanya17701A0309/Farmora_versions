-- Farmora Module 2: Community Demand Exchange.
-- Lives in its own `demand` schema and has NO references to marketplace tables
-- (products, orders, ...). It depends only on core identity: public.profiles / farmer_profiles.
-- The marketplace can be disabled, migrated or broken without affecting this module, and vice versa.

create schema if not exists demand;
grant usage on schema demand to anon, authenticated, service_role;

create type demand.item_kind      as enum ('crop', 'product');
create type demand.item_status    as enum ('pending', 'active', 'archived');
create type demand.season         as enum ('kharif', 'rabi', 'zaid', 'year_round');
create type demand.request_status as enum ('pending', 'approved', 'merged', 'rejected');
create type demand.poll_status    as enum ('draft', 'active', 'closed');
create type demand.question_type  as enum ('single_choice', 'multi_choice', 'rating', 'text');
create type demand.harvest_status as enum ('upcoming', 'harvested', 'cancelled');

-- =========================================================
-- VOTING CYCLES (one per agricultural season)
-- =========================================================
create table demand.cycles (
  id         smallint generated always as identity primary key,
  name       text not null unique,                 -- "Rabi 2026-27"
  season     demand.season not null,
  starts_on  date not null,
  ends_on    date not null,
  is_current boolean not null default false,
  check (ends_on > starts_on)
);
create unique index cycles_one_current_idx on demand.cycles (is_current) where is_current;

-- =========================================================
-- DEMAND ITEMS (what families can vote for; independent of marketplace products)
-- =========================================================
create table demand.items (
  id         uuid primary key default gen_random_uuid(),
  kind       demand.item_kind not null,
  slug       text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name       text not null check (char_length(name) between 2 and 80),
  name_i18n  jsonb not null default '{}',          -- {"te": "...", "ta": "...", "hi": "..."}
  category   text,                                 -- millets, pulses, oilseeds, vegetables, spices, honey, ghee, oils ...
  image_path text,                                 -- demand-images bucket
  seasons    demand.season[] not null default '{}',
  status     demand.item_status not null default 'active',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index items_kind_status_idx on demand.items (kind, status);
create index items_name_trgm_idx   on demand.items using gin (name extensions.gin_trgm_ops);

-- =========================================================
-- VOTES (each family gets a limited number per cycle so votes carry signal)
-- =========================================================
create table demand.votes (
  user_id     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  item_id     uuid not null references demand.items(id) on delete cascade,
  cycle_id    smallint not null references demand.cycles(id),
  monthly_qty numeric(8,2) check (monthly_qty > 0 and monthly_qty <= 1000),
  qty_unit    text check (qty_unit in ('kg', 'litre', 'piece', 'dozen')),
  state       text,                                -- snapshot of voter region
  district    text,
  created_at  timestamptz not null default now(),
  primary key (user_id, item_id, cycle_id),
  check ((monthly_qty is null) = (qty_unit is null))
);
create index votes_cycle_item_idx   on demand.votes (cycle_id, item_id);
create index votes_item_created_idx on demand.votes (item_id, created_at);
create index votes_created_idx      on demand.votes (created_at);

create or replace function demand.votes_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  -- Serialise a user's votes so the per-cycle limit cannot be bypassed concurrently.
  perform 1 from public.profiles where id = new.user_id for update;

  if new.cycle_id is null then
    select id into new.cycle_id from demand.cycles where is_current;
  end if;
  if not exists (select 1 from demand.cycles where id = new.cycle_id and is_current) then
    raise exception 'CYCLE_CLOSED';
  end if;
  if not exists (select 1 from demand.items where id = new.item_id and status = 'active') then
    raise exception 'ITEM_NOT_ACTIVE';
  end if;

  select count(*) into v_count from demand.votes where user_id = new.user_id and cycle_id = new.cycle_id;
  if v_count >= 10 then
    raise exception 'VOTE_LIMIT_REACHED';
  end if;

  select p.state, p.district into new.state, new.district from public.profiles p where p.id = new.user_id;
  new.created_at := now();
  return new;
end $$;
create trigger votes_before_insert before insert on demand.votes
  for each row execute function demand.votes_before_insert();

-- =========================================================
-- REQUESTS (families ask for crops/products not yet listed)
-- =========================================================
create table demand.requests (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind              demand.item_kind not null,
  title             text not null check (char_length(title) between 3 and 120),
  description       text check (char_length(description) <= 1000),
  monthly_qty       numeric(8,2) check (monthly_qty > 0 and monthly_qty <= 1000),
  qty_unit          text check (qty_unit in ('kg', 'litre', 'piece', 'dozen')),
  preferred_season  demand.season,
  organic_preferred boolean not null default false,
  state             text,
  district          text,
  pincode           text check (pincode ~ '^[1-9][0-9]{5}$'),
  status            demand.request_status not null default 'pending',
  item_id           uuid references demand.items(id) on delete set null,   -- set on approve/merge
  reviewed_by       uuid references public.profiles(id) on delete set null,
  reviewed_at       timestamptz,
  review_note       text,
  created_at        timestamptz not null default now()
);
create index requests_status_idx on demand.requests (status, created_at);
create index requests_item_idx   on demand.requests (item_id) where item_id is not null;
create index requests_user_idx   on demand.requests (user_id, created_at desc);

create or replace function demand.requests_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from demand.requests
       where user_id = new.user_id and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'REQUEST_LIMIT_REACHED';
  end if;
  select coalesce(new.state, p.state), coalesce(new.district, p.district)
    into new.state, new.district
    from public.profiles p where p.id = new.user_id;
  return new;
end $$;
create trigger requests_before_insert before insert on demand.requests
  for each row execute function demand.requests_before_insert();

-- =========================================================
-- POLLS & SURVEYS
-- =========================================================
create table demand.polls (
  id               uuid primary key default gen_random_uuid(),
  title            text not null check (char_length(title) between 3 and 150),
  title_i18n       jsonb not null default '{}',
  description      text,
  description_i18n jsonb not null default '{}',
  status           demand.poll_status not null default 'draft',
  target_state     text,                           -- null = everyone
  target_district  text,
  starts_at        timestamptz not null default now(),
  ends_at          timestamptz not null,
  results_public   boolean not null default true,
  created_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index polls_status_idx on demand.polls (status, ends_at);

create table demand.poll_questions (
  id          uuid primary key default gen_random_uuid(),
  poll_id     uuid not null references demand.polls(id) on delete cascade,
  sort_order  smallint not null default 0,
  prompt      text not null,
  prompt_i18n jsonb not null default '{}',
  type        demand.question_type not null,
  -- [{"id": 1, "label": "Groundnut", "label_i18n": {...}, "item_id": "<demand.items.id>"}]
  options     jsonb not null default '[]' check (jsonb_typeof(options) = 'array'),
  is_required boolean not null default true
);
create index poll_questions_poll_idx on demand.poll_questions (poll_id, sort_order);

create table demand.poll_responses (
  id           uuid primary key default gen_random_uuid(),
  poll_id      uuid not null references demand.polls(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  state        text,
  district     text,
  submitted_at timestamptz not null default now(),
  unique (poll_id, user_id)
);

create table demand.poll_answers (
  response_id uuid not null references demand.poll_responses(id) on delete cascade,
  question_id uuid not null references demand.poll_questions(id) on delete cascade,
  option_ids  smallint[],
  rating      smallint check (rating between 1 and 5),
  text_answer text check (char_length(text_answer) <= 500),
  primary key (response_id, question_id)
);
create index poll_answers_question_idx on demand.poll_answers (question_id);

-- =========================================================
-- UPCOMING HARVESTS & PRE-ORDER INTEREST (non-binding, no payment)
-- =========================================================
create table demand.harvest_announcements (
  id                      uuid primary key default gen_random_uuid(),
  farmer_id               uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  item_id                 uuid references demand.items(id) on delete set null,
  crop_name               text not null check (char_length(crop_name) between 2 and 80),
  variety                 text,
  expected_harvest_date   date not null,
  quantity_kg             numeric(10,2) not null check (quantity_kg > 0),
  price_hint_paise_per_kg bigint check (price_hint_paise_per_kg > 0),   -- indicative only
  is_organic              boolean not null default false,
  state                   text,
  district                text,
  description             text check (char_length(description) <= 1000),
  image_path              text,
  status                  demand.harvest_status not null default 'upcoming',
  created_at              timestamptz not null default now()
);
create index harvests_upcoming_idx on demand.harvest_announcements (expected_harvest_date) where status = 'upcoming';
create index harvests_farmer_idx   on demand.harvest_announcements (farmer_id);

create table demand.preorder_interests (
  announcement_id uuid not null references demand.harvest_announcements(id) on delete cascade,
  user_id         uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  quantity        numeric(8,2) not null check (quantity > 0 and quantity <= 500),
  unit            text not null default 'kg' check (unit in ('kg', 'litre', 'piece', 'dozen')),
  note            text check (char_length(note) <= 300),
  state           text,
  district        text,
  created_at      timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create or replace function demand.preorder_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from demand.harvest_announcements
                  where id = new.announcement_id and status = 'upcoming') then
    raise exception 'HARVEST_NOT_OPEN';
  end if;
  select p.state, p.district into new.state, new.district from public.profiles p where p.id = new.user_id;
  return new;
end $$;
create trigger preorder_before_insert before insert on demand.preorder_interests
  for each row execute function demand.preorder_before_insert();

-- =========================================================
-- AGGREGATES (materialised; refreshed by pg_cron)
-- =========================================================
create materialized view demand.mv_item_votes as
select v.cycle_id,
       v.item_id,
       coalesce(v.state, '')    as state,
       coalesce(v.district, '') as district,
       count(*)::bigint         as votes,
       coalesce(sum(v.monthly_qty) filter (where v.qty_unit = 'kg'), 0)    as monthly_kg,
       coalesce(sum(v.monthly_qty) filter (where v.qty_unit = 'litre'), 0) as monthly_litre
  from demand.votes v
 group by 1, 2, 3, 4;
create unique index mv_item_votes_pk on demand.mv_item_votes (cycle_id, item_id, state, district);

create or replace function demand.refresh_stats() returns void
language sql security definer set search_path = '' as $$
  refresh materialized view concurrently demand.mv_item_votes;
$$;

select cron.schedule('demand-refresh-stats', '*/10 * * * *', $$select demand.refresh_stats()$$);

-- =========================================================
-- ACCESS HELPERS
-- =========================================================
create or replace function demand.assert_admin() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
end $$;

create or replace function demand.assert_insights_access() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(public.current_app_role() in ('farmer', 'admin'), false) is false then
    raise exception 'FORBIDDEN';
  end if;
end $$;

create or replace function demand.current_cycle_id() returns smallint
language sql stable security definer set search_path = '' as $$
  select id from demand.cycles where is_current
$$;

-- =========================================================
-- PUBLIC READ FUNCTIONS (families, landing page)
-- =========================================================
create or replace function demand.get_leaderboard(
  p_kind demand.item_kind default null, p_state text default null, p_district text default null,
  p_cycle_id smallint default null, p_limit int default 20
) returns table (rank bigint, item_id uuid, kind demand.item_kind, slug text, name text, name_i18n jsonb,
                 image_path text, votes bigint, monthly_kg numeric, monthly_litre numeric)
language sql stable security definer set search_path = '' as $$
  select rank() over (order by sum(m.votes) desc),
         i.id, i.kind, i.slug, i.name, i.name_i18n, i.image_path,
         sum(m.votes)::bigint, sum(m.monthly_kg), sum(m.monthly_litre)
    from demand.mv_item_votes m
    join demand.items i on i.id = m.item_id
   where m.cycle_id = coalesce(p_cycle_id, demand.current_cycle_id())
     and i.status = 'active'
     and (p_kind is null or i.kind = p_kind)
     and (p_state is null or m.state = p_state)
     and (p_district is null or m.district = p_district)
   group by i.id
   order by sum(m.votes) desc, i.name
   limit least(greatest(p_limit, 1), 100);
$$;

create or replace function demand.get_trending(
  p_kind demand.item_kind default null, p_days int default 7, p_limit int default 10
) returns table (item_id uuid, kind demand.item_kind, slug text, name text, name_i18n jsonb, image_path text,
                 recent_votes bigint, previous_votes bigint, growth_pct numeric)
language sql stable security definer set search_path = '' as $$
  with params as (select least(greatest(p_days, 1), 90) as d),
  counts as (
    select v.item_id,
           count(*) filter (where v.created_at >= now() - make_interval(days => (select d from params)))  as recent,
           count(*) filter (where v.created_at <  now() - make_interval(days => (select d from params)))  as previous
      from demand.votes v
     where v.created_at >= now() - make_interval(days => 2 * (select d from params))
     group by v.item_id
  )
  select i.id, i.kind, i.slug, i.name, i.name_i18n, i.image_path, c.recent, c.previous,
         case when c.previous = 0 then null else round((c.recent - c.previous) * 100.0 / c.previous, 1) end
    from counts c
    join demand.items i on i.id = c.item_id
   where i.status = 'active' and (p_kind is null or i.kind = p_kind) and c.recent >= 3
   order by (c.recent - c.previous) desc, c.recent desc
   limit least(greatest(p_limit, 1), 50);
$$;

create or replace function demand.get_upcoming_harvests(
  p_state text default null, p_district text default null, p_item_id uuid default null, p_limit int default 30
) returns table (id uuid, crop_name text, variety text, item_id uuid, expected_harvest_date date,
                 quantity_kg numeric, price_hint_paise_per_kg bigint, is_organic boolean, state text,
                 district text, description text, image_path text, farmer_id uuid, farm_name text,
                 farmer_verified boolean, interested_families bigint, interested_qty_kg numeric, i_am_interested boolean)
language sql stable security definer set search_path = '' as $$
  select h.id, h.crop_name, h.variety, h.item_id, h.expected_harvest_date, h.quantity_kg,
         h.price_hint_paise_per_kg, h.is_organic, h.state, h.district, h.description, h.image_path,
         h.farmer_id, fp.farm_name, coalesce(fp.is_verified, false),
         (select count(*) from demand.preorder_interests pi where pi.announcement_id = h.id),
         (select coalesce(sum(pi.quantity), 0) from demand.preorder_interests pi
           where pi.announcement_id = h.id and pi.unit = 'kg'),
         exists (select 1 from demand.preorder_interests pi where pi.announcement_id = h.id and pi.user_id = auth.uid())
    from demand.harvest_announcements h
    left join public.farmer_profiles fp on fp.id = h.farmer_id
   where h.status = 'upcoming'
     and h.expected_harvest_date >= current_date - 7
     and (p_state is null or h.state = p_state)
     and (p_district is null or h.district = p_district)
     and (p_item_id is null or h.item_id = p_item_id)
   order by h.expected_harvest_date
   limit least(greatest(p_limit, 1), 100);
$$;

create or replace function demand.get_poll_results(p_poll_id uuid)
returns table (question_id uuid, option_id smallint, responses bigint, avg_rating numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from demand.polls p
                  where p.id = p_poll_id
                    and p.status <> 'draft'
                    and (p.results_public or public.is_admin())) then
    raise exception 'RESULTS_NOT_AVAILABLE';
  end if;

  return query
    select null::uuid, null::smallint, count(*)::bigint, null::numeric        -- total respondents
      from demand.poll_responses r where r.poll_id = p_poll_id
    union all
    select pa.question_id, o.option_id, count(*)::bigint, null::numeric
      from demand.poll_answers pa
      join demand.poll_responses r on r.id = pa.response_id
     cross join lateral unnest(pa.option_ids) as o(option_id)
     where r.poll_id = p_poll_id
     group by pa.question_id, o.option_id
    union all
    select pa.question_id, null::smallint, count(*)::bigint, round(avg(pa.rating), 2)
      from demand.poll_answers pa
      join demand.poll_responses r on r.id = pa.response_id
     where r.poll_id = p_poll_id and pa.rating is not null
     group by pa.question_id;
end $$;

create or replace function demand.get_public_stats()
returns table (families_voted bigint, total_votes bigint, active_items bigint,
               upcoming_harvests bigint, active_polls bigint, farmers bigint)
language sql stable security definer set search_path = '' as $$
  select (select count(distinct user_id) from demand.votes where cycle_id = demand.current_cycle_id()),
         (select count(*) from demand.votes where cycle_id = demand.current_cycle_id()),
         (select count(*) from demand.items where status = 'active'),
         (select count(*) from demand.harvest_announcements where status = 'upcoming'),
         (select count(*) from demand.polls where status = 'active' and now() between starts_at and ends_at),
         (select count(*) from public.profiles where role = 'farmer');
$$;

-- =========================================================
-- FAMILY ACTIONS
-- =========================================================
create or replace function demand.submit_poll_response(p_poll_id uuid, p_answers jsonb)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_poll        demand.polls;
  v_state       text;
  v_district    text;
  v_response_id uuid;
  q             record;
  a             jsonb;
  v_num         int;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if jsonb_typeof(p_answers) <> 'object' then raise exception 'INVALID_PAYLOAD'; end if;

  select * into v_poll from demand.polls where id = p_poll_id;
  if not found or v_poll.status <> 'active' or now() not between v_poll.starts_at and v_poll.ends_at then
    raise exception 'POLL_NOT_OPEN';
  end if;

  select state, district into v_state, v_district from public.profiles where id = auth.uid();
  if (v_poll.target_state is not null and v_state is distinct from v_poll.target_state)
     or (v_poll.target_district is not null and v_district is distinct from v_poll.target_district) then
    raise exception 'POLL_NOT_FOR_REGION';
  end if;

  begin
    insert into demand.poll_responses (poll_id, user_id, state, district)
    values (p_poll_id, auth.uid(), v_state, v_district)
    returning id into v_response_id;
  exception when unique_violation then
    raise exception 'ALREADY_RESPONDED';
  end;

  for q in select * from demand.poll_questions where poll_id = p_poll_id order by sort_order loop
    a := p_answers -> q.id::text;
    if a is null or jsonb_typeof(a) = 'null' then
      if q.is_required then raise exception 'ANSWER_REQUIRED:%', q.id; end if;
      continue;
    end if;

    if q.type = 'single_choice' then
      if jsonb_typeof(a) <> 'number' then raise exception 'INVALID_ANSWER:%', q.id; end if;
      v_num := (a #>> '{}')::int;
      if not exists (select 1 from jsonb_array_elements(q.options) o where (o ->> 'id')::int = v_num) then
        raise exception 'INVALID_ANSWER:%', q.id;
      end if;
      insert into demand.poll_answers (response_id, question_id, option_ids)
      values (v_response_id, q.id, array[v_num::smallint]);

    elsif q.type = 'multi_choice' then
      if jsonb_typeof(a) <> 'array' or jsonb_array_length(a) = 0
         or exists (select 1 from jsonb_array_elements_text(a) x
                     where not exists (select 1 from jsonb_array_elements(q.options) o where o ->> 'id' = x)) then
        raise exception 'INVALID_ANSWER:%', q.id;
      end if;
      insert into demand.poll_answers (response_id, question_id, option_ids)
      values (v_response_id, q.id, (select array_agg(distinct x::smallint) from jsonb_array_elements_text(a) x));

    elsif q.type = 'rating' then
      if jsonb_typeof(a) <> 'number' or (a #>> '{}')::numeric not in (1, 2, 3, 4, 5) then
        raise exception 'INVALID_ANSWER:%', q.id;
      end if;
      insert into demand.poll_answers (response_id, question_id, rating)
      values (v_response_id, q.id, (a #>> '{}')::smallint);

    else -- text
      if jsonb_typeof(a) <> 'string' or char_length(a #>> '{}') > 500 then
        raise exception 'INVALID_ANSWER:%', q.id;
      end if;
      insert into demand.poll_answers (response_id, question_id, text_answer)
      values (v_response_id, q.id, a #>> '{}');
    end if;
  end loop;

  return v_response_id;
end $$;

-- =========================================================
-- FARMER INSIGHTS (farmers & admins; aggregates only, no personal data)
-- =========================================================
create or replace function demand.get_most_requested(
  p_kind demand.item_kind default null, p_days int default 90, p_state text default null, p_limit int default 20
) returns table (item_id uuid, kind demand.item_kind, name text, name_i18n jsonb, requests bigint,
                 monthly_kg numeric, organic_share numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_insights_access();
  return query
    select i.id, i.kind, i.name, i.name_i18n, count(*)::bigint,
           coalesce(sum(r.monthly_qty) filter (where r.qty_unit = 'kg'), 0),
           round(avg(case when r.organic_preferred then 1 else 0 end) * 100, 1)
      from demand.requests r
      join demand.items i on i.id = r.item_id
     where r.status in ('approved', 'merged')
       and r.created_at >= now() - make_interval(days => least(greatest(p_days, 1), 730))
       and (p_kind is null or i.kind = p_kind)
       and (p_state is null or r.state = p_state)
     group by i.id
     order by count(*) desc
     limit least(greatest(p_limit, 1), 100);
end $$;

-- Regions with fewer than 3 voters are hidden to protect privacy.
create or replace function demand.get_demand_by_region(
  p_item_id uuid default null, p_level text default 'state', p_cycle_id smallint default null
) returns table (region text, state text, votes bigint, monthly_kg numeric, monthly_litre numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_insights_access();
  if p_level not in ('state', 'district') then raise exception 'INVALID_LEVEL'; end if;
  return query
    select case when p_level = 'district' then m.district else m.state end,
           m.state, sum(m.votes)::bigint, sum(m.monthly_kg), sum(m.monthly_litre)
      from demand.mv_item_votes m
     where m.cycle_id = coalesce(p_cycle_id, demand.current_cycle_id())
       and (p_item_id is null or m.item_id = p_item_id)
       and m.state <> ''
     group by 1, 2
    having sum(m.votes) >= 3
     order by 3 desc;
end $$;

create or replace function demand.get_seasonal_trends(p_item_id uuid, p_months int default 12)
returns table (month date, votes bigint, requests bigint, preorder_families bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_insights_access();
  return query
    with months as (
      select gs as m_start, gs + interval '1 month' as m_end
        from generate_series(date_trunc('month', now()) - make_interval(months => least(greatest(p_months, 1), 36) - 1),
                             date_trunc('month', now()), interval '1 month') gs
    )
    select m.m_start::date,
           (select count(*) from demand.votes v
             where v.item_id = p_item_id and v.created_at >= m.m_start and v.created_at < m.m_end),
           (select count(*) from demand.requests r
             where r.item_id = p_item_id and r.created_at >= m.m_start and r.created_at < m.m_end),
           (select count(*) from demand.preorder_interests pi
              join demand.harvest_announcements h on h.id = pi.announcement_id
             where h.item_id = p_item_id and pi.created_at >= m.m_start and pi.created_at < m.m_end)
      from months m
     order by 1;
end $$;

create or replace function demand.get_cycle_history(p_item_id uuid)
returns table (cycle_id smallint, cycle_name text, season demand.season, starts_on date, votes bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_insights_access();
  return query
    select c.id, c.name, c.season, c.starts_on, coalesce(sum(m.votes), 0)::bigint
      from demand.cycles c
      left join demand.mv_item_votes m on m.cycle_id = c.id and m.item_id = p_item_id
     group by c.id
     order by c.starts_on;
end $$;

-- Farmers see their own announcements; admins can pass any id.
create or replace function demand.get_preorder_report(p_announcement_id uuid default null)
returns table (announcement_id uuid, crop_name text, expected_harvest_date date, district text,
               families bigint, total_qty numeric, unit text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_insights_access();
  return query
    select h.id, h.crop_name, h.expected_harvest_date, coalesce(pi.district, 'Unknown'),
           count(*)::bigint, sum(pi.quantity), pi.unit
      from demand.harvest_announcements h
      join demand.preorder_interests pi on pi.announcement_id = h.id
     where (h.farmer_id = auth.uid() or public.is_admin())
       and (p_announcement_id is null or h.id = p_announcement_id)
     group by h.id, coalesce(pi.district, 'Unknown'), pi.unit
     order by h.expected_harvest_date, 5 desc;
end $$;

-- =========================================================
-- ADMIN ACTIONS & ANALYTICS
-- =========================================================
create or replace function demand.slugify(p_text text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(nullif(trim(both '-' from regexp_replace(lower(p_text), '[^a-z0-9]+', '-', 'g')), ''), 'item')
$$;

create or replace function demand.admin_review_request(
  p_request_id uuid, p_action text, p_item_id uuid default null, p_note text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_req  demand.requests;
  v_item uuid;
  v_status demand.request_status;
begin
  perform demand.assert_admin();
  select * into v_req from demand.requests where id = p_request_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_req.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_action = 'approve' then
    insert into demand.items (kind, slug, name, seasons, created_by)
    values (v_req.kind,
            demand.slugify(v_req.title) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6),
            left(initcap(v_req.title), 80),
            case when v_req.preferred_season is null then '{}' else array[v_req.preferred_season] end,
            v_req.user_id)
    returning id into v_item;
    v_status := 'approved';
  elsif p_action = 'merge' then
    if p_item_id is null or not exists (select 1 from demand.items where id = p_item_id) then
      raise exception 'ITEM_REQUIRED';
    end if;
    v_item := p_item_id;
    v_status := 'merged';
  elsif p_action = 'reject' then
    v_status := 'rejected';
  else
    raise exception 'INVALID_ACTION';
  end if;

  update demand.requests
     set status = v_status, item_id = v_item, reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note
   where id = p_request_id;

  insert into public.notifications (user_id, title, body, link)
  values (v_req.user_id,
          'Your request was ' || v_status::text,
          case when v_status = 'rejected' then coalesce(p_note, 'Thank you for your suggestion.')
               else '"' || v_req.title || '" is now open for voting.' end,
          '/demand/requests');
  return v_item;
end $$;

create or replace function demand.admin_set_current_cycle(p_cycle_id smallint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform demand.assert_admin();
  update demand.cycles set is_current = false where is_current and id <> p_cycle_id;
  update demand.cycles set is_current = true where id = p_cycle_id;
  if not found then raise exception 'NOT_FOUND'; end if;
end $$;

create or replace function demand.admin_overview()
returns table (families_voted bigint, total_votes bigint, votes_last_7d bigint, pending_requests bigint,
               requests_last_30d bigint, active_polls bigint, poll_responses_30d bigint,
               upcoming_harvests bigint, preorder_families bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform demand.assert_admin();
  return query
    select (select count(distinct user_id) from demand.votes where cycle_id = demand.current_cycle_id()),
           (select count(*) from demand.votes where cycle_id = demand.current_cycle_id()),
           (select count(*) from demand.votes where created_at >= now() - interval '7 days'),
           (select count(*) from demand.requests where status = 'pending'),
           (select count(*) from demand.requests where created_at >= now() - interval '30 days'),
           (select count(*) from demand.polls where status = 'active'),
           (select count(*) from demand.poll_responses where submitted_at >= now() - interval '30 days'),
           (select count(*) from demand.harvest_announcements where status = 'upcoming'),
           (select count(distinct user_id) from demand.preorder_interests);
end $$;

-- =========================================================
-- ROW LEVEL SECURITY & PRIVILEGES
-- =========================================================
alter table demand.cycles                enable row level security;
alter table demand.items                 enable row level security;
alter table demand.votes                 enable row level security;
alter table demand.requests              enable row level security;
alter table demand.polls                 enable row level security;
alter table demand.poll_questions        enable row level security;
alter table demand.poll_responses        enable row level security;
alter table demand.poll_answers          enable row level security;
alter table demand.harvest_announcements enable row level security;
alter table demand.preorder_interests    enable row level security;

revoke all on all tables in schema demand from anon, authenticated;
revoke all on demand.mv_item_votes from anon, authenticated;

-- cycles & items: public read, admin write
grant select on demand.cycles, demand.items to anon, authenticated;
grant insert, update, delete on demand.cycles, demand.items to authenticated;
create policy cycles_read  on demand.cycles for select to anon, authenticated using (true);
create policy cycles_admin on demand.cycles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy items_read  on demand.items for select to anon, authenticated using (status = 'active' or public.is_admin());
create policy items_admin on demand.items for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- votes: families vote, see and change their own votes in the current cycle
grant select on demand.votes to authenticated;
grant insert (item_id, monthly_qty, qty_unit), update (monthly_qty, qty_unit), delete on demand.votes to authenticated;
create policy votes_select on demand.votes for select to authenticated using (user_id = auth.uid());
create policy votes_insert on demand.votes for insert to authenticated
  with check (user_id = auth.uid() and public.current_app_role() = 'family');
create policy votes_update on demand.votes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy votes_delete on demand.votes for delete to authenticated
  using (user_id = auth.uid() and cycle_id = demand.current_cycle_id());

-- requests: families submit; owner sees own; admin sees all (review via RPC)
grant select on demand.requests to authenticated;
grant insert (kind, title, description, monthly_qty, qty_unit, preferred_season, organic_preferred, pincode),
      delete on demand.requests to authenticated;
create policy requests_select on demand.requests for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy requests_insert on demand.requests for insert to authenticated
  with check (user_id = auth.uid() and public.current_app_role() = 'family');
create policy requests_delete on demand.requests for delete to authenticated
  using (user_id = auth.uid() and status = 'pending');

-- polls & questions: visible once published; admin manages; questions editable only in draft
grant select on demand.polls, demand.poll_questions to anon, authenticated;
grant insert, update, delete on demand.polls, demand.poll_questions to authenticated;
create policy polls_read on demand.polls for select to anon, authenticated
  using (status <> 'draft' or public.is_admin());
create policy polls_admin on demand.polls for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy questions_read on demand.poll_questions for select to anon, authenticated
  using (exists (select 1 from demand.polls p
                  where p.id = poll_id and (p.status <> 'draft' or public.is_admin())));
create policy questions_admin on demand.poll_questions for all to authenticated
  using (public.is_admin() and exists (select 1 from demand.polls p where p.id = poll_id and p.status = 'draft'))
  with check (public.is_admin() and exists (select 1 from demand.polls p where p.id = poll_id and p.status = 'draft'));

-- responses/answers: written only through submit_poll_response(); users read their own
grant select on demand.poll_responses, demand.poll_answers to authenticated;
create policy responses_select on demand.poll_responses for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy answers_select on demand.poll_answers for select to authenticated
  using (exists (select 1 from demand.poll_responses r
                  where r.id = response_id and (r.user_id = auth.uid() or public.is_admin())));

-- harvest announcements: public read; farmers manage their own
grant select on demand.harvest_announcements to anon, authenticated;
grant insert (item_id, crop_name, variety, expected_harvest_date, quantity_kg, price_hint_paise_per_kg,
              is_organic, state, district, description, image_path),
      update (item_id, crop_name, variety, expected_harvest_date, quantity_kg, price_hint_paise_per_kg,
              is_organic, state, district, description, image_path, status),
      delete on demand.harvest_announcements to authenticated;
create policy harvests_read on demand.harvest_announcements for select to anon, authenticated
  using (status <> 'cancelled' or farmer_id = auth.uid() or public.is_admin());
create policy harvests_insert on demand.harvest_announcements for insert to authenticated
  with check (farmer_id = auth.uid() and public.current_app_role() = 'farmer');
create policy harvests_update on demand.harvest_announcements for update to authenticated
  using (farmer_id = auth.uid() or public.is_admin()) with check (farmer_id = auth.uid() or public.is_admin());
create policy harvests_delete on demand.harvest_announcements for delete to authenticated
  using (farmer_id = auth.uid() or public.is_admin());

-- pre-order interest: families manage their own; farmers see aggregates via get_preorder_report()
grant select on demand.preorder_interests to authenticated;
grant insert (announcement_id, quantity, unit, note), update (quantity, unit, note), delete
  on demand.preorder_interests to authenticated;
create policy preorder_select on demand.preorder_interests for select to authenticated using (user_id = auth.uid());
create policy preorder_insert on demand.preorder_interests for insert to authenticated
  with check (user_id = auth.uid() and public.current_app_role() = 'family');
create policy preorder_update on demand.preorder_interests for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy preorder_delete on demand.preorder_interests for delete to authenticated using (user_id = auth.uid());

-- functions: deny by default, then allow the public API surface
revoke execute on all functions in schema demand from public, anon, authenticated;

grant execute on function demand.current_cycle_id()                                                      to anon, authenticated;
grant execute on function demand.get_leaderboard(demand.item_kind, text, text, smallint, int)             to anon, authenticated;
grant execute on function demand.get_trending(demand.item_kind, int, int)                                 to anon, authenticated;
grant execute on function demand.get_upcoming_harvests(text, text, uuid, int)                             to anon, authenticated;
grant execute on function demand.get_poll_results(uuid)                                                   to anon, authenticated;
grant execute on function demand.get_public_stats()                                                       to anon, authenticated;
grant execute on function demand.submit_poll_response(uuid, jsonb)                                        to authenticated;
grant execute on function demand.get_most_requested(demand.item_kind, int, text, int)                     to authenticated;
grant execute on function demand.get_demand_by_region(uuid, text, smallint)                               to authenticated;
grant execute on function demand.get_seasonal_trends(uuid, int)                                           to authenticated;
grant execute on function demand.get_cycle_history(uuid)                                                  to authenticated;
grant execute on function demand.get_preorder_report(uuid)                                                to authenticated;
grant execute on function demand.admin_review_request(uuid, text, uuid, text)                             to authenticated;
grant execute on function demand.admin_set_current_cycle(smallint)                                        to authenticated;
grant execute on function demand.admin_overview()                                                         to authenticated;
-- current_cycle_id() is also used inside RLS policies, so callers need execute on it (granted above).
