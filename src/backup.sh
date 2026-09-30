# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# parses its own options, so the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG051,BSG033
# @file backup.sh
# @brief Utilities for taking backups and applying a retention policy
# @namespace dybatpho
# @description
#   `archive.sh` creates and extracts archives; this module adds the policy
#   around them. It takes a timestamped snapshot, keeps the ones a retention
#   rule says to keep, and deletes the rest -- the loop that log rotation,
#   pre-change config snapshots and local database dumps each reimplement, and
#   each gets wrong in the same place: what exactly counts as "the last N".
#
#   A backup is written under a temporary name in the destination directory and
#   renamed into place, so a run that is killed halfway leaves no half-written
#   file that later looks like a good backup. A checksum sidecar is written
#   beside it, and `dybatpho::backup_verify` is what a restore checks before
#   trusting the archive.
#
#   Backups are named `<name>-<UTC timestamp>.<extension>`, which is why
#   sorting them by name is the same as sorting them by age, with no dependence
#   on a modification time that copying a directory can change.
# @tip Destinations are local paths; pushing a backup to object storage or a
#   network share stays with the caller
# @env DYBATPHO_BACKUP_EXTENSION string Archive extension, default is `tar.gz`; `archive.sh` reads the format from it
# @env DYBATPHO_BACKUP_CHECKSUM_ALGORITHM string Algorithm for the sidecar, default is `sha256`
# @see
#   - `example/backup_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_BACKUP_EXTENSION string Extension every backup is written with, default is `tar.gz`
DYBATPHO_BACKUP_EXTENSION="${DYBATPHO_BACKUP_EXTENSION:-tar.gz}"
# @env DYBATPHO_BACKUP_CHECKSUM_ALGORITHM string Checksum algorithm for the sidecar, default is `sha256`
DYBATPHO_BACKUP_CHECKSUM_ALGORITHM="${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM:-sha256}"

#######################################
# @description Print the timestamp a backup name carries.
#   UTC, so the names keep sorting in the order the backups were taken across
#   a daylight-saving change, which a local-time stamp does not.
# @noargs
# @stdout Timestamp in `YYYYmmddTHHMMSSZ` form
# @internal
#######################################
function __dybatpho_backup_stamp {
  TZ=UTC dybatpho::date_now "%Y%m%dT%H%M%SZ"
}

