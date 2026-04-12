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
