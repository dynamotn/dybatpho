# screen.sh

Full-screen terminal applications: layout, widgets, and an event loop

> 🧭 Source: [src/screen.sh](../src/screen.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`tui.sh` draws widgets beside a script's ordinary output. This module takes
the whole terminal instead: it switches to the alternate screen, puts the
terminal in raw mode, splits the area into rectangles with a constraint
solver, draws widgets into them, and hands keystrokes, mouse clicks, and
resizes back one event at a time. It is the `ratatui` shape, in Bash.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SCREEN_MOUSE`** | bool | Report mouse clicks as events. Default `true` |
| **`DYBATPHO_SCREEN_POINTER`** | string | Marker drawn beside the selected list or table row. Default `❯` |
| **`DYBATPHO_SCREEN_STYLE_SELECTED`** | string | SGR parameters for a selected row. Default `1;7` |
| **`DYBATPHO_SCREEN_STYLE_BORDER`** | string | SGR parameters for a block border. Default `2` |
| **`DYBATPHO_SCREEN_STYLE_TITLE`** | string | SGR parameters for a block title. Default `1` |
| **`DYBATPHO_SCREEN_WIDTH`** | number | Columns of the terminal the buffer is sized for |
| **`DYBATPHO_SCREEN_HEIGHT`** | number | Rows of the terminal the buffer is sized for |
| **`DYBATPHO_SCREEN_RECT`** | string | The whole terminal as a rectangle, `x y width height` |
| **`DYBATPHO_SCREEN_ACTIVE`** | bool | `true` between `dybatpho::screen_begin` and `dybatpho::screen_end` |
| **`DYBATPHO_SCREEN_MOUSE_COLUMN`** | number | Zero-based column of the last mouse event |
| **`DYBATPHO_SCREEN_MOUSE_ROW`** | number | Zero-based row of the last mouse event |
| **`DYBATPHO_SCREEN_INNER`** | string | Rectangle left inside the last block or popup |
| **`DYBATPHO_SCREEN_OFFSET`** | number | Index of the first item the last list or table drew, after it scrolled to keep the selection visible |

### 🚀 Highlights

- [`__dybatpho_screen_expect_int`](#__dybatpho_screen_expect_int) — Validate a whole number, or end the script naming what was wrong.
- [`__dybatpho_screen_is_ascii`](#__dybatpho_screen_is_ascii) — Return success when a string is nothing but printable ASCII, which is the case where one character is one index and one column, so no measuring is needed at all. The test is `[:ascii:]` rather than a byte range under a local `LC_ALL=C`. Assigning `LC_ALL` makes Bash reload its locale data on the way in and again on the way out, which measured at 47 microseconds a call against 14 for this form -- and this sits under every segment of every frame.
- [`__dybatpho_screen_indexes_bytes`](#__dybatpho_screen_indexes_bytes) — Report whether Bash indexes strings by byte in this locale. Under a UTF-8 locale a multi-byte character is one index and `printf '%d'` reports its codepoint; under `C` both count bytes, and a character has to be reassembled before it can be measured.
- [`__dybatpho_screen_chars_into`](#__dybatpho_screen_chars_into) — Split text into characters, whatever the locale indexes by.
- [`__dybatpho_screen_codepoint_into`](#__dybatpho_screen_codepoint_into) — Decode one character to its Unicode codepoint, including when the locale makes Bash index by byte and the character arrives as its UTF-8 bytes.
- [`__dybatpho_screen_char_width_into`](#__dybatpho_screen_char_width_into) — Return the number of columns one character occupies, against the embedded Unicode tables. Every character measured is remembered, so a screen redrawn sixty times a second measures each distinct glyph once.
- [`dybatpho::screen_width`](#dybatphoscreen_width) — Return the number of terminal columns a string occupies. Text that is nothing but printable ASCII is its own length, which is the overwhelmingly common case and is answered without looking at a single character.
- [`__dybatpho_screen_width_into`](#__dybatpho_screen_width_into) — Measure a string, without validating the target name. Painting calls this for every segment it draws, and the check in the public entry point is worth a regular expression per frame, not per segment.
- [`__dybatpho_screen_truncate_into`](#__dybatpho_screen_truncate_into) — Cut a string down to a number of columns, never splitting a character in half and never leaving half of a double-width glyph behind.
- [`__dybatpho_screen_index_into`](#__dybatpho_screen_index_into) — Return the string index that a display column falls at in a row. A row of plain ASCII answers immediately; any other row is walked once.
- [`__dybatpho_screen_style_set`](#__dybatpho_screen_style_set) — Replace a span of style runs on a row with one run, restoring whatever style was in force at the far end. Runs are kept instead of one style per cell because a row holds a handful of runs and a few hundred cells: painting and rendering then cost what was drawn rather than how wide the terminal is.
- [`dybatpho::screen_put`](#dybatphoscreen_put) — Draw text into the buffer at one position, clipped to the screen. Nothing reaches the terminal until `dybatpho::screen_flush` runs.
- [`__dybatpho_screen_render_into`](#__dybatpho_screen_render_into) — Build the escape sequence for one row from its text and runs.
- [`dybatpho::screen_clear`](#dybatphoscreen_clear) — Reset the buffer to blank, which is where every frame starts.
- [`dybatpho::screen_size`](#dybatphoscreen_size) — Resize the buffer to the terminal, and report whether it changed.
- [`dybatpho::screen_flush`](#dybatphoscreen_flush) — Write the rows that changed since the last frame to the terminal.
- [`dybatpho::screen_rect`](#dybatphoscreen_rect) — Build a rectangle from its parts.
- [`dybatpho::screen_layout`](#dybatphoscreen_layout) — Split a rectangle into parts that satisfy a list of constraints. The constraints are the ones `ratatui` uses, and they are resolved in the same order of authority: the fixed sizes are taken out first, what is left is shared between the flexible ones, and the last part absorbs the rounding so the pieces always add up to the whole. | Constraint | Meaning | | --- | --- | | `length:N` | exactly `N` | | `percent:N` | `N` percent of the rectangle | | `ratio:A/B` | the fraction `A/B` of the rectangle | | `min:N` | at least `N`, and grows into what is left | | `max:N` | at most `N`, and grows into what is left | | `fill:W` | no size of its own; shares what is left by weight `W` |
- [`dybatpho::screen_rect_inner`](#dybatphoscreen_rect_inner) — Shrink a rectangle by a margin on every side.
- [`dybatpho::screen_rect_center`](#dybatphoscreen_rect_center) — Centre a rectangle of a given size inside another, which is what a popup needs.
- [`__dybatpho_screen_on_resize`](#__dybatpho_screen_on_resize) — Note that the terminal changed size, so the next event reports it.
- [`dybatpho::screen_begin`](#dybatphoscreen_begin) — Take over the terminal: alternate screen, raw mode, hidden cursor, and mouse reporting. The terminal is opened directly rather than taken from stdin and stdout, so an application can still read a pipe and print a result that a caller captures while it is drawing.
- [`exec`](#exec) — 
- [`exec`](#exec) — 
- [`dybatpho::screen_end`](#dybatphoscreen_end) — Give the terminal back: mouse reporting off, cursor shown, the alternate screen left, and the original line settings restored.
- [`exec`](#exec) — 
- [`dybatpho::screen_event`](#dybatphoscreen_event) — Wait for the next event and report it under a stable name. Keys come back as `up`, `down`, `left`, `right`, `enter`, `space`, `tab`, `backspace`, `escape`, `home`, `end`, `pageup`, `pagedown`, `delete`, or `char:<c>`. A terminal that changed size reports `resize`, a mouse click reports `mouse:<button>`, and a closed input reports `eof`.
- [`__dybatpho_screen_read_escape`](#__dybatpho_screen_read_escape) — Read the rest of an escape sequence and name it.
- [`__dybatpho_screen_read_char`](#__dybatpho_screen_read_char) — Read one character with a timeout.
- [`__dybatpho_screen_parse_mouse`](#__dybatpho_screen_parse_mouse) — Turn an SGR mouse report into an event name and a position.
- [`__dybatpho_screen_options`](#__dybatpho_screen_options) — Read `key:value` widget options into an associative array. Anything without a colon is left in place for the widget to read as a positional argument.
- [`__dybatpho_screen_copy_array`](#__dybatpho_screen_copy_array) — Copy a caller's array into one of the module's own. Only namespaced locals exist in this function's scope, so a nameref bound to a caller's array finds that array rather than a local of the same name. The widgets that take small arrays copy through it instead of namespacing every local they have; the ones that may be handed a long array bind the nameref directly and namespace their locals instead, to avoid copying every frame.
- [`__dybatpho_screen_align_into`](#__dybatpho_screen_align_into) — Pad text to a width, aligning it within the space.
- [`dybatpho::screen_block`](#dybatphoscreen_block) — Draw a bordered box, optionally titled, and report the area left inside it. The inner rectangle is published rather than returned, because a block is almost always followed by a widget drawn inside it and computing that rectangle by hand is where off-by-one borders come from.
- [`dybatpho::screen_text`](#dybatphoscreen_text) — Draw text in a rectangle, wrapped and aligned.
- [`dybatpho::screen_list`](#dybatphoscreen_list) — Draw a scrollable list of items with one of them selected. The list scrolls itself: the offset that keeps the selected item on screen is worked out here and published, so an application only tracks which item is selected.
- [`dybatpho::screen_table`](#dybatphoscreen_table) — Draw a table with a header and an optional selected row.
- [`__dybatpho_screen_table_row_into`](#__dybatpho_screen_table_row_into) — 
- [`dybatpho::screen_gauge`](#dybatphoscreen_gauge) — Draw a horizontal gauge filled to a ratio, with a label centred on it.
- [`dybatpho::screen_tabs`](#dybatphoscreen_tabs) — Draw a row of tabs with one of them active.
- [`dybatpho::screen_scrollbar`](#dybatphoscreen_scrollbar) — Draw a vertical scrollbar showing where a window sits in a list longer than the screen.
- [`dybatpho::screen_sparkline`](#dybatphoscreen_sparkline) — Draw a one-row sparkline from a series of numbers.
- [`dybatpho::screen_barchart`](#dybatphoscreen_barchart) — Draw horizontal bars, one per value, with optional labels.
- [`__dybatpho_screen_braille_table`](#__dybatpho_screen_braille_table) — Fill the Braille lookup table, once. The table is built with a single `printf`: the format string is assembled from `\Uxxxxxxxx` escapes first and expanded in one call, rather than calling out once per character.
- [`dybatpho::screen_chart`](#dybatphoscreen_chart) — Plot a series as a line chart, using Braille dots for a resolution of two points across and four down inside every character. This is the one widget that works a cell at a time, because a chart is the one thing whose every cell differs. It is bounded by the rectangle it is given, so a chart in a corner of the screen costs what that corner is worth rather than what the whole screen would be.
- [`dybatpho::screen_popup`](#dybatphoscreen_popup) — Blank a rectangle and draw a block over it, which is what a dialog or a menu laid over the screen needs. Whatever was underneath is erased rather than shown through, so the popup can be drawn last over a frame that knows nothing about it.

## Why rows and not cells

`ratatui` keeps a buffer of cells, diffs it against the previous frame, and
writes the cells that changed. Measured in Bash that model costs about 50
microseconds per cell, which is 0.5 seconds for one frame of a 200x50
terminal -- the per-cell loop itself is the cost, so a smarter diff does not
rescue it. This module keeps a buffer of rows instead: a row is one string,
painted with Bash's own string operations, and the diff compares rows. The
same 200x50 frame then costs about 6 milliseconds, which is the difference
between an unusable and a comfortable frame rate.

Styles are kept beside each row as a list of runs (`column`, `SGR`) rather
than one entry per cell, so painting and rendering both cost what the
drawing actually contains instead of what the screen could hold.

## Drawing a frame

Every frame follows the same three steps: clear the buffer, draw into it,
flush it. Widgets never write to the terminal themselves, so the order they
are called in only decides what covers what.

```sh
dybatpho::screen_begin
while true; do
  dybatpho::screen_clear
  dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" length:3 fill:1
  dybatpho::screen_block "${rows[0]}" title:"Status"
  dybatpho::screen_list "${rows[1]}" items selected:"${cursor}"
  dybatpho::screen_flush
  dybatpho::screen_event key
  case "${key}" in
    char:q | escape) break ;;
    down) cursor=$((cursor + 1)) ;;
  esac
