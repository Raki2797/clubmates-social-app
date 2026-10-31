import { closePool, query, withTransaction } from "../src/db/pool.js";

type DemoUser = {
  phone: string;
  name: string;
  age: number;
  profession: string;
  gender: string;
  interests: string[];
  photoUrl: string;
};

type CompetitionSpec = {
  category: "male" | "female" | "lgbtq";
  title: string;
  startsOffsetHours: number;
  endsOffsetHours: number;
  registrationClosesOffsetHours: number;
  entryPhones: string[];
  votePlan: Array<{ voterPhone: string; entryPhone: string }>;
};

const demoUsers: DemoUser[] = [
  { phone: "+910000100001", name: "Aarav Rao", age: 27, profession: "Product Designer", gender: "Male", interests: ["House", "Cocktails", "Travel"], photoUrl: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100002", name: "Kabir Mehta", age: 29, profession: "Founder", gender: "Male", interests: ["EDM", "Fitness", "Startups"], photoUrl: "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100003", name: "Vihaan Suri", age: 26, profession: "Architect", gender: "Male", interests: ["Jazz", "Food", "Design"], photoUrl: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100004", name: "Rhea Kapoor", age: 25, profession: "Brand Manager", gender: "Female", interests: ["Bollywood", "Dance", "Fashion"], photoUrl: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100005", name: "Ananya Shah", age: 24, profession: "Photographer", gender: "Female", interests: ["Live Music", "Art", "Coffee"], photoUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100006", name: "Meera Iyer", age: 28, profession: "Chef", gender: "Female", interests: ["Food", "House", "Travel"], photoUrl: "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100007", name: "Nisha Verma", age: 26, profession: "Stylist", gender: "Female", interests: ["Pop", "Fashion", "Rooftops"], photoUrl: "https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100008", name: "Sam Noor", age: 27, profession: "DJ", gender: "Non-binary", interests: ["Techno", "Art", "Community"], photoUrl: "https://images.unsplash.com/photo-1527980965255-d3b416303d12?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100009", name: "Ira Sen", age: 25, profession: "Illustrator", gender: "Queer", interests: ["Indie", "Design", "Poetry"], photoUrl: "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=1200&h=1500&q=90" },
  { phone: "+910000100010", name: "Dev Rai", age: 30, profession: "Producer", gender: "LGBTQ", interests: ["Commercial", "Film", "Dancing"], photoUrl: "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=1200&h=1500&q=90" }
];

const currentCompetitions: CompetitionSpec[] = [
  {
    category: "male",
    title: "Weekend Voting Demo",
    startsOffsetHours: 10 / 3600,
    endsOffsetHours: 20 / 3600,
    registrationClosesOffsetHours: 8 / 3600,
    entryPhones: ["+910000100001", "+910000100002", "+910000100003"],
    votePlan: []
  },
  {
    category: "female",
    title: "Weekend Voting Demo",
    startsOffsetHours: 10 / 3600,
    endsOffsetHours: 20 / 3600,
    registrationClosesOffsetHours: 8 / 3600,
    entryPhones: ["+910000100004", "+910000100005", "+910000100006", "+910000100007"],
    votePlan: [
      { voterPhone: "+910000100001", entryPhone: "+910000100004" },
      { voterPhone: "+910000100002", entryPhone: "+910000100004" },
      { voterPhone: "+910000100003", entryPhone: "+910000100004" },
      { voterPhone: "+910000100008", entryPhone: "+910000100005" },
      { voterPhone: "+910000100009", entryPhone: "+910000100005" },
      { voterPhone: "+910000100010", entryPhone: "+910000100006" }
    ]
  },
  {
    category: "lgbtq",
    title: "Weekend Voting Demo",
    startsOffsetHours: 10 / 3600,
    endsOffsetHours: 20 / 3600,
    registrationClosesOffsetHours: 8 / 3600,
    entryPhones: ["+910000100008", "+910000100009", "+910000100010"],
    votePlan: [
      { voterPhone: "+910000100001", entryPhone: "+910000100008" },
      { voterPhone: "+910000100002", entryPhone: "+910000100008" },
      { voterPhone: "+910000100003", entryPhone: "+910000100008" },
      { voterPhone: "+910000100004", entryPhone: "+910000100009" },
      { voterPhone: "+910000100005", entryPhone: "+910000100010" }
    ]
  }
];

