# Feature Specification: Text Block Utilities

**Feature Branch**: `[reverse-spec-text]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/text.sh"

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

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a helper that prefixes every line in a text block.
- **FR-002**: The indent helper MUST accept stdin when the input argument is `-`.
- **FR-003**: The module MUST provide a helper that removes shared leading indentation from non-empty lines.
- **FR-004**: The module MUST provide a helper that strips ANSI escape sequences from text.
- **FR-005**: The module MUST provide a helper that prefixes non-empty lines as bullet items.
- **FR-006**: The module MUST provide a helper that aligns delimited text blocks into plain columns.

### Key Entities *(include if feature involves data)*

- **Text Block**: A multi-line string passed as a direct argument or through stdin.
- **Indent Prefix**: The string prepended to each rendered line.
- **ANSI Escape Sequence**: Terminal control bytes such as color styling codes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can format or normalize multi-line text without inlining custom loops.
- **SC-002**: Heredoc-like content can be dedented cleanly before output.
- **SC-003**: Colored console output can be converted to plain text for reuse.

## Integration Tests *(mandatory)*

- **IT-001**: Indent a multi-line block with a custom prefix.
- **IT-002**: Dedent a block with shared leading spaces.
- **IT-003**: Strip ANSI escape sequences from a colored block.
- **IT-004**: Read a text block from stdin and indent it.
- **IT-005**: Convert a text block into a bullet list.
- **IT-006**: Align delimited text into columns with a custom gap.

## Acceptance Criteria *(mandatory)*

1. Output-oriented helpers print focused text suitable for command substitution or direct console output.
2. The module keeps multi-line formatting behavior deterministic for tests and docs.
