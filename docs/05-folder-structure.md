# 5. Folder Structure

Turborepo + pnpm workspaces monorepo.

```
farmora/
├── apps/
│   ├── web/                          # Next.js 15 (App Router) + Tailwind
│   │   ├── src/
│   │   │   ├── app/
│   │   │   │   ├── [locale]/                     # en | te | ta | hi (next-intl)
│   │   │   │   │   ├── (public)/
│   │   │   │   │   │   ├── page.tsx              # Home
│   │   │   │   │   │   ├── products/[slug]/page.tsx
│   │   │   │   │   │   ├── category/[slug]/page.tsx
│   │   │   │   │   │   ├── search/page.tsx
│   │   │   │   │   │   └── farmers/[id]/page.tsx
│   │   │   │   │   ├── (auth)/login | register | otp
│   │   │   │   │   ├── (customer)/
│   │   │   │   │   │   ├── cart/ checkout/ orders/[id]/
│   │   │   │   │   │   ├── wishlist/ subscriptions/ account/
│   │   │   │   │   ├── farmer/
│   │   │   │   │   │   ├── dashboard/ farms/[id]/ crops/[id]/
│   │   │   │   │   │   ├── schedules/ expenses/ health/
│   │   │   │   │   │   ├── products/ inventory/ orders/ market/
│   │   │   │   │   └── admin/
│   │   │   │   │       ├── dashboard/ farmers/ customers/ products/
│   │   │   │   │       ├── orders/ coupons/ payouts/ reports/ settings/
│   │   │   │   ├── api/auth/[...nextauth]/route.ts   # Google OAuth bridge (optional)
│   │   │   │   └── layout.tsx
│   │   │   ├── components/
│   │   │   │   ├── ui/                   # Button, Card, Input, Modal, Badge (shadcn/ui)
│   │   │   │   ├── layout/               # Navbar, Sidebar, Footer, BottomNav
│   │   │   │   ├── product/              # ProductCard, Gallery, VariantPicker, ReviewList
│   │   │   │   ├── farmer/               # CropCard, TaskList, WeatherWidget, HealthBadge
│   │   │   │   ├── charts/               # RevenueChart, CategoryPie, ExpenseDonut
│   │   │   │   └── checkout/             # AddressForm, RazorpayButton, CouponInput
│   │   │   ├── hooks/                    # useCart, useAuth, useRazorpay
│   │   │   ├── lib/                      # api client, auth helpers, formatters
│   │   │   ├── store/                    # Zustand stores
│   │   │   ├── messages/                 # en.json te.json ta.json hi.json
│   │   │   └── middleware.ts             # locale + role-based route guard
│   │   ├── public/
│   │   ├── tailwind.config.ts
│   │   ├── next.config.mjs
│   │   └── Dockerfile
│   │
│   ├── mobile/                       # React Native (Expo SDK, Expo Router)
│   │   ├── app/
│   │   │   ├── (auth)/ login.tsx otp.tsx language.tsx
│   │   │   ├── (customer)/(tabs)/ index.tsx browse.tsx wishlist.tsx orders.tsx profile.tsx
│   │   │   ├── (farmer)/(tabs)/ dashboard.tsx crops.tsx tasks.tsx shop.tsx profile.tsx
│   │   │   ├── product/[slug].tsx  cart.tsx  checkout.tsx
│   │   │   ├── crop/[id].tsx  crop/scan.tsx  farm/[id].tsx
│   │   │   └── _layout.tsx
│   │   ├── src/
│   │   │   ├── components/  hooks/  store/  theme/  i18n/
│   │   │   └── services/ (push.ts, razorpay.ts, camera.ts, location.ts)
│   │   ├── app.config.ts
│   │   └── eas.json
│   │
│   ├── api/                          # Node.js + Express (TypeScript)
│   │   ├── src/
│   │   │   ├── app.ts                    # express app, middleware wiring
│   │   │   ├── server.ts                 # http + socket.io bootstrap
│   │   │   ├── config/                   # env (zod-validated), logger, db, redis, s3
│   │   │   ├── middleware/
│   │   │   │   ├── authenticate.ts  authorize.ts  validate.ts
│   │   │   │   ├── rateLimit.ts  errorHandler.ts  locale.ts  idempotency.ts
│   │   │   ├── modules/
│   │   │   │   ├── auth/         {routes,controller,service,schemas}.ts  otp.service.ts  google.service.ts
│   │   │   │   ├── users/
│   │   │   │   ├── farms/
│   │   │   │   ├── crops/        + yield.service.ts  schedule.service.ts
│   │   │   │   ├── expenses/
│   │   │   │   ├── health/       + ai.client.ts
│   │   │   │   ├── catalog/
│   │   │   │   ├── inventory/
│   │   │   │   ├── cart/  wishlist/  coupons/
│   │   │   │   ├── orders/
│   │   │   │   ├── payments/     razorpay.client.ts  webhook.controller.ts
│   │   │   │   ├── subscriptions/
│   │   │   │   ├── reviews/
│   │   │   │   ├── notifications/ channels/{fcm,sms,whatsapp,email}.ts
│   │   │   │   ├── weather/  market/
│   │   │   │   ├── analytics/
│   │   │   │   └── admin/
│   │   │   ├── shared/                   # errors, pagination, money, s3 presign, i18n
│   │   │   └── routes.ts                 # mounts /v1/*
│   │   ├── prisma/
│   │   │   ├── schema.prisma
│   │   │   ├── migrations/
│   │   │   └── seed.ts
│   │   ├── tests/  unit/  integration/
│   │   └── Dockerfile
│   │
│   ├── worker/                       # BullMQ consumers + cron
│   │   ├── src/
│   │   │   ├── queues.ts
│   │   │   ├── jobs/
│   │   │   │   ├── send-notification.job.ts
│   │   │   │   ├── crop-reminders.job.ts       # every 15 min
│   │   │   │   ├── weather-sync.job.ts         # every 3 h
│   │   │   │   ├── market-prices.job.ts        # daily 07:00 IST
│   │   │   │   ├── expire-unpaid-orders.job.ts # every 1 min
│   │   │   │   ├── subscription-orders.job.ts  # daily
│   │   │   │   ├── low-stock-alerts.job.ts
│   │   │   │   └── refresh-analytics.job.ts    # hourly
│   │   │   └── index.ts
│   │   └── Dockerfile
│   │
│   └── ai-service/                   # Python FastAPI – crop disease model
│       ├── app/ main.py  model.py  remedies/{en,te,ta,hi}.json
│       ├── training/ notebooks/ train.py
│       ├── requirements.txt
│       └── Dockerfile
│
├── packages/
│   ├── shared/                       # Zod schemas, TS types, enums, constants, money utils
│   ├── api-client/                   # Typed fetch client used by web + mobile
│   ├── i18n/                         # shared translation JSON (en, te, ta, hi)
│   ├── ui-tokens/                    # colors, spacing, typography (Tailwind + RN theme)
│   ├── eslint-config/
│   └── tsconfig/
│
├── database/
│   └── schema.sql                    # reference DDL (Prisma migrations are source of truth)
│
├── infra/
│   ├── terraform/
│   │   ├── modules/ vpc  ecs  rds  redis  s3-cloudfront  alb  waf  secrets  monitoring
│   │   └── envs/ dev  staging  prod
│   └── docker/
│       └── docker-compose.yml        # local: postgres+postgis, redis, localstack, mailhog
│
├── .github/workflows/
│   ├── ci.yml                        # lint, typecheck, test, build
│   ├── deploy-api.yml  deploy-web.yml  deploy-worker.yml
│   └── mobile-eas.yml
│
├── docs/
├── turbo.json
├── pnpm-workspace.yaml
├── package.json
└── .env.example
```

### Module file pattern (API)
```
modules/orders/
├── orders.routes.ts       # router + middleware (auth, validate, authorize)
├── orders.controller.ts   # HTTP in/out only
├── orders.service.ts      # business logic, transactions
├── orders.repository.ts   # Prisma queries
├── orders.schemas.ts      # Zod request/response schemas
└── orders.test.ts
```
