# Feature Specification: Text Block Utilities

**Feature Branch**: `[reverse-spec-text]`
**Status**: Implemented
**Input**: Existing source analysis: `src/text.sh`, `docs/text.md`, `test/text.bats`, and `example/text_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts often need to reformat multi-line text blocks for logs, heredocs, templates, and reports, but repeating ad-hoc indentation, dedentation, and ANSI-cleanup snippets makes scripts noisy and inconsistent.

## Business Value *(mandatory)*

- Centralize common multi-line text formatting helpers in one reusable module.
- Keep scripts readable when they need to shape output for terminals or files.
- Reduce one-off `sed` or manual loop logic for text preparation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Indent text blocks consistently (Priority: P1)

As a script author, I want to prefix every line in a text block so that nested logs, quoted output, and generated snippets are easy to format.

**Independent Test**: Indent a two-line block with the default or custom prefix and verify that every line is prefixed.

**Acceptance Scenarios**:

1. **Given** a multi-line text block, **When** the indent helper runs, **Then** every line is prefixed with the chosen indent string
2. **Given** `-` as the input, **When** the helper reads stdin, **Then** it indents the piped text block

---

### User Story 2 - Remove shared indentation from heredoc-like content (Priority: P1)

As a maintainer, I want to strip common leading indentation from a text block so that indented shell source can still emit clean left-aligned content.

**Independent Test**: Dedent a block with shared leading spaces and verify the common indent is removed while relative inner indentation stays intact.

**Acceptance Scenarios**:

1. **Given** several lines that share a leading indent, **When** the dedent helper runs, **Then** that shared indent is removed
2. **Given** a line that is more deeply indented than the others, **When** the helper runs, **Then** its relative extra indentation remains

---

### User Story 3 - Normalize terminal text before reuse (Priority: P2)

As a script author, I want to remove ANSI escape sequences from text so that colored console output can be reused in plain-text files or comparisons.

**Independent Test**: Strip a colored two-line string and verify only the printable text remains.

**Acceptance Scenarios**:

1. **Given** text containing ANSI color codes, **When** the strip helper runs, **Then** the visible text remains and the escape sequences are removed

---

### User Story 4 - Render compact text lists and columns (Priority: P2)

As a script author, I want helpers for bullet lists and lightweight aligned columns so that reports and summaries remain readable without switching to a full table renderer every time.

**Independent Test**: Convert a short list into bullets and align a small delimited block into plain columns.

**Acceptance Scenarios**:

1. **Given** a multi-line list, **When** the bullet helper runs, **Then** every non-empty line is prefixed with the chosen bullet marker
2. **Given** delimited text rows, **When** the column helper runs, **Then** cells are padded into aligned plain columns with the requested gap

---

### User Story 5 - Frame, center, number, and shorten blocks for display (Priority: P2)

As a script author, I want to put a border around a summary, center a banner, number the lines of a quoted file, and cut a long log short so that console reports stay readable without hand-measuring every line.

**Independent Test**: Box a block with a title, center lines within a width, number a block from a custom start, and truncate a block to two lines, then compare each output exactly.

**Acceptance Scenarios**:

1. **Given** a multi-line block and a title, **When** the box helper runs, **Then** the block is framed by a border as wide as its widest line or title, with the title set into the top edge
2. **Given** a border style of `single`, `double`, `rounded`, `heavy`, or `ascii`, **When** the box helper runs, **Then** the border uses that style's characters, and an unknown style is rejected
3. **Given** lines that contain ANSI color sequences or wide characters, **When** the box or center helper runs, **Then** padding follows the visible width rather than the byte or character count, measured the way `table` measures its cells
4. **Given** a width, **When** the center helper runs, **Then** each line is padded on the left only, blank lines stay blank, and a line wider than the width is unchanged
5. **Given** a block and a first line number, **When** the number helper runs, **Then** every line, blank ones included, carries its number right-aligned to the widest number
6. **Given** a block longer than a count, **When** the truncate helper runs, **Then** the first `count` lines are printed followed by a marker naming how many were left out, and a block that fits is printed unchanged

### Example Workflow

```bash
notes="$(cat <<'EOF'
      Fixed the retry budget
      Documented the new flags
EOF
)"

dybatpho::text_bullet_list "$(dybatpho::text_dedent "${notes}")" "*"
dybatpho::text_indent "$(dybatpho::text_dedent "${notes}")" "    "

# Strip colors before storing captured terminal output.
./build.sh 2>&1 | dybatpho::text_strip_ansi - > build.log
dybatpho::text_columns "name|status" "|" 4

