# tui.sh

Interactive terminal widgets: spinners, progress bars, menus, and confirmations

> 🧭 Source: [src/tui.sh](../src/tui.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`cli.sh` turns a declarative spec into a parser, a help screen, and
completions -- everything a command line needs before it runs. This module
covers what happens once it is running and has to talk to a person: a
spinner the script starts and stops around work of its own, a progress bar
it drives from a loop, arrow-key menus for one or several choices, and a
confirmation that reads as a question rather than a `[y/N]` stub.

Every widget has two renderings and the module chooses between them, rather
than asking the caller to. On a terminal it draws in place with ANSI escape
sequences and reads raw keys. Anywhere else -- a pipe, a log file, CI, a
`$( )` -- it falls back to the numbered prompts of `cli.sh` and to ordinary
log lines. A script therefore calls the same function in both places, which
is why the example and the tests in this repository exercise the whole
interactive API without a terminal attached.

Widgets draw on stderr. A value a script prints to stdout stays clean, so
the menus remain usable in a command substitution and the progress of a
pipeline never lands in its own output.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TUI`** | string | When widgets draw in place (`auto\|always\|never`). `auto` draws only when both stdin and stderr are terminals. Default `auto` |
| **`DYBATPHO_TUI_INTERVAL`** | string | Seconds between spinner frames. Default is `DYBATPHO_SPINNER_INTERVAL` |
| **`DYBATPHO_TUI_FRAMES`** | string | Space-separated frames the spinner cycles through. Default is `DYBATPHO_SPINNER_FRAMES` |
| **`DYBATPHO_TUI_BAR_WIDTH`** | number | Width of a progress bar in columns when none is given. Default `30` |
| **`DYBATPHO_TUI_BAR_FILLED`** | string | Character drawn for the completed part of a bar. Default `█` |
| **`DYBATPHO_TUI_BAR_EMPTY`** | string | Character drawn for the remaining part of a bar. Default `░` |
| **`DYBATPHO_TUI_PROGRESS_STEP`** | number | Percentage granularity of the progress lines logged when there is no terminal to draw on. `0` logs every update. Default `10` |
| **`DYBATPHO_TUI_POINTER`** | string | Marker drawn beside the highlighted menu entry. Default `❯` |
| **`DYBATPHO_TUI_CHECKED`** | string | Marker drawn beside a selected multi-select entry. Default `◉` |
| **`DYBATPHO_TUI_UNCHECKED`** | string | Marker drawn beside an unselected multi-select entry. Default `◯` |
| **`DYBATPHO_TUI_MENU_HEIGHT`** | number | Entries a drawn menu shows at once before it scrolls. Default `10` |
| **`DYBATPHO_TUI_DEFAULT`** | string | Comma-separated 1-based entries a menu starts on, and the answer it uses when the script cannot ask at all. Empty means no default, and a menu that cannot ask then fails instead of choosing |
| **`DYBATPHO_TUI_SPINNER_PID`** | number | PID of the running spinner, or empty when none is running |
| **`DYBATPHO_TUI_INDEX`** | number | 1-based position the last `dybatpho::tui_menu` returned |
| **`DYBATPHO_TUI_INDEXES`** | string | Space-separated 1-based positions the last `dybatpho::tui_multi_menu` returned |
| **`DYBATPHO_TUI_PROGRESS_CURRENT`** | number | Units of work the running progress bar has recorded |
| **`DYBATPHO_TUI_PROGRESS_TOTAL`** | number | Units of work the running progress bar expects in total |

### 🚀 Highlights

- [`dybatpho::tui_supported`](#dybatphotui_supported) — Return success when the widgets may draw in place and read raw keys, which is what separates the interactive rendering from the fallback. `auto` requires a terminal on both ends: stdin is where the keys come from, and stderr is where the frames go. A script whose diagnostics are piped still has a terminal on stdin, and drawing a menu into that pipe would corrupt it.
- [`__dybatpho_tui_sgr_into`](#__dybatpho_tui_sgr_into) — Return the SGR sequence for a style, or nothing when color is off.
- [`__dybatpho_tui_repeat_into`](#__dybatpho_tui_repeat_into) — Repeat a string into a named variable, without a subshell.
- [`__dybatpho_tui_hide_cursor`](#__dybatpho_tui_hide_cursor) — Hide the cursor while a widget is drawing, and arrange for it to come back however the script ends. A script killed mid-menu would otherwise leave the terminal with no cursor, and that outlives the script: it has to be undone by hand afterwards.
- [`__dybatpho_tui_show_cursor`](#__dybatpho_tui_show_cursor) — Show the cursor again, if a widget hid it.
- [`__dybatpho_tui_draw_line`](#__dybatpho_tui_draw_line) — Redraw the current line on stderr, erasing whatever was on it.
- [`__dybatpho_tui_erase_line`](#__dybatpho_tui_erase_line) — Erase the current line on stderr and leave the cursor at its start, so the next output begins on a clean column.
- [`__dybatpho_tui_duration_into`](#__dybatpho_tui_duration_into) — Format a whole number of seconds as a compact duration.
- [`__dybatpho_tui_expect_int`](#__dybatpho_tui_expect_int) — Validate a whole number, or end the script naming what was wrong.
- [`dybatpho::tui_bar`](#dybatphotui_bar) — Render a progress bar as text. This is the whole of the bar drawing, kept apart from the state the `dybatpho::tui_progress_*` helpers carry, so that a script with a progress model of its own can reuse the rendering and so that the rendering can be asserted without a terminal.
- [`__dybatpho_tui_spin`](#__dybatpho_tui_spin) — Animate the spinner on stderr until the shell that started it kills it, re-reading its message from the state file on every frame. Runs as a background job, so it never returns on its own.
- [`dybatpho::tui_spinner_start`](#dybatphotui_spinner_start) — Start a spinner that runs until `dybatpho::tui_spinner_stop` stops it. `dybatpho::spinner` wraps one command and is the right tool when the work is one command. This one brackets a region instead, which is what a script needs when the work is a loop, a pipeline, or a sequence whose steps deserve to be named as they happen. Without a terminal to draw on the message is logged once at `info`, so a CI log keeps the same narration without the frames.
- [`dybatpho::tui_spinner_message`](#dybatphotui_spinner_message) — Replace the message of the running spinner without restarting it.
- [`dybatpho::tui_spinner_stop`](#dybatphotui_spinner_stop) — Stop the running spinner, erase its line, and report the outcome.
- [`__dybatpho_tui_banner`](#__dybatpho_tui_banner) — Draw a closing banner for a widget, on stderr. `dybatpho::success` writes its banner to stdout, which is right for a script reporting its own result and wrong here: a widget that printed to stdout would land inside whatever captured the value the script was computing. The same box is drawn on stderr instead, so every byte this module emits goes to the same place.
- [`__dybatpho_tui_progress_render`](#__dybatpho_tui_progress_render) — Draw or log one frame of the running progress bar.
- [`dybatpho::tui_progress_start`](#dybatphotui_progress_start) — Start a progress bar over a known amount of work.
- [`dybatpho::tui_progress_update`](#dybatphotui_progress_update) — Move the progress bar to an absolute position.
- [`dybatpho::tui_progress_step`](#dybatphotui_progress_step) — Advance the progress bar by a number of units.
- [`dybatpho::tui_progress_stop`](#dybatphotui_progress_stop) — Finish the progress bar, leaving the line complete rather than part-drawn. The bar is filled to its total first: a loop that ended early would otherwise leave a terminal showing `80%` for work that is over, which reads as a hang rather than as a finish.
- [`__dybatpho_tui_read_key_into`](#__dybatpho_tui_read_key_into) — Read one keypress and report it under a stable name, so the menu loops never deal with escape sequences themselves.
- [`__dybatpho_tui_defaults_into`](#__dybatpho_tui_defaults_into) — Fill an array with the 1-based positions named by `DYBATPHO_TUI_DEFAULT`, dropping anything outside the menu.
- [`__dybatpho_tui_menu_fallback`](#__dybatpho_tui_menu_fallback) — Ask for a choice with a numbered prompt, which is the rendering used whenever the menu cannot be drawn. The answer is read through `dybatpho::prompt`, so a piped `2` and a typed `2` are the same thing, and an empty answer takes `DYBATPHO_TUI_DEFAULT`.
- [`__dybatpho_tui_menu_interactive`](#__dybatpho_tui_menu_interactive) — Draw a menu and drive it from the keyboard until it is answered or cancelled.
- [`dybatpho::tui_menu`](#dybatphotui_menu) — Ask the user to pick one entry from a list. The answer comes back through a named variable rather than on stdout, because both renderings write to stderr and a `$( )` around the call would swallow the menu it is supposed to show.
- [`dybatpho::tui_multi_menu`](#dybatphotui_multi_menu) — Ask the user to pick any number of entries from a list. The answer comes back in a named array, so entries holding spaces survive a round trip that a space-separated string would lose.
- [`dybatpho::tui_confirm`](#dybatphotui_confirm) — Ask a yes/no question with the answer shown as a choice rather than as a `[y/N]` hint. Off a terminal this is `dybatpho::confirm`: the same `DYBATPHO_FORCE` override, the same refusal to guess in an unattended shell, the same exit codes. On a terminal the two answers are drawn side by side with the default highlighted, `←`/`→` move between them, and `y`/`n` still answer directly.

<a id="see-also"></a>
## 🔗 See also

- [example/tui_ops.sh](../example/tui_ops.sh)
- [src/cli.sh](../src/cli.sh)
- [src/safety.sh](../src/safety.sh)

<a id="tips"></a>
## 💡 Tips

- `DYBATPHO_TUI=never` forces the fallback rendering everywhere, which is what a CI job wants; `DYBATPHO_TUI=always` forces the drawn one, which is what a demo recording wants
- A menu asks through `dybatpho::prompt` when it cannot draw, so feeding `2` to the script answers it the same way pressing `enter` on the second entry does -- with a redirect rather than a pipe, which would run the call in a subshell and lose the answer with it

### `dybatpho::tui_bar`

- The bar carries no carriage return of its own, so it composes with a label and can be written to a file as readily as to a terminal

### `dybatpho::tui_spinner_start`

- Registered secrets are masked before the message is drawn, exactly as the logging helpers mask them

### `dybatpho::tui_spinner_stop`

- `dybatpho::tui_spinner_stop "$?" "Done"` reports the work and keeps its exit status

### `dybatpho::tui_menu`

- Arrow keys and `j`/`k` both move, `enter` selects, and `esc` or `q` cancels

### `dybatpho::tui_multi_menu`

- `space` toggles an entry, `a` selects every entry and `n` clears them all; the numbered fallback takes the same list as `1,3`

### `dybatpho::tui_confirm`

- The question is the whole contract: a `--force` flag bound to `DYBATPHO_FORCE` makes every one of them answer yes at once

<a id="reference"></a>
## 📚 Reference

### `dybatpho::tui_supported`

Return success when the widgets may draw in place and read raw
keys, which is what separates the interactive rendering from the fallback.

`auto` requires a terminal on both ends: stdin is where the keys come from,
and stderr is where the frames go. A script whose diagnostics are piped
still has a terminal on stdin, and drawing a menu into that pipe would
corrupt it.

**🧪 Example**

```bash
dybatpho::tui_supported || dybatpho::info "No terminal; answering from flags"

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TUI`** | string | `auto` detects the terminals, `always` and `never` override the detection |

**🚦 Exit codes**

- `0`: Widgets draw in place
- `1`: Widgets fall back to prompts and log lines


---

### `__dybatpho_tui_sgr_into`

Return the SGR sequence for a style, or nothing when color is off.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the sequence |
| `$2` | string | Style, as the parameters of an SGR escape |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_tui_repeat_into`

Repeat a string into a named variable, without a subshell.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the result |
| `$2` | string | Text to repeat |
| `$3` | number | Number of repetitions |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_tui_hide_cursor`

Hide the cursor while a widget is drawing, and arrange for it to
come back however the script ends.

A script killed mid-menu would otherwise leave the terminal with no cursor,
and that outlives the script: it has to be undone by hand afterwards.

_Function has no arguments._


---

### `__dybatpho_tui_show_cursor`

Show the cursor again, if a widget hid it.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Always, so it cannot change the exit status of a trap


---

### `__dybatpho_tui_draw_line`

Redraw the current line on stderr, erasing whatever was on it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to draw |

**📤 Output on stderr**

- The text, preceded by a carriage return and followed by an erase


---

### `__dybatpho_tui_erase_line`

Erase the current line on stderr and leave the cursor at its
start, so the next output begins on a clean column.

_Function has no arguments._


---

### `__dybatpho_tui_duration_into`

Format a whole number of seconds as a compact duration.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the text |
| `$2` | number | Seconds |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_tui_expect_int`

Validate a whole number, or end the script naming what was wrong.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the caller, used in the message |
| `$2` | string | Description of the value, used in the message |
| `$3` | string | Value to check |
| `$4` | number | Smallest value accepted |


---

### `dybatpho::tui_bar`

Render a progress bar as text.

This is the whole of the bar drawing, kept apart from the state the
`dybatpho::tui_progress_*` helpers carry, so that a script with a progress
model of its own can reuse the rendering and so that the rendering can be
asserted without a terminal.

**🧪 Example**

```bash
dybatpho::tui_bar 3 4       # [██████████████████████░░░░░░░░]  75%
dybatpho::tui_bar 1 3 12    # [████░░░░░░░░]  33%

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Units of work completed, clamped to the total |
| `$2` | number | Units of work in total, at least 1 |
| `$3` | number | Optional bar width in characters, default is `DYBATPHO_TUI_BAR_WIDTH` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TUI_BAR_FILLED`** | string | Character drawn for the completed part |
| **`DYBATPHO_TUI_BAR_EMPTY`** | string | Character drawn for the remaining part |

**📤 Output on stdout**

- The bar and its percentage, with no trailing newline

**🚦 Exit codes**

- `1`: An argument is not a whole number, or is out of range


---

### `__dybatpho_tui_spin`

Animate the spinner on stderr until the shell that started it
kills it, re-reading its message from the state file on every frame. Runs as
a background job, so it never returns on its own.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path of the file holding the current message |

**📤 Output on stderr**

- One frame per interval, redrawn over the same line


---

### `dybatpho::tui_spinner_start`

Start a spinner that runs until `dybatpho::tui_spinner_stop`
stops it.

`dybatpho::spinner` wraps one command and is the right tool when the work is
one command. This one brackets a region instead, which is what a script
needs when the work is a loop, a pipeline, or a sequence whose steps deserve
to be named as they happen.

Without a terminal to draw on the message is logged once at `info`, so a CI
log keeps the same narration without the frames.

**🧪 Example**

```bash
dybatpho::tui_spinner_start "Resolving dependencies"
for module in "${modules[@]}"; do
  dybatpho::tui_spinner_message "Resolving ${module}"
  _resolve "${module}"
done
dybatpho::tui_spinner_stop 0 "Resolved ${#modules[@]} modules"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message shown beside the frame |

**🧩 Variable sets**

- **`DYBATPHO_TUI_SPINNER_PID`** (number): PID of the animation, or empty when it is not animating

**📤 Output on stderr**

- The animation, or one log line when there is no terminal

**🚦 Exit codes**

- `1`: A spinner is already running


---

### `dybatpho::tui_spinner_message`

Replace the message of the running spinner without restarting it.

**🧪 Example**

```bash
dybatpho::tui_spinner_message "Uploading layer 3 of 7"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | New message |

**📤 Output on stderr**

- The next frame carries the new message, or one log line when there is no terminal

**🚦 Exit codes**

- `1`: A terminal is attached but no spinner is running


---

### `dybatpho::tui_spinner_stop`

Stop the running spinner, erase its line, and report the outcome.

**🧪 Example**

```bash
dybatpho::tui_spinner_stop 0 "Uploaded"
dybatpho::tui_spinner_stop 1 "Upload failed"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Optional exit status the work ended with, default is `0` |
| `$2` | string | Optional closing message, default is none |

**🧩 Variable sets**

- **`DYBATPHO_TUI_SPINNER_PID`** (string): Cleared

**📤 Output on stderr**

- A success or failure banner, when a message is given

**🚦 Exit codes**

- `The`: status passed in, so the call can both report and propagate an outcome


---

### `__dybatpho_tui_banner`

Draw a closing banner for a widget, on stderr.

`dybatpho::success` writes its banner to stdout, which is right for a
script reporting its own result and wrong here: a widget that printed to
stdout would land inside whatever captured the value the script was
computing. The same box is drawn on stderr instead, so every byte this
module emits goes to the same place.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Exit status the work ended with |
| `$2` | string | Message |

**📤 Output on stderr**

- The banner


---

### `__dybatpho_tui_progress_render`

Draw or log one frame of the running progress bar.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | bool | `true` when this is the closing frame |


---

### `dybatpho::tui_progress_start`

Start a progress bar over a known amount of work.

**🧪 Example**

```bash
dybatpho::tui_progress_start "Uploading" "${#files[@]}"
for file in "${files[@]}"; do
  _upload "${file}"
  dybatpho::tui_progress_step
done
dybatpho::tui_progress_stop "Uploaded ${#files[@]} files"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Label drawn in front of the bar |
| `$2` | number | Units of work in total, at least 1 |

**🧩 Variable sets**

- **`DYBATPHO_TUI_PROGRESS_TOTAL`** (number): Units of work expected
- **`DYBATPHO_TUI_PROGRESS_CURRENT`** (number): Reset to `0`

**📤 Output on stderr**

- The first frame, or one log line when there is no terminal

**🚦 Exit codes**

- `1`: The total is not a whole number of at least 1


---

### `dybatpho::tui_progress_update`

Move the progress bar to an absolute position.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Units of work completed, clamped to the total |
| `$2` | string | Optional new label |

**🧩 Variable sets**

- **`DYBATPHO_TUI_PROGRESS_CURRENT`** (number): Units recorded

**📤 Output on stderr**

- The redrawn bar, or a log line when the percentage crosses a reporting step

**🚦 Exit codes**

- `1`: No progress bar is running, or the position is not a whole number


---

### `dybatpho::tui_progress_step`

Advance the progress bar by a number of units.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Optional units to add, default is `1` |
| `$2` | string | Optional new label |

**🧩 Variable sets**

- **`DYBATPHO_TUI_PROGRESS_CURRENT`** (number): Units recorded

**🚦 Exit codes**

- `1`: No progress bar is running, or the increment is not a whole number


---

### `dybatpho::tui_progress_stop`

Finish the progress bar, leaving the line complete rather than
part-drawn.

The bar is filled to its total first: a loop that ended early would
otherwise leave a terminal showing `80%` for work that is over, which reads
as a hang rather than as a finish.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional closing message replacing the bar |

**🧩 Variable sets**

- **`DYBATPHO_TUI_PROGRESS_CURRENT`** (number): Set to the total

**📤 Output on stderr**

- The final frame, then a newline, or a closing log line

**🚦 Exit codes**

- `0`: Even when no progress bar was running, so it is safe to call from a trap


---

### `__dybatpho_tui_read_key_into`

Read one keypress and report it under a stable name, so the menu
loops never deal with escape sequences themselves.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the key name |

**🧩 Variable sets**

- **`The`** (named): variable to `up`, `down`, `left`, `right`, `enter`, `space`, `escape`, `eof`, or `char:<c>`


---

### `__dybatpho_tui_defaults_into`

Fill an array with the 1-based positions named by
`DYBATPHO_TUI_DEFAULT`, dropping anything outside the menu.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the positions |
| `$2` | number | Number of entries in the menu |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_tui_menu_fallback`

Ask for a choice with a numbered prompt, which is the rendering
used whenever the menu cannot be drawn.

The answer is read through `dybatpho::prompt`, so a piped `2` and a typed
`2` are the same thing, and an empty answer takes `DYBATPHO_TUI_DEFAULT`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the selection |
| `$2` | bool | `true` to accept several positions |
| `$3` | string | Prompt text |
| `$@` | string | Menu entries |

**🧩 Variable sets**

- **`The`** (named): variable, `DYBATPHO_TUI_INDEX`, and `DYBATPHO_TUI_INDEXES`

**🚦 Exit codes**

- `1`: Nothing could be read and there is no default


---

### `__dybatpho_tui_menu_interactive`

Draw a menu and drive it from the keyboard until it is answered
or cancelled.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the selection |
| `$2` | bool | `true` to accept several entries |
| `$3` | string | Prompt text |
| `$@` | string | Menu entries |

**🧩 Variable sets**

- **`The`** (named): variable, `DYBATPHO_TUI_INDEX`, and `DYBATPHO_TUI_INDEXES`

**🚦 Exit codes**

- `1`: The menu was cancelled


---

### `dybatpho::tui_menu`

Ask the user to pick one entry from a list.

The answer comes back through a named variable rather than on stdout,
because both renderings write to stderr and a `$( )` around the call would
swallow the menu it is supposed to show.

**🧪 Example**

```bash
local environment
dybatpho::tui_menu environment "Deploy to which environment?" dev staging prod \
  || dybatpho::die "No environment chosen"
dybatpho::info "Deploying to ${environment} (entry ${DYBATPHO_TUI_INDEX})"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the chosen entry |
| `$2` | string | Prompt text |
| `$@` | string | Menu entries, at least one |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TUI_DEFAULT`** | string | 1-based entry the menu starts on, and the answer used when it cannot ask |

**🧩 Variable sets**

- **`The`** (named): variable to the chosen entry
- **`DYBATPHO_TUI_INDEX`** (number): 1-based position of the chosen entry
- **`DYBATPHO_TUI_INDEXES`** (string): The same position, for symmetry with the multi-select

**📝 Notes**

- Feed the numbered fallback with a redirect (`< <(printf '2\n')`), never with a pipe. A pipe runs the call in a subshell, where the answer is written to a copy of the caller's variable and is lost on return.

**📤 Output on stderr**

- The menu, drawn in place or printed as a numbered list

**🚦 Exit codes**

- `1`: The menu was cancelled, or nothing could be read and no default was set


---

### `dybatpho::tui_multi_menu`

Ask the user to pick any number of entries from a list.

The answer comes back in a named array, so entries holding spaces survive a
round trip that a space-separated string would lose.

**🧪 Example**

```bash
local -a components=()
dybatpho::tui_multi_menu components "Which components?" api worker scheduler \
  || dybatpho::die "No component chosen"
dybatpho::info "Deploying ${#components[@]} components"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the chosen entries |
| `$2` | string | Prompt text |
| `$@` | string | Menu entries, at least one |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TUI_DEFAULT`** | string | Comma-separated entries preselected, and the answer used when the menu cannot ask |

**🧩 Variable sets**

- **`The`** (named): array to the chosen entries, in menu order
- **`DYBATPHO_TUI_INDEXES`** (string): Space-separated 1-based positions of the chosen entries

**📝 Notes**

- In the drawn menu, confirming with nothing toggled is a valid answer and returns an empty array, which is how "none of these" is said. The numbered fallback has no such keystroke, so an empty line there takes `DYBATPHO_TUI_DEFAULT` or fails
- Feed the numbered fallback with a redirect rather than a pipe, for the reason given on `dybatpho::tui_menu`

**📤 Output on stderr**

- The menu, drawn in place or printed as a numbered list

**🚦 Exit codes**

- `1`: The menu was cancelled, or nothing could be read and no default was set


---

### `dybatpho::tui_confirm`

Ask a yes/no question with the answer shown as a choice rather
than as a `[y/N]` hint.

Off a terminal this is `dybatpho::confirm`: the same `DYBATPHO_FORCE`
override, the same refusal to guess in an unattended shell, the same exit
codes. On a terminal the two answers are drawn side by side with the default
highlighted, `←`/`→` move between them, and `y`/`n` still answer directly.

**🧪 Example**

```bash
dybatpho::tui_confirm "Delete the staging database?" no \
  || dybatpho::die "Cancelled"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Question to ask |
| `$2` | string | Optional default answer used on `enter`, default is `no` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORCE`** | bool | Answer yes without asking |

**📤 Output on stderr**

- The question; nothing reaches stdout

**🚦 Exit codes**

- `0`: The answer is yes, or `DYBATPHO_FORCE` is enabled
- `1`: The answer is no, the question was cancelled, or the script is not interactive
