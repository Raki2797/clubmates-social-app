import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { authenticate } from "../plugins/auth.js";
import { broadcastToUser } from "../realtime/chatHub.js";
import { withSignedPhotoUrls } from "../services/profilePhotoStorage.js";
import { asString, sendError } from "../utils/http.js";
import { PhotoRow, serializeProfile, UserRow } from "../utils/serializers.js";

type VotingCategory = "male" | "female" | "lgbtq";

const votingCategories: VotingCategory[] = ["male", "female", "lgbtq"];

type CompetitionRow = {
  id: string;
  venue_id: string;
  category: VotingCategory;
  title: string;
  prize_amount_cents: number;
  entry_fee_cents: number;
  platform_fee_cents: number;
  max_votes_per_voter: number;
  registration_closes_at: Date;
  starts_at: Date;
  ends_at: Date;
};

type EntryRow = {
  entry_id: string;
  joined_at: Date;
  vote_count: string;
  has_voted: boolean;
  is_winner_eligible: boolean;
} & UserRow & { photo_id?: string | null; storage_key?: string | null; photo_url?: string | null };

type HistoryRow = {
  id: string;
  venue_id: string;
  venue_name: string;
  category: VotingCategory;
  title: string;
  prize_amount_cents: number;
  ends_at: Date;
  total_votes: string;
  user_votes: string;
  user_received_votes: string;
  user_joined: boolean;
  user_won: boolean;
};

function phaseFor(row: CompetitionRow): "registration" | "live" | "ended" {
  const now = Date.now();
  if (now >= new Date(row.ends_at).getTime()) return "ended";
  if (now >= new Date(row.starts_at).getTime()) return "live";
  return "registration";
}

function normalizeCategory(value: unknown): VotingCategory | undefined {
  const rawValue = asString(value)?.trim().toLowerCase();
  if (rawValue === "men" || rawValue === "man") return "male";
  if (rawValue === "women" || rawValue === "woman") return "female";
  if (rawValue === "queer" || rawValue === "lgbt" || rawValue === "lgbtq+") return "lgbtq";
  return votingCategories.includes(rawValue as VotingCategory) ? rawValue as VotingCategory : undefined;
}

function categoryForGender(gender: string | null | undefined): VotingCategory {
  const normalized = (gender ?? "").trim().toLowerCase();
  if (["male", "man", "men", "m"].includes(normalized)) return "male";
  if (["female", "woman", "women", "f"].includes(normalized)) return "female";
  return "lgbtq";
}

async function hasActiveVenueCheckin(userId: string, venueId: string): Promise<boolean> {
  const result = await query<{ id: string }>(
    `
      SELECT id
      FROM checkins
      WHERE user_id = $1
        AND venue_id = $2
        AND checked_out_at IS NULL
      LIMIT 1
    `,
    [userId, venueId]
  );
  return (result.rowCount ?? 0) > 0;
}

async function hasVenueCheckin(userId: string, venueId: string): Promise<boolean> {
  const result = await query<{ id: string }>(
    `
      SELECT id
      FROM checkins
      WHERE user_id = $1
        AND venue_id = $2
      LIMIT 1
    `,
    [userId, venueId]
  );
  return (result.rowCount ?? 0) > 0;
}

async function venueVotingRecipientIds(venueId: string): Promise<string[]> {
  const result = await query<{ user_id: string }>(
    `
      SELECT DISTINCT user_id
      FROM (
        SELECT c.user_id
        FROM checkins c
        JOIN users u ON u.id = c.user_id
        WHERE c.venue_id = $1
          AND c.checked_out_at IS NULL
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL

        UNION

        SELECT e.user_id
        FROM venue_voting_entries e
        JOIN venue_voting_competitions vc ON vc.id = e.competition_id
        JOIN users u ON u.id = e.user_id
        WHERE vc.venue_id = $1
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL

        UNION

        SELECT v.voter_id AS user_id
        FROM venue_voting_votes v
        JOIN venue_voting_competitions vc ON vc.id = v.competition_id
        JOIN users u ON u.id = v.voter_id
        WHERE vc.venue_id = $1
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
      ) recipients
    `,
    [venueId]
  );

  return result.rows.map((row) => row.user_id);
}

async function broadcastVenueVotingUpdate(
  venueId: string,
  category: VotingCategory | null,
  action: "demo_restarted" | "joined" | "voted"
): Promise<void> {
  const recipients = await venueVotingRecipientIds(venueId);
  for (const userId of recipients) {
    broadcastToUser(userId, {
      type: "venue_voting.updated",
      venueId,
      category,
      action
    });
  }
}

