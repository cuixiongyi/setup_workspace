import { test, expect } from 'vitest'
import { startPayment, markPaid } from '../src/orders/service'

test('startPayment refuses an order that is not a cart', async () => {
  await expect(startPayment(awaitingOrder.id, owner.id)).rejects.toThrow()
})

test('markPaid ignores a redelivered event', async () => {
  await markPaid('evt_1', order.id, order.amount)
  await markPaid('evt_1', order.id, order.amount)
  expect(await eventsFor(order.id)).toHaveLength(1)
})
