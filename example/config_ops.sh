#!/usr/bin/env bash
# @file config_ops.sh
# @brief Example showing layered configuration and schema validation.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

config_dir="${TMPDIR:-/tmp}/dybatpho-config-example-${BASHPID}"
mkdir -p "${config_dir}"
trap 'rm -rf -- "${config_dir}"' EXIT

printf 'HOST=localhost\nPORT=8080\nMODE=dev\n' > "${config_dir}/defaults.env"
printf 'PORT=8443\n' > "${config_dir}/local.env"

# Environment values have the highest precedence over configuration files.
export APP_MODE=prod
dybatpho::config_load "${config_dir}/defaults.env" "${config_dir}/local.env"
dybatpho::config_env APP_

dybatpho::config_schema HOST string required:true
dybatpho::config_schema PORT int min:1 max:65535
dybatpho::config_schema MODE enum choices:dev,prod
dybatpho::config_schema REGION string default:us-east-1
dybatpho::config_validate
dybatpho::config_export APP_

dybatpho::header "CONFIGURATION"
dybatpho::print "host: ${APP_HOST}"
dybatpho::print "port: ${APP_PORT}"
dybatpho::print "mode: ${APP_MODE}"
dybatpho::print "region (default): ${APP_REGION}"
dybatpho::success "Configuration validated"
