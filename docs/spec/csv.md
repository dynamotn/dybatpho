# Feature Specification: CSV Data Handling

**Feature Branch**: `[spec-csv]`
**Status**: Implemented
**Input**: Existing source analysis: `src/csv.sh`, `docs/csv.md`, `test/csv.bats`, and `example/csv_ops.sh`

## Problem Statement *(mandatory)*

Ops scripts keep receiving CSV — spreadsheet exports, cloud billing reports, CI artifacts — and the library had nowhere to parse it. `table.sh` renders comma-delimited text and deliberately refuses a quoted field, because it splits on every comma and a comma inside a value would silently become a column separator. Every script that needed real CSV therefore hand-rolled an `awk -F,` or `cut -d,` parser, each of which gets the same three cases wrong: a delimiter inside a quoted value, a doubled quote standing for a literal one, and a line break inside a value.

## Business Value *(mandatory)*

- A value that contains a comma, a quote, or a newline survives being read, filtered, and written back.
- One parser for the whole library, so `table.sh`'s refusal has somewhere to point.
- CSV and JSON convert into each other without a hand-written escape loop at the call site.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Parse CSV the way the file was written (Priority: P1)

As a script author, I want quoted fields read the way RFC 4180 describes so that a delimiter, a doubled quote, or a line break inside a value stays part of that value.

**Independent Test**: Read a file whose fields carry each of those three cases and verify every value comes back whole.

**Acceptance Scenarios**:

1. **Given** a quoted field containing the delimiter, **When** the input is parsed, **Then** the value keeps the delimiter and the row keeps its column count
2. **Given** a quoted field containing a doubled quote, **When** the input is parsed, **Then** the value holds one literal quote
3. **Given** a quoted field containing a line break, **When** the input is parsed, **Then** the record spans the lines and stays one record
4. **Given** a quote that is not at a field boundary, such as `5" pipe`, **When** the input is parsed, **Then** it is data and is left alone

---

### User Story 2 - Pick out the part of the file that matters (Priority: P1)

As a script author, I want the column names, one column's values, and the rows matching a comparison so that reading a report needs no parser of my own.

**Independent Test**: Print the header, one column by name, and the rows whose numeric column exceeds a threshold.

**Acceptance Scenarios**:

1. **Given** a column name, **When** that column is requested, **Then** its values print one per line, excluding the header
2. **Given** a numeric column and a numeric bound, **When** rows are filtered with `gt` or `lt`, **Then** the comparison is numeric rather than lexical
3. **Given** a column name the header does not have, **When** it is requested, **Then** the script stops and the message names the columns there are
4. **Given** a row with more fields than the header names, **When** it is read by column, **Then** the script stops rather than dropping the extra field
5. **Given** a list of columns by name or by 1-based position, **When** they are selected, **Then** the output is CSV holding just those columns, header included, in the order given
6. **Given** a column that is neither a header name nor a position inside the header, **When** it is selected, **Then** the script stops and the message names the columns there are
7. **Given** a column of numbers, **When** the rows are sorted by it, **Then** they are ordered by value, rows with equal keys keep their input order, and empty values come last in either direction
8. **Given** a column holding any value that is not a number, **When** it is sorted with the default comparison, **Then** it is ordered as text, byte by byte, whatever the locale

---

### User Story 3 - Write CSV back out (Priority: P1)

As a script author, I want records serialized back to CSV with only the quoting the data needs, so that a normalized file is readable and a value is never corrupted by being written.

**Independent Test**: Read a file and write it back, verifying the values round-trip and that only the fields that must be quoted are.

**Acceptance Scenarios**:

1. **Given** a value containing the delimiter, a quote, or a line break, **When** it is written, **Then** it is quoted and any quote inside it is doubled
2. **Given** a value needing none of that, **When** it is written, **Then** it is written bare

---

### User Story 4 - Move between CSV and JSON (Priority: P2)

As a script author, I want CSV to become a JSON array of objects and back, so that the data can be handed to `jq` or to an HTTP request without a conversion of my own.

