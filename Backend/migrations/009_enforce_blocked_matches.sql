CREATE INDEX IF NOT EXISTS idx_blocks_blocked_blocker
  ON blocks(blocked_id, blocker_id);

UPDATE matches m
SET unmatched_at = now()
WHERE m.unmatched_at IS NULL
  AND EXISTS (
    SELECT 1
    FROM blocks b
    WHERE (b.blocker_id = m.user_a_id AND b.blocked_id = m.user_b_id)
       OR (b.blocker_id = m.user_b_id AND b.blocked_id = m.user_a_id)
  );

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

CREATE OR REPLACE FUNCTION close_matches_for_block()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE matches
  SET unmatched_at = now()
  WHERE unmatched_at IS NULL
    AND (
      (user_a_id = NEW.blocker_id AND user_b_id = NEW.blocked_id)
      OR (user_a_id = NEW.blocked_id AND user_b_id = NEW.blocker_id)
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS blocks_close_matches ON blocks;
CREATE TRIGGER blocks_close_matches
AFTER INSERT ON blocks
FOR EACH ROW
EXECUTE FUNCTION close_matches_for_block();

CREATE OR REPLACE FUNCTION close_matches_for_report()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.reporter_id <> NEW.reported_id THEN
    INSERT INTO blocks(blocker_id, blocked_id)
    VALUES (NEW.reporter_id, NEW.reported_id)
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE matches
  SET unmatched_at = now()
  WHERE unmatched_at IS NULL
    AND (
      (user_a_id = NEW.reporter_id AND user_b_id = NEW.reported_id)
      OR (user_a_id = NEW.reported_id AND user_b_id = NEW.reporter_id)
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reports_close_matches ON reports;
CREATE TRIGGER reports_close_matches
AFTER INSERT ON reports
FOR EACH ROW
EXECUTE FUNCTION close_matches_for_report();

CREATE OR REPLACE FUNCTION prevent_blocked_match_reactivation()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.unmatched_at IS NULL AND (
    EXISTS (
      SELECT 1
      FROM blocks b
      WHERE (b.blocker_id = NEW.user_a_id AND b.blocked_id = NEW.user_b_id)
         OR (b.blocker_id = NEW.user_b_id AND b.blocked_id = NEW.user_a_id)
    )
    OR EXISTS (
      SELECT 1
      FROM reports r
      WHERE (r.reporter_id = NEW.user_a_id AND r.reported_id = NEW.user_b_id)
         OR (r.reporter_id = NEW.user_b_id AND r.reported_id = NEW.user_a_id)
    )
  ) THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.unmatched_at = COALESCE(OLD.unmatched_at, now());
    ELSE
      NEW.unmatched_at = now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS matches_prevent_blocked_reactivation ON matches;
CREATE TRIGGER matches_prevent_blocked_reactivation
BEFORE INSERT OR UPDATE ON matches
FOR EACH ROW
EXECUTE FUNCTION prevent_blocked_match_reactivation();
