# Face Verification — Full Rewrite

**Audience:** Product Team · Backend Team  
**Feature:** Account verification via face matching  
**Status:** Implemented, pending migration + deploy

---

## Why We Rewrote This

### The old system had three problems

**1. Clunky two-step UX**  
The user had to take a selfie, review it, tap Continue, then record a video for the blink check. Two separate camera interactions felt unnecessary and slowed down onboarding.

**2. Verification logic was split between the app and the server**  
The iOS app was doing the face comparison math locally in Swift using the embedding it fetched from the server. This meant:
- The comparison logic existed in two places (Swift + TypeScript)
- Results were not auditable on the backend
- The app had to download raw embedding vectors (4096 floats) over the network

**3. Group photos broke verification**  
If a user uploaded a group photo, the old system picked just one face arbitrarily (usually the largest one in the frame). That face might not be the user. At verification time, the selfie would be compared to the wrong person — causing a false rejection even when the user was genuinely real.

---

## What the New System Does

### For the user (product perspective)

The verification screen is now a **single step**:

```
Open verification screen
  → Camera turns on automatically
  → "Blink to verify you're real" prompt appears
  → User blinks once
  → "Uploading…" → "Verifying your identity…"
  → Done ✅
```

The photo is captured **silently in the background** the moment the face is stable — the user never taps a camera button. The only action required from the user is the blink, which proves they are a real live person and not a printed photo.

**Before:** Take selfie → Review → Tap Continue → Blink  
**After:** Look at camera → Blink

---

### For the backend team (technical perspective)

The system now works in two independent pipelines:

---

#### Pipeline 1 — Profile photo upload (happens when user uploads any photo)

```
User uploads photo
       ↓
Photo saved to Supabase storage
Profile photo row saved to DB
Response returned to user immediately ← user sees success
       ↓  (background, non-blocking)
embedding_jobs record inserted
       ↓  (worker polls every 5 seconds)
Worker downloads photo from CDN url
Worker runs extract_embedding.py (all faces mode)
       ↓
If group photo → multiple embeddings extracted, one per face
If solo photo  → one embedding extracted
If no face     → face_count = 0, nothing stored
       ↓
profile_photos row updated:
  face_embeddings = [[...emb1...], [...emb2...]]
  face_count      = 2
```

**Key point:** The upload endpoint returns instantly. Embedding extraction happens asynchronously in the background. This keeps upload fast regardless of how long face detection takes.

**Photo replacement handling:** When a user replaces a photo at the same position, the old embeddings are cleared immediately (`face_embeddings = NULL`) before the new job is queued. This ensures stale embeddings from the previous photo never contribute to verification.

---

#### Pipeline 2 — Selfie verification (happens when user completes the blink check)

```
User blinks → app uploads selfie JPEG
       ↓
POST /users/me/verification-selfie
       ↓
1. Selfie stored in Supabase (verification-selfies bucket)
2. extract_embedding.py run with --first-only flag
     → 422 error returned if no face detected in selfie
     → selfie embedding stored on users.face_embedding
       ↓
3. Load all profile_photos for this user where face_embeddings IS NOT NULL
4. Flatten into one big list of candidate vectors
     e.g. photo1 has 1 face, photo2 has 3 faces → 4 candidates total
       ↓
5. Compute cosine distance: selfie_embedding vs each candidate
6. Take the best (lowest) distance across all candidates
       ↓
7. If best distance < 0.68 threshold → is_verified = true
   If best distance ≥ 0.68           → is_verified = false
       ↓
Response returned to app: { ok: true }
App polls GET /users/me every 3s until isVerified flips
```

**Key point:** Verification passes if **any single face** across **any profile photo** matches the selfie. A user with 5 photos where 3 are group photos and 1 is solo — only the solo photo needs to match.

---

## How Group Photos Are Handled

This is the core improvement. Here is the before/after:

| Scenario | Old system | New system |
|---|---|---|
| Solo photo (1 face) | Extracts 1 embedding ✓ | Extracts 1 embedding ✓ |
| Group photo (3 faces) | Picks 1 face arbitrarily — may be wrong person ✗ | Extracts all 3 embeddings ✓ |
| Photo with no face | May error or pick garbage ✗ | Stores face_count = 0, skipped at verification ✓ |
| User has mix of solo + group | Only first photo compared ✗ | All faces across all photos compared ✓ |

