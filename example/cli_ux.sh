#!/usr/bin/env bash
# @file cli_ux.sh
# @brief Example of the advanced CLI UX helpers
# @description Demonstrates prompts, choices, multi-value parameters,
#              environment fallbacks, completion, schema, and man generation.
#
# Interactive usage:
#   bash example/cli_ux.sh deploy
#   DEPLOY_ENV=production bash example/cli_ux.sh deploy --tag api --tag worker
#
# Generate shell integrations and reference artifacts:
#   bash example/cli_ux.sh --completion bash > cli_ux.bash
#   bash example/cli_ux.sh --completion zsh > _cli_ux
#   bash example/cli_ux.sh --completion fish > cli_ux.fish
#   bash example/cli_ux.sh --schema > cli_ux.json
#   bash example/cli_ux.sh --man > cli_ux.1
#   bash example/cli_ux.sh --help
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _run_deploy {
  dybatpho::header "DEPLOY ${DEPLOY_ENV}"
  dybatpho::info "Selected components: ${COMPONENTS}"
  dybatpho::info "Dry run: ${DRY_RUN}"
  dybatpho::success "Deployment plan is ready"
  exit 0
}

function _run_root {
  if [[ -n "${COMPLETION_SHELL:-}" ]]; then
    dybatpho::generate_completion _spec_root "${COMPLETION_SHELL}" cli_ux.sh
  else
    dybatpho::generate_help _spec_root
  fi
}

function _spec_deploy {
  dybatpho::opts::setup "Deploy selected components" DEPLOY_ARGS args:none action:"_run_deploy"
  dybatpho::opts::param "Target environment" DEPLOY_ENV --environment env:DEPLOY_ENV \
    choices:staging,production prompt:"Choose the target environment"
  dybatpho::opts::param "Components to deploy" COMPONENTS --component \
    choices:api,worker,frontend multiple:true prompt:"Choose components"
  dybatpho::opts::flag "Preview without applying changes" DRY_RUN --dry-run on:true off:false init:="false"
}

function _spec_root {
  dybatpho::opts::setup "CLI UX demonstration" ROOT_ARGS action:"_run_root"
  dybatpho::opts::cmd deploy _spec_deploy
  dybatpho::opts::param "Completion shell (bash, zsh, or fish)" COMPLETION_SHELL --completion \
    choices:bash,zsh,fish
  dybatpho::opts::disp "Generate JSON schema" --schema \
    action:'dybatpho::generate_schema _spec_root cli_ux.sh'
  dybatpho::opts::disp "Generate roff man page" --man \
    action:'dybatpho::generate_man _spec_root cli_ux.sh'
}

dybatpho::generate_from_spec _spec_root "$@"
