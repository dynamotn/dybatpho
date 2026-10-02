#!/usr/bin/env bash
# @file json_ops.sh
# @brief Example showing JSON and YAML utilities
# @description
#   Demonstrates dybatpho::json_query, json_has, json_pretty, json_to_yaml, yaml_query, yaml_has, yaml_pretty,
#   yaml_to_json, and the editing helpers json_set, json_del, json_merge, yaml_set, yaml_del, and yaml_merge
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules json

dybatpho::register_common_handlers

# @description Run the `JSON HELPERS` section of this example.
# @noargs
function _demo_json_helpers {
  dybatpho::header "JSON HELPERS"
  local json_file
  dybatpho::create_temp json_file ".json"
  cat > "${json_file}" << 'EOF'
{"name":"dybatpho","version":"1.0.0","features":["json","yaml"]}
EOF
  local json_query
  json_query=$(dybatpho::json_query "${json_file}" ".version")
  dybatpho::info "Version: ${json_query}"
  local json_has
  json_has=$(dybatpho::json_has "${json_file}" ".features" && echo yes || echo no)
  dybatpho::info "Has features? ${json_has}"
  dybatpho::info "Pretty JSON:"
  local json_pretty_output
  json_pretty_output=$(dybatpho::json_pretty "${json_file}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${json_pretty_output}")
  dybatpho::info "JSON helpers prefer yq when it is available"
}

# @description Run the `YAML HELPERS` section of this example.
# @noargs
function _demo_yaml_helpers {
  dybatpho::header "YAML HELPERS"
  local yaml_file
  dybatpho::create_temp yaml_file ".yaml"
  cat > "${yaml_file}" << 'EOF'
service:
  name: dybatpho
  enabled: true
EOF
  local yaml_query
  yaml_query=$(dybatpho::yaml_query "${yaml_file}" ".service.name")
  dybatpho::info "Service name: ${yaml_query}"
  local yaml_has
  yaml_has=$(dybatpho::yaml_has "${yaml_file}" ".service" && echo yes || echo no)
  dybatpho::info "Has service?  ${yaml_has}"
  dybatpho::info "Pretty YAML:"
  local yaml_pretty_output
  yaml_pretty_output=$(dybatpho::yaml_pretty "${yaml_file}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${yaml_pretty_output}")
}

# @description Run the `CONVERSION` section of this example.
# @noargs
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
  local json_to_yaml_output
  json_to_yaml_output=$(dybatpho::json_to_yaml "${json_file}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${json_to_yaml_output}")

  dybatpho::info "YAML -> JSON:"
  local yaml_to_json_output
  yaml_to_json_output=$(dybatpho::yaml_to_json "${yaml_file}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${yaml_to_json_output}")
}

# @description Run the `DOCUMENTS IN A VARIABLE` section of this example.
# @noargs
function _demo_in_memory {
  dybatpho::header "DOCUMENTS IN A VARIABLE"

  dybatpho::info "Encoding one value:"
  local json_string
  json_string=$(dybatpho::json_string 'he said "hi"')
  dybatpho::print "  ${json_string}"

  local document
  document=$(dybatpho::json_object \
    service api \
    note 'operator said "restart at 02:00"' \
    ports:json '[80,443]')
  dybatpho::info "Building an object, escaping included:"
  dybatpho::print "  ${document}"

  dybatpho::info "Reading it back:"
  local json_get
  json_get=$(dybatpho::json_get "${document}" '.service')
  dybatpho::print "  service: ${json_get}"
  local json_eval
  json_eval=$(dybatpho::json_eval "${document}" '.ports')
  dybatpho::print "  ports:   ${json_eval}"

  dybatpho::info "Appending to an array:"
  local list='[]'
  local json_object_2
  json_object_2=$(dybatpho::json_object name web)
  list=$(dybatpho::json_eval "${list}" \
    ". + [${json_object_2}]")
  local json_object
  json_object=$(dybatpho::json_object name worker)
  list=$(dybatpho::json_eval "${list}" \
    ". + [${json_object}]")
  dybatpho::print "  ${list}"

  if dybatpho::json_valid "${document}"; then
    dybatpho::info "The document parses"
  fi
  if ! dybatpho::json_valid 'not a document'; then
    dybatpho::info "Prose does not, so a script can tell the difference"
  fi
}

# @description Print a document indented under the current section.
# @arg $1 string Document text
function _print_document {
  local document
  dybatpho::expect_args document -- "$@"
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${document}")
}

# @description Run the `EDITING DOCUMENTS` section of this example.
# @noargs
function _demo_editing {
  dybatpho::header "EDITING DOCUMENTS"
  if ! dybatpho::is command yq && ! dybatpho::is command jq; then
    dybatpho::warn "yq or jq is required to run the editing demo"
    return 0
  fi

  local config overrides
  dybatpho::create_temp config ".json"
  dybatpho::create_temp overrides ".json"
  cat > "${config}" << 'EOF'
{"server":{"host":"localhost","port":8080},"debug":true,"tags":["a","b"]}
EOF
  cat > "${overrides}" << 'EOF'
{"server":{"host":"api.example.test"},"tags":["prod"]}
EOF

  dybatpho::info "Setting a string and a typed value, in place:"
  dybatpho::json_set "${config}" server.note 'set by "deploy"' "${config}"
  dybatpho::json_set --json "${config}" server.port 9090 "${config}"
  dybatpho::info "Removing a key and an array element:"
  dybatpho::json_del "${config}" debug "${config}"
  dybatpho::json_del "${config}" tags.0 "${config}"
  _print_document "$(< "${config}")"

  dybatpho::info "Merging an override file, the override winning:"
  local merged
  merged=$(dybatpho::json_merge "${config}" "${overrides}")
  _print_document "${merged}"

  if dybatpho::json_set "${config}" server.port.number 1 > /dev/null 2>&1; then
    dybatpho::error "A path through a number should have been refused"
  else
    dybatpho::info "A path through a number is refused, and the file is left untouched"
  fi

  if ! dybatpho::is command yq; then
    dybatpho::warn "yq is required for the YAML editing demo"
    return 0
  fi
  local values
  dybatpho::create_temp values ".yaml"
  cat > "${values}" << 'EOF'
image:
  tag: "1.0" # bumped by CI
replicas: 1
EOF
  dybatpho::info "Editing YAML keeps its comments:"
  dybatpho::yaml_set "${values}" image.tag 2.0 "${values}"
  dybatpho::yaml_set --json "${values}" replicas 3 "${values}"
  _print_document "$(< "${values}")"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_json_helpers
  _demo_yaml_helpers
  _demo_conversion
  _demo_in_memory
  _demo_editing
  dybatpho::success "JSON operations demo complete"
}

_main "$@"
