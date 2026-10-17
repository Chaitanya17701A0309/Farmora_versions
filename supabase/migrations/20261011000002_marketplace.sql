-- Farmora MVP (Supabase): marketplace (catalog, inventory, cart, wishlist, orders, reviews).
-- Prices, totals and stock changes are computed only in security-definer functions called by the server.

create type public.product_status as enum ('draft', 'pending', 'active', 'inactive', 'rejected');
-- Enum order matters: used with min() to derive order status from item statuses.
create type public.order_status   as enum ('pending_payment', 'confirmed', 'packed', 'shipped', 'delivered', 'cancelled', 'expired');

-- =========================================================
-- CATALOG
-- =========================================================
create table public.categories (
  id         smallint generated always as identity primary key,
  slug       text not null unique,
  name_i18n  jsonb not null,                       -- {"en": "Honey", "te": "...", "ta": "...", "hi": "..."}
  sort_order smallint not null default 0,
  is_active  boolean not null default true
);

create table public.products (
  id               uuid primary key default gen_random_uuid(),
  farmer_id        uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  category_id      smallint not null references public.categories(id),
  slug             text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name             text not null check (char_length(name) between 3 and 120),
  name_i18n        jsonb not null default '{}',
  description      text check (char_length(description) <= 5000),
  description_i18n jsonb not null default '{}',
  is_organic       boolean not null default false,
  status           public.product_status not null default 'pending',
  rejection_reason text,
  rating_avg       numeric(3,2) not null default 0,
  rating_count     integer not null default 0,
  search           tsvector generated always as (
                     to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(description, ''))
                   ) stored,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index products_active_category_idx on public.products (category_id) where status = 'active';
create index products_farmer_idx          on public.products (farmer_id);
create index products_search_idx          on public.products using gin (search);
create index products_name_trgm_idx       on public.products using gin (name extensions.gin_trgm_ops);
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

create table public.product_variants (
  id                  uuid primary key default gen_random_uuid(),
  product_id          uuid not null references public.products(id) on delete cascade,
  farmer_id           uuid not null default auth.uid() references public.profiles(id),
  label               text not null check (char_length(label) between 1 and 40),   -- "500 g"
  weight_grams        integer check (weight_grams > 0),
  mrp_paise           bigint not null check (mrp_paise > 0),
  price_paise         bigint not null check (price_paise > 0),
  stock_qty           integer not null default 0 check (stock_qty >= 0),
  reserved_qty        integer not null default 0 check (reserved_qty >= 0),
  low_stock_threshold integer not null default 5 check (low_stock_threshold >= 0),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (price_paise <= mrp_paise),
  check (reserved_qty <= stock_qty)
);
create index product_variants_product_idx on public.product_variants (product_id);
create index product_variants_farmer_idx  on public.product_variants (farmer_id);
create trigger product_variants_updated_at before update on public.product_variants
  for each row execute function public.set_updated_at();

create table public.product_images (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products(id) on delete cascade,
  farmer_id    uuid not null default auth.uid() references public.profiles(id),
  storage_path text not null,                      -- product-images/<farmer_id>/<file>.webp
  sort_order   smallint not null default 0
);
create index product_images_product_idx on public.product_images (product_id, sort_order);

