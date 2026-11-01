# Push notifications — Android contract

The inbox (`GET /api/v1/notifications`) is the source of truth; FCM only delivers. An app version
that never registers for push keeps working through the inbox. Everything here is additive.

## Firebase setup

| Build | Firebase project | Package |
|---|---|---|
| debug | `aghour-dev` (project number 134325122645) | `com.aghourservices.dev` |
| release | `aghour-app` (project number 344587732104) | `com.aghourservices` |

Each build ships that project's `google-services.json`. The server holds the matching
service-account key in `FCM_SERVICE_ACCOUNT_JSON`.

## 1. Register the install

Generate `installationId` once per install (Firebase Installation ID or a random UUID in
DataStore) and treat it as a secret: never log or share it.

Call on app launch, in `FirebaseMessagingService.onNewToken`, and right after login (with the
bearer):

```http
PUT /api/v1/devices/{installationId}
Authorization: Bearer <jwt>        (the guest token for guests; see README "Endpoints")
Content-Type: application/json

{ "token": "<fcm token>", "locale": "ar", "app_version": "2.4.0", "platform": "android" }
```

```json
{ "data": { "platform": "android", "locale": "ar", "app_version": "2.4.0",
            "user_attached": true, "topics": [ "all", "news" ] } }
```

| Status | Meaning |
|---|---|
| 200 | Registered. Safe to call repeatedly. |
| 403 `forbidden` | The install belongs to a signed-in user, this request has no bearer, and the `token` is not the one the server has stored. Sending the stored token without a bearer (expired JWT, deleted account) detaches the install and succeeds. |
| 409 `duplicate` | Two first registrations of the same install raced; retry once. |
| 429 `rate_limited` | More than 30 registrations per minute from this IP; retry later. |

## 2. Logout

Before dropping the JWT:

```http
POST /api/v1/devices/{installationId}/detach
Authorization: Bearer <jwt>
```

The phone becomes a guest: it keeps broadcasts (`all` and the topics it opted into as a guest)
and stops receiving the previous user's notifications. Its guest inbox (section 5) shows again.

## 3. Topics (opt-in)

```http
GET /api/v1/topics
X-Installation-Id: {installationId}
Authorization: Bearer <jwt>        (the user token, or the guest token)
```

```json
{ "data": [ { "key": "news", "name": "الأخبار", "description": "…", "subscribed": true } ] }
```

Toggle: `PUT` or `DELETE /api/v1/devices/{installationId}/topics/{key}`. Signed in, the
subscription belongs to the user (follows them to every phone); as a guest, to this install. The
server subscribes the FCM token itself: **do not call `FirebaseMessaging.subscribeToTopic`**, or
the server's list and FCM drift apart.

## 4. Receiving and tapping

Every push has a `notification` block (title, body) and string `data`:

| key | when | value |
|---|---|---|
| `screen` | always | `none`, `article`, `firm`, `category`, `subscription` |
| `id` | unless `screen` is `none` | the record id, as a string |
| `notification_id` | push to one user | inbox id: mark it read (`PATCH /notifications/:id/read`) |
| `campaign_id` | push to topics | informational |

Routing rule, and the one that keeps old versions safe: **a `screen` the app does not know opens
the inbox.** New screens are added on the server first and used only after an app release that
handles them.

| screen | opens |
|---|---|
| `article` | `GET /articles/:id` detail |
| `firm` | `GET /firms/:id` detail |
| `category` | that category's firm list |
| `subscription` | the subscription screen (`GET /subscriptions/:id`) |
| `none` / unknown | the inbox |

A target can disappear between send and tap (article deleted, firm suspended): handle the 404 by
showing the inbox.

Review notifications reuse these screens. A super admin told of a submission (admins are not
notified) gets `firm` / `article` with the pending record's id, which their token can open; an author told
of approval or rejection gets the same, and can open their own record in any state. `kind`
(`firm_submitted`, `article_submitted`, `firm_approved`, `firm_rejected`, `article_approved`,
`article_rejected`) is informational, like every `kind`: route on `screen`.

## 5. The inbox

Signed in, the inbox is the user's, as it always was:

```http
GET /api/v1/notifications?unread=true&page=1
Authorization: Bearer <user jwt>
```

A guest has an inbox too, per install. It holds only campaigns (pushes to topics, including
`all`) sent while the install was a guest and subscribed; personal notifications never reach it.
Send the guest token **and** the install id:

```http
GET   /api/v1/notifications?unread=true&page=1
PATCH /api/v1/notifications/:id/read
PATCH /api/v1/notifications/read_all
Authorization: Bearer <guest jwt>
X-Installation-Id: {installationId}
```

The response is the same envelope for both: `data` is the list, `meta` carries the page fields
plus `unread_count`.

| Status | Meaning |
|---|---|
| 200 | The inbox. An install not registered yet (no FCM token so far) gets an empty one. |
| 401 `unauthorized` | No user token, and not both the guest token and `X-Installation-Id`. |
| 403 `forbidden` | The install is signed in: use the user token. |
| 404 `not_found` | `:id` is not in this inbox. |

The guest inbox belongs to the install, not to a person. Signing in hides it (the user's inbox
shows instead) and logging out shows it again; nothing moves between the two. It starts empty: a
campaign sent before the install registered is not in it. Uninstalling, or another install taking
over the FCM token, deletes it.

The install id is not a credential: whoever knows it can read and mark that guest inbox. That is
acceptable only because the inbox holds broadcasts everyone could receive. Still treat the id as
private (section 1).

Ask for `POST_NOTIFICATIONS` (Android 13+) at a meaningful moment, for example after the first
subscription or when the user opens the inbox, not on first launch.
