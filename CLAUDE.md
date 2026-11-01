# CLAUDE.md

@RTK.md
@MENTOR.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

JSON API backend (Rails 8.1, Ruby 4.0.1, PostgreSQL) for a village services app in Aghour Al Kubra,
Egypt. A native Android app is the main client. Arabic is the default locale throughout.
See `README.md` for the full endpoint table, role matrix and deploy steps; `docs/push-notifications.md`
for the push contract with the Android app.

## Commands

```bash
docker compose up -d db                  # PostgreSQL on host port 5434 (set DB_PORT=5434 in .env)
bin/setup --skip-server                  # bundle install, copy .env, db:prepare (without --skip-server it boots the server)
bin/rails db:reset                       # drop/recreate/seed development (seeds.rb + demo.rb)
bin/rails s
bin/rails tailwindcss:watch              # rebuild admin CSS on change; run beside the server

bundle exec rspec                        # full suite
bundle exec rspec spec/requests/api/v1/firms_spec.rb        # one file
bundle exec rspec spec/requests/api/v1/firms_spec.rb:25     # one example by line

bin/rubocop                              # rubocop-rails-omakase; -a to autocorrect
bundle exec brakeman -q --no-pager       # security scan

bin/rails notifications:subscription_reminders   # the daily job, by hand
```

`bin/rubocop` currently reports 2 pre-existing offenses in `config/application.rb` — don't treat a
clean run as the baseline. `.env.example` has no `DB_PORT` line even though `config/database.yml`
reads one; add it by hand when the DB is on 5434. Run `bundle exec rspec` before you start editing
so you know which failures are yours (see **Testing**).

## Architecture

### Two front doors, one domain

The app is **not** `api_only`. Both halves share the models, policies and services:

- **`/api/v1/*`** — `ApplicationController < ActionController::API`. Stateless, JWT bearer tokens
  (`JsonWebToken`, 30-day, HS256 off `secret_key_base`), authorized with Pundit. New endpoints
  subclass `Api::V1::BaseController` (an empty subclass that exists as the API-only seam); the
  super-admin endpoints live under `Api::V1::Admin::`.
- **`/admin/*`** — `Admin::BaseController < ActionController::Base`. Cookie session
  (`AdminSession`, 12h TTL, re-checks `super_admin?` on every request), server-rendered ERB,
  Arabic RTL, Tailwind (`app/assets/tailwind/application.css` → `app/assets/builds/tailwind.css`)
  and inline SVG icons (`Admin::IconsHelper`). Deliberately no admin gem and no JS framework —
  keep it that way. `Admin::SessionsController` sits outside `BaseController` (it can't require an
  admin) and carries Rails 8 `rate_limit` plus `reset_session` against fixation.

### Admin design system

Colour has exactly one definition site: eleven rgb channel triplets (`--gold`, `--surface`, …) in
`application.css`, mapped once into `@theme` as `--color-*`. The themes redefine those channels
under `[data-theme]`, so **every utility flips automatically and there are no `dark:` variants
anywhere** — add one and you have created a second definition site. Repeated patterns are
`@apply` components in `@layer components` (`.card`, `.btn`, `.tbl`, `.badge-*`, `.stat`, `.tab`,
`.switch`); keep them there rather than repeating utility strings across views.

Three theme states: no `admin_theme` cookie follows `prefers-color-scheme`, `light`/`dark` pin it.
The dark block is declared twice — once guarded by `:root:not([data-theme="light"])` inside the
media query, once as `:root[data-theme="dark"]` — and dropping that guard makes an explicit light
choice lose to a dark OS. `Admin::ThemeController` writes the cookie against an allowlist because
the value lands in an HTML attribute. Two rules cannot be utilities and stay hand-written: the
`body.nav-open .sidebar` drawer and `.brand-mark` visibility, both keyed off an ancestor.

Brand images come in pairs (`mark.png`/`mark-light.png`, `logo.png`/`logo-light.png`); render them
through `brand_mark` / `brand_logo`, which ship both and let CSS pick, since an `<img>` cannot swap
source by media query.

Admin view copy says **نشاط** and **تصنيف**, not منشأة/قسم. `config/locales/*.yml` deliberately
still says منشأة: those strings reach the Android client, where a rename is a contract change.

Admin actions that change subscription state call the same `Subscriptions::Approve` / `Reject`
services as the API, so renewal stacking, role promotion and notifications can't drift apart.

### API request pipeline

`ApplicationController` mixes in `Pundit::Authorization` and three concerns, and every API controller
relies on all of them:

- `Authentication` — `current_user` from the `Authorization: Bearer` header; `authenticate_user!`.
- `ErrorHandling` — `rescue_from` for the whole app. **Prefer bang methods** (`create!`, `update!`,
  `find`) and let exceptions become responses rather than hand-writing error branches.
  `Subscriptions::ReviewError` and `Pundit::NotAuthorizedError` are mapped here too.
- `Pagination` — `paginate(scope)` returns `[records, meta]`; `per_page` clamps to 50.
  `Admin::BaseController` includes it as well, so dashboard index pages paginate the same way.

Two response envelopes, used everywhere:

```jsonc
{ "data": …, "meta": { "page", "per_page", "total", "total_pages" } }
{ "error": { "code": "not_found", "message": "<localized>", "details": {…} } }
```

Render through `render_record` / `render_collection` / `render_error`. The `code` is an i18n key
under `errors.api.*` — adding an error code means adding it to **both** `config/locales/ar.yml`
and `en.yml`.

### Layers

- **Serializers** (`app/serializers/`) are plain classes with a `self.render(record)` class method —
  not ActiveModel::Serializers, not jbuilder. They assume associations are preloaded; when you add a
  field backed by an association, add the `includes` in the controller too.
- **Policies** (`app/policies/`) use Pundit. Controllers call `policy_scope`, `authorize` and
  `permitted_attributes(Model)` — strong params for the API live in the *policy*, not the controller,
  so permissions can vary by role (see `FirmPolicy#permitted_attributes` adding `:status` for super
  admins). Admin controllers use ordinary `params.require(...).permit(...)` instead.
- **Services** (`app/services/`) hold multi-step domain operations with a `self.call(**kwargs)` entry
  point. They own the transactions and the row locks.
- **Admin views** build on `Admin::UiHelper` (`page_header`, `nav_link`, `badge` / `enum_badge`,
  `egp`, `fmt_time`, `filter_params`) and `Admin::IconsHelper#icon`. Reach for those before writing
  new markup, and for `like(term)` / `destroy_and_redirect` in `Admin::BaseController` when adding a
  search box or a delete action.

## Domain rules that span files

These are easy to break from a single file and are covered by request specs:

- **Every API call carries a token**, the user's or a guest's (`POST /api/v1/auth/guest`).
  `Api::V1::BaseController` runs `require_api_token!`, enforced only with `API_TOKEN_REQUIRED=1`
  so old app versions keep working; `/auth/*`, `app_config` and `categories#icon` skip it. Guest
  tokens carry `typ: "guest"` and no `sub`, and `user_from_token` refuses any typed token — keep
  that check, or a guest token reaches `User.find_by(id:)`. New endpoints get the guard for free;
  skip it only for something a client must reach before it holds a token.
- **Firm visibility** is not just `status: active`. `Firm.visible` = active **and** the owner holds a
  current subscription (or is a super admin). Expiry is purely time-based — no job flips a flag.
  Any new public listing must go through `Firm.visible` or `policy_scope(Firm)`.
- **Subscription `status` vs `state`.** The column is `pending/active/rejected`; `#state` derives the
  user-facing `scheduled/current/expired` from `starts_at`/`ends_at`. Serializers expose both.
- **Renewals stack.** `Subscriptions::Approve` starts the new period at `max(now, latest ends_at)`,
  locks the user row and the subscription, and promotes `user` → `firm_admin`. Notification sending
  happens *outside* the transaction on purpose: a failed notification must never undo an approval.
- **An owner's edit of an approved firm is re-reviewed.** `Firms::Update` turns an active firm
  `pending` when its owner changes anything; super admin edits, and edits of pending or suspended
  firms, keep the status. Firm JSON carries `can: { update, destroy, moderate }` from `FirmPolicy`
  for the current user, which the apps use to show controls — the policy still decides.
- **Firm quota is separate from authorization.** `FirmPolicy#create?` only asks
  `can_manage_firms?`; the plan's `max_firms` is enforced by `User#can_add_firm?`, checked in the
  controller and answered with `403 subscription_required`. Both checks must stay.
- **Guards backed by DB indexes:** one pending subscription per user, and `transaction_reference`
  unique per `payment_method`. The race is caught by `rescue_from ActiveRecord::RecordNotUnique`.
- **Feature flags fail closed.** `GET /api/v1/app_config` returns `FeatureFlag.to_h`: the `feature_flags`
  rows (toggled at `/admin/feature_flags`) merged over `FeatureFlag::DEFAULTS`. A missing flag is off.
  `key` is a contract with the Android app — `attr_readonly`, never renamed; add new keys to `DEFAULTS`.
