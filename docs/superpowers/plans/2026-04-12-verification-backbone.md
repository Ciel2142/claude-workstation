# Verification Backbone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Graft GSD's verification spine onto the claude-workstation orchestrator: 4-gate taxonomy, `must_haves` schema, dedicated verifier subagent, count-only stall detection, and H2 completion sentinels with filesystem spot-check.

**Architecture:** Four new bash hook scripts do the testable work (`stall-check`, `parse-sentinel`, `parse-must-haves`, `spot-check-artifacts`) so orchestrator logic can be unit-tested. Skill markdown files and protocol templates are edited in place and verified via `validate-config.sh` grep checks. One new protocol template (`protocol-verifier.md`). One new orchestrator step (9.5). Version bumps to 2.8.0.

**Tech Stack:** Bash 5+, awk, sed, python3 (for JSON validation only, existing pattern), beads CLI, markdown.

**Beads epic:** `claude-workstation-fg0j`
**Spec:** `docs/superpowers/specs/2026-04-12-verification-backbone-design.md`

---

## File Structure

**New files (bash hook scripts):**

- `hooks/stall-check.sh` — detects revision-loop stall by comparing current issue count to previous (persistent via `/tmp/claude-workstation` state dir)
- `hooks/parse-sentinel.sh` — reads subagent response from stdin, returns the last H2 sentinel from a fixed registry or `none`
- `hooks/parse-must-haves.sh` — parses a YAML fence inside a markdown plan file at a given anchor, extracts one field as newline-separated values
- `hooks/spot-check-artifacts.sh` — given a plan path + anchor, asserts every declared artifact file exists and has ≥10 lines

**New files (tests):**

- `tests/test-stall-check.sh` — unit test for stall detection
- `tests/test-parse-sentinel.sh` — unit test for sentinel parsing
- `tests/test-parse-must-haves.sh` — unit test for must_haves parser
- `tests/test-spot-check-artifacts.sh` — unit test for artifact spot-check
- `tests/fixtures/plan-with-must-haves.md` — fixture plan file used by parse + spot-check tests

**New files (template):**

- `templates/protocol-verifier.md` — zero-tolerance verifier subagent contract

**Modified files:**

- `templates/protocol-base.md` — add H2 sentinel rule
- `templates/protocol-implementer.md` — emit `## PLAN COMPLETE`, read `must_haves` before TDD
- `templates/protocol-reviewer.md` — emit `## REVIEW PASS` or `## REVIEW BLOCKED`
- `templates/protocol-planner.md` — require per-task `## must_haves` yaml block in plan output
- `templates/protocol-build-fixer.md` — emit `## BUILD FIXED` or `## BUILD STUCK`
- `skills/agent-roles/SKILL.md` — register `verifier` role
- `skills/task-scaffolder/SKILL.md` — append `must_haves: <plan-path>#<anchor>` note per child task
- `skills/workflow/SKILL.md` — add Gate Taxonomy section, extend milestone table with verify rows
- `skills/orchestrator/SKILL.md` — add Step 9.5 (verify dispatch), stall-check calls in Steps 6 & 8, sentinel parsing + spot-check in post-dispatch rules
- `tests/validate-config.sh` — assert every protocol template declares its sentinel, verifier template exists, workflow has Gate Taxonomy section
- `.claude-plugin/plugin.json` — version 2.7.1 → 2.8.0
- `.claude-plugin/marketplace.json` — version 2.7.1 → 2.8.0
- `skills/workflow/SKILL.md`, `skills/orchestrator/SKILL.md`, `skills/agent-roles/SKILL.md`, `skills/task-scaffolder/SKILL.md` — frontmatter version 2.7.1 → 2.8.0

---

## Task 1: `hooks/stall-check.sh` (TDD)

**Files:**
- Create: `tests/test-stall-check.sh`
- Create: `hooks/stall-check.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-stall-check.sh`:

```bash
#!/usr/bin/env bash
# Unit test for hooks/stall-check.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/hooks/stall-check.sh"
STATE_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR"' EXIT
export CLAUDE_WORKSTATION_STATE_DIR="$STATE_DIR"
TASK="test-task-001"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: first call has no prior state, always OK
if out=$(bash "$SCRIPT" "$TASK" spec 5 2>&1) && echo "$out" | grep -q "OK"; then
    pass "first call prints OK and exits 0"
else
    fail "first call rejected or no OK output: $out"
fi

# Case 2: decreasing count continues
if out=$(bash "$SCRIPT" "$TASK" spec 3 2>&1) && echo "$out" | grep -q "OK"; then
    pass "decreasing count continues"
else
    fail "decreasing count rejected: $out"
fi

# Case 3: equal count stalls (exit 1)
set +e
out=$(bash "$SCRIPT" "$TASK" spec 3 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "STALLED"; then
    pass "equal count stalls with exit 1"
else
    fail "equal count did not stall (rc=$rc): $out"
fi

# Case 4: growing count stalls
bash "$SCRIPT" "$TASK" quality 2 >/dev/null
set +e
out=$(bash "$SCRIPT" "$TASK" quality 5 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ]; then
    pass "growing count stalls"
else
    fail "growing count did not stall (rc=$rc)"
fi

# Case 5: different phases use independent state
bash "$SCRIPT" new-task-002 spec 10 >/dev/null
if bash "$SCRIPT" new-task-002 quality 10 >/dev/null 2>&1; then
    pass "phases are independent"
else
    fail "phases leaked state"
fi

# Case 6: usage error on missing args
set +e
bash "$SCRIPT" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
    pass "missing args returns exit 2"
else
    fail "missing args returned rc=$rc"
fi

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-stall-check.sh`
Expected: fails on every case with message about `hooks/stall-check.sh` not found.

- [ ] **Step 3: Write the implementation**

Create `hooks/stall-check.sh`:

```bash
#!/usr/bin/env bash
# Detect stall in revision loop by comparing current issue count to previous.
# Usage: stall-check.sh <task-id> <phase> <current-count>
# Phase: spec | quality
# State persisted per (task-id, phase) under $CLAUDE_WORKSTATION_STATE_DIR.
# Exit 0 = not stalled (state updated, continue)
# Exit 1 = stalled (current >= previous)
# Exit 2 = usage error

set -euo pipefail

TASK_ID="${1:-}"
PHASE="${2:-}"
CURRENT="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$PHASE" ] || [ -z "$CURRENT" ]; then
    echo "Usage: stall-check.sh <task-id> <phase> <current-count>" >&2
    exit 2
fi

case "$CURRENT" in
    ''|*[!0-9]*)
        echo "error: current-count must be a non-negative integer, got: $CURRENT" >&2
        exit 2
        ;;
esac

STATE_DIR="${CLAUDE_WORKSTATION_STATE_DIR:-/tmp/claude-workstation}"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/stall-${TASK_ID}-${PHASE}.count"

PREV=""
if [ -f "$STATE_FILE" ]; then
    PREV=$(cat "$STATE_FILE")
fi

if [ -n "$PREV" ] && [ "$CURRENT" -ge "$PREV" ]; then
    echo "STALLED: phase=$PHASE task=$TASK_ID count=$CURRENT prev=$PREV"
    exit 1
fi

echo "$CURRENT" > "$STATE_FILE"
echo "OK: phase=$PHASE task=$TASK_ID count=$CURRENT prev=${PREV:-infinity}"
exit 0
```

- [ ] **Step 4: Mark executable + run test to verify it passes**

Run:
```bash
chmod +x hooks/stall-check.sh tests/test-stall-check.sh
bash tests/test-stall-check.sh
```
Expected: all 6 cases pass, `Passed: 6  Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/stall-check.sh tests/test-stall-check.sh
git commit -m "feat(hooks): add stall-check.sh for revision loop stall detection

Count-only comparison (current >= previous = stall). Per-(task,phase)
state persisted to \$CLAUDE_WORKSTATION_STATE_DIR. Exit 1 on stall,
exit 2 on usage error. Matches GSD revision-gate semantics.

Part of claude-workstation-fg0j."
```

