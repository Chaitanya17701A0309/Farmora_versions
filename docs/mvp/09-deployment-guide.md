# Farmora MVP: Complete Deployment Guide (Zero Cost)

Covers deliverable 17. From an empty laptop to production on free tiers.

## 0. Prerequisites (all free)
| Tool | Install |
|---|---|
| Node.js 20 LTS | `brew install node@20` |
| Supabase CLI | `brew install supabase/tap/supabase` |
| Git + GitHub account | `brew install git` · github.com |
| Docker Desktop (local Supabase only) | docker.com (optional; free for personal/small business) |
| Accounts | Supabase, Vercel, Google Cloud (OAuth), Brevo or Resend (SMTP), Google Analytics, Razorpay |

---

## 1. Repository

```bash
npx create-next-app@latest farmora --ts --tailwind --eslint --app --src-dir --import-alias "@/*"
cd farmora
npm i @supabase/supabase-js @supabase/ssr next-intl zod razorpay
npm i -D vitest @playwright/test supabase
supabase init
# copy supabase/migrations/*.sql and supabase/seed.sql from this repo
git init && git add . && git commit -m "chore: bootstrap Farmora"
gh repo create farmora --private --source=. --push   # or create on github.com
```

Expose the demand schema to the API. In `supabase/config.toml`:
```toml
[api]
schemas = ["public", "graphql_public", "demand"]
extra_search_path = ["public", "extensions"]
```

Local development:
```bash
supabase start                    # local Postgres + Auth + Storage in Docker
supabase db reset                 # applies migrations + seed.sql
npm run dev
```

---

## 2. Supabase (Free plan)

1. **Create project** at supabase.com → region **ap-south-1 (Mumbai)** → strong DB password (save it in a password manager).
2. **Link & push migrations**
   ```bash
   supabase login
   supabase link --project-ref <project-ref>
   supabase db push                 # applies supabase/migrations/*
   psql "$(supabase db url)" -f supabase/seed.sql   # or paste seed.sql into SQL Editor once
   ```
3. **API → Settings → Exposed schemas:** add `demand`.
4. **Extensions:** confirm `pg_cron` and `pg_trgm` are enabled (Database → Extensions). Check jobs:
   ```sql
   select jobname, schedule from cron.job;   -- expire-unpaid-orders, demand-refresh-stats
   ```
5. **Auth → URL configuration**
   - Site URL: `https://farmora.vercel.app`
   - Redirect URLs: `https://farmora.vercel.app/auth/callback`, `http://localhost:3000/auth/callback`, `https://*-<team>.vercel.app/auth/callback` (previews)
6. **Auth → Providers → Google:** enable, paste Client ID/Secret (step 3).
7. **Auth → Providers → Email:** enable, **confirm email ON**, OTP length 6, expiry 3600 s.
8. **Auth → Email templates → Magic Link:** use the code instead of a link:
   ```html
   <h2>Your Farmora login code</h2>
   <p style="font-size:28px;letter-spacing:6px"><b>{{ .Token }}</b></p>
   <p>Valid for 1 hour. If you didn't request this, ignore this email.</p>
   ```
9. **Auth → SMTP settings:** enable custom SMTP (step 4). The built-in mailer is for testing only.
10. **Auth → Rate limits:** keep defaults (OTP send/verify limits protect against abuse).
11. **Storage:** buckets are created by the migration. Verify the 4 buckets and their size limits.
12. **Create the first admin:** sign up in the app, then in SQL Editor:
    ```sql
    update public.profiles set role = 'admin'
     where id = (select id from auth.users where email = 'you@example.com');
    ```

---

## 3. Google Login (Google Cloud, free)