- **`Notifier.notify` is idempotent** via `dedupe_key`. The daily reminder job relies on this —
  running it twice must send nothing new.
- **Push: the inbox is the source of truth, FCM only delivers.** `Notifier.notify` writes the
  `notifications` row and enqueues one `PushNotificationJob` per device *in the same transaction*
  (Solid Queue is in the primary DB, so that is a transactional outbox). Every push carries a
  destination (`Notifications::Destination`: `screen` from a closed list + `id`); the app opens the
  inbox for a screen it does not know, so add screens server-side first. Groups and everyone are
  `NotificationCampaign`s to topics (`DeliverCampaignJob`: one topic send + inbox rows, idempotent,
  at-least-once). Contract with the app: `docs/push-notifications.md`.
- **Topic membership lives in our DB, FCM holds a mirror.** `topics` / `topic_subscriptions` (user or
  guest device) are the truth; `SyncDeviceTopicsJob` reconciles a device with FCM. FCM cannot list
  members, so never "read back" from it. `Topic.key` is the FCM topic name — `attr_readonly`.
  `Topic.everyone` (`all`) is implicit membership for every device and creates itself if missing.
- **Devices belong to an install, not a token.** `devices.installation_id` is stable, `token`
  rotates. An anonymous request can never modify a device that has a user (`Devices::OwnershipError`
  → 403); logout calls `detach`, which also pulls the token out of that user's topics.
- **All Google calls go through `Fcm.client`** (`Fcm::Client`, a thin layer over the `fcm` gem that
  turns its status hashes into `Fcm::*` errors): `send_to_token(s)`, `send_to_topic(s)`,
  `send_to_condition`, and topic membership through the gem's `batch_topic_subscription`.
  **Deadline:** that is the legacy Instance ID API, removed by Google on 2027-09-29; move
  `subscribe`/`unsubscribe` to the topicSubscriptions REST API before then. Specs get `FakeFcm`
  automatically (`spec/support/fake_fcm.rb`); nothing in the suite reaches the network. No
  `FCM_SERVICE_ACCOUNT_JSON` = logged no-op.
- **Payment screenshots are never public.** Controllers authorize first, then redirect to a URL that
  expires in 5 minutes (`ScreenshotRedirect`). Max 4MB, PNG/JPEG/WEBP.
- **Payment account numbers live in ENV** (`INSTAPAY_ADDRESS`, `VODAFONE_CASH_NUMBER`), surfaced by
  `PaymentMethods.all` — never hardcode them.
- **Phones are normalized** (`normalizes :phone`, digits and `+` only), so a lookup by raw input has
  to go through `User.normalize_value_for(:phone, input)` — seeds and the admin login already do.
- **Nearly every association is `dependent: :restrict_with_error`.** Deletes fail loudly instead of
  cascading; surface the message (`destroy_and_redirect` in admin, `errors.api.cannot_delete` in the
  API) rather than working around the restriction.

## Storage

`lib/active_storage/service/database_service.rb` is a custom Active Storage service that keeps file
bodies in PostgreSQL (`stored_files`), served by `StoredFilesController` through signed expiring
URLs. It exists because Vercel has no persistent disk. Development uses `:local`, test uses `:test`,
production defaults to `database` (override with `ACTIVE_STORAGE_SERVICE`). Switch to S3/R2 before
files get large or numerous.

## Category icons

`Category has_one_attached :icon_image` (PNG/JPEG/WEBP, ≤ 512KB). The apps read `icon_url`
(categories and the `category` inside firms): a **relative** path to the public
`GET /api/v1/categories/:id/icon?v=<icon_version>`, which streams the image with a one-year
`immutable` cache when `v` matches the content (an hour otherwise) — unlike payment screenshots,
these are public. The `icon` string column stays for older Android versions and to pick the default
image. Preload with `with_attached_icon_image` / `includes(category: { icon_image_attachment: :blob })`.

## Seeds

- `db/seeds.rb` is the base data every environment needs and must stay idempotent: the super admin
  (from `SUPER_ADMIN_PHONE` / `SUPER_ADMIN_PASSWORD`), the 11 categories, a welcome article and
  three subscription plans. Each category gets its default image (`Category#attach_default_icon!`,
  `db/seeds/category_icons/<icon>.png`) only if it has none; production backfills existing rows with
  `bin/rails categories:attach_default_icons`.
- `db/seeds/demo.rb` is loaded only in development or with `SEED_DEMO=1`. It imports the real
  Aghour Al Kubra places from `db/seeds/aghour_al_kubra_places.json`, mapping the source's detailed
  Arabic types onto the category names from `seeds.rb` with `fetch` — so renaming a category in
  `seeds.rb` breaks the import loudly. Every place is owned by the super admin.
