# Feature Specification: Release Automation

**Feature Branch**: `[feature-release]`
**Status**: Implemented
**Input**: `src/release.sh`, `test/release.bats`, `docs/release.md`, `example/release_ops.sh`, and `dybatpho::git_latest_tag` in `src/git.sh`

## Problem Statement *(mandatory)*

Cutting a release is a sequence every project rebuilds by hand: read the last tag, decide whether the change is a patch or a breaking one, write the changelog entry, package the build output once per platform under a name users recognize, and publish checksums and a signature so a download can be verified. Done by hand it is slow and easy to get wrong in ways that matter — a version that understates a breaking change, a changelog that omits a fix, an artifact nobody can verify.

## Business Value *(mandatory)*

- Make the version follow from the commits rather than from someone's memory.
- Produce release notes that match what actually changed.
- Publish artifacts under the naming convention consumers already know.
- Let a consumer verify a download with tools they already have.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Let the commits decide the version (Priority: P1)

As a maintainer, I want the next version derived from the commits since the last tag so that a breaking change cannot ship as a patch.

**Why this priority**: Every other step needs the version, and an understated version is the mistake with the longest tail.

**Independent Test**: Tag a repository, add commits of each kind, and verify the version each combination produces.

**Acceptance Scenarios**:

1. **Given** only `fix` commits since the tag, **When** the next version is computed, **Then** the patch moves
2. **Given** a `feat` commit in the range, **When** the next version is computed, **Then** the minor moves and a later `fix` does not weaken it
3. **Given** a commit marked breaking, by `!` in the subject or a `BREAKING CHANGE:` footer, **Then** the major moves
4. **Given** only commits that do not call for a release, such as `docs` or `chore`, **Then** the caller is told there is nothing to release
5. **Given** a repository with no tag yet, **When** the next version is computed, **Then** the whole history is read, including the first commit

---

### User Story 2 - Write the changelog from the commits (Priority: P1)

As a maintainer, I want the release notes generated from the same commits so that the notes and the version cannot disagree.

**Why this priority**: A changelog written separately drifts from the code it describes.

**Independent Test**: Generate an entry for a range containing each kind of commit and verify the grouping and what is left out.

**Acceptance Scenarios**:

1. **Given** commits of several kinds, **When** the entry is rendered, **Then** breaking changes, features, and fixes appear under their own headings
2. **Given** a commit with a scope, **When** it is rendered, **Then** the scope is kept and the type prefix is dropped
3. **Given** commits that do not call for a release, **When** the entry is rendered, **Then** they are left out
4. **Given** a section with no commits, **When** the entry is rendered, **Then** that heading is omitted

---

### User Story 3 - Package per platform (Priority: P1)

As a maintainer, I want one artifact per platform, named the way consumers expect, so that a download is unambiguous.

**Why this priority**: The name is the contract: it tells a user, and an installer script, which file to fetch.

**Independent Test**: Package the same build output for several platforms and verify the names and contents.

**Acceptance Scenarios**:

1. **Given** a name, version, operating system, and architecture, **When** the artifact name is built, **Then** it follows the `name_version_os_arch` layout with the extension that platform expects
2. **Given** a Windows target, **When** the artifact is named, **Then** it is a zip rather than a tarball
3. **Given** no platform is supplied, **When** the artifact is named, **Then** the running platform is used
4. **Given** an output directory that does not exist, **When** an artifact is packaged, **Then** the directory is created

---

### User Story 4 - Publish checksums and a signature (Priority: P1)

As a consumer, I want checksums and a signature so that I can tell an authentic download from a corrupted or substituted one.

**Why this priority**: Artifacts distributed without them cannot be verified at all.

**Independent Test**: Produce a checksum file for a directory of artifacts, verify it with the system tool, and sign it.

**Acceptance Scenarios**:

