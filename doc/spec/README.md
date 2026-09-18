# dybatpho Spec Kit Index

This directory contains GitHub Spec Kit style specifications reverse-engineered from the current `dybatpho` codebase.

`README.md` is an index; every feature specification listed below follows the
same section order: Problem Statement, Business Value, User Scenarios &
Testing, Edge Cases, Requirements, Key Entities, Success Criteria, Integration
Tests, and Acceptance Criteria.

The goal is to capture the current product behavior of the library in a form that is easier to review, evolve, and use as a baseline for future `/speckit.specify`, `/speckit.plan`, and `/speckit.tasks` workflows.

## Scope

- `project.md` describes the full Bash utility library as a product.
- Every `src/*.sh` module has a matching spec file. This mapping is mandatory:
  adding a module without adding its spec is an incomplete change.
- `init.md` describes repository bootstrap and module loading behavior.
- Recent helper additions are folded into the existing module specs here rather than tracked in a separate spec tree.

## Spec Files

- `project.md`
- `init.md`
- `array.md`
- `string.md`
- `logging.md`
- `helpers.md`
- `process.md`
- `network.md`
- `file.md`
- `cli.md`
- `os.md`
- `config.md`
- `lock.md`
- `archive.md`
- `git.md`
- `table.md`
- `text.md`
- `testing.md`
- `json.md`
- `date.md`
- `semver.md`
- `notification.md`
- `secret.md`
- `safety.md`
- `metrics.md`
- `ai.md`
- `agent.md`

## Source Mapping

- `init.sh` -> `init.md`
- `src/array.sh` -> `array.md`
- `src/string.sh` -> `string.md`
- `src/logging.sh` -> `logging.md`
- `src/helpers.sh` -> `helpers.md`
- `src/process.sh` -> `process.md`
- `src/network.sh` -> `network.md`
- `src/file.sh` -> `file.md`
- `src/cli.sh` -> `cli.md`
- `src/os.sh` -> `os.md`
- `src/config.sh` -> `config.md`
- `src/lock.sh` -> `lock.md`
- `src/archive.sh` -> `archive.md`
- `src/git.sh` -> `git.md`
- `src/table.sh` -> `table.md`
- `src/text.sh` -> `text.md`
- `src/json.sh` -> `json.md`
- `src/date.sh` -> `date.md`
- `src/semver.sh` -> `semver.md`
- `src/notification.sh` -> `notification.md`
- `src/secret.sh` -> `secret.md`
- `src/testing.sh` -> `testing.md`
- `src/safety.sh` -> `safety.md`
- `src/metrics.sh` -> `metrics.md`
- `src/ai.sh` -> `ai.md`
- `src/agent.sh` -> `agent.md`

## Notes

- These specs describe the current observable behavior of the existing codebase, not a proposed rewrite.
- They intentionally stay focused on user-visible outcomes and contracts rather than line-by-line implementation details.
- `doc/spec/` is the canonical spec location for the repository.
- Keep the Spec Files and Source Mapping lists above in sync with `src/`. The
  check is `comm -23 <(ls src/*.sh | xargs -n1 basename | sed 's/\.sh$/.md/' | sort) <(ls doc/spec/*.md | xargs -n1 basename | sort)`,
  which must print nothing.