---

## Task 2: `hooks/parse-sentinel.sh` (TDD)

**Files:**
- Create: `tests/test-parse-sentinel.sh`
- Create: `hooks/parse-sentinel.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-parse-sentinel.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/hooks/parse-sentinel.sh"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: ## PLAN COMPLETE
out=$(printf '## Work summary\ndid stuff\n\n## PLAN COMPLETE\n' | bash "$SCRIPT")
[ "$out" = "## PLAN COMPLETE" ] && pass "PLAN COMPLETE matched" || fail "PLAN COMPLETE: got '$out'"

# Case 2: ## VERIFICATION FAILED with trailing reason
out=$(printf 'findings below\n\n## VERIFICATION FAILED missing artifact\n' | bash "$SCRIPT")
case "$out" in
    "## VERIFICATION FAILED"*) pass "VERIFICATION FAILED prefix matched" ;;
    *) fail "VERIFICATION FAILED: got '$out'" ;;
esac

# Case 3: no sentinel → exit 1, print 'none'
set +e
out=$(printf '## Random heading\nnothing special\n' | bash "$SCRIPT")
rc=$?
set -e
if [ "$rc" -eq 1 ] && [ "$out" = "none" ]; then
    pass "missing sentinel exits 1 and prints none"
else
    fail "missing sentinel: rc=$rc out='$out'"
fi

# Case 4: last sentinel wins when multiple present
out=$(printf '## PLAN READY\ndraft done\n\n## PLAN COMPLETE\nfinalized\n' | bash "$SCRIPT")
[ "$out" = "## PLAN COMPLETE" ] && pass "last sentinel chosen" || fail "last sentinel: got '$out'"

# Case 5: ## REVIEW BLOCKED
out=$(printf '## REVIEW BLOCKED\n' | bash "$SCRIPT")
[ "$out" = "## REVIEW BLOCKED" ] && pass "REVIEW BLOCKED matched" || fail "REVIEW BLOCKED: got '$out'"

# Case 6: ## BUILD FIXED
out=$(printf '## BUILD FIXED\n' | bash "$SCRIPT")
[ "$out" = "## BUILD FIXED" ] && pass "BUILD FIXED matched" || fail "BUILD FIXED: got '$out'"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-parse-sentinel.sh`
Expected: all cases fail (script missing).

- [ ] **Step 3: Write the implementation**

Create `hooks/parse-sentinel.sh`:

```bash
#!/usr/bin/env bash
# Parse subagent response for the last H2 sentinel marker.
# Reads stdin. Prints the matching H2 line on stdout.
# Exit 0 if a sentinel was found. Exit 1 if none.
# Usage: cat response.txt | parse-sentinel.sh

set -euo pipefail

SENTINELS=(
    "## PLAN COMPLETE"
    "## PLAN READY"
    "## PLAN BLOCKED"
    "## REVIEW PASS"
    "## REVIEW BLOCKED"
    "## VERIFICATION PASSED"
    "## VERIFICATION FAILED"
    "## BUILD FIXED"
    "## BUILD STUCK"
    "## BLOCKED"
)

INPUT=$(cat)

LAST_MATCH=""
while IFS= read -r line; do
    for s in "${SENTINELS[@]}"; do
        if [[ "$line" == "$s" || "$line" == "$s "* ]]; then
            LAST_MATCH="$line"
            break
        fi
    done
done <<< "$INPUT"

if [ -z "$LAST_MATCH" ]; then
    echo "none"
    exit 1
fi

echo "$LAST_MATCH"
exit 0
```

- [ ] **Step 4: Mark executable + run test**

Run:
```bash
chmod +x hooks/parse-sentinel.sh tests/test-parse-sentinel.sh
bash tests/test-parse-sentinel.sh
```
Expected: `Passed: 6  Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/parse-sentinel.sh tests/test-parse-sentinel.sh
git commit -m "feat(hooks): add parse-sentinel.sh for H2 completion marker detection

Recognizes 10 registered sentinels. Returns last-occurring match
(prose often restates earlier phases). Exit 1 + 'none' on miss.
Orchestrator calls this to classify subagent returns.

Part of claude-workstation-fg0j."
```

---

## Task 3: Fixture plan file for parse + spot-check tests

**Files:**
- Create: `tests/fixtures/plan-with-must-haves.md`

- [ ] **Step 1: Create the fixture**

Create `tests/fixtures/plan-with-must-haves.md`:

````markdown
# Fixture Plan

## must_haves

```yaml
truths:
  - Orchestrator dispatches verifier after quality PASS
  - Stall detection triggers escalate on equal count
artifacts:
  - hooks/stall-check.sh
  - hooks/parse-sentinel.sh
key_links:
  - skills/orchestrator/SKILL.md:Step-9.5 -> templates/protocol-verifier.md
```

## Tasks

### Task 1: Implement stall-check

```yaml
must_haves:
  truths:
    - stall-check.sh returns exit 1 on equal count
  artifacts:
    - hooks/stall-check.sh
  key_links:
    - skills/orchestrator/SKILL.md:Step-6 -> hooks/stall-check.sh
```

### Task 2: Implement parse-sentinel

```yaml
must_haves:
  truths:
    - parse-sentinel.sh matches last H2 sentinel
  artifacts:
    - hooks/parse-sentinel.sh
```
````

- [ ] **Step 2: Verify the fixture is valid markdown + yaml**

Run:
```bash
python3 -c "
import re, yaml
content = open('tests/fixtures/plan-with-must-haves.md').read()
fences = re.findall(r'\`\`\`yaml\n(.*?)\n\`\`\`', content, re.DOTALL)
assert len(fences) == 3, f'expected 3 yaml fences, got {len(fences)}'
for f in fences:
    yaml.safe_load(f)
print('OK: 3 valid yaml fences')
"
```
Expected: `OK: 3 valid yaml fences`.

If `yaml` module missing on the target machine, install with `pip install pyyaml` or skip this guard (fixture content is still valid by construction).

- [ ] **Step 3: Commit**

```bash
git add tests/fixtures/plan-with-must-haves.md
git commit -m "test: add plan-with-must-haves.md fixture for parser tests

Contains one epic-level must_haves block and two per-task blocks
covering truths/artifacts/key_links. Used by parse-must-haves and
spot-check-artifacts tests.

Part of claude-workstation-fg0j."
```

---

## Task 4: `hooks/parse-must-haves.sh` (TDD)

**Files:**
- Create: `tests/test-parse-must-haves.sh`
- Create: `hooks/parse-must-haves.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-parse-must-haves.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/hooks/parse-must-haves.sh"
PLAN="$REPO/tests/fixtures/plan-with-must-haves.md"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: epic artifacts
out=$(bash "$SCRIPT" "$PLAN" epic artifacts)
expected=$'hooks/stall-check.sh\nhooks/parse-sentinel.sh'
if [ "$out" = "$expected" ]; then
    pass "epic artifacts extracted"
else
    fail "epic artifacts: got '$out'"
fi

# Case 2: epic truths (2 items)
out=$(bash "$SCRIPT" "$PLAN" epic truths)
count=$(echo "$out" | wc -l)
[ "$count" -eq 2 ] && pass "epic truths count=2" || fail "epic truths count=$count"

# Case 3: task-1 artifacts
out=$(bash "$SCRIPT" "$PLAN" task-1 artifacts)
[ "$out" = "hooks/stall-check.sh" ] && pass "task-1 artifacts" || fail "task-1 artifacts: got '$out'"

# Case 4: task-2 truths
out=$(bash "$SCRIPT" "$PLAN" task-2 truths)
[ "$out" = "parse-sentinel.sh matches last H2 sentinel" ] && pass "task-2 truths" || fail "task-2 truths: got '$out'"

# Case 5: task-2 key_links (empty, missing field)
out=$(bash "$SCRIPT" "$PLAN" task-2 key_links)
[ -z "$out" ] && pass "task-2 key_links empty" || fail "task-2 key_links non-empty: '$out'"

# Case 6: missing anchor returns exit 1
set +e
bash "$SCRIPT" "$PLAN" task-99 artifacts 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing anchor exits 1" || fail "missing anchor rc=$rc"

# Case 7: missing plan file returns exit 1
set +e
bash "$SCRIPT" /nonexistent.md epic artifacts 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing plan file exits 1" || fail "missing plan rc=$rc"

# Case 8: invalid field returns exit 2
set +e
bash "$SCRIPT" "$PLAN" epic bogus 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] && pass "invalid field exits 2" || fail "invalid field rc=$rc"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-parse-must-haves.sh`
Expected: all cases fail, script missing.

