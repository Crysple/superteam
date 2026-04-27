# Superteam Schema

This file documents two separate schemas that are both read by agents at
runtime:

1. **Wiki conventions** for `~/.superteam/*` (knowledge, skills, projects) -
 the persistent cross-session knowledge store.
2. **Shared session-state artifacts** under `.superteam/*` -
 `state.json`, `events.jsonl`, and `strict-evaluations.jsonl` - the
 three authoritative in-session coordination documents.

 `scripts/init-session.sh` copies this file to `~/.superteam/SCHEMA.md` at
each session start so the Curator, Explorer, Generator, and Evaluator
can read it without a path dependency on the plugin directory.

---

# Part 1 - Wiki Conventions (`~/.superteam/*`)

## Directory Structure

***
~/.superteam/
|- SCHEMA.md # This file - single source of wiki conventions
|- index.md # Content-oriented catalog with one-line summaries per entry
+- log.md # Append-only audit trail of all wiki changes
 | - knowledge/ # Facts about tools, platforms, patterns (one topic per file)
/- skills/ # Procedures - flat markdown files by default; directory format for skills needing scripts
/- projects/ # Per-project context and findings
**

## Write Protocol

All roles follow these steps when writing to `~/.superteam/*`:

1. Read this SCHEMA.md for conventions.
2. Write/update the file following the formats below.
3. Update `index.md` - add/update entry with one-line summary.
4. Append to `log.md` - what changed, which role, why.

## Write Permissions

| Role | Scope | When |
|------|-------|------|
| Curator | everything | Session end - sole writer to global wiki. Deep analysis, selective extraction, verified writes. |

Only the Curator writes to the global wiki. Explorer, Generator, and Evaluator write ONLY to session-local `.superteam/*` artifacts.

## File Formats

**Knowledge:** Plain markdown, no YAML frontmatter. One topic per file. Structure: `# Topic Name`, optional `## Subtopic`, optional `## See Also` with one-directional pointers (`- knowledge/related.md - reason`). No procedures (those are skills). No raw code snippets.

**Skills:** Plain markdown, no YAML frontmatter. Default format is a flat file at `skills/{name}.md`. Reserve the directory format (`skills/{name}/SKILL.md` + `scripts/` + `references/`) only for skills that genuinely need scripts or reference files. Discoverable through index.md.

Required sections for every skill file:

 # Skill: {Name}

 ## When to Use
 {1-2 sentences: trigger conditions for when this procedure applies}

 ## Prerequisites
 {What must be true before starting - tools, files, permissions}

 ## Steps
1. {Step with specific commands, file paths, or patterns}
 2. {Step}
 ...

 ## Common Errors
 | Error | Cause | Fix |
 |------- |------- |-----|

 ## See Also
 - {related entries - one-directional, per See Also Rules below}

**Projects:** Unchanged - `projects/<name>/context.md` + `findings/*.md`.

## Three Operations

### Ingest

**When:** Curator at session end, `/superteam-learn` ad hoc.

**No artificial budget.** Quality is the constraint. Every entry must pass the value filter:
1. Agent doesn't already know this (internal/undocumented knowledge)
2. Cost significant time to discover
3. Likely to be encountered again
4. Durable (not version-specific)

**Skill-specific evaluation:** For candidates describing multi-step procedures successfully applied in this session, evaluate additionally:
- Would a future Generator benefit from having these steps pre-documented?
- Does the procedure involveproject-specific file paths, naming conventions, or tool combinations?
- Did the session discover non-obvious ordering, prerequisites, or failure modes?

If yes to any, classify as skill even if individual steps are "known." The value of a skill is the specific combination and ordering of steps, not any individual step. A project-specific combination of known steps IS a skill.

