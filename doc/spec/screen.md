# Feature Specification: Full-Screen Terminal Applications

**Feature Branch**: `[feat-screen]`
**Status**: Implemented
**Input**: Existing source analysis: `src/screen.sh`, `doc/screen.md`, `test/screen.bats`, and `example/screen_ops.sh`

## Problem Statement *(mandatory)*

`tui.sh` draws widgets beside a script's ordinary output, which suits a script
that asks a question and carries on. It does not suit an application: a process
browser, a log viewer, a picker with a preview pane. Those need the whole
terminal, a layout that survives a resize, widgets that compose, and keystrokes
delivered one at a time.

Shell authors reach outside the shell for this -- `dialog`, `whiptail`, `fzf`,
`gum` -- or hand-roll a `read -rsn1` loop and a pile of `printf '\033[...'`. The
hand-rolled version fails in the same places every time: columns drift apart as
soon as a CJK character or an emoji appears, a resize corrupts the screen, an
interrupted script leaves the terminal in raw mode with no cursor, and redrawing
the whole screen on every keystroke is too slow to use.

The obvious design, the one `ratatui` uses, is a buffer of cells diffed against
the previous frame. Measured in Bash that costs about 50 microseconds per cell,
which is half a second for one frame of a 200x50 terminal, and the per-cell loop
itself is the cost, so a cleverer diff does not rescue it. A Bash implementation
therefore needs a different internal model to reach a usable frame rate.

## Business Value *(mandatory)*

- Let a shell script be a real terminal application without adding a dependency
  the target machine may not have.
- Make correct Unicode layout the default, so a dashboard does not come apart
  the first time a container name contains a CJK character.
- Give the terminal back under every exit path, so a crashed application never
  leaves a shell unusable.
- Keep frames cheap enough that an application redraws on every keystroke
  without feeling slow.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Lay a screen out and keep it laid out (Priority: P1)

As an application author, I want to split the terminal into regions by
constraint, so that a layout describes intent rather than arithmetic and
survives any terminal size.

**Independent Test**: Split a rectangle with fixed, proportional, and flexible
constraints and verify the parts tile it exactly.

**Acceptance Scenarios**:

1. **Given** a mix of fixed and flexible constraints, **When** a rectangle is
   split, **Then** the fixed parts get what they asked for and the flexible
   ones share what is left
2. **Given** constraints whose sizes do not divide evenly, **When** a rectangle
   is split, **Then** the parts still tile it exactly, with no row or column
   unaccounted for
3. **Given** constraints asking for more than exists, **When** a rectangle is
   split, **Then** the parts shrink from the end and none becomes negative
4. **Given** an unknown direction or constraint, **When** a split is asked for,
   **Then** it is refused, naming what was wrong

---

### User Story 2 - Compose a screen from widgets (Priority: P1)

As an application author, I want blocks, text, lists, tables, gauges, tabs,
scrollbars, and charts that draw into a rectangle, so that a screen is assembled
from parts rather than drawn by hand.

**Independent Test**: Draw each widget into a known rectangle and verify the
resulting rows.

**Acceptance Scenarios**:

1. **Given** a block with a title, **When** it is drawn, **Then** it draws its
   border and reports the area left inside it
2. **Given** a list longer than its rectangle, **When** an item near the end is
   selected, **Then** the list scrolls so that the selection is visible and
   reports the offset it chose
3. **Given** a popup, **When** it is drawn over a frame, **Then** what was
   underneath is erased rather than showing through
4. **Given** a series of values, **When** a line chart is drawn, **Then**
   consecutive samples are joined into a continuous line rather than left as
   separate dots

---

### User Story 3 - Drive the application from the keyboard and mouse (Priority: P1)

As an application author, I want keystrokes, mouse clicks, and resizes delivered
as named events, so that an input loop never parses escape sequences.

**Independent Test**: Feed arrow keys, navigation keys, a bare escape, and an
SGR mouse report, and verify each is named.

**Acceptance Scenarios**:

1. **Given** an arrow key or a navigation key, **When** it is read, **Then** it
   is reported under a stable name
2. **Given** a bare escape, **When** it is read, **Then** it is reported as a
   cancel rather than waiting for a sequence that is not coming
3. **Given** a mouse click, **When** it is read, **Then** the button and the
   zero-based position are reported
4. **Given** a terminal that changed size, **When** the next event is read,
   **Then** the resize is reported before any key
