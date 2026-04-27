# Superteam

> *You have AI. Why are you still glued to the screen?*

A Claude Code plugin that turns a single `/superteam` command into an autonomous multi-agent engineering team. Describe what to build. The PM clarifies, generates hard gates, gets your approval — then the team builds, verifies, and delivers while you do something else.

[Quick Start](#quick-start) · [How It Works](#how-it-works) · [Global Wiki](#global-wiki--local-warm-start) · [Global Guide](#global-guide) · [Design](#design-philosophy) · [Project Structure](#project-structure)

---

## Features

| Feature | Description |
|---------|-------------|
| **PM-driven spec** | PM asks classifying questions until confident, then generates executable hard gates for your review |
| **One approval gate** | Review the spec + gates once. After approval, the team runs to completion autonomously |
| **Adversarial evaluation** | Each increment gets a fresh Generator/Evaluator pair — evaluation is always separate from generation |
| **Hard gates first** | Deterministic scripts (0 LLM tokens) are the primary verification layer, not vibes |
| **Self-healing** | 5-strike escalation ladder, per-unit fresh agents, watchdog restarts — stalls resolve without you |
| **Compounding knowledge** | Curator extracts reusable findings to a global wiki (`~/.superteam/`) shared across all your projects |

---

## Quick Start

### 1. Install

```bash
git clone https://github.com/your-username/superteam ~/.claude/plugins/superteam
```

Requires **Claude Code** with multi-agent (team) support enabled.

### 2. Open your project and run

```
/superteam Build a rate-limited job queue with Redis and dead-letter support
```

### 3. The PM brainstorms with you

The PM surveys your codebase and asks targeted clarifying questions — scope, edge cases, acceptance criteria — until it's confident it understands the full request. Expect 2–4 rounds:

```
PM: The existing worker pool uses a pull model. Should the new queue follow the
    same pattern, or do you prefer a push-based approach?

PM: What's the expected throughput — low (<100/s), medium, or high (>10k/s)?
    This affects whether we need partitioning.

PM: Should dead-lettered jobs be automatically retried on a backoff schedule,
    or manually re-queued by an operator?
```

Answer as briefly or fully as you like. The PM will keep asking until it can write an unambiguous spec.

### 4. Review the hard gates

Once confident, the PM generates **concrete, executable acceptance gate scripts** — the binary criteria that define "done." You see them before a single line is written:

```
Final Acceptance Gates
────────────────────────────────────────────────────────
  gate-01-enqueue.sh      job appears in queue within 100ms
  gate-02-dequeue.sh      job delivered exactly once under concurrent consumers
  gate-03-rate-limit.sh   queue respects configured rate limit (burst + sustained)
  gate-04-dlq.sh          failed jobs move to dead-letter after max retries
  gate-05-persistence.sh  queue survives process restart with no message loss
────────────────────────────────────────────────────────
Do you approve this spec and these gates? (yes / no / revise)
```

If anything looks wrong, say so — the PM revises before anything is built.

### 5. Approve and step away

```
> yes
```

Done. The Architect decomposes the spec into contracts, Generator/Evaluator pairs implement and verify each increment, and the Strict Evaluator runs all gates against the final deliverable. You'll be notified on completion or if a genuine blocker requires your input.

---

## How It Works

### The Pipeline

Five phases run automatically after you approve the spec:

```
┌─────────────────────────┐
│  Phase 1 · PM           │  ← you interact here
│  Brainstorm + gates     │
└────────────┬────────────┘
             │ you approve
┌────────────▼────────────┐
│  Phase 2 · Architect    │  fully automated from here
│  Plan + contracts       │
└────────────┬────────────┘
             │
┌────────────▼────────────┐
│  Phase 3 · Execute      │
│  Generator ↔ Evaluator  │
│  (fresh pair per unit)  │
└────────────┬────────────┘
             │
┌────────────▼────────────┐
│  Phase 4 · Strict Eval  │  FAIL → targeted fix increments → Phase 3
│  All acceptance gates   │  max 3 restarts, then escalate
└────────────┬────────────┘
             │ PASS
┌────────────▼────────────┐
│  Phase 5 · Delivery     │
│  Curator + results      │
└─────────────────────────┘
```

**Phase 1 (PM)** — PM surveys the codebase via the Explorer, asks classifying questions, and produces a spec with measurable acceptance gates. You review and approve before anything is built.

**Phase 2 (Architect)** — Decomposes the spec into increments, each with a frozen contract (preconditions, hard gates, soft gates, invariants). A Generator writes and tests the gate scripts.

**Phase 3 (Execute)** — The Manager drives a parallel execution loop. Each increment gets a fresh Generator/Evaluator pair. They iterate directly against the frozen contract until APPROVED. The Manager monitors for anomalies.

**Phase 4 (Strict Evaluation)** — A fresh Strict Evaluator runs *all* final acceptance gates against the complete deliverable. Binary PASS or FAIL. On FAIL, the Architect writes targeted fix increments and Phase 3 reruns (max 3 cycles).

**Phase 5 (Delivery)** — The Curator extracts reusable knowledge to your global wiki (`~/.superteam/`). Results are presented.

---

### The Generator ↔ Evaluator Loop

The core quality primitive. Two fresh agents, one frozen contract, adversarial feedback:

```
┌──────────────────────────────────────┐
│  Frozen Contract (read-only)         │
│  preconditions · hard gates          │
│  soft gates · invariants             │
└────────┬──────────────────┬──────────┘
         │                  │
┌────────▼───────┐   ┌──────▼──────────┐
│   Generator    │──▶│   Evaluator     │
│   implement    │   │   run gates     │
│   commit       │◀──│   judge         │
└────────────────┘   └──────┬──────────┘
     REVISE + feedback       │ APPROVED
                             ▼
                    increment done ✓
```

The Evaluator reads **only** the contract and the Generator's outputs — never the Generator's reasoning. This prevents evaluator anchoring.

---

### 4-Tier Contract Verification

Every increment is verified against a frozen contract written *before* implementation begins:

| Tier | What | Cost |
|------|------|------|
| **Preconditions** | Scripts that must pass before work starts | 0 LLM tokens |
| **Hard Gates** | Deterministic scripts — binary pass/fail | 0 LLM tokens |
| **Soft Gates** | Evidence-backed LLM review (minimize these) | Low |
| **Invariants** | Universal quality bar — hook-enforced, always run | 0 LLM tokens |

Hard gates are the primary mechanism. Soft gates supplement only where human judgment is genuinely required.

---

### The Agent Roster

| Agent | Lifecycle | Role |
|-------|-----------|------|
| **Team Lead (TL)** | Persistent | Sole user-facing interface. Spawns agents. Owns the approval gate. Runs the watchdog. |
| **Orchestrator** | Persistent | Drives phase transitions. Owns `state.json`. Routes GATE-CHALLENGE, inability, and restart cycles. |
| **PM** | Phase 1 | Brainstorms spec with user. Generates acceptance gates. |
| **Explorer** | Persistent | Surveys the codebase. Seeds the knowledge base. Dispatches research subagents. |
| **Architect** | Persistent | Decomposes spec into contracts. Fixes gate scripts on GATE-CHALLENGE. |
| **Manager** | Phase 3–5 | Stateless monitoring loop (270s). Detects anomalies. Drives the execution loop. |
| **Curator** | Phase 5 | Session-end knowledge extraction to global wiki. |
| **Generator** | Fresh per increment | Reads frozen contract → implements → pre-validates → commits → requests review. |
| **Evaluator** | Fresh per increment | Reads contract + outputs only → runs 4-tier verification → issues verdict. |

---

### The 5-Strike Escalation Ladder

When an increment stalls, the Manager escalates — each strike changes the approach:

```
Stall detected
    │
    ▼ Strike 1 — retry with feedback (Gen/Eval loop)
    ▼ Strike 2 — Manager nudge: "try a different approach"
    ▼ Strike 3 — context reset: kill pair, spawn fresh
    ▼ Strike 4 — scope change: Architect splits the increment
    ▼ Strike 5 — user input (only for auth/access blockers)
```

---

### State Architecture

Three append-safe artifacts coordinate the team. The Manager re-reads them every cycle from scratch — no accumulated context. **History is the files.**

```
.superteam/
├── state.json                  CAS-protected coordination state
│                               phase, active agents, loop counters
│                               mutations via scripts/state-mutate.sh only
│
├── events.jsonl                Append-only event stream
│                               decisions · anomalies · mutations · escalations
│
└── strict-evaluations.jsonl    Phase 4 verdict log
                                idempotent per cycle · FAIL count drives restart cap
```

---

## Global Wiki & Local Warm Start

> *Inspired by Andrej Karpathy's [LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — where an LLM maintains a living, compounding knowledge base instead of re-deriving the same facts on every session.*

### Two tiers of knowledge

```
~/.superteam/           ← global wiki (shared across all your projects)
  index.md              ← entry point: entity pages, concept pages, cross-references
  knowledge/            ← individual wiki pages by topic

.superteam/             ← local wiki (this project only)
  knowledge/
    index.md            ← local entry point
    …                   ← project-specific findings
```

**Local wiki** (`.superteam/knowledge/`) — project-specific discoveries: architecture quirks, undocumented APIs, integration gotchas, test fixture patterns, team conventions. Seeded by the Explorer at session start; enriched by every agent throughout the session.

**Global wiki** (`~/.superteam/`) — evergreen knowledge that applies across projects: company-wide patterns, framework insights, toolchain quirks, reusable gate scripts, team conventions. The Curator promotes valuable local findings to the global wiki at the end of every session.

### Warm start

At the beginning of every session, before surveying the codebase, the Explorer checks `~/.superteam/index.md` for cached global knowledge. If relevant pages exist, the Explorer loads them first — the codebase survey only fills gaps. Over time this means agents start with meaningful context on every new session, not a blank slate.

The first session in a new project is a cold start. Every session after that is warmer. After a few sessions on related projects, the Explorer arrives already knowing your patterns, toolchains, and conventions.

### What compounds

| What gets promoted to global wiki | Example |
|-----------------------------------|---------|
| Cross-project conventions | "All services use `x-request-id` for distributed tracing" |
| Toolchain quirks | "The internal build CLI `xyz build` requires `--no-cache` in CI" |
| Reusable gate scripts | A working Redis availability check |
| Framework-specific patterns | "React components here always co-locate their tests" |
| Hard-won debugging knowledge | "Port 5432 must be pre-allocated before Docker Compose starts" |

---

## Global Guide

The `global-guide.md` file is pre-loaded into **every agent prompt** on every session. It's the right place for knowledge that should always be present — tools, conventions, company context.

### Customizing for your team

Open `global-guide.md` and update these sections:

**Tools** — Add your company-specific MCP servers or search tools here. This is the most important section to customize: agents will use whatever you register, but they can only use what you tell them about. Examples of what to add:

```markdown
## Tools

Use the **internal-search** MCP when you encounter unfamiliar internal terms,
acronyms, or need context not in the codebase. Sub-tools available:

- `internal-search.semantic`  — company-wide doc/code/people search
- `internal-search.design`    — RFCs, architecture docs, meeting notes
- `internal-search.chat`      — Slack discussions and decisions
- `internal-search.tickets`   — Jira/Linear epics and sprint context
- `internal-search.code`      — cross-repo code search (e.g. Sourcegraph)
```

> If your company uses a specific code search tool (Sourcegraph, Grep.app, an internal MCP), register it here. Agents will use it when they encounter unknown symbols, APIs, or acronyms — dramatically reducing hallucination on internal codebases.

**Company Knowledge** — Replace the placeholder section with the internal systems, CLIs, platforms, and terminology your agents will encounter in this codebase. The Explorer promotes reusable findings from the local wiki to the global wiki automatically, but seed it with what you already know.

**General Rules** — The three default rules (think before coding, simplicity first, surgical changes) apply universally. Add project-specific invariants here — e.g., "never modify the public API surface without a migration path."

---

## Installation

```bash
# Clone into your Claude Code plugins directory
git clone https://github.com/your-username/superteam ~/.claude/plugins/superteam

# Or copy just the plugin
cp -r superteam/superteam ~/.claude/plugins/superteam
```

---

## Design Philosophy

Ten principles from [`docs/Design.md`](docs/Design.md):

1. **Separate generation from evaluation** — self-evaluation is inherently lenient
2. **Context is the scarcest resource** — progressive disclosure, not context dumping
3. **Design the environment, not just the prompts** — add tools and structure, not more words
4. **Incremental, independently verifiable work units** — contracts define "done" before work starts
5. **Per-unit freshness** — spawn fresh pairs; replace, don't compact
6. **File-based artifacts as source of truth** — state survives context resets
7. **Active verification over passive review** — run tests, don't just read code
8. **Codify expert knowledge as system rules** — encode the senior review into the gates
9. **Self-evolving systems** — the Curator promotes session findings to the global wiki
10. **Explore before you plan, plan before you build** — evidence-backed specs and plans

---

## Project Structure

```
superteam/
├── skills/superteam/
│   ├── SKILL.md              entry point (/superteam trigger)
│   └── phases/               phase-specific orchestration guides
├── agents/
│   ├── orchestrator.md       pipeline driver
│   ├── architect.md          contract author
│   ├── manager.md            stateless execution monitor
│   ├── explorer.md           codebase researcher
│   ├── pm.md                 product manager
│   ├── curator.md            knowledge extractor
│   └── plan-evaluator.md     plan review
├── task-forms/
│   └── engineering/
│       ├── FORM.md           form definition
│       ├── generator.md      inner-loop implementer
│       └── evaluator.md      inner-loop verifier
├── scripts/                  primitives (state-mutate, record-event, run-gates, …)
├── hooks/                    hook definitions (verdict-gate, completion-nudge, …)
├── docs/
│   ├── Design.md             philosophy and principles
│   └── SCHEMA.md             state artifact schemas
├── global-guide.md           shared rules injected into every teammate prompt
└── tests/                    shell-based harness tests
```

---

## License

MIT — see [LICENSE](LICENSE).
