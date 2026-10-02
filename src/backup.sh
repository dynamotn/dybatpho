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
#
#   `--incremental` takes a snapshot directory instead of an archive, in which
#   every file unchanged since the previous snapshot is a hard link to it, so a
#   long history of a large tree costs one copy plus what changed. Snapshots
#   are listed, verified, restored, compared and pruned like archives.
#
#   `dybatpho::backup_diff` answers what a restore would undo: it compares two
#   backups, or a backup and the live data, through `dybatpho::diff_dir`,
#   extracting each verified backup into a scratch directory first.
# @tip Destinations are local paths; pushing a backup to object storage or a
#   network share stays with the caller
# @tip A snapshot shares its unchanged files with other snapshots, so read and
#   restore it, never edit inside it
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
# @description Return success when a path is an incremental snapshot: a real
#   directory, not a link to one, named with the `.snapshot` suffix.
# @arg $1 string Path
# @exitcode 0 The path is a snapshot
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_backup_is_snapshot {
  [[ "$1" == *.snapshot && -d "$1" && ! -L "$1" ]]
}

#######################################
# @description Build the key that orders a backup among the others.
#   The key is the backup name, the UTC stamp, and the same-second suffix
#   zero-padded to nine digits, joined by a byte lower than any character a
#   name can hold, so a byte-wise comparison orders by name, then by the time
#   the backup was taken, then by the suffix as a number. A file name that does
#   not carry a stamp keys as itself.
# @arg $1 string Name of the variable receiving the key
# @arg $2 string Path of the backup
# @set The named variable
# @internal
#######################################
function __dybatpho_backup_sort_key_into {
  local -n __dybatpho_backup_key_ref="$1"
  local __dybatpho_backup_base="${2##*/}"
  __dybatpho_backup_base="${__dybatpho_backup_base%.snapshot}"
  __dybatpho_backup_base="${__dybatpho_backup_base%."${DYBATPHO_BACKUP_EXTENSION}"}"

  if [[ "${__dybatpho_backup_base}" =~ ^(.*)-([0-9]{8}T[0-9]{6}Z)(-([0-9]+))?$ ]]; then
    printf -v __dybatpho_backup_key_ref '%s\001%s\001%09d' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$((10#${BASH_REMATCH[4]:-0}))"
  else
    __dybatpho_backup_key_ref="${__dybatpho_backup_base}"
  fi
}

#######################################
# @description Collect a directory's backups into a named array, newest first.
#   Archives and incremental snapshots are both backups. Each kind is globbed
#   on its own, and the two are ordered together by name, stamp and
#   same-second suffix, so the result stays in the order the backups were taken
#   whatever the caller's collation.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Directory holding the backups
# @arg $3 string Backup name to match, or empty for every name
# @arg $4 string Kind to collect: `archive`, `snapshot`, or empty for both
# @set The named array
# @internal
#######################################
function __dybatpho_backup_collect_into {
  local -n __dybatpho_backup_found_ref="$1"
  local __dybatpho_backup_dir="$2"
  local __dybatpho_backup_name="${3-}"
  local __dybatpho_backup_kind="${4-}"
  __dybatpho_backup_found_ref=()

  dybatpho::is dir "${__dybatpho_backup_dir}" || return 0

  local -a __dybatpho_backup_archives=() __dybatpho_backup_snapshots=()
  local __dybatpho_backup_path
  # The cases are written out rather than folded into one pattern variable: a
  # `*` that comes from a quoted expansion is the character, not the wildcard,
  # so the unfiltered listing would match nothing at all. The order comes from
  # the sort keys below, not from the glob, so no `sort` is needed and a path
  # holding a newline does no harm. A glob that matched nothing stays literal,
  # which the kind checks below drop.
  if [[ "${__dybatpho_backup_kind}" != snapshot ]]; then
    if [[ -n "${__dybatpho_backup_name}" ]]; then
      __dybatpho_backup_archives=("${__dybatpho_backup_dir}/${__dybatpho_backup_name}"-*."${DYBATPHO_BACKUP_EXTENSION}")
    else
      __dybatpho_backup_archives=("${__dybatpho_backup_dir}"/*-*."${DYBATPHO_BACKUP_EXTENSION}")
    fi
  fi
  if [[ "${__dybatpho_backup_kind}" != archive ]]; then
    if [[ -n "${__dybatpho_backup_name}" ]]; then
      __dybatpho_backup_snapshots=("${__dybatpho_backup_dir}/${__dybatpho_backup_name}"-*.snapshot)
    else
      __dybatpho_backup_snapshots=("${__dybatpho_backup_dir}"/*-*.snapshot)
    fi
  fi

  local -a __dybatpho_backup_files=() __dybatpho_backup_trees=()
  for __dybatpho_backup_path in ${__dybatpho_backup_archives[@]+"${__dybatpho_backup_archives[@]}"}; do
    dybatpho::is file "${__dybatpho_backup_path}" || continue
    __dybatpho_backup_files+=("${__dybatpho_backup_path}")
  done
  for __dybatpho_backup_path in ${__dybatpho_backup_snapshots[@]+"${__dybatpho_backup_snapshots[@]}"}; do
    __dybatpho_backup_is_snapshot "${__dybatpho_backup_path}" || continue
    __dybatpho_backup_trees+=("${__dybatpho_backup_path}")
  done

  # Order both kinds together by sort key rather than trusting the glob. The
  # glob compares whole names under the caller's collation, which gets the
  # same-second suffix wrong: `-1.` against `.` flips between collations, so
  # `snap-<stamp>-1` could count as older than `snap-<stamp>`, and `-10` sorts
  # before `-2` under every collation. The keys compare byte by byte.
  local LC_ALL=C
  local -a __dybatpho_backup_sorted=() __dybatpho_backup_keys=()
  local __dybatpho_backup_key __dybatpho_backup_at
  for __dybatpho_backup_path in \
    ${__dybatpho_backup_files[@]+"${__dybatpho_backup_files[@]}"} \
    ${__dybatpho_backup_trees[@]+"${__dybatpho_backup_trees[@]}"}; do
    __dybatpho_backup_sort_key_into __dybatpho_backup_key "${__dybatpho_backup_path}"
    __dybatpho_backup_at="${#__dybatpho_backup_sorted[@]}"
    while ((__dybatpho_backup_at > 0)) \
      && [[ "${__dybatpho_backup_keys[__dybatpho_backup_at - 1]}" > "${__dybatpho_backup_key}" ]]; do
      __dybatpho_backup_sorted[__dybatpho_backup_at]="${__dybatpho_backup_sorted[__dybatpho_backup_at - 1]}"
      __dybatpho_backup_keys[__dybatpho_backup_at]="${__dybatpho_backup_keys[__dybatpho_backup_at - 1]}"
      __dybatpho_backup_at=$((__dybatpho_backup_at - 1))
    done
    __dybatpho_backup_sorted[__dybatpho_backup_at]="${__dybatpho_backup_path}"
    __dybatpho_backup_keys[__dybatpho_backup_at]="${__dybatpho_backup_key}"
  done

  __dybatpho_backup_at=$((${#__dybatpho_backup_sorted[@]} - 1))
  for (( ; __dybatpho_backup_at >= 0; __dybatpho_backup_at--)); do
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
# @description Fingerprint a snapshot tree into a named variable.
#   Every entry is recorded as its kind, its path, and what identifies its
#   content -- a file's checksum, a link's target -- in bytewise path order,
#   and the record is hashed with the sidecar algorithm. The record is
#   NUL-separated, so a name holding a newline cannot be mistaken for two.
#   Modification times and permissions are left out: a hard-linked file shares
#   them with every snapshot that links it, so they are not the snapshot's own.
# @arg $1 string Name of the variable receiving the checksum
# @arg $2 string Snapshot directory
# @set The named variable
# @internal
#######################################
function __dybatpho_backup_tree_hash_into {
  local -n __dybatpho_backup_hash_ref="$1"
  local __dybatpho_backup_tree="$2"
  local __dybatpho_backup_entry __dybatpho_backup_full __dybatpho_backup_kind __dybatpho_backup_payload
  local __dybatpho_backup_algorithm="${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM}"

  # Not a `__dybatpho`-prefixed name: `dybatpho::create_temp` refuses one.
  local dybatpho_backup_manifest
  dybatpho::create_temp dybatpho_backup_manifest ".manifest" "backup"

  while IFS= read -r -d '' __dybatpho_backup_entry; do
    [[ "${__dybatpho_backup_entry}" != . ]] || continue
    __dybatpho_backup_entry="${__dybatpho_backup_entry#./}"
    __dybatpho_backup_full="${__dybatpho_backup_tree}/${__dybatpho_backup_entry}"
    __dybatpho_backup_payload=""
    if [[ -L "${__dybatpho_backup_full}" ]]; then
      __dybatpho_backup_kind="symlink"
      __dybatpho_backup_payload="$(readlink -- "${__dybatpho_backup_full}")"
    elif [[ -d "${__dybatpho_backup_full}" ]]; then
      __dybatpho_backup_kind="directory"
    else
      __dybatpho_backup_kind="file"
      __dybatpho_backup_payload="$(dybatpho::file_hash "${__dybatpho_backup_full}" "${__dybatpho_backup_algorithm}")"
    fi
    printf '%s\0%s\0%s\0' "${__dybatpho_backup_kind}" "${__dybatpho_backup_entry}" \
      "${__dybatpho_backup_payload}" >> "${dybatpho_backup_manifest}"
  done < <(cd -- "${__dybatpho_backup_tree}" && find . -print0 | LC_ALL=C sort -z) # kcov(skip)

  __dybatpho_backup_hash_ref="$(dybatpho::file_hash "${dybatpho_backup_manifest}" "${__dybatpho_backup_algorithm}")"
}

#######################################
# @description Copy a source into a snapshot directory, hard-linking every
#   file that is unchanged since the previous snapshot instead of copying it.
#   `rsync --link-dest` does the work when it is installed. Otherwise the
#   source is walked here: a regular file whose content and mode match the
#   previous snapshot's is linked to it, any other file is copied with its
#   mode and times, links are recreated, and directories get their mode once
#   everything inside them is written, so a read-only directory can still be
#   filled. Special files -- FIFOs, sockets, devices -- are skipped on both
#   paths, as `rsync --no-D` skips them.
# @arg $1 string Absolute source path, with no trailing slash
# @arg $2 string Absolute snapshot directory being filled
# @arg $3 string Absolute path of the previous snapshot, or empty for none
# @exitcode 0 The source was copied
# @exitcode 1 A file could not be read or written
# @internal
#######################################
function __dybatpho_backup_link_copy {
  local source="$1" partial="$2" previous="${3-}"
  local base
  base="$(dybatpho::path_basename "${source}")"

  if dybatpho::is command rsync; then
    local -a link=()
    [[ -z "${previous}" ]] || link=("--link-dest=${previous}")
    # `rsync` reports each special file it skips on stdout, which would land
    # in the path `dybatpho::backup_create` prints; its errors stay on stderr.
    rsync -a --no-D ${link[@]+"${link[@]}"} -- "${source}" "${partial}/" > /dev/null
    return
  fi

  local entry from to old mode target from_mode old_mode linked
  local -a directories=() entries=(.)
  if [[ -d "${source}" && ! -L "${source}" ]]; then
    entries=()
    while IFS= read -r -d '' entry; do
      entries+=("${entry}")
    done < <(cd -- "${source}" && find . -print0) # kcov(skip)
  fi

  for entry in "${entries[@]}"; do
    if [[ "${entry}" == . ]]; then
      from="${source}"
      to="${partial}/${base}"
      old="${previous:+${previous}/${base}}"
    else
      entry="${entry#./}"
      from="${source}/${entry}"
      to="${partial}/${base}/${entry}"
      old="${previous:+${previous}/${base}/${entry}}"
    fi

    if [[ -L "${from}" ]]; then
      target="$(readlink -- "${from}")" || return 1
      ln -s -- "${target}" "${to}" || return 1
    elif [[ -d "${from}" ]]; then
      mkdir -p -- "${to}" || return 1
      directories+=("${from}" "${to}")
    elif [[ -f "${from}" ]]; then
      linked=0
      if [[ -n "${old}" && -f "${old}" && ! -L "${old}" ]] && cmp -s -- "${from}" "${old}"; then
        from_mode="$(__dybatpho_file_stat mode "${from}")" || from_mode=""
        old_mode="$(__dybatpho_file_stat mode "${old}")" || old_mode=""
        # A link can still fail -- the link count of a file shared by many
        # snapshots has a ceiling on some filesystems -- and a copy is then
        # the correct, if larger, answer.
        if [[ -n "${from_mode}" && "${from_mode}" == "${old_mode}" ]] \
          && ln -- "${old}" "${to}" 2> /dev/null; then
          linked=1
        fi
      fi
      ((linked)) || cp -p -- "${from}" "${to}" || return 1
    fi
  done

  # Deepest first, so a read-only parent is locked only after its children.
  local at=$((${#directories[@]} - 2))
  for (( ; at >= 0; at -= 2)); do
    mode="$(__dybatpho_file_stat mode "${directories[${at}]}")" || continue
    chmod "${mode}" "${directories[$((at + 1))]}"
  done
}

#######################################
# @description Take an incremental snapshot: a directory holding a copy of the
#   source, whose unchanged files are hard links into the newest earlier
#   snapshot of the same name.
#   The snapshot is filled under a hidden temporary name in the destination
#   and renamed into place, and its sidecar records the fingerprint
#   `dybatpho::backup_verify` checks.
# @arg $1 string Source path
# @arg $2 string Destination directory, already created
# @arg $3 string Backup name
# @arg $4 string Timestamp for the name
# @stdout Path of the snapshot that was created
# @internal
#######################################
function __dybatpho_backup_snapshot {
  local source="$1" destination="$2" name="$3" stamp="$4"
  local caller="dybatpho::backup_create"

  # Absolute paths throughout: `rsync` reads `host:path` in an argument as a
  # remote location, and an absolute path is never read that way.
  local source_dir base
  source_dir="$(dybatpho::path_dirname "${source}")"
  source_dir="$(cd -- "${source_dir}" && pwd -P)"
  base="$(dybatpho::path_basename "${source}")"
  source="${source_dir%/}/${base}"
  destination="$(cd -- "${destination}" && pwd -P)"

  local final="${destination}/${name}-${stamp}.snapshot"
  local suffix=1
  while dybatpho::is exist "${final}"; do
    final="${destination}/${name}-${stamp}-${suffix}.snapshot"
    suffix=$((suffix + 1))
  done

  local -a previous=()
  __dybatpho_backup_collect_into previous "${destination}" "${name}" snapshot
  local link_dest=""
  ((${#previous[@]} == 0)) || link_dest="${previous[0]}"

  local partial="${destination}/.${name}-${stamp}.$$.partial.snapshot"
  mkdir -- "${partial}"
  # "dybatpho::backup_create --incremental leaves nothing behind when a file
  # cannot be read" covers these two lines. `dybatpho::die` exits, so that test
  # uses `run`, which clears the trap kcov instruments through.
  if ! __dybatpho_backup_link_copy "${source}" "${partial}" "${link_dest}"; then
    rm -rf -- "${partial}"                                     # kcov(skip)
    dybatpho::die "${caller}: Could not snapshot: ${source}" # kcov(skip)
  fi

  local checksum
  __dybatpho_backup_tree_hash_into checksum "${partial}"

  mv -- "${partial}" "${final}"
  printf '%s  %s\n' "${checksum}" "$(dybatpho::path_basename "${final}")" \
    > "$(__dybatpho_backup_sidecar "${final}")"

  printf '%s\n' "${final}"
}

#######################################
# @description Take a timestamped backup of a file or directory.
#   The archive is written under a temporary name in the destination and
#   renamed into place, so nothing half-written is ever left looking complete.
#   A checksum sidecar is written beside it.
#
#   With `--incremental`, the backup is a directory named
#   `<name>-<UTC timestamp>.snapshot` instead of an archive: a plain copy of
#   the source in which every file unchanged since the newest earlier snapshot
#   of the same name is a hard link to that snapshot's copy, so a nightly run
#   costs only what changed. `rsync --link-dest` is used when installed, and a
#   walk in Bash otherwise. Pruning a snapshot never touches another one: a
#   hard-linked file lives on until the last snapshot naming it is removed.
#   Files are shared, so a snapshot is read and restored, never edited in
#   place. Special files are skipped, and the sidecar holds a fingerprint of
#   the tree -- each entry's path, kind, and checksum or link target.
# @arg $1 string Option `--incremental`/`-i` to take a hard-linked snapshot directory
# @arg $2 string File or directory to back up
# @arg $3 string Destination directory, created when missing
# @arg $4 string Optional name for the backup, default is the source's base name
# @stdout Path of the archive or snapshot that was created
# @exitcode 0 The backup was taken
# @exitcode 1 The source does not exist, or the backup could not be written
# @example
#   archive="$(dybatpho::backup_create /etc/nginx /var/backups)"
#   snapshot="$(dybatpho::backup_create --incremental /srv/www /var/backups www)"
#######################################
function dybatpho::backup_create {
  local incremental=0
  if [[ "${1-}" == "--incremental" || "${1-}" == "-i" ]]; then
    incremental=1
    shift
  fi

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
  if ((incremental)); then
    __dybatpho_backup_snapshot "${source}" "${destination}" "${name}" "${stamp}"
    return
  fi

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
#   Archives and incremental snapshots are listed together, in the order they
#   were taken.
# @arg $1 string Directory holding the backups
# @arg $2 string Optional backup name to match, default is every name
# @stdout One archive or snapshot path per line, newest first
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
# @stdout Path of the newest archive or snapshot
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
#   An incremental snapshot is checked by recomputing the fingerprint of its
#   tree, so a file changed, added, or removed inside it is caught.
# @arg $1 string Backup archive or snapshot path
# @exitcode 0 The archive matches its sidecar
# @exitcode 1 The backup is missing, has no sidecar, or does not match it
# @example
#   dybatpho::backup_verify "${archive}" || dybatpho::die "Corrupted backup"
#######################################
function dybatpho::backup_verify {
  local archive
  dybatpho::expect_args archive -- "$@"

  dybatpho::is file "${archive}" || __dybatpho_backup_is_snapshot "${archive}" \
    || dybatpho::die "${FUNCNAME[0]}: No such backup: ${archive}"

  local sidecar
  sidecar="$(__dybatpho_backup_sidecar "${archive}")"
  dybatpho::is file "${sidecar}" \
    || dybatpho::die "${FUNCNAME[0]}: No checksum sidecar beside: ${archive}"

  local recorded actual
  read -r recorded _ < "${sidecar}"
  if __dybatpho_backup_is_snapshot "${archive}"; then
    __dybatpho_backup_tree_hash_into actual "${archive}"
  else
    actual="$(dybatpho::file_hash "${archive}" "${DYBATPHO_BACKUP_CHECKSUM_ALGORITHM}")"
  fi

  if [[ "${recorded}" != "${actual}" ]]; then
    dybatpho::error "${FUNCNAME[0]}: ${archive} does not match its sidecar"
    dybatpho::error "recorded ${recorded}, found ${actual}"
    return 1
  fi
  return 0
}

#######################################
# @description Find the one entry a backup holds, into a named variable.
#   An archive or snapshot holds the source under its own name, so a
#   directory source is reached through that entry; anything else -- a single
#   file, or a backup that does not hold exactly one entry -- is read from the
#   directory itself.
# @arg $1 string Name of the variable receiving the path
# @arg $2 string Directory holding the extracted or snapshotted entry
# @set The named variable
# @internal
#######################################
function __dybatpho_backup_entry_root_into {
  local -n __dybatpho_backup_entry_ref="$1"
  local __dybatpho_backup_holder="$2" __dybatpho_backup_item
  local -a __dybatpho_backup_items=()

  while IFS= read -r -d '' __dybatpho_backup_item; do
    __dybatpho_backup_items+=("${__dybatpho_backup_item}")
  done < <(find "${__dybatpho_backup_holder}" -mindepth 1 -maxdepth 1 -print0) # kcov(skip)

  if ((${#__dybatpho_backup_items[@]} == 1)) \
    && [[ -d "${__dybatpho_backup_items[0]}" && ! -L "${__dybatpho_backup_items[0]}" ]]; then
    __dybatpho_backup_entry_ref="${__dybatpho_backup_items[0]}"
  else
    __dybatpho_backup_entry_ref="${__dybatpho_backup_holder}"
  fi
}

#######################################
# @description Copy a verified snapshot's entry into a target directory.
# @arg $1 string `--force`, or empty to confirm an overwrite
# @arg $2 string Snapshot directory
# @arg $3 string Target directory, already created
# @exitcode 0 The snapshot was restored
# @exitcode 1 The overwrite was declined
# @internal
#######################################
function __dybatpho_backup_restore_snapshot {
  local force="$1" snapshot="$2" target="$3"
  # `dybatpho::confirm` reads `DYBATPHO_FORCE` itself when not forced here.
  local approve=false
  [[ -z "${force}" ]] || approve=true

  local target_path
  target_path="$(dybatpho::assert_safe_path "${target}" "destination")" || return $?

  local entry
  local -a entries=()
  while IFS= read -r -d '' entry; do
    entries+=("${entry}")
  done < <(find "${snapshot}" -mindepth 1 -maxdepth 1 -print0) # kcov(skip)
  ((${#entries[@]} == 1)) \
    || dybatpho::die "dybatpho::backup_restore: Expected one entry in snapshot: ${snapshot}"
  entry="${entries[0]}"

  local landing
  landing="${target_path%/}/$(dybatpho::path_basename "${entry}")"
  if [[ -e "${landing}" || -L "${landing}" ]] \
    && ! __dybatpho_safety_approve "${approve}" "Overwrite ${landing} from ${snapshot}?"; then
    dybatpho::warn "Aborted restore of ${snapshot}"
    return 1
  fi

  if [[ -d "${entry}" && ! -L "${entry}" ]]; then
    dybatpho::dry_run mkdir -p -- "${landing}"
    dybatpho::dry_run cp -R -p -- "${entry}/." "${landing}/"
  else
    dybatpho::dry_run cp -P -p -- "${entry}" "${target_path%/}/"
  fi
}

#######################################
# @description Restore a backup into a target directory.
#   The checksum is verified first, and the extraction goes through
#   `dybatpho::safe_extract`, so an archive whose entries would land outside
#   the target is refused and an overwrite is confirmed.
#
#   A snapshot is restored the same way: verified, then its one entry is
#   copied into the target -- `<target>/<source name>`, as an archive
#   extracts -- after confirming when that entry already exists there. The
#   copy holds plain files, so editing it never reaches the snapshot.
# @arg $1 string Option `--force`/`-f` to skip the overwrite confirmation
# @arg $2 string Backup archive or snapshot path
# @arg $3 string Target directory, created when missing
# @exitcode 0 The backup was restored
# @exitcode 1 The backup fails its checksum, the overwrite is declined, or an entry escapes the target
# @env DRY_RUN string When true-like, report the extraction or copy instead of performing it
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

  if __dybatpho_backup_is_snapshot "${archive}"; then
    __dybatpho_backup_restore_snapshot "${force}" "${archive}" "${target}"
    return
  fi

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

  # `--recursive` because a snapshot is a directory. Removing one never
  # reaches another: a file hard-linked between snapshots lives on until the
  # last snapshot naming it is gone.
  if [[ -n "${force}" ]]; then
    dybatpho::safe_rm "${force}" --recursive -- "${doomed[@]}"
    return
  fi
  dybatpho::safe_rm --recursive -- "${doomed[@]}"
}

#######################################
# @description Resolve one side of a backup comparison to a directory to walk,
#   into a named variable.
#   A snapshot directory, or a path ending in the backup extension, is a
#   backup: it must pass its checksum, and an archive must hold no entry that
#   escapes before it is extracted into a temporary directory; a snapshot is
#   read in place. A backup holds one top-level entry, the source it was taken
#   from, so a directory source is compared from inside that entry and a
#   single-file source from the directory holding it. A live directory is
#   walked where it is, and a live file is copied into a temporary directory
#   of its own so it lines up with a single-file backup.
# @arg $1 string Name of the variable receiving the directory
# @arg $2 string Backup archive or snapshot, or a live file or directory
# @set The named variable
# @exitcode 0 The side was resolved
# @exitcode 2 Stop the script when the side is missing, fails its checksum, or is unsafe to extract
# @internal
#######################################
function __dybatpho_backup_root_into {
  local -n __dybatpho_backup_root_ref="$1"
  local __dybatpho_backup_side="$2"
  local caller="dybatpho::backup_diff"

  # Not a `__dybatpho`-prefixed name: `dybatpho::create_temp` refuses one.
  local dybatpho_backup_scratch

  if __dybatpho_backup_is_snapshot "${__dybatpho_backup_side}"; then
    dybatpho::is file "$(__dybatpho_backup_sidecar "${__dybatpho_backup_side}")" \
      || dybatpho::die "${caller}: No checksum sidecar beside: ${__dybatpho_backup_side}" 2
    dybatpho::backup_verify "${__dybatpho_backup_side}" \
      || dybatpho::die "${caller}: Refusing to compare a backup that fails its checksum" 2
    __dybatpho_backup_entry_root_into __dybatpho_backup_root_ref "${__dybatpho_backup_side}"
    return 0
  fi

  if [[ "${__dybatpho_backup_side}" == *".${DYBATPHO_BACKUP_EXTENSION}" ]] \
    && dybatpho::is file "${__dybatpho_backup_side}"; then
    local sidecar
    sidecar="$(__dybatpho_backup_sidecar "${__dybatpho_backup_side}")"
    dybatpho::is file "${sidecar}" \
      || dybatpho::die "${caller}: No checksum sidecar beside: ${__dybatpho_backup_side}" 2
    dybatpho::backup_verify "${__dybatpho_backup_side}" \
      || dybatpho::die "${caller}: Refusing to compare a backup that fails its checksum" 2
    dybatpho::archive_is_safe "${__dybatpho_backup_side}" \
      || dybatpho::die "${caller}: Refusing to extract an entry outside the scratch directory" 2

    dybatpho::create_temp dybatpho_backup_scratch "/" "backup-diff"
    dybatpho::archive_extract "${__dybatpho_backup_side}" "${dybatpho_backup_scratch}"

    __dybatpho_backup_entry_root_into __dybatpho_backup_root_ref "${dybatpho_backup_scratch}"
    return 0
  fi

  if dybatpho::is dir "${__dybatpho_backup_side}"; then
    __dybatpho_backup_root_ref="${__dybatpho_backup_side}"
    return 0
  fi

  dybatpho::is exist "${__dybatpho_backup_side}" || dybatpho::is link "${__dybatpho_backup_side}" \
    || dybatpho::die "${caller}: Nothing to compare at: ${__dybatpho_backup_side}" 2

  dybatpho::create_temp dybatpho_backup_scratch "/" "backup-diff"
  cp -P -p -- "${__dybatpho_backup_side}" "${dybatpho_backup_scratch}/"
  __dybatpho_backup_root_ref="${dybatpho_backup_scratch}"
}

#######################################
# @description Show what changed between two backups, or between a backup and
#   the live data it was taken from.
#   Each side is a backup archive, an incremental snapshot, or a live file or
#   directory. A backup is checked against its sidecar before anything is read
#   from it, and an archive is extracted into a temporary directory that is
#   removed when the shell exits; nothing in the destination or the source is
#   written. The two sides are then
#   compared with `dybatpho::diff_dir`, so the records, the summary and the
#   exit code are the ones it prints: `+` for what the second side added, `-`
#   for what it no longer has, `~` for a rewritten file, `!` for a change of
#   kind.
#
#   A backup holds its source under the source's own name, and that name is
#   not compared: a directory backup is compared from inside it, so the older
#   backup of `/etc/nginx` lines up with the live `/etc/nginx` or with a copy
#   restored somewhere else.
# @arg $1 string Options, then the older side
# @arg $2 string The newer side
# @opt --summary, -s Print one `+A -R ~M` line instead of the records
# @opt --null, -z Terminate each record with NUL instead of a newline
# @stdout The records or the summary `dybatpho::diff_dir` prints
# @exitcode 0 The two sides hold the same entries with the same content
# @exitcode 1 They differ
# @exitcode 2 A side is missing, fails its checksum, or holds an entry that escapes
# @example
#   dybatpho::backup_diff "$(dybatpho::backup_latest /var/backups nginx)" /etc/nginx
#   mapfile -t backups < <(dybatpho::backup_list /var/backups nginx)
#   dybatpho::backup_diff --summary "${backups[1]}" "${backups[0]}"
#######################################
function dybatpho::backup_diff {
  local -a options=()
  while (($#)); do
    case "$1" in
      --summary | -s | --null | -z) options+=("$1") ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
    shift
  done

  local older newer
  dybatpho::expect_args older newer -- "$@"

  local older_root newer_root
  __dybatpho_backup_root_into older_root "${older}"
  __dybatpho_backup_root_into newer_root "${newer}"

  dybatpho::diff_dir ${options[@]+"${options[@]}"} -- "${older_root}" "${newer_root}"
}
