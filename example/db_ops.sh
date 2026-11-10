#!/usr/bin/env bash
# @file db_ops.sh
# @brief Example showing how to keep a script's state in SQLite
# @description
#   Migrates a task table, adds tasks whose text holds quotes and newlines,
#   claims one atomically, and reads the result. The database lives in a
#   temporary directory removed on exit; nothing is run where sqlite3 is
#   missing.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules db

dybatpho::register_common_handlers

# @description Run every section of this example, in order.
# @noargs
function _main {
  if ! command -v sqlite3 > /dev/null; then
    dybatpho::warn "sqlite3 isn't installed; skipping"
    return 0
  fi
  local work
  dybatpho::create_temp_dir work "db-example"
  local db="${work}/state.db"

  dybatpho::header "MIGRATE"
  mkdir -p "${work}/migrations"
  printf 'create table tasks (id integer primary key, body text not null, owner text);\n' \
    > "${work}/migrations/001_tasks.sql"
  dybatpho::db_migrate "${db}" "${work}/migrations"
  dybatpho::db_migrate "${db}" "${work}/migrations"
  local applied
  applied="$(dybatpho::db_value "${db}" "select group_concat(name) from dybatpho_migrations")"
  dybatpho::info "Applied: ${applied}"

  dybatpho::header "BIND"
  local body
  for body in "Ship v2" $'Fix O\'Reilly\'s "quote"\nbug' "'; DROP TABLE tasks; --"; do
    dybatpho::db_exec "${db}" "insert into tasks (body) values (:body)" body="${body}"
  done
  local count
  count="$(dybatpho::db_value "${db}" "select count(*) from tasks")"
  dybatpho::info "Tasks: ${count}"

  dybatpho::header "CLAIM"
  dybatpho::db_query "${db}" "update tasks set owner = :me
    where id = (select id from tasks where owner is null order by id limit 1)
    returning id, body" me="worker-$$"
  dybatpho::success "Database demo complete"
}

_main "$@"
