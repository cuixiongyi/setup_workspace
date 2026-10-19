---
name: code-path-explorer
description: Build an evidence-backed, interactive HTML explorer for one user journey or code path through a codebase, in any language. It shows the lifecycle of the durable state the journey changes, every path and ending, a multi-lane sequence diagram that folds from hosts and processes down to functions and database tables, a collision table, and the problems found. Use when asked to plot, map, trace, explain or review a journey, request flow, state machine or failure path through code. Not for ordinary data charts.
---

# Code path explorer

Create an interactive HTML journey explorer for [FEATURE / USER JOURNEY / SYSTEM]. It opens on the lifecycle of the durable state the journey changes: every way that state moves and every way it ends. Each path through the lifecycle links to its sequence diagram, with component states, data flow, conditions, and failure explanations.

Paths in this skill are relative to the skill folder, the folder that holds this `SKILL.md`. Write the model and the generated page into the repository being described: in `docs/plots/` unless the user or the repository names another place.

## 1. Ask about scope if the user didn't provide it

Use scope and granularity already supplied by the user, by the repository's instructions, or by a user-invoked parent prompt or skill, without asking for confirmation. When a parent prompt or skill supplies the journey boundaries, included branches and granularity for several slices, use that scope for each slice without asking again. Record the boundaries and the discovered lane inventory before rendering. Ask only when a material boundary remains unresolved; continue independent work while waiting. This does not authorize changing the agreed scope.

Before generating the plot, ask only about missing scope: Which journey or process? Where does it start and end? Which systems, branches, and failure modes should be included or excluded? Use the user's terminology.

Granularity has a default; do not ask about it. A **lane** is one participant drawn as one column. A **granularity** is one level of the participant tree at which the lanes are drawn. Unless the user specifies otherwise, use five levels, coarsest first:

- **Host**: where code runs, such as the person's device or the servers.
- **Process**: one running program or store, such as the browser, an API process, a worker or the database.
- **Component / schema**: a boundary inside a process, such as the HTTP layer, the service layer or data access, or a schema inside a database.
- **File**: a source file.
- **Function / table**: every application-owned function or method and every SQL routine as a callable participant, and every database table touched by the traced scenarios as its own participant.

Open the page at the component level, so hosts and processes show as two band rows above one lane per component. Every function and table stays available by switching granularity or opening a lane.

When the user specifies a granularity, use it. They may name the lanes, for example Browser / API / Database; a service level, for example gateway, API services, queue, workers, databases and external dependencies; internal detail inside one component; or a mix that expands selected components and keeps others folded. If they ask to expand some components without naming them, ask which. Do not ask again for supplied boundaries, routine interactions, visual edits, or updates within an agreed scope.

## 2. Build an evidence-backed journey model

For an existing codebase, trace relevant entry points, calls, events, persistence, dependencies, and user-visible outcomes. Inspect source, tests, and available runtime evidence.

Represent:
- Participants: stable IDs, names, responsibilities, and optional parent/child components.
- Interactions: sender, receiver, trigger, ordering, transport or mechanism, payload, delivery outcome, and related state changes.
- States: owner, previous state, new state, triggering condition, side effects, and consequences elsewhere.
- Conditions and failures: branch predicate, impact, detection, recovery, guarantees, and verification.

Distinguish durable business state, transient handler/process state, local UI state, and derived or cached state. A component's belief about an outcome may differ from another component's actual state.

Label findings as code-confirmed, runtime-observed, inferred, proposed, or unknown. Record file/symbol references or trace references when available. Clearly label hypothetical examples and synthetic payloads. Never present missing recovery logic as implemented.