function serializeCompetition(row: CompetitionRow, entries: unknown[], userEntryId: string | null, userVotesUsed: number) {
  const phase = phaseFor(row);
  const maxVotes = Number(row.max_votes_per_voter);
  const typedEntries = entries as { voteCount?: number }[];
  const totalVotes = typedEntries.reduce((sum, entry) => sum + Number(entry.voteCount ?? 0), 0);
  const winner = phase === "ended"
    ? [...entries]
      .filter((entry) => {
        const typedEntry = entry as { isWinnerEligible?: boolean; voteCount?: number };
        return typedEntry.isWinnerEligible === true && Number(typedEntry.voteCount ?? 0) > 0;
      })
      .sort((lhs, rhs) => {
        const lhsVotes = Number((lhs as { voteCount?: number }).voteCount ?? 0);
        const rhsVotes = Number((rhs as { voteCount?: number }).voteCount ?? 0);
        return rhsVotes - lhsVotes;
      })[0] ?? null
    : null;

  return {
    id: row.id,
    venueId: row.venue_id,
    category: row.category,
    title: row.title,
    phase,
    prizeAmountCents: row.prize_amount_cents,
    entryFeeCents: row.entry_fee_cents,
    platformFeeCents: row.platform_fee_cents,
    maxVotesPerVoter: maxVotes,
    registrationClosesAt: row.registration_closes_at,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    entries,
    userEntryId,
    userVotesUsed,
    userVotesRemaining: Math.max(0, maxVotes - userVotesUsed),
    totalVotes,
    winner
  };
}

async function ensureTodayCompetition(venueId: string, category: VotingCategory): Promise<CompetitionRow> {
  const existing = await query<CompetitionRow>(
    `
      SELECT *
      FROM venue_voting_competitions
      WHERE venue_id = $1
        AND category = $2
        AND ends_at > now() - interval '12 hours'
      ORDER BY
        CASE
          WHEN starts_at <= now() AND ends_at > now() THEN 0
          WHEN starts_at > now() THEN 1
          ELSE 2
        END,
        CASE
          WHEN starts_at > now() THEN starts_at
          ELSE NULL
        END ASC NULLS LAST,
        starts_at DESC
      LIMIT 1
    `,
    [venueId, category]
  );
  if ((existing.rowCount ?? 0) > 0) {
    return existing.rows[0];
  }

  const created = await query<CompetitionRow>(
    `
      WITH vote_clock AS (
        SELECT now() AS value,
               date_trunc('day', now()) AS today,
               EXTRACT(DOW FROM now())::int AS day_of_week
      ),
      voting_day AS (
        SELECT CASE
          WHEN day_of_week IN (0, 6) AND value < today + interval '25 hours'
            THEN today
          ELSE today + (((6 - day_of_week + 7) % 7) || ' days')::interval
        END AS starts_on
        FROM vote_clock
      )
      INSERT INTO venue_voting_competitions(
        venue_id,
        category,
        title,
        max_votes_per_voter,
        registration_closes_at,
        starts_at,
        ends_at
      )
      VALUES (
        $1,
        $2,
        'Venue Voting',
        1,
        (SELECT starts_on FROM voting_day) + interval '19 hours 45 minutes',
        (SELECT starts_on FROM voting_day) + interval '20 hours',
        (SELECT starts_on FROM voting_day) + interval '25 hours'
      )
      RETURNING *
    `,
    [venueId, category]
  );
  return created.rows[0];
}

