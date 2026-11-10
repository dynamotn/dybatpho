# Feature Specification: SQLite Storage for Scripts

**Feature Branch**: `[feature-db]`
**Status**: Implemented
**Input**: Issue #18; `src/db.sh`, `test/db.bats`, `docs/db.md`, `example/db_ops.sh`; how `dyai` keeps its crew store, inbox and leases as JSON files edited with `jq` under `flock` (`lib/dyai_crew.sh`, `lib/dyai_store.sh`)

## Problem Statement *(mandatory)*

A script that keeps state beyond one file -- a task queue, leases with expiry, an inbox, a history it queries -- ends up rebuilding a database out of JSON: read the file under a lock, edit it with `jq`, write a temporary copy, move it into place, and hope no other process did the same in between. It is slow, every query is a full read, and each script gets the locking subtly wrong in its own way.

SQLite does all of that already, and its command line tool ships on macOS and most Linux distributions. What a Bash script lacks is a safe way to call it: the `sqlite3` CLI has no bound parameters, so values are pasted into SQL, and a value holding a quote, a newline or `; DROP TABLE` breaks the statement or worse. Its dot-command `.param set` takes a value on one line only.

## Business Value *(mandatory)*

- Keep structured state in one file with transactions, concurrent access and crash safety, without hand-written locking.
- Pass any value -- quotes, newlines, Unicode, SQL syntax -- into a statement without it ever being parsed as SQL.
- Apply schema changes in order, once, from numbered files.
- Read results as JSON, which `jq` and the `json` module already read.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run statements with bound values (Priority: P1)

As a script author, I want to run SQL with named parameters whose values are never parsed as SQL.

**Independent Test**: Insert a value holding `O'Reilly"; DROP TABLE t; --`, a newline, a tab and Unicode; read it back identical, as `text`, and find the table still there.

**Acceptance Scenarios**:

1. **Given** `db_exec DB "insert into t values(:k, :v)" k=key v="$value"`, **When** it runs, **Then** `:k` and `:v` hold exactly those strings, whatever they contain
2. **Given** several statements in one `db_exec`, **When** one fails, **Then** none of them takes effect and the call returns 1 with SQLite's message
3. **Given** a parameter named in the SQL but not passed, passed but not named, or passed twice, **When** it runs, **Then** the script stops naming it rather than binding NULL or ignoring it
4. **Given** `name=value` whose name is not a word, or a `$name`, `@name` or `?` placeholder in the SQL, **When** it runs, **Then** the script stops

---

### User Story 2 - Read results (Priority: P1)

**Acceptance Scenarios**:

1. **Given** `db_query DB SQL [params]`, **When** it runs, **Then** it prints the rows of all its statements as one JSON array of objects, `[]` for none
2. **Given** `db_value DB SQL [params]`, **When** the query yields one row and one column, **Then** it prints that value as it is, without quoting, and returns 0; **When** it yields no row or NULL, **Then** it prints nothing and returns 1; **When** it yields several rows or columns, **Then** the script stops
3. **Given** `db_query DB "update tasks set owner = :me where id = (...) returning id" me=$$`, **When** it runs, **Then** the claim and its result come from one transaction

---

### User Story 3 - Migrate a schema (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a directory of `NNN_name.sql` files, **When** `db_migrate DB DIR` runs, **Then** each file not yet recorded runs in order, each in its own transaction, and is recorded in a `dybatpho_migrations` table
2. **Given** the same directory again, **When** it runs, **Then** nothing runs
3. **Given** a file that fails, **When** it runs, **Then** that file's changes are rolled back, it is not recorded, later files do not run, and the call returns 1

---

### User Story 4 - Share a database between processes (Priority: P1)

**Acceptance Scenarios**:

1. **Given** several processes writing the same database, **When** they collide, **Then** each waits up to `DYBATPHO_DB_TIMEOUT` milliseconds for the lock instead of failing at once
2. **Given** `db_exec` with a read-modify-write, such as claiming the oldest unclaimed task, **When** two processes run it at once, **Then** exactly one claims each task: the statements of one call run in one `BEGIN IMMEDIATE` transaction

### Example Workflow

```bash
. init.sh --modules db

db="${XDG_STATE_HOME:-${HOME}/.local/state}/myapp/state.db"
dybatpho::db_migrate "${db}" "${SCRIPT_DIR}/migrations"

dybatpho::db_exec "${db}" "insert into tasks(id, body) values(:id, :body)" id=42 body="${text}"

# Claim one task atomically, across processes.
dybatpho::db_exec "${db}" "update tasks set owner = :me
  where id = (select id from tasks where owner is null order by id limit 1)" me="$$"

dybatpho::db_query "${db}" "select id, body from tasks where owner = :me" me="$$" | jq -r '.[].body'
count="$(dybatpho::db_value "${db}" "select count(*) from tasks")"
```

## Edge Cases

- `sqlite3` is not installed, as in a minimal Alpine image.
- The database file does not exist yet, or its directory does not.
- A value is empty, very long, holds a NUL-free binary-looking string, a newline, a quote, or SQL.
- A parameter is passed twice, or passed and not used.
- A query returns no rows, or `db_value` gets several rows or columns.
- Two processes write at once; one holds a long transaction.
- A migration directory is empty, holds a file not named `NNN_*.sql`, or two files with the same number.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `sqlite3` MUST run with `-init /dev/null -batch`, so the user's `~/.sqliterc` changes nothing. Every value MUST reach SQLite hex-encoded, bound through `.param set :name "CAST(X'<hex>' AS TEXT)"`, so no character of it is ever parsed by the shell, the dot-command parser, or SQL; the bound value MUST be of type `text` and equal to the input byte for byte.
- **FR-002**: Parameters MUST be passed as `name=value` arguments after the SQL, MUST be named `[A-Za-z_][A-Za-z0-9_]*`, and are referred to as `:name`; a `:name` in the SQL with no argument, an argument whose `:name` the SQL never uses, a name passed twice, and a `$name`, `@name` or `?` placeholder MUST each stop the script before SQLite runs. References are found outside string literals, quoted identifiers and comments.
- **FR-003**: `db_exec DB SQL [name=value...]` MUST run all its statements in one `BEGIN IMMEDIATE` transaction with `.bail on`, committing only if every statement succeeded; on failure it MUST return 1 and print SQLite's error to stderr. Its statements' output, such as `RETURNING` rows, MUST be discarded.
- **FR-004**: `db_query` MUST run like `db_exec`, in one `BEGIN IMMEDIATE` transaction that may write, and MUST print the rows of all its statements merged into one JSON array of objects, `[]` for no row.
- **FR-005**: `db_value` MUST run like `db_exec` and print the one value of a one-row, one-column result as it is; MUST return 1 with no output for no row or a NULL; and MUST stop the script on several rows or columns.
- **FR-006**: Every call MUST set a busy timeout of `DYBATPHO_DB_TIMEOUT` milliseconds (default 5000), and MUST open the database with its directory created when missing.
- **FR-007**: `db_migrate DB DIR` MUST run the files of DIR named `<digits>_<name>.sql` in numeric order, those not in `dybatpho_migrations(version, name, applied_at)`, each in its own transaction that inserts its record first: a process that finds the record already inserted by another -- a unique constraint on the version -- MUST skip the file rather than fail, so two processes may migrate at once. A failure MUST stop at that file and return 1. Two files with the same number MUST stop the script before any runs.
- **FR-008**: A missing `sqlite3` MUST stop the script with exit code 127 and an install hint.
- **FR-009**: The SQL and every value MUST reach `sqlite3` on its standard input, never on its command line, so neither appears in the process list.
- **FR-010**: With `DYBATPHO_DB_WAL` true-like, every call MUST first put the database in WAL mode (outside the transaction, its output discarded), so readers do not block a writer.
- **FR-011**: Statements that control a transaction (`BEGIN`, `COMMIT`, `ROLLBACK`, `SAVEPOINT`), and those that cannot run inside one (`VACUUM`, `PRAGMA journal_mode`, `PRAGMA foreign_keys`), are not supported in `db_exec`, `db_query`, `db_value` or a migration file. Values are text: one that is not valid UTF-8 is stored exactly but read back through JSON with replacement characters.