Model the lifecycle. For the durable concept whose state the journey changes (more than one when the journey hands off between owners), build its state machine from the code that enforces it: constraints, guard triggers, conditional updates and transition functions. Do not build it from the happy path. Record:
- States: meaning, the facts on the row in that state, and what is outstanding while the concept stays there: money held, deadlines running, external work in flight, unpublished data, leases. Include states the schema allows but no code writes or reads, and mark them as gaps.
- Transitions: source states, target, the writer and the authority it acts under, the guard, the effect, the evidence, the tests located, and reach. Reach is `deployed` (reachable in the target deployment today), `substitute` (runs only with a test double or fixture) or `untraced` (allowed by the source, no traced sequence).
- Endings: split a terminal state by reason when reasons differ in what the person pays, keeps or loses. For each ending record the durable row, the money outcome, the result, the external party's state, what the person sees, and what is still owed after the end and who discharges it.
- Paths: an ordered walk of transition IDs ending at an ending or at a named non-terminal state. Each consecutive step must leave the state the previous step entered. Link each traced scenario to its path, and each interaction that causes a transition to that transition's ID. A path without a traced sequence stays in the model and appears as its transition walk; never present it as traced.
- Collisions: a table whose rows are the non-terminal states, or groups of states that share their consequential facts, and whose columns are events that can arrive at any moment on this journey, such as a cancel, process loss, a deadline, a retryable error or a duplicate request. Each cell names the result, who resolves it, the transitions it uses and its evidence. A cell that cannot occur says why.
Every transition and ending either lies on a path or is reported as untraced work.

Include usage, billing, reconciliation and cleanup wherever the journey creates those obligations.

## 3. Generate the interactive plot

Deliver a self-contained HTML explorer with embedded styling and JavaScript. The JSON model is the source. Write it in the format defined by `scripts/journey.schema.json` and described in `references/format.md`. Start from the closer of `examples/python/cancel-export.json` and `examples/typescript/pay-order.json`. Generate the page with `node scripts/build.mjs <model.json> [out.html]`. The build refuses a model that breaks the schema, has references that do not resolve, or cites a file or symbol the repository no longer has. Do not hand-edit generated HTML. Change `scripts/template.html` only to improve every explorer; keep feature-specific text in the model.

Lay the page out in this order: the lifecycle diagram, the problems (section 4 below), one card per ending with the paths that reach it, the sequence or transition walk for the selected path, and the collision table. A selection inspector stays beside them. A sticky bar holds the path selector and the selected path's numbered steps.

In the lifecycle diagram, order the main states along the ordinary journey and put endings in rows beside them, grouped by kind of ending. Encode the writer by colour and also by a glyph on the arrow. Encode reach by line style: solid for deployed, dashed for substitute, dotted for untraced. Never let colour alone carry meaning. Show each state's outstanding obligations as labelled markers on the state. Dim arrows outside the selected path and number its steps.

In the sequence, show time/order along one axis and the agreed components as lanes. Show component states at relevant checkpoints, with clear alignment between an interaction and its resulting states.

Model lanes as one participant tree with named levels, coarsest first: the default host → process → component / schema → file → function / table from section 1, or the granularity the user supplied. Each participant declares its level; a branch may skip a level or stop where finer detail was not traced. Attach each interaction to the finest participants the evidence supports. The page then shows the journey at any granularity: an arrow is drawn between the nearest visible ancestors of its ends, a call inside one lane becomes a loop, and the reader can open one lane or fold one group without changing the model. Set `defaultLevel` to the component level, or to the most readable view of a supplied granularity, which must still exist as a level. Never coarsen the traced data to fit the page.

Give the tree enough grouping levels that every level from the default down shows at least one band row, and usually two, above its lanes. A grouping level is a real boundary, such as where a process runs, what it may do or what a store holds, with its own `about` and evidence; it is not a label for layout. Add a component or schema level inside a process whose files would otherwise push other processes off the first screen.

At function and table level, give each application-owned function/method in the traced scenarios and each touched schema-qualified database table its own participant and inspectable lane. Include helper functions and tables read indirectly through views, SQL routines, triggers, foreign-key actions or authorization policies. Represent executed SQL routines and trigger functions as callable participants, distinct from table participants. Do not drop a function or table merely because it is considered supporting, bookkeeping or read-only. Track framework/third-party boundaries as external/opaque when their internals are outside the inspected code; label unknown dynamic dispatch instead of inventing callees. Anonymous handlers need a real source location and enclosing route/symbol.

