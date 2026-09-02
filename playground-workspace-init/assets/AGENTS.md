<!-- playground-workspace-init:rules:start version="1" -->
## Playground workspace management

These rules manage conversation ownership and artifact placement in this short-lived, multi-topic workspace. They do not override normal operations that the user explicitly authorizes for a concrete task.

### Conversation ownership

- Pure workspace initialization, upgrades, and management use `workspace-management/`; do not create a dated topic directory for them.
- Before a new conversation's first concrete task, create a new `YYYY-MM-DD-undetermined-topic[-N]/` directory and its `README.md`. Use the local creation date and the smallest available suffix.
- Create a topic directory atomically. If its name is taken, recompute the suffix and retry.
- A new conversation must never reuse, claim, move, or rename an existing topic directory.
- A continued conversation reuses its original directory. Use conversation context and the topic README to locate it. If ownership cannot be established confidently, ask before writing or moving files.

### Topic naming and documentation

- Rename only the current conversation's directory and only after the user explicitly chooses the topic or clearly requests a rename.
- Convert the topic to concise English kebab-case, keep the original date prefix, and use the smallest available numeric suffix on collision.
- After a rename, update the topic README and the managed topic index in the root `README.md`.
- Each topic README records creation date and time, an available conversation or task identifier, initial directory name, current topic, purpose, main files and outputs, status, pending work, and continuation entry points.
- Update the topic README before finishing whenever outputs, status, or pending work change.

### File placement

- Put files created, copied, downloaded, or generated for the current conversation inside its topic directory, including one-off tools, scripts, dependencies, and intermediate artifacts.
- Put single-file or one-off scripts in `scripts/`. Put multi-file tools in `tools/<tool-name>/`. Keep dependencies and configuration with the corresponding script or tool. Create only directories the task actually needs.
- Keep existing project files at their original paths; do not move them into a topic directory for bookkeeping.
- Treat source material outside the workspace as read-only. Copy it into the topic directory only when a local copy is needed.
- Keep the workspace root limited to `AGENTS.md`, the global `README.md`, `workspace-management/`, topic directories, and content the user explicitly designates as shared.

### Safety and completion

- During workspace management, do not delete files, move content of uncertain ownership, rewrite Git history, stop existing services, or overwrite user changes.
- If moving a current-topic file could break a path, dependency, or running process, leave it in place and record the exception in the topic README.
- Keep the root topic index synchronized after creating, deleting, or renaming a topic directory. Deletion still requires explicit user authorization.
- Before finishing, confirm ownership, artifact placement, current topic documentation, topic-index accuracy, and preservation of other conversations' content.
<!-- playground-workspace-init:rules:end -->
