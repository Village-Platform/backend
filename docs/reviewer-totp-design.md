# Design: Authenticator-app (TOTP) second factor for reviewers

Status: **Dashboard implemented; API not yet** · Scope: `admin` and `super_admin` users, on **both**
the `/admin` dashboard and the `/api/v1` login used by the Android app.

## Implementation status

Built (dashboard only):

- `REVIEWER_MFA_MODE` = `off` (default) / `optional` / `required`; the app refuses to boot with any
  other value, or with a mode other than `off` and no Active Record Encryption keys.
- Password step → `/admin/second_factor/new` (code or recovery code) → signed in.
  `AdminSession` holds a 10-minute pending step; a session without the code is not signed in.
- Setup at `/admin/authenticator/new`: QR code (inline SVG via `rqrcode`), manual key, confirm with the
  first code, 10 recovery codes shown once. In `required` mode an unenrolled reviewer goes there right
  after the password (trust on first use); in `optional` mode the sidebar offers it.
- Replay guard, 10-failure lock (unconfirmed setups never lock), HMAC-stored recovery codes.
- `bin/rails "totp:reset[USER_ID,OPERATOR]"` for a lost phone or a locked authenticator.

Not built yet: the API (`mfa_required` login, §9 API contract), 14-day `admin_sessions` and step-up
(§9; the dashboard session is still 12 h), operator-issued enrollment tokens (§6 phase 3).
**Until the API part ships, a reviewer's password alone still gets an API token**, including
`/api/v1/admin/*`.

Production rollout: set the three `ACTIVE_RECORD_ENCRYPTION_*` keys in `village-env` (keep an
offline copy), deploy with `optional`, have super admins enroll, then switch to `required`.

## 1. Context

Today reviewers sign in with phone + password only:

- **Dashboard** (`Admin::SessionsController` → `AdminSession`): cookie session, 12 h TTL, re-checks
  `reviewer?` on each request.
- **API** (`Api::V1::AuthController#login` → `JsonWebToken`): a 30-day HS256 JWT carrying only `sub`.
  The Android app exposes super-admin screens (firms, categories, articles, plans) and
  `Api::V1::Admin::` endpoints (user role changes, subscription approval) through this token.

Facts that shape the design:

1. **Both doors must be gated.** If TOTP protects only `/admin`, a stolen password still yields a
   30-day super-admin JWT through `POST /api/v1/auth/login`, and with it role grants via
   `PATCH /api/v1/admin/users/:id`.
2. **JWTs can't be revoked today.** There is no `jti` or version claim; changing the password leaves
   every issued token valid for up to 30 days. This affects all users, not only reviewers.
3. **No out-of-band channel exists.** There are no mailers and email is optional, so there's nothing
   to fall back on or recover through: recovery codes and an operator reset are the only paths.
4. **Small footprint:** one web pod, Solid Queue inside Puma, `production: {}` in `recurring.yml` (no
   scheduler process), `memory_store` cache. The design adds no Redis, no scheduler, no new process.
5. **Android clears the session on any 401** (`AuthInterceptor`). "Code needed" must never be a 401.

## 2. Goals and non-goals

**Goals**
- Reviewers need password + TOTP on both surfaces.
- They stay signed in up to **14 days**, with instant revocation and a fresh code (step-up) for
  high-risk actions.
- Single-use recovery codes; an audited operator reset.
- Fix JWT revocation (fact 2) as part of the same change, since revocation is a prerequisite for
  long-lived reviewer tokens.

**Non-goals**
- TOTP for `user` and `firm_admin` (open question 1).
- Phishing resistance (WebAuthn/passkeys): later, through the same `factor` seam.
- Changing the 30-day lifetime of normal user tokens.

## 3. Key decisions

