# validate.sh

One validator for the whole library: named value types and declarative rules

> 🧭 Source: [src/validate.sh](../src/validate.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Before this module every caller wrote its own check. `config` matched an
integer with one regex and a URL with another, `cli` matched a shell
variable name with a third, and a script that wanted an email address or an
existing path had nowhere to get one. The regexes drifted, the messages
drifted with them, and a fix in one place never reached the other.

This module owns the checks instead. A *type* is a name — `int`, `email`,
`url`, `ipv4`, `semver`, `file` — bound to a predicate, and
`dybatpho::validate_is` is the only call needed to apply one:

```sh
dybatpho::validate_is email "${address}" || dybatpho::die "Not an address"
```

A *rule* is the declarative form of the same idea, used where a value
arrives with constraints attached rather than a single type:
`dybatpho::validate_value` takes `type:`, `pattern:`, `choices:`, `min:`,
`max:`, `minlen:` and `maxlen:` and reports **every** violation it finds
rather than only the first, which is what lets `config` list a whole broken
file at once.

Nothing here shells out or touches the network, so the module depends on
the core modules alone and stays cheap enough for `config` and `cli` to
load unconditionally. The path types are the one exception to "pure
computation": they ask the filesystem, because "does this exist" cannot be
answered any other way.

`dybatpho::validate_register` adds a type of your own, which then works
everywhere a built-in type does, including in a `config` schema and in a
`cli` `type:` attribute.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_VALIDATE_ERRORS`** | array | Reasons recorded by the last `dybatpho::validate_value` call |

### 🚀 Highlights

- [`dybatpho::validate_matches`](#dybatphovalidate_matches) — Match a value against an extended regular expression, without letting a malformed expression reach the caller as a shell diagnostic. Bash answers a broken pattern with exit status 2 and a message of its own, which reads as a validation failure at the call site; here it is turned into the library's own fatal error instead.
- [`dybatpho::validate_is`](#dybatphovalidate_is) — Return success when a value is of the named type. A type is a name bound to a predicate: the built-ins listed by `dybatpho::validate_types`, plus anything added with `dybatpho::validate_register`.
- [`dybatpho::validate_describe`](#dybatphovalidate_describe) — Print the noun a message uses for a type, such as `an email address` for `email`. Error messages are built from this, so a caller that reports its own failure words it the same way the library does.
- [`dybatpho::validate_types`](#dybatphovalidate_types) — Print every registered type name, one per line, in alphabetical order. Aliases are not listed: they resolve to the names printed here.
- [`dybatpho::validate_register`](#dybatphovalidate_register) — Register a type, or replace one that is already registered. The predicate is a function taking the value as its only argument and returning success when the value is of the type; it must not print anything and must not terminate the script.
- [`dybatpho::validate_value`](#dybatphovalidate_value) — Validate one value against a list of declarative rules, and record every violation rather than stopping at the first. Supported rules: | Rule | Meaning | | --- | --- | | `type:<name>` | The value must be of that type; defaults to `string` | | `pattern:<ere>` | The value must match that extended regular expression | | `choices:a,b` | The value must be one of the listed choices | | `min:<n>` / `max:<n>` | Bounds; numeric for a numeric type, character count otherwise | | `minlen:<n>` / `maxlen:<n>` | Bounds on the character count, whatever the type | A value that is not of its declared type is not then measured against the other rules: `min:1` on something that is not a number has no answer worth reporting, and a second message about it only buries the first. The reasons are phrased to follow the name of whatever was validated, so a caller prints `Invalid configuration ${key}: ${reason}` without rewording them. `dybatpho::validate_errors` prints them.
- [`dybatpho::validate_errors`](#dybatphovalidate_errors) — Print the reasons recorded by the last `dybatpho::validate_value` call, one per line.
- [`dybatpho::validate_or_die`](#dybatphovalidate_or_die) — Validate a value and stop the script when it is rejected, naming what was being validated and every reason it failed.
- [`dybatpho::validate_reset`](#dybatphovalidate_reset) — Forget every type added with `dybatpho::validate_register` and restore the built-ins to their original predicates. A test or an example that registers a type of its own calls this to leave the registry the way it found it.

<a id="see-also"></a>
## 🔗 See also

- [example/validate_ops.sh](../example/validate_ops.sh)
- [dybatpho::config_schema](#dybatphoconfig_schema)
- [dybatpho::opts::param](#dybatphooptsparam)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::validate_matches`

Match a value against an extended regular expression, without
letting a malformed expression reach the caller as a shell diagnostic.
Bash answers a broken pattern with exit status 2 and a message of its own,
which reads as a validation failure at the call site; here it is turned into
the library's own fatal error instead.

**🧪 Example**

```bash
dybatpho::validate_matches "v1.2.3" '^v[0-9]'      # succeeds

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to match |
| `$2` | string | Extended regular expression |

**🚦 Exit codes**

- `0`: The value matches
- `1`: The value does not match
- `1`: Stop the script when the expression is not a valid ERE


---

### `dybatpho::validate_is`

Return success when a value is of the named type.
A type is a name bound to a predicate: the built-ins listed by
`dybatpho::validate_types`, plus anything added with
`dybatpho::validate_register`.

**🧪 Example**

```bash
dybatpho::validate_is int "42"                   # yes
dybatpho::validate_is email "ops@example.com"    # yes
dybatpho::validate_is dir "${HOME}"              # yes, it exists
dybatpho::validate_is ipv4 "192.0.2.256"         # no

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type name or alias |
| `$2` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is of that type
- `1`: The value is not
- `1`: Stop the script when the type is not registered

**🔗 See also**

- [- `dybatpho::validate_types` - `dybatpho::validate_register](#dybatphovalidate_types-dybatphovalidate_register)


---

### `dybatpho::validate_describe`

Print the noun a message uses for a type, such as `an email
address` for `email`. Error messages are built from this, so a caller that
reports its own failure words it the same way the library does.

**🧪 Example**

```bash
dybatpho::validate_describe int      # an integer
dybatpho::validate_describe url      # a URL

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type name or alias |

**📤 Output on stdout**

- The description

**🚦 Exit codes**

- `0`: The description is printed
- `1`: Stop the script when the type is not registered


---

### `dybatpho::validate_types`

Print every registered type name, one per line, in alphabetical
order. Aliases are not listed: they resolve to the names printed here.

_Function has no arguments._

**📤 Output on stdout**

- Canonical type names

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::validate_register`

Register a type, or replace one that is already registered.
The predicate is a function taking the value as its only argument and
returning success when the value is of the type; it must not print anything
and must not terminate the script.

**🧪 Example**

```bash
function _is_branch { [[ "$1" =~ ^(main|release/.+)$ ]]; }
dybatpho::validate_register branch _is_branch "a release branch"
dybatpho::validate_is branch "release/2.0"     # yes

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type name, lowercase letters, digits and underscores |
| `$2` | string | Predicate function name |
| `$3` | string | Description used in messages, such as `a release branch` |
| `$4` | string | Optional `numeric` to make `min:`/`max:` bound the value rather than its length |

**🧩 Variable sets**

- __DYBATPHO_VALIDATE_PREDICATES
- __DYBATPHO_VALIDATE_DESCRIPTIONS

**🚦 Exit codes**

- `0`: The type is registered
- `1`: Stop the script when the name is malformed or the predicate is not a function

**🔗 See also**

- [- `dybatpho::validate_reset](#dybatphovalidate_reset)


---

### `dybatpho::validate_value`

Validate one value against a list of declarative rules, and
record every violation rather than stopping at the first.

Supported rules:

| Rule | Meaning |
| --- | --- |
| `type:<name>` | The value must be of that type; defaults to `string` |
| `pattern:<ere>` | The value must match that extended regular expression |
| `choices:a,b` | The value must be one of the listed choices |
| `min:<n>` / `max:<n>` | Bounds; numeric for a numeric type, character count otherwise |
| `minlen:<n>` / `maxlen:<n>` | Bounds on the character count, whatever the type |

A value that is not of its declared type is not then measured against the
other rules: `min:1` on something that is not a number has no answer worth
reporting, and a second message about it only buries the first.

The reasons are phrased to follow the name of whatever was validated, so a
caller prints `Invalid configuration ${key}: ${reason}` without rewording
them. `dybatpho::validate_errors` prints them.

**🧪 Example**

```bash
if ! dybatpho::validate_value "${port}" type:int min:1 max:65535; then
  dybatpho::die "Invalid --port: $(dybatpho::validate_errors)"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to validate |
| `$@` | string | Rules, as `name:value` |

**🧩 Variable sets**

- **`DYBATPHO_VALIDATE_ERRORS`** (Reset,): then one entry per violation

**🚦 Exit codes**

- `0`: The value satisfies every rule
- `1`: At least one rule was violated
- `1`: Stop the script when a rule name, a rule value, or a type is not supported

**🔗 See also**

- [- `dybatpho::validate_errors` - `dybatpho::validate_or_die](#dybatphovalidate_errors-dybatphovalidate_or_die)


---

### `dybatpho::validate_errors`

Print the reasons recorded by the last `dybatpho::validate_value`
call, one per line.

_Function has no arguments._

**📤 Output on stdout**

- One reason per line, nothing when the last call succeeded

**🚦 Exit codes**

- `0`: Always

**🔗 See also**

- [- `dybatpho::validate_value](#dybatphovalidate_value)


---

### `dybatpho::validate_or_die`

Validate a value and stop the script when it is rejected,
naming what was being validated and every reason it failed.

**🧪 Example**

```bash
dybatpho::validate_or_die "--port" "${PORT}" type:int min:1 max:65535
# Invalid --port: expected an integer, got `http`

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of what is being validated, used in the diagnostic |
| `$2` | string | Value to validate |
| `$@` | string | Rules, as accepted by `dybatpho::validate_value` |

**🧩 Variable sets**

- **`DYBATPHO_VALIDATE_ERRORS`** (Reset,): then one entry per violation

**🚦 Exit codes**

- `0`: The value satisfies every rule
- `1`: Stop the script when the value is rejected

**🔗 See also**

- [- `dybatpho::validate_value](#dybatphovalidate_value)


---

### `dybatpho::validate_reset`

Forget every type added with `dybatpho::validate_register` and
restore the built-ins to their original predicates. A test or an example
that registers a type of its own calls this to leave the registry the way it
found it.

_Function has no arguments._

**🧩 Variable sets**

- **`__DYBATPHO_VALIDATE_PREDICATES`** (Reset): to the built-in types
- **`__DYBATPHO_VALIDATE_DESCRIPTIONS`** (Reset): to the built-in descriptions
- **`__DYBATPHO_VALIDATE_ALIASES`** (Reset): to the built-in aliases

**🚦 Exit codes**

- `0`: Always
