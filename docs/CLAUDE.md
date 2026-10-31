# ClubMates — Project Context
<!-- Repository documentation; excluded from runtime deployment. -->

Venue-based dating/social discovery app. Users check in to a venue, discover and swipe people at the same spot in real time, match, and chat.

**GitHub:** https://github.com/Taarvyn/ClubMates  
**Git identity (local):** `Vikram <kadamvikram147@gmail.com>`  
**Branch:** `main`

## Repo Structure

```
ClubMates/
├── iOS/          — SwiftUI app (iOS 18.2+), MVVM
├── Android/      — Jetpack Compose app (min SDK 26), MVVM
├── Backend/      — Node.js 22 + TypeScript, Fastify REST + WebSocket
└── docs/         — Architecture, deployment, testing, and product guides
```

## iOS (`iOS/`)
- SwiftUI, iOS 18.2+
- ViewModels: `AppSessionStore`, `DiscoverViewModel`, `MatchesViewModel`
- `NetworkClient` fully wired to all REST endpoints
- New screens: `SelfieVerificationView`, stepped onboarding progress pills, welcome with login/create flows
- **Not yet done:** WebSocket client, photo uploads, Keychain token storage, APNs push

## Android (`Android/`)
- Jetpack Compose + Material3 dark theme, min SDK 26
- Hilt DI, Retrofit + OkHttp, Kotlinx Serialization
- `WebSocketClient` with exponential backoff reconnect
- `EncryptedSharedPreferences` for secure token storage
- **`MOCK_MODE = true`** in all repositories — flip to `false` to connect real backend
- Screens: Welcome → OTP → CreateProfile → VenuePicker → Discover (swipe cards) → Matches → Chat → Profile → EditProfile
- ViewModels: `AuthViewModel`, `DiscoverViewModel`, `MatchesViewModel`, `ProfileViewModel`
- Repositories: `AuthRepository`, `VenueRepository`, `DiscoverRepository`, `MatchesRepository`, `SafetyRepository`

## Backend (`Backend/`)
- Fastify REST API + WebSocket chat
- PostgreSQL (Supabase-hosted), Redis (Upstash), BullMQ job queue
- Phone OTP auth: MSG91 (primary, India DLT-compliant) + Twilio fallback
- JWT access token (15min) + opaque refresh token (30d, stored in Redis)
- Run: `cd Backend && npm install && npm run dev`
- `.env` is gitignored — copy from `.env.example`
- Android emulator URL: `http://10.0.2.2:3000`

## What's Next
- Wire Redis presence, rate limiting, OTP delivery (MSG91/Twilio)
- Photo uploads (Supabase Storage + Sharp EXIF stripping)
- FCM push notifications (Android) / APNs (iOS)
- Flip `MOCK_MODE = false` in Android and test end-to-end

## Separate Android repo (for independent hosting)
- Path: `/Users/vikram.kadam/Desktop/sm /Clubmate/ClubMate-android/`
- Has its own git repo with the same Android code + a copy of `Backend/`
- `.claude/` is gitignored in both repos
