CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164        TEXT UNIQUE NOT NULL,
  name              TEXT NOT NULL DEFAULT '',
  age               SMALLINT NOT NULL DEFAULT 18,
  bio               TEXT,
  job_title         TEXT,
  company           TEXT,
  height            TEXT,
  interests         TEXT[] DEFAULT '{}',
  is_verified       BOOLEAN DEFAULT false,
  is_active         BOOLEAN DEFAULT true,
  is_flagged        BOOLEAN DEFAULT false,
  profile_completed BOOLEAN DEFAULT false,
  deletion_requested_at TIMESTAMPTZ,
  deletion_scheduled_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_deletion_scheduled
  ON users(deletion_scheduled_at)
  WHERE deletion_scheduled_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS profile_photos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  storage_key TEXT NOT NULL,
  cdn_url     TEXT NOT NULL,
  position    SMALLINT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, position)
);

CREATE TABLE IF NOT EXISTS profile_prompts (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
  question  TEXT NOT NULL,
  answer    TEXT NOT NULL,
  position  SMALLINT NOT NULL,
  UNIQUE(user_id, position)
);

CREATE TABLE IF NOT EXISTS venues (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  city          TEXT NOT NULL DEFAULT 'Hyderabad',
  neighborhood  TEXT NOT NULL,
  vibe          TEXT,
  music         TEXT,
  symbol_name   TEXT,
  gradient_hex  TEXT[],
  latitude      DOUBLE PRECISION,
  longitude     DOUBLE PRECISION,
  checkin_radius_meters INTEGER NOT NULL DEFAULT 200,
  is_active     BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS checkins (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES users(id) ON DELETE CASCADE,
  venue_id       UUID REFERENCES venues(id),
  checked_in_at  TIMESTAMPTZ DEFAULT now(),
  checked_out_at TIMESTAMPTZ,
  last_ping_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_checkins_active_venue ON checkins(venue_id) WHERE checked_out_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_checkins_active_user ON checkins(user_id) WHERE checked_out_at IS NULL;

CREATE TABLE IF NOT EXISTS swipes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id   UUID REFERENCES users(id) ON DELETE CASCADE,
  target_id  UUID REFERENCES users(id) ON DELETE CASCADE,
  venue_id   UUID REFERENCES venues(id),
  direction  TEXT CHECK(direction IN ('like', 'nope', 'superlike')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(actor_id, target_id, venue_id)
);
CREATE INDEX IF NOT EXISTS idx_swipes_actor_venue ON swipes(actor_id, venue_id);

CREATE TABLE IF NOT EXISTS matches (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id  UUID REFERENCES users(id) ON DELETE CASCADE,
  user_b_id  UUID REFERENCES users(id) ON DELETE CASCADE,
  venue_id   UUID REFERENCES venues(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  unmatched_at TIMESTAMPTZ,
  UNIQUE(user_a_id, user_b_id, venue_id)
);
CREATE INDEX IF NOT EXISTS idx_matches_user_a ON matches(user_a_id);
CREATE INDEX IF NOT EXISTS idx_matches_user_b ON matches(user_b_id);

CREATE TABLE IF NOT EXISTS messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id   UUID REFERENCES matches(id) ON DELETE CASCADE,
  sender_id  UUID REFERENCES users(id) ON DELETE CASCADE,
  body       TEXT NOT NULL,
  is_read    BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_match ON messages(match_id, created_at);

CREATE TABLE IF NOT EXISTS blocks (
  blocker_id UUID REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE IF NOT EXISTS reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID REFERENCES users(id) ON DELETE CASCADE,
  reported_id UUID REFERENCES users(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL,
  details     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device_tokens (
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  platform   TEXT DEFAULT 'apns',
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, token)
);

CREATE TABLE IF NOT EXISTS otp_codes (
  phone_e164 TEXT PRIMARY KEY,
  code_hash  TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts   SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_touch_updated_at ON users;
CREATE TRIGGER users_touch_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

CREATE OR REPLACE FUNCTION record_swipe(
  p_actor_id  UUID,
  p_target_id UUID,
  p_venue_id  UUID,
  p_direction TEXT
) RETURNS TABLE(is_match BOOLEAN, match_id UUID)
LANGUAGE plpgsql AS $$
DECLARE
  v_mutual BOOLEAN;
  v_match_id UUID;
BEGIN
  INSERT INTO swipes(actor_id, target_id, venue_id, direction)
  VALUES (p_actor_id, p_target_id, p_venue_id, p_direction)
  ON CONFLICT (actor_id, target_id, venue_id)
  DO UPDATE SET direction = p_direction, created_at = now();

  IF p_direction IN ('like', 'superlike') THEN
    IF EXISTS (
      SELECT 1
      FROM blocks
      WHERE (blocker_id = p_actor_id AND blocked_id = p_target_id)
         OR (blocker_id = p_target_id AND blocked_id = p_actor_id)
    ) OR EXISTS (
      SELECT 1
      FROM reports
      WHERE (reporter_id = p_actor_id AND reported_id = p_target_id)
         OR (reporter_id = p_target_id AND reported_id = p_actor_id)
    ) THEN
      RETURN QUERY SELECT false, NULL::UUID;
      RETURN;
    END IF;

    SELECT EXISTS(
      SELECT 1 FROM swipes
      WHERE actor_id = p_target_id AND target_id = p_actor_id
        AND venue_id = p_venue_id AND direction IN ('like', 'superlike')
    ) INTO v_mutual;

    IF v_mutual THEN
      INSERT INTO matches(user_a_id, user_b_id, venue_id)
      VALUES (
        LEAST(p_actor_id::text, p_target_id::text)::uuid,
        GREATEST(p_actor_id::text, p_target_id::text)::uuid,
        p_venue_id
      )
      ON CONFLICT (user_a_id, user_b_id, venue_id)
      DO UPDATE SET unmatched_at = NULL
      RETURNING id INTO v_match_id;

      RETURN QUERY SELECT true, v_match_id;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::UUID;
END;
$$;
