import { Router } from 'express'
import { startPayment, Conflict } from '../orders/service'

export const ordersRouter = Router()

ordersRouter.post('/orders/:id/pay', async function payOrderRoute(req, res) {
  try {
    const { clientSecret } = await startPayment(req.params.id, req.user.id)
    res.status(200).json({ clientSecret })
  } catch (error) {
    if (error instanceof Conflict) return res.status(409).end()
    throw error
  }
})