done
dybatpho::screen_end
```

## Rectangles

A rectangle is the string `x y width height`, with `x` and `y` zero-based.
`DYBATPHO_SCREEN_RECT` always holds the whole terminal, and
`dybatpho::screen_layout` splits any rectangle into more of them.

<a id="see-also"></a>
## 🔗 See also

- [example/screen_ops.sh](../example/screen_ops.sh)
- [src/tui.sh](../src/tui.sh)

<a id="tips"></a>
## 💡 Tips

- Everything is drawn on `/dev/tty` rather than on stdout, so an application can still print a result that a caller captures
- Character widths are measured against an embedded Unicode table, so CJK text and emoji line up without calling out to another program

### `dybatpho::screen_put`

- Pass the text without escape sequences and give the style separately; a style passed inside the text would break the column arithmetic

### `dybatpho::screen_clear`

- The front buffer is deliberately left alone, so a cleared frame still only sends the rows that actually changed

### `dybatpho::screen_flush`

- A frame costs what changed: redrawing a screen where one list row moved sends one or two rows, not the whole screen

### `dybatpho::screen_layout`

- A part can come out zero-sized when the rectangle is too small for its constraints; a widget drawn into it simply draws nothing

### `dybatpho::screen_begin`

- The restore is registered on `EXIT`, `INT` and `TERM`, so a killed application still gives the terminal back

### `dybatpho::screen_event`

- A resize is delivered as an event rather than acted on, so an application redraws at a moment of its choosing instead of in the middle of a frame

### `dybatpho::screen_block`

- `border:` takes `plain`, `rounded`, `double`, `thick`, or `none`; `none` still reserves no space, so the inner rectangle is the whole one

### `dybatpho::screen_text`

- `wrap:false` keeps one source line on one row and cuts what does not fit, which is what a status line wants

### `dybatpho::screen_list`

- Pass `pointer:false` for a list that marks the selection by highlight alone, which reads better in a narrow column

### `dybatpho::screen_table`

- `widths:` takes a comma-separated list of column widths; without it the columns share the space evenly

### `dybatpho::screen_gauge`

- Leave `label:` out for the percentage, or pass an empty one for a bar with no text at all

### `dybatpho::screen_sparkline`

- Without `max:` the line scales to its own largest value, so a quiet series still fills the row

### `dybatpho::screen_barchart`

- Bars are drawn with eighth-width blocks, so a bar is accurate to an eighth of a column rather than rounded to a whole one

### `dybatpho::screen_chart`

- A rectangle of 40x10 is 400 cells and costs a few milliseconds; a full-screen chart is where this model stops being cheap

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_screen_expect_int`

