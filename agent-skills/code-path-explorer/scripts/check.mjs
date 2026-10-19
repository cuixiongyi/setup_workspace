#!/usr/bin/env node
// Drives a built journey explorer in Chromium and fails on any broken interaction.
//
//   node check.mjs <explorer.html> [screenshot-dir]
//
// Uses the Playwright installed in the current directory's project, else the one installed beside
// these scripts (`npm install` in the folder above). If its bundled browser is missing, set
// CHROMIUM_PATH to any Chromium or Chrome executable. The check covers behaviour, not legibility:
// look at the screenshots for label collisions and clipping.
import { createRequire } from 'node:module'
import { readFileSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const [input, shots] = process.argv.slice(2)
if (!input) {
  console.error('usage: node check.mjs <explorer.html> [screenshot-dir]')
  process.exit(2)
}
const here = dirname(fileURLToPath(import.meta.url))
const playwright = () => {
  for (const base of [resolve('package.json'), join(here, '..', 'package.json')]) {
    try { return createRequire(base)('playwright') } catch (e) { if (e.code !== 'MODULE_NOT_FOUND') throw e }
  }
  console.error(`check.mjs: Playwright not found in ${process.cwd()} or ${resolve(here, '..')}; run \`npm install\` in ${resolve(here, '..')}`)
  process.exit(2)
}
const { chromium } = playwright()
const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {})
const page = await browser.newPage({ viewport: { width: 1512, height: 950 } })
const failures = []
const fail = (message) => failures.push(message)
page.on('pageerror', (e) => fail(`page error: ${e}`))
page.on('console', (m) => { if (m.type() === 'error') fail(`console: ${m.text()}`) })
await page.goto(pathToFileURL(resolve(input)).href)
if (shots) mkdirSync(shots, { recursive: true })
const shoot = async (name, full = false) => { if (shots) await page.screenshot({ path: join(shots, `${name}.png`), fullPage: full }) }

const model = await page.evaluate(() => JOURNEY)
const exported = JSON.parse(readFileSync(join(dirname(resolve(input)), model.export), 'utf8'))
if (JSON.stringify(exported) !== JSON.stringify(model)) fail(`embedded model differs from ${model.export}; rebuild the page`)

const inspector = async () => ({
  tag: (await page.locator('#inspector .tag').first().innerText()).trim(),
  title: (await page.locator('#inspector h3').innerText()).trim(),
  first: (await page.locator('#inspector dt').first().innerText().catch(() => '')).trim(),
})
const expectInspector = async (what) => {
  const seen = await inspector()
  if (!seen.title) fail(`${what}: inspector has no title`)
  if (seen.first.toLowerCase() !== 'code') fail(`${what}: inspector does not lead with code (first field is “${seen.first}”)`)
  return seen
}
const lanes = () => page.locator('#lane-head .lane').count()
const brokenGeometry = () => page.$$eval('#diagram path, #diagram rect, #diagram line', (els) => els.filter((el) => /NaN|undefined/.test(el.outerHTML)).length)

// Every path renders: a traced one draws its sequence, any other lists its transitions.
for (const path of model.lifecycle.paths) {
  await page.selectOption('#path-select', path.id)
  const rows = await page.locator('#diagram [data-sel^="interaction|"]').count()
  const walk = await page.locator('.walk-step').count()
  const crumb = await page.locator('#crumb .step').count()
  if (path.scenario && (rows === 0 || walk !== 0)) fail(`path ${path.id}: traced, but ${rows} sequence rows and ${walk} walk steps`)
  if (!path.scenario && (rows !== 0 || walk !== path.transitions.length)) fail(`path ${path.id}: expected ${path.transitions.length} walk steps, saw ${walk} (and ${rows} rows)`)
  if (crumb !== path.transitions.length) fail(`path ${path.id}: breadcrumb shows ${crumb} of ${path.transitions.length} steps`)
  await expectInspector(`path ${path.id}`)
}

