-- Farmora PostgreSQL schema (PostgreSQL 15+)
-- Money is stored in paise (BIGINT). Timestamps are TIMESTAMPTZ (UTC).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";            -- pgvector, for AI assistant RAG

-- =========================================================
-- ENUMS
-- =========================================================
CREATE TYPE user_role          AS ENUM ('FARMER', 'CUSTOMER', 'ADMIN', 'EXPERT', 'SERVICE_PROVIDER');
CREATE TYPE user_status        AS ENUM ('ACTIVE', 'PENDING_VERIFICATION', 'SUSPENDED');
CREATE TYPE locale_code        AS ENUM ('en', 'te', 'ta', 'hi');
CREATE TYPE auth_provider      AS ENUM ('PASSWORD', 'GOOGLE', 'OTP');
CREATE TYPE crop_status        AS ENUM ('PLANNED', 'SOWN', 'GROWING', 'HARVESTED', 'FAILED');
CREATE TYPE schedule_type      AS ENUM ('FERTILIZER', 'IRRIGATION', 'PESTICIDE', 'WEEDING', 'OTHER');
CREATE TYPE schedule_status    AS ENUM ('PENDING', 'DONE', 'SKIPPED');
CREATE TYPE health_status      AS ENUM ('HEALTHY', 'AT_RISK', 'DISEASED');
CREATE TYPE expense_category   AS ENUM ('SEEDS', 'FERTILIZER', 'PESTICIDE', 'LABOUR', 'IRRIGATION', 'EQUIPMENT', 'TRANSPORT', 'OTHER');
CREATE TYPE product_status     AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'ACTIVE', 'INACTIVE', 'REJECTED');
CREATE TYPE stock_move_type    AS ENUM ('RESTOCK', 'SALE', 'RESERVE', 'RELEASE', 'ADJUSTMENT', 'RETURN');
CREATE TYPE order_status       AS ENUM ('PENDING_PAYMENT', 'CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED', 'EXPIRED');
CREATE TYPE payment_status     AS ENUM ('CREATED', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED', 'PARTIALLY_REFUNDED');
CREATE TYPE payment_method     AS ENUM ('UPI', 'CARD', 'NETBANKING', 'WALLET', 'COD');
CREATE TYPE discount_type      AS ENUM ('PERCENT', 'FLAT');
CREATE TYPE sub_frequency      AS ENUM ('WEEKLY', 'BIWEEKLY', 'MONTHLY');
CREATE TYPE sub_status         AS ENUM ('ACTIVE', 'PAUSED', 'CANCELLED', 'HALTED');
CREATE TYPE notif_channel      AS ENUM ('PUSH', 'SMS', 'WHATSAPP', 'IN_APP', 'EMAIL');
CREATE TYPE notif_status       AS ENUM ('QUEUED', 'SENT', 'DELIVERED', 'FAILED', 'READ');
-- Expansion (docs/09)
CREATE TYPE license_type       AS ENUM ('SEED', 'FERTILIZER', 'PESTICIDE', 'DRONE_PILOT', 'INSURANCE_AGENT');
CREATE TYPE service_type       AS ENUM ('EQUIPMENT', 'DRONE', 'SOIL_TEST', 'CONSULTANCY');
CREATE TYPE booking_status     AS ENUM ('REQUESTED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'DISPUTED');
-- Community (docs/10)
CREATE TYPE post_type          AS ENUM ('POST', 'STORY', 'CROP_UPDATE', 'QUESTION', 'RECIPE', 'THANK_YOU', 'POLL', 'SUCCESS_STORY', 'LIVE', 'SEED_SWAP', 'LABOUR_SHARE');
CREATE TYPE post_visibility    AS ENUM ('PUBLIC', 'FOLLOWERS', 'CIRCLE', 'PRIVATE');
CREATE TYPE mod_status         AS ENUM ('PENDING', 'APPROVED', 'FLAGGED', 'REMOVED');
CREATE TYPE reaction_type      AS ENUM ('LIKE', 'LOVE', 'HELPFUL', 'THANKS');

-- =========================================================
-- USERS & AUTH
-- =========================================================
CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role              user_role   NOT NULL,
    status            user_status NOT NULL DEFAULT 'ACTIVE',
    full_name         VARCHAR(120) NOT NULL,
    email             VARCHAR(255) UNIQUE,
    phone             VARCHAR(15)  UNIQUE,          -- E.164, e.g. +919876543210
    password_hash     VARCHAR(255),                 -- bcrypt; NULL for OTP/Google-only users
    google_id         VARCHAR(64)  UNIQUE,
    avatar_url        TEXT,
    preferred_locale  locale_code NOT NULL DEFAULT 'en',
    email_verified_at TIMESTAMPTZ,
    phone_verified_at TIMESTAMPTZ,
    last_login_at     TIMESTAMPTZ,
    referred_by       UUID REFERENCES users(id),
    signup_utm        JSONB,                        -- {source, medium, campaign} for marketing attribution
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    CONSTRAINT users_contact_chk CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE refresh_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   VARCHAR(128) NOT NULL UNIQUE,   -- SHA-256 of token
    device_info  VARCHAR(255),
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);

CREATE TABLE otp_codes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(15) NOT NULL,
    code_hash   VARCHAR(128) NOT NULL,
    purpose     VARCHAR(20) NOT NULL DEFAULT 'LOGIN',
    attempts    SMALLINT NOT NULL DEFAULT 0,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_phone ON otp_codes(phone, created_at DESC);

CREATE TABLE device_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fcm_token   TEXT NOT NULL UNIQUE,
    platform    VARCHAR(10) NOT NULL,             -- ios | android | web
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notification_preferences (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    push_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
    sms_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    whatsapp_enabled BOOLEAN NOT NULL DEFAULT FALSE,  -- requires explicit opt-in
    email_enabled   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE addresses (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label         VARCHAR(30),
    recipient     VARCHAR(120) NOT NULL,
    phone         VARCHAR(15) NOT NULL,
    line1         VARCHAR(255) NOT NULL,
    line2         VARCHAR(255),
    city          VARCHAR(80) NOT NULL,
    district      VARCHAR(80),
    state         VARCHAR(80) NOT NULL,
    pincode       CHAR(6) NOT NULL,
    location      GEOGRAPHY(POINT, 4326),
    is_default    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_addresses_user ON addresses(user_id);

-- =========================================================
-- FARMER PROFILE & FARMS
-- =========================================================
CREATE TABLE farmer_profiles (
    user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    farm_name        VARCHAR(150) NOT NULL,
    bio              TEXT,
    experience_years SMALLINT,
    is_organic_certified BOOLEAN NOT NULL DEFAULT FALSE,
    certification_doc_url TEXT,
    kyc_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    pan_number       VARCHAR(10),
    gstin            VARCHAR(15),
    bank_account_ref VARCHAR(64),     -- Razorpay Route linked account id; never raw bank details
    rating_avg       NUMERIC(3,2) NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE farms (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name          VARCHAR(120) NOT NULL,
    area_acres    NUMERIC(10,2) NOT NULL CHECK (area_acres > 0),
    soil_type     VARCHAR(50),
    water_source  VARCHAR(50),
    village       VARCHAR(80),
    district      VARCHAR(80),
    state         VARCHAR(80),
    pincode       CHAR(6),
    location      GEOGRAPHY(POINT, 4326),
    boundary      GEOGRAPHY(POLYGON, 4326),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);
CREATE INDEX idx_farms_farmer   ON farms(farmer_id);
CREATE INDEX idx_farms_location ON farms USING GIST(location);

-- =========================================================
-- CROPS
-- =========================================================
CREATE TABLE crop_types (                       -- master data (admin managed)
    id                 SERIAL PRIMARY KEY,
    code               VARCHAR(40) NOT NULL UNIQUE,   -- e.g. PADDY, GROUNDNUT
    name               VARCHAR(80) NOT NULL,
    avg_duration_days  SMALLINT,
    avg_yield_per_acre_kg NUMERIC(10,2),
    default_schedule   JSONB                         -- template of fertilizer/irrigation tasks by day offset
);

CREATE TABLE crop_type_translations (
    crop_type_id  INT NOT NULL REFERENCES crop_types(id) ON DELETE CASCADE,
    locale        locale_code NOT NULL,
    name          VARCHAR(80) NOT NULL,
    PRIMARY KEY (crop_type_id, locale)
);

CREATE TABLE crops (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id               UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    crop_type_id          INT  NOT NULL REFERENCES crop_types(id),
    variety               VARCHAR(80),
    season                VARCHAR(20),               -- KHARIF | RABI | ZAID
    area_acres            NUMERIC(10,2) NOT NULL CHECK (area_acres > 0),
    status                crop_status NOT NULL DEFAULT 'PLANNED',
    sowing_date           DATE,
    expected_harvest_date DATE,
    actual_harvest_date   DATE,
    estimated_yield_kg    NUMERIC(12,2),
    actual_yield_kg       NUMERIC(12,2),
    notes                 TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT crops_dates_chk CHECK (expected_harvest_date IS NULL OR sowing_date IS NULL OR expected_harvest_date >= sowing_date)
);
CREATE INDEX idx_crops_farm   ON crops(farm_id);
CREATE INDEX idx_crops_status ON crops(status);

CREATE TABLE crop_images (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crop_id     UUID NOT NULL REFERENCES crops(id) ON DELETE CASCADE,
    s3_key      TEXT NOT NULL,
    caption     VARCHAR(255),
    taken_at    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_crop_images_crop ON crop_images(crop_id);

CREATE TABLE crop_schedules (                   -- fertilizer / irrigation / other reminders
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crop_id        UUID NOT NULL REFERENCES crops(id) ON DELETE CASCADE,
    type           schedule_type NOT NULL,
    title          VARCHAR(150) NOT NULL,
    details        JSONB,                          -- e.g. {"fertilizer":"Urea","qty_kg":50} or {"duration_min":60,"method":"drip"}
    scheduled_at   TIMESTAMPTZ NOT NULL,
    recurrence     VARCHAR(100),                   -- RFC 5545 RRULE, optional
    status         schedule_status NOT NULL DEFAULT 'PENDING',
    completed_at   TIMESTAMPTZ,
    reminder_sent_at TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_schedules_due ON crop_schedules(scheduled_at) WHERE status = 'PENDING' AND reminder_sent_at IS NULL;

CREATE TABLE crop_health_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crop_id        UUID NOT NULL REFERENCES crops(id) ON DELETE CASCADE,
    image_s3_key   TEXT,
    status         health_status NOT NULL,
    disease_code   VARCHAR(60),
    confidence     NUMERIC(4,3),                   -- 0.000 - 1.000
    ai_predictions JSONB,                          -- top-k raw predictions
    recommendation TEXT,
    source         VARCHAR(10) NOT NULL DEFAULT 'AI', -- AI | MANUAL | EXPERT
    observed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_health_crop ON crop_health_logs(crop_id, observed_at DESC);

CREATE TABLE farm_expenses (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id      UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    crop_id      UUID REFERENCES crops(id) ON DELETE SET NULL,
    category     expense_category NOT NULL,
    amount_paise BIGINT NOT NULL CHECK (amount_paise > 0),
    description  VARCHAR(255),
    receipt_s3_key TEXT,
    spent_on     DATE NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_expenses_farm ON farm_expenses(farm_id, spent_on DESC);

-- =========================================================
-- CATALOG & INVENTORY
-- =========================================================
CREATE TABLE categories (
    id          SERIAL PRIMARY KEY,
    parent_id   INT REFERENCES categories(id),
    slug        VARCHAR(60) NOT NULL UNIQUE,      -- honey, ghee, oils, millets, pulses, spices
    image_url   TEXT,
    sort_order  SMALLINT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE category_translations (
    category_id INT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    locale      locale_code NOT NULL,
    name        VARCHAR(80) NOT NULL,
    PRIMARY KEY (category_id, locale)
);

CREATE TABLE products (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id     UUID NOT NULL REFERENCES users(id),
    category_id   INT  NOT NULL REFERENCES categories(id),
    slug          VARCHAR(160) NOT NULL UNIQUE,
    name          VARCHAR(150) NOT NULL,
    description   TEXT,
    status        product_status NOT NULL DEFAULT 'PENDING_APPROVAL',
    is_organic    BOOLEAN NOT NULL DEFAULT FALSE,
    origin_farm_id UUID REFERENCES farms(id) ON DELETE SET NULL,
    hsn_code      VARCHAR(10),
    gst_rate      NUMERIC(4,2) NOT NULL DEFAULT 0,
    is_subscribable BOOLEAN NOT NULL DEFAULT FALSE,
    rating_avg    NUMERIC(3,2) NOT NULL DEFAULT 0,
    rating_count  INT NOT NULL DEFAULT 0,
    search_vector TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(description, '')), 'B')
    ) STORED,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);
CREATE INDEX idx_products_category ON products(category_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_products_farmer   ON products(farmer_id);
CREATE INDEX idx_products_search   ON products USING GIN(search_vector);
CREATE INDEX idx_products_name_trgm ON products USING GIN(name gin_trgm_ops);

CREATE TABLE product_translations (
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    locale      locale_code NOT NULL,
    name        VARCHAR(150) NOT NULL,
    description TEXT,
    PRIMARY KEY (product_id, locale)
);

CREATE TABLE product_variants (                 -- e.g. Honey 250g / 500g / 1kg
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku              VARCHAR(60) NOT NULL UNIQUE,
    label            VARCHAR(60) NOT NULL,          -- "500 g"
    weight_grams     INT,
    mrp_paise        BIGINT NOT NULL CHECK (mrp_paise > 0),
    price_paise      BIGINT NOT NULL CHECK (price_paise > 0),
    subscription_price_paise BIGINT,
    stock_qty        INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    reserved_qty     INT NOT NULL DEFAULT 0 CHECK (reserved_qty >= 0),
    low_stock_threshold INT NOT NULL DEFAULT 10,
    lot_number       VARCHAR(40),                   -- seed/fertilizer traceability
    manufactured_on  DATE,
    expires_on       DATE,
    required_license license_type,                  -- seller must hold this verified licence
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT price_le_mrp CHECK (price_paise <= mrp_paise),
    CONSTRAINT reserved_le_stock CHECK (reserved_qty <= stock_qty)
);
CREATE INDEX idx_variants_product ON product_variants(product_id);

CREATE TABLE product_images (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    s3_key      TEXT NOT NULL,
    alt_text    VARCHAR(150),
    sort_order  SMALLINT NOT NULL DEFAULT 0
);
CREATE INDEX idx_product_images_product ON product_images(product_id);

CREATE TABLE price_history (
    id           BIGSERIAL PRIMARY KEY,
    variant_id   UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    old_price_paise BIGINT,
    new_price_paise BIGINT NOT NULL,
    changed_by   UUID REFERENCES users(id),
    changed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stock_movements (
    id           BIGSERIAL PRIMARY KEY,
    variant_id   UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    type         stock_move_type NOT NULL,
    quantity     INT NOT NULL,                    -- signed
    reference_id UUID,                            -- order_id etc.
    note         VARCHAR(255),
    created_by   UUID REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_stock_moves_variant ON stock_movements(variant_id, created_at DESC);

-- =========================================================
-- CART & WISHLIST
-- =========================================================
CREATE TABLE cart_items (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    variant_id  UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity    INT NOT NULL CHECK (quantity > 0 AND quantity <= 50),
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, variant_id)
);

CREATE TABLE wishlist_items (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);

-- =========================================================
-- COUPONS
-- =========================================================
CREATE TABLE coupons (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code               VARCHAR(30) NOT NULL UNIQUE,
    description        VARCHAR(255),
    discount_type      discount_type NOT NULL,
    discount_value     BIGINT NOT NULL CHECK (discount_value > 0),  -- percent (1-100) or paise
    max_discount_paise BIGINT,
    min_order_paise    BIGINT NOT NULL DEFAULT 0,
    usage_limit        INT,
    per_user_limit     INT NOT NULL DEFAULT 1,
    used_count         INT NOT NULL DEFAULT 0,
    category_id        INT REFERENCES categories(id),
    farmer_id          UUID REFERENCES users(id),     -- farmer-specific coupon
    first_order_only   BOOLEAN NOT NULL DEFAULT FALSE,
    starts_at          TIMESTAMPTZ NOT NULL,
    ends_at            TIMESTAMPTZ NOT NULL,
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT coupon_window CHECK (ends_at > starts_at),
    CONSTRAINT coupon_percent CHECK (discount_type <> 'PERCENT' OR discount_value <= 100)
);

-- =========================================================
-- ORDERS & PAYMENTS
-- =========================================================
CREATE SEQUENCE order_number_seq START 100000;

CREATE TABLE orders (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number      VARCHAR(20) NOT NULL UNIQUE DEFAULT ('FRM' || nextval('order_number_seq')),
    customer_id       UUID NOT NULL REFERENCES users(id),
    subscription_id   UUID,                        -- FK added below
    status            order_status NOT NULL DEFAULT 'PENDING_PAYMENT',
    shipping_address  JSONB NOT NULL,              -- snapshot at order time
    subtotal_paise    BIGINT NOT NULL,
    discount_paise    BIGINT NOT NULL DEFAULT 0,
    shipping_paise    BIGINT NOT NULL DEFAULT 0,
    tax_paise         BIGINT NOT NULL DEFAULT 0,
    total_paise       BIGINT NOT NULL CHECK (total_paise >= 0),
    coupon_id         UUID REFERENCES coupons(id),
    wallet_paise      BIGINT NOT NULL DEFAULT 0,   -- referral/wallet credits applied
    gift_card_paise   BIGINT NOT NULL DEFAULT 0,
    utm               JSONB,
    idempotency_key   VARCHAR(64) UNIQUE,
    payment_expires_at TIMESTAMPTZ,
    placed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    delivered_at      TIMESTAMPTZ,
    cancelled_at      TIMESTAMPTZ,
    cancel_reason     VARCHAR(255),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_customer ON orders(customer_id, placed_at DESC);
CREATE INDEX idx_orders_status   ON orders(status);

CREATE TABLE order_items (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id        UUID NOT NULL REFERENCES product_variants(id),
    farmer_id         UUID NOT NULL REFERENCES users(id),
    product_name      VARCHAR(150) NOT NULL,       -- snapshot
    variant_label     VARCHAR(60)  NOT NULL,
    unit_price_paise  BIGINT NOT NULL,
    quantity          INT NOT NULL CHECK (quantity > 0),
    tax_paise         BIGINT NOT NULL DEFAULT 0,
    line_total_paise  BIGINT NOT NULL,
    fulfillment_status order_status NOT NULL DEFAULT 'CONFIRMED'
);
CREATE INDEX idx_order_items_order  ON order_items(order_id);
CREATE INDEX idx_order_items_farmer ON order_items(farmer_id);

CREATE TABLE order_status_history (
    id          BIGSERIAL PRIMARY KEY,
    order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status      order_status NOT NULL,
    note        VARCHAR(255),
    changed_by  UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_order_history_order ON order_status_history(order_id, created_at);

CREATE TABLE shipments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    courier         VARCHAR(60),
    tracking_number VARCHAR(80),
    tracking_url    TEXT,
    shipped_at      TIMESTAMPTZ,
    estimated_delivery DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE coupon_redemptions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coupon_id   UUID NOT NULL REFERENCES coupons(id),
    user_id     UUID NOT NULL REFERENCES users(id),
    order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    discount_paise BIGINT NOT NULL,
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (coupon_id, order_id)
);
CREATE INDEX idx_coupon_redemptions_user ON coupon_redemptions(coupon_id, user_id);

CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            UUID REFERENCES orders(id),
    subscription_id     UUID,
    razorpay_order_id   VARCHAR(40) UNIQUE,
    razorpay_payment_id VARCHAR(40) UNIQUE,
    method              payment_method,
    status              payment_status NOT NULL DEFAULT 'CREATED',
    amount_paise        BIGINT NOT NULL CHECK (amount_paise > 0),
    currency            CHAR(3) NOT NULL DEFAULT 'INR',
    failure_reason      VARCHAR(255),
    refunded_paise      BIGINT NOT NULL DEFAULT 0,
    raw_response        JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_order ON payments(order_id);

CREATE TABLE payment_webhook_events (            -- idempotent webhook processing
    event_id     VARCHAR(64) PRIMARY KEY,
    event_type   VARCHAR(60) NOT NULL,
    payload      JSONB NOT NULL,
    processed_at TIMESTAMPTZ,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE farmer_payouts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id      UUID NOT NULL REFERENCES users(id),
    period_start   DATE NOT NULL,
    period_end     DATE NOT NULL,
    gross_paise    BIGINT NOT NULL,
    commission_paise BIGINT NOT NULL,
    net_paise      BIGINT NOT NULL,
    razorpay_transfer_id VARCHAR(40),
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- SUBSCRIPTIONS
-- =========================================================
CREATE TABLE subscriptions (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id              UUID NOT NULL REFERENCES users(id),
    address_id               UUID NOT NULL REFERENCES addresses(id),
    frequency                sub_frequency NOT NULL,
    status                   sub_status NOT NULL DEFAULT 'ACTIVE',
    razorpay_subscription_id VARCHAR(40) UNIQUE,
    amount_paise             BIGINT NOT NULL,
    next_delivery_date       DATE NOT NULL,
    paused_until             DATE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    cancelled_at             TIMESTAMPTZ
);
CREATE INDEX idx_subscriptions_next ON subscriptions(next_delivery_date) WHERE status = 'ACTIVE';

CREATE TABLE subscription_items (
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    variant_id      UUID NOT NULL REFERENCES product_variants(id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (subscription_id, variant_id)
);

ALTER TABLE orders   ADD CONSTRAINT fk_orders_subscription   FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);
ALTER TABLE payments ADD CONSTRAINT fk_payments_subscription FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);

-- =========================================================
-- REVIEWS
-- =========================================================
CREATE TABLE reviews (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id    UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(id),   -- verified purchase
    rating        SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title         VARCHAR(120),
    body          TEXT,
    images        TEXT[],
    is_approved   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, user_id)
);
CREATE INDEX idx_reviews_product ON reviews(product_id, created_at DESC);

-- =========================================================
-- NOTIFICATIONS
-- =========================================================
CREATE TABLE notification_templates (
    code      VARCHAR(60) NOT NULL,              -- ORDER_CONFIRMED, IRRIGATION_REMINDER ...
    channel   notif_channel NOT NULL,
    locale    locale_code NOT NULL,
    subject   VARCHAR(150),
    body      TEXT NOT NULL,                     -- {{placeholders}}
    provider_template_id VARCHAR(80),            -- DLT (SMS) / WhatsApp approved template
    PRIMARY KEY (code, channel, locale)
);

CREATE TABLE notifications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel      notif_channel NOT NULL,
    template_code VARCHAR(60),
    title        VARCHAR(150),
    body         TEXT NOT NULL,
    data         JSONB,                          -- deep-link payload
    status       notif_status NOT NULL DEFAULT 'QUEUED',
    provider_msg_id VARCHAR(100),
    error        VARCHAR(255),
    sent_at      TIMESTAMPTZ,
    read_at      TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);

-- =========================================================
-- WEATHER & MARKET
-- =========================================================
CREATE TABLE weather_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    farm_id      UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    forecast_for DATE NOT NULL,
    temp_min_c   NUMERIC(4,1),
    temp_max_c   NUMERIC(4,1),
    humidity_pct SMALLINT,
    rain_mm      NUMERIC(6,2),
    wind_kph     NUMERIC(5,1),
    condition    VARCHAR(60),
    raw          JSONB,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (farm_id, forecast_for)
);

CREATE TABLE market_prices (
    id             BIGSERIAL PRIMARY KEY,
    commodity      VARCHAR(80) NOT NULL,
    variety        VARCHAR(80),
    market         VARCHAR(120) NOT NULL,
    district       VARCHAR(80),
    state          VARCHAR(80) NOT NULL,
    min_price_per_qtl  NUMERIC(10,2),
    max_price_per_qtl  NUMERIC(10,2),
    modal_price_per_qtl NUMERIC(10,2),
    price_date     DATE NOT NULL,
    source         VARCHAR(40) NOT NULL DEFAULT 'AGMARKNET',
    UNIQUE (commodity, variety, market, price_date)
);
CREATE INDEX idx_market_prices_lookup ON market_prices(commodity, state, price_date DESC);

-- =========================================================
-- ADMIN / AUDIT
-- =========================================================
CREATE TABLE audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    actor_id    UUID REFERENCES users(id),
    action      VARCHAR(60) NOT NULL,           -- PRODUCT_APPROVED, USER_SUSPENDED ...
    entity_type VARCHAR(40) NOT NULL,
    entity_id   VARCHAR(64),
    changes     JSONB,
    ip_address  INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

-- =========================================================
-- REPORTING VIEWS
-- =========================================================
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT date_trunc('day', o.placed_at)::date AS day,
       oi.farmer_id,
       p.category_id,
       COUNT(DISTINCT o.id)        AS orders,
       SUM(oi.quantity)            AS units,
       SUM(oi.line_total_paise)    AS revenue_paise
FROM orders o
JOIN order_items oi     ON oi.order_id = o.id
JOIN product_variants v ON v.id = oi.variant_id
JOIN products p         ON p.id = v.product_id
WHERE o.status NOT IN ('PENDING_PAYMENT', 'CANCELLED', 'EXPIRED')
GROUP BY 1, 2, 3;
CREATE UNIQUE INDEX idx_mv_daily_sales ON mv_daily_sales(day, farmer_id, category_id);

CREATE VIEW v_inventory_status AS
SELECT v.id AS variant_id, v.sku, p.name AS product_name, p.farmer_id, p.category_id,
       v.stock_qty, v.reserved_qty, (v.stock_qty - v.reserved_qty) AS available_qty,
       v.low_stock_threshold,
       (v.stock_qty - v.reserved_qty) <= v.low_stock_threshold AS is_low_stock
FROM product_variants v
JOIN products p ON p.id = v.product_id
WHERE p.deleted_at IS NULL;

-- =========================================================
-- SEED: categories
-- =========================================================
INSERT INTO categories (slug, sort_order) VALUES
 ('honey', 1), ('ghee', 2), ('oils', 3), ('millets', 4), ('pulses', 5), ('spices', 6);

INSERT INTO category_translations (category_id, locale, name)
SELECT c.id, t.locale::locale_code, t.name
FROM categories c
JOIN (VALUES
 ('honey','en','Honey'),   ('honey','te','తేనె'),        ('honey','ta','தேன்'),          ('honey','hi','शहद'),
 ('ghee','en','Ghee'),     ('ghee','te','నెయ్యి'),       ('ghee','ta','நெய்'),           ('ghee','hi','घी'),
 ('oils','en','Oils'),     ('oils','te','నూనెలు'),       ('oils','ta','எண்ணெய்கள்'),     ('oils','hi','तेल'),
 ('millets','en','Millets'),('millets','te','చిరుధాన్యాలు'),('millets','ta','சிறுதானியங்கள்'),('millets','hi','मोटा अनाज'),
 ('pulses','en','Pulses'), ('pulses','te','పప్పులు'),     ('pulses','ta','பருப்பு வகைகள்'), ('pulses','hi','दालें'),
 ('spices','en','Spices'), ('spices','te','సుగంధ ద్రవ్యాలు'),('spices','ta','மசாலா பொருட்கள்'),('spices','hi','मसाले')
) AS t(slug, locale, name) ON t.slug = c.slug;

-- =========================================================
-- MARKETING: waitlist, referrals, wallet, gift cards (docs/08)
-- =========================================================
CREATE TABLE waitlist_signups (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         VARCHAR(15),
    email         VARCHAR(255),
    role          user_role NOT NULL,
    locale        locale_code NOT NULL DEFAULT 'en',
    district      VARCHAR(80),
    referral_code VARCHAR(20),
    utm           JSONB,
    converted_user_id UUID REFERENCES users(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (phone IS NOT NULL OR email IS NOT NULL)
);
CREATE UNIQUE INDEX idx_waitlist_phone ON waitlist_signups(phone) WHERE phone IS NOT NULL;

CREATE TABLE referral_codes (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code       VARCHAR(20) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE referrals (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id    UUID NOT NULL REFERENCES users(id),
    referee_id     UUID NOT NULL UNIQUE REFERENCES users(id),
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',   -- PENDING | QUALIFIED | REWARDED | REJECTED
    qualifying_order_id UUID REFERENCES orders(id),
    reward_paise   BIGINT NOT NULL DEFAULT 0,
    rewarded_at    TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (referrer_id <> referee_id)
);

CREATE TABLE wallet_transactions (                -- balance = SUM(amount_paise)
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_paise BIGINT NOT NULL,                -- +credit / -debit
    reason       VARCHAR(30) NOT NULL,           -- REFERRAL | REFUND | ORDER | PROMO | HARVEST_POINTS | EXPIRY
    ref_id       UUID,
    expires_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_user ON wallet_transactions(user_id, created_at DESC);

CREATE TABLE gift_cards (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code_hash      VARCHAR(128) NOT NULL UNIQUE,
    purchaser_id   UUID REFERENCES users(id),
    recipient_email VARCHAR(255),
    recipient_phone VARCHAR(15),
    initial_paise  BIGINT NOT NULL CHECK (initial_paise > 0),
    balance_paise  BIGINT NOT NULL CHECK (balance_paise >= 0),
    payment_id     UUID REFERENCES payments(id),
    expires_at     TIMESTAMPTZ NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (balance_paise <= initial_paise)
);

-- =========================================================
-- EXPANSION: licences, B2B, bookings, soil, insurance/loans, AI (docs/09)
-- =========================================================
CREATE TABLE seller_licenses (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES users(id),
    type              license_type NOT NULL,
    license_number    VARCHAR(60) NOT NULL,
    issuing_authority VARCHAR(120),
    document_s3_key   TEXT NOT NULL,
    valid_until       DATE NOT NULL,
    verified_by       UUID REFERENCES users(id),
    verified_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (type, license_number)
);
CREATE INDEX idx_seller_licenses_user ON seller_licenses(user_id);

CREATE TABLE b2b_listings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id           UUID NOT NULL REFERENCES users(id),
    crop_id             UUID REFERENCES crops(id) ON DELETE SET NULL,
    commodity           VARCHAR(80) NOT NULL,
    description         TEXT,
    quantity_kg         NUMERIC(12,2) NOT NULL CHECK (quantity_kg > 0),
    min_order_kg        NUMERIC(12,2) NOT NULL CHECK (min_order_kg > 0),
    price_per_qtl_paise BIGINT NOT NULL CHECK (price_per_qtl_paise > 0),
    negotiable          BOOLEAN NOT NULL DEFAULT TRUE,
    location            GEOGRAPHY(POINT, 4326),
    status              VARCHAR(20) NOT NULL DEFAULT 'OPEN',   -- OPEN | RESERVED | SOLD | CLOSED
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_b2b_listings_geo ON b2b_listings USING GIST(location);
CREATE INDEX idx_b2b_listings_commodity ON b2b_listings(commodity) WHERE status = 'OPEN';

CREATE TABLE b2b_offers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id          UUID NOT NULL REFERENCES b2b_listings(id) ON DELETE CASCADE,
    buyer_id            UUID NOT NULL REFERENCES users(id),
    quantity_kg         NUMERIC(12,2) NOT NULL CHECK (quantity_kg > 0),
    price_per_qtl_paise BIGINT NOT NULL CHECK (price_per_qtl_paise > 0),
    status              VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING | COUNTERED | ACCEPTED | REJECTED
    parent_offer_id     UUID REFERENCES b2b_offers(id),
    order_id            UUID REFERENCES orders(id),            -- escrow order once accepted
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_b2b_offers_listing ON b2b_offers(listing_id);

CREATE TABLE service_listings (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id       UUID NOT NULL REFERENCES users(id),
    type              service_type NOT NULL,
    title             VARCHAR(150) NOT NULL,
    details           JSONB,                     -- equipment HP, drone capacity, lab tests, expert specialisation
    price_unit        VARCHAR(20) NOT NULL,      -- HOUR | DAY | ACRE | TEST | SESSION
    price_paise       BIGINT NOT NULL CHECK (price_paise > 0),
    deposit_paise     BIGINT NOT NULL DEFAULT 0,
    service_radius_km SMALLINT,
    location          GEOGRAPHY(POINT, 4326),
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_service_listings_geo ON service_listings USING GIST(location);
CREATE INDEX idx_service_listings_type ON service_listings(type) WHERE is_active;

CREATE TABLE bookings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id    UUID NOT NULL REFERENCES service_listings(id),
    farmer_id     UUID NOT NULL REFERENCES users(id),
    farm_id       UUID REFERENCES farms(id),
    crop_id       UUID REFERENCES crops(id),
    slot_start    TIMESTAMPTZ NOT NULL,
    slot_end      TIMESTAMPTZ NOT NULL,
    quantity      NUMERIC(10,2) NOT NULL CHECK (quantity > 0),   -- hours/days/acres/tests
    total_paise   BIGINT NOT NULL,
    status        booking_status NOT NULL DEFAULT 'REQUESTED',
    report        JSONB,                                          -- spray log, consult notes
    report_s3_key TEXT,
    payment_id    UUID REFERENCES payments(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (slot_end > slot_start)
);
CREATE INDEX idx_bookings_service_slot ON bookings(service_id, slot_start);
CREATE INDEX idx_bookings_farmer ON bookings(farmer_id, created_at DESC);

CREATE TABLE soil_tests (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id     UUID REFERENCES bookings(id),
    farm_id        UUID NOT NULL REFERENCES farms(id) ON DELETE CASCADE,
    ph             NUMERIC(4,2),
    ec             NUMERIC(6,3),
    organic_carbon NUMERIC(5,2),
    n_kg_ha        NUMERIC(8,2),
    p_kg_ha        NUMERIC(8,2),
    k_kg_ha        NUMERIC(8,2),
    micronutrients JSONB,                         -- S, Zn, Fe, Cu, Mn, B
    report_s3_key  TEXT,
    tested_on      DATE NOT NULL
);
CREATE INDEX idx_soil_tests_farm ON soil_tests(farm_id, tested_on DESC);

CREATE TABLE user_consents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    purpose     VARCHAR(60) NOT NULL,             -- LOAN_DATA_SHARE | INSURANCE_DATA_SHARE | MARKETING_WHATSAPP
    partner     VARCHAR(80),
    data_scope  TEXT[] NOT NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at  TIMESTAMPTZ
);
CREATE INDEX idx_user_consents_user ON user_consents(user_id);

CREATE TABLE partner_applications (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id),
    kind         VARCHAR(20) NOT NULL,            -- INSURANCE | LOAN
    partner      VARCHAR(80) NOT NULL,
    product_code VARCHAR(60),
    crop_id      UUID REFERENCES crops(id),
    consent_id   UUID NOT NULL REFERENCES user_consents(id),
    external_ref VARCHAR(80),
    status       VARCHAR(30) NOT NULL,
    amount_paise BIGINT,
    payload      JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_partner_apps_user ON partner_applications(user_id);

CREATE TABLE knowledge_chunks (
    id         BIGSERIAL PRIMARY KEY,
    source     VARCHAR(120) NOT NULL,
    locale     locale_code NOT NULL,
    content    TEXT NOT NULL,
    embedding  VECTOR(1024)
);
CREATE INDEX idx_knowledge_embedding ON knowledge_chunks USING hnsw (embedding vector_cosine_ops);

CREATE TABLE assistant_messages (
    id         BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       VARCHAR(10) NOT NULL,              -- user | assistant | tool
    content    TEXT NOT NULL,
    tool_calls JSONB,
    feedback   SMALLINT CHECK (feedback IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_assistant_session ON assistant_messages(session_id, id);

-- =========================================================
-- COMMUNITY: social network (docs/10)
-- =========================================================
CREATE TABLE follows (
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);
CREATE INDEX idx_follows_followee ON follows(followee_id);

CREATE TABLE circles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            VARCHAR(80) NOT NULL UNIQUE,
    name            VARCHAR(120) NOT NULL,
    kind            VARCHAR(20) NOT NULL,         -- CROP | DISTRICT | LANGUAGE | INTEREST
    crop_type_id    INT REFERENCES crop_types(id),
    district        VARCHAR(80),
    locale          locale_code,
    is_farmers_only BOOLEAN NOT NULL DEFAULT TRUE,
    member_count    INT NOT NULL DEFAULT 0,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE circle_members (
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      VARCHAR(10) NOT NULL DEFAULT 'MEMBER',   -- MEMBER | MOD | ADMIN
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id)
);
CREATE INDEX idx_circle_members_user ON circle_members(user_id);

CREATE TABLE posts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type                post_type NOT NULL DEFAULT 'POST',
    visibility          post_visibility NOT NULL DEFAULT 'PUBLIC',
    circle_id           UUID REFERENCES circles(id) ON DELETE CASCADE,
    body                TEXT,
    original_locale     locale_code NOT NULL,
    voice_s3_key        TEXT,
    transcript          TEXT,
    crop_id             UUID REFERENCES crops(id) ON DELETE SET NULL,
    product_ids         UUID[],                   -- shoppable tags
    farm_location       GEOGRAPHY(POINT, 4326),   -- coarse (village-level) only
    metadata            JSONB,                    -- poll options, recipe steps, labour needs
    is_draft            BOOLEAN NOT NULL DEFAULT FALSE,   -- auto-generated Harvest Journal drafts
    moderation          mod_status NOT NULL DEFAULT 'PENDING',
    needs_expert_review BOOLEAN NOT NULL DEFAULT FALSE,
    is_expert_verified  BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_answer_id  UUID,
    reaction_count      INT NOT NULL DEFAULT 0,
    comment_count       INT NOT NULL DEFAULT 0,
    expires_at          TIMESTAMPTZ,              -- stories
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX idx_posts_author ON posts(author_id, created_at DESC);
CREATE INDEX idx_posts_circle ON posts(circle_id, created_at DESC) WHERE circle_id IS NOT NULL;
CREATE INDEX idx_posts_geo    ON posts USING GIST(farm_location);
CREATE INDEX idx_posts_review ON posts(created_at) WHERE moderation IN ('PENDING', 'FLAGGED') OR needs_expert_review;

CREATE TABLE post_media (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id      UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    kind         VARCHAR(10) NOT NULL,            -- IMAGE | VIDEO
    s3_key       TEXT NOT NULL,
    hls_url      TEXT,
    width        INT,
    height       INT,
    duration_sec INT,
    sort_order   SMALLINT NOT NULL DEFAULT 0
);
CREATE INDEX idx_post_media_post ON post_media(post_id);

CREATE TABLE post_translations (
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    locale  locale_code NOT NULL,
    body    TEXT NOT NULL,
    PRIMARY KEY (post_id, locale)
);

CREATE TABLE comments (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id            UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id          UUID REFERENCES comments(id) ON DELETE CASCADE,
    body               TEXT,
    voice_s3_key       TEXT,
    is_expert_verified BOOLEAN NOT NULL DEFAULT FALSE,
    helpful_count      INT NOT NULL DEFAULT 0,
    moderation         mod_status NOT NULL DEFAULT 'PENDING',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ,
    CHECK (body IS NOT NULL OR voice_s3_key IS NOT NULL)
);
CREATE INDEX idx_comments_post ON comments(post_id, created_at);

ALTER TABLE posts ADD CONSTRAINT fk_posts_accepted_answer
    FOREIGN KEY (accepted_answer_id) REFERENCES comments(id) ON DELETE SET NULL;

CREATE TABLE reactions (
    post_id    UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type       reaction_type NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE poll_votes (
    post_id       UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    option_idx    SMALLINT NOT NULL,
    pledge_qty_kg NUMERIC(8,2),                   -- demand poll pre-commitment
    PRIMARY KEY (post_id, user_id)
);

CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    is_group        BOOLEAN NOT NULL DEFAULT FALSE,
    title           VARCHAR(120),
    last_message_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at    TIMESTAMPTZ,
    muted           BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX idx_conversation_members_user ON conversation_members(user_id);

-- Partitioned monthly; worker creates upcoming partitions, default catches the rest
CREATE TABLE messages (
    id              BIGSERIAL,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES users(id),
    body            TEXT,
    media_s3_key    TEXT,
    voice_s3_key    TEXT,
    product_id      UUID REFERENCES products(id),
    flagged         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE messages_default PARTITION OF messages DEFAULT;
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);

CREATE TABLE dm_settings (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    allow_from VARCHAR(30) NOT NULL DEFAULT 'CUSTOMERS_AND_FOLLOWED'  -- EVERYONE | CUSTOMERS_AND_FOLLOWED | NONE
);

CREATE TABLE crop_share_offers (                   -- Adopt-a-Crop
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crop_id           UUID NOT NULL REFERENCES crops(id) ON DELETE CASCADE,
    farmer_id         UUID NOT NULL REFERENCES users(id),
    share_qty_kg      NUMERIC(8,2) NOT NULL CHECK (share_qty_kg > 0),
    price_paise       BIGINT NOT NULL CHECK (price_paise > 0),
    total_shares      INT NOT NULL CHECK (total_shares > 0),
    sold_shares       INT NOT NULL DEFAULT 0,
    expected_delivery DATE NOT NULL,
    risk_terms        TEXT NOT NULL,              -- crop-failure refund terms shown before payment
    status            VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (sold_shares <= total_shares)
);

CREATE TABLE crop_share_purchases (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id    UUID NOT NULL REFERENCES crop_share_offers(id),
    customer_id UUID NOT NULL REFERENCES users(id),
    shares      INT NOT NULL CHECK (shares > 0),
    payment_id  UUID REFERENCES payments(id),
    status      VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',   -- ACTIVE | DELIVERED | REFUNDED
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_crop_share_purchases_offer ON crop_share_purchases(offer_id);

CREATE TABLE farmer_tips (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user    UUID NOT NULL REFERENCES users(id),
    to_farmer    UUID NOT NULL REFERENCES users(id),
    post_id      UUID REFERENCES posts(id) ON DELETE SET NULL,
    message      VARCHAR(500),
    amount_paise BIGINT NOT NULL CHECK (amount_paise BETWEEN 1000 AND 500000),
    payment_id   UUID REFERENCES payments(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE community_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    host_id     UUID NOT NULL REFERENCES users(id),
    kind        VARCHAR(20) NOT NULL,             -- FARM_VISIT | FARM_STAY | MELA | WORKSHOP | WEBINAR
    title       VARCHAR(150) NOT NULL,
    description TEXT,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    location    GEOGRAPHY(POINT, 4326),
    capacity    INT,
    price_paise BIGINT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ends_at > starts_at)
);

CREATE TABLE event_rsvps (
    event_id   UUID NOT NULL REFERENCES community_events(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    guests     SMALLINT NOT NULL DEFAULT 1 CHECK (guests > 0),
    payment_id UUID REFERENCES payments(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, user_id)
);

CREATE TABLE reputation_ledger (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    points     INT NOT NULL,
    reason     VARCHAR(40) NOT NULL,             -- ANSWER_ACCEPTED | EXPERT_VERIFIED | RECIPE_POSTED ...
    ref_id     UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_reputation_user ON reputation_ledger(user_id);

CREATE TABLE user_badges (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge      VARCHAR(40) NOT NULL,
    awarded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, badge)
);

CREATE TABLE content_reports (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(id),
    target_type VARCHAR(20) NOT NULL,             -- POST | COMMENT | MESSAGE | USER
    target_id   VARCHAR(64) NOT NULL,             -- messages use BIGINT ids
    reason      VARCHAR(40) NOT NULL,
    details     TEXT,
    status      VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_content_reports_open ON content_reports(created_at) WHERE status = 'OPEN';

CREATE TABLE user_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
