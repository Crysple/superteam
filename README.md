<div align="center">

# 🦸 Superteam

### *You have AI. Why are you still glued to the screen?*

**one `/superteam` command spawns a real engineering team that brainstorms the spec with you, locks executable acceptance gates, and grinds through your enterprise stack (Flyte, HDFS, k8s, internal mirrors, your MCP servers) — increment by increment, overnight, until every gate passes.<br/>*Not another agent in a loop <br/>No fake "looks good"<br/>No re-teaching your company every Monday***

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Built for Claude Code](https://img.shields.io/badge/Built%20for-Claude%20Code-d97757?style=for-the-badge&logo=anthropic&logoColor=white)](https://github.com/anthropics/claude-code)
[![Drop-in Plugin](https://img.shields.io/badge/Drop--in-Plugin-c4441b?style=for-the-badge)](#installation)
[![Multi-Agent Team](https://img.shields.io/badge/Architecture-Multi--Agent%20Team-254866?style=for-the-badge)](#the-agent-roster)
[![Hard Gates](https://img.shields.io/badge/Verification-Hard%20Gates-4a7c3f?style=for-the-badge)](#4-tier-contract-verification)
[![Runs in tmux](https://img.shields.io/badge/Runs%20in-tmux-1bb91f?style=for-the-badge&logo=tmux&logoColor=white)](#run-it-247-on-a-remote-vm-claude-code-team-mode--tmux)
[![Self-Healing](https://img.shields.io/badge/Loop-Self--Healing-8a2d10?style=for-the-badge)](#the-5-strike-escalation-ladder)
[![Compounding Wiki](https://img.shields.io/badge/Memory-Karpathy%20Wiki-786a59?style=for-the-badge)](#global-wiki--local-warm-start)

**[Features](#features)** · **[Quick Start](#quick-start)** · **[How It Works](#how-it-works)** · **[Run on a Remote VM](#run-it-247-on-a-remote-vm-claude-code-team-mode--tmux)** · **[Related Projects](#related-projects)** · **[Global Wiki](#global-wiki--local-warm-start)**
</div>

---

## Features

**Five things a single agent in a loop cannot do.**

### 🤝 Aligned-Before-Code PM Brainstorm

> *"Keep asking until your goal and the spec are byte-identical."*

A real PM-style intake grounded in your codebase — not a vibes-based "got it, building now." The PM surveys what you already have, asks targeted classifying questions about scope, edge cases, and integration points, and refuses to move on while ambiguity remains. **No more "the LLM made an assumption I'd never make"** at hour 14 of a run.

### 🔒 Unbribable Acceptance Gates

> *"You approve scripts, not adjectives. After that, 'done' is binary — and no agent can negotiate it."*
Acceptance criteria compile to **executable shell scripts** — `pytest`, `ssh edge-01 'hdfs dfs -test ...'`, `flytectl ... | jq -e '.phase=="SUCCEEDED"'`. **Review once, before any code.** After that, "done" is a non-zero exit code or it isn't done. **Adversarial reviewers can be sweet-talked. Failing exit codes cannot.**

### 🌙 Overnight Delegated Delivery

> *"Hand it off at 6 PM. Wake up to a green PR."*

Claude Code alone caps at **~20 min** before drift. Superteam runs **20+ hours**: every increment gets a *fresh* Generator/Evaluator pair, and the Evaluator can't read the Generator's reasoning — **adversarial by construction**. No accumulated context. No fake "looks good." Pair with [tmux on a remote VM](#run-it-247-on-a-remote-vm-claude-code-team-mode--tmux) and the team runs while you sleep.

### 🛟 Stalls Heal. Pipelines Resurrect.

> *"Real Isolated Claude Code sessions in tmux. A file-based harness keeps them in sync. Watchdogs bring them back."*

Every teammate is a **full Claude Code session in its own tmux pane** — not an in-process sub-agent, not a multi-agent prompt. Coordination lives on disk (`state.json`, `events.jsonl`, frozen contracts, hooks), so the harness self-heals:

- **1200-s watchdog** — auto-relaunches the Orchestrator when `state.json` goes stale
- **5-strike escalation** — *changes the approach* every strike (retry → nudge → fresh pair → split → user); never just retries
- **Phase-4 strict re-eval** — fresh Evaluator re-runs *all* final gates; up to 3 FAIL → fix → re-evaluate cycles before escalating to you

*Inspired by [Anthropic's harness-design writeup](https://www.anthropic.com/engineering/harness-design-long-running-apps).*

### 🧠 Learns Your Stack Once. Forever.

> *"Stop teaching it about your company every Monday."*

Inspired by [Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). At the end of every successful session, the Curator filters what the team learned through a four-step value gate (*novel? expensive? recurring? durable?*) and writes survivors to a **global wiki at `~/.superteam/`**. Next session, the Explorer warm-starts from it before touching the codebase. First session: cold. By session 5: your internal CLIs, package mirror quirks, edge-node gymnastics, and team conventions are already loaded before a line of code is read.

---

## Quick Start

### 1. Install

Inside Claude Code, add this repo as a plugin marketplace and install the plugin:

```
/plugin marketplace add Crysple/superteam
/plugin install superteam@superteam
/reload-plugins
```

Requires **Claude Code v2.1.32+** with agent teams enabled. Launch inside tmux so each teammate gets its own pane:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
tmux new -s superteam
claude --teammate-mode tmux
```

<details>
<summary>Install tmux (optional)</summary>
```bash
brew install tmux              # macOS
sudo apt-get install -y tmux   # Debian/Ubuntu
```
</details>

### 2. Hand it your goal

The kind of work that goes beyond your laptop, where a normal coding agent quits at *`command not found`*, *`No matching distribution found`*, or *`No CUDA GPUs available`* and waits for you to become the runtime — *that's* the work Superteam exists for.
```
/superteam Train a CTR ranker on the last 7 days of impression logs, submit to
the H100 pool via `pyflyte run --remote`, target AUC ≥ 0.78, publish the
artifact to the model registry tagged v3.
```
We'll walk *this* prompt end-to-end below — PM brainstorm, hard gates, approval. Check [**More prompts to try**](#more-prompts-to-try).

### 3. The PM brainstorms with you
The PM surveys your codebase, company wiki and asks targeted clarifying questions — scope, edge cases, acceptance criteria — until it's confident it understands the full request.
```
PM: The impression-logs Hive partition lands at 02:00 UTC. "Last 7 days" —
    should the cutoff be 7 calendar days from now, or 7 *complete* daily
    partitions (i.e., yesterday minus 6)? The latter avoids a partial last
    day if you re-run mid-morning.
PM: AUC ≥ 0.78 — same eval split your current production model is graded on,
    or a fresh holdout? If holdout, I need to coordinate with the data team
    to lock the split before training starts.
PM: Your model registry uses semver. Tagging v3 implies a major bump — does
    the serving config need to change, or is this architecture-compatible
    with the current v2.x server? If incompatible, we need a backward-compat
    eval gate before the registry publish.
```
Answer as briefly or fully as you like. The PM will keep asking until it can write an unambiguous spec.

### 4. Review the hard gates
Once confident, the PM generates **concrete, executable acceptance gate scripts** — the binary criteria that define "done." You see them before a single line is written:
```
Final Acceptance Gates
─────────────────────────────────────────────────────────────────────────────
  gate-01-data.sh       last 7 complete impression-logs partitions exist
                        → hdfs dfs -test -d /data/impressions/dt={d-7..d-1}/_SUCCESS
  gate-02-submit.sh     pyflyte run --remote returns ${EXEC_ID}
                        → flytectl get execution ${EXEC_ID} --details
  gate-03-train.sh      Flyte execution reaches SUCCEEDED
                        → flytectl get execution ${EXEC_ID} -o json \
                            | jq -e '.phase=="SUCCEEDED"'
  gate-04-auc.sh        eval AUC ≥ 0.78 on the locked v2 holdout split
                        → python eval.py --split locked-holdout-2026-Q1 \
                            | jq -e '.auc>=0.78'
  gate-05-registry.sh   ctr-ranker:v3 published with signed manifest, ready=true
                        → registry-cli get ctr-ranker:v3 \
                            | jq -e '.signed and .ready'
─────────────────────────────────────────────────────────────────────────────
Do you approve this spec and these gates? (yes / no / revise)
```
These are the gates the team will be graded against — by an *adversarial* Strict Evaluator that has never seen the implementation. If anything looks wrong (wrong AUC threshold, wrong holdout split, missing gate for the serving-config check), say so — the PM revises before anything is built.

### 5. Approve and step away
```
> yes
```
Done. The Architect decomposes the spec into contracts, Generator/Evaluator pairs implement and verify each increment, and the Strict Evaluator runs all gates against the final deliverable. You'll be notified on completion or if a genuine blocker requires your input.

### More prompts to try
The hero example above is just one shape. Here are four more enterprise scenarios where a normal agent stalls but Superteam shines — plus a laptop-only warm-up if you want to try without a cluster:
```bash
# Spark + Airflow data pipeline that actually lands in prod  (HDFS firewalled, kerberos on edge node)
/superteam Add a daily PySpark job: join /data/prod/events with the feature_flags table, land partitioned output to /out/daily/features/, schedule in Airflow with retries, alert #data-oncall on SLA breach.
# New gRPC endpoint against the internal stack  (private package mirror, multi-language stubs)
/superteam Add POST /v2/payments to payment-service with idempotency keys, pull acme-auth==2.4.* from the company mirror, regenerate Python + Java proto stubs, update the OpenAPI doc.
# Kafka consumer that has to survive production  (DLQ, broker restart, internal auth)
/superteam Kafka consumer on user-events at 10k/s: write to the internal Postgres (ldap-auth), emit DataDog metrics, route poison messages to user-events-dlq, survive a broker restart with zero loss.
# Canary rollout with SLO gates and auto-rollback  (real prod operation, no babysitting)
/superteam Migrate user-search from EC2 to our k8s platform. Keep P99 ≤ 80ms, roll out behind the canary flag, watch the Datadog dashboard for 1h, auto-rollback if error rate > 0.5%.
# Warm-up — runs entirely on your laptop  (no cluster needed, good first try)
/superteam Build a rate-limited job queue with Redis and dead-letter support.
```
Each enterprise prompt forces gates that can't be faked on a laptop — `hdfs dfs -test`, `pip install --index-url`, `kafka-consumer-groups --describe`, `kubectl rollout status && datadog-cli monitor get`. **That's where "done" stops being a vibe.**

---

## Run It 24/7 on a Remote VM (Claude Code Team Mode + tmux)
Superteam is built on **Claude Code's team mode**, where every teammate (PM, Architect, Manager, Generator, Evaluator, …) runs as a *full Claude Code session in its own tmux pane* — not as an in-process subagent. They coordinate through `SendMessage`, append-only event logs, and a CAS-protected `state.json`. That gives you a property normal coding agents don't have:
> **The team lives inside tmux. Detach from tmux and the team keeps running. Reattach from anywhere — laptop closed, internet dropped, or the next morning — and you're staring at exactly the state you left.**
Combine that with the watchdog (auto-restarts the Orchestrator on stalls), the per-increment fresh agents (no context drift), and the file-based state (`.superteam/state.json` + `events.jsonl`), and you get a team that genuinely runs *while you sleep*. Here's the whole pattern on a single remote box:

```bash
# --- one-time, on your dev VM (any cheap GPU-less Linux box works) ---
ssh you@vm.dev
# install Claude Code per Anthropic's docs, ensure team mode is enabled
sudo apt-get install -y tmux jq
# --- starting an overnight run ---
ssh you@vm.dev
cd ~/projects/my-repo
tmux new -s superteam             # one named tmux session per project
claude                             # launches Claude Code (it spawns teammates as panes)
> /plugin marketplace add Crysple/superteam   # one-time, per machine
> /plugin install superteam@superteam
> /reload-plugins
> /superteam Build a rate-limited job queue with Redis and DLQ support
# …PM brainstorms with you, you approve the gates…
# Press Ctrl-b d  to DETACH. Close your laptop. Go home.
# --- the next morning, anywhere ---
ssh you@vm.dev
tmux attach -t superteam         # full team state restored, work has been progressing
# Watch the Orchestrator's pane, or:
jq '.phase, .phase_step, .agents.active_agents' .superteam/state.json
tail -f .superteam/events.jsonl  # decisions, anomalies, gate verdicts as they happen
```

**Why this works so well together:**
| Component | What it gives you for 24/7 runs |
|-----------|---------------------------------|
| **Claude Code team mode** | Each teammate is an independent Claude Code session in its own tmux pane — failures are isolated, restarts are surgical, context never bleeds between roles. |
| **tmux on a remote VM** | The session outlives your laptop, your Wi-Fi, and your sleep cycle. SSH back anytime; the team is exactly where you left it. |
| **`.superteam/state.json`** | Even if a pane dies, the watchdog respawns it from disk state. *History is the files.* |
| **Watchdog (1200 s)** | Detects pipeline stalls and auto-relaunches the Orchestrator with full context. You don't have to babysit the babysitter. |
| **Per-increment fresh pairs** | Long runs don't degrade — each Generator/Evaluator starts with zero accumulated context. |
**Recovery checklist** (if you ever ssh in and something looks wrong):
1. `tmux attach -t superteam` — see all panes at a glance.
2. `jq '.' .superteam/state.json | head -40` — current phase, active agents, watchdog stall count.
3. `tail -50 .superteam/events.jsonl` — last decisions, anomalies, escalations.
4. If the Orchestrator pane is gone: the watchdog will respawn it within 20 minutes. Or restart it manually — the new instance will re-read `state.json` and resume from the recorded `phase_step`.

---

## Wire It to Your Company's Knowledge (Optional MCP Setup)
The team is **only as smart as what it can search**. The Explorer knows your codebase out of the box. Add your company's MCP servers — Glean, Sourcegraph, Confluence, Linear, Slack, org-chart — and it knows *your company*: internal CLIs, package mirrors, recent decisions, who to ask.
Register them in Claude Code (`/mcp`) and list them in [`global-guide.md`](#global-guide). The **Explorer** consults them on unknown internal terms; the **Curator** promotes the answers to `~/.superteam/` at session end. **Next session, the lookup is already in your wiki.**
> Today's MCP query → tomorrow's wiki entry → next week's instinct.

---

## Related Projects
The plugin itself is intentionally lean (no APIs, no cloud, no extra processes — pure Claude Code). These projects pair well with it:
### [free-claude-code](https://github.com/Alishahryar1/free-claude-code) — *route Claude Code to free / cheap / local model providers*
A drop-in proxy for Claude Code's Anthropic Messages API that re-routes traffic to NVIDIA NIM, OpenRouter, DeepSeek, LM Studio, llama.cpp, or Ollama. Lets you run Superteam's overnight loops on free hosted models or fully local hardware, with per-tier routing (Opus/Sonnet/Haiku → different providers) and an optional Discord/Telegram bot wrapper for poking at the run from your phone.
```bash
# pair it with Superteam: point Claude Code at the proxy, then run /superteam as usual
ANTHROPIC_AUTH_TOKEN="freecc" ANTHROPIC_BASE_URL="http://localhost:8082" claude
> /superteam …
```
> Useful when you want to leave a 20-hour overnight build running and don't want a 20-hour Anthropic bill.

*(More companion projects coming — PRs welcome.)*

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
Inside Claude Code (preferred — works from any machine, including remote VMs):
```
/plugin marketplace add Crysple/superteam
/plugin install superteam@superteam
/reload-plugins
```
For local development on the plugin itself, clone the repo anywhere you like and add it as a *local* marketplace:
```bash
git clone https://github.com/Crysple/superteam ~/code/superteam
```
Then in Claude Code:
```
/plugin marketplace add ~/code/superteam
/plugin install superteam@superteam
/reload-plugins
```
Either way, Claude Code copies the plugin into its versioned cache at `~/.claude/plugins/cache`. Don't `cp` or `git clone` into that path directly — it's managed by the plugin system. See the [official install docs](https://code.claude.com/docs/en/discover-plugins) for scopes, updates, and `/plugin` UI usage.

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
