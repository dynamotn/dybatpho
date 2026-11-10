setup() {
  load test_helper
  command -v sqlite3 > /dev/null || skip "sqlite3 is not installed"
  export DYBATPHO_DB_WAL=false DYBATPHO_DB_TIMEOUT=5000
  DB="${BATS_TEST_TMPDIR}/state/app.db"
  dybatpho::db_exec "${DB}" "create table t (k text primary key, v text)"
}

@test "dybatpho::db_exec binds any value as text, never as SQL" {
  local value=$'O\'Reilly"; DROP TABLE t; --\nline2\ttab é $(touch pwned) `id`'
  dybatpho::db_exec "${DB}" "insert into t values (:k, :v)" k=one v="${value}"
  run_traced -0 dybatpho::db_value "${DB}" "select v from t where k = :k" k=one
  assert_output "${value}"
  run_traced -0 dybatpho::db_value "${DB}" "select typeof(v) from t where k = 'one'"
  assert_output "text"
  run_traced -0 dybatpho::db_value "${DB}" "select count(*) from sqlite_master where name = 't'"
  assert_output "1"
  dybatpho::db_exec "${DB}" "insert into t values (:k, :v)" k=empty v=
  run_traced -0 dybatpho::db_value "${DB}" "select length(v) from t where k = :k" k=empty
  assert_output "0"
}

@test "dybatpho::db_exec runs its statements in one transaction" {
  run -1 --separate-stderr dybatpho::db_exec "${DB}" \
    "insert into t values ('a', '1'); insert into t values ('a', '2')"
  assert_stderr --partial "UNIQUE constraint failed"
  run_traced -0 dybatpho::db_value "${DB}" "select count(*) from t"
  assert_output "0"
}

@test "dybatpho::db_exec stops on a parameter it cannot bind exactly" {
  run -1 --separate-stderr dybatpho::db_exec "${DB}" "insert into t values (:k, :v)" k=x
  assert_stderr --partial "Parameter :v is not passed"
  run -1 --separate-stderr dybatpho::db_exec "${DB}" "insert into t values (:k, 'x')" k=x v=y
  assert_stderr --partial "Parameter v is not used"
  run -1 --separate-stderr dybatpho::db_exec "${DB}" "insert into t values (:k, 'x')" k=x k=y
  assert_stderr --partial "Parameter k is passed twice"
  run -1 --separate-stderr dybatpho::db_exec "${DB}" "insert into t values (:k, 'x')" 'k-1=x'
  assert_stderr --partial "Invalid parameter"
  local placeholder
  # The placeholders are SQL, meant literally.
  # shellcheck disable=SC2016
  for placeholder in '$v' '@v' '?' '?1'; do
    run -1 --separate-stderr dybatpho::db_exec "${DB}" "insert into t values ('x', ${placeholder})"
    assert_stderr --partial "Use :name placeholders"
  done
}

@test "dybatpho::db_exec ignores :name inside a string literal, a quoted name and a comment" {
  dybatpho::db_exec "${DB}" "insert into t values ('a:b', ':c') -- :d
    /* :e */; insert into t select :k, 'x' as \":f\"" k=z
  run_traced -0 dybatpho::db_value "${DB}" "select v from t where k = 'a:b'"
  assert_output ":c"
}

@test "dybatpho::db_query prints one JSON array, [] for no row, merging statements" {
  run_traced -0 dybatpho::db_query "${DB}" "select * from t"
  assert_output "[]"
  dybatpho::db_exec "${DB}" "insert into t values ('a', '1'); insert into t values ('b', '2')"
  run_traced -0 dybatpho::db_query "${DB}" "select k from t where k = 'a'; select k from t where k = 'b'"
  assert_output '[{"k":"a"},
{"k":"b"}]'
}

@test "dybatpho::db_query claims a row and returns it in one transaction" {
  dybatpho::db_exec "${DB}" "insert into t values ('a', null); insert into t values ('b', null)"
  run_traced -0 dybatpho::db_query "${DB}" \
    "update t set v = :me where k = (select k from t where v is null order by k limit 1) returning k" me=p1
  assert_output '[{"k":"a"}]'
}

