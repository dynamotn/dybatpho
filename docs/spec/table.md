# Feature Specification: Table Rendering Utilities

**Feature Branch**: `[reverse-spec-table]`
**Status**: Implemented
**Input**: Existing source analysis: `src/table.sh`, `docs/table.md`, `test/table.bats`, and `example/table_ops.sh`

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

---

### User Story 5 - Render real CSV and JSON records directly (Priority: P2)

As a script author, I want to render a quoted CSV export or a JSON array of objects as a table in one call, so that a report needs no detour through the parser and a hand-built delimited string.

**Independent Test**: Render a CSV file with quoted commas, doubled quotes and a multi-line value, and a JSON array with a missing key, in each style.

**Acceptance Scenarios**:

1. **Given** CSV with quoted fields, **When** it is rendered, **Then** a quoted comma stays inside its cell, a doubled quote is one quote, and a line break inside a value is drawn as a space
2. **Given** the Markdown style, **When** a value holds `|`, **Then** it is escaped so the row keeps its column count
3. **Given** a JSON array of objects, **When** it is rendered, **Then** the keys of the first object are the header and a missing key is an empty cell
4. **Given** an empty input or an empty array, **When** it is rendered, **Then** nothing is printed

### Example Workflow

```bash
rows="Service|Status|Replicas
api|healthy|3
worker|degraded|1"

# Same data, three renderings.
dybatpho::table_box "${rows}"
dybatpho::table_markdown "${rows}" >> report.md
dybatpho::table_align "${rows}" "|" "left,left,right" 3

kubectl get pods --no-headers | tr -s ' ' ',' | dybatpho::table_csv - box

# Real CSV, quoting and all, and JSON records.
dybatpho::csv_sort billing.csv cost desc | dybatpho::table_from_csv - box
dybatpho::table_from_json pods.json markdown >> report.md
```

## Edge Cases

- Empty input or input supplied through stdin with `-`.
- Rows contain uneven numbers of cells or leading/trailing whitespace.
- A custom delimiter is multi-character.
- A table has only a header row or no meaningful rows.
- An invalid alignment name or negative/non-numeric gap is supplied.
- A CSV value holds the delimiter, a quote, a line break, or `|`; the only cell is `-`; the file uses `;` or a tab.
- A JSON document is an empty array, is not an array of objects, or no JSON processor is installed.

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
- **FR-009**: The CSV wrapper splits on the delimiter and does not parse RFC
  4180 quoting. It MUST refuse a row whose fields are quoted rather than
  splitting through the quotes, naming the limitation and the way to override
  it, because splitting through them changed the number of columns in a row
  without reporting anything.
- **FR-010**: `DYBATPHO_TABLE_CSV_STRICT=false` MUST restore the plain
  splitting, for data the caller knows carries no quoting.
- **FR-011**: A quote that is not at a field boundary is data, not quoting,
  and MUST NOT be refused.
- **FR-012**: Rendering MUST NOT start a process per cell. Measuring a cell,
  padding it, aligning it and splitting a row into cells MUST all happen in the
  calling shell. Reaching each of those through `$( )` made drawing a table cost
  a fork per cell several times over, which dominated its running time.
- **FR-013**: The module MUST render CSV parsed by the csv module, honouring `DYBATPHO_CSV_DELIMITER`, in the plain, boxed and Markdown styles, with each value in its own cell.
- **FR-014**: A line break inside a CSV value MUST be drawn as a space, and the Markdown style MUST escape `|` inside a value.
- **FR-015**: The module MUST render a JSON array of objects, taking the header from the keys of the first object and leaving a missing key's cell empty, and MUST report a document that is not an array of objects through its exit status.
- **FR-016**: An empty CSV input or an empty JSON array MUST render nothing, and an unknown style MUST stop the script.

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
- **IT-007**: Verify a quoted field is refused with a message naming the
  override, that the override renders it the old way, that `5" pipe` is not
  refused, and that stdin is still read once and rendered.
- **IT-008**: Verify the rendered output is identical to the previous
  implementation for plain, boxed and Markdown styles, including a table with
  wide characters.
- **IT-009**: Render quoted CSV boxed, as Markdown with an escaped pipe, and plain with alignments.
- **IT-010**: Render CSV from stdin with a tab delimiter, a lone `-` cell, and an empty input.
- **IT-011**: Render JSON from text, a file and stdin under a caller's delimiter, and an empty array.
- **IT-012**: Reject an unknown style for both renderers.
- **IT-013**: Report a JSON document that is not an array of objects without ending the caller.

## Acceptance Criteria *(mandatory)*

1. Table helpers print complete rendered tables suitable for direct console use or redirection to files.
2. The same row data can be reused across plain, boxed, and Markdown output styles.
