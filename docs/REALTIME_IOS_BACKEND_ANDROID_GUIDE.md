# ClubMates Realtime Implementation
<!-- Repository documentation; excluded from runtime deployment. -->

## Purpose

This document records the realtime work completed in the ClubMates backend and
iOS app. It also defines how Android should implement the same behavior without
introducing periodic polling.

The main user-facing result is:

- Venue users appear and disappear quickly after check-in or checkout.
- Incoming likes and super likes are shown while the user is on any app screen.
- Mutual matches are shown immediately.
- Treat invites and accepted invites are shown immediately.
- New messages, read state, unmatches, safety changes, and online presence are
  delivered through the same realtime connection.
- REST APIs are used to save data and reconcile state.
- WebSocket events are used to notify connected clients.
- Local storage keeps the UI responsive and is cleared on sign-out.

Android should use this document as the implementation contract. It should not
copy iOS UI code, but it should match the lifecycle, event handling, and data
consistency behavior described here.

## Current Architecture

```text
User action
    |
    | REST mutation
    v
Fastify backend
    |
    | PostgreSQL transaction succeeds
    v
Backend realtime hub
    |
    | WebSocket event
    v
App-level realtime repository
    |
    +--> update in-memory state
    +--> update local database
    +--> show app-wide notification
    +--> run a one-time REST reconciliation when needed
```

The WebSocket is currently a server-to-client notification channel.

Actions such as swiping, sending an invite, accepting an invite, sending a
message, and checking in are still performed through authenticated REST APIs.
The backend broadcasts a WebSocket event only after the server operation has
succeeded.

## Environments

QA backend:

```text
https://139.59.25.255
```

QA WebSocket:

```text
wss://139.59.25.255/v1/ws?token=<access-token>
```

Local backend from the iOS Simulator:

```text
http://127.0.0.1:3000
ws://127.0.0.1:3000/v1/ws?token=<access-token>
```

Local backend from the Android Emulator:

```text
http://10.0.2.2:3000
ws://10.0.2.2:3000/v1/ws?token=<access-token>
```

`127.0.0.1` inside the Android Emulator points to the emulator itself, not the
Mac. Android must use `10.0.2.2` to reach a backend running on the development
machine.

For a physical Android device, use the Mac's LAN IP and ensure both devices are
on the same network.

## Backend Work Completed

### 1. Central authenticated WebSocket

The backend exposes:

```text
GET /v1/ws?token=<access-token>
```

Connection flow:

1. Read the JWT access token from the query string.
2. Verify the access token.
3. Register the connection under the authenticated user ID.
4. Send `connection.ready`.
5. Send `presence.snapshot`.
6. Broadcast `presence.update` to connected clients.

The client must not consider the socket ready until it receives
`connection.ready`.

### 2. Multiple connections per user

The realtime hub stores a set of connections for each user. This supports:

- multiple devices
- multiple app sessions
- temporary overlapping reconnects

An event is delivered to every open connection registered for the target user.

### 3. UUID normalization

All realtime user keys are converted to lowercase before insertion and lookup.

This fixed an important delivery bug:

```text
JWT user ID:       505f7fc3-...
Client/DB user ID: 505F7FC3-...
```

UUIDs are case-insensitive as identifiers, but JavaScript `Map` string keys are
case-sensitive. Without normalization, the backend could report zero
connections even while the user was online.

Android should also normalize UUID strings to lowercase when using them as map,
Room, cache, or deduplication keys.

### 4. Realtime delivery diagnostics

`broadcastToUser` now returns the number of successful deliveries and logs:

- target user ID
- event type
- registered connection count
- delivered connection count

Useful backend trace names:

```text
realtime.connected
realtime.disconnected
realtime.broadcast
swipe.request
swipe.transition
swipe.broadcast
swipe.withdrawn
```

### 5. Secure request logging

The Fastify request serializer removes the query string from logged URLs.

This is important because the WebSocket currently authenticates with:

```text
/v1/ws?token=<access-token>
```

The access token must never appear in normal server logs. Android logging must
also avoid printing the complete WebSocket URL.

### 6. Realtime venue presence

