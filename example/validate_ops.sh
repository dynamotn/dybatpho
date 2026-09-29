#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file validate_ops.sh
# @brief Example showing the shared validator
# @description
#   Checks a deployment request the way a real script would: the named types
#   first, then a record whose fields carry rules, then a type of this script's
#   own, and finally the same validator reached through a `config` schema and a
#   `cli` option so the three read the same.
#
#   Demonstrates dybatpho::validate_is, validate_matches, validate_value,
#   validate_errors, validate_or_die, validate_types, validate_describe,
#   validate_register, validate_reset
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules validate config cli

dybatpho::register_common_handlers

dybatpho::create_temp WORKDIR "" "validate"

# @description Run the `NAMED TYPES` section of this example.
# @noargs
function _demo_types {
  dybatpho::header "NAMED TYPES"
  local validate_types
  validate_types=$(dybatpho::validate_types | wc -l | tr -d ' ')
  dybatpho::info "${validate_types} types are registered"
  local -a pairs=(
    "email    ops@example.com"
    "email    ops.example.com"
    "port     8080"
    "port     65536"
    "url      https://example.com/health"
    "url      example.com"
    "ipv4     192.0.2.10"
    "ipv4     127.0.0.010"
    "semver   v2.1.0-rc.1"
    "semver   2.1"
    "date     2024-02-29"
    "date     2023-02-29"
    "duration 1h30m"
  )
  local pair type value verdict
  for pair in "${pairs[@]}"; do
    read -r type value <<< "${pair}"
    if dybatpho::validate_is "${type}" "${value}"; then
      verdict="ok"
    else
      verdict="not $(dybatpho::validate_describe "${type}")"
    fi
    dybatpho::print "$(printf '  %-9s %-28s %s' "${type}" "${value}" "${verdict}")"
  done
}

# @description Run the `PATH TYPES` section of this example.
# @noargs
function _demo_paths {
  dybatpho::header "PATH TYPES"
  # shellcheck disable=SC2154 # set by the option spec of this script
  local report="${WORKDIR}/report.txt"
  printf 'deployed\n' > "${report}"
  local validate_is_4
  validate_is_4=$(dybatpho::validate_is file "${report}" && echo yes || echo no)
  dybatpho::info "existing file      : ${validate_is_4}"
  local validate_is_3
  validate_is_3=$(dybatpho::validate_is dir "${WORKDIR}" && echo yes || echo no)
  dybatpho::info "existing directory : ${validate_is_3}"
  local validate_is_2
  validate_is_2=$(dybatpho::validate_is file "${WORKDIR}/absent" && echo yes || echo no)
  dybatpho::info "absent file        : ${validate_is_2}"
  # The output file does not exist yet; what has to exist is the directory it
  # will land in.
  local validate_is
  validate_is=$(dybatpho::validate_is parent_dir "${WORKDIR}/new.log" && echo yes || echo no)
  dybatpho::info "writable target    : ${validate_is}"
}

# @description Run the `RULES ON A RECORD` section of this example.
# @noargs
function _demo_rules {
  dybatpho::header "RULES ON A RECORD"
  local -a fields=(
    "contact|ops@example.com|type:email"
    "contact|ops@|type:email"
    "port|8080|type:int min:1 max:65535"
    "port|70000|type:int min:1 max:65535"
    "environment|qa|choices:dev,staging,prod"
    "branch|main|pattern:^(main|release/.+)$"
  )
  local field name value rules
  for field in "${fields[@]}"; do
    IFS='|' read -r name value rules <<< "${field}"
    # `rules` is a space-separated list on purpose: word splitting is how the
    # rules reach the validator as separate arguments.
    # shellcheck disable=SC2086
    if dybatpho::validate_value "${value}" ${rules}; then
      dybatpho::info "${name}=${value} accepted"
    else
      local validate_errors
      validate_errors=$(dybatpho::validate_errors | tr '\n' ' ')
      dybatpho::warn "${name}=${value} rejected: ${validate_errors}"
    fi
  done

  local validate_matches
  validate_matches=$(dybatpho::validate_matches "release/2.0" '^release/' && echo matches || echo no)
  dybatpho::info "regex directly: ${validate_matches}"
}

# @description Run the `A TYPE OF YOUR OWN` section of this example.
# @noargs
function _demo_custom_type {
  dybatpho::header "A TYPE OF YOUR OWN"
  # @description A validator of its own: a service name is `<team>-api` or `<team>-worker`.
  # @noargs
  function _is_service { [[ "$1" =~ ^[a-z]+-(api|worker)$ ]]; }
  dybatpho::validate_register service _is_service "a service name"
  local validate_is_2
  validate_is_2=$(dybatpho::validate_is service billing-api && echo ok || echo rejected)
  dybatpho::info "billing-api : ${validate_is_2}"
  local validate_is
  validate_is=$(dybatpho::validate_is service billing-db && echo ok || echo rejected)
  dybatpho::info "billing-db  : ${validate_is}"
  dybatpho::validate_value "billing-db" type:service || true
  local validate_errors
  validate_errors=$(dybatpho::validate_errors)
  dybatpho::warn "message: ${validate_errors}"
  # Leave the registry the way it was found.
  dybatpho::validate_reset
}

