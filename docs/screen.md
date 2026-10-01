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
| **`DYBATPHO_SCREEN_STYLE_FOCUS`** | string | SGR parameters for the border of a block drawn with `focus:true`. Default `1` |
| **`DYBATPHO_SCREEN_STYLE_TAB_ACTIVE`** | string | SGR parameters for the active tab. Default `1;7` |
| **`DYBATPHO_SCREEN_STYLE_KEYBAR`** | string | SGR parameters for the background of a key bar. Default `7` |
| **`DYBATPHO_SCREEN_STYLE_KEY`** | string | SGR parameters for a key named in a key bar. Default `1` |
| **`DYBATPHO_SCREEN_STYLE_ACCENT`** | string | SGR parameters an application uses for what should stand out. Default `1` |
| **`DYBATPHO_SCREEN_STYLE_DIM`** | string | SGR parameters for secondary text, and for the divider between tabs. Default `2` |
| **`DYBATPHO_SCREEN_STYLE_OK`** | string | SGR parameters for success. Default `32` |
| **`DYBATPHO_SCREEN_STYLE_WARN`** | string | SGR parameters for a warning. Default `33` |
| **`DYBATPHO_SCREEN_STYLE_ERROR`** | string | SGR parameters for an error. Default `31` |
| **`DYBATPHO_SCREEN_WIDTH`** | number | Columns of the terminal the buffer is sized for |
| **`DYBATPHO_SCREEN_HEIGHT`** | number | Rows of the terminal the buffer is sized for |
| **`DYBATPHO_SCREEN_RECT`** | string | The whole terminal as a rectangle, `x y width height` |
| **`DYBATPHO_SCREEN_ACTIVE`** | bool | `true` between `dybatpho::screen_begin` and `dybatpho::screen_end` |
| **`DYBATPHO_SCREEN_MOUSE_COLUMN`** | number | Zero-based column of the last mouse event |
| **`DYBATPHO_SCREEN_MOUSE_ROW`** | number | Zero-based row of the last mouse event |
| **`DYBATPHO_SCREEN_INNER`** | string | Rectangle left inside the last block or popup |
| **`DYBATPHO_SCREEN_OFFSET`** | number | Index of the first item the last list or table drew, after it scrolled to keep the selection visible |

### 🚀 Highlights

