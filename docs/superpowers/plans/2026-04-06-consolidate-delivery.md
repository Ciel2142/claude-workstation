# Consolidate Context Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove redundant rules/ directory, install-rules skill, and MCP configs from the plugin — consolidate all context delivery to the SessionStart hook + on-demand skills.

**Architecture:** The plugin currently delivers context through three redundant layers (hook, rules, skills). After this change, only two remain: the SessionStart hook (`contexts/workflow.md`) for always-on routing context, and on-demand skills for phase-specific protocols. MCP servers are delegated to their own plugins.

**Tech Stack:** Bash, Markdown, shell scripts

---

### Task 1: Add spec amendments, micro-tiers, and skill references to `contexts/workflow.md`

**Files:**
- Modify: `contexts/workflow.md:27` (insert before "## Plugin Routing")

- [ ] **Step 1: Add three new sections to `contexts/workflow.md`**

Insert the following between the "## Hard Rules" section (ends at line 27) and "## Plugin Routing" (currently line 28). Use the Edit tool to replace `## Plugin Routing` with the new sections followed by `## Plugin Routing`:

```markdown
## Spec Amendments

When implementation reveals the spec is wrong, amend it — don't silently deviate.

**Minor (agent self-approves):** Naming mismatches, missing edge case detail, clarifying ambiguous wording, parameter type corrections to match existing code.
- Update the spec file, commit, log: `spec-amendment: minor -- <what changed>`
- Continue without interruption.

**Material (requires human approval):** Different algorithm, adding/dropping features, new dependencies, changed API shape, architectural changes.
- Stop implementing and present the change, wait for approval.
- Log: `spec-amendment: material -- <what changed>, approved by human`

Applies to Small and Medium+ tiers. Trivial tasks have no spec.

## Sub-task Micro-tiers

Within a Medium+ epic, each sub-task gets a micro-tier that determines ceremony level.

| Micro-tier | Signal | Ceremony |
|---|---|---|
| **Micro-trivial** | Config, wiring, exports, type files, boilerplate. No logic. | Micro-TDD (one assertion) → commit. Batch review every 3 tasks. |
| **Micro-small** | Single-concern logic, one function/method, straightforward. | Full TDD (red-green-refactor) → commit. Batch review every 3 tasks. |
| **Micro-complex** | New algorithm, security-sensitive, public API, cross-cutting. | Full TDD → individual code review → commit. |

When claiming a sub-task, assess its micro-tier. Log: `micro-tier: <micro-trivial|micro-small|micro-complex>`

**Micro-TDD:** One assertion proving the wiring works (import resolves, config parses, type compiles).

**Batch review cadence:** After every 3rd non-complex task, dispatch one batch code review. Micro-complex tasks get individual reviews and reset the batch counter.

## Skill References

On-demand skills for specific workflow phases — invoke when reaching that step:
- **Bug work** → `/claude-workstation:debugging-protocol` (root cause before fix, 3-strike rule)
- **Spike phase** (Medium+) → `/claude-workstation:spike-phase` (lightweight or deep validation)
- **Every 3rd sub-task** (Medium+) → `/claude-workstation:scope-health` (scope creep detection)
- **Milestone notes** → `/claude-workstation:beads-milestones` (standardized checkpoint format)
- **Verification** → `/claude-workstation:verification-template` (output format with exit codes)

## Plugin Routing
```

- [ ] **Step 2: Verify the edit**

Run: `grep -c "Spec Amendments\|Micro-tiers\|Skill References\|Plugin Routing" contexts/workflow.md`
Expected: 4

Run: `wc -c contexts/workflow.md`
Expected: approximately 4000-4200 bytes

- [ ] **Step 3: Commit**

```bash
git add contexts/workflow.md
git commit -m "feat: add spec amendments, micro-tiers, and skill references to workflow context"
```

---

### Task 2: Delete redundant files

**Files:**
- Delete: `rules/common/beads-milestones.md`
- Delete: `rules/common/debugging.md`
- Delete: `rules/common/development-workflow.md`
- Delete: `rules/common/plugin-routing.md`
- Delete: `rules/common/scope-health.md`
- Delete: `rules/common/spike-phase.md`
- Delete: `rules/common/unified-workflow.md`
- Delete: `rules/common/verification-template.md`
- Delete: `skills/install-rules/SKILL.md`
- Delete: `.mcp.json`
- Delete: `mcp-configs/optional-servers.json`

