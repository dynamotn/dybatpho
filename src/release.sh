# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file release.sh
# @brief Utilities for cutting a release from a Git repository
# @namespace dybatpho
# @description
#   This module turns the commits since the last tag into a release: it decides
#   how far the version moves, writes the changelog entry, packages build output
#   per platform, and produces the checksums and signature a consumer needs to
#   verify what they downloaded.
#
#   Version decisions follow [Conventional Commits](https://www.conventionalcommits.org):
#   a commit marked breaking moves the major, `feat` moves the minor, `fix` and
#   `perf` move the patch, and anything else does not move the version at all.
#
#   Nothing here talks to a forge. The module produces files; pushing a tag or
#   creating a GitHub release stays with the caller, who owns those credentials.
# @see
#   - `example/release_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_RELEASE_TAG_PATTERN string Glob that release tags match, default is `v*`
DYBATPHO_RELEASE_TAG_PATTERN="${DYBATPHO_RELEASE_TAG_PATTERN:-v*}"
# @env DYBATPHO_RELEASE_CHECKSUM_ALGORITHM string Checksum algorithm for the sums file, default is `sha256`
DYBATPHO_RELEASE_CHECKSUM_ALGORITHM="${DYBATPHO_RELEASE_CHECKSUM_ALGORITHM:-sha256}"
# @env DYBATPHO_RELEASE_SIGN_CMD string Command that signs a file, receiving the signature path and the file path.
#   Default
#   signs with `gpg`
DYBATPHO_RELEASE_SIGN_CMD="${DYBATPHO_RELEASE_SIGN_CMD:-}"
# @env DYBATPHO_RELEASE_GPG_KEY string Key `gpg` signs with, default is its configured default key
DYBATPHO_RELEASE_GPG_KEY="${DYBATPHO_RELEASE_GPG_KEY:-}"

#######################################
# @description Break a commit message into the parts Conventional Commits defines.
#   `dybatpho::release_commit_type` answers only "what kind of change is this",
#   and reports a breaking change as its own kind, which loses the type. This
#   reports every part separately, so a caller can group by type and still know
#   that the change was breaking.
# @example
#   read -r type scope breaking description < <(
#     dybatpho::release_commit_parse "feat(api)!: drop the v1 endpoints" | paste -sd' ' -
#   )
#
# @example
#   dybatpho::release_commit_parse "fix: handle empty input"
#   # fix
#   #
#   # false
#   # handle empty input
#
# @arg $1 string Commit subject line
# @arg $2 string Optional commit body, searched for a `BREAKING CHANGE:` footer
# @stdout Four lines: type, scope (empty if none), `true` or `false` for
#   breaking, and the description with the type prefix removed
# @tip A subject that follows no convention reports the type `other` and keeps
#   the whole subject as its description
#######################################
function dybatpho::release_commit_parse {
  local subject body type="other" scope="" breaking="false" description
  dybatpho::expect_args subject -- "$@"
  body="${2-}"
  description="${subject}"

  # `type(scope)!: summary`, where the scope and the breaking marker are optional.
  if [[ "${subject}" =~ ^([a-zA-Z]+)(\(([^\)]*)\))?(!)?:[[:space:]]*(.*)$ ]]; then
    type="$(dybatpho::lower "${BASH_REMATCH[1]}")"
    scope="${BASH_REMATCH[3]}"
    [[ -n "${BASH_REMATCH[4]}" ]] && breaking="true"
    description="${BASH_REMATCH[5]}"
  fi

  # The convention allows a footer instead of the `!` marker, and the footer
  # lives in the body rather than in the subject.
  if [[ "${breaking}" == "false" ]] \
    && printf '%s\n' "${body}" | grep -q '^BREAKING[ -]CHANGE:'; then
    breaking="true"
  fi

  printf '%s\n%s\n%s\n%s\n' "${type}" "${scope}" "${breaking}" "${description}"
}

#######################################
# @description Classify one commit subject as Conventional Commits does.
# @example
#   dybatpho::release_commit_type "feat(api)!: drop v1 endpoints"  # breaking
#   dybatpho::release_commit_type "fix: handle empty input"        # fix
#
# @arg $1 string Commit subject line
# @stdout One of `breaking`, `feat`, `fix`, `perf`, the declared type, or `other`
#######################################
function dybatpho::release_commit_type {
  local subject parsed type breaking
  dybatpho::expect_args subject -- "$@"
  parsed="$(dybatpho::release_commit_parse "${subject}")"
  type="$(printf '%s\n' "${parsed}" | sed -n '1p')"
  breaking="$(printf '%s\n' "${parsed}" | sed -n '3p')"
  if [[ "${breaking}" == "true" ]]; then
    printf 'breaking\n'
  else
    printf '%s\n' "${type}"
  fi
}

