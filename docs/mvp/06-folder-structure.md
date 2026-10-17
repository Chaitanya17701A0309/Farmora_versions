# Farmora MVP: Folder Structure

Covers deliverable 9. A single Next.js (App Router, TypeScript) repository, organised by **feature modules** so the Demand Exchange stays independent of the Marketplace.

```
farmora/
├── .github/
│   └── workflows/
│       ├── ci.yml                      # lint, typecheck, test, build on every PR
│       ├── db-migrate.yml              # supabase db push on main
│       ├── jobs-daily.yml              # weather + mandi prices → Postgres
│       └── backup-nightly.yml          # encrypted pg_dump → private artifact
│
├── supabase/
│   ├── config.toml                     # [api] schemas = ["public", "graphql_public", "demand"]
│   ├── migrations/
│   │   ├── 20261011000001_core.sql
│   │   ├── 20261011000002_marketplace.sql
│   │   ├── 20261011000003_demand_exchange.sql
│   │   └── 20261011000004_storage.sql
│   ├── seed.sql
│   └── templates/
│       └── magic_link.html             # Email OTP template showing {{ .Token }}
│
├── public/
│   ├── manifest.webmanifest            # PWA
│   ├── icons/                          # 192/512 maskable icons
│   └── images/                         # landing illustrations (WebP)
│
├── messages/                           # next-intl UI strings
│   ├── en.json
│   ├── te.json
│   ├── ta.json
│   └── hi.json
│
├── src/
│   ├── app/
│   │   ├── [locale]/
│   │   │   ├── layout.tsx              # html lang, fonts, GA, providers
│   │   │   ├── page.tsx                # Landing page
│   │   │   ├── (auth)/
│   │   │   │   ├── login/page.tsx      # Google + Email OTP
│   │   │   │   ├── verify/page.tsx     # 6-digit code
│   │   │   │   └── onboarding/page.tsx # role, language, district
│   │   │   ├── demand/                 # ── MODULE 2 (public + family) ──
│   │   │   │   ├── page.tsx            # Community Demand dashboard (trending, leaderboard)
│   │   │   │   ├── vote/page.tsx       # Vote crops / products
│   │   │   │   ├── requests/page.tsx   # My requests + new request
│   │   │   │   ├── polls/page.tsx
│   │   │   │   ├── polls/[id]/page.tsx
│   │   │   │   └── harvests/page.tsx   # Upcoming harvests + interest
│   │   │   ├── shop/                   # ── MODULE 1 (marketplace) ──
│   │   │   │   ├── page.tsx
│   │   │   │   ├── c/[category]/page.tsx
│   │   │   │   ├── p/[slug]/page.tsx
│   │   │   │   ├── cart/page.tsx
│   │   │   │   └── checkout/page.tsx
│   │   │   ├── farmers/[id]/page.tsx   # public farmer storefront
│   │   │   ├── account/                # ── Customer dashboard ──
│   │   │   │   ├── page.tsx
│   │   │   │   ├── orders/[id]/page.tsx
│   │   │   │   ├── wishlist/page.tsx
│   │   │   │   ├── addresses/page.tsx
│   │   │   │   └── settings/page.tsx
│   │   │   ├── farmer/                 # ── Farmer dashboard (role guard) ──
│   │   │   │   ├── page.tsx            # overview
│   │   │   │   ├── demand/page.tsx     # Demand Dashboard
│   │   │   │   ├── demand/[itemId]/page.tsx  # Consumer interest report
│   │   │   │   ├── harvests/page.tsx   # announcements + pre-order reports
│   │   │   │   ├── farms/page.tsx
│   │   │   │   ├── crops/[id]/page.tsx
│   │   │   │   ├── products/page.tsx
│   │   │   │   ├── orders/page.tsx
│   │   │   │   └── profile/page.tsx
│   │   │   └── admin/                  # ── Admin dashboard (role guard) ──
│   │   │       ├── page.tsx
│   │   │       ├── demand/page.tsx     # analytics
│   │   │       ├── demand/polls/…      # list, new, [id]
│   │   │       ├── demand/requests/page.tsx
│   │   │       ├── demand/items/page.tsx
│   │   │       ├── farmers/page.tsx
│   │   │       ├── customers/page.tsx
│   │   │       ├── products/page.tsx
│   │   │       ├── orders/page.tsx
│   │   │       └── reports/page.tsx
│   │   ├── auth/callback/route.ts
│   │   ├── api/
│   │   │   ├── checkout/route.ts
│   │   │   ├── payments/verify/route.ts
│   │   │   ├── payments/webhook/route.ts
│   │   │   ├── admin/users/[id]/ban/route.ts
│   │   │   ├── export/[report]/route.ts
│   │   │   └── health/route.ts
│   │   ├── sitemap.ts
│   │   └── robots.ts
│   │
│   ├── features/                       # domain logic per module (no cross-imports between demand ↔ marketplace)
│   │   ├── demand/
│   │   │   ├── api.ts                  # typed wrappers: getLeaderboard, castVote, submitPoll…
│   │   │   ├── components/             # VoteCard, Leaderboard, TrendingStrip, PollForm, HarvestCard, RegionChart
│   │   │   ├── hooks/                  # useMyVotes, useLeaderboard
│   │   │   └── schemas.ts              # zod: request form, poll answers
│   │   ├── marketplace/
│   │   │   ├── api.ts
│   │   │   ├── components/             # ProductCard, VariantPicker, CartDrawer, RazorpayButton
│   │   │   └── schemas.ts
│   │   ├── farmer/
│   │   │   ├── api.ts
│   │   │   └── components/             # FarmForm, CropCard, TaskList, WeatherWidget, MandiPrices
│   │   ├── admin/
│   │   │   └── components/             # DataTable, KpiCard, PollBuilder, RequestReview
│   │   └── auth/
│   │       └── components/             # GoogleButton, OtpForm, RolePicker
│   │
│   ├── components/
│   │   ├── ui/                         # Button, Card, Input, Sheet, Tabs, Badge, Skeleton (shadcn/ui)
│   │   ├── layout/                     # Header, BottomNav, Sidebar, LanguageSwitcher, Footer
│   │   └── charts/                     # BarChart, LineChart, Donut (Recharts, lazy-loaded)
│   │
│   ├── lib/
│   │   ├── supabase/
│   │   │   ├── client.ts               # createBrowserClient
│   │   │   ├── server.ts               # createServerClient (cookies)
│   │   │   ├── admin.ts                # service-role client: import 'server-only'
│   │   │   └── middleware.ts           # session refresh
│   │   ├── razorpay.ts                 # server-only
│   │   ├── analytics.ts                # GA4 events (vote_cast, request_submitted, purchase…)
│   │   ├── errors.ts                   # map DB error codes → i18n keys
│   │   ├── money.ts                    # paise ⇄ ₹ formatting
│   │   ├── flags.ts                    # FEATURE_DEMAND / FEATURE_MARKETPLACE
│   │   └── image.ts                    # client-side WebP compression
│   ├── i18n/
│   │   ├── routing.ts                  # locales: en, te, ta, hi
│   │   └── request.ts
│   ├── types/
│   │   └── database.types.ts           # generated: supabase gen types typescript
│   └── middleware.ts                   # locale + auth refresh + /farmer,/admin role guard
│
├── tests/
│   ├── unit/                           # vitest
│   ├── e2e/                            # playwright: vote flow, poll, checkout (Razorpay test mode)
│   └── db/                             # pgTAP: RLS + function tests
│
├── docs/
├── .env.example
├── next.config.ts                      # security headers, images.unoptimized
├── tailwind.config.ts
├── tsconfig.json
├── eslint.config.mjs
└── package.json
```

## Rules
1. `src/features/demand/**` must not import from `src/features/marketplace/**` and vice versa. Enforce with ESLint `no-restricted-imports`.
2. Only files under `src/app/api/**` and `src/lib/supabase/admin.ts` may use the service-role key. `admin.ts` starts with `import 'server-only'`.
3. All user-facing strings live in `messages/*.json`, never hard-coded.
4. Database types are regenerated after every migration (`npm run db:types`).

## `.env.example`
```bash
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=            # server only
NEXT_PUBLIC_SITE_URL=https://farmora.vercel.app
NEXT_PUBLIC_GA_MEASUREMENT_ID=G-XXXXXXX
NEXT_PUBLIC_RAZORPAY_KEY_ID=rzp_test_xxx
RAZORPAY_KEY_SECRET=                  # server only
RAZORPAY_WEBHOOK_SECRET=              # server only
NEXT_PUBLIC_FEATURE_DEMAND=true
NEXT_PUBLIC_FEATURE_MARKETPLACE=true
```