@test "dybatpho::db_value returns 1 on no row and NULL, and stops on several rows or columns" {
  dybatpho::db_exec "${DB}" "insert into t values ('a', null); insert into t values ('b', '')"
  run_traced -1 dybatpho::db_value "${DB}" "select v from t where k = 'none'"
  assert_output ""
  run_traced -1 dybatpho::db_value "${DB}" "select v from t where k = 'a'"
  run_traced -0 dybatpho::db_value "${DB}" "select v from t where k = 'b'"
  assert_output ""
  run -1 --separate-stderr dybatpho::db_value "${DB}" "select k from t"
  assert_stderr --partial "several rows"
  run -1 --separate-stderr dybatpho::db_value "${DB}" "select k, v from t where k = 'a'"
  assert_stderr --partial "several columns"
}

@test "concurrent processes claim distinct rows" {
  local i
  for i in 1 2 3 4 5; do
    dybatpho::db_exec "${DB}" "insert into t values (:k, null)" k="task${i}"
  done
  for i in 1 2 3 4 5 6 7 8; do
    (dybatpho::db_query "${DB}" "update t set v = :me
      where k = (select k from t where v is null order by k limit 1) returning k" me="p${i}" \
      > "${BATS_TEST_TMPDIR}/claim.${i}") &
  done
  wait
  run_traced -0 dybatpho::db_value "${DB}" "select count(distinct v) from t where v is not null"
  assert_output "5"
  run -0 bash -c "cat '${BATS_TEST_TMPDIR}'/claim.* | grep -o 'task[0-9]' | sort | uniq -d"
  assert_output ""
}

# A migration directory with the given files: name, then SQL.
_migrations() {
  MIGRATIONS="${BATS_TEST_TMPDIR}/migrations"
  mkdir -p "${MIGRATIONS}"
  while (($#)); do
    printf '%s\n' "$2" > "${MIGRATIONS}/$1"
    shift 2
  done
}

@test "dybatpho::db_migrate applies each file once, in order" {
  _migrations 002_add.sql "insert into m values (2);" \
    001_create.sql "create table m (n integer);" \
    010_more.sql "insert into m values (10);"
  dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  run_traced -0 dybatpho::db_value "${DB}" "select group_concat(n) from m"
  assert_output "2,10"
  dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  run_traced -0 dybatpho::db_value "${DB}" "select count(*) from m"
  assert_output "2"
  run_traced -0 dybatpho::db_value "${DB}" "select group_concat(version) from dybatpho_migrations"
  assert_output "1,2,10"
}

@test "dybatpho::db_migrate stops at a failing file and undoes it" {
  _migrations 001_create.sql "create table m (n integer);" \
    002_bad.sql "insert into m values (1); insert into nope values (1);" \
    003_after.sql "insert into m values (3);"
  run -1 --separate-stderr dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  run_traced -0 dybatpho::db_value "${DB}" "select count(*) from m"
  assert_output "0"
  run_traced -0 dybatpho::db_value "${DB}" "select group_concat(version) from dybatpho_migrations"
  assert_output "1"
}

@test "dybatpho::db_migrate refuses two files with the same number" {
  _migrations 001_a.sql "select 1;" 001_b.sql "select 1;"
  run -1 --separate-stderr dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  assert_stderr --partial "Two migrations numbered 1"
}

@test "two processes migrating at once each apply every file exactly once" {
  _migrations 001_create.sql "create table m (n integer);" \
    002_add.sql "insert into m values (2);"
  (dybatpho::db_migrate "${DB}" "${MIGRATIONS}") &
  (dybatpho::db_migrate "${DB}" "${MIGRATIONS}") &
  wait
  run_traced -0 dybatpho::db_value "${DB}" "select count(*) from m"
  assert_output "1"
}

@test "DYBATPHO_DB_WAL puts the database in WAL mode and keeps query output clean" {
  DYBATPHO_DB_WAL=true run_traced -0 dybatpho::db_query "${DB}" "select 1 as one"
  assert_output '[{"one":1}]'
  run_traced -0 dybatpho::db_value "${DB}" "pragma journal_mode"
  assert_output "wal"
}

@test "SQL and values never reach sqlite3's command line" {
  local real
  real="$(command -v sqlite3)"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' \
    "${BATS_TEST_TMPDIR}/argv" "${real}" > "${BATS_TEST_TMPDIR}/bin/sqlite3"
  chmod +x "${BATS_TEST_TMPDIR}/bin/sqlite3"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" dybatpho::db_exec "${DB}" "insert into t values (:k, 'x')" k=secret-value
  run -0 cat "${BATS_TEST_TMPDIR}/argv"
  refute_output --partial "secret-value"
  refute_output --partial "insert"
}

@test "dybatpho::db_exec stops with an install hint when sqlite3 is missing" {
  PATH="$(path_without sqlite3)" run -127 --separate-stderr dybatpho::db_exec "${DB}" "select 1"
  assert_stderr --partial "sqlite3 isn't installed"
}

@test "dybatpho::db_value returns control characters as they are" {
  local value=$'\x01x\x1b[31m'
  dybatpho::db_exec "${DB}" "insert into t values ('c', :v)" v="${value}"
  run_traced -0 dybatpho::db_value "${DB}" "select v from t where k = 'c'"
  assert_output "${value}"
}

@test "dybatpho::db_exec stops on an unterminated comment, quote or bracket" {
  local sql
  for sql in "insert into t values ('a', 'b') /* note" "insert into t values ('a, 'b')" \
    "select [k from t"; do
    run -1 --separate-stderr dybatpho::db_exec "${DB}" "${sql}"
    assert_stderr --partial "Unterminated"
  done
}

@test "dybatpho::db_exec stops on every placeholder form sqlite3 would bind as NULL" {
  local sql
  # The placeholders are SQL, meant literally.
  # shellcheck disable=SC2016
  for sql in "select :idé" "select :1" 'select $1' "select @1" "select :é" 'select $é' "select #a"; do
    run -1 --separate-stderr dybatpho::db_exec "${DB}" "${sql}" id=5
    assert_stderr --partial "placeholder"
  done
}

@test "dybatpho::db_exec refuses a line that sqlite3 would run as a dot-command" {
  run -1 --separate-stderr dybatpho::db_exec "${DB}" $'select 1;\n.shell touch '"${BATS_TEST_TMPDIR}/pwned"
  assert_stderr --partial "dot-command"
  assert_file_not_exists "${BATS_TEST_TMPDIR}/pwned"
  run -1 --separate-stderr dybatpho::db_exec "${DB}" ".bail off"
  assert_stderr --partial "dot-command"
  # Inside a literal it is data.
  dybatpho::db_exec "${DB}" $'insert into t values (\'d\', \'\n.shell id\')'
}

@test "dybatpho::db_migrate scans its files: no placeholder, no dot-command" {
  _migrations 001_a.sql "create table m (n text); insert into m values (:zzz);"
  run -1 --separate-stderr dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  assert_stderr --partial "placeholder"
  rm "${MIGRATIONS}/001_a.sql"
  _migrations 001_b.sql $'create table m (n text);\n.shell touch '"${BATS_TEST_TMPDIR}/pwned"
  run -1 --separate-stderr dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  assert_file_not_exists "${BATS_TEST_TMPDIR}/pwned"
}

@test "dybatpho::db_exec binds a large value in linear time" {
  local value
  value="$(head -c 400000 /dev/zero | tr '\0' 'x')"
  local start="${SECONDS}"
  dybatpho::db_exec "${DB}" "insert into t values ('big', :v)" v="${value}"
  ((SECONDS - start < 10))
  run_traced -0 dybatpho::db_value "${DB}" "select length(v) from t where k = 'big'"
  assert_output "400000"
}

@test "a database path is a file, never a sqlite URI" {
  cd "${BATS_TEST_TMPDIR}"
  dybatpho::db_exec 'file:uri.db?mode=memory' "create table x (a)"
  assert_file_exists "${BATS_TEST_TMPDIR}/file:uri.db?mode=memory"
}

@test "dybatpho::db_exec stops on the TCL-style suffixes sqlite3 reads into a placeholder" {
  local sql
  # The placeholders are SQL, meant literally.
  # shellcheck disable=SC2016
  for sql in 'select :a$' "select :a::b" "select :a(x)" "select :::a" 'select $::a' "select @::a" "select #::a"; do
    run -1 --separate-stderr dybatpho::db_exec "${DB}" "${sql}" a=5 b=6
    assert_stderr --partial "placeholder"
  done
}

@test "dybatpho::db_migrate names the placeholder it refused in a migration file" {
  _migrations 001_a.sql "create table m (n text); insert into m values (:zzz);"
  run -1 --separate-stderr dybatpho::db_migrate "${DB}" "${MIGRATIONS}"
  assert_stderr --partial "not :zzz"
  refute_stderr --partial "was rolled back"
}