After check-in or checkout, the backend broadcasts
`venue.presence_changed` to active users at the affected venue.

This solves both ordering cases:

- User A is already checked in and User B checks in.
- User B checks in after User A and still immediately receives the correct
  venue roster after reconciliation.

The backend sends the event only after the database check-in state has been
updated.

### 7. Realtime swipe delivery

When User A likes or super likes User B, the backend broadcasts
`swipe.received` to User B with User A's compact profile.

The compact profile is included so the receiving app can render a useful
notification immediately without waiting for another profile request.

When a swipe is undone, the backend broadcasts `swipe.withdrawn`.

### 8. Realtime treat invite delivery

The backend broadcasts:

- `invite.received` when a pending invite is created.
- `invite.accepted` when an invite creates or confirms a match.

`invite.accepted` is sent to both participants and includes the other user's
compact profile whenever available.

### 9. Existing chat, safety, and presence events

The same realtime hub also carries:

- new messages
- message read state
- unmatches
- safety visibility changes
- online presence

### 10. Offline checkout grace period

When a user's last realtime connection closes, the backend schedules automatic
checkout after:

```text
OFFLINE_CHECKOUT_GRACE_MINUTES=20
```

If the user reconnects before the grace period ends, the pending checkout is
cancelled.

This means Android socket lifecycle quality affects venue presence. The app
should reconnect promptly after a temporary network change or foreground
transition.

## Realtime Event Contract

All messages are JSON objects with a required `type` field. Other fields depend
on the event.

The Android decoder should tolerate unknown fields and unknown event types so a
backend addition does not crash older app versions.

### Common compact profile

Events involving another user can include:

```json
{
  "id": "uuid",
  "name": "Sai Pavan",
  "age": 28,
  "bio": "",
  "profession": "Architect",
  "gender": "Male",
  "height": 178,
  "interests": ["Music", "Travel"],
  "isVerified": true,
  "isGhostMode": false,
  "photoUrl": "https://...",
  "distance": 0,
  "hasSuperLikedMe": false,
  "lookingFor": ""
}
```

Use the backend response as the source of truth. Do not fail the whole event if
an optional profile field is absent.

### `connection.ready`

Sent immediately after authentication and registration.

```json
{
  "type": "connection.ready",
  "userId": "uuid"
}
```

Android action:

- Mark the socket as ready.
- Cancel the handshake timeout.
- Run one interaction reconciliation:
  - `GET /matches`
  - `GET /swipes/incoming`
  - `GET /invites/incoming`

This recovers events that occurred while the socket was disconnected.

### `presence.snapshot`

```json
{
  "type": "presence.snapshot",
  "userIds": ["uuid-1", "uuid-2"]
}
```

Android action:

- Replace the in-memory online-user set.
- Normalize all UUID keys to lowercase.

### `presence.update`

```json
{
  "type": "presence.update",
  "userId": "uuid",
  "online": true
}
```

Android action:

- Add or remove the user from the online-user set.

### `venue.presence_changed`

```json
{
  "type": "venue.presence_changed",
  "venueId": "uuid",
  "userId": "uuid",
  "status": "checked_in"
}
```

`status` is either:

```text
checked_in
checked_out
```

Android action:

1. Ignore the event if the user is not currently viewing or checked into the
   affected venue.
2. If it is the active venue, run one refresh of:
   - `GET /venues/:id/roster`
   - `GET /venues/:id/discover`
3. Serialize refreshes so multiple events do not start overlapping requests.
4. If another event arrives during a refresh, run one more refresh afterward.

Do not wait 30 seconds and do not add a venue polling loop.

### `swipe.received`

```json
{
  "type": "swipe.received",
  "profile": {},
  "direction": "like",
  "isMatch": false,
  "matchId": null,
  "venueId": "uuid"
}
```

`direction` can be:

```text
like
superlike
```

Android action:

- Upsert the incoming interaction by `profile.id`.
- If `isMatch` is `false`, show an app-wide incoming-like notification.
- If `isMatch` is `true`, remove pending-like state, upsert the match, and show
  the match experience.
- Run a debounced one-time reconciliation.
- Include `GET /matches` in reconciliation when `isMatch` is `true`.

