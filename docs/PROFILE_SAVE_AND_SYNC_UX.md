# Profile Save and Sync UX
<!-- Repository documentation; excluded from runtime deployment. -->

## Purpose

This document explains why ClubMates removed the visible profile sync status,
how profile saving works now, and how the experience follows common patterns
used by leading dating apps.

It is both a product decision and an implementation contract. Future iOS and
Android work should preserve the behavior described here.

## Previous Experience

The profile screen previously displayed one of these messages:

```text
Synced just now
Syncing...
Not synced
```

These messages represented the internal state of the profile save system:

- `synced`: the backend confirmed the latest profile.
- `syncing`: a network request was in progress.
- `failed`: one step in the save sequence failed.

The internal state was useful during development, but it was not suitable for
the customer-facing profile screen.

### Why "Not synced" was misleading

Saving a profile is a multi-step operation:

1. Save profile fields such as bio, profession, prompts, and preferences.
2. Upload new photos.
3. Delete removed photos.
4. Save the final photo order.
5. Fetch the confirmed profile from the backend.
6. Mark the local SQLite copy as clean.

If step 5 failed after the previous steps succeeded, the app still displayed
`Not synced`. The message could therefore imply that nothing was saved even
when the profile fields and photos were already present in PostgreSQL and
Supabase Storage.

This exposed an internal aggregate state instead of explaining the specific
action a user needed to take.

## Product Decision

ClubMates no longer displays persistent profile synchronization terminology.

The following customer-facing labels were removed:

```text
Synced
Syncing...
Not synced
```

The internal sync state, SQLite dirty flag, retry logic, and diagnostic logging
remain in place. They are implementation details and should not normally be
visible to users.

## Current User Experience

### Successful profile save

1. The user opens Edit Profile.
2. Changes are made in a draft profile.
3. The user taps `Save`.
4. The edit screen closes.
5. ClubMates saves the profile in the background.
6. No permanent success badge is displayed.

Success is intentionally quiet. The updated profile itself is the confirmation.

### Temporary failure

Temporary failures include:

- a lost network connection
- a request timeout
- HTTP 408
- HTTP 429
- HTTP 5xx
- a temporarily unreadable server response

ClubMates automatically retries a temporary profile save once. Users are not
interrupted during this first recovery attempt.

### Profile field failure

If the retry also fails, ClubMates displays:

```text
Couldn't save changes
```

The available actions are:

```text
Try Again
Not Now
```

The message explains that the changes remain saved on the device. Tapping
`Try Again` sends the latest complete local profile to the backend.

### Photo upload progress

Photo uploads are slower and more failure-prone than text updates, so their
state is displayed on the affected photo instead of on the entire profile.

While uploading:

```text
Uploading
```

After a final upload failure:

```text
Upload failed
Tap to retry
```

Tapping the failed photo retries the save.

This keeps the error close to the action that failed and avoids suggesting that
the entire profile is broken.

## Current Technical Flow

```text
User taps Save
    |
    v
Update in-memory profile
    |
    v
Save local profile to SQLite with is_dirty = 1
    |
    v
Add save request to the serialized profile-save queue
    |
    v
PATCH changed profile fields, or PUT the complete profile when required
    |
    v
Upload new photos one at a time
    |
    v
Delete removed photos
    |
    v
Save authoritative photo order
    |
    v
GET /users/me for server confirmation
    |
    v
Replace local profile with confirmed server profile
    |
    v
Set SQLite is_dirty = 0 and record last_synced_at
```

## Serialized Save Queue

Profile saves are serialized instead of cancelling an active save whenever a
new edit occurs.

Example:

1. A user starts uploading a photo.
2. While it uploads, the user changes their bio.
3. The photo upload continues instead of being cancelled.
4. The latest bio change is queued.
5. After the active save finishes, ClubMates saves the latest queued profile.

Multiple quick edits are coalesced into the newest profile state. This prevents
slow photo uploads from being repeatedly cancelled by normal profile edits.

The queue is cancelled only when the session itself becomes invalid, such as
after sign-out or account deletion.

## Reliable Photo Uploads

### Stable client photo ID

Every locally selected photo already has a UUID. The client sends this UUID as:

```text
clientPhotoId=<photo-uuid>
```

The backend uses that ID for both the database row and the Supabase object path:

```text
<user-id>/<photo-id>.jpg
```

Retrying the same photo therefore targets the same object instead of creating a
new object. This makes the upload idempotent and reduces duplicate or orphaned
files.

Older clients remain compatible because `clientPhotoId` is optional. The
backend generates an ID when it is not provided.

### Supabase timeout and retry

Supabase Storage operations use:

- a 15-second timeout per attempt
- up to two attempts
- a short exponential delay between attempts
- retries for network errors, HTTP 408, HTTP 429, and HTTP 5xx

This prevents a single Storage connection from remaining open indefinitely.

### Faster upload response

The backend previously generated a signed URL immediately after uploading the
photo. This required a second Supabase request before the upload API could
respond.

The upload endpoint now:

1. uploads the object
2. saves the database row
3. returns the saved photo immediately

Signed URLs are generated later when the complete profile is fetched. This
shortens the write path and reduces the chance that a successful upload is
reported as failed.

### Response contract

The upload endpoint returns camelCase JSON:

```json
{
  "photo": {
    "id": "photo-uuid",
    "storageKey": "user-uuid/photo-uuid.jpg",
    "cdnUrl": "https://...",
    "position": 0
  }
}
```

