#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file release.sh
# @brief Cut a release of dybatpho: stamp the tree, tag it, and publish it
# @description
#   One command takes the repository from "the changelog has an `Unreleased`
#   section" to "the tag, the forge release, and the artifacts exist". The
#   steps are the ones a release of this library actually needs, in the order
#   that keeps them consistent:
#
#   1. Refuse to start on a dirty tree, a detached head, a branch other than the
#      default one, or a tag that already exists.
#   2. Resolve the version — `--version` wins, then `--bump`, then the commits
#      since the last tag through `dybatpho::release_next_version`.
#   3. Stamp `VERSION`, promote `## [Unreleased]` in `CHANGELOG.md` to the new
#      version with today's date, open a fresh empty `Unreleased`, and rewrite
#      the comparison links at the bottom of the file.
#   4. Regenerate `docs/` so the published docs match the tagged source.
#   5. Commit `chore(release): v<version>` and tag it, annotated with the
#      changelog entry so `git show v<version>` carries the release notes.
#   6. Build the artifacts from the tagged tree: the all-modules bundle, a
#      checksum file, and a detached signature when `--sign` is given.
#   7. Push the branch and the tag, then create the release with the changelog
#      entry as its body and the artifacts attached.
#
#   Publishing goes through `src/forge.sh`, which reads the forge from the Git
#   remote. That keeps the release step working on GitHub, GitHub Enterprise
#   and GitLab alike, and replaces the `gh` CLI with a token: set `GITHUB_TOKEN`
#   (or `GITLAB_TOKEN`), or take one from an authenticated CLI with
#   `GITHUB_TOKEN=$(gh auth token)`. The token is checked before any local step
#   runs, so a missing one cannot be discovered after the tree is tagged.
#
#   The changelog is the source of the release notes, never a generated commit
#   list: this project writes entries by hand, and a release that paraphrased
#   them would publish worse notes than the ones already in the repository.
#   `dybatpho::release_next_version` still reads the commits, because deciding
#   *how far* the version moves is exactly what Conventional Commits answers.
#
#   Nothing is pushed before the local steps succeed, so a failed run leaves a
#   repository that `git reset --hard` and `git tag -d` undo completely. Run
#   `--dry-run` first: it performs every check and every computation, prints the
#   version, the notes, and each command it would run, and writes nothing.
#
# @example
#   scripts/release.sh --dry-run            # what would happen, changing nothing
#   scripts/release.sh                      # version from the commits
#   scripts/release.sh --version 3.0.0      # or name it
#   scripts/release.sh --bump minor --sign  # bump one level and sign the sums
#   scripts/release.sh --no-publish         # tag and push, publish by hand later
#
# @env DYBATPHO_FORCE string When true-like, answer every confirmation with yes
# @env DRY_RUN string When true-like, report every step and change nothing
# @env DYBATPHO_RELEASE_GPG_KEY string Key `--sign` signs the checksum file with
#
# @env GITHUB_TOKEN string Token the release is published with, see `src/forge.sh`
#
# @see
#   - `src/release.sh`
#   - `src/forge.sh`
#   - `CHANGELOG.md`
#   - `scripts/bundle.sh`
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules "cli release safety date forge"

dybatpho::register_common_handlers

CHANGELOG_FILE="${DYBATPHO_DIR}/CHANGELOG.md"
VERSION_FILE="${DYBATPHO_DIR}/VERSION"
DIST_DIR="${DYBATPHO_DIR}/dist"

#######################################
# @description Validator for `--version`, so a typo is rejected before anything
#   in the tree has been touched.
# @arg $1 string Value to check
# @exitcode 0 The value is a valid SemVer version
# @exitcode 1 Otherwise
#######################################
function __dybatpho_release_is_version {
  dybatpho::semver_valid "${1#v}"
}

#######################################
# @description Print the version currently stamped in `VERSION`.
# @noargs
# @stdout The stamped version, without a leading `v`, or empty when unreadable
#######################################
function __dybatpho_release_current_version {
  local _version=""
  [[ -r "${VERSION_FILE}" ]] && { read -r _version < "${VERSION_FILE}" || true; }
  printf '%s\n' "${_version#v}"
}

