CREATE INDEX IF NOT EXISTS idx_reports_reporter_reported
  ON reports(reporter_id, reported_id);

CREATE INDEX IF NOT EXISTS idx_reports_reported_reporter
  ON reports(reported_id, reporter_id);

INSERT INTO blocks(blocker_id, blocked_id)
SELECT DISTINCT reporter_id, reported_id
FROM reports
WHERE reporter_id <> reported_id
ON CONFLICT DO NOTHING;

UPDATE matches m
SET unmatched_at = now()
WHERE m.unmatched_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM reports r
    WHERE (r.reporter_id = m.user_a_id AND r.reported_id = m.user_b_id)
       OR (r.reporter_id = m.user_b_id AND r.reported_id = m.user_a_id)
  );

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
