// Pure functions shared by the build (Node) and the generated page (browser).
// The build inlines this file into the page, so it must not import anything.

/** Split an evidence string ("file symbol; file symbol") into { file, symbol } references. */
export function codeRefs(text, codePaths = {}) {
  if (!text) return []
  const keys = Object.keys(codePaths).sort((a, b) => b.length - a.length)
  return String(text).split(';').map((part) => part.trim()).filter(Boolean).map((part) => {
    const full = part.match(/(?:^|\s)((?:[\w.-]+\/)+[\w.-]+\.[A-Za-z0-9]+)(?=\s|$|:)/)
    if (full) {
      const file = full[1]
      return { file: codePaths[file] || file, symbol: part.slice(part.indexOf(file) + file.length).replace(/^[\s:./-]+/, '').trim() }
    }
    for (const key of keys) {
      const at = part.indexOf(key)
      if (at < 0) continue
      const before = at === 0 || /[\s(]/.test(part[at - 1])
      const edge = part[at + key.length]
      if (!before || !(edge === undefined || /[\s:.]/.test(edge))) continue
      const symbol = `${part.slice(0, at)} ${part.slice(at + key.length)}`.replace(/^[\s:./-]+|[\s:./-]+$/g, '').replace(/\s+/g, ' ').trim()
      return { file: codePaths[key], symbol }
    }
    return { file: part, symbol: '' }
  })
}

/** The identifier a reference's symbol text names: its first word, cut at a call parenthesis. */
export function symbolToken(symbol) {
  const word = String(symbol || '').trim().split(/\s+/)[0] || ''
  return word.replace(/\(.*$/, '').replace(/[,.:;]+$/, '')
}

/** Participants as a tree, in declaration order, with each node's rank from the model's levels. */
export function participantTree(model) {
  const rank = new Map(model.levels.map((level, index) => [level.id, index]))
  const nodes = new Map(model.participants.map((p) => [p.id, { ...p, rank: rank.get(p.level), children: [] }]))
  const roots = []
  for (const p of model.participants) {
    const node = nodes.get(p.id)
    if (p.parent) nodes.get(p.parent)?.children.push(node)
    else roots.push(node)
  }
  const ancestors = (id) => {
    const chain = []
    let at = nodes.get(id)?.parent
    while (at) { chain.unshift(at); at = nodes.get(at)?.parent }
    return chain
  }
  return { nodes, roots, ancestors, rank }
}

/**
 * The lanes visible at a level, after per-node overrides. A branch descends while some child sits
 * at or above the chosen level; `expand` forces a node open and `collapse` folds it into one lane.
 * Returns lane ids in tree order.
 */
export function visibleLanes(tree, levelId, expand = new Set(), collapse = new Set()) {
  const limit = tree.rank.get(levelId)
  const out = []
  const visit = (node) => {
    if (!node.children.length || collapse.has(node.id)) { out.push(node.id); return }
    const open = expand.has(node.id) || node.children.some((child) => child.rank <= limit)
    if (open) node.children.forEach(visit)
    else out.push(node.id)
  }
  tree.roots.forEach(visit)
  return out
}

/** The visible lane that shows a participant: itself or its nearest visible ancestor. */
export function laneFor(tree, visible, id) {
  if (visible.has(id)) return id
  const chain = tree.ancestors(id)
  for (let k = chain.length - 1; k >= 0; k -= 1) if (visible.has(chain[k])) return chain[k]
  // A participant whose descendants are the visible lanes: use the first of them.
  const node = tree.nodes.get(id)
  const stack = node ? [...node.children] : []
  while (stack.length) { const next = stack.shift(); if (visible.has(next.id)) return next.id; stack.unshift(...next.children) }
  return id
}

/**
 * Lay out the lifecycle machine. Start and state nodes form the main row in transition order; a
 * success ending closes that row; cancelled endings and ghost states sit above, other endings below,
 * each near the states that reach it. Explicit `row` and `cx` on a node override the defaults.
 */
export function layoutMachine(machine) {
  const STEP = 160
  const SIZE = { main: { y: 240, h: 66 }, above: { y: 24, h: 60 }, below: { y: 432, h: 64 }, start: { y: 264, h: 18 } }
  const textWidth = (n) => {
    if (n.kind === 'start') return 18
    if (n.kind === 'state') return 104
    if (n.kind === 'ghost') return 124
    return Math.ceil(Math.max(130, (n.reason || '').length * 6.05 + 24, (n.consequence || '').length * 6 + 24, ((n.label || '').length + 2) * 7.4 + 20))
  }
  const row = (n) => n.row || (n.kind === 'start' || n.kind === 'state' ? 'main'
    : n.kind === 'ghost' ? 'above'
      : n.tone === 'success' ? 'main'
        : n.tone === 'cancelled' ? 'above' : 'below')
  const nodes = machine.nodes.map((n) => ({ ...n, row: row(n), w: textWidth(n) }))
  const byId = new Map(nodes.map((n) => [n.id, n]))
  const main = nodes.filter((n) => n.row === 'main')
  // Longest-path rank over forward edges among main-row nodes; edges that close a cycle are ignored.
  const next = new Map(main.map((n) => [n.id, []]))
  for (const t of machine.transitions) for (const from of t.from) {
    if (from !== t.to && next.has(from) && next.has(t.to)) next.get(from).push(t.to)
  }
  const rank = new Map()
  const start = main.find((n) => n.kind === 'start') || main[0]
  const walk = (id, depth, onStack) => {
    if ((rank.get(id) ?? -1) >= depth) return
    rank.set(id, depth)
    onStack.add(id)
    for (const to of next.get(id) || []) if (!onStack.has(to)) walk(to, depth + 1, onStack)
    onStack.delete(id)
  }
  if (start) walk(start.id, 0, new Set())
  const order = (n) => n.order ?? (n.kind === 'ending' ? 1e6 : rank.get(n.id) ?? 1e5)
  const declared = new Map(nodes.map((n, k) => [n.id, k]))
  main.sort((a, b) => order(a) - order(b) || declared.get(a.id) - declared.get(b.id))
  let x = 26
  main.forEach((n, k) => {
    if (n.cx == null) n.cx = k === 0 && n.kind === 'start' ? 26 : x
    x = n.cx + (k === 0 && n.kind === 'start' ? 108 : STEP)
  })
  for (const side of ['above', 'below']) {
    const members = nodes.filter((n) => n.row === side)
    for (const n of members) {
      if (n.cx != null) { n.want = n.cx; continue }
      const sources = machine.transitions.filter((t) => t.to === n.id).flatMap((t) => t.from).map((id) => byId.get(id)).filter((s) => s && s.row === 'main')
      n.want = sources.length ? sources.reduce((sum, s) => sum + s.cx, 0) / sources.length : Infinity
    }
    let right = -Infinity
    members.sort((a, b) => a.want - b.want || declared.get(a.id) - declared.get(b.id)).forEach((n) => {
      const want = Number.isFinite(n.want) ? n.want : right + 10 + n.w / 2
      n.cx = Math.max(want, right + 10 + n.w / 2, 6 + n.w / 2)
      right = n.cx + n.w / 2
    })
  }
  const boxes = new Map(nodes.map((n) => {
    const s = SIZE[n.kind === 'start' ? 'start' : n.row]
    return [n.id, { id: n.id, row: n.row, x: n.cx - n.w / 2, y: s.y, w: n.w, h: s.h, cx: n.cx, cy: s.y + s.h / 2, top: s.y, bottom: s.y + s.h, left: n.cx - n.w / 2, right: n.cx + n.w / 2 }]
  }))
  const width = Math.ceil(Math.max(...[...boxes.values()].map((b) => b.right)) + 12)
  // Without a row below the main one, the diagram ends under the main row.
  const height = nodes.some((n) => n.row === 'below') ? 540 : SIZE.main.y + SIZE.main.h + 40
  return { boxes, width, height }
}