The user must receive this notification from Venue, Matches, Chat, or Profile.
Do not collect this event only inside the Matches screen.

### `swipe.withdrawn`

```json
{
  "type": "swipe.withdrawn",
  "userId": "uuid",
  "venueId": "uuid"
}
```

Android action:

- Remove the pending incoming swipe for `userId`.
- Remove any non-match notification card for that user.
- Dismiss a visible one-way-like banner for that user.

### `invite.received`

```json
{
  "type": "invite.received",
  "inviteId": "uuid",
  "venueId": "uuid",
  "treatType": "coffee",
  "intent": "If we both meet and vibe, I am open to this treat.",
  "createdAt": "2026-06-24T00:00:00.000Z",
  "profile": {}
}
```

Android action:

- Upsert the pending invite by the sender profile ID.
- Show an app-wide treat-invite notification.
- Run a debounced one-time incoming interactions reconciliation.

Use the existing backend/API enum values for `treatType`; do not create a
separate Android-only mapping.

### `invite.accepted`

```json
{
  "type": "invite.accepted",
  "inviteId": "uuid",
  "matchId": "uuid",
  "status": "accepted",
  "venueId": "uuid",
  "createdAt": "2026-06-24T00:00:00.000Z",
  "profile": {}
}
```

Possible `status` values currently include:

```text
accepted
accepted_by_like
accepted_by_invite_back
```

Android action:

- Remove the pending invite and pending swipe for this user.
- Upsert the match immediately when `matchId` and `profile` are present.
- Show the app-wide match experience once.
- Reconcile matches and pending interactions.

### `message.created`

```json
{
  "type": "message.created",
  "message": {
    "id": "uuid",
    "matchId": "uuid",
    "body": "Hello",
    "isFromMe": false,
    "senderId": "uuid",
    "isRead": false,
    "createdAt": "2026-06-24T00:00:00.000Z"
  }
}
```

Android action:

- Upsert the message into Room.
- Update the match preview and timestamp.
- Increase unread state when the conversation is not currently open.
- Update the visible conversation immediately when it is open.

### `messages.read`

```json
{
  "type": "messages.read",
  "matchId": "uuid",
  "readerId": "uuid",
  "upToMessageId": "uuid"
}
```

`upToMessageId` can be `null`.

Android action:

- Update Room and current UI read state for the match.

### `match.unmatched`

```json
{
  "type": "match.unmatched",
  "matchId": "uuid"
}
```

Android action:

- Remove the match and its messages from Room and memory.
- Close the chat if that match is open.

### `safety.hidden_users_updated`

```json
{
  "type": "safety.hidden_users_updated"
}
```

Android action:

- Refresh hidden users.
- Remove hidden users from discovery, pending interactions, matches, and
  visible profile UI.

## REST Reconciliation Contract

Realtime events are intentionally ephemeral. If the app is disconnected, it
can miss them. Correctness therefore comes from a one-time REST reconciliation
at lifecycle boundaries.

Use:

```text
GET /matches
GET /swipes/incoming
GET /invites/incoming
```

Run this reconciliation:

- after `connection.ready`
- after app foreground/resume
- after network connectivity returns
- after token refresh and socket reconnection
- when the user enters Matches or Chat, if a fresh screen load is needed
- after an event that requires authoritative server state

Do not run these endpoints on a repeating timer.

Debounce event-triggered reconciliation for about 250 ms so a burst of related
events produces one REST sync instead of several duplicate syncs.

## iOS Work Completed

### Single app-level realtime owner

`MatchesViewModel` owns the socket for the authenticated main app experience.
It is created at `MainTabView`, above individual screens.

This fixed the original problem where incoming likes were noticed only after
the user opened Matches or Chat.

Android should follow the same ownership principle:

```text
Application/authenticated activity scope
    owns RealtimeRepository

Individual screen ViewModels
    observe shared StateFlow/SharedFlow
    do not create separate sockets
```

### Socket lifecycle

iOS currently implements:

- connect before initial REST loading
- 10-second `connection.ready` handshake timeout
- WebSocket ping every 20 seconds
- reconnect about 2 seconds after disconnect
- foreground health check
- network-path recovery
- cleanup on sign-out