# Frame a summary, then show only the head of a long log.
dybatpho::text_box "$(git diff --shortstat)" "Changes"
dybatpho::text_center "Release 1.2.0" 60
dybatpho::text_number_lines "$(sed -n '40,45p' script.sh)" 40
./build.sh 2>&1 | dybatpho::text_truncate_lines - 20 "(+{count} lines in build.log)"
```

## Edge Cases

- Empty input, blank lines, or input supplied through stdin with `-`.
- Lines have different indentation depths.
- ANSI sequences occur alongside ordinary text.
- A bullet marker, delimiter, or gap is omitted or empty.
- `text_columns` is called while the `table` module it draws through is not loaded.
- A box title is wider than every line, or the input is empty.
- A line contains ANSI sequences or wide characters, whose bytes, characters, and columns all differ.
- A line is wider than the centering width, or the width is zero or not a number.
- A first line number has leading zeros, such as `09`.
- A block already fits within the truncation count, or the count is zero.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a helper that prefixes every line in a text block.
- **FR-002**: The indent helper MUST accept stdin when the input argument is `-`.
- **FR-003**: The module MUST provide a helper that removes shared leading indentation from non-empty lines.
- **FR-004**: The module MUST provide a helper that strips ANSI escape sequences from text.
- **FR-005**: The module MUST provide a helper that prefixes non-empty lines as bullet items.
- **FR-006**: The module MUST provide a helper that aligns delimited text blocks into plain columns.
- **FR-007**: The module MUST provide a helper that frames a text block in a border sized to its widest line or optional title, with `single`, `double`, `rounded`, `heavy`, and `ascii` styles, and MUST fail on an unknown style.
- **FR-008**: Width-sensitive helpers MUST measure a line without its ANSI escape sequences, MUST count a wide character as the two columns it occupies with the core measurement, whether or not `screen` is loaded, and MUST measure exactly as `table` measures its cells.
- **FR-009**: The module MUST provide a helper that centers each line within an explicit width or, when none is given, the terminal width, padding on the left only, and MUST fail on a width that is not a positive integer.
- **FR-010**: The module MUST provide a helper that prefixes every line with its number, starting from an optional first number, right-aligned to the widest number, with an optional separator, and MUST fail on a start that is not a non-negative integer.
- **FR-011**: The module MUST provide a helper that prints the first `count` lines of a block followed by a marker naming how many lines were left out, MUST print a block that fits unchanged and without a marker, MUST replace `{count}` in a custom marker, and MUST fail on a count that is not a non-negative integer.
- **FR-012**: Every helper MUST accept stdin when the input argument is `-`.
- **FR-013**: Loading `text` MUST NOT load `table`; the column helper MUST stop with a message naming the `table` module and how to load it when that module is not loaded, before reading its input.

### Key Entities *(include if feature involves data)*

- **Text Block**: A multi-line string passed as a direct argument or through stdin.
- **Indent Prefix**: The string prepended to each rendered line.
- **ANSI Escape Sequence**: Terminal control bytes such as color styling codes.
- **Visible Width**: The number of terminal columns a line occupies once ANSI sequences are removed.
- **Border Style**: The named set of corner, edge, and side characters a box is drawn with.
- **Truncation Marker**: The line printed after a shortened block, with `{count}` standing for the lines left out.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can format or normalize multi-line text without inlining custom loops.
- **SC-002**: Heredoc-like content can be dedented cleanly before output.
- **SC-003**: Colored console output can be converted to plain text for reuse.
- **SC-004**: Boxed and centered output keeps straight edges for colored text and for wide characters.
- **SC-005**: Long blocks can be numbered or shortened for display without external tools such as `nl` or `head`.

## Integration Tests *(mandatory)*

- **IT-001**: Indent a multi-line block with a custom prefix.
- **IT-002**: Dedent a block with shared leading spaces.
- **IT-003**: Strip ANSI escape sequences from a colored block.
- **IT-004**: Read a text block from stdin and indent it.
- **IT-005**: Convert a text block into a bullet list.
- **IT-006**: Align delimited text into columns with a custom gap.
- **IT-007**: Box a block sized to its widest line, and a short block widened to fit its title.
- **IT-008**: Box with every border style, read from stdin, handle empty input, and reject an unknown style.
- **IT-009**: Box colored text by visible width, and wide characters by their columns with and without `screen` loaded.
- **IT-010**: Center lines within a width, keep blank and over-wide lines, and default to the terminal width.
- **IT-011**: Center colored and wide text by visible width, and reject an invalid width.
- **IT-012**: Number lines including blanks, from a custom start with leading zeros and a custom separator, and reject an invalid start.
- **IT-013**: Truncate a block with the default singular and plural markers, print a fitting block unchanged, fill a custom marker with a zero count, and reject an invalid count.
- **IT-014**: In a child shell that loaded only `text`, stop the column helper with the message naming `table`, then align the same block once `table` is loaded.

## Acceptance Criteria *(mandatory)*

1. Output-oriented helpers print focused text suitable for command substitution or direct console output.
2. The module keeps multi-line formatting behavior deterministic for tests and docs.
3. Invalid styles, widths, start numbers, and counts fail with a clear error instead of producing malformed output.
4. The module does not load or require `screen`; its measurement is the core one, so the result does not depend on which modules are loaded.