Keep a complete function-to-scenario and table-to-scenario inventory with stable IDs, evidence and links to their lanes. Show call/return or async handoff, arguments/results/errors, relevant state changes, and transaction context. Repeated/reentrant invocations have distinct invocation IDs even when sharing a function lane. Group lanes by their owning host/process/component using spanning group bands, not extra participant columns; keep group children contiguous. Preserve stable parent/group IDs in HTML and JSON. Use folding and linked phase/scenario detail views to manage size, while keeping every function/table available as a lane in at least one linked detail view. A high-level overview is optional and cannot replace required detail. Supporting indexes/constraints can stay in inspectors; the functions and tables they affect remain explicit.

Show database calls and transaction boundaries explicitly. Distinguish an application-to-database call, SQL executed internally by a database function, trigger effects, and reads from an in-process cache. Multiple table effects inside one function call must not appear as separate application calls. Mark BEGIN/COMMIT (and rollback where relevant), identify which statements share the transaction, and keep external network effects outside that transaction unless the code actually does otherwise. Check these boundaries against the current source when updating a plot.

The sequence is part of the page. Do not put it in a fixed-height frame or an inner vertical scroller. The page scrolls through the whole diagram. A sticky lane header may stay under the page controls while that happens. Horizontal overflow may scroll on its own only when the lanes are wider than the window; the first column (the row phases, step numbers and the names of the grouping levels) then stays pinned at the left, as the grouping bands stay pinned at the top, and each band keeps its name in view.

Lane headers are horizontal words. A modest diagonal rotation is fine when it keeps each name on one readable line. Do not set the letters in a vertical stack.

Interaction requirements:
- Select a path, from the bar or from an ending card: the diagram highlights it, the sequence shows its traced scenario, or, if none is traced, its transition walk with an explicit notice that no sequence exists yet.
- Click a lifecycle state: its meaning, the facts on the row, what is outstanding there, and the transitions that leave it.
- Click a transition: who moves it and under which authority, the guard, the effect, reach, tests located, and the paths that take it. Shade the sequence rows that carry it and offer a jump to them.
- Click an ending: what the person pays, the result, the external party's state, what the person sees, what is still owed after the end, and the paths that reach it.
- Click a collision cell: the result, who resolves it, the ending or state it leads to, and its transitions, which the diagram highlights.
- Click a state pill or an interaction in the sequence: link back to its lifecycle transition.
- Click a lane header: what that participant is, where that process or store runs, what it is allowed to do on this path, and the evidence. A folded group, such as a database, explains the group and that its children are the expanded lanes.
- Click a state/node: explain its owner, meaning, trigger, previous/new state, side effects, consequences across components, risks, and evidence.
- Click ANY edge: show exactly what crosses it—request, response, event, internal arguments, query parameters, result, or acknowledgement. Include a readable example payload, field types/meanings, important identifiers, validation rules, and delivery status.
- If no application payload exists, say so. If data is unknown, say so. Do not invent captured values.
- For a lost message, distinguish the attempted payload from what the receiver actually received.
- Click a condition: explain when it occurs, resulting states, user impact, detection, recovery, and tests.
- Click a problem: the page switches to the path that shows it, outlines its states, endings and collision cells, draws its transitions in its rank colour (dashed for a move the code never makes), marks its lanes, dims the sequence rows it does not touch, numbers the rows it does by step, and lets the reader step through its walk. The inspector gives its full explanation.
- Allow switching between every path: the normal journey, its failure and recovery paths, and paths not yet traced.
- Switch the granularity, open one lane into its parts, and fold a group band into one lane. Preserve the parent-child relationship and entry/exit boundaries at every granularity. Split into linked pages only when a single model would be unreadable at its finest level.

Include a selection inspector, a clear legend, readable labels, keyboard-accessible selection, and usable scrolling or zooming for the agreed diagram size. Split large journeys into linked views when that improves readability.

Every inspector description leads with the code that owns it. For a lane, an edge, a state, a transition, an ending, a collision cell, a condition, and the path shown before anything is selected, list each relevant file path and the function, method, or SQL routine in that file. Use the repository path, not a bare filename. If a step has no single function, name the route or schema object and say so. Do not invent a symbol that is not in the code.