async function seedUsers(): Promise<Map<string, string>> {
  const userIdsByPhone = new Map<string, string>();

  for (const user of demoUsers) {
    const result = await query<{ id: string }>(
      `
        INSERT INTO users(
          phone_e164,
          name,
          age,
          bio,
          profession,
          gender,
          height,
          interests,
          is_verified,
          is_active,
          profile_completed
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, true, true)
        ON CONFLICT (phone_e164)
        DO UPDATE SET
          name = EXCLUDED.name,
          age = EXCLUDED.age,
          bio = EXCLUDED.bio,
          profession = EXCLUDED.profession,
          gender = EXCLUDED.gender,
          height = EXCLUDED.height,
          interests = EXCLUDED.interests,
          is_verified = true,
          is_active = true,
          profile_completed = true,
          deletion_scheduled_at = NULL
        RETURNING id
      `,
      [
        user.phone,
        user.name,
        user.age,
        `${user.name} is part of the ClubMates weekend voting demo.`,
        user.profession,
        user.gender,
        168 + (user.age % 18),
        user.interests
      ]
    );
    userIdsByPhone.set(user.phone, result.rows[0].id);
    await query(
      `
        INSERT INTO profile_photos(user_id, storage_key, cdn_url, position)
        VALUES ($1, $2, $3, 0)
        ON CONFLICT (user_id, position)
        DO UPDATE SET
          storage_key = EXCLUDED.storage_key,
          cdn_url = EXCLUDED.cdn_url
      `,
      [result.rows[0].id, `demo-voting/v3/${user.phone}.jpg`, user.photoUrl]
    );
  }

  return userIdsByPhone;
}

async function chooseVenueId(): Promise<string> {
  const requestedVenueId = process.env.DEMO_VOTING_VENUE_ID?.trim();
  if (requestedVenueId) return requestedVenueId;

  const requestedVenueName = process.env.DEMO_VOTING_VENUE_NAME?.trim() ?? "10 Downing Street";
  const byName = await query<{ id: string }>(
    "SELECT id FROM venues WHERE lower(name) = lower($1) AND is_active = true LIMIT 1",
    [requestedVenueName]
  );
  if ((byName.rowCount ?? 0) > 0) return byName.rows[0].id;

  const fallback = await query<{ id: string }>(
    "SELECT id FROM venues WHERE is_active = true ORDER BY name LIMIT 1"
  );
  if ((fallback.rowCount ?? 0) === 0) {
    throw new Error("No active venues found. Run migrations/venue seed first.");
  }
  return fallback.rows[0].id;
}

function shiftedDate(hours: number): Date {
  return new Date(Date.now() + hours * 60 * 60 * 1000);
}

async function seedHistoricalCheckins(
  venueId: string,
  userIdsByPhone: Map<string, string>
): Promise<void> {
  for (const userId of userIdsByPhone.values()) {
    await query(
      `
        INSERT INTO checkins(user_id, venue_id, checked_in_at, checked_out_at)
        SELECT $1, $2, now() - interval '2 hours', now() - interval '90 minutes'
        WHERE NOT EXISTS (
          SELECT 1
          FROM checkins
          WHERE user_id = $1
            AND venue_id = $2
        )
      `,
      [userId, venueId]
    );
  }
}

