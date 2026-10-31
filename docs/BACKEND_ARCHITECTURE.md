# ClubMates Backend Architecture
<!-- Repository documentation; excluded from runtime deployment. -->

## Context

ClubMates is a venue-based dating/social app (SwiftUI, iOS 18.2). The iOS UI is complete — all three ViewModels (`AppSessionStore`, `DiscoverViewModel`, `MatchesViewModel`) are fully mocked with local data and simulated timers. This document defines the production backend to replace every mock with real network calls.

---

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| **Backend runtime** | Node.js 22 LTS + TypeScript | Fast to ship, mature WebSocket/APNs libs |
| **Framework** | Fastify | Faster than Express, built-in JSON schema validation, first-class TS |
| **Primary DB** | PostgreSQL (Supabase hosted) | Relational, great for JOIN-heavy discovery queries, managed backups |
| **Cache / presence** | Upstash Redis | Serverless pricing, venue presence sets, OTP TTL, rate limiting, BullMQ queue |
| **Real-time chat** | Custom WebSocket via `@fastify/websocket` | Full protocol control, avoids Firebase lock-in |
| **Venue broadcast** | Supabase Realtime | Zero backend code for check-in/out broadcast to roster subscribers |
| **Photo storage** | Supabase Storage (S3-compatible) + Cloudflare CDN | Same ecosystem as Postgres |
| **OTP SMS** | MSG91 (primary) + Twilio (fallback) | MSG91: cheaper on +91, DLT compliant (legally required in India) |
| **Push notifications** | APNs directly (token-based `.p8` key) | iOS-only; no FCM needed |
| **Hosting** | Render Web Service | Zero-DevOps PaaS, GitHub auto-deploys, simple environment variable management |
| **Job queue** | BullMQ on Upstash Redis | Async notification delivery, presence expiry sweeps |

**Estimated total cost at launch: ~$50–70/month**

---

## Database Schema (PostgreSQL)

```sql
-- Core user data
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164    TEXT UNIQUE NOT NULL,          -- e.g. +919876543210
  name          TEXT NOT NULL,
  age           SMALLINT NOT NULL,
  bio           TEXT,
  job_title     TEXT,
  company       TEXT,
  height        TEXT,
  interests     TEXT[] DEFAULT '{}',
  is_verified   BOOLEAN DEFAULT false,
  is_active     BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

-- Profile photos (ordered 0–5)
CREATE TABLE profile_photos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  storage_key TEXT NOT NULL,                   -- Supabase Storage path
  cdn_url     TEXT NOT NULL,
  position    SMALLINT NOT NULL,               -- 0 = main photo
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, position)
);

-- Icebreaker prompts (ordered 0–2)
CREATE TABLE profile_prompts (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
  question  TEXT NOT NULL,
  answer    TEXT NOT NULL,
  position  SMALLINT NOT NULL,
  UNIQUE(user_id, position)
);

-- Venues (seeded by admins, not user-created)
CREATE TABLE venues (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  neighborhood  TEXT NOT NULL,
  vibe          TEXT,
  music         TEXT,
  symbol_name   TEXT,
  gradient_hex  TEXT[],
  is_active     BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- Live check-ins (also mirrored in Redis for speed)
CREATE TABLE checkins (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES users(id) ON DELETE CASCADE,
  venue_id       UUID REFERENCES venues(id),
  checked_in_at  TIMESTAMPTZ DEFAULT now(),
  checked_out_at TIMESTAMPTZ,
  last_ping_at   TIMESTAMPTZ DEFAULT now()
);
-- Index for fast "who is live at this venue" query
CREATE INDEX idx_checkins_active_venue ON checkins(venue_id) WHERE checked_out_at IS NULL;

-- Swipe actions
CREATE TABLE swipes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id   UUID REFERENCES users(id),
  target_id  UUID REFERENCES users(id),
  venue_id   UUID REFERENCES venues(id),
  direction  TEXT CHECK(direction IN ('like', 'nope', 'superlike')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(actor_id, target_id, venue_id)        -- one swipe per pair per venue
);
CREATE INDEX idx_swipes_actor_venue ON swipes(actor_id, venue_id);

-- Mutual matches
CREATE TABLE matches (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id  UUID REFERENCES users(id),
  user_b_id  UUID REFERENCES users(id),
  venue_id   UUID REFERENCES venues(id),        -- where they matched
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_matches_user_a ON matches(user_a_id);
CREATE INDEX idx_matches_user_b ON matches(user_b_id);

-- Chat messages
CREATE TABLE messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id   UUID REFERENCES matches(id) ON DELETE CASCADE,
  sender_id  UUID REFERENCES users(id),
  body       TEXT NOT NULL,
  is_read    BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_messages_match ON messages(match_id, created_at);

-- Safety
CREATE TABLE blocks (
  blocker_id UUID REFERENCES users(id),
  blocked_id UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID REFERENCES users(id),
  reported_id UUID REFERENCES users(id),
  reason      TEXT NOT NULL,
  details     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- APNs device tokens
CREATE TABLE device_tokens (
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  platform   TEXT DEFAULT 'apns',
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, token)
);
```

