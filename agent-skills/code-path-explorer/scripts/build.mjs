#!/usr/bin/env node
// Builds a self-contained journey explorer page from its JSON model.
//
//   node build.mjs <model.json> [out.html] [--root <repo>] [--no-source-check]
//
// The JSON is the source of truth; the page embeds it unchanged. The build refuses a model that
// breaks journey.schema.json, whose references do not resolve, whose paths do not connect, or whose
// evidence names a file or symbol the repository no longer has. The format reference ships with
// these scripts (references/format.md in the code-path-explorer skill).
import { readFileSync, writeFileSync, existsSync, statSync } from 'node:fs'
import { dirname, join, basename, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { codeRefs, symbolToken, participantTree, visibleLanes, layoutMachine } from './model.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const args = process.argv.slice(2)
const flag = (name) => { const k = args.indexOf(name); if (k < 0) return undefined; const [, value] = args.splice(k, 2); return value }
const noSources = args.includes('--no-source-check') && args.splice(args.indexOf('--no-source-check'), 1)
const rootArg = flag('--root')
const [input, output] = args
if (!input) {
  console.error('usage: node build.mjs <model.json> [out.html] [--root <repo>] [--no-source-check]')
  process.exit(2)
}
const model = JSON.parse(readFileSync(input, 'utf8'))
const errors = []
const warnings = []
const need = (ok, message) => { if (!ok) errors.push(message) }

// ---------- schema (a dependency-free subset of JSON Schema: the keywords journey.schema.json uses) ----------
const schema = JSON.parse(readFileSync(join(here, 'journey.schema.json'), 'utf8'))
const typeOf = (v) => (v === null ? 'null' : Array.isArray(v) ? 'array' : Number.isInteger(v) ? 'integer' : typeof v)
function validate(value, rule, at) {
  if (rule.$ref) return validate(value, schema.$defs[rule.$ref.replace('#/$defs/', '')], at)
  if (rule.enum && !rule.enum.includes(value)) return errors.push(`${at}: must be one of ${rule.enum.join(', ')}`)
  if (rule.type) {
    const types = [].concat(rule.type)
    const t = typeOf(value)
    if (!types.includes(t) && !(t === 'integer' && types.includes('number'))) return errors.push(`${at}: expected ${types.join(' or ')}, got ${t}`)
  }
  if (typeof value === 'string') {
    if (rule.minLength != null && value.length < rule.minLength) errors.push(`${at}: must not be empty`)
    if (rule.maxLength != null && value.length > rule.maxLength) errors.push(`${at}: longer than ${rule.maxLength}`)
  }
  if (Array.isArray(value)) {
    if (rule.minItems != null && value.length < rule.minItems) errors.push(`${at}: needs at least ${rule.minItems} items`)
    if (rule.maxItems != null && value.length > rule.maxItems) errors.push(`${at}: allows at most ${rule.maxItems} items`)
    if (rule.items) value.forEach((item, k) => validate(item, rule.items, `${at}[${k}]`))
  }
  if (typeOf(value) === 'object') {
    const keys = Object.keys(value)
    if (rule.minProperties != null && keys.length < rule.minProperties) errors.push(`${at}: needs at least ${rule.minProperties} entries`)
    if (rule.maxProperties != null && keys.length > rule.maxProperties) errors.push(`${at}: allows at most ${rule.maxProperties} entries`)
    for (const key of rule.required || []) if (!(key in value)) errors.push(`${at}: missing ${key}`)
    for (const key of keys) {
      const sub = rule.properties?.[key]
      if (sub) validate(value[key], sub, `${at}.${key}`)
      else if (rule.additionalProperties === false) errors.push(`${at}: unknown field ${key}`)
      else if (typeof rule.additionalProperties === 'object') validate(value[key], rule.additionalProperties, `${at}.${key}`)
    }
  }
}
validate(model, schema, 'model')
if (errors.length) finish()

// ---------- references ----------
const ids = (rows) => new Set((rows || []).map((row) => row.id))
const unique = (rows, what) => need(ids(rows).size === (rows || []).length, `${what} ids are not unique`)
const levels = ids(model.levels)
unique(model.levels, 'level'); unique(model.participants, 'participant'); unique(model.scenarios, 'scenario'); unique(model.interactions, 'interaction')
need(levels.has(model.defaultLevel), `defaultLevel ${model.defaultLevel} is not a level`)
const people = new Map(model.participants.map((p) => [p.id, p]))
const tree = participantTree(model)
for (const p of model.participants) {
  need(levels.has(p.level), `participant ${p.id}: unknown level ${p.level}`)
  if (p.parent) {
    need(people.has(p.parent), `participant ${p.id}: unknown parent ${p.parent}`)
    const parent = people.get(p.parent)
    if (parent) need(tree.rank.get(p.level) > tree.rank.get(parent.level), `participant ${p.id}: level ${p.level} must be finer than its parent's ${parent.level}`)
  }
}
const scenarios = ids(model.scenarios)
const checkpoints = model.checkpoints || {}
const boundaries = model.boundaries || {}
const interactions = model.interactions
const interactionIds = ids(interactions)
for (const row of interactions) {
  need(people.has(row.from) && people.has(row.to), `interaction ${row.id}: unknown participant ${row.from} → ${row.to}`)
  for (const s of row.scenarios) need(scenarios.has(s), `interaction ${row.id}: unknown scenario ${s}`)
  if (row.checkpoint) need(checkpoints[row.checkpoint], `interaction ${row.id}: unknown checkpoint ${row.checkpoint}`)
  if (row.transaction) need((model.transactions || []).some((t) => t.id === row.transaction), `interaction ${row.id}: unknown transaction ${row.transaction}`)
  need(boundaries[row.boundary], `interaction ${row.id}: boundary ${row.boundary} is not in boundaries`)
  for (const p of row.relatedParticipants || []) need(people.has(p), `interaction ${row.id}: unknown related participant ${p}`)
}
for (const [id, c] of Object.entries(checkpoints)) need(people.has(c.owner), `checkpoint ${id}: unknown owner ${c.owner}`)
for (const tx of model.transactions || []) {
  need(interactionIds.has(tx.start) && interactionIds.has(tx.end), `transaction ${tx.id}: unknown start or end row`)
  need(people.has(tx.span), `transaction ${tx.id}: unknown span ${tx.span}`)
  if (tx.owner) need(people.has(tx.owner), `transaction ${tx.id}: unknown owner ${tx.owner}`)
}
for (const c of model.conditions || []) {
  for (const s of c.scenarios) need(scenarios.has(s), `condition ${c.id}: unknown scenario ${s}`)
  for (const i of c.interactions) need(interactionIds.has(i), `condition ${c.id}: unknown interaction ${i}`)
}

// ---------- lifecycle ----------
const life = model.lifecycle
const machine = life.machine
const nodes = new Map(machine.nodes.map((n) => [n.id, n]))
const transitions = new Map(machine.transitions.map((t) => [t.id, t]))
unique(machine.nodes, 'node'); unique(machine.transitions, 'transition'); unique(life.paths, 'path')
need(machine.nodes.filter((n) => n.kind === 'start').length === 1, 'the machine needs exactly one start node')
for (const n of machine.nodes) {
  if (n.kind === 'state' || n.kind === 'ghost') need(machine.states[n.id], `node ${n.id}: no states entry`)
  if (n.kind === 'ending') {
    need(life.endings[n.id], `node ${n.id}: no endings entry`)
    need(n.tone && n.reason && n.consequence, `node ${n.id}: an ending needs tone, reason and consequence`)
  }
  for (const chip of n.chips || []) need(machine.chips?.[chip], `node ${n.id}: unknown chip ${chip}`)
  if (n.checkpoint) need(checkpoints[n.checkpoint], `node ${n.id}: unknown checkpoint ${n.checkpoint}`)
}
for (const id of Object.keys(life.endings)) need(nodes.get(id)?.kind === 'ending', `endings.${id}: no ending node`)
for (const id of Object.keys(machine.states)) need(['state', 'ghost'].includes(nodes.get(id)?.kind), `states.${id}: no state node`)
for (const t of machine.transitions) {
  for (const from of t.from) need(nodes.has(from), `transition ${t.id}: unknown from ${from}`)
  need(nodes.has(t.to), `transition ${t.id}: unknown to ${t.to}`)
  need(machine.writers[t.writer], `transition ${t.id}: unknown writer ${t.writer}`)
  need(nodes.get(t.to)?.kind !== 'start', `transition ${t.id}: nothing enters the start node`)
}
for (const p of life.paths) {
  for (const id of p.transitions) need(transitions.has(id), `path ${p.id}: unknown transition ${id}`)
  need(nodes.has(p.end), `path ${p.id}: unknown end ${p.end}`)
  const first = transitions.get(p.transitions[0])
  if (first) need(first.from.some((f) => nodes.get(f)?.kind === 'start'), `path ${p.id}: does not begin at the start node`)
  const last = transitions.get(p.transitions.at(-1))
  if (last) need(last.to === p.end, `path ${p.id}: ends at ${p.end} but its last transition goes to ${last.to}`)
  p.transitions.forEach((id, k) => {
    const here = transitions.get(id); const next = transitions.get(p.transitions[k + 1])
    if (here && next) need(next.from.includes(here.to), `path ${p.id}: step ${k + 2} does not leave ${here.to}`)
  })
  if (p.scenario) need(scenarios.has(p.scenario), `path ${p.id}: unknown scenario ${p.scenario}`)
}
for (const row of interactions) if (row.transition) need(transitions.has(row.transition), `interaction ${row.id}: unknown transition ${row.transition}`)
for (const finding of life.findings || []) {
  for (const id of finding.nodes || []) need(nodes.has(id), `finding ${finding.id}: unknown node ${id}`)
  for (const id of finding.transitions || []) need(transitions.has(id), `finding ${finding.id}: unknown transition ${id}`)
  for (const id of finding.interactions || []) need(interactionIds.has(id), `finding ${finding.id}: unknown interaction ${id}`)
  for (const id of finding.participants || []) need(people.has(id), `finding ${finding.id}: unknown participant ${id}`)
  const path = finding.path && life.paths.find((p) => p.id === finding.path)
  if (finding.path) need(path, `finding ${finding.id}: unknown path ${finding.path}`)
  for (const cell of finding.collisions || []) {
    need(life.collisions.cells.some((c) => c.row === cell.row && c.col === cell.col), `finding ${finding.id}: no collision cell ${cell.row} × ${cell.col}`)
  }
  ;(finding.steps || []).forEach((step, k) => {
    if (step.transition) need(transitions.has(step.transition), `finding ${finding.id} step ${k + 1}: unknown transition ${step.transition}`)
    if (!step.interaction) return
    const row = interactions.find((i) => i.id === step.interaction)
    need(row, `finding ${finding.id} step ${k + 1}: unknown interaction ${step.interaction}`)
    if (row && path?.scenario) need(row.scenarios.includes(path.scenario), `finding ${finding.id} step ${k + 1}: ${row.id} is not in its path's scenario ${path.scenario}`)
  })
}
for (const id of life.cardOrder || []) need(nodes.has(id), `cardOrder: unknown node ${id}`)
const { rows, cols, cells } = life.collisions
for (const r of rows) {
  need(nodes.has(r.state), `collision row ${r.id}: unknown state ${r.state}`)
  for (const c of cols) need(cells.filter((x) => x.row === r.id && x.col === c.id).length === 1, `collision ${r.id} × ${c.id}: needs exactly one cell`)
}
for (const c of cells) {
  for (const id of c.transitions) need(transitions.has(id), `collision ${c.row} × ${c.col}: unknown transition ${id}`)
  if (c.end) need(nodes.has(c.end), `collision ${c.row} × ${c.col}: unknown end ${c.end}`)
}
const used = new Set(life.paths.flatMap((p) => p.transitions))
const idle = machine.transitions.filter((t) => !used.has(t.id)).map((t) => t.id)
if (idle.length) warnings.push(`transitions no path takes: ${idle.join(', ')}`)
const unrouted = machine.nodes.filter((n) => n.kind === 'ending' && !life.paths.some((p) => p.end === n.id)).map((n) => n.id)
if (unrouted.length) warnings.push(`endings no path reaches: ${unrouted.join(', ')}`)
for (const level of model.levels) {
  const lanes = visibleLanes(tree, level.id)
  if (lanes.length > 60) warnings.push(`level ${level.id} shows ${lanes.length} lanes; consider a detail view`)
}
const layout = layoutMachine(machine)
if (layout.width > 2400) warnings.push(`the lifecycle diagram is ${layout.width} units wide; consider splitting the machine`)

// ---------- source drift ----------
// Runs even when other checks failed, so one build reports every problem. The schema already passed.
if (!noSources) {
  const root = resolve(rootArg || findRoot(dirname(resolve(input))))
  const sites = []
  const add = (text, at) => { if (text) sites.push([text, at]) }
  model.participants.forEach((p) => add(p.about.evidence, `participant ${p.id}`))
  model.scenarios.forEach((s) => add(s.evidence, `scenario ${s.id}`))
  interactions.forEach((i) => add(i.evidence, `interaction ${i.id}`))
  Object.entries(checkpoints).forEach(([id, c]) => add(c.evidence, `checkpoint ${id}`))
  ;(model.conditions || []).forEach((c) => add(c.tests, `condition ${c.id}`))
  ;(model.transactions || []).forEach((t) => add(t.evidence, `transaction ${t.id}`))
  Object.entries(machine.writers).forEach(([id, w]) => add(w.evidence, `writer ${id}`))
  add(machine.chipEvidence, 'machine.chipEvidence')
  Object.entries(machine.states).forEach(([id, s]) => add(s.evidence, `state ${id}`))
  machine.transitions.forEach((t) => { add(t.evidence, `transition ${t.id}`); add(t.tests, `transition ${t.id} tests`) })
  Object.entries(life.endings).forEach(([id, e]) => add(e.evidence, `ending ${id}`))
  cells.forEach((c) => add(c.evidence, `collision ${c.row} × ${c.col}`))
  ;(life.findings || []).forEach((f) => add(f.evidence, `finding ${f.id}`))
  const files = new Map()
  const read = (file) => {
    if (!files.has(file)) {
      const path = join(root, file)
      files.set(file, existsSync(path) && statSync(path).isFile() ? readFileSync(path, 'utf8') : null)
    }
    return files.get(file)
  }
  let refs = 0
  for (const [text, at] of sites) {
    for (const ref of codeRefs(text, model.codePaths)) {
      refs += 1
      const body = read(ref.file)
      if (body == null) { errors.push(`${at}: ${ref.file} does not exist under ${root}`); continue }
      const token = symbolToken(ref.symbol)
      if (!token) continue
      const tail = token.split(/\.|::/).at(-1)
      // Prose documents cite headings, whose capitalisation varies; code is matched exactly.
      const prose = /\.(md|txt)$/i.test(ref.file)
      const has = (needle) => (prose ? body.toLowerCase().includes(needle.toLowerCase()) : body.includes(needle))
      if (!has(token) && !(tail && has(tail))) errors.push(`${at}: ${ref.file} has no “${token}”`)
    }
  }
  console.log(`sources: ${refs} references in ${files.size} files checked under ${root}`)
}

finish()

function findRoot(dir) {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, '.git'))) return at
    if (dirname(at) === at) return process.cwd()
  }
}

function finish() {
  for (const w of warnings) console.warn(`warning: ${w}`)
  if (errors.length) {
    for (const e of errors) console.error(`error: ${e}`)
    console.error(`${errors.length} error${errors.length > 1 ? 's' : ''}; nothing written`)
    process.exit(1)
  }
  const template = readFileSync(join(here, 'template.html'), 'utf8')
  const shared = readFileSync(join(here, 'model.mjs'), 'utf8').replace(/^export /gm, '')
  for (const marker of ['/*__SHARED__*/', '/*__JOURNEY__*/null']) if (!template.includes(marker)) throw new Error(`template has no ${marker} marker`)
  const embedded = JSON.stringify(model).replace(/</g, '\\u003c')
  const target = output || join(dirname(input), `${basename(input, '.json')}.html`)
  writeFileSync(target, template.replace('/*__SHARED__*/', () => shared).replace('/*__JOURNEY__*/null', () => embedded))
  console.log(`wrote ${target}: ${model.participants.length} participants on ${model.levels.length} levels, ${interactions.length} interactions, ${machine.transitions.length} transitions, ${life.paths.length} paths`)
  process.exit(0)
}
