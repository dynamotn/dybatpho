#!/usr/bin/env bash
# @file json_ops.sh
# @brief Example showing JSON and YAML utilities
# @description Demonstrates dybatpho::json_query, json_has, json_pretty, json_to_yaml, yaml_query, yaml_has, yaml_pretty, and yaml_to_json
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules json

dybatpho::register_common_handlers

function _demo_json_helpers {
  dybatpho::header "JSON HELPERS"
  local json_file
  dybatpho::create_temp json_file ".json"
  cat > "${json_file}" << 'EOF'
{"name":"dybatpho","version":"1.0.0","features":["json","yaml"]}
EOF
  dybatpho::info "Version: $(dybatpho::json_query "${json_file}" ".version")"
  dybatpho::info "Has features? $(dybatpho::json_has "${json_file}" ".features" && echo yes || echo no)"
  dybatpho::info "Pretty JSON:"
  dybatpho::json_pretty "${json_file}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done
  dybatpho::info "JSON helpers prefer yq when it is available"
}

function _demo_yaml_helpers {
  dybatpho::header "YAML HELPERS"
  local yaml_file
  dybatpho::create_temp yaml_file ".yaml"
  cat > "${yaml_file}" << 'EOF'
service:
  name: dybatpho
  enabled: true
EOF
  dybatpho::info "Service name: $(dybatpho::yaml_query "${yaml_file}" ".service.name")"
  dybatpho::info "Has service?  $(dybatpho::yaml_has "${yaml_file}" ".service" && echo yes || echo no)"
  dybatpho::info "Pretty YAML:"
  dybatpho::yaml_pretty "${yaml_file}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done
}

function _demo_conversion {
  dybatpho::header "CONVERSION"
  if ! dybatpho::is command yq; then
    dybatpho::warn "yq is required to run the JSON/YAML conversion demo"
    return 0
  fi

  local json_file yaml_file
  dybatpho::create_temp json_file ".json"
  dybatpho::create_temp yaml_file ".yaml"
  cat > "${json_file}" << 'EOF'
{"name":"dybatpho","kind":"library"}
EOF
  cat > "${yaml_file}" << 'EOF'
name: dybatpho
kind: library
EOF

  dybatpho::info "JSON -> YAML:"
  dybatpho::json_to_yaml "${json_file}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done

  dybatpho::info "YAML -> JSON:"
  dybatpho::yaml_to_json "${yaml_file}" | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done
}

function _demo_in_memory {
  dybatpho::header "DOCUMENTS IN A VARIABLE"

  dybatpho::info "Encoding one value:"
  dybatpho::print "  $(dybatpho::json_string 'he said "hi"')"

  local document
  document=$(dybatpho::json_object \
    service api \
    note 'operator said "restart at 02:00"' \
    ports:json '[80,443]')
  dybatpho::info "Building an object, escaping included:"
  dybatpho::print "  ${document}"

  dybatpho::info "Reading it back:"
  dybatpho::print "  service: $(dybatpho::json_get "${document}" '.service')"
  dybatpho::print "  ports:   $(dybatpho::json_eval "${document}" '.ports')"

  dybatpho::info "Appending to an array:"
  local list='[]'
  list=$(dybatpho::json_eval "${list}" \
    ". + [$(dybatpho::json_object name web)]")
  list=$(dybatpho::json_eval "${list}" \
    ". + [$(dybatpho::json_object name worker)]")
  dybatpho::print "  ${list}"

  if dybatpho::json_valid "${document}"; then
    dybatpho::info "The document parses"
  fi
  if ! dybatpho::json_valid 'not a document'; then
    dybatpho::info "Prose does not, so a script can tell the difference"
  fi
}

function _main {
  _demo_json_helpers
  _demo_yaml_helpers
  _demo_conversion
  _demo_in_memory
  dybatpho::success "JSON operations demo complete"
}

_main "$@"
