-- Store the face embedding generated from the user's verification selfie.
-- Used to check profile photos belong to the same person without re-downloading the selfie.
ALTER TABLE users ADD COLUMN IF NOT EXISTS face_embedding JSONB;