# @description Run the `THE SAME TYPES IN A CONFIG SCHEMA` section of this example.
# @noargs
function _demo_config {
  dybatpho::header "THE SAME TYPES IN A CONFIG SCHEMA"
  dybatpho::config_schema ADMIN_EMAIL email required:true description:"Who to page"
  dybatpho::config_schema LISTEN_PORT port default:8080 description:"Port to bind"
  dybatpho::config_schema RELEASE semver required:true description:"Version to deploy"

  local file="${WORKDIR}/app.env"
  printf 'ADMIN_EMAIL=ops@example.com\nRELEASE=v2.1.0\n' > "${file}"
  dybatpho::config_load "${file}"
  # `config_validate` applies the declared defaults and stops the script on a
  # violation, so this file is the one that passes.
  dybatpho::config_validate
  local config_get_2
  config_get_2=$(dybatpho::config_get ADMIN_EMAIL)
  dybatpho::info "ADMIN_EMAIL=${config_get_2}"
  local config_get
  config_get=$(dybatpho::config_get LISTEN_PORT)
  dybatpho::info "LISTEN_PORT defaulted to ${config_get}"
  local config_doc
  config_doc=$(dybatpho::config_doc markdown "Deployment settings")
  dybatpho::print "${config_doc}"

  printf 'ADMIN_EMAIL=ops@\nRELEASE=two\n' > "${WORKDIR}/broken.env"
  dybatpho::warn "a broken file reports every key at once:"
  # The broken file is loaded in a subshell: the values it carries must not
  # outlive the demonstration, and `config_validate` would end the script.
  (
    # Emptying the store is what `config_load` reads back; the module owns the
    # variable, so nothing in this file refers to it again.
    # shellcheck disable=SC2034 # read by config.sh, not by this example
    DYBATPHO_CONFIG=()
    dybatpho::config_load "${WORKDIR}/broken.env"
    dybatpho::config_validate
  ) 2>&1 | sed -n 's/.*Invalid configuration/  Invalid configuration/p' || true
  dybatpho::config_schema_reset
}

# This section is not an option spec; it defines one and runs it, so the
# `--help` the rule asks for belongs to `_deploy_spec` inside it.
# dyshellint disable=BSG052
# @description Run the `THE SAME TYPES ON A CLI OPTION` section of this example.
# @noargs
function _demo_cli {
  dybatpho::header "THE SAME TYPES ON A CLI OPTION"
  # @description The action behind the spec: report what the validated options say.
  # @noargs
  function _deploy_action {
    # shellcheck disable=SC2154 # set by the option spec of this script
    dybatpho::info "deploying ${RELEASE} to port ${PORT}, paging ${CONTACT}"
  }
  # @description An option spec whose options are validated by type rather than by hand.
  # @noargs
  function _deploy_spec {
    dybatpho::opts::setup "Deploy a release" DEPLOY_ARGS action:"_deploy_action"
    dybatpho::opts::param "Version to deploy" RELEASE --release type:semver required:true
    dybatpho::opts::param "Port to bind" PORT --port type:port init:=8080
    dybatpho::opts::param "Who to page" CONTACT --contact type:email required:true
    dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _deploy_spec"
  }
  dybatpho::generate_from_spec _deploy_spec \
    --release v2.1.0 --port 9090 --contact ops@example.com

  dybatpho::warn "a rejected value names the shape it should have had:"
  (dybatpho::generate_from_spec _deploy_spec --release nope --contact ops@example.com) 2>&1 \
    | sed -n 's/.*Expected/  Expected/p' || true
}

# @description Run the `STOPPING ON A BAD VALUE` section of this example.
# @noargs
function _demo_or_die {
  dybatpho::header "STOPPING ON A BAD VALUE"
  dybatpho::validate_or_die "--port" "8080" type:port
  dybatpho::info "--port 8080 passed"
  # In a real script this ends the run; here it is contained so the example can
  # go on to clean up after itself.
  (dybatpho::validate_or_die "--port" "http" type:int min:1) 2>&1 \
    | sed -n 's/.*Invalid --port/  Invalid --port/p' || true
}

_demo_types
_demo_paths
_demo_rules
_demo_custom_type
_demo_config
_demo_cli
_demo_or_die

dybatpho::header "DONE"
dybatpho::info "Temporary files under ${WORKDIR} are removed on exit"
