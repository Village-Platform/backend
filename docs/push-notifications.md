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
and stops receiving the previous user's notifications.

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

Ask for `POST_NOTIFICATIONS` (Android 13+) at a meaningful moment, for example after the first
subscription or when the user opens the inbox, not on first launch.