// Every granularity draws every row of every traced scenario with resolved geometry.
const traced = model.lifecycle.paths.filter((p) => p.scenario)
await page.selectOption('#path-select', traced[0].id)
const levels = await page.$$eval('#levels [data-level]', (els) => els.map((el) => el.dataset.level))
const laneCounts = {}
for (const level of levels) {
  await page.selectOption('#path-select', traced[0].id)
  await page.locator(`#levels [data-level="${level}"]`).click()
  for (const path of traced) {
    await page.selectOption('#path-select', path.id)
    const expected = model.interactions.filter((i) => i.scenarios.includes(path.scenario)).length
    const rows = await page.locator('#diagram [data-sel^="interaction|"]').count()
    if (rows !== expected) fail(`level ${level}, path ${path.id}: ${rows} of ${expected} rows drawn`)
    if (await brokenGeometry()) fail(`level ${level}, path ${path.id}: an element has NaN or undefined geometry`)
  }
  laneCounts[level] = await lanes()
  await page.locator('#sequence').scrollIntoViewIfNeeded()
  await shoot(`level-${level}`)
}
const counts = levels.map((l) => laneCounts[l])
if (counts.some((n, k) => k && n < counts[k - 1])) fail(`a finer level shows fewer lanes: ${levels.map((l) => `${l} ${laneCounts[l]}`).join(', ')}`)

// Opening one lane adds lanes; folding a band removes them.
await page.locator(`#levels [data-level="${levels[0]}"]`).click()
await page.selectOption('#path-select', traced[0].id)
const before = await lanes()
// Open the lane with the most parts, so the lane count must grow.
const widest = await page.$$eval('#lane-head [data-lane^="expand|"]', (els) => els
  .map((el) => ({ sel: el.dataset.lane, parts: Number((el.getAttribute('aria-label').match(/its (\d+) parts/) || [])[1] || 0) }))
  .sort((a, b) => b.parts - a.parts)[0])
if (widest && widest.parts > 1) {
  await page.locator(`#lane-head [data-lane="${widest.sel}"]`).click()
  if ((await lanes()) <= before) fail('opening a lane did not add lanes')
  const folder = page.locator('#lane-head [data-lane^="collapse|"]').first()
  if (await folder.count()) {
    const opened = await lanes()
    await folder.click()
    if ((await lanes()) >= opened) fail('folding a band did not remove lanes')
  }
  await page.click('#reset-lanes')
  if ((await lanes()) !== before) fail('Reset lanes did not restore the level’s lanes')
}
await page.locator(`#levels [data-level="${model.defaultLevel}"]`).click()

// Every kind of selectable element opens an inspector that leads with code, on every traced path.
const kinds = new Set()
for (const path of traced) {
  await page.selectOption('#path-select', path.id)
  const targets = await page.$$eval('[data-sel]', (els) => {
    const first = new Map()
    for (const el of els) { const kind = el.dataset.sel.split('|')[0]; if (!first.has(kind) && kind !== 'path') first.set(kind, el.dataset.sel) }
    return [...first.values()]
  })
  for (const sel of targets) {
    // A problem button can switch to the path that contains its sequence row.
    await page.selectOption('#path-select', path.id)
    await page.locator(`[data-sel="${sel.replace(/"/g, '\\"')}"]`).first().dispatchEvent('click')
    await expectInspector(`${path.id} ${sel}`)
    kinds.add(sel.split('|')[0])
  }
}
for (const kind of ['transition', 'state', 'ending', 'interaction', 'participant']) if (!kinds.has(kind)) fail(`no selectable ${kind} was found`)
if (model.lifecycle.collisions.rows.length && !kinds.has('collision')) fail('no selectable collision cell was found')

// Problems: each card focuses the plot on that problem and leads its inspector with code.
for (const f of model.lifecycle.findings || []) {
  await page.selectOption('#path-select', model.lifecycle.paths[0].id)
  await page.locator(`#problem-cards [data-sel="finding|${f.id}"]`).click()
  await expectInspector(`problem ${f.id}`)
  if (f.path && (await page.$eval('#path-select', (s) => s.value)) !== f.path) fail(`problem ${f.id}: did not switch to its path ${f.path}`)
  if (await page.locator('#focus').isHidden()) fail(`problem ${f.id}: no focus banner over the sequence`)
  const placed = (f.nodes || []).length + (f.transitions || []).length + (f.interactions || []).length + (f.collisions || []).length + (f.steps || []).filter((s) => s.interaction || s.transition).length
  const lit = await page.locator('[data-focus]').count()
  if (placed && !lit) fail(`problem ${f.id}: names ${placed} places on the plot, but nothing is marked`)
  const steps = await page.locator('#inspector [data-step]').count()
  if (steps !== (f.steps || []).length) fail(`problem ${f.id}: inspector lists ${steps} of ${(f.steps || []).length} steps`)
  if (steps) {
    await page.locator('#inspector [data-step="0"]').click()
    if ((await page.locator('#inspector [data-step="0"]').getAttribute('aria-current')) !== 'step') fail(`problem ${f.id}: picking step 1 did not mark it`)
  }
  await shoot(`problem-${f.id}`)
  await page.locator('#focus [data-clear]').click()
  if (!(await page.locator('#focus').isHidden())) fail(`problem ${f.id}: Clear left the focus banner`)
}

