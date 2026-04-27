# Phase 3: Execute Loop (AUTOMATED -- Manager-Driven)

The Orchestrator drives this phase and coordinates the execution. The Manager drives the execution loop. The Manager and Architect send spawn requests directly to TL via "SendMessage'. TL executes spawns mechanically. The Architect stays alive for scope changes.

## 3a. Request Manager Spawn (Spawn Point #8)

The Orchestrator requests TL to spawn the **Manager**:

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=manager, agent_def={PLUGIN_ROOT}/agents/manager.md,
 context: Execution is beginning. Task form: {form name}. Read the Manager
 Guidance section of {FORM_DIR}/FORM.md for the state machine and monitoring
 heuristics. Monitoring files: .superteam/metrics.md, .superteam/state.json,
 .superteam/events.jsonl (append-only; query with 'jq'), .superteam/plan.md.
 Form directory: {FORM_DIR}.
 Start your ScheduleWakeup loop (270s). Send spawn requests to TL per
 the form's spawn sequence. You ALWAYS schedule the next wakeup. Only TL can
 cancel your loop."
```

The Orchestrator updates state: add manager to 'active_agents*.

## 3b. Handle Spawn Requests (Forwarding Protocol)

The Manager or Architect sends spawn requests to TL:

***
"Spawn request: name={role_name}, agent_def={path_to_agent_md},
 context: {what to include in prompt -- contracts, results, knowledge}"
***

TL receives the request in this format:

```
"Spawn request: name={role_name}, agent_def={path_to_agent_md},
 context: {context from the original request}"
```

TL fulfills spawn requests per its generic spawn protocol:
1. Read the agent definition from the specified path.
2. Construct prompt: global-guide + agent definition content + specified context.
3. Check constraints: max concurrent agents (from FORM.md), agent name uniqueness.
4. Spawn via the team. Pass worktree isolation if the form specifies it.
5. Update `state.json` via `scripts/state-mutate.sh`: read `.agents`, append to `.agents.active_agents` and `.agents.spawn_history` using `jq`, then write back via `--set agents=<json>` (CAS-protected).
6. Confirm to the Orchestrator via `SendMessage`.

The Orchestrator updates its own state tracking upon TL's confirmation.

**The Orchestrator does NOT write to `state.json`'s `.loop.*` fields.** The Manager owns `.loop.*` in `state.json` and detects state changes in its monitoring cycle. The Orchestrator only manages its own state tracking and forwards requests.

## 3c. Handle Agent Completion

When the Orchestrator receives a completion message from an inner-loop agent (e.g., "increment N complete", "version N approved, ready for testing", "Execution complete", verdict message, or Similar):

**This section applies to inner-loop agents ONLY** -- agents with "Fresh per increment/version cycle" lifecycle (Generator, Evaluator, Tester, Test-Evaluator). Do NOT shut down persistent agents (Manager, Architect, Explorer) here --- they are long-running by design and are shut down only at phase transitions or explicit reset (3f).

A **completion message** indicates the sender's own work is finished. Examples from the **engineering** form: "Increment N complete" (Generator done), "Increment N approved" (Evaluator done), "Execution complete" (Tester done), verdict message (Test-Evaluator done). Examples from the **skill-dev** form (each names 'active_agents' explicitly so the cleanup effect is unambiguous): "version N generator complete - remove from active_agents" (skill-dev Generator done), "version N tester complete - remove from active_agents" (skill-dev Tester done), "version N test-evaluator complete - remove from active_agents" (skill-dev Test-Evaluator done, sent after the verdict to TL / GATE-CHALLENGE to Orchestrator). Non-completion messages: "Ready for re-review" (Generator has more work to do), spawn requests (Manager is ongoing).

1. Re-read state file.
2. Verify the reporting agent is an inner-loop role (not Manager, Architect, or Explorer).
3. Send a shutdown request to TL: `SendMessage` to `"team-lead"` - "Shutdown request: name={agent}. Reason: {work unit} complete."
4. Update state: remove that agent from `active_agents`.
5. The Manager or Architect will send the next spawn request based on the form's spawn sequence. Forward it to TL per 3b.

**Per-agent, not group**: Shut down only the agent that reported completion, not all agents in the work unit. This prevents killing an agent mid-work when its partner finishes first.

**Context reset -- kill and respawn:**

When the Manager or Architect requests a context reset (e.g., "Kill current agent on {work unit}. Spawn fresh agent."):

1. Send shutdown request to TL for the specified agent(s).
2. Update state: remove from `active_agents`.

## 3d. Handle Inability and Infrastructure Failure

When an agent reports inability OR infrastructure failure to the Orchestrator:
1. Forward to the Architect via `SendMessage`: "{agent} unable to do {X} / infrastructure failure on {X}."
2. Forward to the Explorer via `SendMessage`: "Research alternative approaches to {X}. Check knowledge base for related findings. Specifically look for: alternative tools, different environments, workaround patterns."
3. The Architect creates targeted fix or exploration increments.
4. Return to Phase 3 for those fix increments only.
5. When exploration increments are ready, the Manager or Architect will send spawn requests to TL.

Infrastructure failures are NOT stop signals. They are research triggers.

## 3e. Handle GATE-CHALLENGE

When an agent messages the Orchestrator with GATE-CHALLENGE:
1. Forward to the Architect via `SendMessage`: "GATE-CHALLENGE on {work unit}. Script: {path}. Issue: {description}."
2. The Architect reviews and fixes (or confirms) the script.
3. The agent re-evaluates after the script is reviewed.

## 3f. Handle Architect Checkpoint/Restart (Spawn Point #13)

When the Manager requests Architect checkpoint/restart via the Orchestrator:
1. **Checkpoint**: Save Architect's current state (plan.md is on disk, and all prior decisions are captured in the append-only .superteam/events.jsonl stream -- together they serve as the checkpoint).
2. **Restart**: The Orchestrator sends a shutdown request to TL for the current Architect, then forwards a spawn request to TL for a fresh Architect:

 `SendMessage` to `"team-lead"`:
```
"Spawn request: name=architect, agent_def={PLUGIN_ROOT}/agents/architect.md,
 context: You are a RESTARTED Architect. The previous Architect was checkpointed.
 Read .superteam/plan.md (the current plan, possibly mutated).
 Read prior decisions via: 'jq -r 'select(.type=="decision")' .superteam/events.jsonl'.
 Task form: {form name}. Read the Architect Guidance section of {FORM_DIR}/FORM.md.
 Manager's guidance: {specific instructions from Manager}.
 Adapt the plan based on this guidance. You stay alive through execution."