- [ ] **Step 3: Write the implementation**

Create `hooks/parse-must-haves.sh`:

```bash
#!/usr/bin/env bash
# Parse a must_haves YAML fence from a plan markdown file at a given anchor.
# Usage: parse-must-haves.sh <plan-path> <anchor> <field>
#   <anchor>: "epic" -> top-level "## must_haves"
#             "task-N" -> "### Task N:" heading
#   <field>:  truths | artifacts | key_links
# Prints extracted list entries one per line on stdout.
# Exit 0 = success, 1 = parse error or not found, 2 = usage.

set -euo pipefail

PLAN="${1:-}"
ANCHOR="${2:-}"
FIELD="${3:-}"

if [ -z "$PLAN" ] || [ -z "$ANCHOR" ] || [ -z "$FIELD" ]; then
    echo "Usage: parse-must-haves.sh <plan-path> <anchor> <field>" >&2
    exit 2
fi

case "$FIELD" in
    truths|artifacts|key_links) ;;
    *) echo "error: field must be truths|artifacts|key_links" >&2; exit 2 ;;
esac

if [ ! -f "$PLAN" ]; then
    echo "error: plan file not found: $PLAN" >&2
    exit 1
fi

# Resolve anchor -> heading regex
if [ "$ANCHOR" = "epic" ]; then
    HEADING='^## must_haves[[:space:]]*$'
elif [[ "$ANCHOR" == task-* ]]; then
    N="${ANCHOR#task-}"
    case "$N" in
        ''|*[!0-9]*) echo "error: task anchor must be task-<integer>" >&2; exit 2 ;;
    esac
    HEADING="^### Task ${N}:"
else
    echo "error: anchor must be 'epic' or 'task-<N>'" >&2
    exit 2
fi

# Extract the section: from heading line until next heading of same-or-higher level.
SECTION=$(awk -v re="$HEADING" -v is_epic="$([ "$ANCHOR" = epic ] && echo 1 || echo 0)" '
    BEGIN { in_section = 0 }
    $0 ~ re && !in_section { in_section = 1; next }
    in_section && is_epic == 1 && /^## / { exit }
    in_section && is_epic == 0 && /^### / { exit }
    in_section && is_epic == 0 && /^## / { exit }
    in_section { print }
' "$PLAN")

if [ -z "$SECTION" ]; then
    echo "error: anchor not found: $ANCHOR" >&2
    exit 1
fi

# Extract the first yaml fence inside the section.
YAML=$(echo "$SECTION" | awk '
    /^```yaml[[:space:]]*$/ { in_yaml = 1; next }
    /^```[[:space:]]*$/ && in_yaml { exit }
    in_yaml { print }
')

if [ -z "$YAML" ]; then
    echo "error: no yaml fence found under anchor: $ANCHOR" >&2
    exit 1
fi

# Pull the field's list entries. Handles two-space-indented list items.
echo "$YAML" | awk -v field="$FIELD" '
    BEGIN { in_field = 0 }
    {
        if (match($0, "^[[:space:]]*" field ":[[:space:]]*$")) {
            in_field = 1
            next
        }
        if (in_field && match($0, "^[a-z_]+:")) {
            in_field = 0
        }
        if (in_field && match($0, "^[[:space:]]*-[[:space:]]*")) {
            item = substr($0, RSTART + RLENGTH)
            print item
        }
    }
'
```

- [ ] **Step 4: Mark executable + run test**

Run:
```bash
chmod +x hooks/parse-must-haves.sh tests/test-parse-must-haves.sh
bash tests/test-parse-must-haves.sh
```
Expected: `Passed: 8  Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/parse-must-haves.sh tests/test-parse-must-haves.sh
git commit -m "feat(hooks): add parse-must-haves.sh for plan-file YAML extraction

Resolves anchor 'epic' -> ## must_haves, 'task-N' -> ### Task N:.
Reads first yaml fence under the resolved section and prints one field
(truths/artifacts/key_links) as newline-separated entries. Exit 1 on
missing anchor or fence, exit 2 on usage.

Part of claude-workstation-fg0j."
```

---

## Task 5: `hooks/spot-check-artifacts.sh` (TDD)

**Files:**
- Create: `tests/test-spot-check-artifacts.sh`
- Create: `hooks/spot-check-artifacts.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-spot-check-artifacts.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/hooks/spot-check-artifacts.sh"
PLAN="$REPO/tests/fixtures/plan-with-must-haves.md"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: epic block — both artifacts exist (previous tasks created them).
if out=$(cd "$REPO" && bash "$SCRIPT" "$PLAN" epic 2>&1); then
    pass "epic artifacts pass spot-check"
else
    fail "epic artifacts rejected: $out"
fi

# Case 2: task-1 — only stall-check.sh exists, still passes (it's the only required)
if out=$(cd "$REPO" && bash "$SCRIPT" "$PLAN" task-1 2>&1); then
    pass "task-1 artifact passes"
else
    fail "task-1 rejected: $out"
fi

# Case 3: anchor missing -> exit 1
set +e
bash "$SCRIPT" "$PLAN" task-99 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing anchor exits 1" || fail "missing anchor rc=$rc"

# Case 4: fake plan file with artifact pointing to nonexistent file
FAKE=$(mktemp)
cat > "$FAKE" <<EOF
## must_haves

\`\`\`yaml
truths:
  - fake
artifacts:
  - nonexistent/path/to/file.txt
\`\`\`
EOF
set +e
out=$(cd "$REPO" && bash "$SCRIPT" "$FAKE" epic 2>&1)
rc=$?
set -e
rm -f "$FAKE"
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "missing"; then
    pass "missing artifact fails"
else
    fail "missing artifact: rc=$rc out=$out"
fi

# Case 5: usage error on missing args
set +e
bash "$SCRIPT" 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] && pass "missing args exits 2" || fail "missing args rc=$rc"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-spot-check-artifacts.sh`
Expected: fails (script missing).

- [ ] **Step 3: Write the implementation**

Create `hooks/spot-check-artifacts.sh`:

```bash
#!/usr/bin/env bash
# Orchestrator-side spot-check: confirm each must_haves artifact exists
# and has at least 10 lines of content. This is the anti-hallucination
# insurance that runs before trusting a subagent's ## PLAN COMPLETE.
#
# Usage: spot-check-artifacts.sh <plan-path> <anchor>
# Exit 0 = every artifact present and non-trivial
# Exit 1 = at least one artifact missing or too short, or parse error
# Exit 2 = usage error

set -euo pipefail

PLAN="${1:-}"
ANCHOR="${2:-}"

if [ -z "$PLAN" ] || [ -z "$ANCHOR" ]; then
    echo "Usage: spot-check-artifacts.sh <plan-path> <anchor>" >&2
    exit 2
fi

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE="$HOOKS_DIR/parse-must-haves.sh"

if [ ! -x "$PARSE" ] && [ ! -f "$PARSE" ]; then
    echo "error: parse-must-haves.sh not found at $PARSE" >&2
    exit 1
fi

ARTIFACTS=$(bash "$PARSE" "$PLAN" "$ANCHOR" artifacts) || {
    echo "FAIL: cannot parse artifacts from $PLAN#$ANCHOR" >&2
    exit 1
}

if [ -z "$ARTIFACTS" ]; then
    echo "FAIL: no artifacts declared under $ANCHOR" >&2
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MIN_LINES=10
FAILED=0

while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    FULL="$REPO_ROOT/$artifact"
    if [ ! -f "$FULL" ]; then
        echo "FAIL: artifact missing: $artifact" >&2
        FAILED=1
        continue
    fi
    LINES=$(wc -l < "$FULL")
    if [ "$LINES" -lt "$MIN_LINES" ]; then
        echo "FAIL: artifact too short ($LINES < $MIN_LINES lines): $artifact" >&2
        FAILED=1
        continue
    fi
    echo "OK: $artifact ($LINES lines)"
done <<< "$ARTIFACTS"

exit "$FAILED"
```

- [ ] **Step 4: Mark executable + run test**

Run:
```bash
chmod +x hooks/spot-check-artifacts.sh tests/test-spot-check-artifacts.sh
bash tests/test-spot-check-artifacts.sh
```
Expected: `Passed: 5  Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add hooks/spot-check-artifacts.sh tests/test-spot-check-artifacts.sh
git commit -m "feat(hooks): add spot-check-artifacts.sh for must_haves file presence

Delegates YAML parsing to parse-must-haves.sh. For each artifact
declared under a plan-file anchor, confirms the file exists and
contains >=10 lines. Exit 1 if any artifact is missing or trivial.
Orchestrator runs this after a completion sentinel to catch lying
subagents.

Part of claude-workstation-fg0j."
```

---

## Task 6: `templates/protocol-verifier.md`

**Files:**
- Create: `templates/protocol-verifier.md`

- [ ] **Step 1: Write the verifier protocol template**

Create `templates/protocol-verifier.md`:

```markdown
# Verifier Bead Protocol

Zero-tolerance final check. Revision already ran. Spec and quality already passed.
Your job: catch lies.

## Core Mindset

Do NOT trust the subagent's SUMMARY or `## PLAN COMPLETE` marker.
Do NOT re-run the tests the implementer claimed to pass.
Open each file. Read actual code. Verify `must_haves` are wired.

## Self-Gather Context

1. Run `bd show <task-id>` and find the note line `must_haves: <plan-path>#<anchor>`.
2. Open the plan file at that path. Parse the YAML fence under the matching anchor.
   (You may invoke `bash hooks/parse-must-haves.sh <plan-path> <anchor> <field>` for each field.)
3. For every entry in `must_haves`, verify independently.

## Verification Procedure

For each `artifact`:
- Use the Read tool to open the file. Does it exist? Does it contain more than 10 lines of real code (not placeholder)?
- Grep for stub patterns: `TODO`, `pass  # implement`, `throw new Error("not implemented")`, `raise NotImplementedError`.

For each `truth`:
- If the truth specifies a prove command, run it via Bash. Read exit code and output.
- If the truth is "file X contains Y", grep directly.

For each `key_link` formatted as `<src>:<anchor> -> <dst>:<anchor>`:
- Grep the src file for a reference to dst. Grep the dst file for the incoming hook from src.
- Both sides must match. One-sided = BLOCKED.

## Structured Report Format

```
VERIFY: <task-id>
PLAN: <plan-path>
VERDICT: PASS | FAIL

CHECKED:
- artifact: <path> -> <exists|missing|stub>
- truth: <description> -> <verified|failed> (evidence: <output snippet>)
- key_link: <src> -> <dst> -> <wired|missing-src|missing-dst>

ISSUES: (empty if PASS)
- [BLOCKER] <category>: <file>:<line> <specific description>
```

## Rules (Non-Negotiable)

1. Zero findings = PASS. Any finding = FAIL.
2. FAIL always escalates. There is no revision loop at this phase.
3. Report only. Do NOT fix code. Do NOT create beads tasks. Do NOT write milestones other than your own role's milestone.
4. Read files directly with the Read tool. Never trust upstream SUMMARY reports.
5. Emit `## VERIFICATION PASSED` or `## VERIFICATION FAILED` as the last H2 in your response.

## Sentinel

Last H2 of your response MUST be exactly one of:
- `## VERIFICATION PASSED`
- `## VERIFICATION FAILED <short reason>`

<!-- BEAD-PROTOCOL-v1:verifier -->
```

- [ ] **Step 2: Verify the file was created with the right marker**

Run:
```bash
grep -c "BEAD-PROTOCOL-v1:verifier" templates/protocol-verifier.md
grep -c "VERIFICATION PASSED" templates/protocol-verifier.md
grep -c "VERIFICATION FAILED" templates/protocol-verifier.md
```
Expected: `1`, `2`, `2` (or more for PASSED/FAILED since they appear in rules section).

- [ ] **Step 3: Commit**

```bash
git add templates/protocol-verifier.md
git commit -m "feat(templates): add protocol-verifier.md zero-tolerance verifier contract

Do-not-trust-SUMMARY mindset. Reads plan-file must_haves fresh every
invocation via parse-must-haves.sh. Reports CHECKED + ISSUES blocks,
emits ## VERIFICATION PASSED or ## VERIFICATION FAILED sentinel.
Report-only: no code fixes, no task creation.

Part of claude-workstation-fg0j."
```

---

## Task 7: Update `templates/protocol-base.md` — H2 sentinel rule

**Files:**
- Modify: `templates/protocol-base.md`

- [ ] **Step 1: Read the current file**

Run: `cat templates/protocol-base.md`
Note the structure — this is a short shared preamble (30 lines). Append new "Completion Sentinel" section at the end, before any existing `BEAD-PROTOCOL-v1` marker.

- [ ] **Step 2: Append the sentinel section**

Add this block at the end of `templates/protocol-base.md` (before any trailing `<!-- BEAD-PROTOCOL -->` comment):

```markdown
## Completion Sentinel (Mandatory)

Every subagent dispatched via a protocol template MUST emit exactly one H2 sentinel as the **last H2 heading** of its response. The orchestrator parses this sentinel to classify the outcome. Without it, the work is rejected and the subagent is re-dispatched.

Registered sentinels:

| Role | On success | On failure |
|------|-----------|-----------|
| implementer | `## PLAN COMPLETE` | `## BLOCKED <reason>` |
| reviewer (spec or quality) | `## REVIEW PASS` | `## REVIEW BLOCKED` |
| verifier | `## VERIFICATION PASSED` | `## VERIFICATION FAILED <reason>` |
| planner | `## PLAN READY` | `## PLAN BLOCKED <reason>` |
| build-fixer | `## BUILD FIXED` | `## BUILD STUCK <reason>` |

Rules:

1. The sentinel MUST be the last H2 heading in the response.
2. Exactly one sentinel per response.
3. The sentinel is required in addition to any beads milestone your role writes — they reinforce each other.
4. The orchestrator runs a filesystem spot-check after a success sentinel. If no artifact in the task's `must_haves` was actually modified, the orchestrator treats the sentinel as a lie and escalates via `bd human`.

## must_haves (Read Before Work)

If your task has a beads note of the form `must_haves: <plan-path>#<anchor>`, you MUST read the YAML block at that anchor before starting work. It contains:

- `truths`: observable behaviors that must hold after the task
- `artifacts`: files that must exist with real implementation
- `key_links`: wiring between artifacts (`<src>:<anchor> -> <dst>:<anchor>`)

