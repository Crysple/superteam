---
name: "engineering"
description: "Linear increment execution with Generator/Evaluator pairs for code-centric tasks"
phases: [pm, architect, execute, integrate, deliver]
isolation: worktree
max_parallel_pairs: 2
termination: "all increments complete + final acceptance gates pass"
---

## Roles

| Role Name | Agent Definition | Lifecycle | Description |
|---------- |---------------- |---------- |------------|
| Generator | `generator.md` | Fresh per increment | Contract-driven implementation - reads frozen contract, implements increment, pre-validates, commits, requests review |
| Evaluator | `evaluator.md` | Fresh per increment | Independent 4-tier verification - runs hard gates, judges soft gates, issues APPROVED/REVISE/GATE-CHALLENGE |

## PM Guidance

When the user's request includes testing on infrastructure (remote compute pods, managed workflow engines), read `{PLUGIN_ROOT}/references/execution-testing.md` and enforce its requirements:

- **Execution FRs must use explicit execution language** ("must be EXECUTED and PASS", not "must be added"). See the GOOD vs BAD examples in the reference.
- **Hard gates for execution FRs must verify execution evidence files**, not grep test source code. The reference defines the evidencefile format and gate script pattern.
- **FR-4.4 equivalent** must explicitly state: "gates must verify EXECUTION EVIDENCE, not source code patterns."

If the user's prompt references that document or mentions "execution testing", this guidance is mandatory.

## Architect Guidance

**Decomposition strategy**:Feature-slice increments. Each increment delivers one coherent capability that can be independently verified. Order increments so that each builds on the previous ones' committed code.

**Contracts**: Each increment gets a frozen contract at 'contracts/increment-{N}.md* using the standard 4-tier verification structure:
- **Preconditions**: Scripts that must pass before the Generator starts (planning-level correctness)
- **Hard Gates**: Deterministic scripts with binarypass/fail (0 LLM tokens) - the primary verification mechanism
- **Soft Gates**: Evidence-backed criteria requiring Evaluator judgment - minimize these, prefer hard gates
- **Invariants**: Universal quality bar (tests pass, lint clean, types check) - enforced by hooks

**Execution testing increments**: When the plan includes testing increments that require infrastructure (remote compute pods, managed workflow engines), the increment type must be 'execution-testing (not "testing ). Contracts for these increments must:
- Require the Generator to EXECUTE tests/workflows and write evidence to `.superteam/execution-evidence/*`
- Hard gates check the evidence files, NOT grep test source code

**Failure analysis**: On GATE-CHALLENGE, the Architect reviews the challenged verification script. If the script is wrong, fix it and signal re-evaluation. If the script is correct, confirm and the Evaluator re-issues the verdict. Standard escalation - no task-form-specific failure analysis protocol.

## Manager Guidance

**State machine**: Linear increment execution with optional parallelism (up to `max_parallel_pairs` concurrent Generator/Evaluator pairs when the Architect marks increments as parallelizable).

**Execution loop**:
1. Detect increment completion (Evaluator writes APPROVED verdict to `verdicts/increment-{N}.md`)
2. Request next increment's Generator spawn from TL
3. If parallel increments are available and a slot is free, request additional spawns

**Health heuristics**: Use the standard 5-strike escalation ladder. Monitor:
- Consecutive failures on the same increment (strike accumulation)
- Iteration count trends (increasing iterations per increment suggests growing complexity or degraded context)
- Time-per-increment trends (increasing time suggests the same)
- Generator/Evaluator communication health (messages flowing, no stuck agents)

**Anomaly detection**: If an increment exceeds 5 revision cycles without progress, escalate to Architect for contract review. If a Generator reports inability, coordinate with Architect for exploration increment insertion.

## Spawn Sequence

The following sequence is driven by agents messaging TL with spawn requests. TL always fulfills them mechanically.

### Step 1: Spawn Generator

Manager (or Architect after GATE-CHALLENGE) sends TL:

```
SendMessage to "team-lead":
 "Spawn request: name=generator, agent_def=task-forms/engineering/generator.md,
 context: contract=contracts/increment-{N}.md, attempts=attempts/increment-{N}.md,
 lessons=lessons-learned.md, knowledge=knowledge/index.md'"
```

### Step 2: Generator implements

Generator reads contract, reads prior attempts (if retry), implements the increment, runs pre-validation (all validation commands + `scripts/run-gates.sh {N}`), fixes any failures, commits changes.

### Step 3: Spawn Evaluator

Generator (or Manager concurrently) requests:

```
SendMessage to "team-lead":
 "Spawn request: name=evaluator, agent_def=task-forms/engineering/evaluator.md,
 context: contract=contracts/increment-{N}.md"
```

Generator messages Evaluator directly when ready for review.

### Step 4: Evaluator verifies

Evaluator runs 4-tier verification against the frozen contract:
1. Preconditions (scripts)
2. Hard gates (deterministic scripts via `run-gates.sh`)
3. Soft gates (evidence-backed LLM review)
4. Invariants (hook-enforced)

Plus sub-evaluations: clean code check, correctness check.

Issues one of three verdicts: **APPROVED**, **REVISE**, or **GATE-CHALLENGE**. 

### Step 5: On APPROVED

1. Evaluator writes verdict to `verdicts/increment-{N}.md`
2. Evaluator messages Generator: "APPROVED"
3. Evaluator messages TL: "Increment {N} approved." Exits. (Informational - Manager detects state via verdict files.)
4. Generator writes lessons to `lessons-learned.md`
5. Generator messages TL: "Increment {N} complete and approved." Exits. (Informational - Manager detects state via verdict files.)
6. Manager detects completion in next cycle, requests next increment's Generator (back to Step 1)

### Step 6: On REVISE

1. Evaluator writes verdict and detailed feedback to `attempts/increment-{N}.md`
2. Evaluator messages Generator: "REVISE" with key issues
3. Generator reads feedback, fixes issues, re-runs pre-validation
4. Generator re-messages Evaluator: "Ready for re-review"
5. Back to Step 4

### Step 7: On GATE-CHALLENGE

1. Evaluator writes verdict identifying the challenged script
2. Evaluator messages Orchestrator: "GATE-CHALLENGE on increment {N}" with script path and evidence
3. Orchestrator forwards to Architect for script review
4. Architect reviews and fixes (or confirms) the script
5. Re-evaluation from Step 4

## Verification Pattern

**Inner loop (per increment)**: 4-tier contract verification as described in the Spawn Sequence. The Evaluator runs all tiers and sub-evaluations before issuing a verdict. No increment is considered complete until it receives an APPROVED verdict.

**Outer loop (project-level)**: Final acceptance gates from `spec.md` are run in Phase 4 (Integration). These verify the complete deliverable against the original requirements, not just individual increments.

## State Files

No additional state files beyond standard `.superteam/*`. Uses: `state.json` (`.loop.*`), `metrics.md`, `events.jsonl` (append-only event stream), `contracts/*`, `attempts/*`, `verdicts/*`, `gate-results/*`, `traces/*`.
