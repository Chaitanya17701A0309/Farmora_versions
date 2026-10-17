# Farmora

> **Families Decide. Farmers Grow. Everyone Benefits.**

An agriculture ecosystem where families tell farmers what to grow (**Community Demand Exchange**), farmers manage crops and see demand before sowing, and both trade directly through a **farm-products marketplace** (Honey, Ghee, Oils, Millets, Pulses, Spices).

## Start Here: Zero-Cost MVP

| Layer | Tech (free tier) |
|---|---|
| Frontend | Next.js · React · TypeScript · Tailwind CSS (mobile-first PWA) |
| Backend | Supabase (PostgREST API, RPC functions, pg_cron) + Next.js Route Handlers |
| Database | PostgreSQL (Supabase) with Row Level Security |
| Auth | Google Login · Email OTP (Supabase Auth) |
| Storage | Supabase Storage |
| Hosting | Vercel (Hobby for build/beta → Pro or Cloudflare for commercial use) |
| Payments | Razorpay (UPI, cards, netbanking): no fixed fee |
| Version control / CI | GitHub Free + GitHub Actions |
| Analytics | Google Analytics 4 |
| Languages | English, తెలుగు, தமிழ், हिन्दी |

### Database (runnable)
- [supabase/migrations/20261011000001_core.sql](supabase/migrations/20261011000001_core.sql): identity, roles, farmer tools
- [supabase/migrations/20261011000002_marketplace.sql](supabase/migrations/20261011000002_marketplace.sql): Module 1, Marketplace
- [supabase/migrations/20261011000003_demand_exchange.sql](supabase/migrations/20261011000003_demand_exchange.sql): **Module 2, Community Demand Exchange** (isolated `demand` schema)
- [supabase/migrations/20261011000004_storage.sql](supabase/migrations/20261011000004_storage.sql): storage buckets
- [supabase/seed.sql](supabase/seed.sql): categories, seasons, crops/products for voting, sample poll

### MVP documents
| # | Deliverable | Document |
|---|---|---|
| 1 | Product Requirement Document | [docs/mvp/01-prd.md](docs/mvp/01-prd.md) |
| 2 | Startup Business Model | [docs/mvp/02-business-and-revenue-model.md](docs/mvp/02-business-and-revenue-model.md) |
| 3 | System Architecture Diagram | [docs/mvp/03-architecture.md](docs/mvp/03-architecture.md) |
| 4 | MVP Feature List | [docs/mvp/01-prd.md § 9](docs/mvp/01-prd.md) |
| 5 | User Stories | [docs/mvp/01-prd.md § 10](docs/mvp/01-prd.md) |
| 6 | Database Schema | [docs/mvp/04-database.md](docs/mvp/04-database.md) |
| 7 | Entity Relationship Diagram | [docs/mvp/04-database.md § 2](docs/mvp/04-database.md) |
| 8 | API Design | [docs/mvp/05-api-design.md](docs/mvp/05-api-design.md) |
| 9 | Folder Structure | [docs/mvp/06-folder-structure.md](docs/mvp/06-folder-structure.md) |
| 10 | UI/UX Wireframes | [docs/mvp/07-ux-design.md § 3](docs/mvp/07-ux-design.md) |
| 11 | Landing Page Design | [docs/mvp/07-ux-design.md § 4](docs/mvp/07-ux-design.md) |
| 12 | Admin Dashboard Design | [docs/mvp/07-ux-design.md § 8](docs/mvp/07-ux-design.md) |
| 13 | Farmer Dashboard Design | [docs/mvp/07-ux-design.md § 6](docs/mvp/07-ux-design.md) |
| 14 | Customer Dashboard Design | [docs/mvp/07-ux-design.md § 7](docs/mvp/07-ux-design.md) |
| 15 | Community Demand Dashboard Design | [docs/mvp/07-ux-design.md § 5](docs/mvp/07-ux-design.md) |
| 16 | Development Roadmap (30/60/90) | [docs/mvp/08-roadmap-30-60-90.md](docs/mvp/08-roadmap-30-60-90.md) |
| 17 | Complete Deployment Guide | [docs/mvp/09-deployment-guide.md](docs/mvp/09-deployment-guide.md) |
| 18 | Social Media Launch Strategy | [docs/mvp/10-launch-strategy.md](docs/mvp/10-launch-strategy.md) |
| 19 | Revenue Model | [docs/mvp/02-business-and-revenue-model.md § 5](docs/mvp/02-business-and-revenue-model.md) |
| 20 | Future Scaling Architecture | [docs/mvp/03-architecture.md § 3–4](docs/mvp/03-architecture.md) |

## Scale Stage (500k+ users)

When Farmora outgrows Supabase (Stage 4 of the [scaling plan](docs/mvp/03-architecture.md)), these documents describe the target AWS architecture and the long-term product vision:

1. [System Architecture (AWS, Express, React Native)](docs/01-architecture.md)
2. [Database Schema](docs/02-database-schema.md): DDL in [database/schema.sql](database/schema.sql)
3. [API Design](docs/03-api-design.md)
4. [UI Wireframes](docs/04-ui-wireframes.md)
5. [Folder Structure](docs/05-folder-structure.md)
6. [Development Roadmap](docs/06-roadmap.md)
7. [Production Deployment Plan](docs/07-deployment.md)
8. [Marketing & Social Media Plan](docs/08-marketing-plan.md)
9. [Future Expansion: Agri Super-App](docs/09-future-expansion.md)
10. [Farmora Community: Social Network](docs/10-community.md)
