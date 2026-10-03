# Feature Specification: Markdown Content Builders

**Feature Branch**: `[spec-markdown]`
**Status**: Implemented
**Input**: Existing source analysis: `src/markdown.sh`, `docs/markdown.md`, `test/markdown.bats`, and `example/markdown_ops.sh`

## Problem Statement *(mandatory)*

Scripts that produce a report, a pull request description, or a release note build Markdown by concatenating strings in a heredoc. Nothing escapes the values they interpolate, so a commit subject containing `*`, a filename containing `[`, or a cell containing `|` renders as formatting rather than as the text it was, and a value that begins with `-` or `#` opens a block of its own. `table.sh` renders a Markdown table but covers no other construct, which leaves the callers that would benefit most — `release.sh` building a changelog and `forge.sh` posting an issue or pull request body — assembling everything else by hand.

## Business Value *(mandatory)*

- Generated documents render as intended whatever characters the data carries.
- One escaping rule for the whole library, rather than a different heredoc per caller.
- Reports, release notes, and forge comments compose from small builders instead of string concatenation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Interpolate untrusted values safely (Priority: P1)

As a script author, I want every builder to escape the text I give it so that a value read from a commit message, a filename, or a command's output cannot change how the document renders.

**Independent Test**: Pass text containing `*`, `[`, `|`, and a leading `-` through a heading and a list, and verify the characters appear as text.

**Acceptance Scenarios**:

1. **Given** text containing inline Markdown syntax, **When** any builder renders it, **Then** the syntax characters are escaped and render as text
2. **Given** an item that begins with `-`, `#`, `+`, `=`, or an ordered-list marker, **When** a list renders it, **Then** the leading character is escaped so the item does not open a block
3. **Given** text containing a backslash, **When** a builder escapes it, **Then** the backslash is doubled before any other character is escaped

---

### User Story 2 - Embed Markdown that is already formatted (Priority: P1)

As a script author, I want to place a fragment I built earlier inside another builder so that composing a document does not force me to choose between escaping everything and escaping nothing.

**Independent Test**: Build a link, mark it raw, interpolate it into a list item, and verify the link renders while the rest of the item is still escaped.

**Acceptance Scenarios**:

1. **Given** a fragment marked raw, **When** a builder renders text containing it, **Then** the fragment is emitted unchanged and the surrounding text is escaped
2. **Given** a raw fragment whose closing mark was cut by a truncation, **When** a builder renders it, **Then** the remainder is emitted unchanged rather than escaped

---

### User Story 3 - Build the blocks a report is made of (Priority: P1)

As a script author, I want headings, lists, task lists, links, badges, fenced code blocks, tables, and collapsible sections so that a generated report needs no Markdown knowledge at the call site.

**Independent Test**: Render one of each block and verify the output is the Markdown the construct requires.

**Acceptance Scenarios**:

1. **Given** a heading level between 1 and 6, **When** the heading renders, **Then** it carries that many leading `#` characters
2. **Given** a marker of `1.` or `1)`, **When** a list renders, **Then** the items are numbered from that value
3. **Given** a code body that itself contains a fence, **When** the code block renders, **Then** the fence is longer than the longest backtick run inside the body
4. **Given** a summary and a body, **When** the collapsible section renders, **Then** the body is surrounded by the blank lines a renderer needs to read it as Markdown

---

### User Story 4 - Write for a forge that speaks GitHub-flavored Markdown (Priority: P2)

As a release author, I want task lists, mentions, and emoji shortcodes so that a generated pull request or release body reads the way a hand-written one does.

**Independent Test**: Render a task list with mixed states, a mention, and an emoji shortcode, and verify each is the GitHub-flavored form.

**Acceptance Scenarios**:

1. **Given** lines carrying a state and a text separated by a delimiter, **When** the task list renders, **Then** each item is checked or unchecked according to its state
2. **Given** a line with no delimiter, **When** the task list renders, **Then** the whole line is an unchecked item
3. **Given** an account name or a shortcode that is already delimited, **When** it renders, **Then** the delimiter is not doubled

### Example Workflow

```bash
. dybatpho/init.sh --modules markdown

dybatpho::md_heading 1 "$(git log -1 --format=%s)"
dybatpho::md_list "$(git log --format=%s "${previous}..HEAD")"
dybatpho::md_task_list $'x|Tag the commit\n|Announce the release'

# A value the escape must not touch, because it is Markdown already.
dybatpho::md_list "see $(dybatpho::md_raw "$(dybatpho::md_link 'the notes' "${url}")")"

# Cells are escaped first and joined with a delimiter the escape leaves alone.
dybatpho::md_table "Artifact::Size"$'\n'"$(dybatpho::md_escape "${name}")::${size}" "::"
dybatpho::md_collapsible "Full build log" "$(dybatpho::md_code_block '' "${log}")"
```

## Edge Cases

