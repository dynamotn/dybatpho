# Feature Specification: Privilege Escalation for a Run

**Feature Branch**: `[spec-privilege]`
**Status**: Implemented
**Input**: Existing source analysis: `src/privilege.sh`, `docs/privilege.md`, `test/privilege.bats`, and `example/privilege_ops.sh`

## Problem Statement *(mandatory)*

`pkg.sh` can put `sudo` in front of one command. A script that runs twenty of them over several minutes needs something the prefix cannot give: the password asked for once at the start, the ticket kept alive while the work runs, and no child process able to stop and ask for it again halfway through. `dyshellint` carries a rule against calling `sudo` from a script (`BSG035`), and in the dotfiles repository that consumes this library it is disabled seven times across three files — the rule is right and the code had nowhere else to go. The parts a script author does not think of until it breaks are the background refresh, tying that refresh to the parent process, and stopping children from prompting at all.

## Business Value *(mandatory)*

- One password prompt at a known moment, rather than one arriving mid-run.
- A long run does not fail because the ticket expired halfway through it.
- A child process cannot hang the run asking for a password nothing can display.
- A script run from cron fails immediately instead of blocking on a prompt no one will answer.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask once, at a moment of my choosing (Priority: P1)

As a script author, I want to authenticate up front so that the password prompt does not interrupt work already in progress.

**Independent Test**: Acquire with no cached ticket and verify the prompt happens once, then that later elevated commands need none.

**Acceptance Scenarios**:

1. **Given** elevation is needed and no ticket is cached, **When** the escalation is acquired, **Then** the caller is prompted once
2. **Given** a ticket is already cached, **When** the escalation is acquired, **Then** nothing prompts
3. **Given** elevation is not needed, **When** the escalation is acquired, **Then** nothing happens at all

---

### User Story 2 - Survive a long run (Priority: P1)

As an operator, I want the ticket refreshed while the work runs, so a long install does not stop to ask again.

**Independent Test**: Acquire, verify a refresher is running, release, and verify it is gone.

**Acceptance Scenarios**:

1. **Given** an acquired escalation, **When** the run continues, **Then** a background refresher holds the ticket
2. **Given** the escalation is released, **When** the refresher is checked, **Then** it has stopped
3. **Given** the script dies without releasing, **When** the process ends, **Then** the refresher ends with it

---

### User Story 3 - Keep children from prompting (Priority: P1)

As an operator, I want child processes unable to ask for a password, so that a run never hangs on a prompt nothing is in a position to show.

**Independent Test**: Acquire with the shield, remove the cached ticket, and verify a child fails rather than prompting.

**Acceptance Scenarios**:

1. **Given** the shield is requested, **When** a child invokes the escalation command, **Then** it runs non-interactively
2. **Given** no ticket is cached, **When** a shielded child needs one, **Then** it fails rather than prompting
3. **Given** the escalation is released, **When** the path is checked, **Then** the shield is gone from it

---

### User Story 4 - Fail where nobody can answer (Priority: P2)

As an operator running a script from cron, I want it to fail immediately when a password would be required, rather than blocking forever.

**Independent Test**: Acquire with no ticket and no terminal, and verify it fails with a message.

**Acceptance Scenarios**:

1. **Given** no cached ticket and no terminal, **When** the escalation is acquired, **Then** it fails and says why
2. **Given** a cached ticket and no terminal, **When** the escalation is acquired, **Then** it succeeds

### Example Workflow

```bash
. dybatpho/init.sh --modules privilege

# A full-screen caller gives the terminal back around the prompt.
DYBATPHO_PRIVILEGE_SUSPEND_HOOK=hand_over
dybatpho::privilege_acquire --shield || dybatpho::die "Cannot elevate"

dybatpho::privilege_run -- apt-get update
dybatpho::privilege_run -- apt-get install -y the-tools
dybatpho::privilege_run -- systemctl enable the-service

dybatpho::privilege_release
```

## Edge Cases

- Already root, no escalation command installed, or the caller turned elevation off.
- `doas` rather than `sudo`, which has no way to be asked about a cached ticket.
- No terminal, with and without a cached ticket.
- Release called twice, or without an acquire.
- `DRY_RUN` set.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST detect an escalation command, preferring `sudo` then `doas`, and MUST accept an explicit override.
- **FR-002**: Elevation MUST be reported as unnecessary when the caller is root, when no escalation command exists, or when the caller turned it off.
- **FR-003**: Acquiring MUST do nothing when elevation is not needed, so a caller may ask unconditionally.
- **FR-004**: Acquiring MUST NOT prompt when a ticket is already cached.
- **FR-005**: Acquiring MUST fail rather than block when a prompt is required and the session has no terminal.
- **FR-006**: A caller-supplied hook MUST be called before and after a prompt, so a full-screen application can hand the terminal over.
- **FR-007**: Acquiring MUST refresh the ticket in the background for as long as the process lives, unless the caller declines it.
- **FR-008**: The refresher MUST watch the parent process rather than wait to be signalled, so it cannot outlive a script that was killed.
- **FR-009**: The refresh MUST be attempted only for an escalation command that supports it; `doas` has no equivalent and MUST NOT be assumed to.
- **FR-010**: `--shield` MUST put a non-interactive escalation command first on `PATH`, so no child can prompt.
- **FR-011**: Releasing MUST stop the refresher and remove the shield from `PATH`, and MUST be safe to call when nothing was acquired.
- **FR-012**: Teardown MUST also run on exit and on `HUP`, `INT` and `TERM`, registered only after the escalation was actually taken.
- **FR-013**: Running one command MUST read the same whether or not elevation is needed.
- **FR-014**: `DRY_RUN` MUST report what would happen and change nothing.
- **FR-015**: An unknown option MUST stop the script.

### Key Entities *(include if feature involves data)*

- **Escalation command**: `sudo`, `doas`, or whatever the caller named.
- **Ticket**: The cached authentication the escalation command keeps.
- **Refresher**: The background process holding the ticket open.
- **Shield**: A non-interactive escalation command placed first on `PATH`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A multi-step run asks for a password once, at the start.
- **SC-002**: A long run does not stop because the ticket expired.
- **SC-003**: No child process can hang a run with a prompt.
- **SC-004**: A non-interactive run fails quickly instead of blocking.

## Integration Tests *(mandatory)*

- **IT-001**: Detect `sudo`, fall back to `doas`, honour an override, and report when neither exists.
- **IT-002**: Report no elevation needed when root, when turned off, and when no command exists.
- **IT-003**: Run one command elevated, and plainly when elevation is not needed.
- **IT-004**: Report under `DRY_RUN` without running, for both a command and an acquire.
- **IT-005**: Reject a missing separator, a missing command, and an unknown option.
- **IT-006**: Do nothing on acquire when elevation is not needed.
- **IT-007**: Fail on acquire with no ticket and no terminal; succeed with a ticket and no terminal.
- **IT-008**: Call the hand-over hook with `suspend` and then `resume` around the prompt.
- **IT-009**: Shield a child so it runs non-interactively and fails instead of prompting.
- **IT-010**: Start a refresher on acquire and stop it on release.
- **IT-011**: Remove the shield from `PATH` on release, and release twice harmlessly.

## Acceptance Criteria *(mandatory)*

1. This module answers whether a command *can* run; whether it *should* is `safety.sh`'s question, and the two are independent.
2. The escalation command is stubbed in tests the way `curl` already is for `network`, so nothing here needs a real password.
3. `BSG035` — the rule against calling `sudo` from a script — is answered here once, rather than disabled at every call site that needs it.