async function resetDemoCompetition(row: CompetitionRow): Promise<CompetitionRow> {
  return withTransaction(async (client) => {
    await client.query(
      `
        INSERT INTO checkins(user_id, venue_id, checked_in_at, checked_out_at)
        SELECT e.user_id, vc.venue_id, now() - interval '2 hours', now() - interval '90 minutes'
        FROM venue_voting_entries e
        JOIN venue_voting_competitions vc ON vc.id = e.competition_id
        WHERE e.competition_id = $1
          AND NOT EXISTS (
            SELECT 1
            FROM checkins ci
            WHERE ci.user_id = e.user_id
              AND ci.venue_id = vc.venue_id
          )
      `,
      [row.id]
    );
    await client.query(
      "DELETE FROM venue_voting_votes WHERE competition_id = $1",
      [row.id]
    );
    await client.query(
      `
        DELETE FROM venue_voting_entries e
        USING users u
        WHERE e.user_id = u.id
          AND e.competition_id = $1
          AND u.phone_e164 NOT LIKE '+910000100%'
      `,
      [row.id]
    );
    await client.query(
      `
        INSERT INTO venue_voting_entries(competition_id, user_id)
        SELECT $1, u.id
        FROM users u
        WHERE u.phone_e164 LIKE '+910000100%'
          AND u.is_active = true
          AND u.deletion_scheduled_at IS NULL
          AND (
            ($2 = 'male' AND lower(u.gender) IN ('male', 'man', 'men', 'm'))
            OR ($2 = 'female' AND lower(u.gender) IN ('female', 'woman', 'women', 'f'))
            OR (
              $2 = 'lgbtq'
              AND lower(u.gender) NOT IN ('male', 'man', 'men', 'm', 'female', 'woman', 'women', 'f')
            )
          )
        ON CONFLICT (competition_id, user_id) DO NOTHING
      `,
      [row.id, row.category]
    );
    const refreshed = await client.query<CompetitionRow>(
      `
        UPDATE venue_voting_competitions
        SET title = 'Weekend Voting Demo',
            registration_closes_at = now() + interval '8 seconds',
            starts_at = now() + interval '10 seconds',
            ends_at = now() + interval '20 seconds',
            max_votes_per_voter = 1
        WHERE id = $1
        RETURNING *
      `,
      [row.id]
    );
    return refreshed.rows[0];
  });
}

async function entriesForCompetition(competitionId: string, userId: string) {
  const result = await query<EntryRow>(
    `
      SELECT e.id AS entry_id,
             e.joined_at,
             count(v.id)::text AS vote_count,
             EXISTS (
               SELECT 1
               FROM venue_voting_votes vv
               WHERE vv.entry_id = e.id
                 AND vv.voter_id = $2
             ) AS has_voted,
             EXISTS (
               SELECT 1
               FROM venue_voting_competitions vc
               WHERE vc.id = e.competition_id
                 AND (
                   vc.title ILIKE '%demo%'
                   OR EXISTS (
                     SELECT 1
                     FROM checkins ci
                     WHERE ci.venue_id = vc.venue_id
                       AND ci.user_id = e.user_id
                   )
                 )
             ) AS is_winner_eligible,
             u.id, u.name, u.age, u.bio, u.profession, u.gender, u.height,
             u.interests, u.is_verified, u.is_ghost_mode, u.looking_for,
             pp.id AS photo_id,
             pp.storage_key,
             pp.cdn_url AS photo_url
      FROM venue_voting_entries e
      JOIN users u ON u.id = e.user_id
      LEFT JOIN profile_photos pp ON pp.user_id = u.id AND pp.position = 0
      LEFT JOIN venue_voting_votes v ON v.entry_id = e.id
      WHERE e.competition_id = $1
        AND u.is_active = true
        AND u.deletion_scheduled_at IS NULL
        AND u.is_flagged = false
        AND u.profile_completed = true
      GROUP BY e.id, u.id, pp.id, pp.storage_key, pp.cdn_url
      ORDER BY count(v.id) DESC, e.joined_at ASC
    `,
    [competitionId, userId]
  );

  return Promise.all(result.rows.map(async (row, index) => {
    const photos = row.photo_id && row.storage_key
      ? await withSignedPhotoUrls([{
        id: row.photo_id,
        storage_key: row.storage_key,
        cdn_url: row.photo_url ?? null,
        position: 0
      }])
      : [];

    return {
      entryId: row.entry_id,
      joinedAt: row.joined_at,
      voteCount: Number(row.vote_count),
      rank: index + 1,
      hasVoted: row.has_voted,
      isWinnerEligible: row.is_winner_eligible,
      profile: serializeProfile(row, [], photos as PhotoRow[])
    };
  }));
}

async function serializeCompetitionById(competitionId: string, userId: string) {
  const competition = await query<CompetitionRow>(
    "SELECT * FROM venue_voting_competitions WHERE id = $1",
    [competitionId]
  );
  if ((competition.rowCount ?? 0) === 0) return null;

  const row = competition.rows[0];
  const [entries, userEntry, userVotes] = await Promise.all([
    entriesForCompetition(row.id, userId),
    query<{ id: string }>(
      "SELECT id FROM venue_voting_entries WHERE competition_id = $1 AND user_id = $2",
      [row.id, userId]
    ),
    query<{ count: string }>(
      "SELECT count(*)::text FROM venue_voting_votes WHERE competition_id = $1 AND voter_id = $2",
      [row.id, userId]
    )
  ]);

  return serializeCompetition(
    row,
    entries,
    userEntry.rows[0]?.id ?? null,
    Number(userVotes.rows[0]?.count ?? 0)
  );
}

