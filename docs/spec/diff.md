# Feature Specification: Text and Structured Diffing

**Feature Branch**: `[spec-diff]`
**Status**: Implemented
**Input**: Existing source analysis: `src/diff.sh`, `docs/diff.md`, `test/diff.bats`, and `example/diff_ops.sh`

## Problem Statement *(mandatory)*

Showing a user what changed is something scripts keep doing and keep doing differently. One shells out to `diff` with its own flags, another to `jq`, and `dybatpho::assert_snapshot` dumped whatever `diff -u` printed, uncolored and unlike every other message the library produces. Comparing two directory trees -- a release against the last one, a backup against the live data -- is the same problem again, solved with `diff -r`, whose output differs between GNU, BSD and BusyBox and which follows symbolic links into whatever they point at. Two problems sit underneath that: `diff --color` is GNU-only, so a script that wants colored output cannot simply ask for it, and a line diff of JSON or YAML reports reformatting and key reordering as changes, burying the one value that actually moved.

## Business Value *(mandatory)*

- One place decides how a comparison is rendered, so a snapshot failure and a config preview read alike.
- Colored output works on GNU, BSD and BusyBox, because the coloring is done here rather than asked of `diff`.
- A structured comparison answers "which keys changed" instead of "which lines moved".
- A tree comparison answers "which entries were added, removed, rewritten or retyped" the same way on every platform, without following links.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Show a change before applying it (Priority: P1)

As a script author, I want a colored unified diff between two texts so that a user can see what a change would do before it is written.

**Independent Test**: Compare two files and verify the unified diff, the labels, and the exit code.

**Acceptance Scenarios**:

1. **Given** two differing texts, **When** they are compared, **Then** a unified diff is printed and the call reports a difference
2. **Given** two identical texts, **When** they are compared, **Then** nothing is printed and the call succeeds
3. **Given** labels for the sides, **When** the diff is printed, **Then** the header carries those labels rather than file paths
4. **Given** literal text rather than a file, **When** it is compared, **Then** the header names the side `a` or `b`, not the temporary file it went through
5. **Given** color is turned on, **When** the diff is printed, **Then** additions, removals and hunk headers each carry their own color

---

### User Story 2 - Report a change in one line (Priority: P2)

As a script author, I want a one-line summary of a comparison so that a log entry or a pull request comment can carry it.

**Independent Test**: Summarize a known comparison and verify the three counts.

**Acceptance Scenarios**:

1. **Given** two differing texts, **When** they are summarized, **Then** the output counts added lines, removed lines and hunks
2. **Given** two identical texts, **When** they are summarized, **Then** the counts are zero and the call succeeds

---

### User Story 3 - Compare documents by key (Priority: P1)

As an operator, I want JSON and YAML compared structurally so that reordering or reformatting a document is not reported as a change.

**Independent Test**: Compare two documents that differ only in key order, then two that differ in one value, and verify what each reports.

**Acceptance Scenarios**:

1. **Given** two documents differing only in key order or formatting, **When** they are compared, **Then** nothing is reported
2. **Given** a key added, removed, or given a new value, **When** the documents are compared, **Then** each is reported on its own line with its path
3. **Given** an array, **When** the documents are compared, **Then** the paths walk into it by index
4. **Given** a key whose value is `null`, **When** it is removed, **Then** the removal is reported rather than passed over
5. **Given** two YAML documents whose quoting style differs, **When** they are compared, **Then** nothing is reported

---

### User Story 4 - Read a snapshot failure (Priority: P2)

As a test author, I want a snapshot mismatch rendered the way every other comparison is, so that a failing test reads like the rest of the library's output.

**Independent Test**: Fail a snapshot assertion and verify the diff it prints.

**Acceptance Scenarios**:

1. **Given** a snapshot that does not match, **When** the assertion fails, **Then** the difference is rendered through this module with `snapshot` and `actual` as the labels
2. **Given** captured text that happens to name an existing file, **When** the assertion fails, **Then** the text is compared, not that file's contents

---

### User Story 5 - Compare two directory trees (Priority: P2)

As an operator, I want two directory trees compared entry by entry so that I can see what a release, a sync or a restore would add, remove or rewrite.

**Independent Test**: Build two trees that differ by an added, removed, rewritten, relinked and retyped entry, compare them, and verify each record, the summary and the exit code.

**Acceptance Scenarios**:

