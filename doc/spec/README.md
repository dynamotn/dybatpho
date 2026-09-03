# dybatpho Spec Kit Index

This directory contains GitHub Spec Kit style specifications reverse-engineered from the current `dybatpho` codebase.

`README.md` is an index; every feature specification listed below follows the
same section order: Problem Statement, Business Value, User Scenarios &
Testing, Edge Cases, Requirements, Key Entities, Success Criteria, Integration
Tests, and Acceptance Criteria.

The goal is to capture the current product behavior of the library in a form that is easier to review, evolve, and use as a baseline for future `/speckit.specify`, `/speckit.plan`, and `/speckit.tasks` workflows.

## Scope

- `project.md` describes the full Bash utility library as a product.
- Each `src/*.sh` module has a matching spec file, including `semver.md` and
  `notification.md`.
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
- `archive.md`
- `git.md`
- `table.md`
- `text.md`
- `json.md`
- `date.md`
- `semver.md`
- `notification.md`

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
- `src/archive.sh` -> `archive.md`
- `src/git.sh` -> `git.md`
- `src/table.sh` -> `table.md`
- `src/text.sh` -> `text.md`
- `src/json.sh` -> `json.md`
- `src/date.sh` -> `date.md`
- `src/semver.sh` -> `semver.md`
- `src/notification.sh` -> `notification.md`

## Notes

- These specs describe the current observable behavior of the existing codebase, not a proposed rewrite.
- They intentionally stay focused on user-visible outcomes and contracts rather than line-by-line implementation details.
- `doc/spec/` is the canonical spec location for the repository.