5. **Given** a deadline and no input, **When** an event is read, **Then** the
   timeout is distinguishable from the end of input

---

### User Story 4 - Give the terminal back (Priority: P1)

As a user of an application, I want my terminal returned to me whatever happens
to it, so that a crash does not leave me with no cursor and no echo.

**Independent Test**: Run an application to completion over a pseudo-terminal
and verify the alternate screen is left, the cursor is restored, and the line
settings come back.

**Acceptance Scenarios**:

1. **Given** an application that ends normally, **When** it exits, **Then** the
   alternate screen is left and the cursor and line settings are restored
2. **Given** an application killed by a signal, **When** it dies, **Then** the
   same restoration happens
3. **Given** no terminal at all, **When** the screen is taken over, **Then** it
   is refused rather than hanging

---

### User Story 5 - Redraw fast enough to feel immediate (Priority: P2)

As a user, I want a screen that repaints on each keystroke without lag.

**Independent Test**: Draw repeated frames of a realistic screen and measure the
cost per frame.

**Acceptance Scenarios**:

1. **Given** a frame where most rows are unchanged, **When** it is flushed,
   **Then** only the changed rows are rendered and only those are sent
2. **Given** a row of ASCII or single-column characters, **When** it is
   painted, **Then** no character measuring happens at all

### Example Workflow

```bash
. dybatpho/init.sh --modules screen

dybatpho::screen_begin || dybatpho::die "No terminal"
while true; do
  dybatpho::screen_clear
  dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" length:1 fill:1
  dybatpho::screen_tabs "${rows[0]}" tabs active:"${tab}"
  dybatpho::screen_block "${rows[1]}" title:"Pods" border:rounded
  dybatpho::screen_list "${DYBATPHO_SCREEN_INNER}" pods selected:"${cursor}"
  dybatpho::screen_flush

  dybatpho::screen_event key
  case "${key}" in
    char:q | escape) break ;;
    down) cursor=$((cursor + 1)) ;;
    resize) dybatpho::screen_size || true ;;
  esac
done
dybatpho::screen_end
```

## Edge Cases

- A widget is given a rectangle of zero width or height, or one off the screen.
- Text is wider than the rectangle, or ends with a double-width glyph exactly
  at the edge.
- The terminal is resized mid-frame, or resized several times before an event
  is read.
- A caller's array is named the same as one of a widget's own variables.
- A list is empty, or the selection is past its end.
- A gauge is given a total of zero, or a value above its total.
- A chart is given one sample, or samples that are all equal.
- A scrollbar is asked for when everything already fits.
- The locale makes Bash index strings by byte rather than by character.
- `stty` is missing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST keep its frame buffer as rows, not as cells. The
  per-cell model costs about 50 microseconds a cell in Bash, which is half a
  second for one 200x50 frame.
- **FR-002**: Styles MUST be kept as runs of columns rather than one entry per
  cell, so painting and rendering cost what was drawn and not how wide the
  terminal is.
- **FR-003**: A style applied to a span MUST end where the span ends, restoring
  whatever style was in force after it.
- **FR-004**: Flushing MUST send only the rows that changed, and MUST NOT
  render a row whose text and runs are unchanged.
- **FR-005**: Character widths MUST be measured against embedded Unicode tables
  covering the double-width and zero-width ranges, without calling another
  program.
- **FR-006**: Measuring MUST be correct whether the locale makes Bash index
  strings by character or by byte.
- **FR-007**: A row MUST keep its fast column-to-index path while every
  character on it spans one column and one index, so a border of box-drawing
  characters does not force the slow path.
- **FR-008**: Text MUST be clipped to the rectangle it is drawn in, and MUST
  NOT be cut in the middle of a character or leave half a double-width glyph.
- **FR-009**: `dybatpho::screen_layout` MUST support `length`, `percent`,
  `ratio`, `min`, `max`, and `fill` constraints.
- **FR-010**: A layout MUST tile its rectangle exactly, with rounding absorbed
  rather than lost.
- **FR-011**: A layout asked for more than exists MUST shrink from the end and
  MUST NOT produce a negative size.
- **FR-012**: A block MUST publish the rectangle left inside its border.
- **FR-013**: A list and a table MUST scroll to keep the selection visible and
  MUST publish the offset they chose.
- **FR-014**: A popup MUST erase the area it covers before drawing.
- **FR-015**: A line chart MUST join consecutive samples into a continuous
  line.