**Independent Test**: Convert a file with quoted values to JSON and back, verifying the values are unchanged.

**Acceptance Scenarios**:

1. **Given** CSV with a header, **When** it is converted, **Then** the result is an array of objects keyed by the header, every value a JSON string
2. **Given** a JSON array of objects, **When** it is converted, **Then** the keys of the first object are the header and a missing key writes an empty value
3. **Given** a document that is not an array of objects, **When** it is converted, **Then** the script stops with a message saying so

---

### User Story 6 - Join two files on a key (Priority: P2)

As a script author, I want to combine two exports on a shared column — services and their owners, hosts and their costs — so that a report needs no hand-written lookup loop.

**Independent Test**: Join a services file to an owners file on the team column, inner and left, and verify every match appears in order.

**Acceptance Scenarios**:

1. **Given** two inputs sharing a key column, **When** they are joined, **Then** the header is the left columns and the right columns without the right key, and each left row is followed by one row per right match, in the right input's order
2. **Given** a `left` join, **When** a left row has no match, **Then** it is kept with the right columns empty
3. **Given** a key named differently on each side, **When** the right key is given, **Then** the inputs join on those two columns
4. **Given** an empty key on either side, **When** the inputs are joined, **Then** it matches nothing

---

### User Story 5 - Read and write TSV and other delimiters (Priority: P2)

As a script author, I want to read a tab- or semicolon-separated export with the same functions, and to rewrite a file with another delimiter, so that a TSV report needs no second parser and a spreadsheet export can be handed to a tool that wants TSV.

**Independent Test**: Read a TSV file with `DYBATPHO_CSV_DELIMITER=tab`, convert a CSV file to TSV and back, and verify an unusable delimiter is refused.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_CSV_DELIMITER` set to `tab` or `\t`, **When** a TSV file is read, **Then** fields split on tabs and a quoted tab stays part of its value
2. **Given** CSV and a target delimiter, **When** it is converted, **Then** every record is written with the new delimiter and each field is quoted for the delimiter it is written with
3. **Given** an empty delimiter, one longer than a character, a quote, a line break, or the unit separator, **When** any function runs, **Then** the script stops with a message naming the delimiter instead of misreading the input

### Example Workflow

```bash
. dybatpho/init.sh --modules csv

dybatpho::csv_header billing.csv
dybatpho::csv_filter billing.csv "cost" gt 100 > expensive.csv
dybatpho::csv_select billing.csv owner cost > owners.csv
dybatpho::csv_sort billing.csv cost desc | head -n 6   # header and the top five
dybatpho::csv_join billing.csv owners.csv owner left name

dybatpho::csv_read billing.csv rows
dybatpho::csv_fields "${rows[1]}" first
printf 'owner=%s\n' "${first[1]}"

dybatpho::csv_to_json billing.csv | jq '[.[] | .cost |= tonumber]'

# Normalize a file: parse it, then write back only the quoting it needs.
dybatpho::csv_write rows > normalized.csv