1. **Given** a directory of artifacts, **When** checksums are written, **Then** the file is in the format the system checksum tool verifies
2. **Given** file names in the checksum file, **When** a consumer verifies from that directory, **Then** the names resolve, because they carry no directory component
3. **Given** a directory that already holds a checksum file or signatures, **When** checksums are written again, **Then** those are not treated as release content
4. **Given** a signing command, **When** a file is signed, **Then** the signature path is produced and printed
5. **Given** no signing command is configured, **When** a file is signed, **Then** `gpg` produces a detached armored signature

---

### Example Workflow

```bash
. dybatpho/init.sh --modules release

if ! version="$(dybatpho::release_next_version .)"; then
  dybatpho::info "Nothing to release"
  exit 0
fi

dybatpho::release_changelog . "$(dybatpho::git_latest_tag . 'v*')" HEAD "${version}" > release-notes.md

for platform in "linux amd64" "darwin arm64"; do
  read -r goos goarch <<< "${platform}"
  dybatpho::release_package "./dist/${goos}_${goarch}" ./release mytool "${version}" "${goos}" "${goarch}"
done

sums="$(dybatpho::release_checksums ./release)"
dybatpho::release_sign "${sums}"
```

## Edge Cases

- The base or head ref of a range does not name a commit.
- A repository with no tag at all.
- A tag that is not a semantic version.
- `scripts/release.sh` is given options that contradict each other, such as `--no-push` while publishing.
- A commit subject that follows no convention, such as a merge commit.
- A breaking change declared in the footer rather than in the subject.
- A range whose commits call for no release.
- A checksum file or signature already present in the artifact directory.
- An artifact directory holding nothing to checksum.
- A signing tool that is not `gpg`.
- A file to sign, or its signature, whose path holds a space or shell syntax
  such as `$(...)` or `;`.
- An artifact is packaged while the `archive` module is not loaded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST classify a commit subject following Conventional Commits, and MUST treat a subject it does not recognize as one that calls for no release.
- **FR-001a**: The module MUST also report a commit's type, scope, breaking flag, and description separately, so that a caller can group by type and still know the change was breaking, and every other helper MUST derive its answer from that one parser rather than restating the convention.
- **FR-002**: A commit MUST be treated as breaking when its subject carries `!` before the colon or its message carries a `BREAKING CHANGE:` footer.
- **FR-003**: The bump for a range MUST be the strongest its commits call for, and MUST NOT be weakened by a later, lesser commit.
- **FR-004**: A range whose commits call for no release MUST report that to the caller rather than inventing a version.
- **FR-005**: The next version MUST be derived from the highest matching tag, MUST accept an explicit base, and MUST reject a base tag that is not a semantic version.
- **FR-006**: With no tag in the repository, the whole history MUST be read, including the first commit, and the version MUST start from zero.
- **FR-007**: The changelog MUST group breaking changes, features, and fixes under their own headings, keep a commit's scope, drop its type prefix, and omit both empty headings and commits that call for no release.
- **FR-008**: Artifact names MUST follow the `name_version_os_arch` layout, MUST use a zip for Windows and a tarball elsewhere, MUST drop a leading `v` from the version, and MUST default to the running platform.
- **FR-009**: Packaging MUST create the output directory when missing, MUST reject a missing source, and MUST print the artifact's path.
- **FR-010**: The checksum file MUST be in the format the system checksum tool verifies, MUST record bare file names, and MUST exclude itself and any signature in the directory.
- **FR-011**: Checksumming a directory with nothing to checksum MUST fail rather than write an empty file.
- **FR-012**: Signing MUST use `gpg` by default and MUST be redirectable to another tool through configuration, and MUST print the signature's path.
- **FR-013**: Every helper that writes MUST honor `DRY_RUN` by reporting the intended path and leaving the filesystem untouched.
- **FR-014**: The module MUST NOT contact any forge: producing files is its whole job, and publishing them stays with the caller.
- **FR-015**: `dybatpho::git_latest_tag` MUST order tags as versions rather than as strings, MUST accept a pattern, and MUST report failure when nothing matches.
- **FR-016**: Loading `release` MUST NOT load `archive`; packaging MUST stop with a message naming the `archive` module and how to load it when that module is not loaded, before it inspects the source or creates anything.
- **FR-017**: A configured signing command MUST receive the signature path and the file path as one argument each, and neither path MUST ever be read as shell syntax; the command itself is run as the project wrote it.
- **FR-018**: `scripts/release.sh` MUST refuse contradicting options -- `--version` with `--bump`, publishing with `--no-push`, `--sign` with `--no-bundle`, and `--draft` with `--no-publish` -- before it reads the commits or changes the tree, and MUST accept every documented `--bump` value.
- **FR-019**: A base or head ref that does not name a commit MUST stop `release_bump_type` and `release_changelog` with an error naming the ref, rather than being read as a range with nothing to release.
- **FR-020**: `scripts/release.sh` MUST run the documentation step from a checkout whose path contains spaces.

