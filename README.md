# Aghour Services API — أجهور الكبرى

JSON API backend (Rails 8.1, API-only, PostgreSQL) for the village app.
The native Android app consumes it. Kept simple on purpose; extend step by step.

## Stack

- Ruby 4.0.1, Rails 8.1, PostgreSQL
- Auth: `has_secure_password` (bcrypt) + JWT bearer tokens (30 days)
- Authorization: Pundit
- Admin dashboard: plain Rails views at `/admin` (Arabic, right-to-left)
- Tests: RSpec + FactoryBot
- Locale: Arabic by default (`Accept-Language: en` for English)

## Setup

```bash
cp .env.example .env            # adjust DB credentials
docker compose up -d db         # or use your local PostgreSQL
bundle install
bin/rails db:prepare db:seed
bin/rails s
bundle exec rspec
```

Seeded super admin: `SUPER_ADMIN_PHONE` / `SUPER_ADMIN_PASSWORD` from `.env`.

### Demo data (development)

`bin/rails db:seed` also loads `db/seeds/demo.rb` in development (or anywhere with `SEED_DEMO=1`).
All names and numbers are fictional. Running it again creates nothing new.

- 8 categories with icon keys used by the Android app.
- 10 firm owners (`01090000001` … `01090000010`, password `password123`), each with a current
  subscription; one ends in 3 days so it shows on the dashboard.
- 21 firms across all categories (2 pending, 1 suspended), plus one firm owned by the super admin.
- A pending subscription request (`01090000020`) and a rejected one (`01090000021`) for the review queue,
  and a normal user (`01090000022`).
- 13 articles: news, announcements and articles, one draft and one scheduled for later.
- Firm locations are placed around an approximate village center (`center_lat` / `center_lng` in the file).

To start fresh: `bin/rails db:reset` (drops and recreates the development database, then seeds).

## Roles

