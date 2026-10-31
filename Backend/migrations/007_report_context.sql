ALTER TABLE reports
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'safety',
  ADD COLUMN IF NOT EXISTS match_id UUID REFERENCES matches(id) ON DELETE SET NULL;

DO $$
BEGIN
  ALTER TABLE reports
    ADD CONSTRAINT reports_category_check
    CHECK (category IN ('safety', 'spam'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_reports_category_created
  ON reports(category, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reports_match
  ON reports(match_id)
  WHERE match_id IS NOT NULL;