Clients must decode these exact field names. Returning or expecting
database-style fields such as `storage_key` or `cdn_url` causes decoding to
fail after the upload has already succeeded.

## Offline Recovery

SQLite stores the latest local profile and an `is_dirty` flag.

```text
is_dirty = 1
```

means local changes have not yet been fully confirmed by the backend.

When the app launches:

1. Load the cached profile from SQLite.
2. Check `is_dirty`.
3. If dirty, retry the complete profile save automatically.
4. Fetch the confirmed server profile after success.
5. Mark the local record clean.

This mechanism prevents edits from being lost when the app closes during a
temporary network failure.

## Dating App UX Research

The following observations are based on public support documentation. These
companies do not publish their internal profile synchronization architecture,
so conclusions about hidden retry or caching behavior are product inferences,
not claims about their private implementation.

### Tinder

Tinder presents profile editing through the profile pencil/Edit Info flow.
Public instructions describe selecting interests and tapping `Done` to save.
Its troubleshooting guidance discusses bio or photo updates not sticking and
asks users to check connectivity or refresh the app experience.

The public workflow focuses on editing and saving. It does not teach customers
about server synchronization states.

References:

- [Editing your profile](https://www.help.tinder.com/hc/en-us/articles/115003339043-Editing-your-profile)
- [Interests](https://www.help.tinder.com/hc/en-us/articles/360046122691-Interests)
- [I cannot update my profile](https://www.help.tinder.com/hc/en-us/articles/115003481703-I-can-t-update-my-profile)

### Bumble

Bumble documents an Edit Profile flow with user-facing actions such as `Save`,
`Save and close`, and `Add Photo`. Its photo documentation supports adding
photos and dragging them to reorder.

The public workflow describes the action the user is taking instead of exposing
a continuous synchronization indicator.

References:

- [Uploading profile photos and videos](https://support.bumble.com/hc/en-us/articles/28523708029341-Uploading-profile-photos-and-videos)
- [Changing your personal details](https://support.bumble.com/hc/en-us/articles/28938787921053-Changing-your-personal-details)
- [Updating your dating intentions](https://support.bumble.com/hc/en-us/articles/30702563597597-Updating-your-dating-intentions)

### Hinge

Hinge documents editing through the profile pencil icon and tapping `Done` to
save changes on iOS. Its prompt editing documentation also supports drag and
drop reordering followed by `Done`.

The public workflow gives users a clear completion action without presenting
technical sync terminology.

References:

- [How do I edit my profile?](https://help.hinge.co/hc/en-us/articles/360011053094-How-do-I-edit-my-profile)
- [How do I edit my Prompts?](https://help.hinge.co/hc/en-us/articles/36311352171539-How-do-I-edit-my-Prompts)
- [What is Top Photo?](https://help.hinge.co/hc/en-us/articles/26558052212627-What-is-Top-Photo)

## Shared Pattern

The public workflows of Tinder, Bumble, and Hinge support the following product
principles:

1. Use familiar actions such as `Save`, `Done`, and `Add Photo`.
2. Keep successful saves quiet.
3. Show progress for slower media operations.
4. Put a media failure on the affected media item.
5. Show errors only when the user needs to take action.
6. Use plain language such as `Couldn't save changes`.
7. Avoid exposing internal terms such as sync state, dirty state, server state,
   or database state.

ClubMates follows these principles while retaining stronger offline recovery
internally.

## Cross-Platform Requirements

iOS and Android should both follow these rules:

- Do not show a permanent `Synced`, `Syncing`, or `Not synced` badge.
- Keep a local profile copy and dirty state.
- Save profile edits through an explicit `Save` or `Done` action.
- Retry transient failures quietly once.
- Preserve local changes after failure.
- Show a general retry message only for non-photo save failures.
- Show photo progress and failure on the specific photo.
- Send a stable `clientPhotoId` for each local photo.
- Serialize profile saves instead of cancelling active uploads.
- Reconcile with `GET /users/me` after the full save sequence.
- Keep detailed errors in development logs and monitoring, not in normal UI.

## Testing Checklist

### Normal profile save

- Change the bio and tap Save.
- Confirm the edit screen closes.
- Confirm no sync badge appears.
- Confirm the backend contains the updated value.

### Photo upload

- Add one photo.
- Confirm the affected photo displays `Uploading`.
- Confirm the overlay disappears after success.
- Confirm the object exists in Supabase Storage.
- Confirm the row exists in `profile_photos`.

### Photo reorder

- Drag photos into a new order.
- Tap Save.
- Confirm no active upload is cancelled.
- Confirm the backend positions match the visible order.
- Relaunch the app and confirm the order remains correct.

### Temporary network failure

- Start a photo upload.
- Interrupt the network temporarily.
- Confirm ClubMates retries quietly.
- If the final attempt fails, confirm only the affected photo displays
  `Upload failed`.
- Restore the network and tap the photo to retry.

### Relaunch recovery

- Save while the backend is unavailable.
- Close and reopen the app.
- Confirm the local profile is restored.
- Restore the backend.
- Confirm the dirty profile retries and becomes clean after confirmation.

### Rapid edits

- Start a photo upload.
- Change the bio or preferences while it is running.
- Confirm the upload is not cancelled.
- Confirm the latest profile state is saved after the active operation.