export async function venueVotingRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Params: { id: string } }>(
    "/venues/:id/voting",
    { preHandler: authenticate },
    async (request, reply) => {
      const venue = await query<{ id: string; name: string }>(
        "SELECT id, name FROM venues WHERE id = $1 AND is_active = true",
        [request.params.id]
      );
      if ((venue.rowCount ?? 0) === 0) return sendError(reply, 404, "Venue not found");

      const competitions = await Promise.all(
        votingCategories.map(async (category) => {
          const competition = await ensureTodayCompetition(request.params.id, category);
          return serializeCompetitionById(competition.id, request.auth.userId);
        })
      );

      return {
        venueId: request.params.id,
        venueName: venue.rows[0].name,
        competitions: competitions.filter(Boolean)
      };
    }
  );

  app.post<{ Params: { id: string } }>(
    "/venues/:id/voting/demo/restart",
    { preHandler: authenticate },
    async (request, reply) => {
      const venue = await query<{ id: string }>(
        "SELECT id FROM venues WHERE id = $1 AND is_active = true",
        [request.params.id]
      );
      if ((venue.rowCount ?? 0) === 0) return sendError(reply, 404, "Venue not found");

      const competitions = await Promise.all(
        votingCategories.map(async (category) => {
          const competition = await ensureTodayCompetition(request.params.id, category);
          const resetCompetition = await resetDemoCompetition(competition);
          return serializeCompetitionById(resetCompetition.id, request.auth.userId);
        })
      );

      await broadcastVenueVotingUpdate(request.params.id, null, "demo_restarted");

      return {
        competitions: competitions.filter(Boolean)
      };
    }
  );

  app.post<{ Params: { id: string; category: string } }>(
    "/venues/:id/voting/:category/join",
    { preHandler: authenticate },
    async (request, reply) => {
      const category = normalizeCategory(request.params.category);
      if (!category) return sendError(reply, 400, "Unknown voting category");

      const user = await query<{ gender: string | null }>(
        "SELECT gender FROM users WHERE id = $1 AND profile_completed = true",
        [request.auth.userId]
      );
      if ((user.rowCount ?? 0) === 0) return sendError(reply, 403, "Complete your profile to join voting");

      const venue = await query<{ id: string }>(
        "SELECT id FROM venues WHERE id = $1 AND is_active = true",
        [request.params.id]
      );
      if ((venue.rowCount ?? 0) === 0) return sendError(reply, 404, "Venue not found");

      const competition = await ensureTodayCompetition(request.params.id, category);
      if (categoryForGender(user.rows[0].gender) !== category) {
        return sendError(reply, 403, "Join the voting category that matches your profile.");
      }

      if (!(await hasActiveVenueCheckin(request.auth.userId, request.params.id))) {
        return sendError(reply, 403, "Check in at this venue to join voting.");
      }

      if (Date.now() >= new Date(competition.registration_closes_at).getTime()) {
        return sendError(reply, 409, "Registration is closed for this competition");
      }

      await query(
        `
          INSERT INTO venue_voting_entries(competition_id, user_id)
          VALUES ($1, $2)
          ON CONFLICT (competition_id, user_id) DO NOTHING
        `,
        [competition.id, request.auth.userId]
      );

      const serialized = await serializeCompetitionById(competition.id, request.auth.userId);
      await broadcastVenueVotingUpdate(request.params.id, category, "joined");
      return { competition: serialized };
    }
  );

  app.post<{ Params: { competitionId: string; entryId: string } }>(
    "/venue-voting/:competitionId/entries/:entryId/vote",
    { preHandler: authenticate },
    async (request, reply) => {
      const competitionResult = await query<CompetitionRow>(
        "SELECT * FROM venue_voting_competitions WHERE id = $1",
        [request.params.competitionId]
      );
      if ((competitionResult.rowCount ?? 0) === 0) return sendError(reply, 404, "Competition not found");

      const competition = competitionResult.rows[0];
      const phase = phaseFor(competition);
      if (phase === "registration") return sendError(reply, 409, "Voting has not opened yet");
      if (phase === "ended") return sendError(reply, 409, "Voting has ended");
      if (!(await hasActiveVenueCheckin(request.auth.userId, competition.venue_id))) {
        return sendError(reply, 403, "Check in at this venue to vote.");
      }

      const entry = await query<{ user_id: string }>(
        "SELECT user_id FROM venue_voting_entries WHERE id = $1 AND competition_id = $2",
        [request.params.entryId, request.params.competitionId]
      );
      if ((entry.rowCount ?? 0) === 0) return sendError(reply, 404, "Entry not found");
      if (entry.rows[0].user_id === request.auth.userId) return sendError(reply, 409, "You cannot vote for yourself");

      const voteResult = await withTransaction(async (client) => {
        const used = await client.query<{ count: string }>(
          "SELECT count(*)::text FROM venue_voting_votes WHERE competition_id = $1 AND voter_id = $2",
          [request.params.competitionId, request.auth.userId]
        );
        if (Number(used.rows[0]?.count ?? 0) >= 1) {
          return { status: "limit" as const };
        }

        const inserted = await client.query(
          `
            INSERT INTO venue_voting_votes(competition_id, voter_id, entry_id)
            VALUES ($1, $2, $3)
            ON CONFLICT (competition_id, voter_id) DO NOTHING
            RETURNING id
          `,
          [request.params.competitionId, request.auth.userId, request.params.entryId]
        );
        if ((inserted.rowCount ?? 0) === 0) return { status: "limit" as const };
        return { status: "ok" as const };
      });

      if (voteResult.status === "limit") {
        return sendError(reply, 409, "You already voted in this competition");
      }

      const serialized = await serializeCompetitionById(request.params.competitionId, request.auth.userId);
      await broadcastVenueVotingUpdate(competition.venue_id, competition.category, "voted");
      return { competition: serialized };
    }
  );

  app.get(
    "/venue-voting/history",
    { preHandler: authenticate },
    async (request) => {
      const result = await query<HistoryRow>(
        `
          WITH ranked AS (
            SELECT c.id,
                   e.user_id,
                   rank() OVER (PARTITION BY c.id ORDER BY count(v.id) DESC, e.joined_at ASC) AS entry_rank
            FROM venue_voting_competitions c
            JOIN venue_voting_entries e ON e.competition_id = c.id
            LEFT JOIN venue_voting_votes v ON v.entry_id = e.id
            WHERE c.ends_at <= now()
              AND EXISTS (
                SELECT 1
                FROM checkins ci
                WHERE ci.venue_id = c.venue_id
                  AND ci.user_id = e.user_id
              )
            GROUP BY c.id, e.id
            HAVING count(v.id) > 0
          )
          SELECT c.id,
                 c.venue_id,
                 ve.name AS venue_name,
                 c.category,
                 c.title,
                 c.prize_amount_cents,
                 c.ends_at,
                 count(v.id)::text AS total_votes,
                 count(v.id) FILTER (WHERE v.voter_id = $1)::text AS user_votes,
                 COALESCE((
                   SELECT count(received_votes.id)::text
                   FROM venue_voting_entries own_entry
                   LEFT JOIN venue_voting_votes received_votes ON received_votes.entry_id = own_entry.id
                   WHERE own_entry.competition_id = c.id
                     AND own_entry.user_id = $1
                 ), '0') AS user_received_votes,
                 EXISTS (
                   SELECT 1 FROM venue_voting_entries own
                   WHERE own.competition_id = c.id AND own.user_id = $1
                 ) AS user_joined,
                 EXISTS (
                   SELECT 1 FROM ranked r
                   WHERE r.id = c.id AND r.user_id = $1 AND r.entry_rank = 1
                 ) AS user_won
          FROM venue_voting_competitions c
          JOIN venues ve ON ve.id = c.venue_id
          LEFT JOIN venue_voting_votes v ON v.competition_id = c.id
          WHERE c.id IN (
            SELECT competition_id FROM venue_voting_votes WHERE voter_id = $1
            UNION
            SELECT competition_id FROM venue_voting_entries WHERE user_id = $1
          )
          GROUP BY c.id, ve.name
          ORDER BY c.ends_at DESC
          LIMIT 30
        `,
        [request.auth.userId]
      );

      return {
        history: result.rows.map((row) => ({
          id: row.id,
          venueId: row.venue_id,
          venueName: row.venue_name,
          category: row.category,
          title: row.title,
          prizeAmountCents: row.prize_amount_cents,
          endedAt: row.ends_at,
          totalVotes: Number(row.total_votes),
          votesCast: Number(row.user_votes),
          votesReceived: Number(row.user_received_votes),
          userJoined: row.user_joined,
          userWon: row.user_won
        }))
      };
    }
  );
}
