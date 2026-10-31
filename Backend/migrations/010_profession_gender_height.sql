-- Replace job_title + company with profession, add gender, change height TEXT → INTEGER (cm)

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS profession TEXT,
  ADD COLUMN IF NOT EXISTS gender     TEXT;

-- Migrate existing job_title into profession where profession is not yet set
UPDATE users SET profession = job_title WHERE profession IS NULL AND job_title IS NOT NULL;

-- Convert height from TEXT to INTEGER (cm). Rows with unparseable values get NULL.
ALTER TABLE users ADD COLUMN IF NOT EXISTS height_cm INTEGER;
UPDATE users
SET height_cm = CASE
  WHEN height ~ '^\d+$' THEN height::INTEGER
  ELSE NULL
END;
ALTER TABLE users DROP COLUMN IF EXISTS height;
ALTER TABLE users RENAME COLUMN height_cm TO height;

-- Drop old columns
ALTER TABLE users DROP COLUMN IF EXISTS job_title;
ALTER TABLE users DROP COLUMN IF EXISTS company;
