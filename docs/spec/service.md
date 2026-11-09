# Feature Specification: Service Management Across Init Systems

**Feature Branch**: `[feature-service]`
**Status**: Draft
**Input**: `scripts/lib/init_system.sh` and `scripts/test/init_system.bats` in the dotfiles repository, which wrap systemd, OpenRC, launchd and runit for `dytoy`; `lib/dyai_node.sh` in `dyai`, which installs and reloads its node daemon on systemd and launchd by hand; `src/pkg.sh`, whose detection and printable-command contract this module follows

## Problem Statement *(mandatory)*

A script that installs something long-running -- a sync daemon, an agent, a socket -- has to enable it on whatever init system the machine runs. Each one has its own tool and vocabulary: `systemctl --user enable --now`, `rc-update add` then `rc-service start`, `launchctl bootout` then `bootstrap` in the `gui/<uid>` domain, `sv-enable` then `sv up`. Each has its own way of not being there: no `systemctl` at all, a `systemctl` with no user manager behind it (a container, a chroot, a machine booted by another init), a `launchctl` run over SSH with no GUI session. Today the dotfiles and `dyai` each carry a copy of this logic, with different edge cases covered in each.

## Business Value *(mandatory)*

- Enable, start, stop and inspect a service with one call, whichever init system is there.
- Install or update a unit file and have it take effect, including the reload or re-bootstrap each manager needs.
- Tell a missing manager from a present one that cannot act, and skip with a warning rather than fail a whole bootstrap on a container.
- Print the exact command before it runs, so a change to the system can be reviewed or dry-run.
- Replace the two hand-rolled copies in the dotfiles and `dyai`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know which init system is here (Priority: P1)

As a script author, I want to know which service manager this machine runs, and whether it can act for my user or for the system, so I can decide what to install.

**Independent Test**: Stub `uname` and the manager binaries, then check the reported manager on systemd, OpenRC, runit, launchd and a machine with none; stub `systemctl --user show-environment` failing and see the user scope reported unavailable.

**Acceptance Scenarios**:

1. **Given** `/run/systemd/system` on Linux, **When** `service_manager` runs, **Then** it prints `systemd`; with `rc-service` and no running systemd, `openrc`; with `sv-enable` (Termux), `runit`; on Darwin with `launchctl`, `launchd`; with none, it prints nothing and returns 1
2. **Given** `DYBATPHO_SERVICE_MANAGER=openrc`, **When** anything runs, **Then** OpenRC is used without probing
3. **Given** systemd whose user manager does not answer `show-environment`, **When** `service_manager_available --user` runs, **Then** it returns 1; **Given** `systemctl is-system-running` reports `offline`, **Then** the system scope is unavailable too
4. **Given** a container (`/.dockerenv`, or `docker` in `/proc/self/cgroup`), **When** `service_manager_available` runs, **Then** the system scope is unavailable

---

### User Story 2 - Enable and control a service (Priority: P1)

As a script author, I want to enable, disable, start, stop and restart a service, for my user or for the system, with one call per action.

**Independent Test**: Stub each manager's tool and assert the exact command each action runs, user and system, and that a system action goes through `dybatpho::privilege_run`.

**Acceptance Scenarios**:

1. **Given** systemd, **When** `service_enable foo --user` runs, **Then** it runs `systemctl --user enable --now foo`; without `--user`, `systemctl enable --now foo` through `privilege_run`
2. **Given** OpenRC, **When** `service_enable foo` runs, **Then** it runs `rc-update add foo default` and `rc-service foo start`, each elevated; with `--user`, `rc-update --user add foo default` and `rc-service --user foo start`
3. **Given** launchd and a loaded job, **When** `service_enable foo --user` runs, **Then** it runs `launchctl enable gui/<uid>/foo` and `launchctl kickstart gui/<uid>/foo`; without `--user`, the same in `system/`, elevated. A job that is not loaded is loaded by `service_install`, which has the plist.
4. **Given** runit (Termux), **When** `service_enable foo` runs, **Then** it runs `sv-enable foo` and `sv up foo`, never elevated: Termux has one user and no root, so `--user` and the system scope are the same there
5. **Given** any manager, **When** `service_disable`, `service_start`, `service_stop` or `service_restart` runs, **Then** the matching command of that manager runs, per the table in FR-006
6. **Given** `DYBATPHO_DRY_RUN=true`, **When** an action runs, **Then** the command is printed and not run

---

### User Story 3 - Ask about a service (Priority: P2)

As a script author, I want to know whether a service is enabled and whether it is running.

**Acceptance Scenarios**:

1. **Given** systemd, **When** `service_is_enabled foo --user` runs, **Then** it returns `systemctl --user is-enabled foo`'s answer; `service_is_active` likewise with `is-active`
2. **Given** launchd, **When** `service_is_active foo --user` runs, **Then** it returns 0 when `launchctl print gui/<uid>/foo` succeeds
3. **Given** OpenRC, **When** `service_is_active foo` runs, **Then** it returns `rc-service foo status`'s answer, and `service_is_enabled` checks `rc-update show default`
4. **Given** runit, **When** `service_is_active foo` runs, **Then** it reads `sv status foo` for `run:`

---

### User Story 4 - Install a unit file (Priority: P1)

As a script author, I want to put a unit file or plist where the manager reads it and have the manager pick it up, whether it is new or changed.

**Independent Test**: With stubbed tools, install a unit into a temporary home and assert the destination path, the reload, and the enable; install it again unchanged and see no reload; change it and see a reload and restart.

**Acceptance Scenarios**:

1. **Given** systemd and `--user`, **When** `service_install foo.service` runs, **Then** the file lands in `${XDG_CONFIG_HOME:-~/.config}/systemd/user/foo.service`, `systemctl --user daemon-reload` runs, then `service_enable foo.service --user`
2. **Given** systemd without `--user`, **When** it runs, **Then** the file lands in `/etc/systemd/system/` through `privilege_run`, and the reload and enable are elevated
3. **Given** launchd and `--user`, **When** `service_install dev.example.foo.plist` runs, **Then** the file lands in `~/Library/LaunchAgents/`, `launchctl enable gui/<uid>/<label>` runs first (a label left disabled by an earlier `service_disable` makes `bootstrap` refuse), then `launchctl bootout gui/<uid> <plist>` with its failure ignored, then `launchctl bootstrap gui/<uid> <plist>`; the label is the plist's basename without `.plist`
4. **Given** the destination already holds the same content, **When** it runs, **Then** nothing is written and no reload happens, but the enable still runs
5. **Given** the destination holds different content, **When** it runs, **Then** the file is replaced, the manager reloads, and a running service is restarted
6. **Given** OpenRC or runit, **When** `service_install` runs, **Then** the script stops: those managers take an init script, not a unit file

---

### User Story 5 - Skip gracefully where nothing can act (Priority: P1)

As a bootstrap author, I want a machine without a usable manager -- a container, a CI runner, SSH into a Mac with no GUI session -- to log what was skipped and carry on.

**Acceptance Scenarios**:

1. **Given** no manager, **When** any action runs, **Then** it warns naming the service and returns 0
2. **Given** a manager whose scope is unavailable, **When** an action runs, **Then** it warns and returns 0
3. **Given** `DYBATPHO_SERVICE_STRICT=true`, **When** the same happens, **Then** it returns 1 instead

### Example Workflow

```bash
. init.sh --modules service

# Install a user unit and have it running, on systemd or launchd alike.
dybatpho::service_install "${HOME}/.config/dyai/dyai-node.service" --user

# A system service, elevated as needed; skipped with a warning in a container.
dybatpho::service_enable sshd

# Decide from the answer.
if dybatpho::service_is_active rclone --user; then
  dybatpho::info "rclone is running"
fi

# Preview before changing the system.
DYBATPHO_DRY_RUN=true dybatpho::service_restart nginx
```

## Edge Cases

