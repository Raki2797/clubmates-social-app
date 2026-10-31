import { FastifyInstance } from "fastify";
import { query, withTransaction } from "../db/pool.js";
import { deleteProfilePhotoObjects } from "../services/profilePhotoStorage.js";

const purgeIntervalMs = 15 * 60 * 1000;

type ExpiredDeletionUserRow = {
  id: string;
  phone_e164: string;
};

export async function purgeExpiredDeletedUsers(): Promise<number> {
  const expiredUsers = await query<ExpiredDeletionUserRow>(`
    SELECT id, phone_e164
    FROM users
    WHERE deletion_scheduled_at IS NOT NULL
      AND deletion_scheduled_at <= now()
  `);

  const expiredRows = expiredUsers?.rows ?? [];

  if (expiredRows.length === 0) {
    return 0;
  }

  const userIds = expiredRows.map((row) => row.id);
  const phoneNumbers = expiredRows.map((row) => row.phone_e164);
  const photos = await query<{ storage_key: string }>(
    `
      SELECT storage_key
      FROM profile_photos
      WHERE user_id = ANY($1::uuid[])
    `,
    [userIds]
  );

  await deleteProfilePhotoObjects(photos.rows.map((photo) => photo.storage_key));

  const deletedCount = await withTransaction<number>(async (client) => {
    await client.query("DELETE FROM otp_codes WHERE phone_e164 = ANY($1::text[])", [phoneNumbers]);
    await client.query("DELETE FROM refresh_tokens WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM device_tokens WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM messages WHERE sender_id = ANY($1::uuid[])", [userIds]);
    await client.query(
      `
        DELETE FROM messages
        WHERE match_id IN (
          SELECT id
          FROM matches
          WHERE user_a_id = ANY($1::uuid[])
             OR user_b_id = ANY($1::uuid[])
        )
      `,
      [userIds]
    );
    await client.query(
      `
        DELETE FROM reports
        WHERE reporter_id = ANY($1::uuid[])
           OR reported_id = ANY($1::uuid[])
           OR match_id IN (
             SELECT id
             FROM matches
             WHERE user_a_id = ANY($1::uuid[])
                OR user_b_id = ANY($1::uuid[])
           )
      `,
      [userIds]
    );
    await client.query("DELETE FROM blocks WHERE blocker_id = ANY($1::uuid[]) OR blocked_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM swipes WHERE actor_id = ANY($1::uuid[]) OR target_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM checkins WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM sos_events WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM matches WHERE user_a_id = ANY($1::uuid[]) OR user_b_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM profile_prompts WHERE user_id = ANY($1::uuid[])", [userIds]);
    await client.query("DELETE FROM profile_photos WHERE user_id = ANY($1::uuid[])", [userIds]);

    const result = await client.query<{ deleted_count: string }>(`
      WITH deleted AS (
      DELETE FROM users
      WHERE deletion_scheduled_at IS NOT NULL
        AND deletion_scheduled_at <= now()
        AND id = ANY($1::uuid[])
      RETURNING id
      )
      SELECT count(*)::text AS deleted_count
      FROM deleted
    `, [userIds]);

    return Number(result.rows[0]?.deleted_count ?? 0);
  });

  return deletedCount;
}

export function registerAccountDeletionPurge(app: FastifyInstance): void {
  const runPurge = async () => {
    try {
      const deletedCount = await purgeExpiredDeletedUsers();
      if (deletedCount > 0) {
        app.log.info({ deletedCount }, "Purged scheduled account deletions");
      }
    } catch (error) {
      app.log.error(error, "Failed to purge scheduled account deletions");
    }
  };

  void runPurge();

  const interval = setInterval(runPurge, purgeIntervalMs);
  interval.unref();

  app.addHook("onClose", async () => {
    clearInterval(interval);
  });
}