- Input arrives through stdin with `-`, or is empty, or contains blank lines.
- Text passed as an argument ends with a newline.
- A value begins with a character that opens a block, or contains a backslash.
- A code body contains a fence as long as or longer than the default one.
- A URL contains a space, a parenthesis, or an angle bracket.
- A raw region is cut so its closing mark is missing.
- A heading level, an emoji shortcode, an account name, or a code-block language is invalid.
- `dybatpho::md_table` is called without the `table` module loaded.
- A badge's label, value or color holds a character that is not safe in a URL path, such as `/`, `?`, `#`, `%` or a parenthesis.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every builder MUST escape the Markdown-significant characters in the text arguments it renders.
- **FR-002**: The escape MUST double a backslash before escaping any other character.
- **FR-003**: The escape MUST escape `#`, `-`, `+`, `=`, and an ordered-list marker only where they begin a line.
- **FR-004**: The module MUST provide a helper that marks a fragment as already-formatted Markdown, and every builder MUST emit such a fragment unchanged.
- **FR-005**: A raw region with no closing mark MUST be emitted unchanged rather than escaped.
- **FR-006**: The module MUST provide builders for headings, lists, task lists, links, badges, fenced code blocks, tables, and collapsible sections.
- **FR-007**: The heading builder MUST reject a level outside 1 to 6.
- **FR-008**: The list builder MUST number its items when given an ordered marker, and MUST preserve blank input lines.
- **FR-009**: The task-list builder MUST read a per-line state, treating a line without the delimiter as unchecked.
- **FR-010**: The link builder MUST percent-encode a URL character that would end the link target early.
- **FR-011**: The badge builder MUST encode its label and value the way shields.io requires, and MUST accept an optional link.
- **FR-012**: The code-block builder MUST NOT escape its body, and MUST choose a fence longer than the longest backtick run the body contains.
- **FR-013**: The code-block builder MUST reject a language containing a backtick.
- **FR-014**: The table builder MUST render through `dybatpho::table_markdown`. Loading `markdown` MUST NOT load `table`, and the table builder MUST stop with a message naming the `table` module and how to load it when that module is not loaded.
- **FR-015**: The collapsible builder MUST escape its summary and MUST emit its body unchanged, surrounded by blank lines.
- **FR-016**: The mention and emoji builders MUST accept an already-delimited argument without doubling the delimiter, and MUST reject a value that cannot render.
- **FR-017**: Every builder that takes a text block MUST accept stdin when the input argument is `-`.
- **FR-018**: `md_badge` MUST percent-encode every character of the label, value and color outside the unreserved URL set, after the shields.io doubling of `-` and `_` and the space-to-`_` rule.
- **FR-019**: Text passed as an argument MUST split into the same lines as the same text on stdin; one trailing newline MUST NOT add an empty item.

### Key Entities *(include if feature involves data)*

- **Text Block**: A multi-line string passed as a direct argument or through stdin.
- **Raw Region**: A fragment bounded by the module's control-character marks, which the escape copies through untouched.
- **Marker**: The bullet or ordered-list prefix a list renders its items with.
- **Task State**: The per-line value deciding whether a task-list item is checked.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A generated document renders as intended whatever characters its interpolated values carry.
- **SC-002**: A report composes from builders without a heredoc that hand-writes Markdown syntax.
- **SC-003**: A fragment built by one call can be embedded in another without being escaped twice.

## Integration Tests *(mandatory)*

- **IT-001**: Render a heading whose text contains inline syntax, and reject an out-of-range level.
- **IT-002**: Render a bullet list, an ordered list from a custom start, and a list preserving blank lines.
- **IT-003**: Escape a list item that begins with a block-opening character.
- **IT-004**: Render a task list with checked, unchecked, and delimiter-less lines.
- **IT-005**: Render a link with a percent-encoded URL and an optional quoted title.
- **IT-006**: Render a badge with shields.io encoding, a default color, and a wrapping link.
- **IT-007**: Render a code block, grow its fence past a body that contains one, and reject a language containing a backtick.
- **IT-008**: Render a table, and, in a child shell that loaded only `markdown`, stop the table builder with the message naming `table` while the other builders still work.
- **IT-009**: Render a collapsible section with an escaped summary and an unescaped body.
- **IT-010**: Embed a raw fragment in a builder, including one whose closing mark was cut.
- **IT-011**: Escape inline and line-leading syntax, a backslash, stdin, and empty input.
- **IT-012**: Render a mention and an emoji shortcode, and reject invalid values of each.
- **IT-013**: Render a badge whose label, value and color hold `/`, `?`, `#`, `%`, a space and parentheses, and find each percent-encoded in the URL.
- **IT-014**: Render a list from text ending in a newline, as an argument and on stdin, and get the same items with no empty one at the end.

## Acceptance Criteria *(mandatory)*

1. Builders print one block at a time on stdout, so they compose through command substitution and concatenation.
2. Escaping is the default for text and never applied to a code-block body, a collapsible body, or a raw region.
3. Invalid input stops the script with a message naming the function and the value, rather than rendering something that will not display.