# Hand the same data to a tool that wants TSV, and read a TSV report back.
dybatpho::csv_convert billing.csv tab > billing.tsv
DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_col billing.tsv "owner"
```

## Edge Cases

- Input arrives as a file path, as `-` for stdin, or as text.
- A row is shorter or longer than the header.
- A selected column is repeated, named by a position, or a header is itself named like a number.
- A join key repeats on the right, is blank, is missing from a side, or holds glob or shell characters; one side is empty or holds only its key.
- A sorted column mixes numbers and text, holds blanks, spells one number two ways (`10`, `010.0`), or holds a value with a line break.
- A record's quote is never closed, or text follows a closing quote.
- A file uses CRLF line endings, or another delimiter such as `;`.
- A field is empty, a row ends with the delimiter, or the input is empty.
- The input contains the ASCII unit separator the module joins fields with.
- Neither `jq` nor `yq` is installed and a JSON conversion is asked for.
- The delimiter is empty, longer than one character, a quote, a line break, or the unit separator.
- A value holds the target delimiter of a conversion, or holds the source delimiter that no longer needs quoting.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST parse quoted fields per RFC 4180: a quoted field ends at the next quote that is not doubled, and a doubled quote inside one is a literal quote.
- **FR-002**: A delimiter or a line break inside a quoted field MUST stay part of that value.
- **FR-003**: A quote that does not begin a field MUST be treated as data.
- **FR-004**: The module MUST accept a file path, `-` for stdin, or CSV text wherever it reads input.
- **FR-005**: Records MUST be exchanged as an array whose elements join their fields with the ASCII unit separator, and the module MUST provide a helper that splits one back apart, preserving empty trailing fields.
- **FR-006**: Input containing that separator MUST be rejected rather than silently re-split.
- **FR-007**: The module MUST reject a caller-supplied variable name that is not bindable.
- **FR-008**: Serializing MUST quote a field only when it contains the delimiter, a quote, or a line break, doubling any quote inside it.
- **FR-009**: The module MUST print the header names, and one column's values chosen by header name.
- **FR-010**: A request for a column the header does not have MUST stop the script and name the columns it does have.
- **FR-011**: A row with more fields than the header names MUST stop the script rather than dropping a field; a row with fewer MUST read as empty values.
- **FR-012**: Filtering MUST support `eq`, `ne`, `gt`, `lt`, and `contains`, and MUST reject any other operator.
- **FR-013**: `gt` and `lt` MUST compare numerically when both values are numeric, and as text otherwise.
- **FR-014**: Filtering MUST print the header followed by the matching rows.
- **FR-015**: Conversion to JSON MUST produce an array of objects keyed by the header, with every value a JSON string, and an empty array for input with no data rows.
- **FR-016**: Conversion from JSON MUST take the header from the keys of the first object and write an empty value where a later object lacks a key.
- **FR-017**: Conversion from JSON MUST produce the same quoting whichever of `jq` or `yq` is available, and MUST report a document that is not an array of objects.
- **FR-018**: The delimiter MUST be configurable through `DYBATPHO_CSV_DELIMITER` for reading and writing alike.
- **FR-019**: A CRLF line ending MUST NOT become part of the last field of a row.
- **FR-020**: `tab` and `\t` MUST name a tab wherever a delimiter is accepted.
- **FR-021**: Every function MUST refuse a delimiter that is not exactly one character, or that is a quote, a line break, or the unit separator, before reading its input.
- **FR-022**: The module MUST rewrite CSV read with the configured delimiter using another delimiter, quoting each field for the delimiter it is written with.
- **FR-023**: Selecting columns MUST print CSV with the header and every row restricted to the chosen columns in the order given, allowing a column to repeat.
- **FR-024**: A selected column MUST resolve by header name first and by 1-based position otherwise, and one matching neither MUST stop the script naming the header.
- **FR-025**: Sorting MUST print the header followed by the data rows ordered by one column, ascending or descending, and MUST be stable.
- **FR-026**: The default comparison MUST be numeric when every non-empty value in the column is a number and byte-wise text otherwise; `text` and `number` MUST force one, and `number` MUST stop the script on a value that is not a number, naming the row.
- **FR-027**: Empty values MUST sort after every other value in both directions.
- **FR-028**: Sorting MUST reject an unknown order or comparison.
- **FR-029**: Joining MUST print the left header followed by the right header without the right key, then one row per pair of matching left and right rows, in left order and then right order.
- **FR-030**: A `left` join MUST keep every left row, with empty right columns where nothing matched; `inner`, the default, MUST keep only matched rows.
- **FR-031**: An empty key MUST match nothing, and the right key column MUST default to the left one's name.
- **FR-032**: Joining MUST reject an unknown join type, a key column a side lacks, and reading both inputs from stdin.

### Key Entities *(include if feature involves data)*

- **Record**: One row, its fields joined by the ASCII unit separator.
- **Header**: The first record, whose values name the columns.
- **Delimiter**: The character separating fields in the file, `,` unless configured otherwise; `tab` names a tab.
- **Operator**: The comparison a filter applies: `eq`, `ne`, `gt`, `lt`, or `contains`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A CSV export with quoted fields reads, filters, and writes back without a value changing.
- **SC-002**: A script needs no `awk -F,` or `cut -d,` parser of its own.
- **SC-003**: Data converts between CSV and JSON without a hand-written escape loop.
- **SC-004**: A row that does not fit its header stops the script instead of losing a field quietly.

## Integration Tests *(mandatory)*

- **IT-001**: Read a quoted field containing the delimiter and verify the column count.
- **IT-002**: Read a doubled quote as one literal quote.
- **IT-003**: Read a line break inside a quoted field as one record.
- **IT-004**: Read a quote that is not a field boundary as data.
- **IT-005**: Read empty fields, a trailing delimiter, and an empty input.
- **IT-006**: Read from a file, from stdin, and from a CRLF file.
- **IT-007**: Reject input holding the unit separator, and a reserved variable name.
- **IT-008**: Split a record back into fields, including an empty record.
- **IT-009**: Write records back, quoting only what needs it, including a carriage return.
- **IT-010**: Print the header, and one column by name.
- **IT-011**: Read a short row as empty, and stop on a row wider than the header.
- **IT-012**: Report an unknown column name, naming the columns there are.
- **IT-013**: Filter with `eq`, `ne`, and `contains`.
- **IT-014**: Filter numerically with `gt` and `lt`, and lexically for non-numeric values.
- **IT-015**: Reject an unknown operator.
- **IT-016**: Convert to JSON, escaping a quote and a line break, and render an empty input as `[]`.
- **IT-017**: Convert from JSON, from a file and from stdin, and round-trip the values.
- **IT-018**: Report a JSON document that is not an array of objects.
- **IT-019**: Read and write with a configured delimiter.
- **IT-020**: Return the data a record with no closing quote still has, and keep text following a closing quote.
- **IT-021**: `dybatpho::table_csv` points at this module when it refuses a quoted field.
- **IT-022**: Read and filter TSV with `DYBATPHO_CSV_DELIMITER` set to `tab` and to `\t`.
- **IT-023**: Refuse an empty, multi-character, quote, line-break, and unit-separator delimiter.
- **IT-024**: Convert CSV to TSV and back, quoting a tab inside a value only in the TSV.
- **IT-025**: Convert from stdin, refuse an unusable target delimiter, and convert an empty input to nothing.
- **IT-026**: Select named columns in a new order, keeping quoted values.
- **IT-027**: Select by position, repeat a column, pad a short row, and prefer a header named like a number.
- **IT-028**: Select from stdin with a configured delimiter, and from an empty input.
- **IT-029**: Report an unknown column, position `0`, no columns, and a row wider than the header.
- **IT-030**: Sort numbers by value, with signs, decimals and two spellings of one value, stably and with the blank last in both directions.
- **IT-031**: Sort text byte by byte under `auto` and `text`, keeping a multi-line value whole.
- **IT-032**: Sort from stdin with a configured delimiter, a header with no rows, and an empty input.
- **IT-033**: Reject an unknown order, an unknown comparison, a non-number under `number`, and an unknown column.
- **IT-034**: Inner-join with repeated right keys, a quoted value, and blank keys on both sides.
- **IT-035**: Left-join with a differently named right key, padding unmatched and short rows.
- **IT-036**: Join on keys holding `@`, `*`, `]`, a space, and `$(...)`.
- **IT-037**: Join with one side on stdin and a configured delimiter, an empty left, an empty right, and a right side holding only its key.
- **IT-038**: Reject an unknown join type, a missing key column, two stdins, and a row wider than its header.

## Acceptance Criteria *(mandatory)*

1. Reading and writing CSV needs no external command; only the JSON conversion asks for `jq` or `yq`.
2. Text output goes to stdout so the helpers compose in pipelines and command substitution.
3. Input that cannot be represented faithfully stops the script with a message naming the row or the value, rather than producing a file that is quietly wrong.