#######################################
# @description Print the repository's HTTPS URL, whichever protocol the remote
#   is configured with, because the changelog links and the release page are
#   always browser URLs.
# @arg $1 string Remote name
# @stdout Repository URL without a trailing `.git`
# @exitcode 1 Stop the script when the remote has no URL
#######################################
function __dybatpho_release_repo_url {
  local _remote
  dybatpho::expect_args _remote -- "$@"
  # `forge` already normalises `git@host:path`, `ssh://git@host/path` and
  # `https://host/path` to the same host and project, so this is the one place
  # that knowledge has to live.
  local forge_repo
  forge_repo=$(dybatpho::forge_repo "${_remote}" "${DYBATPHO_DIR}")
  local forge_host
  forge_host=$(dybatpho::forge_host "${_remote}" "${DYBATPHO_DIR}")
  printf 'https://%s/%s\n' \
    "${forge_host}" \
    "${forge_repo}"
}

#######################################
# @description Rewrite the changelog for the release and extract its notes.
#   `## [Unreleased]` becomes `## [<version>] - <date>`, a fresh empty
#   `Unreleased` heading takes its place, and the link definitions at the bottom
#   gain the new version while `Unreleased` starts comparing from it.
# @arg $1 string Version being released
# @arg $2 string Release date, `YYYY-MM-DD`
# @arg $3 string Previous version, empty when this is the first release
# @arg $4 string Repository URL used for the link definitions
# @arg $5 path File the rewritten changelog is written to
# @arg $6 path File the release notes are written to
# @exitcode 1 Stop the script when the `Unreleased` section is missing or empty
#######################################
function __dybatpho_release_render_changelog {
  local _version _date _previous _url _changelog _notes
  dybatpho::expect_args _version _date _previous _url _changelog _notes -- "$@"

  awk -v version="${_version}" -v date="${_date}" -v previous="${_previous}" \
    -v url="${_url}" -v notes="${_notes}" '
    function flush_body(   i, start, stop) {
      # Trim the blank lines the section is padded with, so the notes file holds
      # the entry alone and the rewritten file keeps one blank line either side.
      start = 1; stop = count
      while (start <= stop && body[start] ~ /^[[:space:]]*$/) start++
      while (stop >= start && body[stop] ~ /^[[:space:]]*$/) stop--
      if (stop < start) { empty = 1; return }
      print ""
      print "## [" version "] - " date
      print ""
      for (i = start; i <= stop; i++) {
        print body[i]
        print body[i] > notes
      }
      print ""
    }
    /^## \[Unreleased\]/ && !seen {
      seen = 1
      capturing = 1
      print "## [Unreleased]"
      next
    }
    capturing && (/^## \[/ || /^\[Unreleased\]:/) {
      capturing = 0
      flush_body()
    }
    capturing { body[++count] = $0; next }
    /^\[Unreleased\]:/ {
      print "[Unreleased]: " url "/compare/v" version "...HEAD"
      if (previous == "") {
        print "[" version "]: " url "/releases/tag/v" version
      } else {
        print "[" version "]: " url "/compare/v" previous "...v" version
      }
      linked = 1
      next
    }
    { print }
    END {
      if (capturing) flush_body()
      if (!seen) exit 3
      if (empty || !count) exit 4
      if (!linked) {
        print ""
        print "[Unreleased]: " url "/compare/v" version "...HEAD"
        if (previous == "") {
          print "[" version "]: " url "/releases/tag/v" version
        } else {
          print "[" version "]: " url "/compare/v" previous "...v" version
        }
      }
    }
  ' "${CHANGELOG_FILE}" > "${_changelog}" || {
    local _status=$?
    ((_status == 3)) && dybatpho::die "CHANGELOG.md has no '## [Unreleased]' section"
    ((_status == 4)) && dybatpho::die "CHANGELOG.md has an empty '## [Unreleased]' section: nothing to release"
    dybatpho::die "Cannot rewrite CHANGELOG.md"
  }
}

