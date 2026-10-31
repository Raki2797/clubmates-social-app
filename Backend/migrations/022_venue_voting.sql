CREATE TABLE IF NOT EXISTS venue_voting_competitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('male', 'female', 'lgbtq')),
  title TEXT NOT NULL DEFAULT 'Venue Voting',
  prize_amount_cents INTEGER NOT NULL DEFAULT 200000,
  entry_fee_cents INTEGER NOT NULL DEFAULT 20000,
  platform_fee_cents INTEGER NOT NULL DEFAULT 2000,
  max_votes_per_voter INTEGER NOT NULL DEFAULT 1,
  registration_closes_at TIMESTAMPTZ NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_venue_voting_competitions_venue
  ON venue_voting_competitions(venue_id, category, starts_at DESC);

CREATE TABLE IF NOT EXISTS venue_voting_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id UUID NOT NULL REFERENCES venue_voting_competitions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(competition_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_venue_voting_entries_competition
  ON venue_voting_entries(competition_id, joined_at);

CREATE TABLE IF NOT EXISTS venue_voting_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id UUID NOT NULL REFERENCES venue_voting_competitions(id) ON DELETE CASCADE,
  voter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entry_id UUID NOT NULL REFERENCES venue_voting_entries(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(voter_id, entry_id)
);

CREATE INDEX IF NOT EXISTS idx_venue_voting_votes_competition_voter
  ON venue_voting_votes(competition_id, voter_id);

CREATE INDEX IF NOT EXISTS idx_venue_voting_votes_entry
  ON venue_voting_votes(entry_id);
