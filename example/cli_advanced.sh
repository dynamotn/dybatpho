#!/usr/bin/env bash
# @file cli_advanced.sh
# @brief Example showing advanced CLI option parsing with nested subcommands
# @description Demonstrates dybatpho opts system with multiple subcommands,
#              flags, params, and auto-generated help pages
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# ===========================================================================
# Global flags (shared across all commands)
# ===========================================================================

function _spec_global {
  dybatpho::opts::flag "Enable verbose output" VERBOSE --verbose alias:-v persistent:true
  dybatpho::opts::flag "Print commands without executing" DRY_RUN --dry-run -n on:true off:false init:="false" persistent:true
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" persistent:true
}

# ===========================================================================
# deploy subcommand
# ===========================================================================

function _run_deploy {
  local _target="${ENV:-staging}"
  dybatpho::header "DEPLOY → ${_target}"
  [[ "${FORCE:-false}" == "true" ]] && dybatpho::warn "Force flag set — skipping pre-flight checks"
  [[ "${BUILD:-false}" == "true" ]] && dybatpho::progress "Building application..."
  dybatpho::dry_run "echo 'Deploying to ${_target}...'"
  dybatpho::dry_run "echo 'Running post-deploy hooks on ${_target}...'"
  dybatpho::success "Deploy to ${_target} complete" && exit 0
}

function _spec_deploy {
  dybatpho::opts::setup "Deploy application to an environment" DEPLOY_ARGS args:none action:"_run_deploy" \
    prerun:"dybatpho::progress 'Preparing deploy...'" \
    postrun:"dybatpho::success 'Deploy hook finished'"
  dybatpho::opts::param "Target environment" ENV -e --env init:="staging"
  dybatpho::opts::flag "Force deploy even if checks fail" FORCE -f --force
  dybatpho::opts::flag "Build before deploying" BUILD -b --build
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_deploy"
}

# ===========================================================================
# db subcommands
# ===========================================================================

function _run_db_migrate {
  dybatpho::header "DB MIGRATE (steps: ${STEPS:-all})"
  dybatpho::dry_run "echo 'Running ${STEPS:-all} migration(s)...'"
  dybatpho::success "Migrations complete" && exit 0
}

function _spec_db_migrate {
  dybatpho::opts::setup "Run pending database migrations" MIGRATE_ARGS args:none action:"_run_db_migrate"
  dybatpho::opts::param "Number of migrations to run" STEPS -s --steps init:="all"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_db_migrate"
}

function _run_db_seed {
  dybatpho::header "DB SEED (fixture: ${FIXTURE})"
  dybatpho::dry_run "echo 'Seeding from ${FIXTURE}...'"
  dybatpho::success "Seeding complete" && exit 0
}

function _spec_db_seed {
  dybatpho::opts::setup "Populate database with seed data" SEED_ARGS args:none action:"_run_db_seed"
  dybatpho::opts::param "Seed fixture file" FIXTURE -f --fixture required:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_db_seed"
}

function _run_db_reset {
  if [[ "${YES:-false}" != "true" ]]; then
    dybatpho::warn "This will DESTROY all data. Pass --yes to confirm."
    exit 0
  fi
  dybatpho::header "DB RESET"
  dybatpho::dry_run "echo 'Dropping database...'"
  dybatpho::dry_run "echo 'Recreating database...'"
  dybatpho::success "Database reset complete" && exit 0
}

function _spec_db_reset {
  dybatpho::opts::setup "Drop and recreate the database" RESET_ARGS args:none action:"_run_db_reset"
  dybatpho::opts::flag "Skip confirmation prompt" YES -y --yes
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_db_reset"
}

function _spec_db {
  dybatpho::opts::setup "Database management commands" DB_ARGS action:"dybatpho::generate_help _spec_db"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_db"
  dybatpho::opts::cmd migrate _spec_db_migrate
  dybatpho::opts::cmd seed _spec_db_seed
  dybatpho::opts::cmd reset _spec_db_reset
}

# ===========================================================================
# config subcommand
# ===========================================================================

function _run_config {
  dybatpho::header "CONFIG"
  if [[ "${LIST:-false}" == "true" ]]; then
    dybatpho::info "APP_ENV   = ${APP_ENV:-<unset>}"
    dybatpho::info "LOG_LEVEL = ${LOG_LEVEL:-info}"
    dybatpho::info "DRY_RUN   = ${DRY_RUN:-false}"
    exit 0
  fi
  if [[ -z "${KEY:-}" ]]; then
    dybatpho::generate_help _spec_config
    exit 0
  fi
  if [[ -n "${VALUE:-}" ]]; then
    dybatpho::info "Set ${KEY}=${VALUE} (dry-run — not actually persisted)"
  else
    dybatpho::info "Reading key '${KEY}' — not found (demo only)"
  fi
  exit 0
}

function _spec_config {
  dybatpho::opts::setup "Show or update configuration" CONFIG_ARGS args:none action:"_run_config"
  dybatpho::opts::param "Config key to read or write" KEY -k --key
  dybatpho::opts::param "Value to set (omit to read)" VALUE -V --value
  dybatpho::opts::flag "List all config keys" LIST -l --list
  dybatpho::opts::flag "Legacy output format" LEGACY_OUTPUT --legacy-output hidden:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_config"
}

# ===========================================================================
# Root spec + entry point
# ===========================================================================

function _spec_root {
  _spec_global
  dybatpho::opts::setup "A sample devops CLI built with dybatpho" ROOT_ARGS action:"dybatpho::generate_help _spec_root"
  dybatpho::opts::disp "Show version" --version action:"echo v1.0.0"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_root"
  dybatpho::opts::cmd deploy _spec_deploy
  dybatpho::opts::cmd db _spec_db
  dybatpho::opts::cmd config _spec_config alias:cfg
  dybatpho::opts::cmd old-config _spec_config deprecated:"Use 'config' instead"
}

dybatpho::generate_from_spec _spec_root "$@"
