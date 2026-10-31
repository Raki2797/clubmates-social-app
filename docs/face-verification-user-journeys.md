# Face Verification — User Journeys

---

## Journey 1: Unverified user with 3 existing photos

```
Profile screen
    ↓
"Get Verified" banner visible (isVerified = false)
    ↓
User taps banner → SelfieVerificationView opens
    ↓
Camera turns on (front-facing), face oval guide shown
    ↓
User taps "Capture Photo" button
    ↓
Photo captured, blink detection starts automatically
    → EAR-based detection (scale-invariant eye aspect ratio, threshold 0.2)
    → Warmup: 8 open frames with noise tolerance (up to 2 flicker frames allowed)
    → Detects blink: 2+ consecutive closed frames followed by reopen
    → 15-second timeout → "Retry Blink Detection" button + tips shown
    ↓
User blinks once → "Blink Detected!" overlay
    ↓
POST /users/me/verification-selfie
    → selfie stored in Supabase (verification-selfies/{userId}.jpg)
    → is_verified = false, verification_selfie_url saved
    → selfie_embedding_jobs record enqueued (async extraction)
    → { ok: true, selfieUrl } returned to iOS immediately
    ↓
iOS shows "Verifying your identity..." spinner
iOS polls GET /users/me every 15s (4 attempts, 60s total)
    ↓
Background pipeline starts (embedding worker polls every 5s):
    ↓
    1. Selfie embedding extraction
       → downloads selfie from CDN
       → extract_embedding.py (VGG-Face, first face only)
       → saves to users.face_embedding
       → if no face detected: job marked failed, no verification runs
    ↓
    2. backfillUserPhotoEmbeddings()
       → finds profile_photos WHERE face_embeddings IS NULL
       → Photo 1: NULL → download from CDN → extract all faces → store embeddings ✓
       → Photo 2: NULL → download from CDN → extract all faces → store embeddings ✓
       → Photo 3: NULL → download from CDN → extract all faces → store embeddings ✓
       → (if embeddings already exist on a photo, it is skipped)
    ↓
    3. verifyUserAgainstProfilePhotos()
       → loads all profile_photos WHERE face_embeddings IS NOT NULL AND face_count > 0
       → checks each photo individually against selfie embedding:

           Photo 1 (solo):          best distance = 0.31 < 0.68 ✓
           Photo 2 (group, 3 faces): best distance = 0.29 < 0.68 ✓
           Photo 3 (solo):          best distance = 0.34 < 0.68 ✓
           mismatchedPhotoIds = []
           → UPDATE users SET
               is_verified = true,
               verification_failure_reason = NULL,
               verification_mismatched_photo_ids = []

           ── OR ──

           Photo 3 (different person): best distance = 0.81 ≥ 0.68 ✗
           mismatchedPhotoIds = [photo3.id]
           → UPDATE users SET
               is_verified = false,
               verification_failure_reason = 'photo_mismatch',
               verification_mismatched_photo_ids = [photo3.id]
    ↓
iOS poll detects is_verified = true  OR  verificationFailureReason != nil
    ↓
    ✅ is_verified = true
        → Done screen shown
        → Verified badge appears on profile
        → "Get Verified" banner disappears

    ❌ verification_failure_reason = 'photo_mismatch'
        → Failed screen shown
        → Card: "Some photos appear to show a different person"
        → Badge: "1 photo needs to be replaced"
        → Button: "Update Photos"
              → Sheet dismissed → Edit Profile opens
              → User replaces Photo 3
              → Photo upload clears face_embeddings = NULL, enqueues embedding job
              → Worker extracts embeddings for new Photo 3 (~5s)
              → Worker triggers re-verification automatically
              → All photos pass → is_verified = true → banner disappears ✅
```

---

## Journey 2: Already verified user adds a new photo (re-verify)

