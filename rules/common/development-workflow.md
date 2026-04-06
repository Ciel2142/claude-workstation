# Development Workflow

> The full development flow (task creation → brainstorming → planning → TDD → review → verification → close) is defined in `unified-workflow.md` and available via `/help`.

## Research & Reuse (mandatory before any new implementation)

- **GitHub code search first:** Run `gh search repos` and `gh search code` to find existing implementations, templates, and patterns before writing anything new.
- **Library docs second:** Use Context7 or primary vendor docs to confirm API behavior, package usage, and version-specific details before implementing.
- **Exa only when the first two are insufficient:** Use Exa for broader web research or discovery after GitHub search and primary docs.
- **Check package registries:** Search npm, PyPI, crates.io, and other registries before writing utility code. Prefer battle-tested libraries over hand-rolled solutions.
- **Search for adaptable implementations:** Look for open-source projects that solve 80%+ of the problem and can be forked, ported, or wrapped.
- Prefer adopting or porting a proven approach over writing net-new code when it meets the requirement.