Validate a whole number, or end the script naming what was wrong.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the caller, used in the message |
| `$2` | string | Description of the value, used in the message |
| `$3` | string | Value to check |
| `$4` | number | Smallest value accepted |


---

### `__dybatpho_screen_is_ascii`

Return success when a string is nothing but printable ASCII,
which is the case where one character is one index and one column, so no
measuring is needed at all.

The test is `[:ascii:]` rather than a byte range under a local `LC_ALL=C`.
Assigning `LC_ALL` makes Bash reload its locale data on the way in and again
on the way out, which measured at 47 microseconds a call against 14 for this
form -- and this sits under every segment of every frame.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to classify |

**🚦 Exit codes**

- `0`: The text is ASCII
- `1`: The text holds a character that may not be one column wide


---

### `__dybatpho_screen_indexes_bytes`

Report whether Bash indexes strings by byte in this locale.
Under a UTF-8 locale a multi-byte character is one index and `printf '%d'`
reports its codepoint; under `C` both count bytes, and a character has to be
reassembled before it can be measured.

**🚦 Exit codes**

- `0`: Bash counts bytes
- `1`: Bash counts characters


---

### `__dybatpho_screen_chars_into`

Split text into characters, whatever the locale indexes by.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the characters |
| `$2` | string | Text to split |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_screen_codepoint_into`

Decode one character to its Unicode codepoint, including when
the locale makes Bash index by byte and the character arrives as its UTF-8
bytes.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the codepoint |
| `$2` | string | One character |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_char_width_into`