- Re-running must create nothing new: match on natural keys with `find_or_initialize_by` and only
  set `owner` / `status` when `new_record?`.

## i18n

Arabic (`:ar`) is the default, English is the fallback; API clients pick with `Accept-Language`.
`ApplicationController#switch_locale` reads the first two characters of that header;
`Admin::BaseController` forces `:ar` regardless.

- API-facing strings go through `config/locales/{ar,en}.yml` — both files.
- Admin page copy, `notice:` and `alert:` are **hardcoded Arabic** in the views and controllers;
  that's the convention there, don't start extracting it.
- The exceptions already extracted are `config/locales/admin.{ar,en}.yml` (login page, bulk-action
  flashes) and the `enums.*` / `activerecord.*` trees in `ar.yml`, which `Admin::UiHelper#enum_label`
  and `enum_options` read for labels and `<select>` options. Those trees are Arabic-only on purpose.

## Testing

RSpec + FactoryBot, overwhelmingly **request specs** (`spec/requests/`) that exercise real HTTP in
and JSON out — there are no model unit specs, so put new coverage at the request level. Only the
reminders job and the custom storage service have their own specs (`spec/jobs/`, `spec/services/`).

- Helpers: `json` (parsed body), `auth_headers(user)` (API), `sign_in_admin` (dashboard).
- Factory traits carry the domain setup: `create(:user, :subscribed)` makes a firm admin with a
  current subscription; subscriptions have `:current` / `:expired`.
- `ActiveSupport::Testing::TimeHelpers` is included for `travel_to`.
- **The app's time zone is Cairo and Egypt observes DST.** `Subscription#days_left` is
  `((ends_at - now) / 1.day).ceil`, so `6.days.from_now` spanning the October fallback is 6.04 days
  → 7. Any spec asserting a day count needs `travel_to` on a fixed date.
- `spec/seeds_spec.rb` runs the real seeds with `SEED_DEMO=1` and asserts both their content and
  their idempotence, so it has to be updated in the same change as `db/seeds/demo.rb`.
- `spec/requests/admin/brand_assets_spec.rb` fails if a view references a `/brand/web/*` image that
  isn't in `public/`.

Known failures as of 2026-10-25, before any change of yours: four in `spec/seeds_spec.rb` (it still
expects the old fictional demo data that the current `db/seeds/demo.rb` no longer creates) and one
in `spec/jobs/subscription_expiry_reminders_job_spec.rb` (the DST case above).

## Style

`rubocop-rails-omakase`: double quotes, and **spaces inside array/hash literal brackets**
(`[ :en ]`, `%i[ mri windows ]`). Policies use endless method definitions (`def index? = true`).
Models lean on Rails 8 features already in use here: `enum ... validate: true`, `normalizes`,
and range-based scopes (`where(starts_at: ..Time.current)`).

## Deployment

Production runs on a single-node k3s cluster (`deploy/k8s/`, `deploy/observability/`); the Vercel
setup below (`Dockerfile.vercel`, `vercel.json`) is still in the repo.

- Background jobs: **Solid Queue**, tables in the primary database, run inside Puma when
  `SOLID_QUEUE_IN_PUMA=1` (set in `deploy/k8s/config.yaml` and `.env.example`; otherwise run
  `bin/jobs`). Production and development use it; test uses `:test`. Move it to its own Deployment
  before campaigns compete with web requests — and watch memory: the plugin forks extra Ruby
  processes on a 2 GB node.
- The daily reminders: a k8s `CronJob` curls `GET /internal/cron/subscription_reminders` with
  `CRON_SECRET` (Vercel Cron did the same).

## Deployment constraints (Vercel Container Runtime)

- Request bodies cap at 4.5MB — that is why the screenshot limit is 4MB.
- `bin/docker-entrypoint` runs `db:prepare_locked` on boot; the custom rake task takes a PostgreSQL
  advisory lock because several containers can cold-start at once and plain `db:prepare` races on
  schema load.
- The daily job runs via Vercel Cron hitting `GET /internal/cron/subscription_reminders`, guarded by
  a `CRON_SECRET` bearer token compared with `secure_compare` (`Internal::CronController`).
  On Vercel, Solid Queue would need `SOLID_QUEUE_IN_PUMA` and a container that is not scaled to zero.
- `ruby-vips` is in the `:production` group only (libvips is installed in `Dockerfile.vercel`), so
  image variants can't be exercised locally without installing it.