---

## Auth — Phone OTP Flow

```
iOS                        Backend                        MSG91
 │                             │                             │
 │  POST /auth/otp/send        │                             │
 │  { phone: "+9198765..." }   │                             │
 │ ───────────────────────────►│                             │
 │                             │  Rate check (3/hr in Redis) │
 │                             │  SET otp:{phone} EX 300     │
 │                             │  Send SMS ─────────────────►│
 │  { ok: true }               │                             │
 │ ◄───────────────────────────│                             │
 │                             │
 │  POST /auth/otp/verify      │
 │  { phone, code }            │
 │ ───────────────────────────►│
 │                             │  Compare + DEL Redis key
 │                             │  Upsert users row
 │                             │  Issue accessToken (15min JWT RS256)
 │                             │  Issue refreshToken (30d opaque, stored in Redis)
 │ ◄───────────────────────────│
 │  { accessToken,             │
 │    refreshToken,            │
 │    user, isNewUser }        │
```

**Token strategy:**
- `accessToken`: RS256 JWT, 15-min expiry, payload `{ sub: userId, phone }`
- `refreshToken`: 256-bit random string, 30-day TTL in Redis as `refresh:{token} → userId`
- iOS stores both in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- On 401: silent `POST /auth/refresh` rotates the refresh token and issues a new access token

---

## REST API

```
# Auth
POST   /auth/otp/send              { phone }
POST   /auth/otp/verify            { phone, code }
POST   /auth/refresh               { refreshToken }
DELETE /auth/session               (logout — invalidates refresh token)

# Profile
GET    /users/me
PUT    /users/me                   (name, age, bio, prompts, interests, etc.)
POST   /users/me/photos            (multipart — resizes + strips EXIF, returns cdnUrl)
DELETE /users/me/photos/:photoId
PUT    /users/me/photos/order      { order: [photoId, ...] }
POST   /users/me/device-token      { token }

# Venues
GET    /venues                     (list with live occupancy via Redis SCARD)
GET    /venues/:id/roster          (compact profiles currently checked in)
POST   /venues/:id/checkin
DELETE /venues/:id/checkin

# Discovery
GET    /venues/:id/discover        (paginated swipe queue — excludes swiped & blocked)
POST   /swipes                     { targetUserId, venueId, direction }
                                   → { isMatch: bool, matchId?: UUID }
DELETE /swipes/:targetUserId/:venueId   (undo last swipe)

# Chat
GET    /matches                    (list with last message + unread count)
GET    /matches/:id/messages       (cursor-paginated)
PUT    /matches/:id/messages/read  { upToMessageId }

# Safety
POST   /blocks                     { blockedUserId }
POST   /reports                    { reportedUserId, reason, details? }
```

