# Feature Specification: Interactive Terminal Widgets

**Feature Branch**: `[feat-tui]`
**Status**: Implemented
**Input**: Existing source analysis: `src/tui.sh`, `docs/tui.md`, `test/tui.bats`, and `example/tui_ops.sh`

## Problem Statement *(mandatory)*

`cli.sh` covers everything a command line needs before it runs: parsing, help,
subcommands, completions. It stops where the script starts talking to a person.
A script that has to narrate slow work, show how far along it is, offer a list
of choices, or ask for confirmation is left hand-rolling ANSI escapes, raw key
reading, and a second code path for the case where there is no terminal at all.

That second path is where hand-rolled widgets fail. A menu written for a
terminal hangs or draws garbage in CI; a progress bar written with `\r` fills a
log file with thousands of part-drawn lines; a widget that prints to stdout
corrupts the value the script was computing. The result is that scripts either
avoid interactivity or become unusable unattended.

## Business Value *(mandatory)*

- Give scripts one interactive API that is correct both on a terminal and in a
  pipeline, so no script needs two code paths for the same question.
- Keep unattended runs readable: the same calls that draw a menu produce a
  numbered prompt, and the same calls that animate a bar produce periodic log
  lines.
- Protect script output: every widget writes to stderr, so a value on stdout
  stays usable in a command substitution.
- Complete the `cli.sh` story, so a script built on this library does not have
  to reach outside it for `dialog`, `whiptail`, `fzf`, or `gum`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Narrate slow work with a spinner (Priority: P1)

As a script author, I want to start a spinner, rename what it is doing as the
work moves on, and stop it with an outcome, so that a long operation made of
several steps does not look like a hang.

**Independent Test**: Start a spinner, change its message, and stop it with a
status, with no terminal attached; verify each message is logged once and the
status is returned to the caller.

**Acceptance Scenarios**:

1. **Given** no terminal, **When** a spinner is started, **Then** its message is
   logged once instead of animated
2. **Given** a running spinner, **When** its message is replaced, **Then** the
   next frame carries the new text without the animation restarting
3. **Given** a spinner is stopped with a status, **When** the call returns,
   **Then** it returns that same status, so the call both reports and propagates
   the outcome
4. **Given** a spinner is already running, **When** another is started, **Then**
   the second start is refused rather than leaving an orphaned animation

---

### User Story 2 - Show how far along a known amount of work is (Priority: P1)

As a script author, I want a progress bar driven from a loop, so that a run over
a known number of items shows its position, and so that the same loop produces a
readable log when nobody is watching.

**Independent Test**: Drive a bar over five units and verify the reported
percentages, that the closing frame appears once, and that a bar stopped early
still finishes at 100%.

**Acceptance Scenarios**:

1. **Given** a bar over a known total, **When** it is advanced, **Then** the
   drawn rendering redraws one line in place and the fallback logs a line
2. **Given** no terminal, **When** the bar is advanced many times, **Then**
   lines are logged on a percentage grid rather than once per update
3. **Given** a loop that ended before reaching the total, **When** the bar is
   stopped, **Then** it is filled to 100% first, so a reader is not left looking
   at a part-drawn bar for work that is over
4. **Given** a bar that already reached 100%, **When** it is stopped, **Then**
   the closing frame is not reported a second time

---

### User Story 3 - Offer a list of choices (Priority: P1)

As a script author, I want the user to pick one entry, or several, from a list,
so that a script can ask a real question instead of failing on a missing flag.

**Independent Test**: Answer a single-select and a multi-select from a redirect
and verify the chosen entries, their positions, and the handling of an answer
that names nothing.

**Acceptance Scenarios**:

1. **Given** a terminal, **When** a menu runs, **Then** it is drawn with a
   pointer and driven by arrow keys, `enter` and `esc`
2. **Given** no terminal, **When** a menu runs, **Then** it prints a numbered
   list and reads one line
3. **Given** an answer naming no entry, **When** it is read, **Then** the menu
   asks again rather than choosing something
4. **Given** a multi-select answered out of order, **When** it returns, **Then**
   the entries come back in menu order, each once
5. **Given** entries containing spaces, **When** a multi-select returns, **Then**
   each entry survives whole

---

### User Story 4 - Confirm a destructive step (Priority: P2)

As a script author, I want a confirmation that reads as a question with two
visible answers, so that a destructive step is harder to approve by reflex, and
so that the same call stays safe unattended.

**Independent Test**: Answer yes, no, and the default from a redirect; verify a
non-interactive shell refuses and `DYBATPHO_FORCE` approves.

**Acceptance Scenarios**:

