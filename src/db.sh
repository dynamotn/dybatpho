# shellcheck shell=bash
# The library returns its values on stdout, so its own functions are called inside `$(...)` by design. Every call
# here that can stop the script was reviewed: it is fixed, or listed with its reason in test/die-in-substitution.allow,
# which test/conventions.bats enforces.
# dyshellint disable=BSG047 # reviewed in test/die-in-substitution.allow
# @file db.sh
# @brief Utilities for keeping a script's state in SQLite
# @namespace dybatpho
# @description
#   This module runs SQL against a SQLite file through the `sqlite3` command
#   line tool, with what that tool lacks for a script: bound parameters, a
#   transaction per call, and numbered migrations.
#
#   Values are passed as `name=value` arguments and referred to as `:name`.
#   Each one reaches SQLite hex-encoded and is decoded there, so no character
#   of it -- a quote, a newline, `; DROP TABLE` -- is ever parsed as SQL. The
#   SQL and the values go to `sqlite3` on its standard input, never on its
#   command line.
#
#   Every call runs its statements in one `BEGIN IMMEDIATE` transaction, and
#   waits up to `DYBATPHO_DB_TIMEOUT` milliseconds for another process's lock,
#   so a read-modify-write -- claiming the next task -- is atomic across
#   processes. Statements that control a transaction themselves (`BEGIN`,
#   `COMMIT`, `VACUUM`, `PRAGMA journal_mode`) are not supported.
# @usage
#   ### Keep and claim tasks
#
#   ```bash
#   dybatpho::db_migrate "${db}" "${SCRIPT_DIR}/migrations"
#   dybatpho::db_exec "${db}" "insert into tasks(body) values (:body)" body="${text}"
#   dybatpho::db_query "${db}" "update tasks set owner = :me
#     where id = (select id from tasks where owner is null order by id limit 1)
#     returning id, body" me="$$"
#   ```
# @see
#   - `example/db_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_DB_TIMEOUT number [default: 5000] Milliseconds a call waits for another process's lock
DYBATPHO_DB_TIMEOUT="${DYBATPHO_DB_TIMEOUT:-5000}"
# @env DYBATPHO_DB_WAL bool [default: false] Put the database in WAL mode, so readers do not block a writer
DYBATPHO_DB_WAL="${DYBATPHO_DB_WAL:-false}"

# Separators of `db_value`'s output: control characters no ordinary value holds.
__DYBATPHO_DB_COLUMN=$'\037'
__DYBATPHO_DB_ROW=$'\036'
__DYBATPHO_DB_NULL=$'\035NULL\035'

