# Strategic Compaction at Phase Boundaries

## Problem

Long sessions accumulate context through exploration, brainstorming, planning, and debugging. Auto-compaction triggers at arbitrary points mid-task, losing important intermediate reasoning. Strategic compaction at natural phase boundaries preserves context intentionally before it's lost accidentally.

## Design

### Trigger Points

Four phase boundaries trigger a compaction assessment:

| Trigger | Milestone | Why |
|---|---|---|
| Brainstorming complete | `spec:` | Heavy exploration/discussion context can be safely compressed once spec is on disk |
| Planning complete | `plan:` | Codebase analysis and plan writing consume significant context; plan is on disk |
| Debug root cause found | `debug:` | Hypothesis testing, stack traces, and log analysis are context-heavy; root cause is logged |
| Scope-health check | Every 3rd closed sub-task | Context accumulates across sub-tasks; piggybacks on existing scope-health cadence |

### Protocol

At each trigger point:

1. **Invoke `ecc:strategic-compact`** to assess current context consumption
2. **If compaction recommended:**
   a. Write any unrecorded decisions, context, or insights to beads notes via `bd-notes-append` -- anything that lives only in conversation and wouldn't survive compaction (agent uses own judgment on what to save)
   b. Log `stopped: pre-compact -- <phase>` to beads notes
   c. Proceed with compaction
3. **If compaction not recommended:** Continue to next workflow step

### What Survives Compaction

Already persisted (no action needed):
- Milestone notes in beads (tier, spec, plan, completed, etc.)
- Spec document on disk
- Plan document on disk
- Git state (commits, branches)
- CLAUDE.md and workflow context (re-injected on session start)

Potentially lost (agent must save if relevant):
- Design decisions discussed but not captured in spec
- Failed approaches and why they were rejected
- User preferences expressed during conversation
- Context about related issues or dependencies discovered

## Implementation

Single change: add a "Strategic Compaction" section to `contexts/workflow.md` after the Scope Health section.

### Proposed workflow.md Addition

```markdown
## Strategic Compaction

At these phase boundaries, invoke `ecc:strategic-compact` to assess context consumption:
- After `spec:` milestone (brainstorming complete)
- After `plan:` milestone (planning complete)
- After `debug:` milestone (root cause found)
- During scope-health check (every 3rd closed sub-task)

If strategic-compact recommends compaction: (1) write any unrecorded decisions, context, or insights to beads notes via `bd-notes-append` -- anything that lives only in conversation and wouldn't survive compaction, (2) log `stopped: pre-compact -- <phase>`, (3) proceed with compaction.
```

### Size Impact

+7 lines, ~450 bytes. Workflow.md: ~6.7KB -> ~7.1KB (budget: ~8KB).

### What Does NOT Change

- No new milestone keys (`stopped:` already exists with "Session end / pre-compact")
- No changes to `/continue` position detection (already handles `stopped:`)
- No changes to Milestone Notes table
- No hook changes
- No changes to third-party superpowers skills

## Acceptance Criteria

1. `contexts/workflow.md` contains a "Strategic Compaction" section after Scope Health
2. Section lists the four trigger points (spec, plan, debug, scope-health)
3. Section references `ecc:strategic-compact` invocation
4. Section specifies save-to-beads-then-compact protocol
5. Existing tests pass (no regressions)
6. Behavioral test validates the section content is present in workflow.md
