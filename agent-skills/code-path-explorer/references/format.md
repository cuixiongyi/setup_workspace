# Journey explorer

A journey explorer is one self-contained HTML page about one user journey through a system. It
opens on the **lifecycle** of the durable state the journey changes: every state, every way it
moves, who moves it, and every way it ends with what the ending costs the person. Pick a **path**
through that lifecycle to see its **sequence**, an interaction-by-interaction diagram whose lanes
can be shown at any granularity the model declares. A **collision table** shows what happens when
events such as a cancel, a lost worker or a deadline arrive in each state.

The page is generated. The JSON model is the source: edit the model, never the HTML.

Paths below are relative to the skill folder, the folder that holds `SKILL.md`.

| File | Role |
|---|---|
| `scripts/journey.schema.json` | The format, as JSON Schema. Point an editor at it with `"$schema"`. |
| `scripts/build.mjs` | Validates a model and writes its page. No dependencies beyond Node 20 or later. |
| `scripts/check.mjs` | Drives a built page in Chromium and fails on broken interactions. |
| `scripts/template.html` | The page renderer. Change it only to improve every explorer. |
| `scripts/model.mjs` | Pure functions shared by the build and the page: evidence parsing, lane folding, diagram layout. |
| `examples/python/` | A Python service (FastAPI-style routes, a worker, PostgreSQL) with its model and page. |
| `examples/typescript/` | A TypeScript service (Express-style routes, a payment provider, PostgreSQL) with its model and page. |

Start a new model from the example closer to the system you are tracing. Each example carries the
few source files its evidence cites, so it builds with `--root` set to its own folder.

## Workflow

Keep models and pages in the repository they describe, for example under `docs/plots/`:

```sh
node <skill>/scripts/build.mjs docs/plots/<name>.json            # writes docs/plots/<name>.html
node <skill>/scripts/check.mjs docs/plots/<name>.html [shots/]   # browser check, optional screenshots
```

The build fails, and writes nothing, when:

- the model breaks the schema, including an unknown field;
- a reference does not resolve: a participant, scenario, checkpoint, transaction, boundary,
  transition, node, ending or collision cell;
- a participant's level is not finer than its parent's;
- a path does not start at the start node, a step does not leave the state the previous step
  entered, or its last step does not reach its `end`;
- a collision row lacks a cell for some column, or has two;
- an evidence string names a file that does not exist, or a symbol that no longer appears in that
  file.

It warns about transitions no path takes, endings no path reaches, a level with more than 60 lanes,
and a lifecycle diagram too wide to read. Report each warning as untraced work; do not delete the
transition to silence it.

Build options:

- `--root <dir>` checks evidence against another checkout. The default is the nearest directory
  above the model that holds `.git`.
- `--no-source-check` skips the evidence check, for a model of a system you cannot read. Say so in
  the model's `note`.

`check.mjs` uses the Playwright of the project it runs in, and otherwise the one installed in the
skill folder by `npm install` there. A Python repository needs only the skill's copy. If
Playwright's bundled browser is not installed, run `npx playwright install chromium` in the skill
folder or set `CHROMIUM_PATH` to any Chromium or Chrome executable. It checks:

- every path renders, as a sequence or as a transition walk;
- every level draws every row with resolved geometry, and a finer level never shows fewer lanes;
- opening a lane, folding a band and Reset work;
- every kind of selectable element opens an inspector that leads with code;
- every problem focuses the plot on its path, marks what it names, lists its steps and clears;
- keyboard selection and Escape work;
- the sequence has no inner scroller, its lane header sticks under the bar, and its rail stays at the
  left edge while the lanes scroll sideways;
- the embedded model equals the JSON file.

It checks behaviour, not legibility, so look at the screenshots as well.

## The model

### Participants and levels: lanes at any granularity

A **lane** is one participant drawn as one column. A **level** is a granularity the lanes can be
drawn at; the page's **Granularity** switcher picks one. `levels` lists them, coarsest first. Unless
the person asked for another granularity, use this tree and open the page at the component level:

```json
"levels": [
  { "id": "host", "label": "Host" },
  { "id": "process", "label": "Process" },
  { "id": "component", "label": "Component / schema" },
  { "id": "file", "label": "File" },
  { "id": "unit", "label": "Function / table" }
],
"defaultLevel": "component"
```