1. console.cloud.google.com → New project "Farmora".
2. **OAuth consent screen:** External; app name, logo, support email; scopes `email`, `profile`, `openid`; add privacy policy URL.
3. **Credentials → Create OAuth client ID → Web application**
   - Authorised JavaScript origins: `https://farmora.vercel.app`, `http://localhost:3000`
   - Authorised redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`
4. Copy Client ID and Secret into Supabase (step 2.6).
5. Publish the consent screen (Testing mode limits you to 100 test users).

---

## 4. Email OTP SMTP (free)

| Provider | Free | Settings for Supabase |
|---|---|---|
| **Brevo** | ~300 emails/day | Host `smtp-relay.brevo.com`, port 587, SMTP login + key |
| **Resend** | ~3,000/month (100/day) | Host `smtp.resend.com`, port 465, user `resend`, API key as password |

Verify a sender domain (SPF/DKIM) if you have one. Otherwise use the provider's shared domain during beta. Set sender to `Farmora <login@yourdomain>`.

---

## 5. Vercel (Hobby → see licence note)

1. vercel.com → **Add New Project** → import the GitHub repo → framework Next.js.
2. **Environment variables** (Production + Preview):

   | Name | Value | Exposure |
   |---|---|---|
   | `NEXT_PUBLIC_SUPABASE_URL` | `https://<ref>.supabase.co` | public |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon key | public |
   | `SUPABASE_SERVICE_ROLE_KEY` | service role key | **server only** |
   | `NEXT_PUBLIC_SITE_URL` | `https://farmora.vercel.app` | public |
   | `NEXT_PUBLIC_GA_MEASUREMENT_ID` | `G-…` | public |
   | `NEXT_PUBLIC_RAZORPAY_KEY_ID` | `rzp_test_…` | public |
   | `RAZORPAY_KEY_SECRET` | secret | **server only** |
   | `RAZORPAY_WEBHOOK_SECRET` | secret | **server only** |
   | `NEXT_PUBLIC_FEATURE_DEMAND` / `_MARKETPLACE` | `true` | public |

3. Deploy. Every push to `main` deploys to production; every PR gets a preview URL.
4. `next.config.ts`:
   ```ts
   const securityHeaders = [
     { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
     { key: 'X-Content-Type-Options', value: 'nosniff' },
     { key: 'X-Frame-Options', value: 'DENY' },
     { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
     { key: 'Permissions-Policy', value: 'camera=(self), geolocation=(self), microphone=()' },
   ];
   export default {
     images: { unoptimized: true },
     async headers() { return [{ source: '/(.*)', headers: securityHeaders }]; },
   };
   ```
   Add a Content-Security-Policy allowing `self`, `*.supabase.co`, `checkout.razorpay.com`, `api.razorpay.com`, `www.googletagmanager.com` and `www.google-analytics.com`.

> ⚠️ **Commercial use:** Vercel's Hobby plan is for non-commercial use. Before taking real payments (Day ~80), choose one:
> - **Vercel Pro** ($20/month): no code changes, or
> - **Cloudflare Workers (free tier allows commercial use):** `npm i -D @opennextjs/cloudflare wrangler`, add `wrangler.jsonc`, `npx opennextjs-cloudflare build && npx wrangler deploy`, and set the same env vars as Worker secrets.

---

## 6. Custom domain (optional, ~₹700/year)
Buy `farmora.in` (or similar) → Vercel/Cloudflare → Domains → add → set DNS records. Then update the Supabase Site URL/redirects, the Google OAuth origins and the Razorpay webhook URL.

---

## 7. Google Analytics 4
1. analytics.google.com → create property "Farmora" → Web stream → copy `G-…` ID.
2. Load GA with `@next/third-parties/google` **only after cookie consent**.
3. Key events: `sign_up`, `vote_cast`, `vote_removed`, `request_submitted`, `poll_completed`, `preorder_interest`, `harvest_announced`, `add_to_cart`, `begin_checkout`, `purchase`.
4. Mark `vote_cast`, `sign_up` and `purchase` as conversions.

---

## 8. Razorpay
1. Sign up → **Test mode** keys → put in env vars.
2. Settings → **Webhooks** → URL `https://<domain>/api/payments/webhook`, events `payment.captured`, `payment.failed`, `refund.processed`, a strong secret.
3. Complete KYC (business PAN, bank account) to activate **Live mode**. No setup fee; per-transaction pricing.
4. Switch env vars to live keys in Production only. Keep test keys in Preview.

---

## 9. GitHub Actions

