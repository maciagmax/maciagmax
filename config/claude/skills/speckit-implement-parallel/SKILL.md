---
name: "speckit-implement-parallel"
description: "Execute tasks.md as a team of parallel Claude agents — one git worktree, one branch, and one cmux pane per user story. Runs the blocking Setup/Foundational phases first, then fans out. Stops and reports; never merges."
argument-hint: "Optional guidance, or a lane filter like 'US1,US3'"
compatibility: "Requires spec-kit project structure (.specify/), git >= 2.5 (worktrees), and the cmux CLI"
metadata:
  author: "maciagmax"
  based-on: "speckit-implement"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). It is either extra
implementation guidance to pass through to every lane, or a lane filter (`US1,US3`) restricting
which user stories get an agent.

## What this skill is

`/speckit-implement` executes every task in `tasks.md` sequentially in one session. This skill does
the same work, but splits the user-story phases across a team of Claude agents, each in its own git
worktree, on its own branch, in its own cmux pane inside **the workspace you invoked this from**.

**The contract, stated up front so you do not have to infer it:**

- Phases that `tasks.md` marks as blocking prerequisites (Setup, Foundational) run **here, in this
  session, on the current branch**, sequentially, and are committed before anything fans out.
- Each user-story phase becomes one **lane**: one branch, one worktree, one cmux pane, one agent.
- The Polish / Cross-Cutting phase is **never** given a lane. It depends on all stories and is
  reported at the end as remaining work.
- **This skill never merges.** It stops when the agents finish and reports branches, status, and a
  suggested merge order. Merging is the user's call.
- **This skill never deletes a worktree or branch** without explicit confirmation.

## Step 0 — Preflight gates

Run these first. Any failure is a **hard stop** with a clear message — do not work around it.

1. **cmux reachable and this session is inside it:**

   ```bash
   cmux identify
   ```

   Parse `caller.workspace_ref` and `caller.surface_ref` from the JSON. Record
   `WS=<caller.workspace_ref>`. If `cmux` is not on PATH, or `identify` reports no caller workspace,
   stop: this skill has nowhere to put the panes. Suggest `/speckit-implement` instead.

2. **Clean working tree.** `git worktree add` on a dirty tree strands uncommitted work on the base
   branch where no lane can see it:

   ```bash
   git status --porcelain
   ```

   Must be empty. If not, stop and list the dirty paths; ask the user to commit or stash.

3. **Spec-kit prerequisites:**

   ```bash
   .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
   ```

   Parse `FEATURE_DIR` and `AVAILABLE_DOCS`. All paths absolute.

4. **Checklists gate** — identical to `/speckit-implement`. If `FEATURE_DIR/checklists/` exists,
   scan every file, count `- [ ]` vs `- [X]`/`- [x]`, print the status table, and if any item is
   unchecked **STOP and ask** whether to proceed. Treat markers as read-only; never edit them.

5. **Extension pre-hooks** — if `.specify/extensions.yml` exists, honour `hooks.before_implement`
   exactly as `/speckit-implement` does (dots to hyphens, mandatory hooks actually invoked and
   awaited, conditions left to the HookExecutor).

Record these for the rest of the run:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
FEATURE_SLUG=$(basename "$FEATURE_DIR")            # e.g. 003-github-assigned-issues
SWARM_ROOT="$(dirname "$REPO_ROOT")/${REPO_NAME}-swarm/${FEATURE_SLUG}"
```

`SWARM_ROOT` lives **outside** the repository on purpose: worktrees, briefs, and status files must
not appear in `git status`, test globs, or file watchers.

## Step 1 — Load the implementation context

Read, from `FEATURE_DIR`:

- **REQUIRED** `tasks.md` — the task list, phases, `[P]` markers, and the two sections that drive
  the partition: **"Dependencies & Execution Order"** and **"Parallel Opportunities"**.
- **REQUIRED** `plan.md` — tech stack, architecture, file structure, package manager.
- **IF EXISTS** `spec.md`, `data-model.md`, `contracts/`, `research.md`, `quickstart.md`.
- **IF EXISTS** `.specify/memory/constitution.md`.

Read the "Dependencies & Execution Order" and "Parallel Opportunities" sections **in full and
literally**. They are written by `/speckit-tasks` for exactly this purpose and they routinely name
the specific files two stories will collide on. Do not infer a dependency graph you could have read.

## Step 2 — Partition tasks.md into lanes

Parse the `## Phase N: ...` headings in order and classify each:

