-- Farmora MVP (Supabase): identity, roles, farmer module, notifications, loyalty, data caches.
-- Money is stored in paise (bigint). All tables use RLS; privileges are granted explicitly.

create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_cron;

-- =========================================================
-- ENUMS
-- =========================================================
create type public.app_role         as enum ('family', 'farmer', 'admin');
create type public.app_locale       as enum ('en', 'te', 'ta', 'hi');
create type public.crop_status      as enum ('planned', 'sown', 'growing', 'harvested', 'failed');
create type public.crop_health      as enum ('healthy', 'at_risk', 'diseased');
create type public.task_type        as enum ('fertilizer', 'irrigation', 'pesticide', 'weeding', 'other');
create type public.expense_category as enum ('seeds', 'fertilizer', 'pesticide', 'labour', 'irrigation', 'equipment', 'transport', 'other');

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- =========================================================
-- PROFILES (1:1 with auth.users)
-- =========================================================
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  role             public.app_role   not null default 'family',
  full_name        text              not null default '' check (char_length(full_name) <= 120),
  avatar_path      text,
  phone            text check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  locale           public.app_locale not null default 'en',
  state            text,
  district         text,
  pincode          text check (pincode ~ '^[1-9][0-9]{5}$'),
  referral_code    text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  referred_by      uuid references public.profiles(id) on delete set null,
  marketing_opt_in boolean not null default false,
  whatsapp_opt_in  boolean not null default false,
  utm              jsonb,
  onboarded_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index profiles_role_idx   on public.profiles (role);
create index profiles_region_idx on public.profiles (state, district);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.current_app_role() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