| Decision | Choice | Why / alternative rejected |
|---|---|---|
| Library | `rotp` + `rqrcode` | Small, standard RFC 6238 implementation; no auth framework is in use here to plug into. |
| Factor storage | Separate `totp_credentials` table | `users` is small here, so columns would be cheap. The table is chosen for lifecycle: an unconfirmed enrollment, replacement, and lockout state shouldn't sit on `users`, and a later WebAuthn credential follows the same shape. |
| Secret | `encrypts :otp_secret` | Active Record Encryption isn't configured yet: `bin/rails db:encryption:init`, keys as k8s secrets (§11). |
| Replay guard | Compare-and-set on `last_used_timestep` | One atomic `UPDATE`; no cache dependency. |
| Brute-force lockout | DB counter on the credential | `rate_limit` uses `memory_store`: per process, reset on every deploy. Fine as a first filter, not as the lockout. |
| API "code needed" response | `200` with `mfa_required`, no token | A 401 would sign the Android app out (fact 5). |
| JWT revocation | `users.token_version` claim | Stateless check on the user row `user_from_token` already loads. No token table. |
| Expired-session cleanup | Opportunistic on sign-in | No scheduler in production by design (`recurring.yml`). |

## 4. Data model

All three tables are new and empty; `users` gets one column with a constant default (metadata-only in
PostgreSQL 11+, no table rewrite).

```ruby
add_column :users, :token_version, :integer, null: false, default: 0

create_table :totp_credentials do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.text     :otp_secret, null: false          # AR-encrypted
  t.datetime :confirmed_at                     # null = enrollment not proven yet
  t.bigint   :last_used_timestep               # replay guard (unix_time / 30)
  t.integer  :failed_attempts, null: false, default: 0
  t.datetime :locked_at                        # set after too many failures; cleared by operator reset
  t.timestamps
end

create_table :recovery_codes do |t|
  t.references :user, null: false, foreign_key: true
  t.string   :code_digest, null: false, index: { unique: true }
  t.datetime :used_at
  t.timestamps
end

create_table :admin_sessions do |t|               # dashboard only; the API uses JWT + token_version
  t.references :user, null: false, foreign_key: true
  t.string   :token_digest, null: false, index: { unique: true }
  t.datetime :expires_at, null: false             # created_at + 14 days, never extended
  t.datetime :last_seen_at, null: false
  t.datetime :stepped_up_at
  t.datetime :revoked_at
  t.string   :user_agent
  t.timestamps
end
```

`User` has `has_one :totp_credential` and `has_many :recovery_codes` with `dependent: :delete_all`.
Note `acts_as_paranoid`: soft-deleting a reviewer must also revoke (bump `token_version`, revoke
admin sessions). Add `otp`, `otp_secret`, `recovery_code`, `challenge_token` to
`filter_parameter_logging`.

## 5. Verifying a code

```ruby
# TotpCredential#verify!(code, at: Time.current) -> :ok / :invalid / :replayed / :locked
return :locked if locked_at
matched_at = ROTP::TOTP.new(otp_secret, issuer: ISSUER).verify(code.to_s, drift_behind: 30, at:)
return register_failure! unless matched_at

step = matched_at.to_i / 30
updated = self.class.where(id:, locked_at: nil)
                    .where("last_used_timestep IS NULL OR last_used_timestep < ?", step)
                    .update_all(last_used_timestep: step, failed_attempts: 0, updated_at: Time.current)
updated == 1 ? :ok : :replayed
```

- `register_failure!` runs `UPDATE … SET failed_attempts = failed_attempts + 1`, and sets
  `locked_at` when the count reaches **10**. That's a durable cap independent of the cache. 10 tries
  with 2 valid codes each gives an attacker about a 0.002 % chance before lockout. A locked
  credential needs an operator reset (§8).
- Recovery codes go through the same counter.
- Input: string, `\A\d{6}\z` for TOTP; normalized `\A[A-Z2-9]{10}\z` for recovery codes.
- Keep Rails `rate_limit` (per IP) on every code endpoint as a first filter.

## 6. Enrollment

### Bootstrap: who is trusted to enroll first?

No reviewer has a second factor today, so the first enrollment is **trust on first use (TOFU)**: the
next password login enrolls a device. If an attacker already has a reviewer's password, they could
enroll first. Limit that window:

1. Super-admins enroll first, in person, right after deploy (§10 phase 1).
2. Other reviewers get a short enrollment window (proposed 7 days). During it, a password login
   without a credential is forced into enrollment and does nothing else.
3. After the window, enrollment needs a **single-use enrollment token** issued by a super-admin
   (`bin/rails "totp:issue_enrollment[USER_ID]"`, or an admin page behind step-up). Granting the
   `admin` role then means "issue a token too".

### Flow (same for web and API)