- [`dybatpho::screen_width`](#dybatphoscreen_width) — Return the number of terminal columns a string occupies. Text that is nothing but printable ASCII is its own length, which is the overwhelmingly common case and is answered without looking at a single character.
- [`dybatpho::screen_put`](#dybatphoscreen_put) — Draw text into the buffer at one position, clipped to the screen. Nothing reaches the terminal until `dybatpho::screen_flush` runs.
- [`dybatpho::screen_clear`](#dybatphoscreen_clear) — Reset the buffer to blank, which is where every frame starts.
- [`dybatpho::screen_size`](#dybatphoscreen_size) — Resize the buffer to the terminal, and report whether it changed.
- [`dybatpho::screen_flush`](#dybatphoscreen_flush) — Write the rows that changed since the last frame to the terminal.
- [`dybatpho::screen_rect`](#dybatphoscreen_rect) — Build a rectangle from its parts.
- [`dybatpho::screen_layout`](#dybatphoscreen_layout) — Split a rectangle into parts that satisfy a list of constraints. The constraints are the ones `ratatui` uses, and they are resolved in the same order of authority: the fixed sizes are taken out first, what is left is shared between the flexible ones, and the last part absorbs the rounding so the pieces always add up to the whole. | Constraint | Meaning | | --- | --- | | `length:N` | exactly `N` | | `percent:N` | `N` percent of the rectangle | | `ratio:A/B` | the fraction `A/B` of the rectangle | | `min:N` | at least `N`, and grows into what is left | | `max:N` | at most `N`, and grows into what is left | | `fill:W` | no size of its own; shares what is left by weight `W` |
- [`dybatpho::screen_rect_inner`](#dybatphoscreen_rect_inner) — Shrink a rectangle by a margin on every side.
- [`dybatpho::screen_rect_center`](#dybatphoscreen_rect_center) — Centre a rectangle of a given size inside another, which is what a popup needs.
- [`dybatpho::screen_begin`](#dybatphoscreen_begin) — Take over the terminal: alternate screen, raw mode, hidden cursor, and mouse reporting. The terminal is opened directly rather than taken from stdin and stdout, so an application can still read a pipe and print a result that a caller captures while it is drawing.
- [`exec`](#exec) — 
- [`exec`](#exec) — 
- [`dybatpho::screen_end`](#dybatphoscreen_end) — Give the terminal back: mouse reporting off, cursor shown, the alternate screen left, and the original line settings restored.
- [`dybatpho::screen_event`](#dybatphoscreen_event) — Wait for the next event and report it under a stable name. Keys come back as `up`, `down`, `left`, `right`, `enter`, `space`, `tab`, `backspace`, `escape`, `home`, `end`, `pageup`, `pagedown`, `delete`, or `char:<c>`. A terminal that changed size reports `resize`, a mouse click reports `mouse:<button>`, and a closed input reports `eof`.
- [`dybatpho::screen_pending`](#dybatphoscreen_pending) — Return success when an event is already waiting, so reading it with `dybatpho::screen_event` will not block. A frame drawn in Bash takes longer than a terminal takes to repeat a held key, so an application that draws once per event falls further behind for as long as the key is held, and keeps moving after it is released. Handling every event that is waiting before drawing the next frame keeps the screen in step with the keyboard instead.
- [`dybatpho::screen_block`](#dybatphoscreen_block) — Draw a bordered box, optionally titled, and report the area left inside it. The inner rectangle is published rather than returned, because a block is almost always followed by a widget drawn inside it and computing that rectangle by hand is where off-by-one borders come from.
- [`dybatpho::screen_text`](#dybatphoscreen_text) — Draw text in a rectangle, wrapped and aligned.
- [`dybatpho::screen_list`](#dybatphoscreen_list) — Draw a scrollable list of items with one of them selected. The list scrolls itself: the offset that keeps the selected item on screen is worked out here and published, so an application only tracks which item is selected.
- [`dybatpho::screen_table`](#dybatphoscreen_table) — Draw a table with a header and an optional selected row.
- [`dybatpho::screen_gauge`](#dybatphoscreen_gauge) — Draw a horizontal gauge filled to a ratio, with a label centred on it.
- [`dybatpho::screen_tabs`](#dybatphoscreen_tabs) — Draw a row of tabs with one of them active.
- [`dybatpho::screen_scrollbar`](#dybatphoscreen_scrollbar) — Draw a vertical scrollbar showing where a window sits in a list longer than the screen.
- [`dybatpho::screen_sparkline`](#dybatphoscreen_sparkline) — Draw a one-row sparkline from a series of numbers.
- [`dybatpho::screen_barchart`](#dybatphoscreen_barchart) — Draw horizontal bars, one per value, with optional labels.
- [`dybatpho::screen_chart`](#dybatphoscreen_chart) — Plot a series as a line chart, using Braille dots for a resolution of two points across and four down inside every character. This is the one widget that works a cell at a time, because a chart is the one thing whose every cell differs. It is bounded by the rectangle it is given, so a chart in a corner of the screen costs what that corner is worth rather than what the whole screen would be.
- [`dybatpho::screen_popup`](#dybatphoscreen_popup) — Blank a rectangle and draw a block over it, which is what a dialog or a menu laid over the screen needs. Whatever was underneath is erased rather than shown through, so the popup can be drawn last over a frame that knows nothing about it.
- [`dybatpho::screen_spans`](#dybatphoscreen_spans) — Draw pieces of text side by side on one row, each in its own style, cut to a width. This is what a row needs as soon as it is more than one colour -- a check mark in green before a name in bold, a key in a key bar before what it does -- and what `dybatpho::screen_list` cannot do, because it styles a whole row at once. With a background, every piece is drawn over it and the rest of the width is filled with it, so a selected row or a status bar reads as one band.
- [`dybatpho::screen_ansi`](#dybatphoscreen_ansi) — Draw a line that carries its own SGR colour sequences -- the output of a command, a log written by another program -- keeping its colours. Each sequence changes the style of the text after it, the way a terminal reads it: parameters accumulate until a reset. A sequence that is not a colour change, such as a cursor movement, is dropped rather than drawn, because it would move the cursor out of the frame.
- [`dybatpho::screen_keybar`](#dybatphoscreen_keybar) — Draw a one-row bar of key hints: each key in `DYBATPHO_SCREEN_STYLE_KEY`, what it does after it, all over `DYBATPHO_SCREEN_STYLE_KEYBAR` across the whole width.
- [`dybatpho::screen_theme`](#dybatphoscreen_theme) — Set every `DYBATPHO_SCREEN_STYLE_*` variable from a named palette, so an application gets a consistent look without choosing a colour for each widget. | Theme | Look | | --- | --- | | `default` | the module's own defaults: bold, dim, reverse and the eight basic colours | | `dusk` | a 256-colour palette: violet frames and selection, soft green, amber and red | | `mono` | no colour at all, only bold, dim and reverse | `NO_COLOR` turns `dusk` into `mono`, so an application can ask for colour and still respect a user who does not want it.

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

### `dybatpho::screen_pending`

- Nothing is consumed: the event is still there for the next `dybatpho::screen_event`

### `dybatpho::screen_block`

- `border:` takes `plain`, `rounded`, `double`, `thick`, or `none`; `none` still reserves no space, so the inner rectangle is the whole one
- `focus:true` draws the border in `DYBATPHO_SCREEN_STYLE_FOCUS`, which is how the panel that takes the keys stands out from the others; an explicit `style:` still wins

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

### `dybatpho::screen_spans`

- The background comes before each piece's own style, so a piece keeps its colours over it; a piece styled `""` or `0` is drawn in the background alone

### `dybatpho::screen_ansi`

- Strip `\r` and expand tabs before passing a line; they are control characters, not text with a width

<a id="reference"></a>
## 📚 Reference

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

### `dybatpho::screen_pending`

Return success when an event is already waiting, so reading it
with `dybatpho::screen_event` will not block.

A frame drawn in Bash takes longer than a terminal takes to repeat a held
key, so an application that draws once per event falls further behind for
as long as the key is held, and keeps moving after it is released. Handling
every event that is waiting before drawing the next frame keeps the screen
in step with the keyboard instead.

**🧪 Example**

```bash
while true; do
  _draw
  dybatpho::screen_flush
  dybatpho::screen_event key || continue
  _handle "${key}"
  while dybatpho::screen_pending; do
    dybatpho::screen_event key
    _handle "${key}"
  done
done

```

_Function has no arguments._

**🚦 Exit codes**

- `0`: A key, or a resize, is waiting
- `1`: Nothing is waiting


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
| `$@` | string | Options: `title:`, `border:`, `style:`, `title_style:`, `align:`, `focus:` |

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
| `$@` | string | Options: `active:`, `style:`, `active_style:`, `divider:`, `divider_style:` |

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


---

### `dybatpho::screen_spans`

Draw pieces of text side by side on one row, each in its own
style, cut to a width.

This is what a row needs as soon as it is more than one colour -- a check
mark in green before a name in bold, a key in a key bar before what it does
-- and what `dybatpho::screen_list` cannot do, because it styles a whole row
at once. With a background, every piece is drawn over it and the rest of
the width is filled with it, so a selected row or a status bar reads as one
band.

**🧪 Example**

```bash
dybatpho::screen_spans 3 2 30 "" "✔ " "32" "ripgrep" "1" " 2s" "2"
dybatpho::screen_spans 4 2 30 "48;5;237" "▌ " "1;35" "selected row" "1"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Row, zero-based |
| `$2` | number | Column, zero-based |
| `$3` | number | Width in columns |
| `$4` | string | SGR parameters of the background, or empty for none |
| `$@` | string | Pairs of text and its SGR parameters |

**🚦 Exit codes**

- `0`: Always; a piece that does not fit is cut, and the pieces after it are dropped


---

### `dybatpho::screen_ansi`

Draw a line that carries its own SGR colour sequences -- the
output of a command, a log written by another program -- keeping its
colours.

Each sequence changes the style of the text after it, the way a terminal
reads it: parameters accumulate until a reset. A sequence that is not a
colour change, such as a cursor movement, is dropped rather than drawn,
because it would move the cursor out of the frame.

**🧪 Example**

```bash
dybatpho::screen_ansi 5 1 60 $'\033[1;32mok\033[0m installed ripgrep'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Row, zero-based |
| `$2` | number | Column, zero-based |
| `$3` | number | Width in columns |
| `$4` | string | The line, with its escape sequences |

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::screen_keybar`

Draw a one-row bar of key hints: each key in
`DYBATPHO_SCREEN_STYLE_KEY`, what it does after it, all over
`DYBATPHO_SCREEN_STYLE_KEYBAR` across the whole width.

**🧪 Example**

```bash
dybatpho::screen_keybar "${footer}" "↑↓" "move" "space" "pick" "q" "quit"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rectangle to draw in; only its first row is used |
| `$@` | string | Pairs of a key and what it does |

**🚦 Exit codes**

- `0`: Always; hints that do not fit are cut at the edge


---

### `dybatpho::screen_theme`

Set every `DYBATPHO_SCREEN_STYLE_*` variable from a named
palette, so an application gets a consistent look without choosing a
colour for each widget.

| Theme | Look |
| --- | --- |
| `default` | the module's own defaults: bold, dim, reverse and the eight basic colours |
| `dusk` | a 256-colour palette: violet frames and selection, soft green, amber and red |
| `mono` | no colour at all, only bold, dim and reverse |

`NO_COLOR` turns `dusk` into `mono`, so an application can ask for colour
and still respect a user who does not want it.

**🧪 Example**

```bash
dybatpho::screen_theme dusk
dybatpho::screen_block "${rect}" title:"Tools" focus:true

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Theme name: `default`, `dusk`, or `mono` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`NO_COLOR`** | string | Use `mono` in place of a coloured theme when set to a non-empty value |

**🧩 Variable sets**

- **`DYBATPHO_SCREEN_STYLE_*`** (string): Every style variable of the module, from the palette

**🚦 Exit codes**

- `0`: The theme was applied
- `1`: The theme is unknown, and nothing was changed