### `ci.yml`
```yaml
name: CI
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm run lint && npm run typecheck && npm test -- --run
      - run: npm run build
        env:
          NEXT_PUBLIC_SUPABASE_URL: https://example.supabase.co
          NEXT_PUBLIC_SUPABASE_ANON_KEY: dummy
```

### `db-migrate.yml`
```yaml
name: DB migrate
on:
  push:
    branches: [main]
    paths: ['supabase/migrations/**']
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env: { SUPABASE_ACCESS_TOKEN: '${{ secrets.SUPABASE_ACCESS_TOKEN }}' }
      - run: supabase db push
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}
```

### `backup-nightly.yml` (free-tier backups)
```yaml
name: Nightly backup
on:
  schedule: [{ cron: '30 20 * * *' }]   # 02:00 IST
  workflow_dispatch:
jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - run: sudo apt-get update && sudo apt-get install -y postgresql-client age
      - run: |
          pg_dump "$DB_URL" --no-owner --format=custom --file=farmora.dump
          age -r "$AGE_PUBLIC_KEY" -o farmora.dump.age farmora.dump
          rm farmora.dump
        env:
          DB_URL: ${{ secrets.SUPABASE_DB_URL }}          # session pooler connection string
          AGE_PUBLIC_KEY: ${{ secrets.BACKUP_AGE_PUBLIC_KEY }}
      - uses: actions/upload-artifact@v4
        with: { name: 'farmora-${{ github.run_id }}', path: farmora.dump.age, retention-days: 30 }
```
Keep the `age` **private** key offline. Test a restore monthly: `age -d -i key.txt farmora.dump.age > f.dump && pg_restore -d <local-db> f.dump`. Make sure `pg_dump`'s major version matches the server's.

### `jobs-daily.yml`
Runs a small Node script daily: fetches mandi prices from data.gov.in (free API key) and district weather from OpenWeatherMap (free key), then upserts into `market_prices` / `weather_cache` with the service role key. It also calls `/api/health`.

**GitHub secrets:** `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `BACKUP_AGE_PUBLIC_KEY`, `DATA_GOV_IN_KEY`, `OPENWEATHER_KEY`.

---

## 10. Monitoring (free)
| What | Tool |
|---|---|
| Uptime | UptimeRobot → `/api/health` every 5 min, email/Telegram alerts |
| Errors | Sentry (Next.js SDK) |
| DB usage | Supabase dashboard → Reports (DB size, egress, MAU). Set a calendar reminder to check weekly |
| Web vitals | Vercel Speed Insights (Hobby quota) or GA4 |
| Logs | Vercel function logs, Supabase logs explorer |

---

## 11. Go-Live Checklist
- [ ] All migrations applied; `cron.job` shows 2 jobs
- [ ] `demand` schema exposed; leaderboard RPC works for anonymous users
- [ ] RLS spot-check: an anonymous `select * from demand.votes` returns nothing
- [ ] Service role key **not** present in any `NEXT_PUBLIC_*` variable or client bundle (`grep -r service_role .next/static` → no hits)
- [ ] Google OAuth consent screen published
- [ ] Custom SMTP working; OTP email arrives in < 1 min, not in spam
- [ ] Razorpay live keys + webhook verified with a ₹1 test purchase and refund
- [ ] Hosting plan permits commercial use (Vercel Pro or Cloudflare)
- [ ] Privacy Policy (DPDP), Terms, Refund & Shipping policies linked in footer
- [ ] GA4 consent banner working
- [ ] Nightly backup artifact created and a restore tested
- [ ] UptimeRobot + Sentry alerts going to the team
- [ ] Admin account created; seed items and current season cycle present

## 12. Upgrade Runbook (when limits approach)
| Signal | Action |
|---|---|
| DB > 400 MB or MAU > 40k | Supabase → Billing → **Pro** (no migration needed, same project) |
| OTP emails > 250/day | Upgrade SMTP plan or switch to Amazon SES |
| Storage > 900 MB or egress > 4 GB | Supabase Pro; put Cloudflare in front of public image URLs |
| Slow leaderboard / dashboards | Supabase compute add-on; add read replica; increase MV refresh interval |