Return the number of columns one character occupies, against the
embedded Unicode tables. Every character measured is remembered, so a screen
redrawn sixty times a second measures each distinct glyph once.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the width |
| `$2` | string | One character |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `dybatpho::screen_width`

Return the number of terminal columns a string occupies.

Text that is nothing but printable ASCII is its own length, which is the
overwhelmingly common case and is answered without looking at a single
character.

**🧪 Example**

```bash
local columns
dybatpho::screen_width columns "漢字ab"   # 6

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the width |
| `$2` | string | Text to measure |

**🧩 Variable sets**

- **`The`** (named): variable

**🚦 Exit codes**

- `0`: Always


---

### `__dybatpho_screen_width_into`

Measure a string, without validating the target name.
Painting calls this for every segment it draws, and the check in the public
entry point is worth a regular expression per frame, not per segment.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the width |
| `$2` | string | Text to measure |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_truncate_into`

Cut a string down to a number of columns, never splitting a
character in half and never leaving half of a double-width glyph behind.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the text |
| `$2` | string | Text to cut |
| `$3` | number | Columns available |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_index_into`

Return the string index that a display column falls at in a row.
A row of plain ASCII answers immediately; any other row is walked once.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the index |
| `$2` | number | Row |
| `$3` | number | Display column |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_style_set`

