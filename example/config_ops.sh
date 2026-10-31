#!/usr/bin/env bash
# @file config_ops.sh
# @brief Example showing layered configuration and schema validation.
# @description
#   Builds a three-layer configuration — a base dotenv file, a per-environment
#   override and the process environment — then declares a schema and shows
#   what validation catches, then reads single values from an INI file with
#   dybatpho::config_ini_get. Every file it reads is written into a temporary
#   directory it removes on exit.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules config

dybatpho::register_common_handlers

config_dir="${TMPDIR:-/tmp}/dybatpho-config-example-${BASHPID}"
mkdir -p "${config_dir}"
trap 'rm -rf -- "${config_dir}"' EXIT

printf 'HOST=localhost\nPORT=8080\nMODE=dev\n' > "${config_dir}/app.env"
printf 'PORT=8443\n' > "${config_dir}/app.prod.env"

# A profile overlays `app.<profile>.env` on top of `app.env`. The overlay may
# be absent, which is how the same call works on a machine that has no
# profile-specific file.
dybatpho::config_profile "${config_dir}/app.env" prod

# Any other list of files merges left to right, and `--optional` tolerates the
# ones that are simply not there.
dybatpho::config_load --optional "${config_dir}/site.env"

# Environment values have the highest precedence over configuration files.
export APP_MODE=prod
dybatpho::config_env APP_

# Every key is declared with a type, its constraints, and a description that
# feeds both the error messages and the generated reference.
dybatpho::config_schema HOST string required:true min:1 \
  description:"Service hostname"
dybatpho::config_schema PORT integer min:1 max:65535 \
  description:"Listening port"
dybatpho::config_schema MODE enum choices:dev,prod \
  description:"Deployment mode"
dybatpho::config_schema REGION string default:us-east-1 \
  description:"Cloud region"
dybatpho::config_schema ENDPOINT url default:https://api.example.test \
  description:"Upstream API endpoint"
dybatpho::config_validate
dybatpho::config_export APP_

dybatpho::header "CONFIGURATION"
# shellcheck disable=SC2154 # set by the option spec of this script
dybatpho::print "host: ${APP_HOST}"
# shellcheck disable=SC2154 # set by the option spec of this script
# Set by `dybatpho::config_load` above from the file it reads, which the linter cannot follow.
# dyshellint disable=BSG073 # set by `dybatpho
dybatpho::print "port: ${APP_PORT}"
dybatpho::print "mode: ${APP_MODE}"
# shellcheck disable=SC2154 # set by the option spec of this script
# Set by `dybatpho::config_load` above from the file it reads, which the linter cannot follow.
# dyshellint disable=BSG073 # set by `dybatpho
dybatpho::print "region (default): ${APP_REGION}"
# shellcheck disable=SC2154 # set by the option spec of this script
# Set by `dybatpho::config_load` above from the file it reads, which the linter cannot follow.
# dyshellint disable=BSG073 # set by `dybatpho
dybatpho::print "endpoint (default): ${APP_ENDPOINT}"
dybatpho::success "Configuration validated"

dybatpho::header "CONFIGURATION REFERENCE"
dybatpho::config_doc markdown "Example settings"

# Validation failures are reported per key, so every problem surfaces at once
# instead of one error per run.
dybatpho::header "VALIDATION FAILURES"
dybatpho::config_set PORT "not-a-number"
dybatpho::config_set MODE staging
unset "DYBATPHO_CONFIG[HOST]"
if (dybatpho::config_validate); then
  dybatpho::error "Expected the invalid configuration to be rejected"
else
  dybatpho::warn "Rejected the invalid configuration as expected"
fi

# A value can also be changed in memory and written back. The dotenv rewrite
# keeps the comments, blank lines, and order the file already has, and touches
# only the keys it is given.
dybatpho::header "SAVING CHANGES"
printf '%s\n' '# managed by the example' 'HOST=localhost' '' 'PORT=8080' \
  > "${config_dir}/saved.env"
dybatpho::config_set PORT 9090
dybatpho::config_set NOTE 'rewritten by config_save'
dybatpho::config_save "${config_dir}/saved.env" PORT NOTE
dybatpho::show_file "${config_dir}/saved.env"
dybatpho::success "Rewrote saved.env in place"

# An INI file another program owns is read one value at a time, without loading
# it into the configuration. Keys match whole, so the `-size` key never answers
# for `-name`, and a `#` inside a value is part of it.
dybatpho::header "READING AN INI FILE"
printf '%s\n' '; written by the GTK settings dialog' '[Settings]' \
  'gtk-cursor-theme-name = Breeze' 'gtk-cursor-theme-size=24' \
  'gtk-color = #3daee9' > "${config_dir}/settings.ini"
cursor_name="$(dybatpho::config_ini_get "${config_dir}/settings.ini" gtk-cursor-theme-name Settings)" \
  || cursor_name="Adwaita"
cursor_size="$(dybatpho::config_ini_get "${config_dir}/settings.ini" gtk-cursor-theme-size Settings)" \
  || cursor_size=24
accent="$(dybatpho::config_ini_get "${config_dir}/settings.ini" gtk-color)" || accent="none"
dybatpho::print "cursor: ${cursor_name} at ${cursor_size}px, accent ${accent}"
if dybatpho::config_ini_get "${config_dir}/settings.ini" gtk-font-name Settings > /dev/null; then
  dybatpho::error "Expected gtk-font-name to be missing"
else
  dybatpho::warn "gtk-font-name is not set; a caller falls back to its own default"
fi
