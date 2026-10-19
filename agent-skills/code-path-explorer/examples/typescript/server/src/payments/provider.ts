// Thin client for the payment provider's HTTP API.
import { createHmac, timingSafeEqual } from 'node:crypto'

const API = 'https://api.payments.example/v1'

export async function createPaymentIntent(input: { amount: number; orderId: string; idempotencyKey: string }) {
  const response = await fetch(`${API}/payment_intents`, {
    method: 'POST',
    headers: { authorization: `Bearer ${process.env.PROVIDER_KEY}`, 'idempotency-key': input.idempotencyKey },
    body: JSON.stringify({ amount: input.amount, metadata: { orderId: input.orderId } }),
  })
  if (!response.ok) throw new Error(`provider ${response.status}`)
  const body = await response.json()
  return { id: body.id as string, clientSecret: body.client_secret as string }
}

export function verifyWebhook(body: Buffer, signature: string | undefined) {
  const expected = createHmac('sha256', process.env.PROVIDER_WEBHOOK_SECRET!).update(body).digest()
  if (!signature || !timingSafeEqual(expected, Buffer.from(signature, 'hex'))) throw new Error('bad signature')
  return JSON.parse(body.toString('utf8'))
}
