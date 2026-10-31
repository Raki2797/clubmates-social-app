ALTER TABLE users
  ADD COLUMN IF NOT EXISTS verification_failure_reason TEXT,
  ADD COLUMN IF NOT EXISTS verification_mismatched_photo_ids UUID[] DEFAULT '{}';