#######################################
# @description Decide how far the version should move, from the commits in a range.
#   A commit is breaking when its subject carries `!` or its body carries a
#   `BREAKING CHANGE:` footer, which is the other spelling the convention allows.
# @example
#   bump="$(dybatpho::release_bump_type "." "v1.2.3")"
#
# @arg $1 string Repository path
# @arg $2 string Base ref, excluded from the range, or empty to read the whole history
# @arg $3 string Optional head ref, default is `HEAD`
# @stdout One of `major`, `minor`, or `patch`
# @exitcode 1 No commit in the range calls for a release
#######################################
function dybatpho::release_bump_type {
  local repo_path base_ref head_ref sha message parsed type breaking bump=""
  dybatpho::expect_args repo_path base_ref -- "$@"
  head_ref="${3:-HEAD}"

  # An empty base means nothing has been released yet. `git_commits_between`
  # excludes its base ref, which would drop the repository's first commit, so
  # that case reads the whole history instead.
  while read -r sha; do
    [[ -n "${sha}" ]] || continue
    # The whole message is read once: the breaking marker may be in the subject
    # or in a footer in the body.
    message="$(__dybatpho_git "${repo_path}" log -1 --format=%B "${sha}")"
    local printf
    printf=$(printf '%s\n' "${message}" | sed -n '1p')
    parsed="$(dybatpho::release_commit_parse \
      "${printf}" "${message}")"
    type="$(printf '%s\n' "${parsed}" | sed -n '1p')"
    breaking="$(printf '%s\n' "${parsed}" | sed -n '3p')"
    if [[ "${breaking}" == "true" ]]; then
      printf 'major\n'
      return 0
    fi
    case "${type}" in
      feat) bump="minor" ;;
      fix | perf) [[ "${bump}" == "minor" ]] || bump="patch" ;;
      *) ;;
    esac
  done < <(if [[ -n "${base_ref}" ]]; then
    dybatpho::git_commits_between "${repo_path}" "${base_ref}" "${head_ref}"
  else
    __dybatpho_git "${repo_path}" rev-list --reverse "${head_ref}"
  fi)

  [[ -n "${bump}" ]] || return 1
  printf '%s\n' "${bump}"
}

#######################################
# @description Print the version a release from these commits should carry.
# @example
#   if next="$(dybatpho::release_next_version ".")"; then
#     dybatpho::info "Next release is v${next}"
#   else
#     dybatpho::info "Nothing to release"
#   fi
#
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional base tag, default is the highest matching tag
# @arg $3 string Optional head ref, default is `HEAD`
# @env DYBATPHO_RELEASE_TAG_PATTERN string Glob that release tags match
# @stdout Next version, without a leading `v`
# @exitcode 1 No commit since the base tag calls for a release
# @tip With no tag in the repository yet, the range starts at the first commit
#   and the result is the first version the commits call for
#######################################
function dybatpho::release_next_version {
  local repo_path base_tag head_ref current bump
  repo_path="${1:-.}"
  head_ref="${3:-HEAD}"
  base_tag="${2-}"
  if [[ -z "${base_tag}" ]]; then
    base_tag="$(dybatpho::git_latest_tag "${repo_path}" "${DYBATPHO_RELEASE_TAG_PATTERN}")" || base_tag=""
  fi

  if [[ -z "${base_tag}" ]]; then
    # Nothing released yet, so the range is the whole history and the version
    # starts from zero.
    current="0.0.0"
  else
    current="${base_tag#v}"
    dybatpho::semver_valid "${current}" \
      || dybatpho::die "${FUNCNAME[0]}: Tag '${base_tag}' is not a semantic version"
  fi

  bump="$(dybatpho::release_bump_type "${repo_path}" "${base_tag}" "${head_ref}")" || return 1
  dybatpho::semver_bump "${current}" "${bump}"
}

