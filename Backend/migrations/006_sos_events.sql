CREATE TABLE IF NOT EXISTS sos_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  venue_id        UUID REFERENCES venues(id) ON DELETE SET NULL,
  match_id        UUID REFERENCES matches(id) ON DELETE SET NULL,
  latitude        DOUBLE PRECISION,
  longitude       DOUBLE PRECISION,
  accuracy_meters DOUBLE PRECISION,
  source          TEXT NOT NULL DEFAULT 'app'
                  CHECK (source IN ('app', 'venue', 'chat', 'profile')),
  message         TEXT,
  status          TEXT NOT NULL DEFAULT 'triggered'
                  CHECK (status IN ('triggered', 'acknowledged', 'resolved', 'false_alarm')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sos_events_user_created
  ON sos_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sos_events_status_created
  ON sos_events(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sos_events_venue_created
  ON sos_events(venue_id, created_at DESC)
  WHERE venue_id IS NOT NULL;
