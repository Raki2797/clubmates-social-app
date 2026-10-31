ALTER TABLE treat_invites
  DROP CONSTRAINT IF EXISTS treat_invites_status_check;

ALTER TABLE treat_invites
  ADD CONSTRAINT treat_invites_status_check CHECK (
    status IN (
      'pending',
      'accepted',
      'accepted_by_like',
      'accepted_by_invite_back',
      'declined',
      'expired'
    )
  );

ALTER TABLE treat_invites
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

UPDATE treat_invites
SET expires_at = created_at + INTERVAL '24 hours'
WHERE expires_at IS NULL;

UPDATE treat_invites
SET status = 'expired', responded_at = COALESCE(responded_at, now())
WHERE status = 'pending'
  AND expires_at <= now();

WITH ranked_pending AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id)
      ORDER BY created_at DESC, id DESC
    ) AS pair_rank
  FROM treat_invites
  WHERE status = 'pending'
)
UPDATE treat_invites i
SET status = 'expired', responded_at = now()
FROM ranked_pending ranked
WHERE i.id = ranked.id
  AND ranked.pair_rank > 1;

ALTER TABLE treat_invites
  ALTER COLUMN expires_at SET DEFAULT (now() + INTERVAL '24 hours'),
  ALTER COLUMN expires_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_treat_invites_active_pair
  ON treat_invites(sender_id, receiver_id, created_at DESC)
  WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS idx_treat_invites_one_pending_per_pair
  ON treat_invites(
    LEAST(sender_id, receiver_id),
    GREATEST(sender_id, receiver_id)
  )
  WHERE status = 'pending';
