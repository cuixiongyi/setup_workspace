import type { Sql } from './pool'

export async function lockCart(tx: Sql, orderId: string, userId: string) {
  const [row] = await tx`SELECT id, amount FROM shop.orders
    WHERE id = ${orderId} AND user_id = ${userId} AND state = 'cart' FOR UPDATE`
  return row
}

export async function setAwaiting(tx: Sql, orderId: string) {
  await tx`UPDATE shop.orders SET state = 'awaiting_payment', payment_started_at = now() WHERE id = ${orderId}`
}

export async function savePaymentId(db: Sql, orderId: string, paymentId: string) {
  await db`UPDATE shop.orders SET provider_payment_id = ${paymentId} WHERE id = ${orderId}`
}

/** False when this provider event was already recorded. */
export async function recordEvent(tx: Sql, eventId: string) {
  const rows = await tx`INSERT INTO shop.webhook_events (event_id) VALUES (${eventId})
    ON CONFLICT (event_id) DO NOTHING RETURNING event_id`
  return rows.length === 1
}

export async function markPaidIfAwaiting(tx: Sql, orderId: string, amount: number) {
  await tx`UPDATE shop.orders SET state = 'paid', paid_at = now()
    WHERE id = ${orderId} AND state = 'awaiting_payment' AND amount = ${amount}`
}
