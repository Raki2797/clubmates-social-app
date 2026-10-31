CREATE TABLE IF NOT EXISTS treat_invites (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  venue_id    UUID REFERENCES venues(id),
  treat_type  TEXT NOT NULL CHECK (
    treat_type IN ('drink', 'dessert', 'coffee', 'starter', 'decide_together')
  ),
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending', 'accepted', 'declined')
  ),
  match_id    UUID REFERENCES matches(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  UNIQUE(sender_id, receiver_id, venue_id)
);

CREATE INDEX IF NOT EXISTS idx_treat_invites_receiver_status
  ON treat_invites(receiver_id, status, created_at DESC);

DROP TRIGGER IF EXISTS treat_invites_touch_updated_at ON treat_invites;
CREATE TRIGGER treat_invites_touch_updated_at
BEFORE UPDATE ON treat_invites
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();