1. **Given** a terminal, **When** the question runs, **Then** both answers are
   drawn with the default highlighted and `y`/`n` still answer directly
2. **Given** no terminal, **When** the question runs, **Then** it behaves
   exactly as `dybatpho::confirm`, including its refusal to guess
3. **Given** `DYBATPHO_FORCE`, **When** the question runs, **Then** it is
   answered yes without asking

---

### User Story 5 - Run the same script unattended (Priority: P1)

As a maintainer, I want every widget to work with no terminal at all, so that a
script written interactively can be scheduled in CI without being rewritten.

**Independent Test**: Run the whole example with its streams captured and verify
it exits zero, asks nothing, and writes nothing to stdout.

**Acceptance Scenarios**:

1. **Given** captured streams, **When** any widget runs, **Then** it takes the
   fallback rendering rather than drawing escape sequences into the capture
2. **Given** a menu that can neither ask nor fall back on a default, **When** it
   runs, **Then** it fails rather than choosing an entry silently
3. **Given** `DYBATPHO_TUI_DEFAULT`, **When** a menu cannot ask, **Then** it
   takes that answer

### Example Workflow

```bash
. dybatpho/init.sh --modules tui

local environment
dybatpho::tui_menu environment "Deploy where?" dev staging prod \
  || dybatpho::die "No environment chosen"

local -a components=()
dybatpho::tui_multi_menu components "Which components?" api worker scheduler

dybatpho::tui_confirm "Deploy ${components[*]} to ${environment}?" \
  || dybatpho::die "Cancelled"

dybatpho::tui_spinner_start "Resolving the release"
_resolve "${environment}"
dybatpho::tui_spinner_stop "$?" "Resolved"

dybatpho::tui_progress_start "Uploading" "${#components[@]}"
for component in "${components[@]}"; do
  _upload "${component}"
  dybatpho::tui_progress_step 1 "Uploading ${component}"
done
dybatpho::tui_progress_stop "Uploaded ${#components[@]} components"
```

## Edge Cases

- Streams are captured, piped, or redirected, in any combination.
- `DYBATPHO_TUI` forces the drawn rendering where there is no terminal, or the
  fallback where there is one.
- A menu is answered with a position outside the list, with a non-number, with
  several positions in single-select mode, or with nothing at all.
- A multi-select answer repeats a position or gives them out of order.
- Menu entries contain spaces.
- A progress bar is given a total of zero, a position past its total, or is
  stopped without having been started.
- A second spinner is started while one is running, or a message is sent when
  none is.
- `NO_COLOR` is set.
- The script is killed while a widget has the cursor hidden.
- A registered secret appears in a spinner message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST expose a predicate reporting whether widgets draw
  in place, and `DYBATPHO_TUI` MUST override its detection in both directions.
- **FR-002**: Detection MUST require a terminal on both stdin and stderr. Keys
  are read from the first and frames are written to the second, and drawing into
  a redirected stderr would corrupt whatever captured it.
- **FR-003**: Every widget MUST write to stderr only. Nothing a widget draws may
  reach stdout, including its closing banner.
- **FR-004**: Every widget MUST have a rendering that works with no terminal:
  menus become numbered prompts read through `dybatpho::prompt`, progress
  becomes log lines, spinners become a single log line per message.
- **FR-005**: The module MUST expose a bar renderer that returns the bar as
  text, independent of any progress state, so a script with its own progress
  model can reuse it.
- **FR-006**: The bar renderer MUST clamp a position past the total instead of
  overflowing, and MUST refuse a total below 1, a non-numeric argument, and a
  width below 1.
- **FR-007**: The spinner MUST support starting, renaming, and stopping as three
  separate calls, so it can bracket a region rather than wrap one command.
- **FR-008**: Starting a spinner while one is running MUST be refused.
- **FR-009**: Stopping a spinner MUST return the status it was given, so one
  call both reports and propagates an outcome.
- **FR-010**: The progress helpers MUST support an absolute move and a relative
  step, and MUST clamp a position past the total.
- **FR-011**: Advancing a progress bar with no terminal MUST report on a
  percentage grid set by `DYBATPHO_TUI_PROGRESS_STEP`, not once per update.
- **FR-012**: Stopping a progress bar MUST fill it to its total first, and MUST
  NOT report a percentage that the previous frame already reported.
- **FR-013**: Stopping a progress bar that was never started MUST succeed and do
  nothing, so it is safe to call from a trap.
- **FR-014**: A menu MUST return its answer through a named variable, never on
  stdout, because both renderings write to stderr and a command substitution
  around the call would swallow the menu it is meant to show.