- **FR-016**: A widget that binds a name the caller chose MUST NOT be able to
  read one of its own locals instead, whatever the caller named their array.
- **FR-017**: Taking over the terminal MUST switch to the alternate screen,
  enter raw mode, hide the cursor, and optionally enable mouse reporting.
- **FR-018**: The terminal MUST be restored on exit, interrupt, and
  termination, and restoring twice MUST be harmless.
- **FR-019**: Drawing and reading MUST go to the terminal directly rather than
  through stdout, so an application can still print a result a caller captures.
- **FR-020**: Events MUST be reported as stable names, covering keys, arrows,
  navigation keys, mouse buttons with a zero-based position, resize, and end of
  input.
- **FR-021**: A pending resize MUST be reported before the next key.
- **FR-022**: A timeout MUST be distinguishable from the end of input.
- **FR-023**: Taking over the terminal when there is none MUST be refused
  rather than hanging.
- **FR-024**: The module MUST declare `stty` as a required dependency.

### Key Entities *(include if feature involves data)*

- **Rectangle**: `x y width height`, zero-based, the unit every widget and the
  layout solver work in.
- **Row Buffer**: The text of one row, padded to the width of the terminal.
- **Style Run**: A column and the SGR parameters in force from it until the
  next run.
- **Event Name**: A keystroke, mouse report, resize, or end of input, reduced
  to a name an input loop can match on.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A frame of a realistic 80x24 screen costs under 25 milliseconds,
  and one of a 200x50 screen under 60, so a keystroke repaint feels immediate.
- **SC-002**: A screen holding CJK text or emoji stays aligned to the column
  grid.
- **SC-003**: An application ending in any way leaves the terminal usable.
- **SC-004**: A shell application needs no `dialog`, `whiptail`, `fzf`, or
  `gum` to present a full-screen interface.

## Integration Tests *(mandatory)*

- **IT-001**: Measure ASCII, CJK, emoji, combining marks, and box drawing, and
  refuse a reserved result variable.
- **IT-002**: Build, shrink, and centre rectangles, clamping rather than going
  negative.
- **IT-003**: Split rectangles vertically and horizontally, with `length`,
  `percent`, `ratio`, `min`, `max`, and `fill`.
- **IT-004**: Verify a layout tiles its rectangle exactly, shrinks from the end
  when over budget, and refuses an unknown direction or constraint.
- **IT-005**: Size the buffer, report only real size changes, draw and clear.
- **IT-006**: Verify a style ends where its span ends and the previous style
  returns.
- **IT-007**: Verify wide characters keep a row exactly the width of the
  terminal, that text is clipped at the edges, and that off-screen writes do
  nothing.
- **IT-008**: Verify a flush sends nothing when nothing changed and sends only
  the changed row otherwise.
- **IT-009**: Draw a titled block, a borderless block, and a popup over other
  content.
- **IT-010**: Wrap, align, and truncate text.
- **IT-011**: Draw a list with a selection, verify it scrolls to keep the
  selection visible, and verify it reads a caller array whose name collides
  with the widget's own locals.
- **IT-012**: Draw a table with a header and a selected row.
- **IT-013**: Draw a gauge at several ratios and with its default percentage
  label.
- **IT-014**: Draw a scrollbar, and verify none is drawn when everything fits.
- **IT-015**: Draw tabs with one active.
- **IT-016**: Draw a sparkline, including one whose series is longer than the
  rectangle.
- **IT-017**: Draw a bar chart with labels and partial blocks.
- **IT-018**: Verify a line chart leaves no column of its plot without a dot.
- **IT-019**: Verify restoring the terminal twice is harmless, and that taking
  it over with no terminal is refused.
- **IT-020**: Verify a pending resize is reported before a key, and that a
  timeout is distinguishable from end of input.
- **IT-021**: Decode ordinary keys, arrows, navigation keys, a bare escape, and
  an SGR mouse report with its zero-based position.

## Acceptance Criteria *(mandatory)*

- Every public function is documented in `doc/screen.md` and exercised by
  `test/screen.bats`.
- `example/screen_ops.sh` runs unattended, offline, and leaves the working tree
  untouched; it composes a frame and prints it rather than taking over the
  terminal, because an example cannot wait for a keystroke.
- The module is registered in `init.sh`, and `stty` is declared in
  `src/doctor.sh`.
- The drawn path is exercised against a real pseudo-terminal before the work is
  reported as done, because no part of taking over a terminal is reachable from
  a suite whose streams are captured.
