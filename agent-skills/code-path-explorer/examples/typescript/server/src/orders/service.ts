import { db } from '../db/pool'
import { lockCart, setAwaiting, savePaymentId, recordEvent, markPaidIfAwaiting } from '../db/orders-repo'
import { createPaymentIntent } from '../payments/provider'

export class Conflict extends Error {}

export async function startPayment(orderId: string, userId: string) {
  // Commit awaiting_payment before calling the provider, so the call is never inside a transaction.
  const order = await db.transaction(async (tx) => {
    const cart = await lockCart(tx, orderId, userId)
    if (!cart) throw new Conflict()
    await setAwaiting(tx, orderId)
    return cart
  })
  // The order id is the idempotency key: a retried request gets the same payment intent.
  const intent = await createPaymentIntent({ amount: order.amount, orderId, idempotencyKey: orderId })
  await savePaymentId(db, orderId, intent.id)
  return { clientSecret: intent.clientSecret }
}

export async function markPaid(eventId: string, orderId: string, amount: number) {
  await db.transaction(async (tx) => {
    if (!(await recordEvent(tx, eventId))) return // a redelivered event
    await markPaidIfAwaiting(tx, orderId, amount)
  })
}
