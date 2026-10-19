// The Exports page in the browser.
export async function cancelExport(exportId) {
  const response = await fetch(`/exports/${exportId}/cancel`, { method: 'POST' })
  if (!response.ok) throw new Error(`cancel failed: ${response.status}`)
  return response.json()
}
