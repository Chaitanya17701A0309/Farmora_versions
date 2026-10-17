# 3. API Design

**Base URL**: `https://api.farmora.in/v1` — REST, JSON, OpenAPI 3.1 spec generated from Zod schemas (served at `/v1/docs`).

## 3.1 Conventions

| Item | Convention |
|---|---|
| Auth header | `Authorization: Bearer <access_token>` |
| Locale | `Accept-Language: en \| te \| ta \| hi` |
| Pagination | `?page=1&limit=20` → `{ data, meta: { page, limit, total, totalPages } }` (cursor `?cursor=` for feeds) |
| Sorting | `?sort=price_asc \| price_desc \| rating \| newest \| popular` |
| Errors | `{ "error": { "code": "OUT_OF_STOCK", "message": "...", "details": [...] } }` |
| Idempotency | `Idempotency-Key` header on `POST /orders/checkout`, `POST /payments/verify` |
| Rate limits | Auth/OTP: 5 req/min/IP+phone; general: 100 req/min/user |
| Money | Integer paise in all payloads |

Status codes: `200` OK, `201` Created, `204` No Content, `400` Validation, `401` Unauthenticated, `403` Forbidden, `404` Not Found, `409` Conflict, `422` Business rule, `429` Rate limited, `500` Server.

Roles: 🅿 Public · 🅲 Customer · 🅵 Farmer · 🅰 Admin · 🔑 Any authenticated

## 3.2 Auth

| Method | Endpoint | Access | Description |
|---|---|---|---|
| POST | `/auth/register` | 🅿 | `{ fullName, email?, phone?, password, role: FARMER\|CUSTOMER }` |
| POST | `/auth/login` | 🅿 | `{ email\|phone, password }` → tokens |
| POST | `/auth/otp/send` | 🅿 | `{ phone }` → sends 6-digit OTP (5 min TTL) |
| POST | `/auth/otp/verify` | 🅿 | `{ phone, code, role? }` → tokens (auto-registers if new) |
| POST | `/auth/google` | 🅿 | `{ idToken, role? }` → verify with Google, return tokens |
| POST | `/auth/refresh` | 🅿 | Rotates refresh token (cookie or body) |
| POST | `/auth/logout` | 🔑 | Revokes refresh token |
| POST | `/auth/password/forgot` | 🅿 | Email/OTP reset |
| POST | `/auth/password/reset` | 🅿 | `{ token, newPassword }` |

