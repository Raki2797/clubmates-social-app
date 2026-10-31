# Match Polling Analysis
<!-- Repository documentation; excluded from runtime deployment. -->

## Problem

While running the iOS app against the local backend, the backend logs show repeated requests like:

```txt
GET /matches?limit=50&page=1
GET /swipes/incoming
GET /invites/incoming
```

These requests appear frequently and can look like backend health checks or random pings. They are not backend-generated pings. They are client-driven polling requests from the iOS app.

## Current Behavior

`MainTabView` starts a repeating task when the main app UI is active. That task calls `matchesViewModel.refreshMatchesNow()` immediately, then repeats every 5 seconds.

`refreshMatchesNow()` performs three backend calls:

```swift
await loadMatches()
await loadIncomingSwipes()
await loadIncomingTreatInvites()
```

Those map to:

```txt
GET /matches?limit=50&page=1
GET /swipes/incoming
GET /invites/incoming
```

Because the three requests run back-to-back every polling cycle, the backend log shows a cluster of three requests.

## Why It Exists

The polling keeps these screens fresh:

- active matches
- incoming likes
- incoming treat invites

The app also has WebSocket/realtime support in `MatchesViewModel`, so this polling acts as a fallback sync mechanism. It helps recover from missed realtime events, app resume, socket reconnects, or local cache drift.

## Why It Is a Problem

The current interval is aggressive.

At 5 seconds:

- 1 user sends 3 requests every 5 seconds
- around 36 requests per minute per active user
- around 2,160 requests per hour per active user

At scale, this becomes noisy and expensive.

Example if 5,000 users kept the app open:

- 180,000 requests per minute
- 10.8 million requests per hour

Real usage will be lower because not all users keep the app open at once, but the polling pattern can still create unnecessary backend load.

## How Top Apps Usually Handle This

Large-scale social, dating, and messaging apps usually do not depend on very frequent polling as the main update mechanism. They use a layered sync model:

1. Realtime events for immediate updates.
2. Local cache for fast screen rendering.
3. Delta sync to repair missed updates.
4. Push notifications for background or closed-app delivery.
5. Low-frequency polling only as a safety net.

This gives users a realtime experience without creating constant API load.

## Best Approach

The best approach for this app is:

```txt
WebSocket realtime first
Local cache second
Delta sync for correctness
Push notifications for background
Polling only as fallback
```

This means the app should not repeatedly ask the backend, "Anything new?" every few seconds. Instead, the backend should tell the app when something changes, and the app should occasionally verify state using lightweight sync.

## Recommended Architecture

### 1. Realtime as the Primary Path

Use WebSocket for events that need to appear quickly while the app is open.

Recommended realtime events:

- `match.created`
- `match.deleted`
- `message.created`
- `message.read`
- `swipe.received`
- `invite.received`
- `invite.accepted`
- `invite.declined`
- `user.online`
- `user.offline`

When one of these events arrives, the iOS app should update local state immediately instead of waiting for the next polling cycle.

Example:

```txt
User A likes User B
Backend stores swipe
Backend emits swipe.received to User B
iOS receives event
iOS updates incoming likes UI
No polling needed
```

### 2. Local Cache for Fast UI

The app should load matches, messages, and pending likes/invites from local storage first.

This gives the user instant UI even before the network finishes.

Recommended flow:

```txt
Open app
Show cached matches immediately
Connect WebSocket
Run delta sync once
Apply new server changes
```

The current app already has local chat storage, so this fits the existing direction.

### 3. Delta Sync for Correctness

Polling should not fetch full data every time. It should ask only for changes since the last known sync point.

Current app already has this idea for matches:

```txt
GET /matches?updatedSince=<timestamp>&limit=50&page=1
```

This should become the standard sync pattern.

Recommended delta endpoints:

```txt
GET /matches?updatedSince=<timestamp>
GET /swipes/incoming?updatedSince=<timestamp>
GET /invites/incoming?updatedSince=<timestamp>
GET /matches/:id/messages?since=<timestamp>
```

Each response should include:

```json
{
  "items": [],
  "serverTime": 1781890000000,
  "hasMore": false
}
```

The app stores `serverTime` as the next sync cursor.