## 4. Make failure consequences explicit

Always integrate the problems under review into the page: every finding the review reports for this journey, and every problem the user asked to be explained. Write each as a `lifecycle.findings` entry with its rank, kind, the invariant it breaks, what goes wrong, its impact on the person, its reproduction, the owning boundary, the proposed repair (labelled as a proposal) and the evidence that would close it, in the review's words. Place it on the plot: the states, transitions, sequence rows, lanes and collision cells it touches, the path that shows it, and an ordered walk of steps, each marked as holding, breaking or not taken. When a problem has a concrete failure schedule, such as a crash between two commits, a retry with another key or a race, trace that schedule as its own scenario and path, so the reader sees the rows where it breaks rather than only a note on the happy path. A problem that applies to the whole plot, such as missing runtime proof, still gets a card; say that it has no single place.

Investigate relevant cases such as invalid input, authorization failure, timeouts, lost responses, duplicate requests, partial writes, dependency outages, process crashes, retries, concurrency, stale reads, and cancellation races.

For each relevant failure, explain:
- What succeeded before the failure?
- What is persisted, pending, rolled back, or uncertain?
- What does each component know?
- What does the user see?
- Can retry duplicate effects? What enforces idempotency, if anything?
- How is the problem detected and recovered?
- Which tests or runtime checks establish the claimed behavior?

Only include failures relevant to the selected scope. Separate actual branches from hypothetical scenarios or proposed improvements.

## 5. Verify and deliver

Build with `node scripts/build.mjs <model.json>`. It fails on a schema violation, an unresolved reference, a path whose steps do not connect, an incomplete collision table, or evidence naming a missing file or symbol. Evidence is checked against the nearest directory above the model that holds `.git`; pass `--root <dir>` for another checkout. It warns about transitions and endings that no path reaches; report each of those as untraced work. The evidence check proves citations are current, not that the described behaviour is; keep behaviour claims labelled by their own evidence class.

Then run `node scripts/check.mjs <explorer.html> [screenshot-dir]`. It uses the project's Playwright, or else the one installed in the skill folder; if neither is installed, run `npm install` in the skill folder. If no Playwright browser is installed, run `npx playwright install chromium` there or set `CHROMIUM_PATH` to a Chromium or Chrome executable. It:
- switches to every path, and draws every traced scenario at every granularity;
- opens and folds lanes;
- selects every kind of element on every traced path and requires its inspector to lead with code;
- focuses every problem: its path is selected, something on the plot is marked when it names a place, every step is listed and can be picked, and Clear ends the focus;
- checks keyboard selection and Escape, page scrolling, the sticky lane header and the pinned rail;
- checks that the embedded model equals the JSON export.

Then look at the screenshots for label collisions, overflow and clipping; the script checks behaviour, not legibility.

Check that lifecycle transitions agree with the enforcing code, endings agree with the money and result code, and each collision cell agrees with the code paths it cites. Check scenario switching, lane-header selection, state selection, condition selection, and edge-payload inspection. Check that each inspector description shows the file path and function, that the sequence is not clipped to a fixed frame, that lane names read horizontally, and that labels, state transitions, arrows, and payloads agree with the model. Test layout in a browser when available and disclose any verification limits.

Verify lane granularity against the agreed scope. At function and table level, reconcile every inventoried function and touched database table to its own lane in the explorer or linked detail views, and every scenario interaction to real source evidence or an explicit unknown. Check group bands, expand/collapse and detail navigation, consistent group ownership in HTML/JSON, call/return and invocation identity, and transaction/lock boundaries. Internal database effects must not be counted as application round trips. No function or table may disappear solely to reduce diagram width.

Provide the working HTML and an exportable JSON journey model containing stable IDs, participants, interactions, states, conditions, payload definitions, evidence, and the lifecycle: machine states, transitions, endings, paths and collisions. If the diagram is based on a repository, identify the inspected revision when available. Keep credentials and sensitive data redacted.

When updating a feature, update affected paths and clearly identify which guarantees are implemented, missing, or proposed.