Use `bash hooks/parse-must-haves.sh <plan-path> <anchor> <field>` to extract entries, or read the plan file directly.
```

Use the Edit tool or append with `cat >> templates/protocol-base.md <<'EOF' ... EOF`.

- [ ] **Step 3: Verify the update**

Run:
```bash
grep -c "Completion Sentinel" templates/protocol-base.md
grep -c "must_haves" templates/protocol-base.md
```
Expected: `1`, at least `3`.

- [ ] **Step 4: Commit**

```bash
git add templates/protocol-base.md
git commit -m "feat(templates): add completion sentinel + must_haves read rules to base

All subagents must emit one H2 sentinel as their last H2 heading.
All subagents must read must_haves from the plan file before work if
the task has a must_haves note pointer. Base template is imported by
every role-specific protocol.

Part of claude-workstation-fg0j."
```

---

## Task 8: Update `templates/protocol-implementer.md`

**Files:**
- Modify: `templates/protocol-implementer.md`

- [ ] **Step 1: Read the file**

Run: `cat templates/protocol-implementer.md`
The file currently shows the TDD milestone chain. We need to add a `must_haves` read step before TDD and a sentinel emission note at the end.

- [ ] **Step 2: Insert the must_haves pre-step**

Use Edit tool. Find the line:

```
## Before ANY Code Changes
```

Replace with:

```
## Before ANY Code Changes

Read the task's `must_haves` block first:

```bash
# Find the pointer in beads notes
bd show <task-id> | grep '^must_haves:' || echo "WARNING: no must_haves pointer — escalate to orchestrator"
# Extract fields (run for each field needed)
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> truths
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> artifacts
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> key_links
```

The truths are your acceptance criteria. Your TDD test must drive at least one truth. Your implementation must touch every artifact. Your wiring must satisfy every key_link.

## TDD Preamble
```

- [ ] **Step 3: Append the sentinel block at the end**

Append before the `<!-- BEAD-PROTOCOL-v1:implementer -->` marker:

```markdown

## Completion Sentinel

After writing `[M] tdd:ready-for-review` milestone, emit as the LAST H2 of your response body:

- `## PLAN COMPLETE` on success
- `## BLOCKED <short reason>` if you could not complete (e.g., upstream task returned bad output, test framework broken, ambiguous spec)

The orchestrator will not accept your return without this sentinel.
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "must_haves" templates/protocol-implementer.md
grep -c "## PLAN COMPLETE" templates/protocol-implementer.md
```
Expected: ≥2, `1`.

- [ ] **Step 5: Commit**

```bash
git add templates/protocol-implementer.md
git commit -m "feat(templates): require must_haves read + ## PLAN COMPLETE sentinel

Implementer reads must_haves (truths/artifacts/key_links) before TDD
to anchor acceptance on observable behaviors. Emits ## PLAN COMPLETE
as final H2 so orchestrator can classify the return without needing
a bd show round-trip.

Part of claude-workstation-fg0j."
```

---

## Task 9: Update `templates/protocol-reviewer.md`

**Files:**
- Modify: `templates/protocol-reviewer.md`

- [ ] **Step 1: Add sentinel requirement**

Append this block to `templates/protocol-reviewer.md` before the `<!-- BEAD-PROTOCOL-v1:reviewer -->` marker:

```markdown

## Completion Sentinel

After your structured report, emit as the LAST H2 of your response body:

- `## REVIEW PASS` if VERDICT is PASS
- `## REVIEW BLOCKED` if VERDICT is BLOCKED

The sentinel must match the VERDICT line. If they disagree, the orchestrator treats the response as corrupt and re-dispatches.
```

- [ ] **Step 2: Verify**

Run: `grep -c "REVIEW PASS\|REVIEW BLOCKED" templates/protocol-reviewer.md`
Expected: at least `2`.

- [ ] **Step 3: Commit**

```bash
git add templates/protocol-reviewer.md
git commit -m "feat(templates): reviewer emits ## REVIEW PASS or ## REVIEW BLOCKED sentinel

Sentinel must match the structured report's VERDICT line. Divergence
between sentinel and verdict = treated as corrupt, orchestrator
re-dispatches.

Part of claude-workstation-fg0j."
```

---

## Task 10: Update `templates/protocol-planner.md`

**Files:**
- Modify: `templates/protocol-planner.md`

- [ ] **Step 1: Add must_haves requirement + sentinel**

Append to `templates/protocol-planner.md` before the `<!-- BEAD-PROTOCOL-v1:planner -->` marker:

```markdown

## must_haves Block (Mandatory Per Task)

For every task in the plan you produce, you MUST write a `must_haves` YAML fence under the task heading:

````markdown
### Task N: <title>

```yaml
must_haves:
  truths:
    - <observable behavior, provable by command or grep>
  artifacts:
    - <repo-relative file path with real impl>
  key_links:
    - <src>:<anchor> -> <dst>:<anchor>
```
````

Field rules:

- `truths` has ≥1 entry. No subjective predicates like "code is clean". Every truth must be provable by a command (test run, grep, file read).
- `artifacts` has ≥1 entry. Repo-relative paths only. Must resolve to real files after the task is done, with more than 10 lines of actual implementation.
- `key_links` is optional but recommended when multiple artifacts must reference each other. Format `<src>:<anchor> -> <dst>:<anchor>` where anchor is line range, symbol, or grep pattern.

You MAY also write one epic-level `## must_haves` block at the top of the plan file covering the whole epic.

## Completion Sentinel

After the plan is written, emit as the LAST H2 of your response body:

- `## PLAN READY` on success
- `## PLAN BLOCKED <reason>` if you could not complete (e.g., spec contradictions, missing inputs)
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "must_haves" templates/protocol-planner.md
grep -c "## PLAN READY\|## PLAN BLOCKED" templates/protocol-planner.md
```
Expected: ≥3, ≥2.

- [ ] **Step 3: Commit**

```bash
git add templates/protocol-planner.md
git commit -m "feat(templates): planner must write per-task must_haves + emit ## PLAN READY

Every task in generated plans now carries a must_haves YAML fence
(truths/artifacts/key_links). Optional epic-level block. Emits
## PLAN READY / ## PLAN BLOCKED sentinel.

Part of claude-workstation-fg0j."
```

---

## Task 11: Update `templates/protocol-build-fixer.md`

**Files:**
- Modify: `templates/protocol-build-fixer.md`

- [ ] **Step 1: Add sentinel requirement**

Append to `templates/protocol-build-fixer.md` before the `<!-- BEAD-PROTOCOL-v1:build-fixer -->` marker:

```markdown

## Completion Sentinel

After the build is fixed (or confirmed unfixable), emit as the LAST H2 of your response body:

- `## BUILD FIXED` on success (build now green)
- `## BUILD STUCK <reason>` if you cannot fix it (upstream bug, missing dependency, ambiguous error)
```

- [ ] **Step 2: Verify**

Run: `grep -c "## BUILD FIXED\|## BUILD STUCK" templates/protocol-build-fixer.md`
Expected: ≥2.

- [ ] **Step 3: Commit**

```bash
git add templates/protocol-build-fixer.md
git commit -m "feat(templates): build-fixer emits ## BUILD FIXED or ## BUILD STUCK sentinel

Part of claude-workstation-fg0j."
```

---

## Task 12: Register verifier role in `skills/agent-roles/SKILL.md`

**Files:**
- Modify: `skills/agent-roles/SKILL.md`

- [ ] **Step 1: Read current role table**

Run: `cat skills/agent-roles/SKILL.md`
The role table lists: implementer, reviewer, planner, build-fixer, default.

- [ ] **Step 2: Insert verifier row**

Use Edit tool. Find:

```
| **build-fixer** | `templates/protocol-build-fixer.md` | fixes build or test errors |
| **default** | *none* — add `BEAD-ROLE:default` to prompt | **nothing above matches** |
```

Replace with:

```
| **build-fixer** | `templates/protocol-build-fixer.md` | fixes build or test errors |
| **verifier** | `templates/protocol-verifier.md` | final goal-backward verification (reads code, not SUMMARY) |
| **default** | *none* — add `BEAD-ROLE:default` to prompt | **nothing above matches** |
```

- [ ] **Step 3: Add a verifier example**

Use Edit tool. Find the "## Examples" section. Append after the "Dispatching a build-error-resolver agent" example:

```markdown

