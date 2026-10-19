import { db } from '../db/pool'

/** Runs every minute. Releases stock held by orders nobody paid for. */
export async function expireStaleOrders() {
  await db`UPDATE shop.orders SET state = 'expired'
    WHERE state = 'awaiting_payment' AND payment_started_at < now() - interval '30 minutes'`
}