| Heading matches | Classification |
|---|---|
| Appears **before** the first `User Story` phase (Setup, Foundational, Blocking Prerequisites) | **Shared** — runs here, sequentially, on `BASE_BRANCH` |
| `## Phase N: User Story M — ...` | **Lane** — one agent |
| Polish, Cross-Cutting, or any phase **after** the last user story | **Deferred** — no agent, reported at the end |

For every lane record: the story id (`US1`), its priority (`P1`/`P2`/…), its title, and the **exact,
verbatim task lines** belonging to it, including IDs, `[P]` markers, and full descriptions. The
brief in Step 6 quotes these verbatim — never paraphrase a task.

**Then apply the declared dependency graph.** Build waves:

- **Wave 1** = every lane whose only prerequisites are the Shared phases.
- **Wave 2** = lanes that "Dependencies & Execution Order" says depend on a Wave 1 lane. And so on.

It is common and expected for a feature to declare something like *"once US1 is complete, US2 and
US3 can be built in parallel"* — that puts US1 alone in Wave 1. **Do not silently ignore this**, and
do not silently obey it either; Step 3 puts the choice to the user.

If `$ARGUMENTS` names a lane filter, drop the lanes it excludes and say so in the plan.

## Step 3 — Present the launch plan and get approval

Print, and stop for approval before creating anything:

```text
## Parallel implementation plan — <FEATURE_SLUG>

Base branch:  <BASE_BRANCH>   (clean)
Worktrees:    <SWARM_ROOT>/wt/
cmux:         <N> panes in <WS>, stacked right of this one

### Runs here first (sequential, committed to <BASE_BRANCH>)
  Phase 1 Setup .............. T001–T005
  Phase 2 Foundational ....... T006–T012

### Wave 1 — launches in parallel
  US1  P1  See everything assigned to me    T013–T031  → <FEATURE_SLUG>-us1
### Wave 2 — blocked by US1 per tasks.md "Dependencies & Execution Order"
  US2  P2  Tell what is new / going stale   T032–T045  → <FEATURE_SLUG>-us2
  US3  P3  Narrow the list                  T046–T058  → <FEATURE_SLUG>-us3
     ⚠ declared collision if forced parallel: src/main/assigned/queries.ts

### Never given a lane
  Phase 6 Polish & Cross-Cutting  T059–T066  (depends on all stories)

Per-worktree setup cost: <install command> × <N>
```

Then ask **one** question, offering exactly these choices:

1. **Waves (respects tasks.md)** — launch Wave 1 only; when it finishes, offer to launch Wave 2.
2. **Force full parallel** — launch every lane now from `BASE_BRANCH`, accepting the collisions
   tasks.md named. Name the specific colliding files in the question so the choice is informed.
3. **Adjust** — the user edits the partition.

Proceed only on an explicit answer.

## Step 4 — Run the shared phases here

Execute the Shared phases in this session, on `BASE_BRANCH`, following `/speckit-implement`'s
execution rules: phase by phase, respecting dependencies, `[P]` tasks together, tests before code,
same-file tasks sequential, verify each phase before the next.

Also perform `/speckit-implement`'s **Project Setup Verification** here — create or verify the
ignore files for the detected stack — because every worktree inherits it.

Mark each finished task `[X]` in `FEATURE_DIR/tasks.md`, and **commit**. The lanes branch from this
commit, so anything uncommitted here is invisible to all of them.

If a shared task fails, **halt**. Do not fan out onto a broken foundation.

## Step 5 — Create the worktrees

For each lane to launch:

```bash
LANE=us1                                        # lowercased story id
BRANCH="${FEATURE_SLUG}-${LANE}"
WT="${SWARM_ROOT}/wt/${LANE}"
mkdir -p "$(dirname "$WT")"
git worktree add -b "$BRANCH" "$WT" "$BASE_BRANCH"
```

If `$BRANCH` already exists, stop and ask — never reuse or force-reset a branch you did not create
in this run.

Then make each worktree actually usable:

1. **Local settings.** `.claude/settings.local.json` is git-ignored, so a fresh worktree has none
   and the agent will re-prompt for permissions you have already granted:

   ```bash
   [ -f "$REPO_ROOT/.claude/settings.local.json" ] && \
     mkdir -p "$WT/.claude" && \
     cp "$REPO_ROOT/.claude/settings.local.json" "$WT/.claude/settings.local.json"
   ```

   (`.claude/skills/` is tracked, so the worktree gets the spec-kit skills for free.)