**Dispatching a verifier agent** (runs after quality review, reads source directly):
→ Role: verifier → include `templates/protocol-verifier.md` in prompt
```

- [ ] **Step 4: Bump frontmatter version**

Use Edit tool. Change line 3:

```
version: 2.7.1
```

to:

```
version: 2.8.0
```

- [ ] **Step 5: Verify**

Run:
```bash
grep -c "verifier" skills/agent-roles/SKILL.md
grep "^version:" skills/agent-roles/SKILL.md
```
Expected: ≥3, `version: 2.8.0`.

- [ ] **Step 6: Commit**

```bash
git add skills/agent-roles/SKILL.md
git commit -m "feat(agent-roles): register verifier role with protocol-verifier.md

Adds verifier to role table between build-fixer and default. Bumps
SKILL frontmatter to 2.8.0 (full version sync happens in the
version-bump task).

Part of claude-workstation-fg0j."
```

---

## Task 13: Update `skills/task-scaffolder/SKILL.md`

**Files:**
- Modify: `skills/task-scaffolder/SKILL.md`

- [ ] **Step 1: Read current scaffolder behavior**

Run: `cat skills/task-scaffolder/SKILL.md`
Locate the section that describes what to write per created child task.

- [ ] **Step 2: Add must_haves pointer instruction**

Use Edit tool. Find the section that lists fields written per child task (likely headed "For each task" or similar). Append this instruction:

```markdown

### must_haves Pointer (Mandatory)

For every child task created, after the `bd create` and `bd dep add` calls, append a must_haves note pointing at the plan file section:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <child-task-id> "must_haves: <plan-path>#task-<N>"
```

- `<plan-path>` is the repo-relative path to the plan file you are scaffolding from.
- `task-<N>` is the anchor format: `task-1`, `task-2`, etc., matching the `### Task N:` heading order in the plan file.
- If the plan has no per-task `must_haves` block but does have an epic-level one, use `#epic` instead of `#task-<N>`.
- If the plan has neither, escalate: the plan is incomplete and needs a planner re-dispatch before scaffolding.
```

- [ ] **Step 3: Bump frontmatter version to 2.8.0**

Use Edit tool. Change `version: 2.7.1` → `version: 2.8.0`.

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "must_haves" skills/task-scaffolder/SKILL.md
grep "^version:" skills/task-scaffolder/SKILL.md
```
Expected: ≥2, `version: 2.8.0`.

- [ ] **Step 5: Commit**

```bash
git add skills/task-scaffolder/SKILL.md
git commit -m "feat(task-scaffolder): append must_haves pointer to every child task

Each bd create is now followed by a bd-notes-append writing
'must_haves: <plan-path>#<anchor>'. Escalation path when plan has
no must_haves block at all.

Part of claude-workstation-fg0j."
```

---

## Task 14: Add Gate Taxonomy section to `skills/workflow/SKILL.md`

**Files:**
- Modify: `skills/workflow/SKILL.md`

- [ ] **Step 1: Insert new section between Hard Rules and Skill Invocation Priority**

Use Edit tool. Find:

```markdown
## Skill Invocation Priority
```

Insert this block immediately before it:

```markdown
## Gate Taxonomy

Every validation checkpoint maps to one of four canonical gate types (adopted from GSD).

| Gate | Purpose | On fail | Where in this repo |
|------|---------|---------|--------------------|
| **pre-flight** | Check preconditions before work | Block entry, no partial work | `milestone-gate` hook, `commit-gate` hook |
| **revision** | Evaluate output, loop back to producer | Bounded loop + stall check | Orchestrator Steps 5–8 (spec and quality review) |
| **escalation** | Surface unresolvable to human | `bd human <id>`, stop | Orchestrator Step 9.5 verify, stall detection, 3-cycle ceiling |
| **abort** | Terminate to prevent damage | Hard stop, preserve state | `stop-gate` hook, `agent-gate` hook |

**Selection heuristic:** Start pre-flight. If the check happens after work is produced, it is a revision gate. If the revision loop cannot resolve the issue, escalate. If continuing is dangerous, abort.

```

- [ ] **Step 2: Bump frontmatter version**

Use Edit tool. Change `version: 2.7.1` → `version: 2.8.0`.

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "Gate Taxonomy" skills/workflow/SKILL.md
grep -c "pre-flight\|revision\|escalation\|abort" skills/workflow/SKILL.md
grep "^version:" skills/workflow/SKILL.md
```
Expected: `1`, ≥4, `version: 2.8.0`.

- [ ] **Step 4: Commit**

```bash
git add skills/workflow/SKILL.md
git commit -m "feat(workflow): add Gate Taxonomy section with 4-gate mapping

Maps existing hooks (milestone-gate, commit-gate, stop-gate,
agent-gate) and orchestrator phases to GSD's pre-flight / revision
/ escalation / abort types. Docs-only.

Part of claude-workstation-fg0j."
```

---

## Task 15: Extend milestone table in `skills/workflow/SKILL.md`

**Files:**
- Modify: `skills/workflow/SKILL.md`

- [ ] **Step 1: Find the Enforcement Milestones table**

Use Grep or Read. Locate the TDD milestone chain table with rows `task:created`, `task:claimed`, …, `verified`.

- [ ] **Step 2: Insert verify rows**

Use Edit tool. Find the row:

```
| `tdd:ready-for-review` | tdd:refactor | Handed off to orchestrator for review |
| `review:spec` | tdd:ready-for-review | Spec compliance passed |
| `review:quality` | review:spec | Code quality review passed |
| `verified` | review:quality | Verification-before-completion done |
```

Replace with:

```
| `tdd:ready-for-review` | tdd:refactor | Handed off to orchestrator for review |
| `review:spec` | tdd:ready-for-review | Spec compliance passed |
| `review:quality` | review:spec | Code quality review passed |
| `verify:dispatched` | review:quality | Orchestrator dispatched verifier subagent |
| `verify:passed` | verify:dispatched | Verifier returned `## VERIFICATION PASSED` |
| `verify:failed` | verify:dispatched | Verifier returned `## VERIFICATION FAILED` — escalated via `bd human` |
| `verified` | verify:passed | Verification-before-completion done |
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "verify:dispatched\|verify:passed\|verify:failed" skills/workflow/SKILL.md
```
Expected: ≥3.

- [ ] **Step 4: Commit**

```bash
git add skills/workflow/SKILL.md
git commit -m "feat(workflow): extend milestone chain with verify phase

Adds verify:dispatched, verify:passed, verify:failed between
review:quality and verified. verified's prerequisite changes
from review:quality to verify:passed.

Part of claude-workstation-fg0j."
```

---

## Task 16: Add Step 9.5 (Dispatch Verifier) to orchestrator

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

- [ ] **Step 1: Read the current Step 9 and Step 10**

Run: `sed -n '140,170p' skills/orchestrator/SKILL.md`
Confirm Step 9 = CLOSE TASK, Step 10 = CHECK COMPACT TRIGGER.

- [ ] **Step 2: Insert Step 9.5 before Step 10**

Use Edit tool. Find:

```
### Step 9: CLOSE TASK

```bash
bd close <task-id>
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:closed:<task-id> all reviews passed (closure #<N>)"
```

Increment `closure_counter`.

### Step 10: CHECK COMPACT TRIGGER
```

Replace with:

```
### Step 9: DISPATCH VERIFIER

After quality-review PASS, before close.

1. Read the must_haves pointer:

```bash
MUST_HAVES_REF=$(bd show <task-id> | grep -oP '^must_haves:\s*\K.*$')
PLAN_PATH="${MUST_HAVES_REF%%#*}"
ANCHOR="${MUST_HAVES_REF##*#}"
```

If `$MUST_HAVES_REF` is empty, escalate:
```bash
bd human <task-id> --reason="no must_haves pointer — cannot verify"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:escalated-verify:<task-id> no must_haves"
```
STOP this task, move to Step 1.

2. Read `templates/protocol-verifier.md`. Dispatch verifier subagent with:
- Task ID
- Plan path
- Anchor
- Full protocol-verifier.md content

Log:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] verify:dispatched"
```

3. After verifier returns, parse the sentinel:

```bash
VERIFIER_RESPONSE=$(cat <<'VERIFIER_EOF'
<paste verifier response here>
VERIFIER_EOF
)
SENTINEL=$(echo "$VERIFIER_RESPONSE" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-sentinel.sh" || true)
```

4. Branch on sentinel:

**`## VERIFICATION PASSED`:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] verify:passed"
```
Proceed to Step 9.6 (close task).

**`## VERIFICATION FAILED`:**
```bash
bd human <task-id> --reason="verifier found unresolved issues"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] verify:failed"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:escalated-verify:<task-id>"
```
STOP this task, move to Step 1.

**Sentinel missing:** re-dispatch verifier once. If still missing, escalate as VERIFICATION FAILED.

### Step 9.6: CLOSE TASK

```bash
bd close <task-id>
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:closed:<task-id> all reviews + verify passed (closure #<N>)"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] verified"
```

Increment `closure_counter`.

### Step 10: CHECK COMPACT TRIGGER
```

- [ ] **Step 3: Bump frontmatter version**

Use Edit tool. Change `version: 2.7.1` → `version: 2.8.0` at the top of the file.

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "DISPATCH VERIFIER\|VERIFICATION PASSED\|VERIFICATION FAILED" skills/orchestrator/SKILL.md
grep "^version:" skills/orchestrator/SKILL.md
```
Expected: ≥3, `version: 2.8.0`.

- [ ] **Step 5: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat(orchestrator): add Step 9 DISPATCH VERIFIER (renumber close to 9.6)

Verifier runs after quality-review PASS, before close. Reads
must_haves pointer from bd notes, dispatches with
protocol-verifier.md. ## VERIFICATION PASSED -> close. FAILED or
missing sentinel -> bd human escalation, stop task. The existing
Step 9 CLOSE is renumbered 9.6 to preserve ordering.

Part of claude-workstation-fg0j."
```

---

## Task 17: Add stall detection to orchestrator Steps 6 and 8

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

- [ ] **Step 1: Find Step 6 ANALYZE SPEC REVIEW REPORT**

Run: `sed -n '85,125p' skills/orchestrator/SKILL.md`
Locate the `**If VERDICT: BLOCKED:**` block.

- [ ] **Step 2: Insert stall-check before cycle increment in Step 6**

Use Edit tool. Find:

```
**If VERDICT: BLOCKED:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:review-blocked:<task-id> spec <N> findings"
```
Increment `spec_cycles`. Check cycle limit (see CYCLE LIMIT below).
```

Replace with:

````
**If VERDICT: BLOCKED:**

Count findings:
```bash
ISSUE_COUNT=$(echo "$REVIEW_RESPONSE" | grep -cE '^\- \[(CRITICAL|HIGH|MEDIUM)\]')
```

**Stall check (BEFORE counting this toward cycle limit):**
```bash
set +e
bash "${CLAUDE_PLUGIN_ROOT}/hooks/stall-check.sh" <task-id> spec "$ISSUE_COUNT"
STALL_RC=$?
set -e
if [ "$STALL_RC" -eq 1 ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:stalled:<task-id> spec $ISSUE_COUNT"
    bd human <task-id> --reason="spec review stalled, count not decreasing"
    # STOP this task. Move to Step 1 (next task).
fi
```

Then log and increment cycle counter:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:review-blocked:<task-id> spec $ISSUE_COUNT findings"
```
Increment `spec_cycles`. Check cycle limit (see CYCLE LIMIT below).
````

- [ ] **Step 3: Mirror the same block in Step 8**

Use Edit tool. Find the Step 8 `**If VERDICT: BLOCKED:**` block (after "Same logic as Step 6"). Replace the whole block with:

````
**If VERDICT: BLOCKED:**

Count findings:
```bash
ISSUE_COUNT=$(echo "$REVIEW_RESPONSE" | grep -cE '^\- \[(CRITICAL|HIGH|MEDIUM)\]')
```

**Stall check:**
```bash
set +e
bash "${CLAUDE_PLUGIN_ROOT}/hooks/stall-check.sh" <task-id> quality "$ISSUE_COUNT"
STALL_RC=$?
set -e
if [ "$STALL_RC" -eq 1 ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:stalled:<task-id> quality $ISSUE_COUNT"
    bd human <task-id> --reason="quality review stalled, count not decreasing"
    # STOP this task. Move to Step 1.
fi
```

Same routing as Step 6. After all bugs fixed → re-dispatch quality reviewer (back to Step 7).
````

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "stall-check.sh" skills/orchestrator/SKILL.md
grep -c "STALL_RC" skills/orchestrator/SKILL.md
```
Expected: ≥2, ≥2.

- [ ] **Step 5: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat(orchestrator): add count-only stall detection to review Steps 6 and 8

Each BLOCKED verdict now runs hooks/stall-check.sh <task> <phase>
<count> before counting against the 3-cycle cap. Exit 1 from
stall-check triggers bd human + [M] orchestrator:stalled. Independent
state per (task,phase) via /tmp/claude-workstation.

Part of claude-workstation-fg0j."
```

---

## Task 18: Add sentinel parsing + spot-check rules to orchestrator

**Files:**
- Modify: `skills/orchestrator/SKILL.md`

- [ ] **Step 1: Find the Rigid Rules section**

Run: `grep -n "Rigid Rules" skills/orchestrator/SKILL.md`
Locate the "## Rigid Rules (All Non-Negotiable)" heading.

- [ ] **Step 2: Insert a new Post-Dispatch Parsing section before Rigid Rules**

Use Edit tool. Find:

```markdown
## Rigid Rules (All Non-Negotiable)
```

Insert this block immediately before it:

````markdown
## Post-Dispatch Parsing (Applies to Every Subagent Return)

After any subagent returns, run this sequence BEFORE acting on the response body:

1. **Parse sentinel:**

```bash
SENTINEL=$(echo "$SUBAGENT_RESPONSE" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-sentinel.sh" || echo "none")
```

2. **Fallback to bd show:** if `$SENTINEL` is `none`, read the latest `[M]` milestone from `bd show <task-id>`. If a milestone indicates the intended outcome, treat it as the effective sentinel.

3. **Reject and re-dispatch** if both the sentinel and the latest milestone are missing or contradictory:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:rejected:no-signal"
# Re-dispatch the same role once. If still missing, escalate via bd human.
```

4. **Filesystem spot-check** on any success sentinel (`## PLAN COMPLETE`, `## VERIFICATION PASSED`, `## PLAN READY`):

```bash
set +e
bash "${CLAUDE_PLUGIN_ROOT}/hooks/spot-check-artifacts.sh" "$PLAN_PATH" "$ANCHOR"
SPOT_RC=$?
set -e
if [ "$SPOT_RC" -ne 0 ]; then
    bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:spot-check-failed:<task-id>"
    bd human <task-id> --reason="sentinel claimed success but must_haves artifacts missing or trivial"
    # STOP this task. Move to Step 1.
fi
```

The spot-check is the anti-hallucination insurance. Sentinels and milestones can both be written by a lying subagent. Files in `must_haves.artifacts` cannot be faked — if they are missing or shorter than 10 lines, the claim is rejected.

````

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "parse-sentinel.sh\|spot-check-artifacts.sh" skills/orchestrator/SKILL.md
grep -c "Post-Dispatch Parsing" skills/orchestrator/SKILL.md
```
Expected: ≥2, `1`.

- [ ] **Step 4: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat(orchestrator): add post-dispatch sentinel parsing + artifact spot-check

Every subagent return now runs parse-sentinel.sh first. Missing
sentinel falls back to bd show milestone. Success sentinels trigger
spot-check-artifacts.sh; failure to find declared artifacts escalates
to bd human regardless of sentinel/milestone agreement.

Part of claude-workstation-fg0j."
```

---

## Task 19: Extend `tests/validate-config.sh`

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Read the end of the file**

Run: `tail -60 tests/validate-config.sh`
Locate the final summary block (`echo "=== Summary ==="` or similar).

- [ ] **Step 2: Add new check sections before the summary**

Use Edit tool. Find the final summary block (search for the last `echo ""` before the exit statement). Insert this block before it:

```bash
# --- N. Protocol template sentinels ---
echo ""
echo "N. Protocol template sentinels"

declare -A SENTINELS=(
    [protocol-implementer.md]="## PLAN COMPLETE"
    [protocol-reviewer.md]="## REVIEW PASS"
    [protocol-planner.md]="## PLAN READY"
    [protocol-build-fixer.md]="## BUILD FIXED"
    [protocol-verifier.md]="## VERIFICATION PASSED"
)

for tmpl in "${!SENTINELS[@]}"; do
    marker="${SENTINELS[$tmpl]}"
    if [[ -f "$PLUGIN_ROOT/templates/$tmpl" ]] && grep -qF "$marker" "$PLUGIN_ROOT/templates/$tmpl"; then
        pass "templates/$tmpl declares '$marker'"
    else
        fail "templates/$tmpl MISSING '$marker'"
    fi
done

# --- N+1. Verifier template existence ---
echo ""
echo "N+1. Verifier protocol template"

if [[ -f "$PLUGIN_ROOT/templates/protocol-verifier.md" ]] \
    && grep -q "BEAD-PROTOCOL-v1:verifier" "$PLUGIN_ROOT/templates/protocol-verifier.md"; then
    pass "templates/protocol-verifier.md exists with verifier protocol marker"
else
    fail "templates/protocol-verifier.md MISSING or no verifier marker"
fi

# --- N+2. Gate taxonomy in workflow skill ---
echo ""
echo "N+2. Gate taxonomy"

for keyword in "Gate Taxonomy" "pre-flight" "revision" "escalation" "abort"; do
    if grep -q "$keyword" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
        pass "workflow contains '$keyword'"
    else
        fail "workflow MISSING '$keyword'"
    fi
done

# --- N+3. Verify milestones in workflow skill ---
echo ""
echo "N+3. Verify milestone chain"

for ms in "verify:dispatched" "verify:passed" "verify:failed"; do
    if grep -q "$ms" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
        pass "workflow declares milestone '$ms'"
    else
        fail "workflow MISSING milestone '$ms'"
    fi
done

# --- N+4. New hook scripts present and executable ---
echo ""
echo "N+4. New hook scripts"

for hook in stall-check.sh parse-sentinel.sh parse-must-haves.sh spot-check-artifacts.sh; do
    if [[ -x "$PLUGIN_ROOT/hooks/$hook" ]]; then
        pass "hooks/$hook exists and is executable"
    else
        fail "hooks/$hook MISSING or not executable"
    fi
done
```

Renumber the section numbers (`N`, `N+1`, etc.) to the next integers after the existing last section — inspect the file and update accordingly.

- [ ] **Step 3: Run validate-config.sh**

Run: `bash tests/validate-config.sh`
Expected: all new checks pass. If any fail, fix the target file (usually a missing sentinel in a template) and re-run.

- [ ] **Step 4: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test(validate): assert sentinels, verifier template, gate taxonomy, new hooks

Adds 5 new check groups covering: protocol sentinels per template,
protocol-verifier.md presence + marker, Gate Taxonomy section in
workflow, verify:* milestones in workflow, new hook scripts executable.

Part of claude-workstation-fg0j."
```

---

## Task 20: Version bump to 2.8.0

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `skills/workflow/SKILL.md` (if not already bumped in Task 14)
- Modify: `skills/orchestrator/SKILL.md` (if not already bumped in Task 16)
- Modify: `skills/agent-roles/SKILL.md` (if not already bumped in Task 12)
- Modify: `skills/task-scaffolder/SKILL.md` (if not already bumped in Task 13)

- [ ] **Step 1: Check current version**

Run: `grep '"version"' .claude-plugin/plugin.json`
Expected: `"version": "2.7.1"`.

- [ ] **Step 2: Bump plugin.json and marketplace.json**

Run:
```bash
sed -i 's/"version": "2.7.1"/"version": "2.8.0"/g' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

- [ ] **Step 3: Ensure every skills/*/SKILL.md has version 2.8.0**

Run:
```bash
for f in skills/*/SKILL.md; do
    sed -i 's/^version: 2\.7\.1$/version: 2.8.0/' "$f"
done
grep '^version:' skills/*/SKILL.md
```
Expected: every file prints `version: 2.8.0`. If any still show 2.7.1, edit manually.

- [ ] **Step 4: Run validate-config.sh version check**

Run: `bash tests/validate-config.sh 2>&1 | grep -iE 'version|13b'`
Expected: version sync check passes, no "version X != plugin Y" errors.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/*/SKILL.md
git commit -m "chore: bump version to 2.8.0

Adds verification backbone (epic fg0j): protocol-verifier.md, gate
taxonomy, must_haves schema, count-only stall detection, H2 completion
sentinels, filesystem spot-check.

Part of claude-workstation-fg0j."
```

---

## Task 21: Final validation

**Files:**
- No code changes. Runs full suite.

- [ ] **Step 1: Run validate-config.sh**

Run: `bash tests/validate-config.sh`
Expected: all checks pass, `Failed: 0`.

- [ ] **Step 2: Run every new shell test**

Run:
```bash
for t in tests/test-stall-check.sh tests/test-parse-sentinel.sh \
         tests/test-parse-must-haves.sh tests/test-spot-check-artifacts.sh; do
    echo "=== $t ==="
    bash "$t" || { echo "FAILED: $t"; exit 1; }
done
echo "ALL NEW TESTS PASSED"
```
Expected: `ALL NEW TESTS PASSED`.

- [ ] **Step 3: Confirm every new file is committed**

Run:
```bash
git status
```
Expected: `working tree clean`.

- [ ] **Step 4: Close the epic**

After all sub-tasks for this plan are closed and Step 1–3 of this task pass, close the epic:

```bash
bd close claude-workstation-fg0j --reason="Verification backbone implemented and validated: protocol-verifier.md, 4 new hooks, gate taxonomy, must_haves schema, count-only stall detection, H2 sentinels + spot-check"
```

Note: this plan is a bootstrapping exercise — it builds the verifier backbone itself, so it cannot be run through the orchestrator that it implements. The executing agent (human or top-level Claude) closes the epic manually.

- [ ] **Step 5: Push**

```bash
git push
```

---

## Rollback Strategy

If this plan is partially implemented and needs to be rolled back:

1. `git log --oneline --grep="claude-workstation-fg0j"` lists every commit from this plan.
2. `git revert --no-edit <first-commit>..<last-commit>` reverts them in reverse order.
3. Delete the state directory: `rm -rf /tmp/claude-workstation` to clear stall-check state.
4. Re-run `bash tests/validate-config.sh` to confirm the repo is back to the 2.7.1 baseline.
5. Manually revert version bump if not covered: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and every `skills/*/SKILL.md` frontmatter back to `2.7.1`.