### Key Entities *(include if feature involves data)*

- **Release Range**: The commits between the last release and the head being released.
- **Bump**: How far the version moves, one of major, minor, or patch.
- **Artifact**: One packaged file for one platform.
- **Checksum File**: The list binding artifact names to their hashes.
- **Signature**: The detached proof over the checksum file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The version of a release follows from its commits, with no manual decision.
- **SC-002**: Release notes list every change that moved the version, and nothing else.
- **SC-003**: A consumer identifies the artifact for their platform from its name alone.
- **SC-004**: A consumer verifies a download with the checksum tool already on their system.
- **SC-005**: One signature covers every artifact of a release.

## Integration Tests *(mandatory)*

- **IT-001**: Classify subjects of every kind, including a breaking marker, an upper-case type, and a subject following no convention.
- **IT-001a**: Parse subjects into their parts, including an absent scope, a footer-declared breaking change, and a subject following no convention.
- **IT-002**: Verify the bump for ranges containing patches, features, a later patch after a feature, and a breaking change.
- **IT-003**: Verify that a `BREAKING CHANGE:` footer produces a major bump.
- **IT-004**: Verify that a range of only non-releasing commits reports nothing to release.
- **IT-005**: Verify the next version from the latest tag, from an explicit base tag, and with no tag at all.
- **IT-006**: Reject a base tag that is not a semantic version.
- **IT-007**: Render a changelog and verify grouping, scope handling, omitted headings, and excluded commits.
- **IT-008**: Verify artifact names for Linux, macOS, and Windows, with and without a leading `v`, and with the platform defaulted.
- **IT-009**: Package for several platforms and verify the files, their contents, and that the output directory is created.
- **IT-010**: Write a checksum file and verify it with the system checksum tool, including that names carry no directory component.
- **IT-011**: Verify that an existing checksum file and signatures are excluded, and that rerunning does not fold them in.
- **IT-012**: Reject checksumming an empty or missing directory.
- **IT-013**: Sign with a configured command, with an explicit signature path, and reject a missing file.
- **IT-014**: Run every writing helper under `DRY_RUN` and verify nothing is created.
- **IT-015**: Verify that the latest-tag lookup orders by version, honors a pattern, and fails when nothing matches.
- **IT-016**: In a child shell that loaded only `release`, verify packaging stops with the message naming `archive` and creates nothing, and packages once `archive` is loaded.
- **IT-017**: Sign a file whose path holds a space and a command substitution with a configured command that takes an option of its own, and verify the command receives the option and the two paths as three arguments and the substitution never runs.
- **IT-018**: Run `scripts/release.sh --dry-run` with each contradicting pair of options and verify each is refused with its own message before the release header, and that `--bump minor` parses.
- **IT-019**: From a script, call `release_bump_type` and `release_changelog` with an unknown base, an unknown head, and an unknown head without a base, and verify the script stops with `Unknown git commit` each time.
- **IT-020**: Release from a copy of the repository under a directory with a space in its name, and find the docs regenerated and the release committed.

## Acceptance Criteria *(mandatory)*

1. The version, the notes, and the artifacts of a release all derive from the same commits.
2. Published artifacts can be verified by a consumer without special tooling.
3. The module produces files and never publishes them, so credentials stay with the caller.