Android should implement equivalent behavior with OkHttp WebSocket,
`ProcessLifecycleOwner`, and `ConnectivityManager`.

### App-wide notifications

iOS uses a window-level overlay above sheets and tab content. This allows a
like, super like, invite, or match to appear while the user is on:

- Venue
- Matches
- Chat
- Profile
- a presented sheet

Android should use one app-level UI event host, such as:

- a root Compose `Scaffold` snackbar/banner host
- a root overlay in the authenticated Activity
- a full-screen match dialog controlled by app-level state

Do not let each screen independently consume the same event. That causes missed
notifications, duplicate banners, or behavior that depends on the selected tab.

Recommended Android split:

```text
StateFlow
    durable screen state: matches, invites, incoming likes, online users

SharedFlow or Channel
    one-time UI effects: show banner, show match dialog, navigate on tap
```

### Duplicate notification prevention

iOS tracks which incoming-like users and matched users have already been
announced.

Android should also deduplicate using normalized user IDs and match IDs.

Important rules:

- Initial REST load populates state but should not announce every old item.
- A newly received realtime event may announce once.
- Reconciliation must not announce the same item again.
- Removing or resolving an interaction should clear its deduplication state
  where appropriate.

### Local cache consistency

iOS keeps matches and messages in SQLite. Server refreshes replace or upsert
local rows, and realtime messages update the cache immediately.

On sign-out, iOS clears:

- socket and reconnect tasks
- pending interaction state
- online presence state
- match/message SQLite data
- profile/session state

Android should clear the equivalent Room tables and in-memory state on sign-out.
Otherwise deleted server data can remain visible from a previous local session.

### Venue refresh serialization

iOS prevents concurrent roster/discovery reloads:

- one refresh runs at a time
- an event arriving during refresh sets a pending flag
- one additional refresh runs after the first finishes

Android should implement this with a `Mutex`, actor/channel, or equivalent
single-flight mechanism.

### Polling removed

The following repeating network polling was removed:

- five-second matches/swipes/invites polling
- thirty-second matches/swipes/invites fallback polling
- thirty-second venue roster/discovery polling
- thirty-second open-chat message polling

The app still performs one-time REST loads at startup, foreground, reconnect,
and relevant navigation boundaries.

iOS also has a local 30-second GPS auto-checkout check. It does not call the
backend every 30 seconds unless checkout is actually required. This is not
server polling.

Android must not add a repeating API loop to simulate realtime.

## Android Recommended Structure

### Core classes

```text
RealtimeRepository
    owns OkHttp WebSocket
    authenticates and reconnects
    parses events
    exposes connection state

RealtimeEventRouter
    applies each event to repositories
    emits one-time UI effects

MatchesRepository
    REST + Room source of truth for matches/messages

InteractionsRepository
    pending swipes and treat invites

VenueRepository
    venues, active venue, roster, discovery queue

AppNotificationCoordinator
    app-wide banners and match dialog
```

The exact names can follow the existing Android architecture, but ownership
must remain app-scoped.

### Suggested event model

```kotlin
@Serializable
data class RealtimeEnvelope(
    val type: String,
    val message: ApiMessage? = null,
    val matchId: String? = null,
    val readerId: String? = null,
    val upToMessageId: String? = null,
    val userId: String? = null,
    val online: Boolean? = null,
    val userIds: List<String>? = null,
    val profile: ApiUserProfile? = null,
    val direction: String? = null,
    val isMatch: Boolean? = null,
    val venueId: String? = null,
    val inviteId: String? = null,
    val treatType: TreatType? = null,
    val intent: String? = null,
    val createdAt: Instant? = null,
    val status: String? = null
)
```

If the Android project uses Moshi or Gson instead of Kotlin Serialization, use
the existing project convention.

### Suggested connection lifecycle