1. **Given** two trees, **When** they are compared, **Then** each added, removed, modified and retyped entry is printed once, sorted bytewise by path, and the call reports a difference
2. **Given** two trees whose files hold the same content with different modification times, **When** they are compared, **Then** nothing is printed and the call succeeds
3. **Given** `--summary`, **When** the trees are compared, **Then** one `+A -R ~M` line is printed in the shape of the text summary, with a change of kind counted in `~`
4. **Given** a removed directory, **When** the trees are compared, **Then** the directory is reported with a trailing `/` together with every entry inside it
5. **Given** a name holding a newline, tab, carriage return or backslash, **When** the trees are compared, **Then** it is printed with C escapes on one line, and `--null` prints it raw, NUL-terminated
6. **Given** a symbolic link, **When** the trees are compared, **Then** its target is compared and it is never followed
7. **Given** a side that is not a directory, **When** the trees are compared, **Then** the call stops with exit code 2

### Example Workflow

```bash
. dybatpho/init.sh --modules diff

# Preview a config change, and act only when there is one.
if ! dybatpho::diff_text /etc/app.conf "${rendered}" current proposed; then
  dybatpho::info "Change: $(dybatpho::diff_summary /etc/app.conf "${rendered}" || true)"
  dybatpho::confirm "Apply it?" || exit 0
fi

# Which keys moved between two states, ignoring how they were written.
dybatpho::diff_json state-before.json state-after.json
dybatpho::diff_yaml deploy-old.yaml deploy-new.yaml

# What a release changes on disk, and the same in one line.
dybatpho::diff_dir ./release-1.2 ./release-1.3 || true
dybatpho::diff_dir --summary ./release-1.2 ./release-1.3 || true
```

## Edge Cases

- A subdirectory one of the trees holds but the process cannot enter.
- A side is a file, `-` for stdin, or the text itself, and text may look like a path.
- The two sides are identical, or one is empty.
- A JSON value is `null`, an empty object, or an empty array.
- The whole document is a scalar rather than an object.
- Output is not a terminal, or `NO_COLOR` is set.
- `jq` is not installed and a structured comparison is asked for.
- A tree holds an empty directory, a symbolic link to a large tree, a FIFO, or a name with spaces, a newline or a backslash.
- A tree root is given with a trailing slash or through a symbolic link.
- An entry is a file in one tree and a directory in the other.
- A side of a tree comparison is missing or is a file.
- A YAML comparison is asked for by a script that loaded `diff` without `json`.
- A JSON or YAML side does not parse, or is empty, and the other side is broken the same way.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each side of a comparison MUST accept a file path, `-` for stdin, or the text itself.
- **FR-002**: A text comparison MUST print a unified diff and MUST return `diff`'s own exit code: zero when identical, one when not.
- **FR-003**: The comparison MUST use only unified-diff behavior that GNU, BSD and BusyBox share.
- **FR-004**: Coloring MUST be applied by this module rather than by `diff --color`, which is not portable.
- **FR-005**: Coloring MUST follow `DYBATPHO_DIFF_COLOR` when set, and otherwise `NO_COLOR` and whether stdout is a terminal.
- **FR-006**: Additions, removals, hunk headers and file headers MUST each be colored distinctly.
- **FR-007**: A caller-supplied label MUST replace the path in the diff header.
- **FR-008**: A side given as literal text MUST be labelled `a` or `b` rather than by its temporary file.
- **FR-009**: The amount of context MUST be configurable through `DYBATPHO_DIFF_CONTEXT`.
- **FR-010**: The summary MUST report added lines, removed lines and hunks, and MUST return the same exit code as the comparison.
- **FR-011**: Structured comparison MUST compare values by path, so key order and formatting are not differences.
- **FR-012**: A leaf MUST be a scalar or an empty container, so a `null` value and an empty object are compared rather than skipped.
- **FR-013**: Array elements MUST be addressed by index in the path.
- **FR-014**: A difference MUST be reported as added, removed, or changed, each on its own line with its path, colored by kind.
- **FR-015**: A structured comparison MUST report when `jq` is not installed, with exit code 127.
- **FR-016**: A YAML comparison MUST convert both documents to JSON before comparing them.
- **FR-017**: `dybatpho::assert_snapshot` MUST render a mismatch through this module, comparing the captured text rather than any file that text may name.