// Keyboard: Enter on a focused arrow selects it, Escape returns to the path.
await page.selectOption('#path-select', model.lifecycle.paths[0].id)
await page.locator('#machine [data-sel^="transition|"][tabindex]').first().focus()
await page.keyboard.press('Enter')
if (!(await inspector()).tag.toLowerCase().startsWith('transition')) fail('Enter on a focused arrow did not select it')
await page.keyboard.press('Escape')
if (!(await inspector()).tag.toLowerCase().startsWith('path')) fail('Escape did not return to the path')

// Layout: the sequence scrolls with the page, and its lane header sticks under the bar. Use the
// longest traced sequence; one shorter than its own header cannot carry the header past the bar.
const longest = traced.slice().sort((p, q) => model.interactions.filter((i) => i.scenarios.includes(q.scenario)).length - model.interactions.filter((i) => i.scenarios.includes(p.scenario)).length)[0]
await page.selectOption('#path-select', longest.id)
const [scrollH, clientH] = await page.$eval('#diagram', (d) => [d.scrollHeight, d.clientHeight])
if (scrollH > clientH) fail('the sequence has an inner vertical scroller')
const room = await page.evaluate(() => {
  const stage = document.getElementById('stage').getBoundingClientRect(); const head = document.getElementById('lane-head').offsetHeight
  const bar = document.getElementById('bar').offsetHeight
  const travel = Math.min(200, stage.height - head - 20)
  const top = window.scrollY + stage.top - bar + travel
  // A page too short to scroll the stage under the bar cannot show the header sticking.
  if (travel <= 0 || top > document.documentElement.scrollHeight - window.innerHeight) return 0
  window.scrollTo({ top, behavior: 'instant' })
  return travel
})
if (room > 0) {
  await page.waitForTimeout(200)
  const head = await page.$eval('#lane-head', (e) => Math.round(e.getBoundingClientRect().top))
  const bar = await page.$eval('#bar', (e) => Math.round(e.getBoundingClientRect().bottom))
  if (Math.abs(head - bar) > 1) fail(`lane header is at ${head}px, the bar ends at ${bar}px`)
} else console.warn(`note: the page cannot scroll the sequence (${longest.id}) under the bar; the sticky header was not exercised`)
await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }))

// The rail (phases, step numbers, level names) stays at the left edge while the lanes scroll sideways.
await page.click('#levels [data-level]:last-child')
const sideways = await page.evaluate(() => {
  const diagram = document.getElementById('diagram')
  if (diagram.scrollWidth <= diagram.clientWidth) return null
  diagram.scrollLeft = 300
  return diagram.scrollLeft
})
if (sideways) {
  await page.waitForTimeout(100)
  const drift = await page.evaluate(() => {
    const edge = (id) => document.getElementById(id).getBoundingClientRect().left
    return [document.querySelector('#diagram .seq-rail').getBoundingClientRect().left - edge('diagram'), document.querySelector('#lane-head .rail-head').getBoundingClientRect().left - edge('lane-head')]
  })
  if (drift.some((d) => Math.abs(d) > 1)) fail(`the rail moved ${drift.map(Math.round).join('px and ')}px when the lanes scrolled ${sideways}px`)
  await shoot('rail-pinned')
  await page.evaluate(() => { document.getElementById('diagram').scrollLeft = 0 })
}
await page.click(`#levels [data-level="${model.defaultLevel}"]`)
await shoot('overview')
await shoot('page', true)
await browser.close()

if (failures.length) {
  for (const f of failures) console.error(`fail: ${f}`)
  process.exit(1)
}
console.log(`ok: ${model.lifecycle.paths.length} paths; lanes per level ${levels.map((l) => `${l} ${laneCounts[l]}`).join(', ')}; selectable kinds ${[...kinds].sort().join(', ')}; ${(model.lifecycle.findings || []).length} problems focused; expand/fold, keyboard, sticky header and rail, JSON parity`)
