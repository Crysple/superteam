# Phase 1: PM Phase (INTERACTIVE) 

**Form phases check**: If the active form's 'phases' list does not include 'pm', skip Phase 1 entirely and proceed to Phase 2 with the user's request as the spec.

This is the only interactive phase. The Orchestrator coordinates all agent spawns (via TL) and phase transitions. The Explorer surveys the codebase, then the PM brainstorms with the user to produce a spec with concrete final acceptance gates.

## 1a. Request PM Spawn (Spawn Point #1)

The Orchestrator requests TL to spawn the **PM** FIRST - the user is waiting to interact, so PM is the highest priority spawn.

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=pm, agent_def={PLUGIN_ROOT}/agents/pm.md,
 context: User request: {user's original request}. Task form: {form name}.
 Read the PM Guidance section of {FORM_DIR}/FORM.md for task-form-specific additions.
 The Explorer will be performing an initial codebase survey at .superteam/knowledge/.
 Use SendMessage to 'explorer' to ask questions (it may still be starting up).
 Brainstorm with the user, then request Orchestrator to spawn a Generator for
 writing concrete final acceptance gates. After user approves gates + spec,
 write .superteam/spec.md and message Orchestrator: 'Spec ready.' (Spawn Point #2)"
```

## 1b. Request Explorer Spawn (Spawn Point #2)

The Orchestrator requests TL to spawn the **Explorer** - it begins its codebase survey concurrently with PM's brainstorming, seeding the knowledge base.

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=explorer, agent_def={PLUGIN_ROOT}/agents/explorer.md,
 context: Begin initial codebase survey. Seed knowledge base at .superteam/knowledge/.
 Before initial survey, check ~/.superteam/index.md for cached global knowledge.
 Follow warm-start procedure if it exists. When done, SendMessage to 'pm':
 'Initial codebase survey complete.' Remain available for queries."
```

The Orchestrator updates state: add explorer to `active_agents`, `phase_step` -> `waiting_for_spec`.

## 1c. Handle PM's Generator Request (Spawn Point #3)

The PM will message the Orchestrator: "Need a Generator for concrete final acceptance gates."

The Orchestrator forwards this as a spawn request to TL:

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=generator, agent_def={FORM_DIR}/generator.md,
 context: Phase 1 Gate Author - write concrete, executable final acceptance gates
 for the spec. Read the PM's requirements (they will message you or point you to
 .superteam/spec.md draft). Write executable gate scripts to
 .superteam/scripts/final/. The user will review these - there is no Evaluator.
 When scripts are ready, message 'pm' that gates are written."
```

## 1d. Wait for Spec Completion

The Orchestrator waits for the PM to message: "Spec ready for approval."

## 1e. User Approval Gate (Coordinated Through TL)

**This is the LAST human decision point before automated execution.**

TL is the sole user-facing interface for this approval gate. The Orchestrator does not handle this directly - it delegates to TL. The coordination flow:

1. The Orchestrator sends `SendMessage` to `"team-lead"`:
 "Spec is ready for approval. Please read `.superteam/spec.md`, present it including the Final Acceptance Gates section, and collect the approval decision."
2. TL reads the spec, presents it to the user, and asks: "Do you approve? (yes/no)"
3. TL relays the user's response back to the Orchestrator.
4. If **rejected**: The Orchestrator forwards the user's feedback to the PM via `SendMessage`. Return to step 1d.
5. If **approved**: Proceed to 1f.

## 1f. Transition to Phase 2 (Spawn Point #4 - PM + Generator exit)

The Orchestrator coordinates the phase transition:

1. Send shutdown requests to TL for PM and Generator: `SendMessage` to `"team-lead"` - "Shutdown request: name=pm. Reason: Phase 1 complete." (and similarly for generator).
2. Update state: phase -> architect, remove pm and generator from `active_agents`.
3. Update `metrics.md`: record Phase 1 (PM) completion time.
4. The Explorer STAYS running.