Replace a span of style runs on a row with one run, restoring
whatever style was in force at the far end.

Runs are kept instead of one style per cell because a row holds a handful of
runs and a few hundred cells: painting and rendering then cost what was
drawn rather than how wide the terminal is.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Row |
| `$2` | number | First column covered |
| `$3` | number | First column past the span |
| `$4` | string | SGR parameters |


---

### `dybatpho::screen_put`

Draw text into the buffer at one position, clipped to the screen.
Nothing reaches the terminal until `dybatpho::screen_flush` runs.

**🧪 Example**

```bash
dybatpho::screen_put 2 4 "Ready" "1;32"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Row, zero-based |
| `$2` | number | Column, zero-based |
| `$3` | string | Text to draw, without escape sequences |
| `$4` | string | Optional SGR parameters, default is `0` |

**🚦 Exit codes**

- `0`: Always, including when the position is off screen


---

### `__dybatpho_screen_render_into`

Build the escape sequence for one row from its text and runs.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the sequence |
| `$2` | number | Row |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `dybatpho::screen_clear`

Reset the buffer to blank, which is where every frame starts.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_size`

Resize the buffer to the terminal, and report whether it changed.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_WIDTH`** (number): Columns the buffer now holds
- **`DYBATPHO_SCREEN_HEIGHT`** (number): Rows the buffer now holds
- **`DYBATPHO_SCREEN_RECT`** (string): The whole terminal as a rectangle

**🚦 Exit codes**

- `0`: The size changed and the buffer was rebuilt
- `1`: The size is unchanged


---

### `dybatpho::screen_flush`

Write the rows that changed since the last frame to the terminal.

_Function has no arguments._

**📤 Output on stderr**

- Nothing; the frame goes to the terminal directly

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_rect`

Build a rectangle from its parts.

**🧪 Example**