### Key Entities

- **Database**: One SQLite file.
- **Parameter**: A `name=value` argument bound as `:name`.
- **Migration**: A numbered SQL file applied once, recorded in `dybatpho_migrations`.

## Success Criteria *(mandatory)*

- **SC-001**: No value passed to the module can change the SQL that runs.
- **SC-002**: Two processes claiming tasks from one table never claim the same task.
- **SC-003**: A migration directory applied twice changes nothing the second time.

## Integration Tests *(mandatory)*

Tests run the real `sqlite3` in the test directory and skip where it is missing.

- **IT-001**: Round-trip a value holding quotes, `; DROP TABLE`, a newline, a tab, `$(cmd)` and Unicode; the table survives and the value is identical and `text`.
- **IT-002**: A failing second statement leaves the first one's change undone; the call returns 1 with the error on stderr.
- **IT-003**: Stop on an unbound `:name`, and on an invalid parameter name.
- **IT-004**: `db_query` prints `[]` and a rows array; `db_value` prints a scalar, returns 1 on no row, and stops on two columns.
- **IT-005**: Eight processes each claim one task from a table of five; five distinct claims, no task twice.
- **IT-006**: Migrate a directory of three files, again with nothing to do, and with a failing file that leaves its changes undone and stops the next.
- **IT-007**: Stop with exit code 127 when `sqlite3` is not on the `PATH`.
- **IT-008**: The SQL and values never appear in `sqlite3`'s arguments (stub records its argv).
- **IT-009**: Stop on a parameter passed twice, passed and unused, and on `$x`, `@x` and `?` placeholders; ignore `:x` inside a string literal and a comment.
- **IT-010**: Claim a row with `update ... returning` through `db_query`; merge two statements' rows into one array.
- **IT-011**: `db_value` returns 1 on NULL and stops on two rows.
- **IT-012**: Two processes migrate the same directory at once; both succeed and each file runs once.
- **IT-013**: With `DYBATPHO_DB_WAL=true`, the database reports `journal_mode` `wal` and `db_query` output is still pure JSON.

## Acceptance Criteria *(mandatory)*

1. Values are data, always.
2. A call is atomic.
3. Concurrency waits, it does not fail.

## Design Notes *(not part of the contract)*

- Decided with the owner: build it, for `dyai`'s state; WAL mode through `DYBATPHO_DB_WAL`, opt-in, since it changes the file for good and does not work on network filesystems.
- Decided by the designer: hex-encoded bound parameters (`.param set` takes one line only, and quoting by hand is the injection this module exists to prevent); JSON output, since `dyai` already reads JSON with `jq` and a TSV cannot carry a tab or newline; `BEGIN IMMEDIATE` so a read-modify-write takes the write lock up front; no `db_transaction` block API -- several statements in one `db_exec` are the transaction, which keeps the lock inside one process.
- Decided by the designer after a check against `sqlite3` 3.53: an unbound `:name` binds NULL silently and `-json` prints nothing for no row, so both are handled by the module; migrations insert their record first so concurrent runs skip rather than collide; transaction-control statements are documented as unsupported rather than lexed out; `db_value` reads `.mode ascii` with control-character separators and a NULL sentinel, so a NULL, an empty string and a comma are told apart.
- Out of scope: binary BLOBs, connection reuse across calls, and changing `dyai`.
