ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_matches_user_a_updated ON matches(user_a_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_matches_user_b_updated ON matches(user_b_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_messages_match_updated ON messages(match_id, updated_at);

CREATE OR REPLACE FUNCTION touch_message_match_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE matches
  SET updated_at = now()
  WHERE id = COALESCE(NEW.match_id, OLD.match_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS messages_touch_match_after_insert ON messages;
CREATE TRIGGER messages_touch_match_after_insert
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION touch_message_match_updated_at();

DROP TRIGGER IF EXISTS messages_touch_match_after_update ON messages;
CREATE TRIGGER messages_touch_match_after_update
AFTER UPDATE ON messages
FOR EACH ROW
EXECUTE FUNCTION touch_message_match_updated_at();

DROP TRIGGER IF EXISTS matches_touch_updated_at ON matches;
CREATE TRIGGER matches_touch_updated_at
BEFORE UPDATE ON matches
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS messages_touch_updated_at ON messages;
CREATE TRIGGER messages_touch_updated_at
BEFORE UPDATE ON messages
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
      INSERT INTO matches(user_a_id, user_b_id, venue_id, deleted_at)
      VALUES (
        LEAST(p_actor_id::text, p_target_id::text)::uuid,
        GREATEST(p_actor_id::text, p_target_id::text)::uuid,
        p_venue_id,
        NULL
      )
      ON CONFLICT (user_a_id, user_b_id, venue_id)
      DO UPDATE SET unmatched_at = NULL, deleted_at = NULL, updated_at = now()
      RETURNING id INTO v_match_id;

      RETURN QUERY SELECT true, v_match_id;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::UUID;
END;
$$;