- [ ] **Step 1: Delete rules directory, install-rules skill, MCP configs**

```bash
rm -rf rules
rm -rf skills/install-rules
rm .mcp.json
rm -rf mcp-configs
```

- [ ] **Step 2: Verify deletions**

```bash
test ! -d rules && echo "OK: rules/ deleted" || echo "FAIL"
test ! -d skills/install-rules && echo "OK: install-rules/ deleted" || echo "FAIL"
test ! -f .mcp.json && echo "OK: .mcp.json deleted" || echo "FAIL"
test ! -d mcp-configs && echo "OK: mcp-configs/ deleted" || echo "FAIL"
```

Expected: 4 "OK" lines.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor: remove rules/, install-rules skill, and MCP configs

Rules content is delivered via SessionStart hook + on-demand skills.
MCP servers are provided by their own plugins (Context7, ECC)."
```

---

### Task 3: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:18-23`

- [ ] **Step 1: Replace "Rules Delivery" section with "Context Delivery"**

Replace lines 18-23 (the "## Rules Delivery" section):

```
## Rules Delivery

Workflow rules are auto-injected via SessionStart hook (~3KB). Reference skills (debugging protocol, milestones, spike phase, scope health, verification template) are loaded on demand.

- **Opt-in always-on rules:** `/claude-workstation:install-rules` — copies all rules to `~/.claude/rules/`
- **Workflow alias:** `claude-workflow` — launches Claude with workflow context
```

With:

```
## Context Delivery

Workflow context is auto-injected via SessionStart hook (~4KB). Phase-specific protocols (debugging, milestones, spike, scope health, verification) are delivered as on-demand skills.
```

- [ ] **Step 2: Verify**

Run: `grep -c "Rules Delivery\|install-rules" CLAUDE.md`
Expected: 0

Run: `grep -c "Context Delivery" CLAUDE.md`
Expected: 1

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md — rules delivery → context delivery"
```

---

### Task 4: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Remove `/install-rules` from commands table (line 60)**

Remove this line:
```
| `/claude-workstation:install-rules` | Opt-in: copy rules to ~/.claude/rules/ for always-on |
```

- [ ] **Step 2: Update "What's Included" list (line 8)**

Replace:
```
- **Auto-Injected Context** — SessionStart hook delivers workflow rules (~3KB) without setup
```
With:
```
- **Auto-Injected Context** — SessionStart hook delivers workflow context (~4KB) without setup
```

- [ ] **Step 3: Remove "Custom Rules" line (line 14)**

Replace:
```
- **Custom Rules** — Workflow routing, plugin lanes, spike phase, scope health, spec amendments, micro-tiers, structured checkpoints, verification template
```
With:
```
- **On-Demand Skills** — Phase-specific protocols for debugging, spike, scope health, milestones, verification
```

- [ ] **Step 4: Remove "MCP Servers" from What's Included (line 12)**

Remove:
```
- **MCP Servers** — context7, sequential-thinking
```

- [ ] **Step 5: Remove "Rules" section (lines 116-131)**

Remove the entire section:
```
## Rules

Copied to `~/.claude/rules/common/` during setup:

| Rule | Purpose |
|---|---|
| `unified-workflow.md` | Beads-first rule, tier definitions, spec amendments, micro-tiers, escalation |
| `plugin-routing.md` | Lane separation: Beads (tracking), Superpowers (process), ECC (expertise) |
| `development-workflow.md` | Research-first culture, GitHub search before coding |
| `verification-template.md` | Standardized verification output format with exit codes |
| `beads-milestones.md` | Structured checkpoint format — standardized key-value milestone notes |
| `debugging.md` | Debugging-first protocol for bugs: root cause before fix, 3-strike rule |
| `spike-phase.md` | Architecture validation before Medium+ implementation (lightweight/deep) |
| `scope-health.md` | Scope creep detection — warning at 1.5x, gate at 2.0x planned tasks |

Rules are auto-injected via hook by default. Run `/install-rules` to opt into always-on global rules.
```

- [ ] **Step 6: Update project structure tree (lines 146-175)**

Replace the entire "## Project Structure" section with:
```markdown
## Project Structure