#######################################
# @description Collect a directory's backups into a named array, newest first.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Directory holding the backups
# @arg $3 string Backup name to match, or empty for every name
# @set The named array
# @internal
#######################################
function __dybatpho_backup_collect_into {
  local -n __dybatpho_backup_found_ref="$1"
  local __dybatpho_backup_dir="$2"
  local __dybatpho_backup_name="${3-}"
  __dybatpho_backup_found_ref=()

  dybatpho::is dir "${__dybatpho_backup_dir}" || return 0

  local -a __dybatpho_backup_candidates=()
  # The two cases are written out rather than folded into one pattern
  # variable: a `*` that comes from a quoted expansion is the character, not
  # the wildcard, so the unfiltered listing would match nothing at all.
  if [[ -n "${__dybatpho_backup_name}" ]]; then
    __dybatpho_backup_candidates=("${__dybatpho_backup_dir}/${__dybatpho_backup_name}"-*."${DYBATPHO_BACKUP_EXTENSION}")
  else
    __dybatpho_backup_candidates=("${__dybatpho_backup_dir}"/*-*."${DYBATPHO_BACKUP_EXTENSION}")
  fi

  local -a __dybatpho_backup_sorted=()
  local __dybatpho_backup_path

  # A glob is already sorted ascending, and the names carry a sortable UTC
  # stamp, so reversing it is the whole of "newest first" -- no `sort`, and no
  # trouble from a path that contains a newline. A glob that matched nothing
  # stays literal, which the file check below drops.
  for __dybatpho_backup_path in "${__dybatpho_backup_candidates[@]}"; do
    dybatpho::is file "${__dybatpho_backup_path}" || continue
    __dybatpho_backup_sorted+=("${__dybatpho_backup_path}")
  done

  local __dybatpho_backup_at=$((${#__dybatpho_backup_sorted[@]} - 1))
  for ((; __dybatpho_backup_at >= 0; __dybatpho_backup_at--)); do
    __dybatpho_backup_found_ref+=("${__dybatpho_backup_sorted[${__dybatpho_backup_at}]}")
  done
}

#######################################
# @description Print the path of a backup's checksum sidecar.
# @arg $1 string Backup archive path
# @stdout Sidecar path
# @internal
#######################################
function __dybatpho_backup_sidecar {
  printf '%s.%s\n' "$1" "${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM}"
}

#######################################
# @description Take a timestamped backup of a file or directory.
#   The archive is written under a temporary name in the destination and
#   renamed into place, so nothing half-written is ever left looking complete.
#   A checksum sidecar is written beside it.
# @arg $1 string File or directory to back up
# @arg $2 string Destination directory, created when missing
# @arg $3 string Optional name for the backup, default is the source's base name
# @stdout Path of the archive that was created
# @exitcode 0 The backup was taken
# @exitcode 1 The source does not exist, or the archive could not be written
# @example
#   archive="$(dybatpho::backup_create /etc/nginx /var/backups)"
#######################################
function dybatpho::backup_create {
  local source destination
  dybatpho::expect_args source destination -- "$@"
  local name="${3-}"

  dybatpho::is exist "${source}" \
    || dybatpho::die "${FUNCNAME[0]}: Nothing to back up at: ${source}"

  if [[ -z "${name}" ]]; then
    name="$(dybatpho::path_basename "${source}")"
  fi

  dybatpho::ensure_dir "${destination}" > /dev/null

  local stamp final
  stamp="$(__dybatpho_backup_stamp)"
  final="${destination}/${name}-${stamp}.${DYBATPHO_BACKUP_EXTENSION}"

  # Two backups of the same source within one second would otherwise overwrite
  # each other, and the second would look like the only one ever taken.
  local suffix=1
  while dybatpho::is exist "${final}"; do
    final="${destination}/${name}-${stamp}-${suffix}.${DYBATPHO_BACKUP_EXTENSION}"
    suffix=$((suffix + 1))
  done

  # The temporary lives in the destination so the rename stays on one
  # filesystem, which is what makes it atomic. It keeps the real extension,
  # because `archive.sh` reads the format from it, and it starts with a dot,
  # which is what keeps a half-written file out of every listing here: a glob
  # does not match a leading dot.
  local partial="${destination}/.${name}-${stamp}.$$.partial.${DYBATPHO_BACKUP_EXTENSION}"
  if ! dybatpho::archive_create "${source}" "${partial}"; then
    rm -f -- "${partial}"
    dybatpho::die "${FUNCNAME[0]}: Could not archive: ${source}"
  fi

  local checksum
  checksum="$(dybatpho::file_hash "${partial}" "${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM}")"

  mv -- "${partial}" "${final}"
  printf '%s  %s\n' "${checksum}" "$(dybatpho::path_basename "${final}")" \
    > "$(__dybatpho_backup_sidecar "${final}")"

  printf '%s\n' "${final}"
}

#######################################
# @description List a directory's backups, newest first.
# @arg $1 string Directory holding the backups
# @arg $2 string Optional backup name to match, default is every name
# @stdout One archive path per line, newest first
# @exitcode 0 The listing was printed, empty when there is nothing to list
# @example
#   dybatpho::backup_list /var/backups nginx
#######################################
function dybatpho::backup_list {
  local directory
  dybatpho::expect_args directory -- "$@"
  local name="${2-}"

  local -a found=()
  __dybatpho_backup_collect_into found "${directory}" "${name}"
  ((${#found[@]})) || return 0
  printf '%s\n' "${found[@]}"
}

#######################################
# @description Print the most recent backup in a directory.
# @arg $1 string Directory holding the backups
# @arg $2 string Optional backup name to match, default is every name
# @stdout Path of the newest archive
# @exitcode 0 A backup was found
# @exitcode 1 The directory holds no backup
# @example
#   dybatpho::backup_restore "$(dybatpho::backup_latest /var/backups nginx)" /etc
#######################################
function dybatpho::backup_latest {
  local directory
  dybatpho::expect_args directory -- "$@"
  local name="${2-}"

  local -a found=()
  __dybatpho_backup_collect_into found "${directory}" "${name}"
  ((${#found[@]})) || return 1
  printf '%s\n' "${found[0]}"
}

#######################################
# @description Check a backup against its checksum sidecar.
#   A backup with no sidecar cannot be checked, which is reported rather than
#   passed, because "nothing to compare" is not the same answer as "matches".
# @arg $1 string Backup archive path
# @exitcode 0 The archive matches its sidecar
# @exitcode 1 The archive is missing, has no sidecar, or does not match it
# @example
#   dybatpho::backup_verify "${archive}" || dybatpho::die "Corrupted backup"
#######################################
function dybatpho::backup_verify {
  local archive
  dybatpho::expect_args archive -- "$@"

  dybatpho::is file "${archive}" \
    || dybatpho::die "${FUNCNAME[0]}: No such backup: ${archive}"

  local sidecar
  sidecar="$(__dybatpho_backup_sidecar "${archive}")"
  dybatpho::is file "${sidecar}" \
    || dybatpho::die "${FUNCNAME[0]}: No checksum sidecar beside: ${archive}"

  local recorded actual
  read -r recorded _ < "${sidecar}"
  actual="$(dybatpho::file_hash "${archive}" "${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM}")"

  if [[ "${recorded}" != "${actual}" ]]; then
    dybatpho::error "${FUNCNAME[0]}: ${archive} does not match its sidecar"
    dybatpho::error "recorded ${recorded}, found ${actual}"
    return 1
  fi
  return 0
}

#######################################
# @description Restore a backup into a target directory.
#   The checksum is verified first, and the extraction goes through
#   `dybatpho::safe_extract`, so an archive whose entries would land outside
#   the target is refused and an overwrite is confirmed.
# @arg $1 string Option `--force`/`-f` to skip the overwrite confirmation
# @arg $2 string Backup archive path
# @arg $3 string Target directory, created when missing
# @exitcode 0 The backup was restored
# @exitcode 1 The archive fails its checksum, the overwrite is declined, or an entry escapes the target
# @env DRY_RUN string When true-like, `safe_extract` reports instead of extracting
# @example
#   dybatpho::backup_restore --force "${archive}" /etc/nginx
#######################################
function dybatpho::backup_restore {
  local force=""
  if [[ "${1-}" == "--force" || "${1-}" == "-f" ]]; then
    force="$1"
    shift
  fi

  local archive target
  dybatpho::expect_args archive target -- "$@"

  dybatpho::backup_verify "${archive}" || return 1
  dybatpho::ensure_dir "${target}" > /dev/null

  if [[ -n "${force}" ]]; then
    dybatpho::safe_extract "${force}" "${archive}" "${target}"
    return
  fi
  dybatpho::safe_extract "${archive}" "${target}"
}

#######################################
# @description Delete the backups a retention policy does not keep.
#   A backup survives when **any** policy keeps it, so asking for both
#   `--keep-count` and `--keep-days` keeps more rather than less: a retention
#   rule that deletes more than the operator expected is the expensive
#   direction to be wrong in.
#
#   `--keep-count` counts from the newest by name, which is the order the
#   backups were taken. `--keep-days` reads how old the file on disk is, so a
#   backup copied in from elsewhere is as old as the copy.
# @arg $1 string Options, in any order
# @arg $@ string Directory holding the backups, after the options
# @opt --keep-count <n> Keep the newest `n` backups
# @opt --keep-days <n> Keep the backups younger than `n` days
# @opt --name <name> Only consider the backups of this name
# @opt --force, -f Delete without confirming
# @stdout Nothing; the paths it would remove are reported by `safe_rm` under `DRY_RUN`
# @exitcode 0 The pruning finished, or nothing needed removing
# @exitcode 1 No retention policy was given, an option is malformed, or the removal was declined
# @env DRY_RUN string When true-like, report what would be removed instead of removing it
# @example
#   dybatpho::backup_prune --keep-count 7 --name nginx /var/backups
#######################################
function dybatpho::backup_prune {
  local keep_count="" keep_days="" name="" force="" directory=""

  while (($#)); do
    case "$1" in
      --keep-count)
        keep_count="${2-}"
        shift 2 || dybatpho::die "${FUNCNAME[0]}: --keep-count needs a number"
        ;;
      --keep-days)
        keep_days="${2-}"
        shift 2 || dybatpho::die "${FUNCNAME[0]}: --keep-days needs a number"
        ;;
      --name)
        name="${2-}"
        shift 2 || dybatpho::die "${FUNCNAME[0]}: --name needs a value"
        ;;
      --force | -f)
        force="--force"
        shift
        ;;
      --)
        shift
        directory="${1-}"
        break
        ;;
      # "dybatpho::backup_prune rejects a malformed option" covers this.
      # `dybatpho::die` exits, so that test uses `run`, which clears the trap
      # kcov instruments through.
      -*) dybatpho::die "${FUNCNAME[0]}: Unrecognized option: $1" ;; # kcov(skip)
      *)
        directory="$1"
        shift
        ;;
    esac
  done

  [[ -n "${directory}" ]] || dybatpho::die "${FUNCNAME[0]}: Expected a directory to prune"

  # Without a policy there is nothing to keep, and pruning would mean deleting
  # every backup there is. Refusing is the only safe reading of the request.
  [[ -n "${keep_count}" || -n "${keep_days}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected --keep-count or --keep-days; refusing to prune without a policy"

  [[ -z "${keep_count}" ]] || dybatpho::is int "${keep_count}" \
    || dybatpho::die "${FUNCNAME[0]}: --keep-count expects a number, got: ${keep_count}"
  [[ -z "${keep_days}" ]] || dybatpho::is int "${keep_days}" \
    || dybatpho::die "${FUNCNAME[0]}: --keep-days expects a number, got: ${keep_days}"

  local -a found=() doomed=()
  __dybatpho_backup_collect_into found "${directory}" "${name}"
  ((${#found[@]})) || return 0

  local at age cutoff=0
  [[ -z "${keep_days}" ]] || cutoff=$((keep_days * 86400))

  for at in "${!found[@]}"; do
    if [[ -n "${keep_count}" ]] && ((at < keep_count)); then
      continue
    fi
    if [[ -n "${keep_days}" ]]; then
      age="$(dybatpho::file_age_seconds "${found[${at}]}")"
      ((age > cutoff)) || continue
    fi
    doomed+=("${found[${at}]}")
    local sidecar
    sidecar="$(__dybatpho_backup_sidecar "${found[${at}]}")"
    dybatpho::is file "${sidecar}" && doomed+=("${sidecar}")
  done

  ((${#doomed[@]})) || return 0

  if [[ -n "${force}" ]]; then
    dybatpho::safe_rm "${force}" -- "${doomed[@]}"
    return
  fi
  dybatpho::safe_rm -- "${doomed[@]}"
}
