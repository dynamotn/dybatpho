#!/usr/bin/env bash
# @file cli_ux.sh
# @brief Example of the advanced CLI UX helpers
# @description Demonstrates prompts, choices, multi-value parameters,
#              environment and configuration fallbacks, generated `--no-`
#              switches, counting verbosity flags, documented positional
#              arguments, typo suggestions, completion, schema, and man
#              generation.
#
# Interactive usage:
#   bash example/cli_ux.sh deploy --component api api
#   DEPLOY_ENV=production bash example/cli_ux.sh deploy --component api --component worker api
#
# Precedence of a bound option is flag > env > config file > default:
#   bash example/cli_ux.sh deploy --component api api                      # default
#   DEPLOY_ENV=production bash example/cli_ux.sh deploy --component api api # env wins over config
#   bash example/cli_ux.sh deploy -e staging --component api api           # flag wins over both
#
# Typos are answered with the closest match:
#   bash example/cli_ux.sh depoy
#   bash example/cli_ux.sh deploy --enviroment staging
#
# Generate shell integrations and reference artifacts:
#   bash example/cli_ux.sh completion --shell bash > cli_ux.bash
#   bash example/cli_ux.sh completion --shell zsh > _cli_ux
#   bash example/cli_ux.sh completion --shell fish > cli_ux.fish
#   bash example/cli_ux.sh schema > cli_ux.json
#   bash example/cli_ux.sh man > cli_ux.1
#   bash example/cli_ux.sh --help
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules cli

dybatpho::register_common_handlers

# Values loaded before the parser runs become the configuration layer that
# `config:<key>` reads, underneath any environment variable or explicit flag.
# A real CLI would reach this state through `dybatpho::config_load ./app.yaml`;
# the keys are set directly here to keep the example free of a data file.
# shellcheck disable=SC2034 # read by the generated parser through config:<key>
DYBATPHO_CONFIG["deploy.environment"]="staging"
# shellcheck disable=SC2034 # read by the generated parser through config:<key>
DYBATPHO_CONFIG["deploy.color"]="true"

# @description Run the `DEPLOY ${DEPLOY_ENV}` section of this example.
# @noargs
function _run_deploy {
  # A counting flag carries how often `-v` was repeated, which maps onto the
  # log level: `-v` is debug and `-vv` is trace.
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::cli_apply_verbosity "${VERBOSITY}"

  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::header "DEPLOY ${DEPLOY_ENV}"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "Service: ${SERVICE}"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "Selected components: ${COMPONENTS}"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "Colorized output: ${COLOR}"
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  dybatpho::info "Dry run: ${DRY_RUN}"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "Replicas: ${REPLICAS}"
  # shellcheck disable=SC2154 # declared by `src/logging.sh`, a core module
  dybatpho::debug "Verbosity requested ${VERBOSITY} time(s), log level is ${LOG_LEVEL}"
  dybatpho::success "Deployment plan is ready"
  exit 0
}

# @description The action of the root command: print its own help.
# @noargs
function _run_root {
  dybatpho::generate_help _spec_root
}

# @description The action of `completion`: write the completion script for a shell.
# @noargs
function _run_completion {
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::generate_completion _spec_root "${COMPLETION_SHELL}" cli_ux.sh
  exit 0
}

# @description The action of `schema`: write the CLI as a JSON schema.
# @noargs
function _run_schema {
  dybatpho::generate_schema _spec_root cli_ux.sh
  exit 0
}

# @description The action of `man`: write the CLI as a roff man page.
# @noargs
function _run_man {
  dybatpho::generate_man _spec_root cli_ux.sh
  exit 0
}

# @description The option spec of `deploy`, which shows every option attribute at once.
# @noargs
function _spec_deploy {
  dybatpho::opts::setup "Deploy selected components" DEPLOY_ARGS action:"_run_deploy"
  dybatpho::opts::arg "Service to deploy" SERVICE
  dybatpho::opts::param "Target environment" DEPLOY_ENV -e --environment \
    env:DEPLOY_ENV config:deploy.environment \
    choices:staging,production prompt:"Choose the target environment"
  dybatpho::opts::param "Components to deploy" COMPONENTS --component \
    choices:api,worker,frontend multiple:true prompt:"Choose components"
  # `pattern:` is the lighter alternative to `validate:` when the rule is a
  # shape rather than a fixed list of values.
  dybatpho::opts::param "Number of replicas" REPLICAS --replicas \
    pattern:'[0-9]*' init:="1"
  # `msg` heads a group of options; it declares no switch and only shows up in
  # help, so completion, schema, and man output are unaffected.
  dybatpho::opts::msg ""
  dybatpho::opts::msg "Output options:"
  # `negatable:true` generates `--no-color` alongside `--color`, so the toggle
  # does not have to be spelled out as `--{no-}color`.
  dybatpho::opts::flag "Colorize the deployment report" COLOR --color \
    negatable:true config:deploy.color
  dybatpho::opts::flag "Preview without applying changes" DRY_RUN --dry-run on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_deploy"
}

# @description The option spec of `completion`.
# @noargs
function _spec_completion {
  dybatpho::opts::setup "Generate shell completion" COMPLETION_ARGS args:none action:"_run_completion"
  dybatpho::opts::param "Completion shell (bash, zsh, or fish)" COMPLETION_SHELL \
    --shell choices:bash,zsh,fish required:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_completion"
}

# @description The option spec of `schema`.
# @noargs
function _spec_schema {
  dybatpho::opts::setup "Generate JSON CLI schema" SCHEMA_ARGS args:none action:"_run_schema"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_schema"
}

# @description The option spec of `man`.
# @noargs
function _spec_man {
  dybatpho::opts::setup "Generate roff man page" MAN_ARGS args:none action:"_run_man"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_man"
}

# @description The option spec of the root command, with the artifact subcommands.
# @noargs
function _spec_root {
  dybatpho::opts::setup "CLI UX demonstration" ROOT_ARGS action:"_run_root"
  # A persistent counting flag every subcommand inherits.
  dybatpho::opts::flag "Increase verbosity, repeat for more" VERBOSITY -v \
    alias:--verbose count:true persistent:true
  dybatpho::opts::cmd deploy _spec_deploy
  dybatpho::opts::cmd completion _spec_completion
  dybatpho::opts::cmd schema _spec_schema
  dybatpho::opts::cmd man _spec_man
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_root"
}

dybatpho::generate_from_spec _spec_root "$@"