- `systemctl` exists but no user manager answers (`show-environment` fails), or the system is `offline` (a chroot).
- The script runs in a container with systemd's binaries installed.
- launchd over SSH: no `gui/<uid>` domain is reachable.
- A unit name with or without its `.service` suffix; a plist named by path or by label.
- The unit file already exists and is identical; it exists and differs; the destination directory does not exist.
- A system action when neither `sudo` nor `doas` is available.
- `DYBATPHO_DRY_RUN` set while asking a question (`is_active`): the question still runs, only changes are suppressed.
- `DYBATPHO_SERVICE_MANAGER` naming something the module does not know.
- Both `systemctl` and `rc-service` installed (Gentoo): the one that booted the machine wins, told by `/run/systemd/system`.
- runit outside Termux (Void, Artix): enabling is a symlink that needs root and has no `sv-enable`; not supported, so `sv` alone is not detected as a manager.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `service_manager` MUST print `systemd`, `openrc`, `runit` or `launchd`, and MUST return 1 with no output when none is found. On Linux it MUST probe in this order: `systemd` when `/run/systemd/system` is a directory (the binary alone is not enough: a Gentoo host with OpenRC booted carries `systemctl` too); `openrc` when `rc-service` exists; `runit` when `sv-enable` exists (Termux). On Darwin, `launchd` when `launchctl` exists. `DYBATPHO_SERVICE_MANAGER` MUST override the probe, and an unknown value MUST stop the script.
- **FR-002**: Every action MUST take the service name first and an optional `--user` flag, and MUST act on the system scope without it.
- **FR-003**: `service_manager_available [--user]` MUST return 0 only when the manager is present and can act in that scope: for systemd, `systemctl --user show-environment` succeeds (user) or `systemctl is-system-running` answers anything but `offline` and the process is not in a container (system); for launchd, `launchctl print gui/<uid>` succeeds (user); for OpenRC, `rc-update --user show` succeeds (user: it needs OpenRC 0.60 and a user instance started by `openrc --user`) or the process is not in a container (system); for runit, `sv-enable` exists.
- **FR-004**: A system-scope change MUST run through `dybatpho::privilege_run`, and a user-scope change MUST NOT. On runit (Termux) there is one scope and no root: nothing is elevated, and `--user` changes nothing.
- **FR-005**: `service_command <action> <name> [--user]` MUST print the commands an action would run, one shell-quoted command per line (`printf '%q '`), the elevation prefix included where FR-004 elevates, as `pkg_install_command` does; every action MUST run exactly those commands in that order, and MUST honour `DYBATPHO_DRY_RUN` the way `privilege_run` does.
- **FR-006**: The per-manager commands MUST be:

  | action | systemd | openrc | runit | launchd |
  |---|---|---|---|---|
  | enable | `systemctl [--user] enable --now NAME` | `rc-update [--user] add NAME default`; `rc-service [--user] NAME start` | `sv-enable NAME`; `sv up NAME` | `launchctl enable DOMAIN/NAME`; `launchctl kickstart DOMAIN/NAME` |
  | disable | `systemctl [--user] disable --now NAME` | `rc-service [--user] NAME stop`; `rc-update [--user] del NAME default` | `sv down NAME`; `sv-disable NAME` | `launchctl disable DOMAIN/NAME`; `launchctl bootout DOMAIN/NAME` |
  | start | `systemctl [--user] start NAME` | `rc-service [--user] NAME start` | `sv up NAME` | `launchctl kickstart DOMAIN/NAME` |
  | stop | `systemctl [--user] stop NAME` | `rc-service [--user] NAME stop` | `sv down NAME` | `launchctl bootout DOMAIN/NAME` (a `kill` would be undone by `KeepAlive`) |
  | restart | `systemctl [--user] restart NAME` | `rc-service [--user] NAME restart` | `sv restart NAME` | `launchctl kickstart -k DOMAIN/NAME` |
  | is-active | `systemctl [--user] is-active NAME` | `rc-service [--user] NAME status` | `sv status NAME` starts with `run: NAME:` (a `fail:` or `warning:` line is not active) | `launchctl print DOMAIN/NAME` prints `state = running` or a `pid =` line (loaded alone is not active) |
  | is-enabled | `systemctl [--user] is-enabled NAME` | `rc-update [--user] show default` lists NAME | `$PREFIX/var/service/NAME/down` absent | `launchctl print-disabled DOMAIN` has no line for NAME ending in `disabled` or `true` (both spellings exist; an unlisted label is enabled) |
  | reload-manager | `systemctl [--user] daemon-reload` | nothing | nothing | nothing |

  where DOMAIN is `gui/<uid>` with `--user` and `system` without.
- **FR-007**: `service_install <file> [--user] [--name NAME]` MUST copy the file to the manager's unit directory -- systemd: `${XDG_CONFIG_HOME:-~/.config}/systemd/user` or `/etc/systemd/system`; launchd: `~/Library/LaunchAgents` or `/Library/LaunchDaemons` -- creating it when missing, MUST compare contents first and skip the write and the reload when identical, MUST reload the manager after a write (systemd `daemon-reload`; launchd `enable` then `bootout` ignoring failure then `bootstrap`), MUST restart the service after a change when it was active, and MUST then enable it. A system file MUST be written with `install -m 644` and, on launchd, owned by `root:wheel`, since `bootstrap` refuses a daemon plist writable by others. The service name defaults to the file's basename, without `.plist` on launchd. On OpenRC and runit it MUST stop the script.
- **FR-008**: `service_uninstall <name> [--user]` MUST disable the service, remove its unit file from the directory of FR-007 when present, and reload the manager.
- **FR-009**: When no manager is found, or the scope is unavailable, every change MUST `dybatpho::warn` naming the service and return 0, or return 1 when `DYBATPHO_SERVICE_STRICT` is true-like; a question (`is_active`, `is_enabled`) MUST return 1 silently.
- **FR-010**: A question MUST run even under `DYBATPHO_DRY_RUN`.
- **FR-011**: The module depends on `privilege` and `file`, which is allowed because it is `experimental` itself (only a stable module may not depend on an experimental one).