```

The Orchestrator updates state: increment `.agents.architect_restarts` in `state.json` via read-modify-write (read `.agents`, bump `architect_restarts` with `jq`, write back with `scripts/state-mutate.sh --set agents=<json>`). Spawn history is updated by TL on respawn. 

## 3g. Wait for Phase 3 Completion

Phase 3 completes when the Manager reports all work units are done. The Manager will message the Orchestrator with completionper the form's termination condition (e.g., "All increments complete" for engineering, "All test specs passed" for skill-dev).

Before transitioning, the Orchestrator runs the phase transition verification:
```bash
bash {PLUGIN_ROOT}/scripts/verify-phase-transition.sh execute integrate
```

Read `.superteam/phase-transition-results.json`:
- If `passed` is false: **DO NOT proceed.** The Orchestrator messages the Manager with the failed checks. Specific increments may need re-evaluation or missing gate-results.
- If `passed` is true: Proceed with transition.

The Orchestrator updates state: phase -> integrate.

# Phase 4: Strict Evaluation (MANDATORY)

Phase 4 is **mandatory** - it runs unconditionally after Phase 3 regardless of form configuration. This is the definitive final evaluation of the entire implementation against `spec.md`. Agents CANNOT skip this phase.

## 4a. Spawn Strict Evaluator (Spawn Point #14)

The Orchestrator requests TL to spawn a single **Strict Evaluator** for final verification. This is an outer-loop role using the shared agent definition - not a form-specific pair.

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=strict-evaluator, agent_def={PLUGIN_ROOT}/agents/strict-evaluator.md,
 context: Phase 4 final evaluation. Read .superteam/spec.md for all requirements
 and final acceptance gates. Run all final hard gate scripts via run-gates.sh final.
 Verify all soft gates with evidence. Deliver binary PASS or FAIL verdict."
```

The Orchestrator updates state: add strict-evaluator to `active_agents`.

## 4b. Handle Strict Evaluator Verdict

The Strict Evaluator delivers a binary verdict - PASS or FAIL. There is no in-phase looping or rework.

### On PASS:

The Strict Evaluator messages the Orchestrator with PASS.

1. Compute the next cycle index from the append-only log:
 ```bash
 N=$(jq 'length' .superteam/strict-evaluations.jsonl)
 ```
2. Append a PASS record to the log:
 ```bash
 bash scripts/record-strict-evaluation.sh \
 --cycle $((N+1)) \
 --verdict PASS \
 --report-file .superteam/verdicts/strict-evaluation.md
 ```
3. Run the phase transition verification:
 ```bash
 bash {PLUGIN_ROOT}/scripts/verify-phase-transition.sh integrate deliver
 ```
4. Read `.superteam/phase-transition-results.json`. If `passed` is true, proceed. If false, follow section 4c.
5. Send shutdown request to TL for the Strict Evaluator.
6. Update `state.json`: `scripts/state-mutate.sh --set phase=deliver`.
7. Update `metrics.md`.
8. Proceed to Phase 5.

### On FAIL:

The Strict Evaluator writes a detailed failure report to `.superteam/verdicts/strict-evaluation.md` and messages the Orchestrator with FAIL.

The Orchestrator receives the failure report and executes the restart protocol:

1. Read the failure report from `.superteam/verdicts/strict-evaluation.md`.
2. Send shutdown request to TL for the Strict Evaluator.
3. Compute the prior FAIL count from the append-only log:
 ```bash
 N=$(jq '[.[] | select(.verdict=="FAIL")] | length' .superteam/strict-evaluations.jsonl)
 ```
 If `N >= 3`, escalate (do NOT restart) - see Iteration Cap below.
4. Append a FAIL record to the log - this both persists the verdict and advances the restart count derivable from `jq`:
 ```bash
 bash scripts/record-strict-evaluation.sh \
 --cycle $((N+1)) \
 --verdict FAIL \
 --report-file .superteam/verdicts/strict-evaluation.md
 ```
5. Forward the failure report to the Architect: "Strict Evaluator issued FAIL (cycle $((N+1)) of 3). Current failure report at `.superteam/verdicts/strict-evaluation.md`.
 Prior failure records live in `.superteam/strict-evaluations.jsonl` - read them with
 `jq -r '.[] | select(.verdict=="FAIL") | .summary' .superteam/strict-evaluations.jsonl`
 for progressive context. Do not repeat previously identified issues.
 Also read `.superteam/lessons-learned.md` and query prior decisions via
 `jq -r 'select(.type=="decision")' .superteam/events.jsonl` for accumulated context.
 Create targeted fix increments for the gaps identified. Do not re-attempt approaches from prior cycles."
6. The Architect creates targeted fix increments addressing the specific gaps.
7. Return to Phase 3 to execute those fix increments only.
8. After fixes complete, Phase 4 runs again (spawn a fresh Strict Evaluator).

This cycle repeats until either PASS is achieved or the iteration cap is reached.

**There is NO conditional pass, partial pass, or pass-with-exceptions.** The evaluation either passes ALL hard gates and spec requirements, or it triggers a return to Phase 3 for targeted fixes.

No `cp`. No counter field. No per-cycle `.md` files - the append-only `strict-evaluations.jsonl` log is the sole record.

## 4c. Recovery Path: PASS Verdict but Transition Failure

If the Strict Evaluator issues PASS but `verify-phase-transition.sh integrate deliver` fails (e.g., malformed verdict file, missing spec.md), the Orchestrator should:

1. **Log the failure**: Read `.superteam/phase-transition-results.json` to identify which specific check(s) failed.
2. **Classify the failure**:
 - **Verdict file format issue** (e.g., missing frontmatter): This is a fixable infrastructure issue, not a real evaluation failure. The Orchestrator should fix the verdict file format and retry the transition - do NOT re-run the Strict Evaluator.
 - **Missing prerequisite** (e.g., spec.md deleted, gate results missing): This indicates a pipeline state corruption. Forward to the Architect for diagnosis and targeted fix increments.
 - **Real evaluation gap** (e.g., verdict file says PASS but gates actually failed): This should not happen - it indicates a Strict Evaluator bug. Escalate to TL for user intervention.
3. **Retry the transition** after fixing the identified issue. If the transition fails a second time after the fix, escalate to TL for user intervention rather than looping indefinitely. 

## Iteration Cap

A maximum of 3 FAIL records is enforced. The count is derived directly from the append-only log:

```bash
jq '[.[] | select(.verdict=="FAIL")] | length' .superteam/strict-evaluations.jsonl
```

| FAIL count | Action |
|----------- |--------|
| 0 | First spawn of Strict Evaluator |
| 1 | First FAIL - restart with failure context from the log |
| 2 | Second FAIL - restart with accumulated failure records |
| 3 | Third FAIL - do NOT restart; escalate to the user |

When 3 FAIL records are present without achieving PASS, the Orchestrator sends:
`SendMessage` to `"team-lead"` - "ESCALATION: 3 FAIL records in strict-evaluations.jsonl. Final evaluation has failed 3 times. Please inform the user and present all accumulated failure records for manual intervention."

TL presents the accumulated failure context to the user, including:
- All FAIL records from `.superteam/strict-evaluations.jsonl` (use `jq` to render)
- The lessons-learned file
- All decision records from `.superteam/events.jsonl` (render with `jq 'select(.type=="decision")' .superteam/events.jsonl`), covering every attempted approach
- A summary of what was tried in each cycle and why it failed

This gives the user full context to decide how to proceed.

## Progressive Context

Each restart cycle builds on all previous attempts so the same issues are not repeated. When the Orchestrator forwards the failure report to the Architect, it includes:

1. **Prior failure records**: All records in `.superteam/strict-evaluations.jsonl` with `.verdict == "FAIL"`. The Architect reads them via `jq` (e.g., `jq -r '.[] | select(.verdict=="FAIL") | .summary' .superteam/strict-evaluations.jsonl`) to understand what was already attempted.
2. **Lessons-learned**: Current `.superteam/lessons-learned.md` - accumulated discoveries from all increments and cycles.
3. **Decision history**: Prior decisions in `.superteam/events.jsonl` (append-only) - query with `jq -r 'select(.type=="decision")' .superteam/events.jsonl` to surface rationale, including decisions that led to failures.

The Architect uses this accumulated context to create targeted fix increments that address the root causes identified in the failure records without repeating prior failed approaches.
