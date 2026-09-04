#!/usr/bin/env bash
# @file secret_ops.sh
# @brief Example showing how to read, mask, and store secrets safely.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# Commands below receive secrets, so keep them out of any history file.
dybatpho::secret_no_history

secret_dir="${TMPDIR:-/tmp}/dybatpho-secret-example-${BASHPID}"
mkdir -p "${secret_dir}"
chmod 700 "${secret_dir}"
trap 'rm -rf -- "${secret_dir}"' EXIT

dybatpho::header "READ SECRETS"

# 1. From a file. Permissions are validated before the file is read.
token_file="${secret_dir}/api.token"
printf 'tok_live_4f8c21b9\n' > "${token_file}"
chmod 600 "${token_file}"
declare API_TOKEN
dybatpho::secret_from_file API_TOKEN "${token_file}"
dybatpho::print "file token: $(dybatpho::secret_hint "${API_TOKEN}")"

# 2. From the environment. The source variable is unset so child processes
#    don't inherit it.
export DEPLOY_KEY="dk_9a71e0c3f5"
declare DEPLOY_TOKEN
dybatpho::secret_from_env DEPLOY_TOKEN DEPLOY_KEY
dybatpho::print "env token: $(dybatpho::secret_hint "${DEPLOY_TOKEN}")"
dybatpho::print "DEPLOY_KEY after read: ${DEPLOY_KEY:-<unset>}"

# 3. From stdin. Use redirection instead of a pipe so the value lands in this
#    shell; on a terminal the input isn't echoed.
declare DB_PASSWORD
dybatpho::secret_from_stdin DB_PASSWORD "Database password: " \
  < <(printf 'pg_s3cret_pass\n')
dybatpho::print "stdin password: $(dybatpho::secret_hint "${DB_PASSWORD}")"

# A single entry point accepts any of the three sources.
# shellcheck disable=SC2034 # Passed by name to dybatpho::secret_write_file.
declare WEBHOOK_SECRET
dybatpho::secret_read WEBHOOK_SECRET "file:${token_file}"

dybatpho::header "MASK SECRETS"

# Logs and fatal errors redact every registered secret automatically.
dybatpho::info "authenticating with ${API_TOKEN}"
dybatpho::warn "retrying request for ${DEPLOY_TOKEN}"

# Command output is masked too, even when the secret is on the command line.
dybatpho::secret_mask_run printf 'authorization: Bearer %s\n' "${API_TOKEN}"

# Anything else can be filtered explicitly.
printf 'psql "postgres://app:%s@db.internal/app"\n' "${DB_PASSWORD}" \
  | dybatpho::secret_mask

dybatpho::header "STORE SECRETS"

# Writing creates a 0600 file atomically instead of leaving a readable file.
credential_file="${secret_dir}/credentials"
dybatpho::secret_write_file "${credential_file}" WEBHOOK_SECRET
dybatpho::print "credential mode: $(stat -L -c '%a' "${credential_file}" 2> /dev/null \
  || stat -L -f '%Lp' "${credential_file}")"
dybatpho::secret_check_permission "${credential_file}"

# Tools that insist on a file path can read from /dev/fd, so the secret never
# reaches the filesystem. `{}` is replaced with the readable path.
dybatpho::print "consumed by a file-based tool:"
dybatpho::secret_with_file DB_PASSWORD wc -c '{}'

# A world-readable secret is refused before it is used.
loose_file="${secret_dir}/loose.token"
printf 'leaked_token_value\n' > "${loose_file}"
chmod 644 "${loose_file}"
# Permission failures stop the script, so probe in a subshell to keep going.
if (dybatpho::secret_from_file LOOSE_TOKEN "${loose_file}") 2> /dev/null; then
  dybatpho::error "unsafe permissions should have been rejected"
else
  dybatpho::print "rejected ${loose_file} because it is readable by others"
fi

dybatpho::header "CLEAN UP"

# Remove file contents and drop the values from memory.
dybatpho::secret_shred "${credential_file}" "${loose_file}" "${token_file}"
dybatpho::secret_wipe API_TOKEN DEPLOY_TOKEN DB_PASSWORD WEBHOOK_SECRET LOOSE_TOKEN
dybatpho::secret_forget
dybatpho::print "remaining files: $(find "${secret_dir}" -type f | wc -l)"
dybatpho::success "Secrets handled without leaking to logs, history, or disk"