#######################################
# @description Report whether the `Unreleased` section declares a breaking
#   change. The commit log and the changelog can disagree — a commit written
#   without a `!` or a `BREAKING CHANGE:` footer still describes a break once
#   the entry for it says **BREAKING** — and publishing the smaller of the two
#   answers is the one mistake a release cannot take back.
# @noargs
# @exitcode 0 The section marks a breaking change
# @exitcode 1 Otherwise
#######################################
function __dybatpho_release_changelog_breaking {
  # `exit` runs the END block, so the answer is carried in a flag rather than in
  # the status of the rule that found it.
  awk '
    /^## \[Unreleased\]/ { capturing = 1; next }
    capturing && (/^## \[/ || /^\[Unreleased\]:/) { exit }
    capturing && /BREAKING/ { breaking = 1; exit }
    END { exit breaking ? 0 : 1 }
  ' "${CHANGELOG_FILE}"
}

#######################################
# @description Refuse to release from a tree that would produce a release nobody
#   can reproduce: uncommitted work, the wrong branch, or a tag that exists.
# @arg $1 string Tag the release will carry
# @exitcode 1 Stop the script when the repository isn't in a releasable state
#######################################
function __dybatpho_release_preflight {
  local _tag _branch _default
  dybatpho::expect_args _tag -- "$@"

  dybatpho::git_is_clean "${DYBATPHO_DIR}" \
    || dybatpho::die "Worktree has uncommitted changes; commit or stash them first"

  _branch="$(dybatpho::git_branch "${DYBATPHO_DIR}")"
  _default="$(dybatpho::git_default_branch "${DYBATPHO_DIR}")"
  if [[ "${_branch}" != "${_default}" ]]; then
    dybatpho::confirm "Release from '${_branch}' rather than '${_default}'?" \
      || dybatpho::die "Release cancelled"
  fi

  git -C "${DYBATPHO_DIR}" rev-parse -q --verify "refs/tags/${_tag}" > /dev/null 2>&1 \
    && dybatpho::die "Tag ${_tag} already exists"
  return 0
}

#######################################
# @description Resolve the version to release from the options and the commits.
# @arg $1 string Value of `--version`, empty when not given
# @arg $2 string Value of `--bump`, empty when not given
# @arg $3 string Currently stamped version
# @stdout The version to release, without a leading `v`
# @exitcode 1 Stop the script when no version can be resolved or it doesn't move forward
#######################################
function __dybatpho_release_resolve_version {
  local _requested _bump _current _next
  dybatpho::expect_args _requested _bump _current -- "$@"

  if [[ -n "${_requested}" ]]; then
    _next="${_requested#v}"
  elif [[ -n "${_bump}" ]]; then
    _next="$(dybatpho::semver_bump "${_current}" "${_bump}")" \
      || dybatpho::die "Cannot bump ${_current} by ${_bump}"
  else
    _next="$(dybatpho::release_next_version "${DYBATPHO_DIR}")" \
      || dybatpho::die "No commit since the last tag calls for a release; pass --version to release anyway"
    # The changelog overrules the commits when it is the stricter of the two:
    # an entry marked BREAKING is a major release whatever the subjects said.
    # shellcheck disable=SC2310 # the changelog check answers yes or no
    if __dybatpho_release_changelog_breaking \
      && [[ -n "${_current}" ]] \
      && [[ "${_next%%.*}" == "${_current%%.*}" ]]; then
      _next="$(dybatpho::semver_bump "${_current}" major)"
      dybatpho::warn "CHANGELOG.md marks a BREAKING change: releasing ${_next} rather than what the commits asked for"
    fi
  fi

  if [[ -n "${_current}" ]] \
    && [[ "$(dybatpho::semver_compare "${_next}" "${_current}")" != "1" ]]; then
    dybatpho::die "Version ${_next} doesn't move forward from the stamped ${_current}"
  fi
  printf '%s\n' "${_next}"
}

#######################################
# @description Build what the release publishes: the all-modules bundle, the
#   checksum file covering it, and a detached signature when asked for one.
#   The bundle is built after the release commit, so the version it carries is
#   the tagged one rather than a dirty working tree.
# @arg $1 string Version being released
# @arg $2 string `true` to sign the checksum file
# @stdout One artifact path per line
#######################################
function __dybatpho_release_artifacts {
  local _version _sign _bundle _sums
  dybatpho::expect_args _version _sign -- "$@"

  dybatpho::ensure_dir "${DIST_DIR}" > /dev/null
  _bundle="${DIST_DIR}/dybatpho-${_version}.bundle.sh"
  # Standard output here is the artifact list the caller reads, so progress and
  # whatever the bundler prints both belong on standard error.
  dybatpho::progress "Building ${_bundle}" >&2
  DYBATPHO_FORCE=true "${SCRIPT_DIR}/bundle.sh" --modules all --output "${_bundle}" >&2

  # DRY_RUN leaves nothing on disk for the checksum step to read, and a checksum
  # over files that weren't built would be a lie rather than a rehearsal.
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    printf '%s\n' "${_bundle}"
    return 0
  fi

  _sums="$(dybatpho::release_checksums "${DIST_DIR}")"
  printf '%s\n%s\n' "${_bundle}" "${_sums}"
  if dybatpho::is true "${_sign}"; then
    dybatpho::release_sign "${_sums}"
  fi
}

#######################################
# @description Run the release.
# @noargs
# @exitcode 0 The release was cut, and published unless told not to
# @exitcode 1 A precondition failed or a step did not complete
#######################################
function __dybatpho_release_run {
  local _version _tag _previous _date _url _changelog _notes
  local -a _artifacts=()

  dybatpho::require "git"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::is true "${DOCS}" && dybatpho::require "gawk"
  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${PUBLISH}" && dybatpho::is false "${DRY_RUN}"; then
    # Resolved before any local step runs: a missing token should not be found
    # out after the tree is stamped, committed and tagged.
    dybatpho::require "curl"
    dybatpho::forge_token > /dev/null \
      || dybatpho::die \
        "No token to publish with. Set GITHUB_TOKEN, or export it from the CLI: GITHUB_TOKEN=\$(gh auth token)"
  fi

  local _current
  _current="$(__dybatpho_release_current_version)"
  # shellcheck disable=SC2154 # set by the option spec of this script
  _version="$(__dybatpho_release_resolve_version "${RELEASE_VERSION}" "${BUMP}" "${_current}")"
  _tag="v${_version}"
  __dybatpho_release_preflight "${_tag}"

  # shellcheck disable=SC2154 # set by the option spec of this script
  _previous="$(dybatpho::git_latest_tag "${DYBATPHO_DIR}" "${DYBATPHO_RELEASE_TAG_PATTERN}" || true)"
  _previous="${_previous#v}"
  _date="$(dybatpho::date_today)"
  # shellcheck disable=SC2154 # set by the option spec of this script
  _url="$(__dybatpho_release_repo_url "${REMOTE}")"

  dybatpho::header "Releasing ${_tag}"
  dybatpho::info "Previous release: ${_previous:-none}"
  dybatpho::info "Stamped version:  ${_current:-none}"

  dybatpho::create_temp _changelog ".md" "release-changelog"
  dybatpho::create_temp _notes ".md" "release-notes"
  __dybatpho_release_render_changelog \
    "${_version}" "${_date}" "${_previous}" "${_url}" "${_changelog}" "${_notes}"

  dybatpho::print "$(< "${_notes}")"

  dybatpho::confirm "Release ${_tag} with the entry above?" "yes" \
    || dybatpho::die "Release cancelled"

  dybatpho::progress "Stamping VERSION and CHANGELOG.md"
  printf '%s\n' "${_version}" | dybatpho::file_write_atomic "${VERSION_FILE}"
  dybatpho::file_write_atomic "${CHANGELOG_FILE}" < "${_changelog}"

  if dybatpho::is true "${DOCS}"; then
    dybatpho::progress "Regenerating docs/"
    dybatpho::dry_run "${SCRIPT_DIR}/docs.sh"
  fi

  dybatpho::progress "Committing and tagging ${_tag}"
  dybatpho::dry_run git -C "${DYBATPHO_DIR}" add -A -- \
    "${VERSION_FILE}" "${CHANGELOG_FILE}" "${DYBATPHO_DIR}/docs"
  dybatpho::dry_run git -C "${DYBATPHO_DIR}" commit -m "chore(release): ${_tag}"
  # The tag message leads with the version, so `git tag -n1` and every tool that
  # shows a tag's first line name the release rather than its first bullet.
  local _message
  dybatpho::create_temp _message ".md" "release-tag"
  {
    printf '%s\n\n' "${_tag}"
    cat "${_notes}"
  } > "${_message}"
  dybatpho::dry_run git -C "${DYBATPHO_DIR}" tag -a "${_tag}" -F "${_message}"

  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${BUNDLE}"; then
    local _artifact
    # shellcheck disable=SC2154 # set by the option spec of this script
    local release_artifacts_output
    release_artifacts_output=$(__dybatpho_release_artifacts "${_version}" "${SIGN}")
    while read -r _artifact || [[ -n "${_artifact}" ]]; do
      [[ -n "${_artifact}" ]] && _artifacts+=("${_artifact}")
    done < <(printf '%s' "${release_artifacts_output}")
  fi

  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${PUSH}"; then
    dybatpho::progress "Pushing to ${REMOTE}"
    dybatpho::dry_run git -C "${DYBATPHO_DIR}" push "${REMOTE}" HEAD
    dybatpho::dry_run git -C "${DYBATPHO_DIR}" push "${REMOTE}" "${_tag}"
  else
    dybatpho::warn "Not pushing; the release exists locally only"
  fi

  if dybatpho::is true "${PUBLISH}"; then
    if dybatpho::is false "${PUSH}"; then
      dybatpho::die "--publish needs the tag pushed; drop --no-push or pass --no-publish"
    fi
    local forge_kind
    forge_kind=$(dybatpho::forge_kind)
    dybatpho::progress "Creating the ${forge_kind} release"
    if dybatpho::is true "${DRY_RUN}"; then
      local wc
      wc=$(wc -l < "${_notes}")
      dybatpho::dry_run "forge_release_create ${_tag} with ${wc} lines of notes"
      local _artifact
      for _artifact in ${_artifacts[@]+"${_artifacts[@]}"}; do
        dybatpho::dry_run "forge_release_upload ${_tag} ${_artifact}"
      done
    else
      # shellcheck disable=SC2154 # set by the option spec of this script
      dybatpho::forge_release_create "${_tag}" "${_tag}" "$(< "${_notes}")" "${DRAFT}" > /dev/null
      local _artifact
      for _artifact in ${_artifacts[@]+"${_artifacts[@]}"}; do
        local path_basename
        path_basename=$(dybatpho::path_basename "${_artifact}")
        dybatpho::progress "Attaching ${path_basename}"
        local forge_release_upload
        forge_release_upload=$(dybatpho::forge_release_upload "${_tag}" "${_artifact}")
        dybatpho::info "${forge_release_upload}"
      done
    fi
  fi

  dybatpho::success "Released ${_tag}"
  ((${#_artifacts[@]})) && dybatpho::info "Artifacts in ${DIST_DIR}"
  dybatpho::is false "${PUBLISH}" \
    && dybatpho::info "Publish it later with dybatpho::forge_release_create and forge_release_upload"
  return 0
}

#######################################
# @description CLI specification for this script.
#######################################
# @noargs
function _spec {
  dybatpho::opts::setup "Cut a release of dybatpho: stamp, tag, and publish" RELEASE_ARGS \
    action:"__dybatpho_release_run"

  dybatpho::opts::param "Release this exact version instead of deriving one" RELEASE_VERSION --version \
    init:@empty validate:"__dybatpho_release_is_version \$OPTARG"
  dybatpho::opts::param "Move the stamped version by one level" BUMP --bump \
    init:@empty choices:"major|minor|patch"
  dybatpho::opts::param "Remote to push the branch and the tag to" REMOTE --remote \
    init:="origin"

  dybatpho::opts::flag "Sign the checksum file" SIGN --sign \
    on:true off:false init:="false"
  dybatpho::opts::flag "Create the GitHub release as a draft" DRAFT --draft \
    on:true off:false init:="false"
  # shellcheck disable=SC1083 # `--{no-}name` is dybatpho's toggle-switch syntax
  dybatpho::opts::flag "Regenerate docs/ before committing" DOCS --{no-}docs \
    on:true off:false init:="true"
  # shellcheck disable=SC1083
  dybatpho::opts::flag "Build the bundle and checksum artifacts" BUNDLE --{no-}bundle \
    on:true off:false init:="true"
  # shellcheck disable=SC1083
  dybatpho::opts::flag "Push the branch and the tag" PUSH --{no-}push \
    on:true off:false init:="true"
  # shellcheck disable=SC1083
  dybatpho::opts::flag "Create the release on the forge" PUBLISH --{no-}publish \
    on:true off:false init:="true"
  dybatpho::opts::flag "Report every step and change nothing" DRY_RUN -n --dry-run \
    on:true off:false init:="${DRY_RUN:-false}" export:true
  dybatpho::opts::flag "Answer every confirmation with yes" DYBATPHO_FORCE -y --yes \
    on:true off:false init:="${DYBATPHO_FORCE:-false}" export:true

  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

dybatpho::generate_from_spec _spec "$@"
