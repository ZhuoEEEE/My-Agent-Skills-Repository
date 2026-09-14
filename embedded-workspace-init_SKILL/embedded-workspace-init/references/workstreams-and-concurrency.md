# Workstreams and Concurrency

Use this guide to create/resume workstreams, declare scope, pin dependencies, coordinate parallel tasks, or change shared workspace state.

## Workstream Rules

Each logical task owns `work/<workstream-id>/`, a source-private branch and linked worktree for every involved source, plus one schema-valid `workstream.json`. The public integration copy is an aggregation point, never the shared edit directory or publish-diff source.

Create a new workstream by default. Reuse only when the user explicitly resumes one or an available conversation binding resolves uniquely. Host/thread IDs are optional hints, not identity requirements. One conversation binds to at most one active workstream at a time.

Use a stable ID shaped like `YYYYMMDD-short-topic-<suffix>`. The machine file is authoritative for status, scope, Git refs/baselines, dependencies, unresolved changes, and timestamps. Its README is a concise human handoff with Goal, Current state, Decisions, Changes, Verification, and Next; do not turn it into command/chat logs.

Scope entries use `source_id`, normalized relative paths, and `read|write`. Reject absolute paths, `..`, link escape, and case-insensitive overlap mistakes. Register useful coarse scope before editing and recheck other active or unresolved workstreams before expanding write scope, building a high-impact generator area, or publishing. Read scope normally does not block a writer; generator configuration, linker scripts, IDE metadata, and other broad-impact inputs always warrant conflict reporting.

`completed` or `abandoned` leaves conflict consideration only when `has_unresolved_changes` is false. Use `workspace-management/tools/update-workstream.ps1` to change scope, status, or unresolved-change state after meaningful changes and before pause/handoff/completion. It creates one explicit management-Git checkpoint at those boundaries, not on every edit.

## Git Baselines And Dependencies

For each source ref record:

- `user_baseline_commit`: user content used for three-way comparison.
- `task_base_commit`: actual branch creation/rebase point, including already pinned dependencies.
- `head_commit`: frozen task result used for publish.
- `mapping_revision`: mapping version interpreted by the task.

A dependency is pinned or explicitly repinned with `workspace-management/tools/pin-workstream-dependency.ps1`. It records a concrete workstream ID and, for every source, fixed task-base/head commits and mapping revision. Verify commits are reachable in that source's private Git and reject cycles. Never depend only on a moving branch. Later dependency commits do not enter the consumer until explicitly repinned and rechecked. A combined integration branch may be built for validation but cannot replace the frozen task commit and dependency closure as publish provenance.

## Shared-State Mutex

All managed scripts that change configuration, indexes, mappings, Git refs/worktrees, baselines, or publish/recovery state share one Windows Named Mutex:

`Local\\embedded-workspace-init-<sha256-of-normalized-real-root-prefix>`

Normalize real path identity through symlinks/junctions, case, separators, and trailing separators before hashing. The operation order is: read-only plan, acquire mutex, reread all affected state and hashes, confirm the plan is still valid, write/verify, release. Timeout reports `busy` and writes nothing. Never use persistent lock files, nested mutex acquisition, or separate source locks in version 1.

Source editing and read-only scans do not require the mutex. A build confined to one worktree normally does not either, but updating build evidence/baselines does. The mutex cannot stop external editors, so file writes and rollback still require per-file expected hashes.

## Parallel Safety

Different workstreams must never edit the same physical worktree. Before new task, scope expansion, build, dependency update, or publish, inspect active and unresolved workstreams. Report overlapping write ranges and coordinate ownership; within one conversation, assign each file to one writer. A lock serializes shared metadata, not conflicting design intent.

All tasks start from the pure root in `Local`. Entering a linked worktree for commands does not make it a separate Codex project, and the initializer must not add `AGENTS.md` or override files inside integration/worktrees. User-owned files with those names remain protected content, not active workspace policy.