-- =========================================================
-- CUSTOMER STATE
-- =========================================================
create table public.addresses (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  label      text,
  recipient  text not null check (char_length(recipient) between 1 and 120),
  phone      text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  line1      text not null check (char_length(line1) between 1 and 255),
  line2      text check (char_length(line2) <= 255),
  city       text not null,
  district   text,
  state      text not null,
  pincode    text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index addresses_user_idx on public.addresses (user_id);

create table public.cart_items (
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  quantity   integer not null check (quantity between 1 and 20),
  added_at   timestamptz not null default now(),
  primary key (user_id, variant_id)
);

create table public.wishlist_items (
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  added_at   timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- =========================================================
-- ORDERS
-- =========================================================
create sequence public.order_number_seq start 100001;

create table public.orders (
  id                  uuid primary key default gen_random_uuid(),
  order_number        text not null unique default ('FRM' || nextval('public.order_number_seq')),
  customer_id         uuid not null references public.profiles(id),
  status              public.order_status not null default 'pending_payment',
  shipping_address    jsonb not null,               -- snapshot at order time
  subtotal_paise      bigint not null check (subtotal_paise > 0),
  shipping_paise      bigint not null default 0 check (shipping_paise >= 0),
  discount_paise      bigint not null default 0 check (discount_paise >= 0),
  total_paise         bigint not null check (total_paise > 0),
  razorpay_order_id   text unique,
  razorpay_payment_id text unique,
  payment_method      text,
  expires_at          timestamptz not null default now() + interval '20 minutes',
  paid_at             timestamptz,
  delivered_at        timestamptz,
  cancelled_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index orders_customer_idx on public.orders (customer_id, created_at desc);
create index orders_pending_idx  on public.orders (expires_at) where status = 'pending_payment';
create trigger orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

create table public.order_items (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders(id) on delete cascade,
  customer_id        uuid not null references public.profiles(id),   -- denormalised to avoid RLS recursion
  farmer_id          uuid not null references public.profiles(id),
  product_id         uuid not null references public.products(id),
  variant_id         uuid not null references public.product_variants(id),
  product_name       text not null,
  variant_label      text not null,
  unit_price_paise   bigint not null check (unit_price_paise > 0),
  quantity           integer not null check (quantity > 0),
  line_total_paise   bigint not null,
  fulfillment_status public.order_status not null default 'pending_payment',
  courier            text,
  tracking_number    text,
  updated_at         timestamptz not null default now()
);
create index order_items_order_idx  on public.order_items (order_id);
create index order_items_farmer_idx on public.order_items (farmer_id, fulfillment_status);
create trigger order_items_updated_at before update on public.order_items
  for each row execute function public.set_updated_at();

create table public.payment_events (              -- Razorpay webhook idempotency
  event_id    text primary key,
  event_type  text not null,
  payload     jsonb not null,
  received_at timestamptz not null default now()
);

-- =========================================================
-- REVIEWS (verified purchase only)
-- =========================================================
create table public.reviews (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id) on delete cascade,
  user_id       uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  order_item_id uuid not null unique references public.order_items(id),
  rating        smallint not null check (rating between 1 and 5),
  body          text check (char_length(body) <= 2000),
  reviewer_name text not null default '',
  created_at    timestamptz not null default now(),
  unique (product_id, user_id)
);
create index reviews_product_idx on public.reviews (product_id, created_at desc);

create or replace function public.reviews_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select split_part(coalesce(nullif(full_name, ''), 'Farmora family'), ' ', 1)
    into new.reviewer_name
    from public.profiles where id = new.user_id;
  return new;
end $$;
create trigger reviews_set_name before insert on public.reviews
  for each row execute function public.reviews_before_insert();

create or replace function public.reviews_refresh_rating() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_product uuid := coalesce(new.product_id, old.product_id);
begin
  update public.products p
     set rating_avg   = coalesce((select round(avg(rating)::numeric, 2) from public.reviews where product_id = v_product), 0),
         rating_count = (select count(*) from public.reviews where product_id = v_product)
   where p.id = v_product;
  return null;
end $$;
create trigger reviews_rating after insert or delete on public.reviews
  for each row execute function public.reviews_refresh_rating();

-- =========================================================
-- ORDER WORKFLOW FUNCTIONS (server / service_role only unless noted)
-- =========================================================
create or replace function public.create_pending_order(p_customer_id uuid, p_address_id uuid)
returns public.orders
language plpgsql security definer set search_path = '' as $$
declare
  v_order    public.orders;
  v_address  jsonb;
  v_subtotal bigint := 0;
  v_shipping bigint;
  r          record;
begin
  select to_jsonb(a) - 'id' - 'user_id' - 'is_default' - 'created_at'
    into v_address
    from public.addresses a
   where a.id = p_address_id and a.user_id = p_customer_id;
  if v_address is null then raise exception 'ADDRESS_NOT_FOUND'; end if;

  -- Lock variants in a stable order to avoid deadlocks between concurrent checkouts.
  for r in
    select c.variant_id, c.quantity, v.price_paise, v.stock_qty, v.reserved_qty,
           v.is_active as variant_active, p.status as product_status
      from public.cart_items c
      join public.product_variants v on v.id = c.variant_id
      join public.products p         on p.id = v.product_id
     where c.user_id = p_customer_id
     order by c.variant_id
       for update of v
  loop
    if r.product_status <> 'active' or not r.variant_active then
      raise exception 'UNAVAILABLE:%', r.variant_id;
    end if;
    if r.stock_qty - r.reserved_qty < r.quantity then
      raise exception 'OUT_OF_STOCK:%', r.variant_id;
    end if;
    v_subtotal := v_subtotal + r.price_paise * r.quantity;
  end loop;

  if v_subtotal = 0 then raise exception 'CART_EMPTY'; end if;
  v_shipping := case when v_subtotal >= 49900 then 0 else 4900 end;   -- free shipping from ₹499

  insert into public.orders (customer_id, shipping_address, subtotal_paise, shipping_paise, total_paise)
  values (p_customer_id, v_address, v_subtotal, v_shipping, v_subtotal + v_shipping)
  returning * into v_order;

  insert into public.order_items (order_id, customer_id, farmer_id, product_id, variant_id,
                                  product_name, variant_label, unit_price_paise, quantity, line_total_paise)
  select v_order.id, p_customer_id, v.farmer_id, p.id, v.id,
         p.name, v.label, v.price_paise, c.quantity, v.price_paise * c.quantity
    from public.cart_items c
    join public.product_variants v on v.id = c.variant_id
    join public.products p         on p.id = v.product_id
   where c.user_id = p_customer_id;

  update public.product_variants v
     set reserved_qty = v.reserved_qty + c.quantity
    from public.cart_items c
   where c.user_id = p_customer_id and c.variant_id = v.id;

  return v_order;
end $$;

create or replace function public.confirm_order_payment(
  p_razorpay_order_id text, p_razorpay_payment_id text, p_method text
) returns public.orders
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where razorpay_order_id = p_razorpay_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if v_order.status <> 'pending_payment' then
    if v_order.razorpay_payment_id = p_razorpay_payment_id then
      return v_order;                                      -- idempotent replay (verify + webhook)
    end if;
    raise exception 'ORDER_NOT_PAYABLE:%', v_order.status; -- caller must refund
  end if;

  update public.product_variants v
     set stock_qty = v.stock_qty - oi.quantity,
         reserved_qty = v.reserved_qty - oi.quantity
    from public.order_items oi
   where oi.order_id = v_order.id and oi.variant_id = v.id;

  update public.order_items set fulfillment_status = 'confirmed' where order_id = v_order.id;

  update public.orders
     set status = 'confirmed', razorpay_payment_id = p_razorpay_payment_id,
         payment_method = p_method, paid_at = now()
   where id = v_order.id
  returning * into v_order;

  delete from public.cart_items c
   using public.order_items oi
   where oi.order_id = v_order.id and c.user_id = v_order.customer_id and c.variant_id = oi.variant_id;

  -- Referral reward: first successful order credits both referrer and referee.
  if not exists (select 1 from public.orders
                  where customer_id = v_order.customer_id and id <> v_order.id
                    and status in ('confirmed', 'packed', 'shipped', 'delivered')) then
    insert into public.points_ledger (user_id, points, reason, ref_id)
    select x.uid, 100, 'referral', v_order.id
      from public.profiles p
     cross join lateral (values (p.id), (p.referred_by)) as x(uid)
     where p.id = v_order.customer_id and p.referred_by is not null;
  end if;

  insert into public.notifications (user_id, title, body, link)
  values (v_order.customer_id, 'Order confirmed',
          'Your order ' || v_order.order_number || ' is confirmed.', '/orders/' || v_order.id);

  insert into public.notifications (user_id, title, body, link)
  select distinct oi.farmer_id, 'New order', 'You have a new order ' || v_order.order_number || '.', '/farmer/orders'
    from public.order_items oi where oi.order_id = v_order.id;

  return v_order;
end $$;

create or replace function public.expire_unpaid_orders() returns void
language plpgsql security definer set search_path = '' as $$
begin
  with expired as (
    update public.orders set status = 'expired'
     where status = 'pending_payment' and expires_at < now()
    returning id
  ), released as (
    update public.product_variants v
       set reserved_qty = v.reserved_qty - x.qty
      from (select oi.variant_id, sum(oi.quantity) as qty
              from public.order_items oi join expired e on e.id = oi.order_id
             group by oi.variant_id) x
     where v.id = x.variant_id
    returning 1
  )
  update public.order_items oi
     set fulfillment_status = 'expired'
    from expired e
   where oi.order_id = e.id;
end $$;

create or replace function public.sync_order_status(p_order_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.orders o
     set status = s.min_status,
         delivered_at = case when s.min_status = 'delivered' then now() else o.delivered_at end
    from (select min(fulfillment_status) as min_status
            from public.order_items
           where order_id = p_order_id and fulfillment_status <> 'cancelled') s
   where o.id = p_order_id and s.min_status is not null and o.status <> s.min_status;
$$;

-- Farmer (authenticated): move own items forward confirmed → packed → shipped → delivered.
create or replace function public.farmer_update_fulfillment(
  p_item_id uuid, p_status public.order_status, p_courier text default null, p_tracking text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.order_items;
begin
  select * into v_item from public.order_items where id = p_item_id and farmer_id = auth.uid() for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if not (
       (v_item.fulfillment_status = 'confirmed' and p_status = 'packed')
    or (v_item.fulfillment_status = 'packed'    and p_status = 'shipped')
    or (v_item.fulfillment_status = 'shipped'   and p_status = 'delivered')
  ) then
    raise exception 'INVALID_TRANSITION:%->%', v_item.fulfillment_status, p_status;
  end if;

  update public.order_items
     set fulfillment_status = p_status,
         courier = coalesce(p_courier, courier),
         tracking_number = coalesce(p_tracking, tracking_number)
   where id = p_item_id;

  perform public.sync_order_status(v_item.order_id);

  insert into public.notifications (user_id, title, body, link)
  values (v_item.customer_id, 'Order update',
          v_item.product_name || ' is now ' || p_status::text || '.', '/orders/' || v_item.order_id);
end $$;

-- Farmer (authenticated): hide/unhide an approved product.
create or replace function public.farmer_set_product_active(p_product_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.products
     set status = case when p_active then 'active'::public.product_status else 'inactive'::public.product_status end
   where id = p_product_id and farmer_id = auth.uid() and status in ('active', 'inactive');
  if not found then raise exception 'NOT_ALLOWED'; end if;
end $$;

-- Admin (authenticated + is_admin): approve / reject products.
create or replace function public.admin_set_product_status(
  p_product_id uuid, p_status public.product_status, p_reason text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_farmer uuid;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  update public.products set status = p_status, rejection_reason = p_reason
   where id = p_product_id returning farmer_id into v_farmer;
  if v_farmer is null then raise exception 'NOT_FOUND'; end if;
  insert into public.notifications (user_id, title, body, link)
  values (v_farmer, 'Product ' || p_status::text, coalesce(p_reason, 'Your product status changed.'), '/farmer/products');
end $$;

-- Admin: cancel or override order status; cancelling a paid order restocks (refund is issued by the server).
create or replace function public.admin_update_order_status(p_order_id uuid, p_status public.order_status) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;

  if p_status = 'cancelled' and v_order.status in ('confirmed', 'packed') then
    update public.product_variants v
       set stock_qty = v.stock_qty + oi.quantity
      from public.order_items oi
     where oi.order_id = p_order_id and oi.variant_id = v.id;
  end if;

  update public.order_items set fulfillment_status = p_status where order_id = p_order_id;
  update public.orders
     set status = p_status,
         cancelled_at = case when p_status = 'cancelled' then now() else cancelled_at end,
         delivered_at = case when p_status = 'delivered' then now() else delivered_at end
   where id = p_order_id;
end $$;

select cron.schedule('expire-unpaid-orders', '*/5 * * * *', $$select public.expire_unpaid_orders()$$);

-- =========================================================
-- ROW LEVEL SECURITY & PRIVILEGES
-- =========================================================
alter table public.categories       enable row level security;
alter table public.products         enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_images   enable row level security;
alter table public.addresses        enable row level security;
alter table public.cart_items       enable row level security;
alter table public.wishlist_items   enable row level security;
alter table public.orders           enable row level security;
alter table public.order_items      enable row level security;
alter table public.payment_events   enable row level security;
alter table public.reviews          enable row level security;

revoke all on public.categories, public.products, public.product_variants, public.product_images,
              public.addresses, public.cart_items, public.wishlist_items, public.orders,
              public.order_items, public.payment_events, public.reviews
  from anon, authenticated;
revoke all on sequence public.order_number_seq from anon, authenticated;

-- categories: public read, admin write
grant select on public.categories to anon, authenticated;
grant insert, update, delete on public.categories to authenticated;
create policy categories_read  on public.categories for select to anon, authenticated using (is_active or public.is_admin());
create policy categories_admin on public.categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- products: public sees active; farmer manages own content (status only via RPC)
grant select on public.products to anon, authenticated;
grant insert (category_id, slug, name, name_i18n, description, description_i18n, is_organic) on public.products to authenticated;
grant update (category_id, name, name_i18n, description, description_i18n, is_organic) on public.products to authenticated;
create policy products_read on public.products for select to anon, authenticated
  using (status = 'active' or farmer_id = auth.uid() or public.is_admin());
create policy products_insert on public.products for insert to authenticated
  with check (farmer_id = auth.uid() and public.current_app_role() = 'farmer');
create policy products_update on public.products for update to authenticated
  using (farmer_id = auth.uid()) with check (farmer_id = auth.uid());

-- variants: pricing & stock by owner; reserved_qty is system-managed
grant select on public.product_variants to anon, authenticated;
grant insert (product_id, label, weight_grams, mrp_paise, price_paise, stock_qty, low_stock_threshold, is_active)
  on public.product_variants to authenticated;
grant update (label, weight_grams, mrp_paise, price_paise, stock_qty, low_stock_threshold, is_active)
  on public.product_variants to authenticated;
create policy variants_read on public.product_variants for select to anon, authenticated
  using ((is_active and exists (select 1 from public.products p where p.id = product_id and p.status = 'active'))
         or farmer_id = auth.uid() or public.is_admin());
create policy variants_insert on public.product_variants for insert to authenticated
  with check (farmer_id = auth.uid()
              and exists (select 1 from public.products p where p.id = product_id and p.farmer_id = auth.uid()));
create policy variants_update on public.product_variants for update to authenticated
  using (farmer_id = auth.uid()) with check (farmer_id = auth.uid());

-- images
grant select on public.product_images to anon, authenticated;
grant insert (product_id, storage_path, sort_order), update (sort_order), delete on public.product_images to authenticated;
create policy images_read on public.product_images for select to anon, authenticated
  using (exists (select 1 from public.products p
                  where p.id = product_id and (p.status = 'active' or p.farmer_id = auth.uid() or public.is_admin())));
create policy images_write on public.product_images for all to authenticated
  using (farmer_id = auth.uid())
  with check (farmer_id = auth.uid()
              and storage_path like auth.uid()::text || '/%'
              and exists (select 1 from public.products p where p.id = product_id and p.farmer_id = auth.uid()));

-- addresses, cart, wishlist: owner only
grant select, insert, update, delete on public.addresses to authenticated;
create policy addresses_owner on public.addresses for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, delete on public.cart_items to authenticated;
grant insert (variant_id, quantity), update (quantity) on public.cart_items to authenticated;
create policy cart_owner on public.cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, delete on public.wishlist_items to authenticated;
grant insert (product_id) on public.wishlist_items to authenticated;
create policy wishlist_owner on public.wishlist_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- orders: read-only for customers, farmers with items in the order, admins
grant select on public.orders, public.order_items to authenticated;
create policy order_items_read on public.order_items for select to authenticated
  using (customer_id = auth.uid() or farmer_id = auth.uid() or public.is_admin());
create policy orders_read on public.orders for select to authenticated
  using (customer_id = auth.uid() or public.is_admin()
         or exists (select 1 from public.order_items oi where oi.order_id = orders.id and oi.farmer_id = auth.uid()));

-- payment_events: service_role only (no policies)

-- reviews: public read; verified delivered purchase to write
grant select on public.reviews to anon, authenticated;
grant insert (product_id, order_item_id, rating, body), delete on public.reviews to authenticated;
create policy reviews_read on public.reviews for select to anon, authenticated using (true);
create policy reviews_insert on public.reviews for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.order_items oi
                           where oi.id = order_item_id and oi.customer_id = auth.uid()
                             and oi.product_id = reviews.product_id and oi.fulfillment_status = 'delivered'));
create policy reviews_delete on public.reviews for delete to authenticated using (user_id = auth.uid());

-- functions
revoke execute on function public.create_pending_order(uuid, uuid)            from public, anon, authenticated;
revoke execute on function public.confirm_order_payment(text, text, text)    from public, anon, authenticated;
revoke execute on function public.expire_unpaid_orders()                     from public, anon, authenticated;
revoke execute on function public.sync_order_status(uuid)                    from public, anon, authenticated;
revoke execute on function public.reviews_before_insert()                    from public, anon, authenticated;
revoke execute on function public.reviews_refresh_rating()                   from public, anon, authenticated;
revoke execute on function public.farmer_update_fulfillment(uuid, public.order_status, text, text) from public, anon;
revoke execute on function public.farmer_set_product_active(uuid, boolean)   from public, anon;
revoke execute on function public.admin_set_product_status(uuid, public.product_status, text) from public, anon;
revoke execute on function public.admin_update_order_status(uuid, public.order_status) from public, anon;
grant execute on function public.farmer_update_fulfillment(uuid, public.order_status, text, text) to authenticated;
grant execute on function public.farmer_set_product_active(uuid, boolean)   to authenticated;
grant execute on function public.admin_set_product_status(uuid, public.product_status, text) to authenticated;
grant execute on function public.admin_update_order_status(uuid, public.order_status) to authenticated;