- **FR-018**: A tree comparison MUST report every entry present in only one tree as added or removed, a file whose content differs or a link whose target differs as modified, and an entry whose kind differs as retyped with both kinds named.
- **FR-019**: Files MUST be compared by content, so modification time, permissions and ownership are not differences.
- **FR-020**: Symbolic links MUST be compared by target and MUST NOT be followed; a root given through a link or with a trailing slash MUST be walked as the directory it names.
- **FR-021**: Records MUST be sorted bytewise by path, an added or removed directory MUST carry a trailing `/`, and the entries inside it MUST be reported as well.
- **FR-022**: A path holding a backslash, newline, tab or carriage return MUST be printed with C escapes in line output, and `--null` MUST print every record raw and NUL-terminated, without color.
- **FR-023**: `--summary` MUST print one `+A -R ~M` line in place of the records, counting a change of kind in `~`.
- **FR-024**: A tree comparison MUST return zero when the trees match, one when they differ, and MUST stop with two when either side is not a directory.
- **FR-025**: Tree records MUST follow the same coloring decision as the other comparisons, with additions, removals, modifications and changes of kind colored distinctly.
- **FR-026**: Loading the module MUST NOT load `json`. The YAML comparison MUST stop before reading its input with `<function> needs the json module, load it with: dybatpho::load json` when `json` is not loaded; the text, JSON and tree comparisons MUST work without it.
- **FR-027**: A JSON or YAML comparison MUST stop with exit code `2` and `<function>: Not valid JSON: the <first|second> document` (or `Not valid YAML`) when either side does not parse or holds no value, and MUST NOT print a difference or report the documents as identical.
- **FR-028**: `diff_dir` MUST stop with exit 2 when either tree cannot be read in full, rather than compare the part it could list.

### Key Entities *(include if feature involves data)*

- **Side**: One of the two things compared: a file, stdin, or literal text.
- **Leaf**: A scalar or empty container in a structured document, addressed by its path.
- **Hunk**: One contiguous region of change in a unified diff.
- **Entry**: A path under a tree root, with its kind: `file`, `directory`, `symlink`, or `other`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script previews a change with colored output on GNU, BSD and BusyBox alike.
- **SC-002**: A reordered or reformatted document reports no change.
- **SC-003**: A snapshot failure reads like the library's other comparisons.
- **SC-004**: A change can be reduced to one line for a log or a pull request comment.
- **SC-005**: Two directory trees compare to the same records on GNU, BSD and BusyBox, whatever their names contain.

## Integration Tests *(mandatory)*

- **IT-001**: Print a unified diff with caller-supplied labels, and report the difference.
- **IT-002**: Print nothing and succeed for identical input.
- **IT-003**: Compare literal text and label the sides `a` and `b`.
- **IT-004**: Read one side from stdin.
- **IT-005**: Color additions, removals and hunk headers when asked to.
- **IT-006**: Emit no color when `NO_COLOR` is set and the choice is left to detection.
- **IT-007**: Honor `DYBATPHO_DIFF_CONTEXT`.
- **IT-008**: Summarize added lines, removed lines and hunks, and report zero for identical input.
- **IT-009**: Report keys added, removed and changed, with their paths.
- **IT-010**: Report no change for a reordered or reformatted document.
- **IT-011**: Walk into arrays by index.
- **IT-012**: Color each kind of structural change distinctly.
- **IT-013**: Report the removal of a key whose value is `null`.
- **IT-014**: Report a change to an empty container, and compare two scalar documents.
- **IT-015**: Compare YAML by key, treating quoting style as no change.
- **IT-016**: Report when `jq` is not installed.
- **IT-017**: Render a snapshot mismatch through this module, with `snapshot` and `actual` as labels.
- **IT-018**: Compare captured text that names an existing file as text.
- **IT-019**: Report added, removed, modified and retyped entries of two trees, sorted by path.
- **IT-020**: Report nothing for trees with the same content, including copies with fresh modification times.
- **IT-021**: Summarize a tree comparison as `+A -R ~M`, and report zero counts for identical trees.
- **IT-022**: Report a removed directory with everything inside it, and an empty directory.
- **IT-023**: Escape a name holding a newline or a backslash, and print it raw with `--null`.
- **IT-024**: Compare links by target without following them.
- **IT-025**: Walk a root given with a trailing slash or through a link.
- **IT-026**: Compare a special file by kind alone.
- **IT-027**: Color each kind of tree change distinctly.
- **IT-028**: Stop with exit code 2 when a side is not a directory.
- **IT-029**: Take the directories after an end-of-options marker.
- **IT-030**: Verify a script that loads `diff` alone can summarize text, that its YAML comparison stops with the message naming `json`, and that once it loads `json` the same call reports the changed key.
- **IT-031**: Verify two broken JSON documents, a broken second document, an empty document, and broken YAML on either side all stop with exit code `2` and name the side, printing nothing on stdout.
- **IT-032**: Compare two trees whose differing subdirectories cannot be entered, and stop with exit 2.

## Acceptance Criteria *(mandatory)*

1. The text and tree comparisons need no external command beyond `diff`, `find`, `cmp` and `sort`; only the structured comparisons ask for `jq`, and YAML additionally for `yq`.
2. Exit codes make the helpers usable in a conditional, so a script can act only when something changed.
3. Structured comparison is built on one flattening filter rather than one per backend, which is why it requires `jq` rather than accepting either JSON tool.