-- Role from sign-up metadata is limited to family/farmer; admins are promoted manually.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_referrer uuid;
begin
  select id into v_referrer
    from public.profiles
   where referral_code = upper(new.raw_user_meta_data ->> 'ref');

  insert into public.profiles (id, role, full_name, avatar_path, referred_by, utm)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'farmer' then 'farmer'::public.app_role else 'family'::public.app_role end,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 120),
    new.raw_user_meta_data ->> 'avatar_url',
    v_referrer,
    case when jsonb_typeof(new.raw_user_meta_data -> 'utm') = 'object' then new.raw_user_meta_data -> 'utm' end
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================
-- FARMER PROFILE (public storefront info)
-- =========================================================
create table public.farmer_profiles (
  id          uuid primary key references public.profiles(id) on delete cascade,
  farm_name   text not null default '' check (char_length(farm_name) <= 150),
  bio         text check (char_length(bio) <= 2000),
  village     text,
  district    text,
  state       text,
  is_organic  boolean not null default false,
  is_verified boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger farmer_profiles_updated_at before update on public.farmer_profiles
  for each row execute function public.set_updated_at();

create or replace function public.set_my_role(p_role public.app_role) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_role = 'admin' then raise exception 'FORBIDDEN'; end if;

  update public.profiles
     set role = p_role, onboarded_at = coalesce(onboarded_at, now())
   where id = auth.uid() and role <> 'admin';

  if p_role = 'farmer' then
    insert into public.farmer_profiles (id) values (auth.uid()) on conflict (id) do nothing;
  end if;
end $$;

-- =========================================================
-- FARMS, CROPS, TASKS, EXPENSES (private to the farmer)
-- =========================================================
create table public.farms (
  id           uuid primary key default gen_random_uuid(),
  farmer_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 120),
  area_acres   numeric(10,2) not null check (area_acres > 0),
  soil_type    text,
  water_source text,
  village      text,
  district     text,
  state        text,
  latitude     numeric(9,6) check (latitude between -90 and 90),
  longitude    numeric(9,6) check (longitude between -180 and 180),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index farms_farmer_idx on public.farms (farmer_id);
create trigger farms_updated_at before update on public.farms
  for each row execute function public.set_updated_at();

create table public.crops (
  id                    uuid primary key default gen_random_uuid(),
  farm_id               uuid not null references public.farms(id) on delete cascade,
  farmer_id             uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  crop_name             text not null check (char_length(crop_name) between 1 and 80),
  variety               text,
  season                text check (season in ('kharif', 'rabi', 'zaid', 'year_round')),
  area_acres            numeric(10,2) check (area_acres > 0),
  status                public.crop_status not null default 'planned',
  health                public.crop_health not null default 'healthy',
  sowing_date           date,
  expected_harvest_date date,
  actual_harvest_date   date,
  estimated_yield_kg    numeric(12,2) check (estimated_yield_kg >= 0),
  actual_yield_kg       numeric(12,2) check (actual_yield_kg >= 0),
  image_paths           text[] not null default '{}',
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (expected_harvest_date is null or sowing_date is null or expected_harvest_date >= sowing_date)
);
create index crops_farmer_idx  on public.crops (farmer_id);
create index crops_farm_idx    on public.crops (farm_id);
create index crops_harvest_idx on public.crops (expected_harvest_date) where status in ('sown', 'growing');
create trigger crops_updated_at before update on public.crops
  for each row execute function public.set_updated_at();

create table public.crop_tasks (
  id         uuid primary key default gen_random_uuid(),
  crop_id    uuid not null references public.crops(id) on delete cascade,
  farmer_id  uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  type       public.task_type not null,
  title      text not null check (char_length(title) between 1 and 150),
  details    jsonb,
  due_date   date not null,
  done_at    timestamptz,
  created_at timestamptz not null default now()
);
create index crop_tasks_due_idx on public.crop_tasks (farmer_id, due_date) where done_at is null;

create table public.farm_expenses (
  id           uuid primary key default gen_random_uuid(),
  farm_id      uuid not null references public.farms(id) on delete cascade,
  crop_id      uuid references public.crops(id) on delete set null,
  farmer_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  category     public.expense_category not null,
  amount_paise bigint not null check (amount_paise > 0),
  spent_on     date not null,
  note         text check (char_length(note) <= 255),
  created_at   timestamptz not null default now()
);
create index farm_expenses_farmer_idx on public.farm_expenses (farmer_id, spent_on desc);

-- =========================================================
-- NOTIFICATIONS, LOYALTY POINTS
-- =========================================================
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text not null,
  link       text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.points_ledger (              -- balance = sum(points)
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  points     integer not null,
  reason     text not null,                       -- referral | order | redeem | bonus
  ref_id     uuid,
  created_at timestamptz not null default now()
);
create index points_ledger_user_idx on public.points_ledger (user_id);

-- =========================================================
-- EXTERNAL DATA CACHES (filled by scheduled jobs)
-- =========================================================
create table public.market_prices (
  id                  bigint generated always as identity primary key,
  commodity           text not null,
  variety             text not null default '',
  market              text not null,
  district            text,
  state               text not null,
  min_price_per_qtl   numeric(10,2),
  max_price_per_qtl   numeric(10,2),
  modal_price_per_qtl numeric(10,2),
  price_date          date not null,
  unique (commodity, variety, market, price_date)
);
create index market_prices_lookup_idx on public.market_prices (commodity, state, price_date desc);

create table public.weather_cache (
  district   text not null,
  state      text not null,
  forecast   jsonb not null,
  fetched_at timestamptz not null default now(),
  primary key (state, district)
);

-- =========================================================
-- ADMIN HELPERS
-- =========================================================
create or replace function public.admin_verify_farmer(p_farmer_id uuid, p_verified boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  update public.farmer_profiles set is_verified = p_verified where id = p_farmer_id;
end $$;

create or replace function public.admin_list_users(
  p_role public.app_role default null, p_search text default null,
  p_limit int default 50, p_offset int default 0
) returns table (id uuid, email text, full_name text, role public.app_role, state text, district text,
                 is_verified boolean, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  return query
    select p.id, u.email::text, p.full_name, p.role, p.state, p.district,
           fp.is_verified, p.created_at, u.last_sign_in_at
      from public.profiles p
      join auth.users u on u.id = p.id
      left join public.farmer_profiles fp on fp.id = p.id
     where (p_role is null or p.role = p_role)
       and (p_search is null or p.full_name ilike '%' || p_search || '%' or u.email ilike '%' || p_search || '%')
     order by p.created_at desc
     limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
end $$;

-- =========================================================
-- ROW LEVEL SECURITY & PRIVILEGES
-- =========================================================
alter table public.profiles        enable row level security;
alter table public.farmer_profiles enable row level security;
alter table public.farms           enable row level security;
alter table public.crops           enable row level security;
alter table public.crop_tasks      enable row level security;
alter table public.farm_expenses   enable row level security;
alter table public.notifications   enable row level security;
alter table public.points_ledger   enable row level security;
alter table public.market_prices   enable row level security;
alter table public.weather_cache   enable row level security;

revoke all on public.profiles, public.farmer_profiles, public.farms, public.crops, public.crop_tasks,
              public.farm_expenses, public.notifications, public.points_ledger,
              public.market_prices, public.weather_cache
  from anon, authenticated;

-- profiles: own row only; role/referral fields are not client-writable
grant select on public.profiles to authenticated;
grant update (full_name, avatar_path, phone, locale, state, district, pincode, marketing_opt_in, whatsapp_opt_in)
  on public.profiles to authenticated;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- farmer_profiles: public storefront; verification is admin-only (via RPC)
grant select on public.farmer_profiles to anon, authenticated;
grant update (farm_name, bio, village, district, state, is_organic) on public.farmer_profiles to authenticated;
create policy farmer_profiles_select on public.farmer_profiles for select to anon, authenticated using (true);
create policy farmer_profiles_update on public.farmer_profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- farms / crops / tasks / expenses: farmer owns, admin reads
grant select, insert, update, delete on public.farms, public.crops, public.crop_tasks, public.farm_expenses to authenticated;

create policy farms_owner on public.farms for all to authenticated
  using (farmer_id = auth.uid())
  with check (farmer_id = auth.uid() and public.current_app_role() = 'farmer');
create policy farms_admin_read on public.farms for select to authenticated using (public.is_admin());

create policy crops_owner on public.crops for all to authenticated
  using (farmer_id = auth.uid())
  with check (farmer_id = auth.uid()
              and exists (select 1 from public.farms f where f.id = farm_id and f.farmer_id = auth.uid()));
create policy crops_admin_read on public.crops for select to authenticated using (public.is_admin());

create policy crop_tasks_owner on public.crop_tasks for all to authenticated
  using (farmer_id = auth.uid())
  with check (farmer_id = auth.uid()
              and exists (select 1 from public.crops c where c.id = crop_id and c.farmer_id = auth.uid()));

create policy farm_expenses_owner on public.farm_expenses for all to authenticated
  using (farmer_id = auth.uid())
  with check (farmer_id = auth.uid()
              and exists (select 1 from public.farms f where f.id = farm_id and f.farmer_id = auth.uid()));

-- notifications: read own, mark read
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- points: read own (writes happen in security-definer functions / server)
grant select on public.points_ledger to authenticated;
create policy points_select on public.points_ledger for select to authenticated using (user_id = auth.uid());

-- public reference data
grant select on public.market_prices, public.weather_cache to anon, authenticated;
create policy market_prices_read on public.market_prices for select to anon, authenticated using (true);
create policy weather_cache_read on public.weather_cache for select to anon, authenticated using (true);

-- functions
revoke execute on function public.admin_verify_farmer(uuid, boolean) from public, anon;
revoke execute on function public.admin_list_users(public.app_role, text, int, int) from public, anon;
revoke execute on function public.set_my_role(public.app_role) from public, anon;
grant execute on function public.admin_verify_farmer(uuid, boolean) to authenticated;
grant execute on function public.admin_list_users(public.app_role, text, int, int) to authenticated;
grant execute on function public.set_my_role(public.app_role) to authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
