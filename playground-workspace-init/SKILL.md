---
name: playground-workspace-init
description: Initialize or safely upgrade a short-lived, multi-topic Playground workspace so each conversation has isolated files, scripts, dependencies, and context notes. Use when explicitly asked to apply or update the Playground workspace convention; do not use as a formal project scaffold or to reorganize existing project source.
---

# Playground Workspace Init

Initialize or upgrade the selected workspace without taking ownership of existing user content. The lasting behavior comes from the managed rules written into the workspace root `AGENTS.md`.

## Workflow

1. Resolve the intended workspace root from the user's request or the current workspace. Never initialize the Skill's own installation directory by accident.
2. Inspect the root directory, `AGENTS.md`, `README.md`, `workspace-management/README.md`, and Git status when applicable.
3. Resolve `scripts/init_workspace.py` relative to this `SKILL.md`, then run it by absolute path:

   ```text
   python <skill-directory>/scripts/init_workspace.py init <workspace-root>
   ```

4. If the script reports an existing unmarked file, read that file and its corresponding template in `assets/`. Perform a minimal semantic merge:

   - Preserve user-authored content and unrelated rules verbatim.
   - Replace only clearly equivalent older Playground-management rules with the versioned managed block.
   - For ambiguous or substantive conflicts, stop and ask the user before changing the file.
   - Do not let the script overwrite or infer the meaning of unmarked content.

5. For pre-existing dated directories, add the topic marker from `assets/topic-README.md` only when their README and context clearly establish that they are prior Playground topic directories. Never mark a merely similar directory.
6. Rerun `init` after the managed blocks are present, then refresh the index if legacy topic markers were added. Verify that required files are readable, the topic index matches managed topic directories, and no duplicate managed blocks exist.
7. Report files created, upgraded, deliberately preserved, and any conflicts left unresolved.

Pure initialization, upgrading, and workspace maintenance belong in `workspace-management/`; do not create a dated topic directory for those operations.

## Topic Operations

When the user explicitly starts a concrete topic and a new topic directory is required, run:

```text
python <skill-directory>/scripts/init_workspace.py create-topic <workspace-root> [--conversation-id <id>]
```

The helper atomically creates `YYYY-MM-DD-undetermined-topic[-N]/`, writes its `README.md`, and refreshes the root topic index. Do not use it when continuing an existing conversation; locate and reuse that conversation's directory instead.

After a user-authorized topic rename or other legitimate directory change, refresh the index with:

```text
python <skill-directory>/scripts/init_workspace.py refresh-index <workspace-root>
```

Only rename a directory that is confidently owned by the current conversation. Convert an explicitly chosen topic to concise English kebab-case and preserve the date prefix. Ask before writing when ownership is uncertain.

## Constraints

- Keep invocation explicit; `agents/openai.yaml` disables implicit invocation.
- Never delete, migrate, claim, or rename pre-existing content merely to conform it to the convention.
- Do not initialize Git or stage, commit, switch, reset, or push Git state.
- Existing project files remain in their original locations.
- Managed blocks may be replaced during upgrades; content outside them remains untouched.
- Repeated initialization or upgrading must be idempotent.
- The initialization script handles deterministic filesystem mechanics only. Semantic merging and real conflicts remain model decisions.
