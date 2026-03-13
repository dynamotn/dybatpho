# Feature Specification: Table Rendering Utilities

**Feature Branch**: `[reverse-spec-table]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/table.sh"

## Problem Statement *(mandatory)*

Shell scripts frequently generate small reports and summaries, but aligning columns or drawing readable text tables by hand quickly becomes repetitive and error-prone.

## Business Value *(mandatory)*

- Provide lightweight table rendering for common script-generated summaries.
- Keep status output and generated documentation snippets readable in terminals and Markdown.
- Reduce repeated alignment logic across scripts and examples.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print aligned columns in the terminal (Priority: P1)

As a script author, I want delimited rows rendered into aligned columns so that quick summaries remain readable without manual padding math.

**Independent Test**: Render several rows with uneven cell widths and verify that columns align.

**Acceptance Scenarios**:

1. **Given** delimited row text, **When** the plain-table helper runs, **Then** each column is padded to the width of the widest cell in that column

---

### User Story 2 - Emit boxed terminal tables (Priority: P1)

As a maintainer, I want a boxed Unicode table format so that console reports can stand out visually without hand-crafted borders.

**Independent Test**: Render a small table and verify top, middle, and bottom border lines plus aligned body rows.

**Acceptance Scenarios**:

1. **Given** a first row that acts as a header, **When** the boxed-table helper runs, **Then** it inserts a separator after the header row

---

### User Story 3 - Emit Markdown tables for docs and comments (Priority: P2)

As a script author, I want to generate Markdown tables from the same row data so that reports can be pasted into README files, issues, or PR comments.

**Independent Test**: Render a small data set as Markdown and verify header, separator, and body rows.

**Acceptance Scenarios**:

1. **Given** delimited row data, **When** the Markdown helper runs, **Then** it emits a valid Markdown table using the first row as the header
2. **Given** a custom delimiter, **When** the helper runs, **Then** it splits cells on that delimiter instead of the default

---

### User Story 4 - Control plain-table alignment and reuse CSV-like data (Priority: P2)

As a script author, I want per-column alignment rules and a CSV convenience wrapper so that numeric columns can line up cleanly and comma-delimited reports can be reused without restating the delimiter every time.

**Independent Test**: Render a plain table with right-aligned numeric cells and render comma-delimited input through both plain and Markdown styles.

**Acceptance Scenarios**:

1. **Given** an alignment specification, **When** the aligned-table helper runs, **Then** each column uses the requested alignment
2. **Given** comma-delimited row data, **When** the CSV helper runs, **Then** it dispatches to the requested renderer using `,` as the delimiter

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a helper that renders aligned plain-text columns from delimited rows.
- **FR-002**: The module MUST provide a helper that renders a Unicode boxed table.
- **FR-003**: The boxed-table helper MUST insert a header separator after the first row when more rows exist.
- **FR-004**: The module MUST provide a helper that renders Markdown tables.
- **FR-005**: Table helpers MUST accept an exact custom delimiter.
- **FR-006**: Table helpers MUST accept stdin when the input argument is `-`.
- **FR-007**: The module MUST provide a helper for plain-table rendering with optional per-column alignment rules.
- **FR-008**: The module MUST provide a CSV convenience wrapper that reuses the supported render styles.

### Key Entities *(include if feature involves data)*

- **Row Data**: A multi-line string where each line is one table row.
- **Delimiter**: The exact string used to split a row into cells.
- **Column Width**: The widest display width observed for a given column.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can generate readable terminal and Markdown tables without reimplementing column measurement.
- **SC-002**: Small script-generated reports remain aligned and easy to scan.

## Integration Tests *(mandatory)*

- **IT-001**: Render a plain aligned table from `|`-delimited rows.
- **IT-002**: Render a boxed table with a header separator.
- **IT-003**: Render a Markdown table from custom-delimited rows.
- **IT-004**: Read row data from stdin for plain table output.
- **IT-005**: Render a plain table with right-aligned numeric cells.
- **IT-006**: Render comma-delimited input through the CSV convenience wrapper.

## Acceptance Criteria *(mandatory)*

1. Table helpers print complete rendered tables suitable for direct console use or redirection to files.
2. The same row data can be reused across plain, boxed, and Markdown output styles.