All endpoints require `Authorization: Bearer {accessToken}` except the `/auth/*` routes.

---

## Real-time: WebSocket Protocol

Single connection per user: `wss://api.clubmates.app/v1/ws?token={accessToken}`

Reconnect strategy: exponential backoff (1s → 2s → 4s → max 60s).

### Server → Client

```json
{ "type": "message.new",    "matchId": "...", "message": { "id": "...", "body": "...", "createdAt": "..." } }
{ "type": "message.ack",    "tempId": "...", "serverId": "...", "createdAt": "..." }
{ "type": "message.read",   "matchId": "...", "upToMessageId": "..." }
{ "type": "typing.start",   "matchId": "...", "userId": "..." }
{ "type": "typing.stop",    "matchId": "...", "userId": "..." }
{ "type": "match.created",  "match": { "id": "...", "profile": {...}, "venueId": "..." } }
{ "type": "presence.join",  "venueId": "...", "userId": "...", "name": "...", "photoUrl": "..." }
{ "type": "presence.leave", "venueId": "...", "userId": "..." }
```

### Client → Server

```json
{ "type": "message.send",  "matchId": "...", "tempId": "client-uuid", "body": "..." }
{ "type": "message.read",  "matchId": "...", "upToMessageId": "..." }
{ "type": "typing.start",  "matchId": "..." }
{ "type": "typing.stop",   "matchId": "..." }
{ "type": "presence.ping", "venueId": "..." }   // send every 90s while checked in
```

`tempId` is a client-generated UUID for optimistic UI — replaced with `serverId` on `message.ack`.

> **Scaling note:** For multiple server replicas, each WS handler publishes to Redis Pub/Sub channel `match:{matchId}`. All instances relay the event to their connected clients.

---

## Venue Presence System

```
Check-in:
  1. INSERT INTO checkins (user_id, venue_id)
  2. SADD venue:{venueId}:members userId
  3. SETEX presence:{userId} 300 venueId     ← 5-minute TTL
  4. Broadcast presence.join via WS

Heartbeat (iOS sends presence.ping every 90s):
  → Backend extends presence:{userId} TTL to 300s

Expiry sweep (BullMQ job every 60s):
  → For each venue: find members whose presence:{userId} key expired
  → SREM venue:{venueId}:members userId
  → UPDATE checkins SET checked_out_at = now()
  → Broadcast presence.leave

Check-out:
  Same as expiry sweep but immediate, triggered by DELETE /venues/:id/checkin

Occupancy count: SCARD venue:{venueId}:members  (O(1))
```

---

## Mutual Like Detection (Race-safe)

A single Postgres stored function handles both the swipe insert and match creation atomically — no race condition when two users swipe simultaneously.

```sql
CREATE OR REPLACE FUNCTION record_swipe(
  p_actor_id  UUID,
  p_target_id UUID,
  p_venue_id  UUID,
  p_direction TEXT
) RETURNS TABLE(is_match BOOLEAN, match_id UUID)
LANGUAGE plpgsql AS $$
DECLARE
  v_mutual BOOLEAN;
  v_match_id UUID;
BEGIN
  INSERT INTO swipes(actor_id, target_id, venue_id, direction)
  VALUES (p_actor_id, p_target_id, p_venue_id, p_direction)
  ON CONFLICT (actor_id, target_id, venue_id) DO UPDATE SET direction = p_direction;

  IF p_direction IN ('like', 'superlike') THEN
    SELECT EXISTS(
      SELECT 1 FROM swipes
      WHERE actor_id = p_target_id AND target_id = p_actor_id
        AND venue_id = p_venue_id AND direction IN ('like', 'superlike')
    ) INTO v_mutual;

    IF v_mutual THEN
      INSERT INTO matches(user_a_id, user_b_id, venue_id)
      VALUES (
        LEAST(p_actor_id::text, p_target_id::text)::uuid,
        GREATEST(p_actor_id::text, p_target_id::text)::uuid,
        p_venue_id
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_match_id;

      IF v_match_id IS NULL THEN
        SELECT id INTO v_match_id FROM matches
        WHERE user_a_id = LEAST(p_actor_id::text, p_target_id::text)::uuid
          AND user_b_id = GREATEST(p_actor_id::text, p_target_id::text)::uuid;
      END IF;

      RETURN QUERY SELECT true, v_match_id;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::UUID;
END;
$$;
```