#######################################
# @description Render the changelog entry for a range of commits.
#   Commits are grouped the way Conventional Commits names them, so the entry
#   reads as a summary of what changed rather than a list of subjects.
# @example
#   dybatpho::release_changelog "." "v1.2.3" "HEAD" "1.3.0" >> CHANGELOG.md
#
# @arg $1 string Repository path
# @arg $2 string Base ref, excluded from the range, or empty to read the whole history
# @arg $3 string Optional head ref, default is `HEAD`
# @arg $4 string Optional version for the heading, default is `Unreleased`
# @stdout Markdown section for the release
# @tip Commits of a type that does not move the version, such as `docs` or
#   `chore`, are left out: they are part of the history, not of the release notes
#######################################
function dybatpho::release_changelog {
  local repo_path base_ref head_ref version sha type scope
  local message parsed is_breaking description entry
  dybatpho::expect_args repo_path base_ref -- "$@"
  head_ref="${3:-HEAD}"
  version="${4:-Unreleased}"

  local -a breaking=() features=() fixes=()
  while read -r sha; do
    [[ -n "${sha}" ]] || continue
    message="$(__dybatpho_git "${repo_path}" log -1 --format=%B "${sha}")"
    local printf
    printf=$(printf '%s\n' "${message}" | sed -n '1p')
    parsed="$(dybatpho::release_commit_parse \
      "${printf}" "${message}")"
    type="$(printf '%s\n' "${parsed}" | sed -n '1p')"
    scope="$(printf '%s\n' "${parsed}" | sed -n '2p')"
    is_breaking="$(printf '%s\n' "${parsed}" | sed -n '3p')"
    description="$(printf '%s\n' "${parsed}" | sed -n '4p')"
    # The scope says where the change landed and is worth keeping; the type
    # prefix is dropped, because the heading already conveys it.
    entry="- ${scope:+**${scope}**: }${description}"
    if [[ "${is_breaking}" == "true" ]]; then
      breaking+=("${entry}")
      continue
    fi
    case "${type}" in
      feat) features+=("${entry}") ;;
      fix | perf) fixes+=("${entry}") ;;
      *) ;;
    esac
  done < <(if [[ -n "${base_ref}" ]]; then
    dybatpho::git_commits_between "${repo_path}" "${base_ref}" "${head_ref}"
  else
    __dybatpho_git "${repo_path}" rev-list --reverse "${head_ref}"
  fi)

  printf '## [%s]\n' "${version}"
  if ((${#breaking[@]})); then
    printf '\n### Changed\n\n'
    printf '%s\n' "${breaking[@]}"
  fi
  if ((${#features[@]})); then
    printf '\n### Added\n\n'
    printf '%s\n' "${features[@]}"
  fi
  if ((${#fixes[@]})); then
    printf '\n### Fixed\n\n'
    printf '%s\n' "${fixes[@]}"
  fi
}

#######################################
# @description Print the name a release artifact should carry for one platform.
#   The layout is the one Go release tooling established, so a consumer who has
#   seen any Go project's downloads recognizes it.
# @example
#   dybatpho::release_artifact_name mytool 1.3.0 linux amd64   # mytool_1.3.0_linux_amd64.tar.gz
#   dybatpho::release_artifact_name mytool 1.3.0 windows amd64 # mytool_1.3.0_windows_amd64.zip
#
# @arg $1 string Project name
# @arg $2 string Version, without a leading `v`
# @arg $3 string Optional operating system, default is the current one
# @arg $4 string Optional architecture, default is the current one
# @stdout Artifact file name, including the extension for that platform
#######################################
function dybatpho::release_artifact_name {
  local name version goos goarch extension
  dybatpho::expect_args name version -- "$@"
  goos="${3:-$(dybatpho::goos)}"
  goarch="${4:-$(dybatpho::goarch)}"
  # Windows users expect a zip; everything else expects a tarball.
  if [[ "${goos}" == "windows" ]]; then
    extension="zip"
  else
    extension="tar.gz"
  fi
  printf '%s_%s_%s_%s.%s\n' "${name}" "${version#v}" "${goos}" "${goarch}" "${extension}"
}

#######################################
# @description Package build output into a release artifact for one platform.
# @example
#   dybatpho::release_package ./dist/linux_amd64 ./release mytool 1.3.0 linux amd64
#
# @arg $1 string Directory or file to package
# @arg $2 string Directory the artifact is written to, created when missing
# @arg $3 string Project name
# @arg $4 string Version
# @arg $5 string Optional operating system, default is the current one
# @arg $6 string Optional architecture, default is the current one
# @stdout Path of the artifact that was created
# @env DRY_RUN string When true-like, print the path without packaging anything
# @exitcode 1 The source is missing or the archive cannot be created
#######################################
function dybatpho::release_package {
  local source output_dir name version goos goarch artifact
  dybatpho::expect_args source output_dir name version -- "$@"
  [[ -e "${source}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Source doesn't exist: ${source}"
  goos="${5:-$(dybatpho::goos)}"
  goarch="${6:-$(dybatpho::goarch)}"

  local release_artifact_name
  release_artifact_name=$(dybatpho::release_artifact_name "${name}" "${version}" "${goos}" "${goarch}")
  artifact="$(dybatpho::path_join "${output_dir}" \
    "${release_artifact_name}")"
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run "package ${source} into ${artifact}"
    printf '%s\n' "${artifact}"
    return 0
  fi
  dybatpho::ensure_dir "${output_dir}" > /dev/null
  dybatpho::archive_create "${source}" "${artifact}"
  printf '%s\n' "${artifact}"
}

#######################################
# @description Write one checksum file covering every artifact in a directory.
#   The layout is the one `sha256sum -c` reads, so a consumer verifies a
#   download with a tool they already have.
# @example
#   sums="$(dybatpho::release_checksums ./release)"
#   ( cd ./release && sha256sum -c "$(basename "${sums}")" )
#
# @arg $1 string Directory holding the artifacts
# @arg $2 string Optional output file, default is `<dir>/SHA256SUMS`
# @env DYBATPHO_RELEASE_CHECKSUM_ALGORITHM string Algorithm passed to the hash helper
# @env DRY_RUN string When true-like, print the path without writing anything
# @stdout Path of the checksum file
# @exitcode 1 The directory is missing or holds no file to checksum
# @tip The file names are recorded without a directory component, so the file
#   verifies from inside the directory it describes
#######################################
function dybatpho::release_checksums {
  local directory output entry name sums=""
  dybatpho::expect_args directory -- "$@"
  dybatpho::is dir "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Directory doesn't exist: ${directory}"
  output="${2:-$(dybatpho::path_join "${directory}" "SHA256SUMS")}"

  local -a artifacts=()
  for entry in "${directory}"/*; do
    [[ -f "${entry}" ]] || continue
    # The sums file itself and any signature beside it are not release content.
    [[ "${entry}" == "${output}" ]] && continue
    case "${entry}" in
      *.asc | *.sig | *SHA256SUMS*) continue ;;
      *) ;;
    esac
    artifacts+=("${entry}")
  done
  ((${#artifacts[@]})) \
    || dybatpho::die "${FUNCNAME[0]}: No artifact to checksum in ${directory}"

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run "checksum ${#artifacts[@]} artifacts into ${output}"
    printf '%s\n' "${output}"
    return 0
  fi

  for entry in "${artifacts[@]}"; do
    name="$(dybatpho::path_basename "${entry}")"
    sums+="$(dybatpho::file_hash "${entry}" "${DYBATPHO_RELEASE_CHECKSUM_ALGORITHM}")  ${name}"$'\n'
  done
  printf '%s' "${sums}" | dybatpho::file_write_atomic "${output}"
  printf '%s\n' "${output}"
}

#######################################
# @description Sign a file and print the signature's path.
#   Signing uses `gpg` unless `DYBATPHO_RELEASE_SIGN_CMD` names another command,
#   which lets a project sign with `minisign`, `cosign`, or anything else
#   without this module knowing about it.
# @example
#   dybatpho::release_sign ./release/SHA256SUMS
#
# @example
#   DYBATPHO_RELEASE_SIGN_CMD="minisign -S -m" dybatpho::release_sign ./release/SHA256SUMS
#
# @arg $1 string File to sign
# @arg $2 string Optional signature path, default is `<file>.asc`
# @env DYBATPHO_RELEASE_SIGN_CMD string Command receiving the signature path and then the file path
# @env DYBATPHO_RELEASE_GPG_KEY string Key `gpg` signs with
# @env DRY_RUN string When true-like, print the path without signing
# @stdout Path of the signature
# @exitcode 1 The file is missing, no signing tool is available, or signing fails
# @tip Sign the checksum file rather than every artifact: one signature then
#   covers them all, because the checksums bind their contents
#######################################
function dybatpho::release_sign {
  local path signature
  dybatpho::expect_args path -- "$@"
  dybatpho::is file "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: File doesn't exist: ${path}"
  signature="${2:-${path}.asc}"

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run "sign ${path} into ${signature}"
    printf '%s\n' "${signature}"
    return 0
  fi

  if [[ -n "${DYBATPHO_RELEASE_SIGN_CMD}" ]]; then
    # The command is a template the project owns, so it is run as written with
    # the two paths appended.
    dybatpho::dry_run "${DYBATPHO_RELEASE_SIGN_CMD} ${signature} ${path}" \
      || dybatpho::die "${FUNCNAME[0]}: Signing ${path} failed"
  else
    dybatpho::require gpg
    local -a gpg_args=(--batch --yes --armor --detach-sign --output "${signature}")
    [[ -n "${DYBATPHO_RELEASE_GPG_KEY}" ]] && gpg_args+=(--local-user "${DYBATPHO_RELEASE_GPG_KEY}")
    gpg "${gpg_args[@]}" "${path}" \
      || dybatpho::die "${FUNCNAME[0]}: Signing ${path} with gpg failed"
  fi
  printf '%s\n' "${signature}"
}
