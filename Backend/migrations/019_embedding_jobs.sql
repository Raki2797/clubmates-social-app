-- Background job queue for face embedding extraction from profile photos.
-- Jobs are inserted on photo upload and processed by the embedding worker.

CREATE TABLE IF NOT EXISTS embedding_jobs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id     UUID NOT NULL REFERENCES profile_photos(id) ON DELETE CASCADE,
  cdn_url      TEXT NOT NULL,
  attempts     SMALLINT NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  failed_at    TIMESTAMPTZ,
  UNIQUE(photo_id)
);

CREATE INDEX IF NOT EXISTS idx_embedding_jobs_pending
  ON embedding_jobs(created_at)
  WHERE completed_at IS NULL AND failed_at IS NULL;