```bash
local box
dybatpho::screen_rect box 0 0 40 10

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the rectangle |
| `$2` | number | Column of the left edge, zero-based |
| `$3` | number | Row of the top edge, zero-based |
| `$4` | number | Width in columns |
| `$5` | number | Height in rows |

**🧩 Variable sets**

- **`The`** (named): variable to `x y width height`


---

### `dybatpho::screen_layout`

Split a rectangle into parts that satisfy a list of constraints.

The constraints are the ones `ratatui` uses, and they are resolved in the
same order of authority: the fixed sizes are taken out first, what is left
is shared between the flexible ones, and the last part absorbs the rounding
so the pieces always add up to the whole.

| Constraint | Meaning |
| --- | --- |
| `length:N` | exactly `N` |
| `percent:N` | `N` percent of the rectangle |
| `ratio:A/B` | the fraction `A/B` of the rectangle |
| `min:N` | at least `N`, and grows into what is left |
| `max:N` | at most `N`, and grows into what is left |
| `fill:W` | no size of its own; shares what is left by weight `W` |



**🧪 Example**

```bash
local -a rows=()
dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" \
  length:3 fill:1 length:1
# rows[0] is a three-row header, rows[2] a one-row footer,
# rows[1] is everything in between

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the rectangles |
| `$2` | string | `vertical` to split the height, `horizontal` to split the width |
| `$3` | string | Rectangle to split |
| `$@` | string | One constraint per part |

**🧩 Variable sets**

- **`The`** (named): array, one rectangle per constraint, in order

**🚦 Exit codes**

- `1`: The direction is unknown, or a constraint is malformed


---

### `dybatpho::screen_rect_inner`

Shrink a rectangle by a margin on every side.

**🧪 Example**

```bash
local inner
dybatpho::screen_rect_inner inner "${box}" 1

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the rectangle |
| `$2` | string | Rectangle to shrink |
| `$3` | number | Optional margin in cells, default is `1` |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `dybatpho::screen_rect_center`

Centre a rectangle of a given size inside another, which is what
a popup needs.

**🧪 Example**

```bash
local popup
dybatpho::screen_rect_center popup "${DYBATPHO_SCREEN_RECT}" 40 10

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the rectangle |
| `$2` | string | Rectangle to centre inside |
| `$3` | number | Width of the centred rectangle |
| `$4` | number | Height of the centred rectangle |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_on_resize`

Note that the terminal changed size, so the next event reports it.


---

### `dybatpho::screen_begin`

Take over the terminal: alternate screen, raw mode, hidden
cursor, and mouse reporting.

The terminal is opened directly rather than taken from stdin and stdout, so
an application can still read a pipe and print a result that a caller
captures while it is drawing.

**🧪 Example**

```bash
dybatpho::screen_begin
dybatpho::trap dybatpho::screen_end EXIT

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SCREEN_MOUSE`** | bool | Turns mouse reporting on |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_ACTIVE`** (bool): `true`
- **`DYBATPHO_SCREEN_WIDTH`** (number): Columns of the terminal
- **`DYBATPHO_SCREEN_HEIGHT`** (number): Rows of the terminal
- **`DYBATPHO_SCREEN_RECT`** (string): The whole terminal as a rectangle

**🚦 Exit codes**

- `1`: There is no terminal to take over


---

### `exec`



---

### `exec`



---

### `dybatpho::screen_end`

Give the terminal back: mouse reporting off, cursor shown, the
alternate screen left, and the original line settings restored.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_ACTIVE`** (bool): `false`

**🚦 Exit codes**

- `0`: Always, so it is safe in a trap and safe to call twice


---

### `exec`



---

### `dybatpho::screen_event`

Wait for the next event and report it under a stable name.

Keys come back as `up`, `down`, `left`, `right`, `enter`, `space`, `tab`,
`backspace`, `escape`, `home`, `end`, `pageup`, `pagedown`, `delete`, or
`char:<c>`. A terminal that changed size reports `resize`, a mouse click
reports `mouse:<button>`, and a closed input reports `eof`.

**🧪 Example**

```bash
dybatpho::screen_event key
case "${key}" in
  char:q | escape) break ;;
  resize) dybatpho::screen_size && continue ;;
  mouse:left) _click "${DYBATPHO_SCREEN_MOUSE_ROW}" "${DYBATPHO_SCREEN_MOUSE_COLUMN}" ;;