**Flow:**
1. Dispatch subagents to read ALL session artifacts (knowledge base, "events.jsonl' decision/anomaly records via "jq', execution traces, attempts, lessons-learned).
2. Understand the session - what happened, what went well, what failed.
3. Extract candidate knowledge items AND candidate skills. For each increment in session artifacts, ask: "What multi-step procedure was followed? Is this procedure reusable?" If yes, create a skill candidate.
4. Evaluate each against the value filter (apply skill-specific evaluation for skill candidates).
5. Verify claims via subagents (tool commands, code patterns, platform facts).
6. Classify: procedure → skill, fact → knowledge, project-specific → project context. Look for `### Potential Skill` headings in `lessons-learned.md` as pre-identified skill candidates.
7. Check for existing entries in index.md - update in place if exists.
8. Write with proper format. Add `## See Also` listing related entries from current index.
9. Update index.md and append to log.md.

### Query

**When:** Explorer warm-start, any teammate during session.

**Flow:**
1. Read `index.md` - one-line summaries help decide which files to read without opening all.
2. Drill into specific files.
3. Follow `## See Also` pointers to related files.
4. Apply TTL rules (see Freshness below) to decide trust level.

### Lint

**When:** Curator runs after every ingest, before reporting to TL.

Two deterministic checks (no LLM judgment):
1. **Orphan check:** List all files in knowledge/, skills/, projects/. Flag any not in index.md.
2. **Stale check:** Check mtime vs TTL (see Freshness below). Flag past-TTL files. 

Append results to log.md. No auto-fix.

## Classification Decision Tree

- Is it a procedure (how to do something)? --> **Skill**
- Is it a fact about a tool/platform/concept? -> **Knowledge**
- Is it project-specific (architecture, convention, gotcha)? --> **Project context**
- Otherwise -> **Skip**

## What NOT to Persist

- Information derivable from code or git history (file paths, function signatures, recent changes)
- Raw code snippets - persist patterns and descriptions, not implementations
- Secrets, credentials, PII - never, under any circumstances
- Duplicates of information already in the knowledge store
- Within-session-stale info("current branch is X", "build is broken'")
- Task-specific debugging solutions - the fix is in the code, the commit message has context

## Freshness / TTL

Filesystem mtime is the TTL clock. No metadata, no confidence scores.

| Type | TTL (stale) | 2x TTL (delete) |
|------|------------|----------------|
| Knowledge | 90 days | 180 days |
| Skills | 90 days | 180 days |
| Project context | 15 days | 60 days |
| Project findings | 30 days | 80 days |

**Actions:**
- **Fresh** (within TTL): Trust the file.
- **Stale** (past TTL, within 2x): Ignore - re-discover from scratch.
- **Very stale** (past 2x TTL): Delete the file. Recreate if still valid.

After TTL actions, update index.md if any files were deleted.

## Index Format

Tables grouped by type. Columns: Name | Description (one-line summary) | Path.

 ## Skills
 | Skill | Description | Path |
 ## Knowledge
 | Topic | Description | Path |
## Projects
 | Project | Description | Path |

## Log Format

 ## [YYYY-MM-DD] <operation> | <role> | session: <context>
 - Created: path/to/file.md
 - Updated: path/to/file.md (what changed) 
 - Lint: results or "all clean"

Agents read last ~20 lines only. Grows unbounded - no rotation.

## See Also Rules

One-directional only. Added to the file being created/updated. Do NOT back-propagate to existing files. Format: `- path - reason`. The index is the authoritative navigation tool; See Also is supplemental.

## Splitting Heuristic

One topic per file. If >50 lines and subtopics independently useful, Curator may split. If >60 total entries, prefer updates over new files. Do not merge existing files.

---

# Part 2 - Shared Session-State Artifacts (`.superteam/*`)

The superteam coordinates across agents through three append-safe shared
artifacts. All are owned by purpose-built primitives under
`scripts/`; no agent writes any of them directly.

| Artifact | Shape | Writer primitive | Introduced by |
|----------|-------|-----------------|---------------|
| `state.json` | Single mutable JSON document, CAS-protected | `scripts/state-mutate.sh` | Increment 1 |
| `events.jsonl` | Append-only JSON-Lines log | `scripts/record-event.sh` | Increment 2 |
| `strict-evaluations.jsonl` | Append-only JSON-lines log, idempotent per cycle | `scripts/record-strict-evaluation.sh` | Increment 3 |

`docs/CONCURRENCY.md` covers the lock / CAS / append-safety invariants.
This section defines the on-disk record shapes.

## `state.json` - unified coordination state

### Canonical schema (v1)

```json
{
 "revision": 0,
 "schema_version": 1,
 "phase": "pm",
 "phase_step": "init",
 "session": {
 "started": "<ISO-8601Z>",
 "last_checkpoint": "<ISO-8601Z>",
 "task_form": "<form>",
 "form_dir": "<abs path>"
 },
 "loop": {
 "current_increment": 0,
 "total_increments": 0,
 "completed_increments": 0,
 "active_pairs": 0,
 "max_parallel_pairs": 2,
 "global_iteration_count": 0,
 "max_iterations": 100,
 "manager_cycle_count": 0
 },
 "agents": {
 "active_agents": [],
 "spawn_history": [],
 "architect_status": "not_spawned",
 "architect_restarts": 0,
 "explorer_status": "not_spawned"
 },
 "watchdog_stall_count": 0
}
```

### Field reference

| Path | Type | Default | Writer | When written |
|------|------|---------|--------|-------------|
| `.revision` | integer | `0` | `state-mutate.sh` only | Bumped by 1 on every successful `--set` |
| `.schema_version` | integer | `1` | `init-session.sh` (once) | Set at session init |
| `.phase` | string | `"pm"` | Orchestrator (TL surrogate) | Phase transitions |
| `.phase_step` | string | `"init"` | Orchestrator | Sub-step transitions |
| `.session.started` | ISO-8601Z string | set at init | TL | Once, at `init-session.sh` |
| `.session.last_checkpoint` | ISO-8601Z string | set at init | TL | Checkpoints |
| `.session.task_form` | string | from FORM.md | TL | Once, at init |
| `.session.form_dir` | absolute path | from FORM.md | TL | Once, at init |
| `.loop.current_increment` | integer | `0` | Manager | On increment start |
| `.loop.total_increments` | integer | `0` | TL | Once, from plan.md |
| `.loop.completed_increments` | integer | `0` | Manager | On increment approval |
| `.loop.active_pairs` | integer | `0` | Manager | On spawn/kill |
| `.loop.max_parallel_pairs` | integer | `2` | TL | Once, from FORM.md |
| `.loop.global_iteration_count` | integer | `0` | Manager | Each monitoring cycle |
| `.loop.max_iterations` | integer | `100` | TL | Once, at init |
| `.loop.manager_cycle_count` | integer | `0` | Manager | Each monitoring cycle |
| `.agents.active_agents` | array<string> | `[]` | TL | On spawn/kill |
| `.agents.spawn_history` | array<object> | `[]` | TL | On spawn |
| `.agents.architect_status` | enum string | `"not_spawned"` | TL | On architect spawn/kill |
| `.agents.architect_restarts` | integer | `0` | Orchestrator | On architect restart |
| `.agents.explorer_status` | enum string | `"not_spawned"` | TL | On explorer spawn/kill |
| `.watchdog_stall_count` | integer | `0` | Watchdog hook | On stall detection |

### Notes

- `watchdog_stall_count` is **flat at the top level** (not nested under
 `.watchdog`) so `scripts/final/gate-6-watchdog-stall-initialized.sh`
 observes it via the top-level `jq --arg f watchdog_stall_count '.[$f]'` idiom.
- No Phase-4 restart counter is stored on `state.json` - that value is
 derived from `strict-evaluations.jsonl` (see below). The field is
 deliberately absent, not zero.
- `pending_operations` is absent - confirmed dead field, no readers.
- `architect_restarts` lives once under `.agents`. `phase` lives once at
 the top level.

### CAS semantics

Mutations go through `scripts/state-mutate.sh --set FIELD=VALUE` - CAS write of a top-level field. Under `flock -x .superteam/state.json.lock`: capture `.revision`, acquire lock, re-read `.revision`; on mismatch exit `CAS_CONFLICT_EXIT` (default `9`); on match write `FIELD`, bump `.revision`, atomic tmp+rename. Retries bounded by `CAS_RETRY_BOUND` (default `5`; set to `0` to surface the first conflict). Callers do not pass `--revision`; the CAS is internal.

`get <jq-path>` - Read a field (lock-free; writers use atomic rename).

`VALUE` is parsed as JSON when it is a valid JSON literal (number,
boolean, null, array, object) and treated as a JSON string otherwise.

## `events.jsonl` - append-only event stream

### Record shape

One JSON object per line, UTF-8, LF-terminated:

```json
{"ts":"<ISO-8601Z>","actor":"<name>","type":"<enum>","payload":{...}}
```

### Field reference

| Field | Type | Required | Writer | Description |
|-------|------|----------|--------|-------------|
| `.ts` | ISO-8601Z string | yes | `record-event.sh` | Wall-clock append time, UTC |
| `.actor` | string | yes | caller (`--actor`) | Agent identity: `tl`, `manager`, `orchestrator`, `architect`, `generator`, `evaluator`, `explorer`, `curator`, `pm`, `watchdog` |
| `.type` | enum string | yes | caller (`--type`) | One of `decision`, `anomaly`, `mutation`, `escalation`, `transition` |
| `.payload` | JSON object | yes | caller (`--payload`) | Event-type-specific body; no schema enforcement beyond "is valid JSON" |

### Event types

| Type | Meaning | Typical actors |
|------|---------|----------------|
| `decision` | A deliberate choice made by an agent (e.g., "escalate to user", "retry with fresh pair") | Manager, Orchestrator, TL |
| `anomaly` | An unexpected observation that did not trigger an action by itself (e.g., long cycle, stalled pair) | Manager, Watchdog |
| `mutation` | Companion audit record for a `state.json` write (what was changed, who changed it) | All state writers |
| `escalation` | A step up the 5-strike ladder | Manager, Orchestrator |
| `transition` | A phase or phase-step change | Orchestrator, TL |

### Invariants

- Append-only; no rewriter. Readers tolerate the log growing unbounded.
- `flock -x` + `O_APPEND` under `scripts/record-event.sh` guarantees no
 torn lines across concurrent appenders.
- Record ordering is append-order (file order), not `ts`-order.

## `strict-evaluations.jsonl` - Phase-4 verdict log

### Record shape

One JSON object per line, UTF-8, LF-terminated:

```json
{
 "ts": "<ISO-8601Z>",
 "cycle": 1,
 "verdict": "FAIL",
 "hard_gates_failed": ["G-4.1", "G-4.3"],
 "soft_gates_unmet": ["S-4.2"],
 "spec_requirements_unsatisfied": ["FR-4.1"],
 "specific_gaps": ["metrics endpoint returns 500"],
 "summary": "<full body of the strict-evaluation failure report>"
}
```

### Field reference

| Field | Type | Required | Source |
|-------|------|----------|--------|
| `.ts` | ISO-8601Z string | yes | `record-strict-evaluation.sh` wallclock |
| `.cycle` | integer >= 1 | yes | `--cycle <N>` (append-order identifier; see below) |
| `.verdict` | enum `"FAIL"` \| `"PASS"` | yes | `--verdict` |
| `.hard_gates_failed` | array<string> | yes (may be empty on PASS) | YAML frontmatter of `--report-file` |
| `.soft_gates_unmet` | array<string> | yes (may be empty) | YAML frontmatter |
| `.spec_requirements_unsatisfied` | array<string> | yes (may be empty) | YAML frontmatter |
| `.specific_gaps` | array<string> | yes (may be empty) | YAML frontmatter |
| `.summary` | string | yes | body of `--report-file` (after frontmatter) |

### Invariants

- **Idempotent per cycle**: at most one record per `.cycle` value.
 Re-invoking with the same cycle exits non-zero rather than
 double-appending.
- **Append-only**: no rewriter. Readers compose with `jq`.
- **Ground truth for Phase-4 progress**: `state.json` holds **no** field
 that duplicates this count.

### Phase-4 iteration-cap semantics (two distinct `jq` queries)

Readers of `strict-evaluations.jsonl` MUST distinguish two queries on the FAIL/PASS verdict history. They are not interchangeable - confusing them either prematurely escalates to the user or permits unbounded restarts.

**Cap check - FAIL-filtered count.** The 3-strike iteration cap counts
only `FAIL` verdicts. A `PASS` record does not consume the budget.

```bash
jq '[.[] | select(.verdict=="FAIL")] | length' \
 .superteam/strict-evaluations.jsonl
```

When this count reaches 3, the Orchestrator escalates to the user
instead of restarting Phase-3 with a fix increment.

**Cycle number - total-length count.** The next cycle number is the
append-order identifier across both verdict types. Any record - FAIL or
PASS - increments the next cycle number.

```bash
jq 'length' .superteam/strict-evaluations.jsonl
```

The Orchestrator passes `--cycle $(next_cycle_number)` to
`record-strict-evaluation.sh` when appending a new record.

**Why both forms matter.**
- Using the FAIL-filter as a cycle number would collide with an
 existing record (idempotency exit) whenever a PASS record exists
 between two FAILs.
- Using the total-length form as the cap check would let a mixed PASS
 + FAIL history exceed 3 FAILs before escalation, violating the
 3-strike contract.

## Cross-artifact interactions

- A state mutation with audit value is accompanied by a `mutation`
 record in `events.jsonl` written by the same actor. The two writes are
 not transactional; the event stream is advisory audit, not truth.
- Phase-4 restart decisions read only `strict-evaluations.jsonl`. The
 Orchestrator never reads a restart counter from `state.json`.
- The watchdog heartbeat is the `state.json` mtime - bumped implicitly
 by every successful `--set`.