1. Password OK, no confirmed credential, enrollment allowed → create or replace an **unconfirmed**
   credential with `ROTP::Base32.random` (160-bit).
2. Show the QR code (SVG via `rqrcode`, server-rendered, never a third-party QR service) and the base32
   secret for manual entry.
   - Issuer `AghourServices`. Use ASCII: some authenticator apps render RTL issuers badly.
   - Label: the user's name, not the phone number, to keep PII off the device list.
   - `Cache-Control: no-store`.
   - On Android the app renders the `otpauth://` URI as a QR or offers "open in authenticator".
3. The first valid code confirms it. In one transaction:
   - set `confirmed_at`;
   - replace the recovery codes (10 new ones, shown once);
   - bump `token_version`, which invalidates every other session/token for this user;
   - sign in.

## 7. Recovery codes

- 10 codes of 10 characters from `A–Z2–9` minus look-alikes, shown as `XXXXX-XXXXX` (about 50 bits
  each).
- Digest: `HMAC-SHA256(secret_key_base, "recovery:#{user_id}:#{normalized}")`.
- Consume with `where(user_id:, code_digest:, used_at: nil).update_all(used_at: Time.current) == 1`.
- A login that used one shows a banner: "N codes left; re-enroll your device". Log it and count a
  metric (no email channel exists to notify).

## 8. Operator reset and break-glass

`bin/rails "totp:reset[USER_ID]"`, run via `kubectl exec` into the web pod:

1. Verify identity out-of-band (call the reviewer; a second super-admin confirms). Write this into
   the runbook. This step is the real attack surface.
2. In one transaction: destroy the credential and recovery codes, bump `token_version`, revoke admin
   sessions, issue an enrollment token, print it once.
3. Log `totp_reset` with the operator name passed as an argument.

Break-glass for "every super-admin is locked out" is the same task: cluster access is the root of
trust. Keep at least two super-admins enrolled.

## 9. Sessions: 14 days, revocable, step-up

| Control | Dashboard | API (Android) |
|---|---|---|
| Absolute lifetime | 14 days, `admin_sessions.expires_at` | Reviewer JWT `exp` = 14 days (users keep 30) |
| Idle timeout | 72 h (`last_seen_at`, written at most every 5 min) | None. A phone app has no meaningful "idle"; the 14-day cap and revocation cover it. |
| Revocation | `revoked_at`; all rows on password change / reset / role removal / soft delete | `ver` claim ≠ `users.token_version` → 401 |
| Step-up | `stepped_up_at` within 15 min | `mfa_at` claim within 15 min |

### Dashboard

- Password step: on success, store only `session[:admin_pending] = { user_id, at }` (5-minute TTL), then
  redirect to the code page. `AdminSession.find_admin` ignores a pending session.
- Code step: create an `admin_sessions` row. Put the raw 256-bit token in a separate encrypted,
  `HttpOnly`, `Secure`, `SameSite=Lax` cookie, `expires: 14.days`, so it survives browser restarts.
- `AdminSession.find_admin` checks: token digest found, not revoked, not expired, idle < 72 h, and the
  user is still `reviewer?` (kept from today).
- Clean up on sign-in: `AdminSession.where(user:).where("expires_at < ? OR revoked_at IS NOT NULL", 30.days.ago).delete_all`.

### API contract (Android change)

```
POST /api/v1/auth/login {phone, password}
  user / firm_admin           → 200 { data: { token, user } }                        (unchanged)
  reviewer, enrolled          → 200 { data: { mfa_required: true, challenge_token } }
  reviewer, must enroll       → 200 { data: { mfa_enrollment_required: true, challenge_token, otpauth_uri } }

POST /api/v1/auth/mfa {challenge_token, code | recovery_code}
                              → 200 { data: { token, user } } | 422 invalid_code | 423 locked
POST /api/v1/auth/mfa/enroll {challenge_token, code}
                              → 200 { data: { token, user, recovery_codes: [...] } }
POST /api/v1/auth/step_up {code}   (Authorization: current token)
                              → 200 { data: { token } }   (fresh mfa_at)
```

- `challenge_token`: JWT with `typ: "mfa_challenge"`, `sub`, `exp` 5 min. `user_from_token` already
  rejects any token with a `typ`, so a challenge token can never act as a user token. Add a spec
  that locks this in.