esac

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the event |
| `$2` | string | Optional timeout in seconds; without one the call waits |

**🧩 Variable sets**

- **`The`** (named): variable
- **`DYBATPHO_SCREEN_MOUSE_COLUMN`** (number): Zero-based column of a mouse event
- **`DYBATPHO_SCREEN_MOUSE_ROW`** (number): Zero-based row of a mouse event

**🚦 Exit codes**

- `0`: An event was read
- `1`: The timeout passed with no event, and the variable is set to `timeout`


---

### `__dybatpho_screen_read_escape`

Read the rest of an escape sequence and name it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the event |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_screen_read_char`

Read one character with a timeout.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the character |
| `$2` | string | Timeout in seconds |

**🧩 Variable sets**

- **`The`** (named): variable

**🚦 Exit codes**

- `1`: Nothing arrived before the timeout


---

### `__dybatpho_screen_parse_mouse`

Turn an SGR mouse report into an event name and a position.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the event |
| `$2` | string | Body of the escape sequence, starting with `<` |

**🧩 Variable sets**

- **`The`** (named): variable, `DYBATPHO_SCREEN_MOUSE_COLUMN`, `DYBATPHO_SCREEN_MOUSE_ROW`


---

### `__dybatpho_screen_options`

Read `key:value` widget options into an associative array.
Anything without a colon is left in place for the widget to read as a
positional argument.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the associative array receiving the options |
| `$@` | string | The options |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_screen_copy_array`

Copy a caller's array into one of the module's own.

Only namespaced locals exist in this function's scope, so a nameref bound to
a caller's array finds that array rather than a local of the same name. The
widgets that take small arrays copy through it instead of namespacing every
local they have; the ones that may be handed a long array bind the nameref
directly and namespace their locals instead, to avoid copying every frame.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array to fill |
| `$2` | string | Name of the array to copy |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_screen_align_into`

Pad text to a width, aligning it within the space.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the padded text |
| `$2` | string | Text |
| `$3` | number | Width in columns |
| `$4` | string | `left`, `center`, or `right` |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `dybatpho::screen_block`

Draw a bordered box, optionally titled, and report the area left
inside it.

The inner rectangle is published rather than returned, because a block is
almost always followed by a widget drawn inside it and computing that
rectangle by hand is where off-by-one borders come from.

**🧪 Example**

```bash
dybatpho::screen_block "${rect}" title:"Pods" border:rounded
dybatpho::screen_list "${DYBATPHO_SCREEN_INNER}" items selected:2

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$@` | string | Options: `title:`, `border:`, `style:`, `title_style:`, `align:` |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_INNER`** (string): The rectangle inside the border

**🚦 Exit codes**

- `0`: Always, including when the rectangle is too small to draw


---

### `dybatpho::screen_text`

Draw text in a rectangle, wrapped and aligned.

**🧪 Example**

```bash
dybatpho::screen_text "${rect}" "${message}" align:center style:"1;33"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Text; embedded newlines start a new line |
| `$@` | string | Options: `style:`, `align:`, `wrap:` |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_list`

Draw a scrollable list of items with one of them selected.

The list scrolls itself: the offset that keeps the selected item on screen
is worked out here and published, so an application only tracks which item
is selected.

**🧪 Example**