### Key Entities *(include if feature involves data)*

- **Manager**: One of `systemd`, `openrc`, `runit`, `launchd`.
- **Scope**: `user` or `system`; decides the tool's flags, the domain, the unit directory and whether to elevate.
- **Unit file**: The systemd unit or launchd plist a service is defined by.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `dytoy` and `dyai node` enable their services through this module with no manager-specific code of their own.
- **SC-002**: A bootstrap run in a container or on a CI runner completes with warnings, never with a failure from a missing init system.
- **SC-003**: Every command the module can run is printable before it runs.

## Integration Tests *(mandatory)*

Tests stub the manager tools, as `test/pkg.bats` does: no test enables a real service. The one thing tested for real is the unit-file installation into a temporary home, with the reload stubbed.

- **IT-001**: Detect each manager from stubbed binaries and `uname`, and nothing when none is there; honour and refuse `DYBATPHO_SERVICE_MANAGER`.
- **IT-002**: Report the user scope unavailable when `show-environment` fails, and the system scope unavailable when `is-system-running` says `offline` or `/.dockerenv` exists.
- **IT-003**: For every action and manager in FR-006, `service_command` prints the table's command, user and system.
- **IT-004**: A system action calls `privilege_run`; a user action does not.
- **IT-005**: `DYBATPHO_DRY_RUN` prints and skips an action, and leaves a question running.
- **IT-006**: Install a systemd user unit into a temporary `XDG_CONFIG_HOME`: the file lands, `daemon-reload` and `enable --now` run; a second identical install writes nothing and reloads nothing; a changed install reloads and restarts when active.
- **IT-007**: Install a launchd agent into a temporary `HOME`: `bootout` then `bootstrap` in `gui/<uid>`.
- **IT-008**: `service_install` stops on OpenRC and runit.
- **IT-009**: `service_uninstall` disables, removes the file and reloads.
- **IT-010**: Without a manager, a change warns and returns 0, returns 1 under `DYBATPHO_SERVICE_STRICT`, and a question returns 1 silently.
- **IT-011**: Names with and without `.service`; a plist named by path.

## Acceptance Criteria *(mandatory)*

1. One call enables a service on systemd, OpenRC, runit and launchd, in either scope.
2. Every change is printable before it runs and respects dry-run.
3. A machine that cannot act is skipped with a warning, not failed.
4. `scripts/lib/init_system.sh` in the dotfiles and the service code in `dyai_node.sh` can be deleted in favour of this module.

## Design Notes *(not part of the contract)*

**Decided with the owner**

- On launchd, `service_enable` and `service_start` act on a loaded job only; a job unloaded by `stop` or `disable` is loaded again by `service_install`, which has the plist. The alternative, looking the plist up by label, was declined to keep the interface the same on every manager.
- macOS 11 and later: `bootstrap`, `bootout` and `kickstart` are assumed, and both spellings of `print-disabled` (`=> disabled` and `=> true`) are read.

**Decided by the designer**

- Named `service`, after what the caller handles, rather than `init` or `systemd`.
- Follows `pkg`: detection with an override variable, a printable command, stubbed-tool tests. Issue #10's objection -- that a stub tests the command line, not the operation -- is accepted here knowingly: a real init system cannot be driven in CI, and the command line *is* the contract (FR-006), reviewed per manager.
- launchd `enable`/`kickstart` is used for a service already loaded; `service_install` is what loads a new plist (`bootstrap`). This matches how `dyai_node.sh` and `init_system.sh` already behave.
- The macOS "login item" and `brew services` paths of `init_system.sh` are left out: the first is an application, not a service; the second is Homebrew's own wrapper over launchd.
- Termux's `sv` is called `runit` because that is what it is; only Termux is supported, detected by its `sv-enable` helper. runit on Void or Artix enables by a root-owned symlink and is left out.
- launchd `stop` and `disable` unload the job (`bootout`): a `kill` is undone by `KeepAlive`, and `disable` alone leaves the job running. `enable` and `start` therefore work on a loaded job only; loading is `service_install`'s job, since it has the plist.
- launchd `is-active` means running, read from `launchctl print`, not merely loaded.
- `service_start` on launchd and a job that is not loaded fails with launchd's own error, and the module's message points at `service_install`.
- Detection reads what booted the machine (`/run/systemd/system`), not which binaries are installed, because a Gentoo host carries both.

**Left to the builder**

- How `is-system-running` output is read (`offline` vs the exit code).
- Whether `--name` is needed for plists whose label differs from the file name; the default is the basename without `.plist`.

**Out of scope**

- Writing unit files or plists from a template (callers already have their own).
- Timers, sockets and other unit types beyond passing their name through.
- Changing the dotfiles or `dyai` to use the module.
