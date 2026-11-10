# db.sh

Utilities for keeping a script's state in SQLite

> 🧭 Source: [src/db.sh](../src/db.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module runs SQL against a SQLite file through the `sqlite3` command
line tool, with what that tool lacks for a script: bound parameters, a
transaction per call, and numbered migrations.

Values are passed as `name=value` arguments and referred to as `:name`.
Each one reaches SQLite hex-encoded and is decoded there, so no character
of it -- a quote, a newline, `; DROP TABLE` -- is ever parsed as SQL. The
SQL and the values go to `sqlite3` on its standard input, never on its
command line.

Every call runs its statements in one `BEGIN IMMEDIATE` transaction, and
waits up to `DYBATPHO_DB_TIMEOUT` milliseconds for another process's lock,
so a read-modify-write -- claiming the next task -- is atomic across
processes. Statements that control a transaction themselves (`BEGIN`,
`COMMIT`, `VACUUM`, `PRAGMA journal_mode`) are not supported.

### 🌍 Environment

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_DB_TIMEOUT`** | number | no | `5000` | Milliseconds a call waits for another process's lock |
| **`DYBATPHO_DB_WAL`** | bool | no | `false` | Put the database in WAL mode, so readers do not block a writer |

### 🚀 Highlights

- [`dybatpho::db_exec`](#dybatphodb_exec) — Run SQL that changes the database, with bound parameters, in one transaction: either every statement takes effect or none does. What the statements print, such as `RETURNING` rows, is discarded; use `dybatpho::db_query` to read it.
- [`dybatpho::db_query`](#dybatphodb_query) — Run SQL and print its rows as one JSON array of objects, `[]` for none. Its statements run in one transaction like `dybatpho::db_exec`'s and may write, so `update ... returning` claims and reads in one step.
- [`dybatpho::db_value`](#dybatphodb_value) — Run SQL and print the one value it yields, as it is.
- [`dybatpho::db_migrate`](#dybatphodb_migrate) — Apply the migrations of a directory not applied yet: the files named `<number>_<name>.sql`, in numeric order, each in its own transaction that records it in `dybatpho_migrations` first. Two processes may migrate at once: the one that finds a file already recorded by the other skips it.

<a id="usage"></a>

## 🚀 Usage

### Keep and claim tasks

```bash
dybatpho::db_migrate "${db}" "${SCRIPT_DIR}/migrations"
dybatpho::db_exec "${db}" "insert into tasks(body) values (:body)" body="${text}"
dybatpho::db_query "${db}" "update tasks set owner = :me
  where id = (select id from tasks where owner is null order by id limit 1)
  returning id, body" me="$$"
```

<a id="see-also"></a>

## 🔗 See also

- [example/db_ops.sh](../example/db_ops.sh)

<a id="tips"></a>

## 💡 Tips

**[`dybatpho::db_query`](#dybatphodb_query)**

- A value that is not valid UTF-8 comes back through JSON with replacement characters

<a id="reference"></a>

## 📚 Reference

### `dybatpho::db_exec`

Run SQL that changes the database, with bound parameters, in one
transaction: either every statement takes effect or none does. What the
statements print, such as `RETURNING` rows, is discarded; use
`dybatpho::db_query` to read it.

**🧪 Example**

```bash
dybatpho::db_exec "${db}" "insert into tasks(id, body) values (:id, :body)" id=42 body="${text}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | Database file, created with its directory when missing |
| `$2` | string | SQL; refer to a parameter as `:name` |
| `$@` | string | Parameters, `name=value`, each used by the SQL exactly once or more |

**🌍 Environment variables**

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_DB_TIMEOUT`** | number | no | `5000` | Milliseconds to wait for another process's lock |
| **`DYBATPHO_DB_WAL`** | bool | no | `false` | Put the database in WAL mode first |

**📤 Output on stderr**

- `sqlite3`'s error when a statement fails

**🚦 Exit codes**

- `0`: Every statement succeeded
- `1`: One failed, and none took effect
- `127`: Stop script when `sqlite3` isn't installed

---

### `dybatpho::db_query`

Run SQL and print its rows as one JSON array of objects, `[]` for
none. Its statements run in one transaction like `dybatpho::db_exec`'s and
may write, so `update ... returning` claims and reads in one step.

**🧪 Example**

```bash
dybatpho::db_query "${db}" "select id, body from tasks where owner = :me" me="$$" | jq -r '.[].body'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | Database file |
| `$2` | string | SQL |
| `$@` | string | Parameters, `name=value` |

**📤 Output on stdout**

- The rows of every statement, merged into one JSON array

**🚦 Exit codes**

- `0`: Every statement succeeded
- `1`: One failed, and none took effect

---

### `dybatpho::db_value`

Run SQL and print the one value it yields, as it is.

**🧪 Example**

```bash
count="$(dybatpho::db_value "${db}" "select count(*) from tasks where owner is null")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | Database file |
| `$2` | string | SQL |
| `$@` | string | Parameters, `name=value` |

**📤 Output on stdout**

- The value

**🚦 Exit codes**

- `0`: There was a value
- `1`: No row, a NULL, or a statement failed
- `2`: Stop script on several rows or columns

---

### `dybatpho::db_migrate`

Apply the migrations of a directory not applied yet: the files
named `<number>_<name>.sql`, in numeric order, each in its own transaction
that records it in `dybatpho_migrations` first. Two processes may migrate
at once: the one that finds a file already recorded by the other skips it.

**🧪 Example**

```bash
dybatpho::db_migrate "${db}" "${SCRIPT_DIR}/migrations"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | Database file |
| `$2` | path | Directory of migrations |

**📤 Output on stderr**

- `sqlite3`'s error for the file that failed

**🚦 Exit codes**

- `0`: Every pending migration was applied, or none was pending
- `1`: One failed; it took no effect, and the later ones did not run
- `2`: Stop script on a missing directory, or two files with the same number
