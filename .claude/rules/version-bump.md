# Version Bump Rule

When committing changes to this plugin repository, bump the version in ALL of these locations:

| File | Field | Format |
|------|-------|--------|
| `.claude-plugin/plugin.json` | `"version"` | `"X.Y.Z"` |
| `.claude-plugin/marketplace.json` | `"version"` (inside plugins array) | `"X.Y.Z"` |
| `skills/*/SKILL.md` | `version:` (frontmatter, line 3) | `X.Y.Z` |

All locations MUST have the same version string. The test suite (`tests/validate-config.sh`, check 13b) enforces this and will fail on mismatch.

## When to Bump

- **Patch** (Z): bug fixes, dead code cleanup, doc updates, test changes
- **Minor** (Y): new skills, new hooks, new templates, behavioral changes
- **Major** (X): breaking changes to hook contracts or skill interfaces

## How

After all code changes are done and before committing:

```bash
# Check current version
grep '"version"' .claude-plugin/plugin.json

# Update all locations (replace OLD with NEW)
sed -i 's/"version": "OLD"/"version": "NEW"/g' .claude-plugin/plugin.json .claude-plugin/marketplace.json
for f in skills/*/SKILL.md; do sed -i "s/^version: OLD/version: NEW/" "$f"; done

# Verify sync
bash tests/validate-config.sh 2>&1 | grep -E "version|13b"
```

## Enforcement

Forgetting any location causes `validate-config.sh` to fail with:
```
skill <name> version X.Y.Z != plugin A.B.C
```