async function seedCompetition(
  venueId: string,
  userIdsByPhone: Map<string, string>,
  spec: CompetitionSpec
): Promise<string> {
  return withTransaction(async (client) => {
    await client.query(
      `
        DELETE FROM venue_voting_competitions
        WHERE venue_id = $1
          AND category = $2
          AND (
            title = $3
            OR (title = 'Venue Voting' AND ends_at > now() - interval '12 hours' AND starts_at < now() + interval '12 hours')
          )
      `,
      [venueId, spec.category, spec.title]
    );

    const competition = await client.query<{ id: string }>(
      `
        INSERT INTO venue_voting_competitions(
          venue_id,
          category,
          title,
          prize_amount_cents,
          entry_fee_cents,
          platform_fee_cents,
          max_votes_per_voter,
          registration_closes_at,
          starts_at,
          ends_at
        )
        VALUES ($1, $2, $3, 200000, 20000, 2000, 1, $4, $5, $6)
        RETURNING id
      `,
      [
        venueId,
        spec.category,
        spec.title,
        shiftedDate(spec.registrationClosesOffsetHours),
        shiftedDate(spec.startsOffsetHours),
        shiftedDate(spec.endsOffsetHours)
      ]
    );

    const competitionId = competition.rows[0].id;
    const entryIdsByPhone = new Map<string, string>();

    for (const phone of spec.entryPhones) {
      const userId = userIdsByPhone.get(phone);
      if (!userId) continue;

      const entry = await client.query<{ id: string }>(
        `
          INSERT INTO venue_voting_entries(competition_id, user_id)
          VALUES ($1, $2)
          RETURNING id
        `,
        [competitionId, userId]
      );
      entryIdsByPhone.set(phone, entry.rows[0].id);
    }

    for (const vote of spec.votePlan) {
      const voterId = userIdsByPhone.get(vote.voterPhone);
      const entryId = entryIdsByPhone.get(vote.entryPhone);
      if (!voterId || !entryId) continue;

      await client.query(
        `
          INSERT INTO venue_voting_votes(competition_id, voter_id, entry_id)
          VALUES ($1, $2, $3)
          ON CONFLICT (competition_id, voter_id) DO NOTHING
        `,
        [competitionId, voterId, entryId]
      );
    }

    return competitionId;
  });
}

async function seedHistoryForAllUsers(
  venueId: string,
  userIdsByPhone: Map<string, string>
): Promise<void> {
  const existingUsers = await query<{ id: string }>(
    `
      SELECT id
      FROM users
      WHERE is_active = true
        AND deletion_scheduled_at IS NULL
      LIMIT 200
    `
  );
  const voterIds = existingUsers.rows.map((row) => row.id);

  const historyCompetitionId = await seedCompetition(venueId, userIdsByPhone, {
    category: "female",
    title: "Weekend Voting Demo History",
    startsOffsetHours: -56,
    endsOffsetHours: -51,
    registrationClosesOffsetHours: -56.25,
    entryPhones: ["+910000100004", "+910000100005", "+910000100006"],
    votePlan: []
  });

  const entries = await query<{ id: string; user_id: string }>(
    `
      SELECT id, user_id
      FROM venue_voting_entries
      WHERE competition_id = $1
      ORDER BY joined_at ASC
    `,
    [historyCompetitionId]
  );
  const winnerEntryId = entries.rows[0]?.id;
  if (!winnerEntryId) return;

  for (const voterId of voterIds) {
    await query(
      `
        INSERT INTO venue_voting_votes(competition_id, voter_id, entry_id)
        VALUES ($1, $2, $3)
        ON CONFLICT (competition_id, voter_id) DO NOTHING
      `,
      [historyCompetitionId, voterId, winnerEntryId]
    );
  }
}

async function main() {
  const venueId = await chooseVenueId();
  const userIdsByPhone = await seedUsers();
  await seedHistoricalCheckins(venueId, userIdsByPhone);

  for (const spec of currentCompetitions) {
    await seedCompetition(venueId, userIdsByPhone, spec);
  }
  await seedHistoryForAllUsers(venueId, userIdsByPhone);

  const venue = await query<{ name: string }>("SELECT name FROM venues WHERE id = $1", [venueId]);
  console.log(`Seeded venue voting demo for ${venue.rows[0]?.name ?? venueId}`);
  console.log("States available: Male, Female, and LGBTQ all start in 10 seconds and end 10 seconds later for demo testing. My Voting history is seeded.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
