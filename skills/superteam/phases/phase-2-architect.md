# Phase 2: Architect Phase (AUTOMATED)

The Orchestrator drives this phase. The Architect decomposes the spec into increments and creates contracts. After the Architect signals readiness, the **Plan Evaluator** independently verifies the plan against the spec before execution begins.

## 2a. Request Architect Spawn (Spawn Point #5)

The Orchestrator requests TL to spawn the **Architect**:

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=architect, agent_def={PLUGIN_ROOT}/agents/architect.md,
 context: The approved spec is at .superteam/spec.md. Read it and decompose
 into increments. Read the Explorer's knowledge base at .superteam/knowledge/
 before designing. Task form: {form name} (phases: {phase list}, isolation:
 {isolation mode}). Read the Architect Guidance section of {FORM_DIR}/FORM.md
 for decomposition and failure analysis guidance. Write plan.md, define contracts,
 then request TL to spawn a Gen/Eval pair for creating hard gate
 verification scripts. You stay alive through execution - available for scope
 changes, GATE-CHALLENGE, and inability responses."
```

The Orchestrator updates state: add architect, set '"architect_status: alive'.

## 2b. Handle Architect's Gate Author Request (Spawn Point #6)

The Architect will message TL with spawn requests for a Gate Author pair, e.g.:

```
"Spawn request: name=generator, agent_def={FORM_DIR}/generator.md,
 context: Phase 2 Gate Author - write hard gate verification scripts for all increments"

"Spawn request: name=evaluator, agent_def={FORM_DIR}/evaluator.md,
 context: Phase 2 Gate Author verifier - validate verification scripts catch real failures"
```

The Orchestrator forwards both spawn requests to TL via `SendMessage` to `"team-lead"`. TL fulfills them per the generic spawn protocol. The Orchestrator updates state: add both to `active_agents`.

## 2c. Wait for Contracts to be Frozen

The Orchestrator waits for the Architect to message: "Plan ready, contracts frozen."

## 2d. Request Plan Evaluator Spawn (Spawn Point #7a)

After the Architect signals readiness, the Orchestrator requests TL to spawn the **Plan Evaluator**:

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=plan-evaluator, agent_def={PLUGIN_ROOT}/agents/plan-evaluator.md,
 context: The Architect has completed Phase 2. Plan, contracts, and gate scripts
 are ready for review. Verify the plan fully corresponds to the spec, contracts
 are faithful, and all gate scripts exist. Artifacts: Spec (.superteam/spec.md),
 Plan (.superteam/plan.md), Contracts (.superteam/contracts/),
 Scripts (.superteam/scripts/). Phase transition script:
 bash {PLUGIN_ROOT}/scripts/verify-phase-transition.sh architect execute.
 Contract fidelity script: bash {PLUGIN_ROOT}/scripts/verify-contract-fidelity.sh {N}.
 Message 'architect' with verdict. Message 'orchestrator' when approved."
```

The Orchestrator updates state: add plan-evaluator to "active_agents'.

## 2e. Handle Plan Evaluator Verdict

**APPROVED**: The Plan Evaluator messages the Orchestrator: "Plan evaluation complete: APPROVED."
1. Proceed to 2f.

**REVISE**: The Plan Evaluator messages the Architect with specific issues. The Architect revises and the Plan Evaluator re-evaluates automatically.
3. If the Plan Evaluator and Architect are stuck (3+ REVISE cycles), the Plan Evaluator will escalate to the Orchestrator. The Orchestrator forwards the unresolved issue to TL via `SendMessage` for user presentation.

## 2f. Transition to Phase 3 (Spawn Point #7b - Gate Author pair + Plan Evaluator exit)

The Orchestrator coordinates the phase transition:

1. Run the phase transition verification as a final mechanical check:
 ```bash
 bash {PLUGIN_ROOT}/scripts/verify-phase-transition.sh architect execute
 ```
 Read `.superteam/phase-transition-results.json`. If `passed` is false, do NOT proceed - message the Architect and Plan Evaluator with the failures.
2. Send shutdown requests to TL for the Gate Author pair and Plan Evaluator: `SendMessage` to `"team-lead"` - "Shutdown request: name=generator. Reason: Phase 2 complete." (and similarly for evaluator and plan-evaluator).
3. Update state: phase -> execute, remove gate author pair AND plan-evaluator from `active_agents`.
4. Update `metrics.md`: record Phase 2 (Architect) completion time.
5. The Architect STAYS alive. The Explorer STAYS running.
