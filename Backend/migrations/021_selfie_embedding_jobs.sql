-- Background job queue for selfie face embedding extraction.
-- Jobs are inserted on selfie upload and processed by the embedding worker.
-- Keeps one pending job per user (upsert on conflict).

CREATE TABLE IF NOT EXISTS selfie_embedding_jobs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cdn_url      TEXT NOT NULL,
  attempts     SMALLINT NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  failed_at    TIMESTAMPTZ,
  UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_selfie_embedding_jobs_pending
  ON selfie_embedding_jobs(created_at)
  WHERE completed_at IS NULL AND failed_at IS NULL;