- Reviewer token claims: `{ sub, ver, mfa_at }`. `user_from_token` adds
  `payload["ver"] == user.token_version`. Apply it to **all** user tokens: tokens without `ver` are
  treated as `0`, so existing user tokens keep working and the next password change revokes them.
  That closes fact 2 for everyone.
- Step-up required → `403 { error: "step_up_required" }`, never 401.
- **Old app builds** can't read `mfa_required` and will treat login as failed. Ship the Android
  release before enabling enforcement (§10); reviewers are few, so tell them to update.

### Step-up actions

Dashboard and API: role changes (`admin/users#update`), subscription approve/reject, subscription-plan
create/update (prices), `destroy_fully` on any resource, and issuing enrollment tokens. Open question 3
confirms the list.

## 10. Rollout (`REVIEWER_MFA_MODE`)

| Phase | Mode | Behaviour | Exit criterion |
|---|---|---|---|
| 0 | `off` | Tables, `token_version` check, endpoints shipped; nothing enforced. | Deployed; Android release with MFA screens published. |
| 1 | `enroll` | Reviewers can enroll from the dashboard; super-admins enroll in person. Login still password-only. | All super-admins enrolled. |
| 2 | `required` | Reviewers must use TOTP on both surfaces. Unenrolled reviewers are forced into TOFU enrollment for 7 days. | Every active reviewer enrolled (`TotpCredential.confirmed.count` vs `User.reviewers.count`). |
| 3 | `required_token_enrollment` | Enrollment only with an operator-issued token. | — |

Rollback: set the mode back. The `token_version` check stays on: it's a fix, not a feature.

## 11. Operations

- **Encryption keys:** `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `…_DETERMINISTIC_KEY`,
  `…_KEY_DERIVATION_SALT` in the k8s secret, plus an offline backup. Losing them locks out every
  reviewer, and the reset task can't help because it runs in the same app.
- **Clock:** TOTP depends on node time. Confirm NTP on the cluster nodes.
- **Memory:** `rotp` and `rqrcode` are tiny. No new process in the 640Mi pod.

## 12. Observability

Extend `Observability::Metrics.increment(:logins, surface:, result:)` with results `mfa_required`,
`mfa_success`, `mfa_invalid`, `mfa_replayed`, `mfa_locked`, `recovery_code_used`, `step_up_success`,
`step_up_failed`. Add structured log lines with `user_id` and `request_id` for `totp_enrolled`,
`totp_reset`, `totp_locked`, `recovery_code_used`, `sessions_revoked` (with reason). Never log
codes, secrets, `otpauth://` URIs or challenge tokens.

Alert on any `mfa_locked`, `totp_reset`, `recovery_code_used`, and on `mfa_replayed` (a reused valid
code usually means it was relayed).

## 13. Testing

- **Model:** valid at current/previous step, invalid two steps back and one ahead (`travel_to`);
  replay rejected; lockout at 10 failures and success resets the counter; locked stays locked.
- **Concurrency:** two threads with the same code → exactly one `:ok` (example with
  `use_transactional_tests = false`).
- **API requests:**
  - each `login` branch;
  - a challenge token is rejected as a bearer token;
  - an old-`ver` token gets 401 after a password change, TOTP reset or soft delete;
  - a token without `ver` works while `token_version == 0`;
  - step-up returns 403 (not 401) and works after `/auth/step_up`;
  - a reviewer JWT expires at 14 days.
- **Dashboard:**
  - a pending session can't reach any admin page;
  - the code step creates a session that survives a new cookie jar with the session token;
  - absolute and idle expiry; revocation;
  - step-up on listed actions;
  - `rate_limit` still applies to code endpoints.
- **Rake:** reset revokes everything and prints a token once; a token works once.

## 14. Open questions

1. Should `firm_admin` (paying firm owners) get optional TOTP later? Their blast radius is their own
   firms only.
2. Enrollment window length for phase 2 (proposed 7 days).
3. Final list of step-up actions (§9), especially whether subscription approval counts.
4. Who may approve an operator reset, and is a second person required?
5. Applying `token_version` to all users means a password change signs the user out of other
   devices. That's the right default, but it's a behaviour change worth a line in the release notes.