**Example:**

```
User has 3 profile photos:
  Photo A — solo selfie         → 1 embedding stored
  Photo B — group photo (3 ppl) → 3 embeddings stored (all 3 faces)
  Photo C — landscape, no face  → face_count = 0, skipped

At verification time:
  Selfie embedding compared against: [A_emb, B_emb1, B_emb2, B_emb3]
  Best match: A_emb at distance 0.31 → verified ✅
```

---

## The Background Worker

The embedding worker is an in-process job queue backed by Postgres (no Redis, no external queue service needed).

**How it works:**
- On server startup, a polling loop starts (every 5 seconds)
- It reads up to 5 pending jobs at a time from the `embedding_jobs` table
- Each job gets up to 3 attempts before being marked permanently failed
- Failed jobs are logged with the photo ID for manual investigation
- On server shutdown, the worker stops cleanly

**Why Postgres instead of a dedicated queue (e.g. Redis/BullMQ)?**  
The project already uses Postgres for everything. Adding Redis purely for a job queue would be operational overhead with no real benefit at this traffic level. The `embedding_jobs` table achieves the same result — jobs survive server restarts, retry on failure, and are visible in the DB for debugging.

---

## Database Changes

Two migrations need to be run **in order** before deploying:

### Migration 018 — `profile_photos` table
```sql
ALTER TABLE profile_photos
  ADD COLUMN face_embeddings JSONB,    -- array of embedding arrays, one per face
  ADD COLUMN face_count      SMALLINT; -- 0 = no face, 1 = solo, 2+ = group
```
`NULL` means the worker hasn't processed this photo yet.

### Migration 019 — `embedding_jobs` table (new)
```sql
CREATE TABLE embedding_jobs (
  id           UUID PRIMARY KEY,
  photo_id     UUID REFERENCES profile_photos(id) ON DELETE CASCADE,
  cdn_url      TEXT NOT NULL,
  attempts     SMALLINT DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,  -- set when done
  failed_at    TIMESTAMPTZ,  -- set after max retries
  UNIQUE(photo_id)            -- one job per photo at a time
);
```

---

## Files Changed

### Backend
| File | What changed |
|---|---|
| `scripts/extract_embedding.py` | Now returns all faces; added `--first-only` flag |
| `migrations/018_profile_photo_embeddings.sql` | New columns on `profile_photos` |
| `migrations/019_embedding_jobs.sql` | New job queue table |
| `src/services/faceVerification.ts` | Added `extractAllFaceEmbeddings`, `bestMatchAcrossEmbeddings`, `verifyUserAgainstProfilePhotos` |
| `src/services/embeddingWorker.ts` | New — background worker |
| `src/routes/users.ts` | Photo upload enqueues job; selfie upload triggers async verification |
| `src/app.ts` | Registers the embedding worker on startup |

### iOS
| File | What changed |
|---|---|
| `Views/SelfieVerificationView.swift` | Removed manual photo step; auto-capture on face stable; added `pendingVerification` polling step |
| `ViewModels/AppSessionStore.swift` | Replaced `completeVideoVerification` with `uploadAndPollVerification`; removed all client-side embedding/comparison code |
| `Views/Profile/ProfileView.swift` | Removed debug Extract/Compare buttons |

---

## Deployment Checklist

1. Run migration `018_profile_photo_embeddings.sql`
2. Run migration `019_embedding_jobs.sql`
3. Deploy backend — worker starts automatically on server boot
4. Deploy iOS build
5. **Existing users:** their profile photos have no embeddings yet. When they next upload a new photo it will be queued. Their old photos will not be auto-processed unless we run a backfill job separately.

---

## Edge Cases Handled

| Situation | Behaviour |
|---|---|
| User uploads selfie before any profile photo embeddings are ready | `verifyUserAgainstProfilePhotos` returns `skipped/no_face_in_any_photo`; `is_verified` stays false; user can re-trigger by refreshing |
| No face detected in selfie | 422 returned immediately; user prompted to try again |
| Embedding worker crashes mid-job | `attempts` counter incremented; job retried on next poll cycle |
| User deletes a profile photo | `profile_photos` row deleted → `embedding_jobs` row cascade-deleted automatically |
| User replaces a photo | Old embeddings cleared immediately; new job enqueued |
| User has only group photos | All faces from all photos are candidates; passes if the user's face appears in any of them |