```
claude-workstation/
├── commands/
│   └── help.md               # /help command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md         # /setup — environment installer
│   ├── test/SKILL.md          # /test — config validation
│   ├── debugging-protocol/    # On-demand: debugging-first protocol
│   ├── beads-milestones/      # On-demand: milestone checkpoint format
│   ├── spike-phase/           # On-demand: architecture validation
│   ├── scope-health/          # On-demand: scope creep detection
│   └── verification-template/ # On-demand: verification output format
├── contexts/
│   ├── workflow.md            # Workflow context (auto-injected via hook)
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + Stop hooks
│   └── session-start          # Context injection script
├── tests/
│   └── validate-config.sh
├── CLAUDE.md
└── AGENTS.md
```
```

- [ ] **Step 7: Verify**

Run: `grep -c "install-rules\|rules/common\|mcp-configs\|\.mcp\.json" README.md`
Expected: 0

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs: update README — remove rules, install-rules, and MCP references"
```

---

### Task 5: Update `skills/setup/SKILL.md`

**Files:**
- Modify: `skills/setup/SKILL.md:109-116`

- [ ] **Step 1: Remove the "Workflow Rules" section**

Remove lines 109-116:
```
## Workflow Rules

Rules are auto-injected via the SessionStart hook — no manual copy needed.

To opt into always-on global rules (adds ~15KB to every session's context):
```bash
/claude-workstation:install-rules
```
```

- [ ] **Step 2: Verify**

Run: `grep -c "install-rules\|Workflow Rules" skills/setup/SKILL.md`
Expected: 0

- [ ] **Step 3: Commit**

```bash
git add skills/setup/SKILL.md
git commit -m "refactor: remove workflow rules section from setup skill"
```

---

### Task 6: Update `tests/validate-config.sh`

**Files:**
- Modify: `tests/validate-config.sh:66,148,161`

- [ ] **Step 1: Remove `install-rules` from skill existence check (line 66)**

Replace:
```bash
for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template install-rules; do
```
With:
```bash
for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

- [ ] **Step 2: Remove `install-rules` from skill directory check (line 148)**

Replace:
```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template install-rules; do
```
With:
```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

- [ ] **Step 3: Remove `install-rules` from frontmatter check (line 161)**

Replace:
```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template install-rules; do
```
With:
```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

- [ ] **Step 4: Add workflow context content check for new sections**

In section 4 "Workflow context content" (line 77), add checks for the new sections. Replace:
```bash
for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Research" "Side Quests"; do
```
With:
```bash
for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Research" "Side Quests" "Spec Amendments" "Micro-tiers" "Skill References"; do
```

- [ ] **Step 5: Run the test suite**

```bash
CLAUDE_PLUGIN_ROOT="$(pwd)" bash tests/validate-config.sh
```

Expected: Some checks may fail (MCP-related, if any), but all skill checks and workflow content checks should pass.

- [ ] **Step 6: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: update validation — remove install-rules, add new section checks"
```

---

### Task 7: Global cleanup — remove installed rule files

**Files:**
- Delete: `~/.claude/rules/common/unified-workflow.md`
- Delete: `~/.claude/rules/common/plugin-routing.md`
- Delete: `~/.claude/rules/common/development-workflow.md`
- Delete: `~/.claude/rules/common/verification-template.md`
- Delete: `~/.claude/rules/common/beads-milestones.md`
- Delete: `~/.claude/rules/common/debugging.md`
- Delete: `~/.claude/rules/common/spike-phase.md`
- Delete: `~/.claude/rules/common/scope-health.md`

- [ ] **Step 1: Remove the 8 files from global rules**

```bash
for f in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md debugging.md spike-phase.md scope-health.md; do
    rm -v "$HOME/.claude/rules/common/$f" 2>/dev/null || echo "not found: $f"
done
```

- [ ] **Step 2: Verify remaining global rules are untouched**

```bash
ls ~/.claude/rules/common/
```

Expected: Only non-plugin rules remain (agents.md, coding-style.md, git-workflow.md, hooks.md, patterns.md, performance.md, security.md, testing.md).

- [ ] **Step 3: No commit needed** — this is a local machine cleanup, not a repo change.
