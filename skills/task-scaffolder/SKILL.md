---
name: task-scaffolder
version: 2.7.0
description: >
  Reads a plan and creates beads tasks with full dependency graph.
  TRIGGER: After plan is written, before implementation begins.
---

# Task Scaffolder

Transforms a plan document into a complete beads task structure. Does NOT execute anything.

## Type

**RIGID.** Follow every step. Do not skip. Do not rationalize.

## Input

Path to plan file (from `docs/superpowers/plans/`).

## Flow

Execute steps in order:

### Step 1: READ PLAN

Read the plan file. Identify:
- Plan title (from `# heading`)
- All `### Task N: <name>` sections
- Dependencies implied by task ordering (Task N+1 depends on Task N unless plan says otherwise)
- File paths in each task's `**Files:**` section to determine role

### Step 2: CREATE EPIC

```bash
bd create --type=epic --title="<plan title>"
```

Store the epic ID.

### Step 3: CREATE SUB-TASKS

For each `### Task N` in the plan:

```bash
bd create --type=task --title="Task N: <task name>"
bd dep add <sub-task-id> <epic-id> --type parent-child
```

Determine role from task content:
- Task modifies code files (`.sh`, `.py`, `.ts`, `.js`, `.go`, `.rs`, etc.) → `role:implementer`
- Task only modifies docs/config (`.md`, `.json`, `.yaml`, `.txt`) → `role:default`

Tag in notes:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <sub-task-id> "[M] task:created role:<role>"
```

### Step 4: WIRE DEPENDENCIES

For sequential tasks (Task N+1 depends on Task N):
```bash
bd dep add <task-N+1-id> <task-N-id> --type=blocks
```

If the plan specifies non-sequential dependencies (e.g., "Task 5 depends on Task 2"), wire those instead.

### Step 5: PRINT SUMMARY

Print the full task graph:

```
✓ Scaffolded: <epic-id> — <plan title>

Tasks:
  1. <task-1-id> — Task 1: <name> (role:implementer)
  2. <task-2-id> — Task 2: <name> (role:implementer)
  3. <task-3-id> — Task 3: <name> (role:default)
  ...

Dependencies:
  <task-2-id> blocked-by <task-1-id>
  <task-3-id> blocked-by <task-2-id>
  ...

→ Ready to implement. Choose:
  1) Subagent-driven (/superpowers:subagent-driven-development)
  2) Inline (/superpowers:executing-plans)
  3) Orchestrator (/claude-workstation:orchestrator)
```

### Step 6: RETURN CONTROL

Do NOT execute any task. Do NOT dispatch any agent. Return control to user.

## Does NOT

- Execute any task
- Dispatch any agent
- Choose implementation strategy
- Modify any files
- Write any code

## Anti-Rationalizations

| Thought | Answer |
|---------|--------|
| "I can see what needs to be done, let me start" | Create tasks only. Do not execute. |
| "This plan is simple, I'll skip the epic" | Every plan gets an epic. No exceptions. |
| "These tasks don't need dependencies" | Wire them. Sequential unless plan says otherwise. |
| "I'll assign roles later" | Tag now. Every task gets a role in notes. |