```text
User becomes authenticated
    -> ensure a valid access token
    -> open one WebSocket
    -> start 10-second handshake timeout

connection.ready
    -> mark READY
    -> cancel handshake timeout
    -> run one REST reconciliation

Every 20 seconds while foreground and connected
    -> WebSocket ping

Socket failure/close
    -> mark DISCONNECTED
    -> schedule reconnect

App foreground
    -> verify socket health
    -> reconnect if needed
    -> run one REST reconciliation

Network restored
    -> reconnect
    -> run one REST reconciliation after ready

Sign-out
    -> close socket
    -> cancel all jobs
    -> clear Room and in-memory authenticated state
```

Ensure only one reconnect job can exist at a time.

### Suggested OkHttp outline

```kotlin
class RealtimeRepository(
    private val okHttpClient: OkHttpClient,
    private val tokenStore: TokenStore
) {
    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null

    suspend fun connect() {
        if (webSocket != null) return

        val token = tokenStore.validAccessToken()
        val request = Request.Builder()
            .url("$webSocketBaseUrl/v1/ws?token=${token.urlEncode()}")
            .build()

        // Never log request.url because it contains the JWT.
        webSocket = okHttpClient.newWebSocket(request, listener)
    }

    fun disconnect() {
        reconnectJob?.cancel()
        reconnectJob = null
        webSocket?.close(1000, "Signed out")
        webSocket = null
    }
}
```

The current backend reads the token from the query parameter. If the backend is
later changed to support an `Authorization` header or a short-lived WebSocket
ticket, Android and iOS should migrate together.

## Android Event Handling Rules

| Event | Immediate local action | REST reconciliation |
|---|---|---|
| `connection.ready` | Mark socket ready | Matches + swipes + invites |
| `presence.snapshot` | Replace online set | None |
| `presence.update` | Update one online user | None |
| `venue.presence_changed` | Mark active venue stale | Roster + discover |
| `swipe.received` | Upsert card, show banner/match | Swipes + invites; matches if mutual |
| `swipe.withdrawn` | Remove pending like | Usually none |
| `invite.received` | Upsert invite, show banner | Swipes + invites |
| `invite.accepted` | Resolve pending state, upsert match | Matches + swipes + invites |
| `message.created` | Upsert Room message | None normally |
| `messages.read` | Update Room read state | None |
| `match.unmatched` | Delete local match/messages | None |
| `safety.hidden_users_updated` | Hide unsafe users immediately | Hidden users + affected screens |

## Android Implementation Order

1. Create the shared realtime event DTO and tolerant JSON decoder.
2. Add one authenticated `RealtimeRepository` using OkHttp WebSocket.
3. Implement handshake timeout, ping, reconnect, foreground, and connectivity
   handling.
4. Add a central event router.
5. Implement presence events.
6. Implement venue presence refresh with single-flight protection.
7. Implement incoming swipe, withdrawal, and app-wide like notification.
8. Implement invite received and invite accepted.
9. Connect message, read, unmatch, and safety events to Room.
10. Add REST reconciliation at connection and lifecycle boundaries.
11. Clear Room and realtime state on sign-out.
12. Confirm there are no periodic match, interaction, venue, or chat API loops.

## Required Android Test Matrix

### Socket and lifecycle

- Login opens exactly one WebSocket.
- `connection.ready` triggers one reconciliation.
- App background and foreground preserve or restore the connection.
- Network loss followed by recovery reconnects.
- A reconnect does not create duplicate sockets or duplicate collectors.
- Sign-out closes the socket and clears local data.

### Venue presence

- User A checks in first, then User B checks in.
- User A immediately sees User B.
- User B immediately sees User A.
- Checkout removes the user from the other device.
- Rapid check-in events do not start overlapping roster refreshes.

### Likes and matches

- User A likes User B while B is on Venue.
- Repeat while B is on Matches.
- Repeat while B is on Chat.
- Repeat while B is on Profile.
- B sees one notification in every case.
- A mutual like shows a match to both users.
- Undo removes the pending like from the receiver.
- Reconciliation does not show the same banner twice.

### Treat invites

- Invite appears while receiver is on every main screen.
- Accept creates a match for both users.
- Invite-back creates a match for both users.
- Like-on-invite creates a match for both users.
- Pending invite state is removed after acceptance.

### Messages and safety

