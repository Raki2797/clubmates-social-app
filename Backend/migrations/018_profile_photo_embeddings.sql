-- Store per-face embeddings extracted from profile photos.
-- face_embeddings: array of embedding arrays (one per detected face).
-- face_count: number of faces found (0 = no face, 1 = solo, 2+ = group photo).
-- NULL means extraction has not run yet (photo just uploaded, worker pending).

ALTER TABLE profile_photos
  ADD COLUMN IF NOT EXISTS face_embeddings JSONB,
  ADD COLUMN IF NOT EXISTS face_count      SMALLINT;
