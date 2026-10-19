// The checkout page. The card is confirmed in the browser by the provider's script; the server
// learns the outcome only from the provider's webhook.
import { loadProvider } from './provider-js'

export async function payOrder(orderId: string): Promise<void> {
  const response = await fetch(`/orders/${orderId}/pay`, { method: 'POST' })
  if (response.status === 409) throw new Error('This order is already being paid')
  if (!response.ok) throw new Error(`pay failed: ${response.status}`)
  const { clientSecret } = await response.json()
  const provider = await loadProvider()
  await provider.confirmPayment(clientSecret)
}