On `is_match = true`, the backend:
1. Sends `match.created` WS event to both users
2. Enqueues APNs push notification for both
3. Returns `{ isMatch: true, matchId }` to the swiping user

---

## Discovery Query

`GET /venues/:id/discover` runs this query (excludes already-swiped, blocked users, and self):

```sql
SELECT u.*, pp.cdn_url AS photo_url,
       (s.direction = 'superlike') AS has_super_liked_me
FROM users u
JOIN checkins c ON c.user_id = u.id
  AND c.venue_id = $venueId AND c.checked_out_at IS NULL
LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0
LEFT JOIN swipes s ON s.actor_id = u.id AND s.target_id = $myUserId
  AND s.venue_id = $venueId AND s.direction = 'superlike'
WHERE u.id != $myUserId
  AND NOT EXISTS (
    SELECT 1 FROM swipes
    WHERE actor_id = $myUserId AND target_id = u.id AND venue_id = $venueId
  )
  AND NOT EXISTS (
    SELECT 1 FROM blocks
    WHERE (blocker_id = $myUserId AND blocked_id = u.id)
       OR (blocker_id = u.id AND blocked_id = $myUserId)
  )
  AND u.is_active = true
ORDER BY c.checked_in_at DESC
LIMIT 20;
```

---

## Photo Upload Pipeline

`POST /users/me/photos` (multipart/form-data):
1. Validate MIME type (JPEG/PNG/HEIC only) and size (≤ 10MB)
2. **Sharp** (Node.js): decode HEIC → JPEG, resize to `1080w` / `400w` / `200w`, strip EXIF (removes GPS coordinates embedded by iPhone)
3. Upload 3 variants to Supabase Storage: `photos/{userId}/{photoId}/{size}.jpg`
4. Return `{ photoId, cdnUrl }` — iOS stores the URL, never re-uploads binary

---

## Push Notifications (APNs)

Token-based auth (`.p8` key file, never expires). All sends go through a **BullMQ queue** — never block request handlers.

| Trigger | Notification |
|---|---|
| Mutual like | "You and Aria both liked each other at Pulse Room 💫" |
| New message | "{senderName}: {messagePreview}" |
| Super like received | "Someone super liked you at Neon Garden ⭐" |

On APNs `BadDeviceToken` error → delete token from `device_tokens` table.

---

## Safety Features

- **Block**: `POST /blocks` — inserts into `blocks` table; both users immediately excluded from each other's `/discover` query. Auto-block applied on every report.
- **Report**: `POST /reports` — 3+ reports on a user sets `users.is_flagged = true`, removing them from discovery pending manual review. Slack webhook alert sent to moderation.
- **Rate limits** (Upstash Redis sliding window):
  - OTP: 3 sends per phone per hour
  - Swipes: 500 per user per day
  - Messages: 30 per minute per match
  - Reports: 10 per day per user

---

## iOS Integration — What Changes

### New files to create

**`NetworkClient.swift`** — actor wrapping URLSession:
- Auto-attaches `Authorization: Bearer {accessToken}`
- On 401: calls `AppSessionStore.refreshSessionIfNeeded()`, retries once
- Throws typed `APIError` (.unauthorized, .notFound, .serverError, .networkOffline)
- Pure `async/await` with `URLSession.data(for:)` — no Combine, no Alamofire

**`WebSocketClient.swift`** — manages the single WSS connection:
- Connects to `wss://api.clubmates.app/v1/ws?token=...`
- Exposes `AsyncStream<WebSocketEvent>` for ViewModels to subscribe with `for await`
- Exponential backoff reconnect (1s → 2s → 4s → max 60s)
- On 401 close: refreshes access token and reconnects

