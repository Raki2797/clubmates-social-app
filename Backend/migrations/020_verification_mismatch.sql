-- Track why verification failed and which photos caused the mismatch.
-- verification_failure_reason: 'photo_mismatch' | 'no_selfie' | 'no_face_in_any_photo'
-- verification_mismatched_photo_ids: IDs of profile_photos whose faces didn't match the selfie

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS verification_failure_reason      TEXT,
  ADD COLUMN IF NOT EXISTS verification_mismatched_photo_ids UUID[] NOT NULL DEFAULT '{}';