- Message appears in an open chat without polling.
- Message updates unread count while another screen is open.
- Read state updates for the sender.
- Unmatch removes the conversation.
- Block/report removes hidden users from relevant UI.

### Local cache

- Cached matches render before network completion.
- Server-deleted matches disappear after reconciliation.
- Sign-out clears Room so another account cannot see stale data.

### Network request audit

With the app left idle for at least one minute:

- no repeating `/matches` calls
- no repeating `/swipes/incoming` calls
- no repeating `/invites/incoming` calls
- no repeating venue roster/discovery calls
- no repeating chat message calls

WebSocket ping frames are expected and are not REST polling.

## Useful Debug Logging

Android debug logs should include:

```text
[RealtimeTrace] connecting
[RealtimeTrace] connection.ready
[RealtimeTrace] disconnected reason=<safe reason>
[RealtimeTrace] reconnect scheduled
[RealtimeTrace] received type=swipe.received
[RealtimeTrace] received type=venue.presence_changed
[RealtimeTrace] reconciliation started reason=<reason>
[RealtimeTrace] reconciliation completed
[OverlayTrace] showing incoming-like user=<uuid>
```

Never log:

- JWT access tokens
- refresh tokens
- complete WebSocket URLs containing `token=`
- OTP values
- private user message bodies in production logs

Backend delivery can be checked with:

```text
trace=realtime.broadcast
eventType=swipe.received
connectionCount=1
deliveredCount=1
```

If `connectionCount` is zero:

1. Confirm the receiving app has completed `connection.ready`.
2. Confirm it did not create and immediately discard its app-level repository.
3. Confirm reconnect has not been cancelled by screen navigation.
4. Confirm user IDs are normalized consistently.

## Files Changed for This Work

Backend:

```text
Backend/src/app.ts
Backend/src/realtime/chatHub.ts
Backend/src/routes/discovery.ts
Backend/src/routes/invites.ts
Backend/src/routes/venues.ts
Backend/tests/unit/chat-hub.test.ts
```

iOS:

```text
iOS/ClubMates/Networking/NetworkClient.swift
iOS/ClubMates/ViewModels/AppSessionStore.swift
iOS/ClubMates/ViewModels/DiscoverViewModel.swift
iOS/ClubMates/ViewModels/MatchesViewModel.swift
iOS/ClubMates/Views/Discover/DiscoverView.swift
iOS/ClubMates/Views/MainTabView.swift
iOS/ClubMates/Views/Matches/MatchesView.swift
iOS/ClubMatesUnitTests/ClubMatesUnitTests.swift
```

## Backend Tests Added

Realtime hub coverage includes:

- offline checkout after the grace period
- cancellation of pending checkout after reconnect
- online presence broadcasting
- stale connection pruning
- closing all sockets on sign-out
- removing disconnected users from recipients
- UUID case-insensitive delivery
- unknown-user disconnect as a no-op

The UUID casing regression test is especially important and should remain.

## Current Limitations and Next Steps

### Background and terminated app delivery

WebSockets provide foreground realtime behavior. A backgrounded or terminated
Android app may not keep a reliable socket.

The future production solution is FCM push notification delivery for:

- incoming like
- super like
- match
- treat invite
- new message

On push open or app resume, Android should run the same REST reconciliation.

### Multiple backend instances

The current connection registry is stored in the Node.js process memory. This
works for the current single backend instance.

Before horizontally scaling to multiple backend containers, add a shared
pub/sub layer such as Redis so an event received by backend instance A can
reach a WebSocket connected to backend instance B.

### WebSocket authentication

The current query-token approach works and server logs now strip query strings.
For a stronger long-term design, consider a short-lived WebSocket ticket or an
authentication mechanism that does not place the access token in the URL.

## Final Android Definition of Done

Android is complete when:

- it maintains one authenticated app-level WebSocket
- all documented events are safely decoded
- venue presence updates both check-in ordering cases immediately
- likes, matches, and invites notify the user from every main screen
- Room and in-memory state remain consistent with the server
- reconnect and foreground flows run one-time reconciliation
- sign-out clears all authenticated local state
- backend logs show no periodic REST polling while the app is idle
- two-device testing passes the full matrix above