- **FR-015**: A menu MUST refuse a result variable whose name is the library's
  own, and MUST refuse an empty entry list.
- **FR-016**: The numbered fallback MUST ask again when an answer names no
  entry, and when a single-select answer names more than one.
- **FR-017**: A multi-select MUST return entries in menu order with each entry
  once, whatever order the answer gave them in, so the drawn menu and the
  numbered fallback agree.
- **FR-018**: A multi-select MUST return its answer in an array, so entries
  containing spaces survive.
- **FR-019**: A menu that can neither ask nor read `DYBATPHO_TUI_DEFAULT` MUST
  fail rather than choose an entry.
- **FR-020**: `DYBATPHO_TUI_DEFAULT` MUST select the entry a drawn menu starts
  on, the entries a drawn multi-select starts with toggled, and the answer used
  when the menu cannot ask.
- **FR-021**: The confirmation MUST honor `DYBATPHO_FORCE`, and off a terminal
  MUST behave exactly as `dybatpho::confirm`, including its refusal to guess in
  an unattended shell.
- **FR-022**: A drawn widget MUST hide the cursor while it draws and restore it
  on exit, interrupt, and termination, so a killed script does not leave the
  terminal without a cursor.
- **FR-023**: Colors MUST be omitted when `NO_COLOR` is set.
- **FR-024**: A spinner message MUST be masked through the registered-secret
  hook before it is drawn or logged.
- **FR-025**: The drawn menu MUST scroll rather than overflow when the list is
  longer than `DYBATPHO_TUI_MENU_HEIGHT`, keeping the highlighted entry visible.

### Key Entities *(include if feature involves data)*

- **Menu Entry**: One choice, an arbitrary string that may contain spaces.
- **Entry Position**: The 1-based position of an entry, which is what the
  numbered fallback reads and what `DYBATPHO_TUI_INDEX` and
  `DYBATPHO_TUI_INDEXES` report.
- **Progress State**: The label, total, and current position of the running bar,
  plus the moment it started, from which the ETA is derived.
- **Key Name**: A keypress normalized to a stable name (`up`, `enter`, `space`,
  `escape`, `eof`, `char:<c>`), so the menu loops never handle escape sequences.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script using the interactive API runs unchanged and unattended
  in CI, with no keystroke and no hang.
- **SC-002**: A value a script prints to stdout is unaffected by any widget
  drawn beside it.
- **SC-003**: A loop of a thousand items produces a bounded number of log lines
  rather than one per item.
- **SC-004**: Scripts no longer need `dialog`, `whiptail`, or a hand-rolled
  `read -rsn1` loop for a menu or a confirmation.

## Integration Tests *(mandatory)*

- **IT-001**: `DYBATPHO_TUI` forces the drawn and fallback renderings, and
  `auto` reports no terminal when the streams are captured.
- **IT-002**: The bar renders proportionally, at both ends of its range, clamps
  a position past the total, and honors the configured characters and width.
- **IT-003**: The bar refuses a total of zero and arguments that are not whole
  numbers.
- **IT-004**: A spinner logs its start and its renamed steps with no terminal,
  and refuses a second start over the first.
- **IT-005**: Stopping a spinner returns the status it was given, is quiet
  without a message, and keeps its banner off stdout.
- **IT-006**: A progress bar reports on a percentage grid, reports its closing
  frame once, and finishes at 100% when the loop ended early.
- **IT-007**: A progress bar refuses a total below 1, refuses an update with no
  bar running, and does nothing when stopped without having been started.
- **IT-008**: A menu returns the chosen entry and its position, asks again after
  an answer naming no entry, and refuses more than one answer.
- **IT-009**: A menu takes `DYBATPHO_TUI_DEFAULT` when nothing can be read, and
  fails when there is neither an answer nor a default.
- **IT-010**: A menu refuses a reserved result variable and an empty entry list.
- **IT-011**: A multi-select returns entries in menu order with each entry once
  whatever order they were given in, keeps entries containing spaces intact,
  honors preselected defaults, and ignores positions outside the menu.
- **IT-012**: The confirmation answers yes, no, and the default off a terminal,
  refuses in an unattended shell, obeys `DYBATPHO_FORCE`, and keeps stdout
  clean.

## Acceptance Criteria *(mandatory)*

- Every public function is documented in `docs/tui.md` and exercised by
  `test/tui.bats`.
- `example/tui_ops.sh` runs unattended, offline, and leaves the working tree
  untouched.
- The module is registered in `init.sh` with its dependency edges on `cli` and
  `safety`.
- The drawn rendering is exercised against a real pseudo-terminal before the
  work is reported as done, because no part of it is reachable from a suite
  whose streams are captured.