#######################################
# @description Find the `:name` parameters a statement refers to, outside
#   string literals, quoted identifiers and comments, and stop on the other
#   placeholder forms, which `sqlite3` would bind as NULL without a word.
# @arg $1 string Name of the array receiving the parameter names, each once
# @arg $2 string SQL
# @set The named array
# @exitcode 1 Stop script on a `$name`, `@name` or `?` placeholder
# @internal
#######################################
function __dybatpho_db_scan_into {
  local -n __dybatpho_db_scan_names="$1"
  local sql="$2" i=0 n="${#2}" c next end name
  local -A seen=()
  __dybatpho_db_scan_names=()
  while ((i < n)); do
    c="${sql:i:1}"
    next="${sql:i+1:1}"
    case "${c}" in
      "'" | '"' | '`')
        # A quote is escaped by doubling it, so the next lone one ends it.
        end="${sql:i+1}"
        end="${end%%"${c}"*}"
        i=$((i + ${#end} + 2))
        while [[ "${sql:i:1}" == "${c}" ]]; do
          end="${sql:i+1}"
          end="${end%%"${c}"*}"
          i=$((i + ${#end} + 2))
        done
        continue
        ;;
      '[')
        end="${sql:i+1}"
        end="${end%%]*}"
        i=$((i + ${#end} + 2))
        continue
        ;;
      -)
        if [[ "${next}" == - ]]; then
          end="${sql:i}"
          end="${end%%$'\n'*}"
          i=$((i + ${#end}))
          continue
        fi
        ;;
      /)
        if [[ "${next}" == '*' ]]; then
          end="${sql:i+2}"
          end="${end%%'*/'*}"
          i=$((i + ${#end} + 4))
          continue
        fi
        ;;
      :)
        if [[ "${sql:i+1}" =~ ^([A-Za-z_][A-Za-z0-9_]*) ]]; then
          name="${BASH_REMATCH[1]}"
          if [[ -z "${seen[${name}]-}" ]]; then
            seen["${name}"]=1
            __dybatpho_db_scan_names+=("${name}")
          fi
          i=$((i + 1 + ${#name}))
          continue
        fi
        ;;
      '$' | @)
        [[ ! "${next}" =~ [A-Za-z_] ]] \
          || dybatpho::die "Use :name placeholders, not ${c}${next}...: sqlite3 would bind it to NULL"
        ;;
      '?') dybatpho::die "Use :name placeholders, not ?: sqlite3 would bind it to NULL" ;;
      *) ;;
    esac
    i=$((i + 1))
  done
}

#######################################
# @description Hex-encode a value, two digits a byte, for an `X'..'` literal.
# @arg $1 string Name of the variable receiving the digits
# @arg $2 string Value
# @set The named variable
# @internal
#######################################
function __dybatpho_db_hex_into {
  local -n __dybatpho_db_hex="$1"
  if [[ -z "$2" ]]; then
    __dybatpho_db_hex=""
    return 0
  fi
  __dybatpho_db_hex="$(printf '%s' "$2" | od -An -v -tx1)"
  __dybatpho_db_hex="${__dybatpho_db_hex//[[:space:]]/}"
}

#######################################
# @description Build and run one `sqlite3` session: the settings, the bound
#   parameters, then the SQL in one `BEGIN IMMEDIATE` transaction that
#   commits only if every statement succeeded.
# @arg $1 string Output: `none`, `json` or `ascii`
# @arg $2 path Database file
# @arg $3 string SQL, whose `:name` references must match the parameters exactly
# @arg $4 string SQL appended unscanned, from a trusted file; may be empty
# @arg $@ string Parameters, `name=value`
# @stdout What the statements printed, in the chosen mode
# @stderr `sqlite3`'s error
# @exitcode 0 Every statement succeeded and was committed
# @exitcode 1 One failed, and none took effect
# @internal
#######################################
function __dybatpho_db_run {
  local mode="$1" db="$2" sql="$3" tail="$4"
  shift 4
  command -v sqlite3 > /dev/null \
    || dybatpho::die "sqlite3 isn't installed; install sqlite (sqlite3 on Debian and Ubuntu)" 127
  [[ "${DYBATPHO_DB_TIMEOUT}" =~ ^[0-9]{1,9}$ ]] \
    || dybatpho::die "DYBATPHO_DB_TIMEOUT must be a number of milliseconds, got: ${DYBATPHO_DB_TIMEOUT}"

  local -A passed=()
  local -a lines=() used=()
  local pair name hex
  for pair in "$@"; do
    name="${pair%%=*}"
    [[ "${pair}" == *=* && "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
      || dybatpho::die "Invalid parameter '${pair%%=*}': write name=value, the name a word"
    [[ -z "${passed[${name}]+set}" ]] || dybatpho::die "Parameter ${name} is passed twice"
    passed["${name}"]="${pair#*=}"
  done
  __dybatpho_db_scan_into used "${sql}"
  for name in ${used[@]+"${used[@]}"}; do
    [[ -n "${passed[${name}]+set}" ]] || dybatpho::die "Parameter :${name} is not passed"
  done
  for name in "${!passed[@]}"; do
    [[ " ${used[*]-} " == *" ${name} "* ]] || dybatpho::die "Parameter ${name} is not used"
  done

  lines+=(".bail on" ".timeout $((10#${DYBATPHO_DB_TIMEOUT}))")
  if dybatpho::is true "${DYBATPHO_DB_WAL}"; then
    lines+=(".output /dev/null" "PRAGMA journal_mode=WAL;" ".output stdout")
  fi
  case "${mode}" in
    json) lines+=(".mode json") ;;
    ascii) lines+=(".mode ascii" '.separator "\037" "\036"' '.nullvalue "\035NULL\035"') ;;
    *) ;;
  esac
  lines+=(".param init")
  for name in "${!passed[@]}"; do
    __dybatpho_db_hex_into hex "${passed[${name}]}"
    lines+=(".param set :${name} \"CAST(X'${hex}' AS TEXT)\"")
  done
  # The newline before each `;` ends a trailing `--` comment first.
  lines+=("BEGIN IMMEDIATE;" "${sql}" ";" "${tail}" ";" "COMMIT;")

  # A path that starts with `-` would be read as an option.
  [[ "${db}" != -* ]] || db="./${db}"
  mkdir -p -- "$(dirname -- "${db}")" || dybatpho::die "Cannot create the directory of ${db}"
  local output status=0
  output="$(printf '%s\n' "${lines[@]}" | sqlite3 -init /dev/null -batch "${db}")" || status=$?
  ((status == 0)) || return 1
  [[ "${mode}" == none ]] || printf '%s' "${output}"
}

#######################################
# @description Run SQL that changes the database, with bound parameters, in one
#   transaction: either every statement takes effect or none does. What the
#   statements print, such as `RETURNING` rows, is discarded; use
#   `dybatpho::db_query` to read it.
# @example
#   dybatpho::db_exec "${db}" "insert into tasks(id, body) values (:id, :body)" id=42 body="${text}"
#
# @arg $1 path Database file, created with its directory when missing
# @arg $2 string SQL; refer to a parameter as `:name`
# @arg $@ string Parameters, `name=value`, each used by the SQL exactly once or more
# @env DYBATPHO_DB_TIMEOUT number [default: 5000] Milliseconds to wait for another process's lock
# @env DYBATPHO_DB_WAL bool [default: false] Put the database in WAL mode first
# @stderr `sqlite3`'s error when a statement fails
# @exitcode 0 Every statement succeeded
# @exitcode 1 One failed, and none took effect
# @exitcode 127 Stop script when `sqlite3` isn't installed
#######################################
function dybatpho::db_exec {
  local db sql
  dybatpho::expect_args db sql -- "$@"
  shift 2
  __dybatpho_db_run none "${db}" "${sql}" "" "$@" > /dev/null
}

#######################################
# @description Run SQL and print its rows as one JSON array of objects, `[]` for
#   none. Its statements run in one transaction like `dybatpho::db_exec`'s and
#   may write, so `update ... returning` claims and reads in one step.
# @example
#   dybatpho::db_query "${db}" "select id, body from tasks where owner = :me" me="$$" | jq -r '.[].body'
#
# @arg $1 path Database file
# @arg $2 string SQL
# @arg $@ string Parameters, `name=value`
# @stdout The rows of every statement, merged into one JSON array
# @exitcode 0 Every statement succeeded
# @exitcode 1 One failed, and none took effect
# @tip A value that is not valid UTF-8 comes back through JSON with replacement characters
#######################################
function dybatpho::db_query {
  local db sql
  dybatpho::expect_args db sql -- "$@"
  shift 2
  local output
  output="$(__dybatpho_db_run json "${db}" "${sql}" "" "$@")" || return 1
  output="${output%$'\n'}"
  if [[ -z "${output}" ]]; then
    printf '[]\n'
    return 0
  fi
  # Each statement prints an array of its own; a value's newlines are escaped
  # in JSON, so `]` and `[` around a bare newline only ever join two arrays.
  printf '%s\n' "${output//$']\n['/$',\n'}"
}

#######################################
# @description Run SQL and print the one value it yields, as it is.
# @example
#   count="$(dybatpho::db_value "${db}" "select count(*) from tasks where owner is null")"
#
# @arg $1 path Database file
# @arg $2 string SQL
# @arg $@ string Parameters, `name=value`
# @stdout The value
# @exitcode 0 There was a value
# @exitcode 1 No row, a NULL, or a statement failed
# @exitcode 2 Stop script on several rows or columns
#######################################
function dybatpho::db_value {
  local db sql
  dybatpho::expect_args db sql -- "$@"
  shift 2
  local output
  output="$(__dybatpho_db_run ascii "${db}" "${sql}" "" "$@")" || return 1
  [[ -n "${output}" ]] || return 1
  output="${output%"${__DYBATPHO_DB_ROW}"}"
  [[ "${output}" != *"${__DYBATPHO_DB_ROW}"* ]] || dybatpho::die "${FUNCNAME[0]}: The query yields several rows"
  [[ "${output}" != *"${__DYBATPHO_DB_COLUMN}"* ]] || dybatpho::die "${FUNCNAME[0]}: The query yields several columns"
  [[ "${output}" != "${__DYBATPHO_DB_NULL}" ]] || return 1
  printf '%s\n' "${output}"
}

#######################################
# @description Apply the migrations of a directory not applied yet: the files
#   named `<number>_<name>.sql`, in numeric order, each in its own transaction
#   that records it in `dybatpho_migrations` first. Two processes may migrate
#   at once: the one that finds a file already recorded by the other skips it.
# @example
#   dybatpho::db_migrate "${db}" "${SCRIPT_DIR}/migrations"
#
# @arg $1 path Database file
# @arg $2 path Directory of migrations
# @stderr `sqlite3`'s error for the file that failed
# @exitcode 0 Every pending migration was applied, or none was pending
# @exitcode 1 One failed; it took no effect, and the later ones did not run
# @exitcode 2 Stop script on a missing directory, or two files with the same number
#######################################
function dybatpho::db_migrate {
  local db dir
  dybatpho::expect_args db dir -- "$@"
  [[ -d "${dir}" ]] || dybatpho::die "${FUNCNAME[0]}: No migration directory: ${dir}"
  local -A files=()
  local file base version
  for file in "${dir}"/*.sql; do
    [[ -e "${file}" ]] || continue
    base="${file##*/}"
    [[ "${base}" =~ ^([0-9]{1,9})_.+\.sql$ ]] || continue
    version=$((10#${BASH_REMATCH[1]}))
    [[ -z "${files[${version}]-}" ]] || dybatpho::die "${FUNCNAME[0]}: Two migrations numbered ${version}"
    files["${version}"]="${file}"
  done
  __dybatpho_db_run none "${db}" "create table if not exists dybatpho_migrations (
    version integer primary key, name text not null, applied_at text not null)" "" > /dev/null || return 1
  local applied
  applied=",$(dybatpho::db_value "${db}" "select group_concat(version) from dybatpho_migrations" || true),"

  # A handful of files: sorted here, with no process.
  local -a versions=()
  local i j swap
  for version in "${!files[@]}"; do
    versions+=("${version}")
  done
  for ((i = 1; i < ${#versions[@]}; i++)); do
    for ((j = i; j > 0 && versions[j - 1] > versions[j]; j--)); do
      swap="${versions[j]}"
      versions[j]="${versions[j - 1]}"
      versions[j - 1]="${swap}"
    done
  done
  local err status
  for version in ${versions[@]+"${versions[@]}"}; do
    [[ -n "${version}" && "${applied}" != *",${version},"* ]] || continue
    file="${files[${version}]}"
    err="$(__dybatpho_db_run none "${db}" \
      "insert into dybatpho_migrations values (cast(:version as integer), :name, datetime('now'))" \
      "$(< "${file}")" version="${version}" name="${file##*/}" 2>&1 > /dev/null)" && continue
    # Recorded by another process meanwhile: it applied this file.
    [[ "${err}" != *"UNIQUE constraint failed: dybatpho_migrations.version"* ]] || continue
    printf '%s\n' "${err}" >&2
    dybatpho::error "Migration ${file##*/} failed; it took no effect"
    return 1
  done
}