A host is where code runs (the person's device, the servers). A process is one running program or
store: a browser, an API process, a worker, a database. A component is a boundary inside a process,
such as the HTTP layer, the service layer or data access, or a schema inside a database. Under those
sit files, then functions, methods, SQL routines, triggers and tables. At the default level the page
shows two band rows, hosts and processes, above one lane per component.

`participants` is one tree. Each node names its `parent` and its `level`, and a child's level must
be finer than its parent's. A branch may skip levels: a database schema can go straight from `component`
to `unit`-level tables. A branch may also stop early where finer detail was not traced. Give
every participant an `about` with `what` and `evidence`. `kind` (process, file, function, table,
route, trigger…) and `detail` (the path or qualified name) appear in the inspector.

Give the tree enough grouping levels that the default level shows one or two band rows above its
lanes, for example host → process → component → file → function. Each band row is named in the rail
beside it by its level. The rail, with the row phases, the step numbers and the level names, stays
pinned at the left while wide lanes scroll sideways, and a band whose start has scrolled under it keeps
its name beside the rail.

The page shows the lanes of the chosen level. A branch opens while some child is at that level or
coarser, and otherwise shows as one lane. At any level, **+** on a lane opens it into its parts and
**−** on a band folds the group back into one lane. `defaultLevel` is the level the page opens at.

An interaction's `from` and `to` name participants at the finest level you traced. At a coarser
level the arrow is drawn between their nearest visible ancestors. When both ends fold into one lane,
the arrow becomes a loop; **Hide calls inside one lane** removes those rows, except rows that change
a checkpoint. The same holds for a checkpoint's `owner` and a transaction's `span`. Trace at the
finest granularity you can support with evidence, then use levels to read it coarser. Do not draw a
coarse model and pretend it has detail.

### Sequence

- `scenarios`: one per traced message-level sequence.
- `interactions`: in order. Each has the scenarios it appears in, a `phase` for the row band, a
  `boundary` key, a `delivery` (`delivered`, `refused` or `not-sent`), a summary, the payload
  (`mechanism`, `example`, `fields`, `rules`) and `evidence`. Optional links: `checkpoint` (the pill
  it produces), `transition` (the lifecycle move it carries), `transaction`, and `invocation` (shared
  by the rows of one call when a function lane is entered more than once).
- `boundaries`: the kinds of crossing this system has, each with a `label`, an optional arrow
  `badge`, and `internal: true` when it is work inside the receiver rather than another round trip
  (SQL inside a function, a trigger, a cache read).
- `checkpoints`: a state change shown as a pill on its `owner`'s lane.
- `transactions`: from the `start` to the `end` interaction, drawn over the `span` participant's
  lanes.
- `conditions`: branch predicates and failures, each with impact, detection, recovery and tests.

### Lifecycle

`lifecycle.machine` is the state machine of the concept the journey changes (`title`, such as Job,
Order or Session), stored at `subject`.

- **nodes**: exactly one `start`; `state` nodes with a one-line `fact` and outstanding-obligation
  `chips`; `ending` nodes with a `tone` (`success`, `failure`, `cancelled` or `neutral`), a `reason`
  and a one-line `consequence` for the person; and `ghost` nodes for states the schema allows but
  nothing reaches. Split an ending by reason when the reasons differ in what the person pays, keeps
  or loses.
- **states**: for each state, its `meaning`, the `facts` on the record, what it `owes` while the
  concept sits there, and `evidence`.
- **transitions**: one or more `from` states, a `to`, the `writer` that moves it (at most four,
  defined in `writers` with the authority each acts under), the `guard`, the `effect`, `evidence`,
  located `tests`, and `reach`:
  - `deployed`: reachable in the target deployment today;
  - `substitute`: runs only with a test double or fixture;
  - `untraced`: allowed by the source, with no traced sequence. The page also shows any transition
    that no traced path takes as untraced.
- **chips**: short marker → meaning. `chipKinds` marks the external ones, such as work in flight at
  a provider.

`lifecycle.endings` gives each ending its `record`, `cost`, `result`, `external` state, what the
person has `seen`, and what is still `owed` after the end and who discharges it.

`lifecycle.paths` are ordered walks of transition ids from the start node, each ending at an ending
or at a named non-terminal state, with `note` saying how it continues. A path with a `scenario`
links to that traced sequence. A path with `scenario: null` appears as its transition walk, with a
notice that no sequence is traced. Keep such paths: they are the untraced work list.

`lifecycle.collisions` has `rows` (states, or groups of states that share their consequential facts)
× `cols` (events that can arrive at any moment) → exactly one cell each, with the result, the
ending or state it leads to, the transitions it uses, and evidence. A cell that cannot occur says
why, with `end: null`.

`lifecycle.findings` are the problems the plot explains: gaps found while modelling and every
finding the review reports for this journey. Each has a `label`, a `detail`, `evidence`, an optional
`issue` link and `rank` (`P1` launch-blocking, `P2` serious, `P3` limited, latent or missing proof).
The explanation fields appear in its card and inspector: `kind`, `invariant` (what must hold),
`impact`, `reproduction`, `owner` (the boundary that owns the repair), `repair` (a proposal, never
implemented behaviour) and `closure` (the evidence that would close it). The placement fields put it
on the plot: `nodes`, `transitions`, `interactions`, `participants`, `collisions` (`{ row, col }`
cells), `path` (the path that shows it) and `steps`, an ordered walk of `{ text, mark, interaction?,
transition? }` where `mark` is `holds`, `breaks` or `missing`. A step's interaction must belong to
the path's scenario. When a problem has a failure schedule, trace that schedule as its own scenario
and path, and point the steps at its rows.

Selecting a problem switches to its path, outlines its states, endings and collision cells, draws
its transitions in its rank colour (dashed when only a `missing` step names them), marks its lanes
with ⚑, dims the sequence rows it does not touch and numbers the rows it does by step. A banner over
the sequence steps through the walk; ⚡ marks where the invariant breaks and ∅ a step not taken.

**Layout** is automatic. The main row follows transition order from the start. A `success` ending
closes the main row. `cancelled` endings and ghosts sit above it, and other endings sit below, each
near the states that reach it. Override a node with `row` (`main`, `above` or `below`), `order` or
`cx` only when the automatic result misleads.

### Evidence

Every `evidence` and `tests` string is `path symbol; path symbol`. Each part names a repository path
and, optionally, a symbol in it: a function, method, route, SQL routine, table or heading. Every
part needs its own path. `codePaths` maps short names to paths, so `postgres.ts claimJobs` can stand
for `apps/server/data/control/postgres.ts claimJobs`. Keep prose out of evidence: put it in
`summary`, `rules` or `detail`.

The build checks that each path exists and that the symbol's first word appears in the file. The
match is exact for code and ignores case for `.md` and `.txt` files. This catches a renamed,
deleted or mis-cited symbol. It does not prove the behaviour the model describes. Behaviour claims
remain source-inspected and carry their own labels: `confidence`, `reach`, tests located or run, and
the revision in `note`.

### Page text

`title`, `lead` and `outside` support `` `code` `` spans. `note` states the revision and evidence
limits. `export` is the model's file name beside the page, and `related` holds links to other
pages.
