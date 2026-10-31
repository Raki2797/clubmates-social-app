ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_ghost_mode BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_users_ghost_mode
  ON users(is_ghost_mode)
  WHERE is_ghost_mode = true;