### AppSessionStore.swift changes
- `sendOTP(phone:) async throws` → `POST /auth/otp/send`
- `verifyOTP(phone:code:) async throws` → `POST /auth/otp/verify`
- Store `accessToken`, `refreshToken`, `userId` in Keychain (not UserDefaults)
- `refreshSessionIfNeeded() async` — called on app foreground
- `completeProfile` / `updateProfile` → `PUT /users/me` + photo upload calls

### DiscoverViewModel.swift changes
- `loadVenues() async` → `GET /venues` (real occupancy from Redis)
- `checkIn(to:) async` → `POST /venues/{id}/checkin` + subscribe to WS presence events
- `checkOut() async` → `DELETE /venues/{id}/checkin`
- `profiles` queue → `GET /venues/{id}/discover`; refetch when < 3 cards remain
- `swipe(_:) async` → `POST /swipes`; read `isMatch` from response
- `undo() async` → `DELETE /swipes/{targetId}/{venueId}`
- **Remove** `startRealtimeSimulation()` and `simulatePresenceChange()` entirely
- **Add** WS handlers for `presence.join` / `presence.leave`
- **Add** heartbeat: `Task` sending `presence.ping` every 90s while checked in

### MatchesViewModel.swift changes
- `loadMatches() async` on init → `GET /matches`
- `openChat(for:)` → `GET /matches/{id}/messages` (cursor pagination) + `PUT .../read`
- `sendMessage()` → WS `message.send` with `tempId`; optimistic local message; replace on `message.ack`
- **Remove** `randomReplies`, all `DispatchQueue.asyncAfter` simulation
- **Add** WS handlers: `message.new`, `typing.start`, `typing.stop`, `match.created`

---

## Deployment Architecture

```
iOS App (SwiftUI)
    │
    ▼ HTTPS / WSS
Cloudflare  (CDN + DDoS protection + photo CDN)
    │
    ▼
Render Web Service  (Node.js backend · GitHub auto-deploys)
    ├── Fastify REST API
    ├── @fastify/websocket  (chat + presence)
    └── BullMQ Workers      (push notifications, presence expiry)
         │
         ├──► Supabase  (Postgres + Realtime + Storage)  ~$25/mo
         ├──► Upstash Redis  (presence, OTP, queue, rate limits)  ~$5/mo
         ├──► MSG91  (OTP SMS, India / +91)
         └──► APNs  (push notifications)
```

---

## Implementation Sequence

| Phase | Timeline | Deliverable |
|---|---|---|
| **1 — Auth + Profile** | Week 1–2 | OTP send/verify, JWT, profile CRUD, photo upload |
| **2 — Venues + Discovery** | Week 2–3 | Check-in/out, presence, discover query, swipe + match detection |
| **3 — Real-time Chat** | Week 3–4 | WebSocket server, messages, typing indicators, read receipts |
| **4 — Notifications + Safety** | Week 4–5 | APNs, push for matches/messages/superlikes, block/report |
| **5 — Scale (post-launch)** | Ongoing | Redis pub/sub for multi-replica WS, Cloudflare Images, analytics |

---

## Key Trade-offs

| Decision | Chosen | Rejected | Reason |
|---|---|---|---|
| OTP provider | MSG91 | Twilio | 70% cheaper on +91; legally required DLT compliance in India |
| Real-time chat | Custom WebSocket | Firebase Realtime DB | Full protocol control; no vendor lock-in |
| Venue presence broadcast | Supabase Realtime | Custom WebSocket | Zero backend code for broadcast events |
| Mutual like detection | Postgres stored function | App-level check | Atomic; race-safe; single DB round trip |
| Backend language | Node.js/TypeScript | Go / Elixir | Faster to ship; larger hiring pool |
| Hosting | Render | Railway / AWS ECS | Current deployment target; zero DevOps overhead at early stage |