2. **Dependencies.** A fresh worktree has no `node_modules` / `.venv`, so tests cannot run. Detect
   the package manager from the lockfile and `plan.md`, and run the install in each worktree. Run
   these **in the background, in parallel across worktrees**, and wait for all of them before
   launching agents — an agent that starts before its install finishes will hit confusing failures.
   Report the install result per worktree.

3. **Copy any git-ignored file the tests genuinely need** (e.g. `config.toml`, `.env`) only if
   `quickstart.md` says so. Never copy secrets the user has not pointed you at.

## Step 6 — Write one brief per lane

Write each brief to `${SWARM_ROOT}/briefs/${LANE}.md`. The brief is the agent's entire starting
context — it must stand alone. Use this structure:

```markdown
# <FEATURE_SLUG> — <US id>: <story title> (<priority>)

You are one of <N> agents implementing this feature in parallel. You own **<US id> only**.

## Your workspace
- Worktree:        <WT>            (you are already here; never `cd` out of it)
- Your branch:     <BRANCH>
- Branched from:   <BASE_BRANCH> @ <sha>
- Other lanes:     <list other US ids and their branches>

## Read first
- specs/<FEATURE_SLUG>/spec.md          — the user story you own and its acceptance criteria
- specs/<FEATURE_SLUG>/plan.md          — tech stack, architecture, file layout
- specs/<FEATURE_SLUG>/tasks.md         — full context; **your phase is <Phase N>**
- <the other AVAILABLE_DOCS, listed>
- .specify/memory/constitution.md       — governance constraints, if present

## Your tasks — implement these and only these, in order

<the verbatim task lines for this story, IDs, [P] markers and full text intact>

## Rules

1. **Stay in your lane.** Do not implement a task belonging to another user story, even if it looks
   trivial or blocking. If you are genuinely blocked by another lane's work, stop and record it in
   your status file rather than reaching across.
2. **Setup and Foundational phases are already done and committed** on <BASE_BRANCH>. Do not redo
   them. Do not re-run migrations that already exist.
3. **Tests before code**, per the task order. `[P]` tasks touch disjoint files and may go together.
4. **Commit per task or per logical group**, message prefixed `<US id>: `, so the merge is legible.
5. **Mark each finished task `[X]` in specs/<FEATURE_SLUG>/tasks.md** in *your* worktree. Every lane
   edits this same file, so it will conflict at merge time — that is expected and the orchestrator
   has flagged it. Change only your own task lines; never touch another story's lines or the prose.
6. **Never** merge, rebase, push, or force-push. Never touch another lane's branch or worktree.
7. **Validate before you finish**: run the project's test suite, and walk the `quickstart.md`
   scenarios that name your story.

## Extra guidance from the user
<$ARGUMENTS, or "none">

## When you are done

Write your status file — this is how the orchestrator knows you finished:

    mkdir -p <SWARM_ROOT>/status
    cat > <SWARM_ROOT>/status/<LANE>.done <<'EOF'
    lane: <US id>
    branch: <BRANCH>
    result: complete | partial | blocked
    tasks_done: <ids>
    tasks_not_done: <ids, with a one-line reason each>
    tests: <the command you ran, and pass/fail>
    files_touched: <paths>
    notes: <anything the merge needs to know — a collision you saw coming, an assumption you made>
    EOF

Write it even if you end blocked or partial. A missing status file is indistinguishable from a hung
agent, and the orchestrator will wait on it.
```

## Step 7 — Launch one cmux pane per lane

All commands below are verified against this cmux build. `new-pane`/`new-split` print
`OK surface:<n> pane:<n> workspace:<n>` — parse field 2 for the surface ref.

**First lane** — split a column off the workspace you were invoked from:

```bash
OUT=$(cmux new-pane --type terminal --direction right --workspace "$WS" --focus false)
S=$(awk '{print $2}' <<<"$OUT")
```

**Every later lane** — stack under the previous agent so the column divides evenly, rather than
splitting your own pane thinner each time:

```bash
OUT=$(cmux new-split down --surface "$PREV_S" --workspace "$WS" --focus false)
S=$(awk '{print $2}' <<<"$OUT")
```

**Label and launch:**

```bash
cmux rename-tab --surface "$S" "US1 · assigned list"
cmux send --surface "$S" "cd '$WT' && clear\n"
cmux send --surface "$S" 'claude "$(cat '"$BRIEF"')"\n'
```

The third line's quoting is deliberate and load-bearing: bash concatenates
`'claude "$(cat '` + `$BRIEF` + `')"\n'`, so cmux receives the literal text
`claude "$(cat /path/to/brief.md)"` and the `$(cat ...)` is expanded by the *target* pane's shell.
This keeps a multi-kilobyte, multi-line brief off the command line and out of every quoting trap.
cmux converts the trailing `\n` to Enter.