**Token response**
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "c0f1...",
  "expiresIn": 900,
  "user": { "id": "uuid", "fullName": "Ravi", "role": "FARMER", "preferredLocale": "te" }
}
```

## 3.3 Users & Profile

| Method | Endpoint | Access | Description |
|---|---|---|---|
| GET/PATCH | `/me` | 🔑 | Current user profile, locale |
| GET/PUT | `/me/notification-preferences` | 🔑 | Channel opt-ins |
| POST | `/me/devices` | 🔑 | Register FCM token |
| GET/POST | `/me/addresses` | 🔑 | List / add address |
| PATCH/DELETE | `/me/addresses/:id` | 🔑 | Update / remove |
| GET/PUT | `/farmer/profile` | 🅵 | Farm profile (name, bio, certification, KYC) |
| GET | `/farmers/:id` | 🅿 | Public farmer storefront |

## 3.4 Farms & Crops (Farmer)

| Method | Endpoint | Description |
|---|---|---|
| GET/POST | `/farms` | List / create farm (with `location: {lat,lng}`, optional `boundary` GeoJSON) |
| GET/PATCH/DELETE | `/farms/:farmId` | Farm detail / update / soft delete |
| GET | `/farms/:farmId/weather` | 7-day forecast + alerts |
| GET/POST | `/farms/:farmId/crops` | List / add crop |
| GET/PATCH/DELETE | `/crops/:cropId` | Crop detail (incl. schedules, latest health, yield) |
| POST | `/crops/:cropId/images/upload-url` | Get S3 pre-signed URL `{ contentType, size }` |
| POST | `/crops/:cropId/images` | Confirm upload `{ s3Key, caption }` |
| GET/POST | `/crops/:cropId/schedules` | List / create fertilizer & irrigation tasks (`?type=FERTILIZER`) |
| POST | `/crops/:cropId/schedules/generate` | Auto-generate from crop-type template |
| PATCH | `/schedules/:id` | Mark DONE / SKIPPED / reschedule |
| GET/POST | `/crops/:cropId/health` | Health logs / manual entry |
| POST | `/crops/:cropId/health/detect` | **AI disease detection** `{ s3Key }` |
| GET | `/crops/:cropId/yield-estimate` | Computed yield + expected revenue (uses market price) |
| GET/POST | `/farms/:farmId/expenses` | List (`?from&to&category`) / add expense |
| PATCH/DELETE | `/expenses/:id` | Update / delete |
| GET | `/crop-types` | Master list (translated) |
| GET | `/farmer/dashboard` | Stats: farms, active crops, upcoming tasks, expenses vs revenue, sales, low stock |

**AI detection response**
```json
{
  "status": "DISEASED",
  "predictions": [
    { "disease": "TOMATO_EARLY_BLIGHT", "label": "Early blight", "confidence": 0.91 },
    { "disease": "TOMATO_SEPTORIA_LEAF_SPOT", "label": "Septoria leaf spot", "confidence": 0.05 }
  ],
  "recommendation": "Remove affected leaves; spray Mancozeb 2.5 g/L ...",
  "needsExpertReview": false
}
```

## 3.5 Catalog & Inventory

| Method | Endpoint | Access | Description |
|---|---|---|---|
| GET | `/categories` | 🅿 | Category tree (translated) |
| GET | `/products` | 🅿 | Search/filter: `q, category, minPrice, maxPrice, rating, organic, farmerId, inStock, sort, page` |
| GET | `/products/:slug` | 🅿 | Product detail + variants + images + farmer |
| GET | `/products/:id/reviews` | 🅿 | Paginated reviews + rating breakdown |
| GET | `/search/suggest?q=` | 🅿 | Autocomplete (trigram) |
| GET/POST | `/farmer/products` | 🅵 | Own products / create (status `PENDING_APPROVAL`) |
| PATCH/DELETE | `/farmer/products/:id` | 🅵 | Update / archive |
| POST | `/farmer/products/:id/images/upload-url` | 🅵 | Pre-signed upload |
| POST/DELETE | `/farmer/products/:id/images[/:imageId]` | 🅵 | Attach / remove image |
| POST | `/farmer/products/:id/variants` | 🅵 | Add variant (SKU, label, MRP, price, stock) |
| PATCH | `/farmer/variants/:id/price` | 🅵 | Update price (logs `price_history`) |
| POST | `/farmer/variants/:id/stock` | 🅵 | `{ type: RESTOCK\|ADJUSTMENT, quantity, note }` |
| GET | `/farmer/inventory` | 🅵 | Inventory status, `?lowStock=true` |
| GET | `/farmer/orders` | 🅵 | Order items for this farmer |
| PATCH | `/farmer/orders/:orderId/items/:itemId` | 🅵 | Update fulfillment (PACKED, SHIPPED + tracking) |

## 3.6 Cart, Wishlist, Coupons

| Method | Endpoint | Description |
|---|---|---|
| GET | `/cart` | Cart with live prices, stock warnings, totals |
| POST | `/cart/items` | `{ variantId, quantity }` |
| PATCH/DELETE | `/cart/items/:variantId` | Update qty / remove |
| POST | `/cart/apply-coupon` | `{ code }` → computed discount (validation only) |
| GET | `/wishlist` | List |
| POST/DELETE | `/wishlist/:productId` | Add / remove |
| GET | `/coupons/available` | Coupons applicable to user |

## 3.7 Orders & Payments (Customer)

| Method | Endpoint | Description |
|---|---|---|
| POST | `/orders/checkout` | `{ addressId, couponCode?, paymentMethod }` → reserves stock, creates order + Razorpay order |
| POST | `/payments/verify` | `{ razorpayOrderId, razorpayPaymentId, razorpaySignature }` → HMAC verify, confirm order |
| POST | `/payments/webhook` | Razorpay webhook (`X-Razorpay-Signature` verified, raw body) |
| GET | `/orders` | Order history |
| GET | `/orders/:id` | Detail + status timeline + shipment tracking |
| POST | `/orders/:id/cancel` | Cancel (before SHIPPED) → auto-refund |
| POST | `/orders/:id/return` | Return request |
| GET | `/orders/:id/invoice` | Signed URL to GST invoice PDF |
| POST | `/products/:id/reviews` | `{ rating, title, body, images[] }` (verified purchase) |

**Checkout response**
```json
{
  "orderId": "uuid",
  "orderNumber": "FRM100245",
  "amount": 64900,
  "currency": "INR",
  "razorpay": { "keyId": "rzp_live_xxx", "orderId": "order_Nx..." },
  "expiresAt": "2026-10-11T10:15:00Z"
}
```

## 3.8 Subscriptions

| Method | Endpoint | Description |
|---|---|---|
| GET | `/subscriptions` | My subscriptions |
| POST | `/subscriptions` | `{ items:[{variantId, qty}], frequency, addressId, startDate }` → Razorpay subscription link/auth |
| PATCH | `/subscriptions/:id` | Change items, frequency, address |
| POST | `/subscriptions/:id/pause` | `{ until }` |
| POST | `/subscriptions/:id/resume` | |
| POST | `/subscriptions/:id/skip-next` | Skip next delivery |
| DELETE | `/subscriptions/:id` | Cancel |

## 3.9 Notifications, Weather, Market

| Method | Endpoint | Access | Description |
|---|---|---|---|
| GET | `/notifications` | 🔑 | In-app inbox |
| PATCH | `/notifications/:id/read` | 🔑 | Mark read |
| POST | `/notifications/read-all` | 🔑 | |
| GET | `/weather?lat&lng` | 🔑 | Ad-hoc forecast |
| GET | `/market-prices` | 🔑 | `?commodity&state&district&from&to` |
| GET | `/market-prices/trends` | 🔑 | 30/90-day trend per commodity |

## 3.10 Admin

| Method | Endpoint | Description |
|---|---|---|
| GET | `/admin/dashboard` | KPIs: GMV, orders, AOV, active farmers/customers, conversion |
| GET | `/admin/farmers` | List/search, `?status&kycVerified` |
| PATCH | `/admin/farmers/:id` | Verify KYC, suspend/activate |
| GET | `/admin/customers` | List/search |
| PATCH | `/admin/customers/:id` | Suspend/activate |
| GET | `/admin/products` | `?status=PENDING_APPROVAL` |
| PATCH | `/admin/products/:id/status` | Approve / reject `{ status, reason }` |
| GET/POST/PATCH/DELETE | `/admin/categories[/:id]` | Manage categories + translations |
| GET | `/admin/orders` | Filter by status, date, farmer, customer |
| PATCH | `/admin/orders/:id/status` | Override status |
| POST | `/admin/orders/:id/refund` | Full/partial refund via Razorpay |
| GET/POST/PATCH/DELETE | `/admin/coupons[/:id]` | Coupon management |
| GET | `/admin/reports/revenue` | `?from&to&groupBy=day\|week\|month&farmerId&categoryId` (+ `format=csv`) |
| GET | `/admin/reports/inventory` | Stock, low-stock, stock value, movement summary |
| GET | `/admin/reports/crops` | Crops by type/region, yield, disease incidence |
| GET/POST | `/admin/payouts` | Farmer settlements |
| GET/PUT | `/admin/notification-templates` | Manage templates per locale |
| POST | `/admin/broadcast` | Send notification to segment |
| GET | `/admin/audit-logs` | Audit trail |

## 3.11 Real-time
- **WebSocket** (`wss://api.farmora.in/ws`, Socket.IO, JWT auth) channels: `order:{id}` status updates, `user:{id}` notifications, `admin:orders` live feed.
