# Phase 5: Delivery (AUTOMATED - TERMINAL)

Phase 5 runs only after Phase 4 PASS. It curates knowledge, presents results to the user, and shuts down the team. This is the terminal phase of the pipeline.

**Form phases check**: If the active form's 'phases' list does not include 'deliver', skip the Curator spawn (5a, 5b) and proceed directly to 5c (delivery presentation and shutdown).

## 5a. Request Curator Spawn (Spawn Point #15)

The Orchestrator requests TL to spawn the **Curator** for knowledge consolidation from session artifacts to the global wiki.

`SendMessage` to `"team-lead"`:
```
"Spawn request: name=curator, agent_def={PLUGIN_ROOT}/agents/curator.md,
 context: The superteam session is complete. You are the Knowledge Curator.
 Read ~/.superteam/SCHEMA.md FIRST for wiki conventions.
 Read ~/.superteam/index.md to know what already exists in the global wiki.
 Session artifacts available:
 - .superteam/knowledge/ - Explorer's session findings
 - .superteam/lessons-learned.md - cross-increment discoveries
 - .superteam/events.jsonl - append-only event stream (decisions, anomalies, mutations, escalations, transitions); query with 'jq'
 - .superteam/traces/ - trajectory data per increment
 - .superteam/attempts/ - failure documentation
 - .superteam/scripts/ - hard gate verification scripts (potential reusable patterns)
 Follow your workflow: Orient --> Gather --> Extract -> Evaluate -> Verify --> Write --> Lint.
 You are an ORCHESTRATOR: dispatch subagents for ALL artifact reading, analysis, and verification.
 Keep your own context lean. When done, SendMessage to 'orchestrator': 'Knowledge curation complete.'"
```

The Orchestrator updates state: add curator to '"active_agents'.

## 5b. Wait for Curator Completion

The Curator messages the Orchestrator: "Knowledge curation complete."

1. The Orchestrator sends a shutdown request to TL for the Curator.
2. The Orchestrator updates state: remove curator from `active_agents`.

## 5c. Notify TL for Delivery and Shutdown

After Curator work is complete(or skipped), the Orchestrator notifies TL to present results and initiate shutdown:

`SendMessage` to `"team-lead"`:
```
"Pipeline complete. Please present delivery report to user and initiate shutdown."
```

TL handles the final user-facing interaction:
1. Present the final delivery report and accumulated artifacts to the user.
2. Shut down all remaining agents in order:
 - **Manager** (cancel its ScheduleWakeup loop)
 - **Architect**
 - **Explorer**
 - **Orchestrator**
3. For each agent: send shutdown message, wait for acknowledgment, confirm exit by reading `.agents.active_agents` via `scripts/state-mutate.sh get .agents.active_agents`.
4. Update `state.json`: `scripts/state-mutate.sh --set phase=complete`, then read-modify-write `.agents` to set `active_agents: []` (write `--set agents=<json>` with the emptied list).

The pipeline is complete. No further phases run.