Record `PREV_S=$S` and keep a table of `lane → branch → worktree → surface ref → pane ref`.

Agents run with **normal permission prompting**. They will stop and wait for approval on edits and
commands, so visit the panes.

Cap the fan-out at **4 panes**. Beyond that the column is unreadable — tell the user and offer to
run the remainder as a second wave.

## Step 8 — Wait for the team

Arm a single monitor on the status files rather than polling screens:

```
Monitor(
  command: 'until [ "$(ls -1 <SWARM_ROOT>/status/*.done 2>/dev/null | wc -l)" -ge <N> ]; do
              for f in <SWARM_ROOT>/status/*.done; do
                [ -f "$f" ] && [ ! -f "$f.seen" ] && { echo "DONE: $(basename "$f" .done)"; touch "$f.seen"; }
              done
              sleep 20
            done
            echo "ALL LANES REPORTED"',
  description: 'speckit lanes reporting done for <FEATURE_SLUG>',
  persistent: true
)
```

While waiting, you may be asked to check on a lane. Read its pane directly — do not guess:

```bash
cmux read-screen --surface "$S" --lines 60
```

An agent that has gone quiet is usually sitting on a permission prompt. Say which pane, and what it
is asking for; do not answer it for the user by sending keystrokes unless they ask you to.

## Step 9 — Final report, and stop

Read every `${SWARM_ROOT}/status/*.done`, then report. **Do not merge. Do not rebase. Do not delete
anything.**

```text
## <FEATURE_SLUG> — parallel implementation complete

Base: <BASE_BRANCH> @ <sha>  (Setup + Foundational, T001–T012, committed)

| Lane | Branch | Result | Tasks | Tests | Pane |
|------|--------|--------|-------|-------|------|
| US1  | ...-us1 | complete | T013–T031 | 142 passed | surface:13 |
| US2  | ...-us2 | partial  | T032–T041 (T042–T045 blocked: …) | 8 failed | surface:14 |

### Suggested merge order  (priority, then declared dependencies)
  1. git merge <FEATURE_SLUG>-us1     # P1, MVP
  2. git merge <FEATURE_SLUG>-us2     # P2
  3. git merge <FEATURE_SLUG>-us3     # P3

### Expected conflicts
  - specs/<FEATURE_SLUG>/tasks.md — every lane marked its own tasks [X].
    Resolution is the union of the [X] marks; the prose is unchanged on all sides.
  - <any file two lanes reported touching, and what each did to it>

### Still unbuilt
  Phase 6 Polish & Cross-Cutting: T059–T066 — run after merging, with /speckit-implement.

### Worktrees left in place (nothing was deleted)
  <SWARM_ROOT>/wt/us1  →  <FEATURE_SLUG>-us1
  ...
  Tear down when you are done merging:
    git worktree remove <SWARM_ROOT>/wt/us1
    git branch -d <FEATURE_SLUG>-us1
```

Then honour `hooks.after_implement` from `.specify/extensions.yml` exactly as `/speckit-implement`
does — same dots-to-hyphens rule, same mandatory-hook `EXECUTE_COMMAND:` emission followed by an
actual invocation you wait on.

If the user chose **Waves** in Step 3 and a later wave is still pending, offer to launch it now:
its lanes branch from the merged result, so ask whether they want to merge Wave 1 first.

## Failure handling

- **A lane reports `blocked`** — report it verbatim. Do not reassign its tasks to another lane or
  finish them yourself without asking; the user may want the boundary preserved.
- **A pane died or the agent crashed** — the worktree and branch survive. Report the surface ref and
  offer to relaunch that one lane with the same brief.
- **The user interrupts mid-run** — worktrees, branches, and briefs all persist under `SWARM_ROOT`.
  Report exactly what exists so the run can be resumed or torn down deliberately.

## Done When

- [ ] Preflight gates passed: cmux caller workspace known, tree clean, prerequisites and checklists honoured
- [ ] Shared Setup/Foundational phases implemented, marked `[X]`, and committed to the base branch
- [ ] One worktree, branch, brief, and cmux pane created per approved lane, with deps installed
- [ ] All launched lanes have written a status file, or their absence is explained
- [ ] Final report delivered with per-lane status, suggested merge order, expected conflicts, deferred Polish tasks, and teardown commands
- [ ] Extension post-hooks dispatched or skipped
- [ ] **Nothing merged, nothing deleted**