| Role          | Can do                                                        |
|---------------|---------------------------------------------------------------|
| `user`        | Browse. Default on register. Submits firms and articles **for review** (at most 3 of each waiting); an approved firm shows once its owner subscribes. |
| `firm_admin`  | Publishes own firms (within the plan's `max_firms`) and articles **directly** while subscribed; without a current subscription, submits for review like a `user`. |
| `admin`       | Publishes directly with no subscription or quota (own firms always visible). Reviews submissions: approve / reject in the API and on the dashboard's firm and article pages, nothing else there. |
| `super_admin` | Everything: categories, news, approve firms, change roles.    |

Who publishes directly is one predicate, `User#can_publish_directly?`. The client never asks for a
status: the server decides from the author. Super admins (not admins) get an inbox row and a push
(`screen` `firm` / `article`) for each submission; authors get one when it is approved or rejected.

## Endpoints (`/api/v1`)

Every call sends `Authorization: Bearer <token>`: the user's token, or for someone not signed in a
guest token from `POST /auth/guest`. "public" below means any token, guest or user. A guest token
names no user, so endpoints marked "user" still answer 401 with it. Only `/auth/*`, `/app_config`
and `/categories/:id/icon` work with no token at all.

Enforcement is behind `API_TOKEN_REQUIRED=1`. Until it is set, calls without a token are still
served (app versions that predate guest tokens) and counted in `aghour.auth.tokenless_requests`
with `result=allowed`; set it once that count has fallen to what you are willing to break.

The app: get a guest token on first launch if it has no user token, keep it in DataStore, and on a
401 from a public endpoint fetch a new guest token and retry once. After logout, switch back to the
guest token. Both kinds last 30 days.

| Method | Path                               | Auth          |
|--------|------------------------------------|---------------|
| POST   | `/auth/guest`                      | none — `{ data: { token } }`, 30 per minute per IP |
| POST   | `/auth/register`                   | none          |
| POST   | `/auth/login`                      | none          |
| GET/PATCH | `/me`                           | user          |
| GET    | `/categories`, `/categories/:id`   | public        |
| POST/PATCH/DELETE | `/categories[/:id]`     | super_admin   |
| GET    | `/categories/:id/firms`            | public        |
| GET    | `/categories/:id/icon?v=`          | none — category image; use the `icon_url` from the JSON (cached 1 year per version) |
| GET    | `/firms?category_id=&q=&mine=true&review=pending` | public — lists only visible firms (active, owner subscribed), for every role; `mine=true` lists all of your own; `review=pending` (admin, super_admin) lists the firms waiting for review |
| GET    | `/firms/:id`                       | public — visible firms; owners, admins and the super admin can also open pending / suspended ones |
| POST   | `/firms`                           | user — `active` or `pending` by role (see Roles); `403 subscription_required` past the plan quota, `403 too_many_pending` past the review cap |
| PATCH/DELETE | `/firms/:id`                 | owner / super_admin — an edit of an active firm by an owner who cannot publish directly, or of a rejected firm, sends it to `pending`; firm JSON has `rejection_reason` and `can: { update, destroy, moderate, review }` |
| PATCH  | `/firms/:id/approve`, `/firms/:id/reject` (`reason`) | admin, super_admin — `422 already_reviewed` when it is not waiting; a rejected firm is `suspended` with `rejection_reason` |
| GET    | `/articles?kind=news&mine=true&review=pending`, `/articles/:id` | public — published articles; authors see their own (any state), reviewers every article |
| POST   | `/articles`                        | user — `review_status` `approved` or `pending` by role; `403 too_many_pending` |
| PATCH/DELETE | `/articles/:id`              | author / super_admin — same re-review rule as firms; article JSON has `review_status`, `rejection_reason`, `can: { update, destroy, review }` |
| PATCH  | `/articles/:id/approve`, `/articles/:id/reject` (`reason`) | admin, super_admin — approving publishes now if no `published_at` was set |
| GET    | `/admin/users?role=`               | super_admin   |
| PATCH  | `/admin/users/:id` (`role`)        | super_admin   |
| GET    | `/payment_methods`                 | public        |
| GET    | `/app_config`                      | none — `{ data: { features: { plans: false } } }`; flags are managed at `/admin/feature_flags`, missing = off, cached 5 min |
| GET    | `/subscription_plans[/:id]`        | public        |
| POST/PATCH/DELETE | `/subscription_plans[/:id]` | super_admin |
| GET    | `/subscriptions[/:id]`             | user (own)    |
| POST   | `/subscriptions` (JSON or multipart with `payment_screenshot`) | user |
| GET    | `/subscriptions/:id/payment_screenshot` | user (own) |
| GET    | `/notifications?unread=true`       | user, or guest token + `X-Installation-Id` (that install's campaigns) |
| PATCH  | `/notifications/:id/read`, `/notifications/read_all` | user, or guest token + `X-Installation-Id` |
| PUT    | `/devices/:installation_id` (`token`, `locale`, `app_version`, `platform`) | public or user — registers the install for push; see `docs/push-notifications.md` |
| POST   | `/devices/:installation_id/detach` | user (own device) — call on logout |
| GET    | `/topics` (header `X-Installation-Id`) | public — topics the app can opt into, with `subscribed` |
| PUT/DELETE | `/devices/:installation_id/topics/:key` | public or user — opt in / out |
| GET    | `/admin/subscriptions?status=pending`, `/admin/subscriptions/:id` | super_admin |
| GET    | `/admin/subscriptions/:id/payment_screenshot` | super_admin |
| PATCH  | `/admin/subscriptions/:id/approve` | super_admin   |
| PATCH  | `/admin/subscriptions/:id/reject` (`reason`) | super_admin |
| GET    | `/up`                              | health check  |

Lists accept `page` and `per_page` (max 50) and return `{ data: [...], meta: {...} }`.
Errors always look like `{ "error": { "code", "message", "details" } }`.

### Example

```bash
curl -X POST localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"phone":"01000000000","password":"change-me-please"}'

curl localhost:3000/api/v1/me -H "Authorization: Bearer <token>"
```

## Admin dashboard

Open `http://localhost:3000/admin/login` and sign in with the seeded super admin.

- Built in-house with plain Rails views (ERB + one CSS file, `app/assets/stylesheets/admin.css`).
  No admin gem, no JavaScript framework, nothing to license.
- Arabic, right-to-left, dark green and gold. Works on phone screens too.
- `super_admin` and `admin` users can sign in. An admin reaches only the firm and article lists,
  their pages and approve / reject (`allow_reviewers` in `Admin::BaseController`); every other page
  redirects to the firms waiting for review. The session lasts 12 hours, login is rate-limited,
  and access is re-checked on every request (a demoted admin loses access at once).
- Brand images: originals in `public/brand/` (logo, cover, splash, village photo). The dashboard uses
  web-optimized copies in `public/brand/web/` (logo, light logo mark for dark backgrounds, favicons,
  village scenery for the login page and dashboard banner, village silhouette for the sidebar).
  Regenerate them with ImageMagick if the originals change (see the commit that added them).

| Page | What you can do |
|------|-----------------|
| الرئيسية | Counters, pending subscription requests, subscriptions ending within 7 days, firms waiting for approval |
| الاشتراكات | Filter / search, view details and the payment screenshot, approve or reject with a reason |
| المنشآت | Filter / search, add, edit, approve, reject with a reason, suspend, delete; shows whether the firm is visible to the public; the sidebar counts firms waiting for review |
| الأقسام | Add, edit, order, enable/disable, upload / remove the icon image (can't delete a category that has firms) |
| الأخبار | Draft, publish now or schedule; filter by kind and review status; approve or reject users' submissions; the sidebar counts those waiting |
| باقات الاشتراك | Prices in EGP, duration, max firms (purchased plans can only be deactivated) |
| المستخدمون | Search, change role, reset password, see subscriptions and firms |

Approve / reject use the same services as the API, so renewal stacking, role promotion and notifications
behave the same everywhere.

## Subscriptions (firm owners)

1. Owner opens `GET /payment_methods` and `GET /subscription_plans`, pays via InstaPay or Vodafone Cash.
2. Owner submits `POST /subscriptions` with the plan, payment method and transfer reference → `pending`.
3. Super admin checks the transfer, then `approve` (→ `active`, user promoted to `firm_admin`) or `reject` with a reason.
4. Renewals stack: a new approval starts when the remaining time ends.
5. A firm is public only if it is `active` **and** its owner has a current subscription.
   No cron job needed — expiry is time-based. `max_firms` on the plan limits how many firms an owner can add.

Safety: one pending request per user, and a transfer reference can't be reused (DB unique indexes).

### Payment screenshot

Optional on `POST /subscriptions` as `subscription[payment_screenshot]` (multipart/form-data):
PNG, JPEG or WEBP, max 4MB (Vercel accepts request bodies up to 4.5MB). Files are stored with Active Storage:
`storage/` locally, and in PostgreSQL in production (the `database` service, see Deploy).
The screenshot is never public: `GET .../payment_screenshot` checks access, then redirects
to a URL that expires after 5 minutes.

### Notifications and expiry reminders

In-app notifications are created when a subscription is approved or rejected, and by a daily job:
7 days and 1 day before expiry, and once after expiry. Owners who already renewed are skipped,
and every reminder has a dedupe key, so running the job twice sends nothing new.

```bash
bin/rails notifications:subscription_reminders
# On Vercel this runs daily through Vercel Cron (vercel.json). Elsewhere, crontab example (09:00 Cairo):
# 0 9 * * * cd /path/to/aghour_services && RAILS_ENV=production bin/rails notifications:subscription_reminders
```

## Deploy (Vercel)

The app runs on Vercel's Container Runtime (beta, all plans): Vercel finds `Dockerfile.vercel`,
builds the image on every deploy and sends all traffic to it.

| Piece | How it works on Vercel |
|-------|------------------------|
| App | `Dockerfile.vercel` (Ruby 4.0.1, Puma on `PORT`=3000, non-root) |
| Database | Neon PostgreSQL from the Vercel Marketplace (sets `DATABASE_URL` and `DATABASE_URL_UNPOOLED`) |
| Migrations / seeds | `bin/docker-entrypoint` runs `db:prepare_locked` on start: migrates, and seeds an empty database. An advisory lock makes containers that start together take turns |
| Files | `database` Active Storage service: screenshots are kept in PostgreSQL (`stored_files`), served by signed 5-minute URLs |
| Daily reminders | Vercel Cron calls `GET /internal/cron/subscription_reminders` at 07:00 UTC (`vercel.json`), protected by `CRON_SECRET` |
| Background jobs | `:async` inside the container (fine for the current small jobs) |

Steps:

1. Push to GitHub, then import the repo in Vercel (or create the project with the CLI: `vercel link`, `vercel deploy`).
2. In the project: Storage → Create → Neon (Postgres). Connect it to Production and Preview.
3. Environment variables (Project → Settings → Environment Variables):

   | Name | Value |
   |------|-------|
   | `PORT` | `3000` (Vercel's default is 80) |
   | `SECRET_KEY_BASE` | `bin/rails secret` (sensitive) |
   | `CRON_SECRET` | a long random string (sensitive) |
   | `SUPER_ADMIN_PHONE` / `SUPER_ADMIN_PASSWORD` | the first admin account (required in production) |
   | `INSTAPAY_ADDRESS` / `VODAFONE_CASH_NUMBER` | where owners pay |
   | `ASSUME_SSL` / `FORCE_SSL` | `1` / `1` |
   | `SEED_DEMO` | `1` only if you want the demo data |
   | `DB_PREPARE_ON_BOOT` | `0` to skip migrations on start (then run them yourself) |

4. Deploy, then open `https://<project>.vercel.app/up` and `/admin/login`.
5. Point the Android release build at it: `AGHOUR_API_URL_RELEASE=https://<project>.vercel.app/api/v1/`.

Limits to know: request bodies up to 4.5MB, requests up to 300s (Hobby), the container sleeps
after 5 minutes without traffic (the next request is a cold start, which also runs `db:prepare`).

Run the production image locally:

```bash
docker build -f Dockerfile.vercel -t village-platform .
docker run --rm -p 3000:3000 -e DATABASE_URL=postgres://postgres:postgres@host.docker.internal/aghour_services_production \
  -e SECRET_KEY_BASE=$(bin/rails secret) -e SUPER_ADMIN_PASSWORD=change-me village-platform
```

## Next steps (planned)

1. Images via Active Storage (firm logos, article covers; category icons done) — move files to S3 / R2 when they grow
2. Token revocation / refresh tokens
3. Push notifications (FCM) — deliver the existing notifications + news
