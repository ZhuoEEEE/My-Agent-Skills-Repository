# References and Project Knowledge

Use this guide to import/reference external examples, create a mutable task copy, promote a reference, or record durable product/solution/roadmap knowledge.

## Reference Snapshots

Wrap each reference as `reference-projects/<reference-id>/{README.md,manifest.json,project/}`. Use a stable concise ID. The wrapper records source, retrieval time, exact version/commit when available, purpose, applicable targets, license, known differences, and build status. The schema-valid manifest records every managed body file and SHA-256. Preserve the project's own layout and README inside `project/`.

The body is an immutable, filtered snapshot and is ignored by Agent-management Git; the wrapper, manifest, and short root reference index are tracked. Do not scan reference bodies as sources/targets, attach source workstream branches, or publish them. Read only references relevant to the current task.

Apply source-import filtering: omit `.git`, local IDE state, known rebuildable outputs, and credentials/signing/license secrets; preserve legal notices, startup/linker material, and needed binaries. For a public repository record a commit/tag, not only a moving branch. A hand-placed ambiguous directory becomes pending organization; do not move or rewrite it automatically.

To modify/build a reference, use `create-reference-copy.ps1` to create `work/<workstream-id>/reference-copies/<reference-id>/project/`, wrapper provenance, cleanup criteria, and an independent no-push private Git baseline. Never publish this copy. Clean it only after its workstream is terminal and all wanted results are retained.

Promotion requires explicit user intent. Use `workspace-management/tools/promote-reference.ps1` to create a new `reference-promoted` source, perform sensitive/topology checks, and make a source-private baseline. Keep `user_source: none`, empty mappings, and no publish until the user separately approves an authority mapping.

## Durable Project Knowledge

`project-docs/README.md` is a short index of current stage, authoritative project documents, and next key decision. Create content only when real facts exist:

- `PRODUCT.md`: enduring product objective, users, scenarios, and capability boundaries, not one version's temporary limits.
- `SOLUTION.md`: currently effective system partition and constraints, not obsolete solution text.
- `ROADMAP.md`: stages with objective, dependencies, scope, exit conditions, current state, and next step.
- `decisions/YYYY-MM-DD-topic.md`: cross-task choice, alternatives, tradeoffs, evidence, status, originating workstream, and confirmation date.
- `versions/V<sequence>-topic.md`: version objective, included/excluded scope, completion criteria, and verification.

Candidate conclusions and task evidence stay in the workstream README. Promote them only after the user confirms they apply across tasks. Do not infer a product-stage transition from adding an MCU/tool or from task completion. Decision states are `待确认`, `已确认`, `已推迟`, and `已替代`; replacement preserves the old decision and links to the new one.

Markdown is authoritative. Diagrams/mind maps are optional derived views. Create interfaces or verification-matrix sections only after real cross-target communication or verification complexity emerges. Stage snapshots are optional and require explicit user request plus verified exit criteria; do not invent an archive Git policy in advance.

Initialization creates only the directory READMEs and local templates, not empty PRODUCT/SOLUTION/ROADMAP, decision, version, reference, or workstream instances.
