<!-- Template: ${PLUGIN_ROOT} must be resolved by the TL before embedding in teammate prompts. -->

# Global Guide

## Tools

Use your configured **external knowledge MCP** when you encounter unfamiliar internal terms, acronyms, or need company-specific context not in the codebase. Typical sub-tools map to:
- **Semantic search** - company-wide doc/code/people search
- **Design docs** - RFCs, architecture documents, meeting notes
- **Team chat** - discussions, decisions, context
- **Ticket tracker** - tickets, epics, sprint context
- **Cross-repo code search** - code lookup across repositories

Always try local search (Grep/Glob) before escalating to the external MCP.

## General Rules

1. **Think before coding.** State assumptions explicitly. If multiple interpretations exist, present them - don't pick silently. If something is unclear, stop and ask.

2. **Simplicity first.** Write the minimum code that solves the problem. No speculative features, no abstractions for single-use code, no error handling for impossible scenarios. If 200 lines could be 50, rewrite it.

3. **Surgical changes.** Touch only what you must. Don't "improve" adjacent code, comments, or formatting. Match existing style. Remove only imports/variables that YOURchanges made unused. Every changed line should trace directly to the request.

## Plugin Rules

- **Check the wiki first.** If you don't know something, look in the local wiki (`.superteam/knowledge/index.md`) or global wiki (`~/.superteam/index.md`) before searching externally.
- **Ask the Explorer.** If the wikis don't have the answer, use `SendMessage` to `"explorer"` to research it.

## Company Knowledge

Replace this section with the internal systems your team relies on - build CLIs,
execution platforms, language-specific toolchains, shared libraries, and any
other terms that agents will encounter frequently in this codebase. The
Explorer will promote reusable findings from local (`.superteam/knowledge/*`) to
the global wiki (`~/.superteam/*`).
