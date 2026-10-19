import { Router, raw } from 'express'
import { verifyWebhook } from '../payments/provider'
import { markPaid } from '../orders/service'

export const webhooksRouter = Router()

// The provider retries any delivery that does not get a 2xx.
webhooksRouter.post('/webhooks/payments', raw({ type: 'application/json' }), async function paymentWebhook(req, res) {
  const event = verifyWebhook(req.body, req.header('Provider-Signature'))
  if (event.type === 'payment_intent.succeeded') await markPaid(event.id, event.data.orderId, event.data.amount)
  res.status(200).end()
})