```
User is verified (is_verified = true, badge shown on profile)
    ↓
User opens Edit Profile → uploads new Photo 4
    ↓
POST /users/me/photos
    → Photo 4 saved to Supabase storage
    → profile_photos row upserted:
          face_embeddings = NULL   ← cleared immediately (stale data gone)
          face_count      = NULL
    → embedding_jobs record inserted for Photo 4
    → { ok: true } returned immediately
    ↓
~5 seconds later: embedding worker polls embedding_jobs
    ↓
    Worker picks up job for Photo 4
    → Downloads Photo 4 from its CDN url
    → extract_embedding.py runs (all-faces mode)
          → Solo photo   → 1 embedding extracted
          → Group photo  → N embeddings extracted (one per detected face)
          → No face      → face_count = 0, face_embeddings = []
    → UPDATE profile_photos SET face_embeddings = [...], face_count = N
    → Job marked completed
    ↓
    Worker looks up user_id from profile_photos
    → Checks users.face_embedding (selfie present? yes)
    → Triggers verifyUserAgainstProfilePhotos()
        ↓
        Checks every photo individually:

            ✅ All pass — Photo 4 belongs to same person
            Photo 1 → distance 0.31 ✓
            Photo 2 → distance 0.29 ✓
            Photo 3 → distance 0.34 ✓
            Photo 4 → distance 0.27 ✓
            mismatchedPhotoIds = []
            → is_verified stays true
            → No visible change to user

            ── OR ──

            ❌ Photo 4 is a different person
            Photo 4 → distance 0.79 ≥ 0.68 ✗
            mismatchedPhotoIds = [photo4.id]
            → is_verified = false
            → verification_failure_reason = 'photo_mismatch'
            → verification_mismatched_photo_ids = [photo4.id]
            ↓
        Next time user opens Profile screen:
            → is_verified = false → "Get Verified" banner reappears
            → User taps banner → selfie flow begins
            → backfill is instant (Photos 1–3 already have embeddings)
            → Only Photo 4 fails → "1 photo needs to be replaced"
            → User replaces Photo 4 → re-verification runs → passes ✅
```

---

## Blink Detection Details

| Parameter | Value | Rationale |
|---|---|---|
| Detection method | Eye Aspect Ratio (EAR) | Scale-invariant; works across distances and face sizes |
| EAR threshold | 0.2 | Below = eyes closed; above = eyes open |
| Warmup frames required | 8 consecutive open (~270ms) | Ensures face is settled before watching |
| Warmup noise tolerance | 2 frames | Prevents Vision flicker from stalling warmup |
| Minimum closed streak | 2 frames (~67ms) | Fast blinkers succeed; EAR stability prevents false positives |
| Timeout | 15 seconds | Shows retry button + troubleshooting tips |
| Indeterminate frames | Skipped (nil) | Missing landmarks don't break open/closed streak counts |

---

## Edge Cases

| Situation | What happens |
|---|---|
| No face detected in selfie embedding extraction | Job marked failed; no verification runs; user sees timeout → can retry from profile |
| User has no profile photos yet | `skipped/no_face_in_any_photo` — verification deferred until photos are added |
| All profile photos have no detectable face (landscapes, pets) | `skipped/no_face_in_any_photo` — user is asked to add a photo of themselves |
| New photo has no detectable face | `face_count = 0`, not checked against selfie — existing verification status unchanged |
| Photo download fails during backfill | That photo is skipped with a warning log; remaining photos still processed |
| Embedding worker crashes mid-job | `attempts` counter incremented; job retried on next poll (up to 3 attempts) |
| User deletes a mismatched photo | `profile_photos` row deleted → re-verify runs on next poll → may now pass |
| User replaces a mismatched photo | Old embeddings cleared immediately; new job queued; worker re-verifies when done |
| Polling times out (60s) without result | User sees done screen; verification completes in background; banner disappears on next profile refresh |
| Blink detection fails (15s timeout) | Retry button shown with tips ("better lighting, hold face steady"); user can retry unlimited times |
| Vision can't detect eye landmarks | Frame skipped as indeterminate; doesn't break blink state machine |