### 4. Push Notifications for Background

When the app is backgrounded or closed, the app should not poll.

Use push notifications for important events:

- new match
- new message
- incoming like
- incoming treat invite
- invite accepted

Background behavior:

```txt
App closed/backgrounded
Backend sends push notification
User opens notification
App launches
App loads cache
App runs delta sync
```

This is how mobile apps avoid wasting battery and backend resources.

### 5. Polling Only as Fallback

Polling should remain, but only as a recovery mechanism.

It helps when:

- WebSocket disconnects
- app resumes after being inactive
- device network changes
- backend deploy restarts socket connections
- realtime event is missed

Recommended fallback polling:

```txt
WebSocket connected and healthy: every 60 seconds or no polling
WebSocket disconnected: every 20-30 seconds
Matches tab open: refresh immediately, then fallback every 60 seconds
Other tabs open: no match polling, or very low frequency
App backgrounded: no polling
```

## Recommended App Lifecycle Rules

### App Launch

```txt
1. Load cached matches/messages immediately.
2. Connect WebSocket.
3. Run one delta sync.
4. Start fallback polling only if needed.
```

### App Becomes Active

```txt
1. Reconnect WebSocket if needed.
2. Run one delta sync.
3. Resume lightweight fallback polling.
```

### App Goes Background

```txt
1. Stop polling.
2. Close or pause WebSocket if needed.
3. Rely on push notifications.
```

### Matches Tab Opens

```txt
1. Show cached matches.
2. Run one immediate delta sync.
3. Listen for WebSocket events.
4. Use 60-second fallback polling only while visible.
```

### Matches Tab Closes

```txt
1. Stop tab-specific polling.
2. Keep WebSocket alive only if needed for global banners.
3. Continue using push/realtime for critical events.
```

### Chat Screen Opens

```txt
1. Show cached messages.
2. Run one message delta sync.
3. Listen for message.created events.
4. Use 30-second fallback sync only while chat is open.
```

## Suggested Final Strategy

Use this combination:

```txt
Immediate refresh on app launch: yes
Immediate refresh on app active: yes
Immediate refresh when Matches tab opens: yes
WebSocket realtime updates: yes
Push notifications for background: yes
Delta sync after reconnect/resume: yes
Background polling: no
Fallback polling while WebSocket is healthy: every 60 seconds or disabled
Fallback polling while WebSocket is disconnected: every 20-30 seconds
Open chat message polling: every 30 seconds only while chat is open
```

## Suggested Implementation Phases

### Phase 1: Quick Fix

Reduce the current 5-second polling interval to 30 or 60 seconds.

Recommended MVP setting:

```txt
30 seconds
```

This keeps fallback sync while immediately reducing traffic by around 6x.

### Phase 2: Screen-Aware Polling

Only poll match-related APIs when the user is on the Matches tab or when the app becomes active.

Stop match polling when the user is on unrelated screens like Profile or Venue.

### Phase 3: WebSocket-First Flow

Make WebSocket events update the local store directly.

The app should not need to call all three endpoints after every realtime event. It should apply the event locally, then use delta sync only for recovery.

### Phase 4: Delta Sync Everywhere

Add `updatedSince` or cursor support to incoming swipes and incoming invites.

This avoids downloading full lists repeatedly.

### Phase 5: Push Notification Integration

Use push notifications for background delivery.

Once push is stable, background polling should be fully removed.

## Expected Impact

Moving from 5-second polling to 60-second fallback polling reduces match-related polling traffic by around 12x.

Current:

```txt
3 requests every 5 seconds
36 requests per minute per active user
```

With 60-second polling:

```txt
3 requests every 60 seconds
3 requests per minute per active user
```

This is much healthier for backend cost, logs, database load, and mobile battery usage.

With WebSocket-first updates and tab-aware polling, real traffic can be even lower because many refresh cycles become unnecessary.

## Conclusion

The repeated backend logs are expected from the current iOS polling design. They are not backend health checks.

The current 5-second polling interval is useful during development, but too aggressive for production.

The production-grade approach is:

```txt
WebSocket for realtime
Push notifications for background
Delta sync for correctness
Local cache for speed
Polling only as fallback
```