```bash
local -a items=(alpha beta gamma)
dybatpho::screen_list "${rect}" items selected:1

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the items |
| `$@` | string | Options: `selected:`, `offset:`, `style:`, `selected_style:`, `pointer:` |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_OFFSET`** (number): Index of the first item drawn

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_table`

Draw a table with a header and an optional selected row.

**🧪 Example**

```bash
local -a rows=("api|running|3" "worker|idle|1")
dybatpho::screen_table "${rect}" rows header:"NAME|STATE|COUNT" selected:0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the rows |
| `$@` | string | Options: `header:`, `delimiter:`, `widths:`, `selected:`, `style:`, `header_style:`, `selected_style:` |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_OFFSET`** (number): Index of the first row drawn

**🚦 Exit codes**

- `0`: Always


---

### `__dybatpho_screen_table_row_into`



---

### `dybatpho::screen_gauge`

Draw a horizontal gauge filled to a ratio, with a label centred
on it.

**🧪 Example**

```bash
dybatpho::screen_gauge "${rect}" 42 100 label:"42% used" style:"1;32"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | number | Value reached |
| `$3` | number | Value that counts as full, at least 1 |
| `$@` | string | Options: `label:`, `style:`, `empty_style:`, `filled:`, `empty:` |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_tabs`

Draw a row of tabs with one of them active.

**🧪 Example**

```bash
local -a names=(Overview Logs Settings)
dybatpho::screen_tabs "${rect}" names active:0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the tab titles |
| `$@` | string | Options: `active:`, `style:`, `active_style:`, `divider:` |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_scrollbar`

Draw a vertical scrollbar showing where a window sits in a list
longer than the screen.

**🧪 Example**

```bash
dybatpho::screen_scrollbar "${rect}" "${DYBATPHO_SCREEN_OFFSET}" "${#items[@]}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in, normally one column wide |
| `$2` | number | Index of the first visible item |
| `$3` | number | Number of items in total |
| `$@` | string | Options: `style:`, `track_style:`, `thumb:`, `track:` |

**🚦 Exit codes**

- `0`: Always, including when everything fits and no bar is needed


---

### `dybatpho::screen_sparkline`

Draw a one-row sparkline from a series of numbers.

**🧪 Example**

```bash
local -a samples=(3 7 2 9 4)
dybatpho::screen_sparkline "${rect}" samples style:"36"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the values |
| `$@` | string | Options: `style:`, `max:` |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_barchart`

Draw horizontal bars, one per value, with optional labels.

**🧪 Example**

```bash
local -a values=(12 30 7) names=(api worker cron)
dybatpho::screen_barchart "${rect}" values labels:names

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the values |
| `$@` | string | Options: `labels:` naming an array, `style:`, `label_width:`, `max:` |

**🚦 Exit codes**

- `0`: Always


---

### `__dybatpho_screen_braille_table`

Fill the Braille lookup table, once.

The table is built with a single `printf`: the format string is assembled
from `\Uxxxxxxxx` escapes first and expanded in one call, rather than
calling out once per character.


---

### `dybatpho::screen_chart`

Plot a series as a line chart, using Braille dots for a
resolution of two points across and four down inside every character.

This is the one widget that works a cell at a time, because a chart is the
one thing whose every cell differs. It is bounded by the rectangle it is
given, so a chart in a corner of the screen costs what that corner is worth
rather than what the whole screen would be.

**🧪 Example**

```bash
local -a series=(1 4 2 8 5 9 3)
dybatpho::screen_chart "${rect}" series style:"32"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in |
| `$2` | string | Name of the array holding the values |
| `$@` | string | Options: `style:`, `max:`, `min:` |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_popup`

Blank a rectangle and draw a block over it, which is what a
dialog or a menu laid over the screen needs.

Whatever was underneath is erased rather than shown through, so the popup
can be drawn last over a frame that knows nothing about it.

**🧪 Example**

```bash
local popup
dybatpho::screen_rect_center popup "${DYBATPHO_SCREEN_RECT}" 40 7
dybatpho::screen_popup "${popup}" title:"Confirm"
dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" "Delete the record?" align:center

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to clear and draw in |
| `$@` | string | Options, the same ones `dybatpho::screen_block` takes |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_INNER`** (string): The rectangle inside the border

**🚦 Exit codes**

- `0`: Always
