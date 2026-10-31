UPDATE venue_voting_competitions
SET max_votes_per_voter = 1
WHERE max_votes_per_voter <> 1;

WITH ranked_votes AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY competition_id, voter_id
           ORDER BY created_at ASC, id ASC
         ) AS vote_rank
  FROM venue_voting_votes
)
DELETE FROM venue_voting_votes
WHERE id IN (
  SELECT id
  FROM ranked_votes
  WHERE vote_rank > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_venue_voting_votes_one_per_competition
  ON venue_voting_votes(competition_id, voter_id);
