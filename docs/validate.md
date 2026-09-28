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
- [`__dybatpho_validate_match`](#__dybatpho_validate_match) — Match a value against an extended regular expression.
- [`__dybatpho_validate_canonical`](#__dybatpho_validate_canonical) — Resolve a type name, or an alias of one, to its canonical name. This never terminates the script: it is called from inside a command substitution, where `dybatpho::die` would only end the subshell and leave the caller reporting success on an empty value.
- [`__dybatpho_validate_numeric_type`](#__dybatpho_validate_numeric_type) — Return success when a type's `min:` and `max:` bound the value itself rather than the number of characters in it.
- [`__dybatpho_validate_number_cmp`](#__dybatpho_validate_number_cmp) — Compare two numbers written as decimal text, without arithmetic the shell would get wrong. `((08 > 1))` is an error, because a leading zero asks for base 8, and `((1.5 > 1))` is an error too, because Bash has no fractional arithmetic at all. Both forms reach here from a configuration file, so both have to compare rather than abort. Two plain integers are compared as integers, which is the case that matters for a port, a timeout, or a count and is the one that must not lose precision. Anything else — a fraction, an exponent — is scaled to a fixed six decimal places first, under `LC_ALL=C` so the radix character is a dot whatever the host's locale says.
- [`__dybatpho_validate_plain_int`](#__dybatpho_validate_plain_int) — Read a signed decimal integer written with any number of leading zeros, as a number the shell's arithmetic accepts.
- [`__dybatpho_validate_scaled`](#__dybatpho_validate_scaled) — Read a decimal number, in any notation `printf` accepts, as an integer scaled by one million, so two of them compare with shell arithmetic.
- [`dybatpho::validate_is`](#dybatphovalidate_is) — Return success when a value is of the named type. A type is a name bound to a predicate: the built-ins listed by `dybatpho::validate_types`, plus anything added with `dybatpho::validate_register`.
- [`dybatpho::validate_describe`](#dybatphovalidate_describe) — Print the noun a message uses for a type, such as `an email address` for `email`. Error messages are built from this, so a caller that reports its own failure words it the same way the library does.
- [`dybatpho::validate_types`](#dybatphovalidate_types) — Print every registered type name, one per line, in alphabetical order. Aliases are not listed: they resolve to the names printed here.
- [`dybatpho::validate_register`](#dybatphovalidate_register) — Register a type, or replace one that is already registered. The predicate is a function taking the value as its only argument and returning success when the value is of the type; it must not print anything and must not terminate the script.
- [`__dybatpho_validate_alias`](#__dybatpho_validate_alias) — Register an alias for a type that is already known.
- [`__dybatpho_validate_error`](#__dybatpho_validate_error) — Record one reason the value was rejected.
- [`dybatpho::validate_value`](#dybatphovalidate_value) — Validate one value against a list of declarative rules, and record every violation rather than stopping at the first. Supported rules: | Rule | Meaning | | --- | --- | | `type:<name>` | The value must be of that type; defaults to `string` | | `pattern:<ere>` | The value must match that extended regular expression | | `choices:a,b` | The value must be one of the listed choices | | `min:<n>` / `max:<n>` | Bounds; numeric for a numeric type, character count otherwise | | `minlen:<n>` / `maxlen:<n>` | Bounds on the character count, whatever the type | A value that is not of its declared type is not then measured against the other rules: `min:1` on something that is not a number has no answer worth reporting, and a second message about it only buries the first. The reasons are phrased to follow the name of whatever was validated, so a caller prints `Invalid configuration ${key}: ${reason}` without rewording them. `dybatpho::validate_errors` prints them.
- [`dybatpho::validate_errors`](#dybatphovalidate_errors) — Print the reasons recorded by the last `dybatpho::validate_value` call, one per line.
- [`dybatpho::validate_or_die`](#dybatphovalidate_or_die) — Validate a value and stop the script when it is rejected, naming what was being validated and every reason it failed.
- [`dybatpho::validate_reset`](#dybatphovalidate_reset) — Forget every type added with `dybatpho::validate_register` and restore the built-ins to their original predicates. A test or an example that registers a type of its own calls this to leave the registry the way it found it.
- [`__dybatpho_validate_is_string`](#__dybatpho_validate_is_string) — Accept any value, including the empty string.
- [`__dybatpho_validate_is_nonempty`](#__dybatpho_validate_is_nonempty) — Return success when a value holds something other than whitespace.
- [`__dybatpho_validate_is_int`](#__dybatpho_validate_is_int) — Return success when a value is an integer, with an optional sign.
- [`__dybatpho_validate_is_uint`](#__dybatpho_validate_is_uint) — Return success when a value is a non-negative integer with no sign.
- [`__dybatpho_validate_is_number`](#__dybatpho_validate_is_number) — Return success when a value is a decimal number, with an optional sign, fraction, and exponent.
- [`__dybatpho_validate_is_bool`](#__dybatpho_validate_is_bool) — Return success when a value is one of the words the library reads as a boolean, in either direction and in any case.
- [`__dybatpho_validate_is_port`](#__dybatpho_validate_is_port) — Return success when a value is a TCP or UDP port number. Port 0 is refused: it asks the kernel to choose rather than naming a port, so a configuration that carries it has not been configured.
- [`__dybatpho_validate_is_email`](#__dybatpho_validate_is_email) — Return success when a value is an email address.
- [`__dybatpho_validate_is_url`](#__dybatpho_validate_is_url) — Return success when a value is an absolute URL: a scheme, `://`, and a remainder that holds no whitespace.
- [`__dybatpho_validate_is_hostname`](#__dybatpho_validate_is_hostname) — Return success when a value is a host name. The whole name is limited to 253 characters and each label to 63, which is what DNS accepts; a label may not start or end with a hyphen, and a single trailing dot is allowed because it is how a fully qualified name is written.
- [`__dybatpho_validate_is_ipv4`](#__dybatpho_validate_is_ipv4) — Return success when a value is an IPv4 address. A leading zero is refused rather than ignored, because `inet_aton` and the software built on it read `010` as octal: an address that means two things is not one this library will agree to. `dybatpho::is_ipv4` in the `network` module answers the same question the same way, and the two are pinned against each other in `test/validate.bats`.
- [`__dybatpho_validate_is_ipv6`](#__dybatpho_validate_is_ipv6) — Return success when a value is an IPv6 address. `::` may appear once and stands for a run of zero groups; the last two groups may instead be written as a dotted IPv4 address. A zone index such as `%eth0` is refused: it names an interface rather than a part of the address.
- [`__dybatpho_validate_is_ip`](#__dybatpho_validate_is_ip) — Return success when a value is an IP address of either version.
- [`__dybatpho_validate_is_cidr`](#__dybatpho_validate_is_cidr) — Return success when a value is a CIDR block: an IP address, a slash, and a prefix length that fits the address's version.
- [`__dybatpho_validate_is_mac`](#__dybatpho_validate_is_mac) — Return success when a value is a MAC address written with colons or hyphens.
- [`__dybatpho_validate_is_semver`](#__dybatpho_validate_is_semver) — Return success when a value is a semantic version, with or without the leading `v` the library accepts everywhere else.
- [`__dybatpho_validate_is_uuid`](#__dybatpho_validate_is_uuid) — Return success when a value is a UUID in the canonical eight-four-four-four-twelve hexadecimal form.
- [`__dybatpho_validate_is_hex`](#__dybatpho_validate_is_hex) — Return success when a value is hexadecimal, with an optional `0x` prefix.
- [`__dybatpho_validate_is_alpha`](#__dybatpho_validate_is_alpha) — Return success when a value is one or more ASCII letters.
- [`__dybatpho_validate_is_alnum`](#__dybatpho_validate_is_alnum) — Return success when a value is one or more ASCII letters or digits.
- [`__dybatpho_validate_is_slug`](#__dybatpho_validate_is_slug) — Return success when a value is a lowercase slug: words of letters and digits joined by single hyphens.
- [`__dybatpho_validate_is_identifier`](#__dybatpho_validate_is_identifier) — Return success when a value is usable as a shell variable name.
- [`__dybatpho_validate_is_date`](#__dybatpho_validate_is_date) — Return success when a value is a calendar date written as `YYYY-MM-DD`. The day is checked against the length of the month, February included, so `2023-02-29` is refused rather than accepted as well-formed.
- [`__dybatpho_validate_is_time`](#__dybatpho_validate_is_time) — Return success when a value is a wall-clock time written as `HH:MM` or `HH:MM:SS`.
- [`__dybatpho_validate_is_duration`](#__dybatpho_validate_is_duration) — Return success when a value is a duration: either a bare number of seconds, or one or more `<number><unit>` pairs using `ns`, `us`, `ms`, `s`, `m`, `h`, `d`, or `w`, as in `1h30m`.
- [`__dybatpho_validate_is_path`](#__dybatpho_validate_is_path) — Return success when a value names a path that exists, of any kind.
- [`__dybatpho_validate_is_file`](#__dybatpho_validate_is_file) — Return success when a value names an existing regular file.
- [`__dybatpho_validate_is_dir`](#__dybatpho_validate_is_dir) — Return success when a value names an existing directory.
- [`__dybatpho_validate_is_symlink`](#__dybatpho_validate_is_symlink) — Return success when a value names an existing symbolic link.
- [`__dybatpho_validate_is_readable`](#__dybatpho_validate_is_readable) — Return success when a value names a path this process can read.
- [`__dybatpho_validate_is_writable`](#__dybatpho_validate_is_writable) — Return success when a value names a path this process can write.
- [`__dybatpho_validate_is_executable`](#__dybatpho_validate_is_executable) — Return success when a value names a path this process can execute.
- [`__dybatpho_validate_is_abspath`](#__dybatpho_validate_is_abspath) — Return success when a value is an absolute path. Unlike the other path types this asks nothing of the filesystem: it is about the shape of the path, so it answers for a file that has not been created yet.
- [`__dybatpho_validate_is_parent_dir`](#__dybatpho_validate_is_parent_dir) — Return success when a value names a path whose parent directory exists. This is the check an output file wants: the file itself is about to be created, but the directory it lands in has to be there already.
- [`__dybatpho_validate_register_builtins`](#__dybatpho_validate_register_builtins) — Bind every built-in type to its predicate and description. Called when the module is sourced, and again by `dybatpho::validate_reset`.

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

### `__dybatpho_validate_match`

Match a value against an extended regular expression.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |
| `$2` | string | Extended regular expression |

**🚦 Exit codes**

- `0`: The value matches
- `1`: The value does not match
- `2`: The expression is not a valid ERE


---

### `__dybatpho_validate_canonical`

Resolve a type name, or an alias of one, to its canonical name.
This never terminates the script: it is called from inside a command
substitution, where `dybatpho::die` would only end the subshell and leave
the caller reporting success on an empty value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Declared type name |

**📤 Output on stdout**

- The canonical type name, when it is known

**🚦 Exit codes**

- `0`: The type is known
- `1`: The type is not registered


---

### `__dybatpho_validate_numeric_type`

Return success when a type's `min:` and `max:` bound the value
itself rather than the number of characters in it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type name or alias |

**🚦 Exit codes**

- `0`: The type is numeric
- `1`: The type is not numeric, or is not registered


---

### `__dybatpho_validate_number_cmp`

Compare two numbers written as decimal text, without arithmetic
the shell would get wrong. `((08 > 1))` is an error, because a leading zero
asks for base 8, and `((1.5 > 1))` is an error too, because Bash has no
fractional arithmetic at all. Both forms reach here from a configuration
file, so both have to compare rather than abort.

Two plain integers are compared as integers, which is the case that matters
for a port, a timeout, or a count and is the one that must not lose
precision. Anything else — a fraction, an exponent — is scaled to a fixed
six decimal places first, under `LC_ALL=C` so the radix character is a dot
whatever the host's locale says.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Left value |
| `$2` | string | Right value |
| `$3` | string | Name of the variable receiving `-1`, `0`, or `1` |

**🧩 Variable sets**

- **`The`** (named): variable

**🚦 Exit codes**

- `0`: The comparison was made
- `1`: A value is not a number


---

### `__dybatpho_validate_plain_int`

Read a signed decimal integer written with any number of leading
zeros, as a number the shell's arithmetic accepts.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the number |
| `$2` | string | Integer text, such as `007` or `-42` |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_validate_scaled`

Read a decimal number, in any notation `printf` accepts, as an
integer scaled by one million, so two of them compare with shell arithmetic.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the scaled integer |
| `$2` | string | Number text, such as `1.5` or `1e3` |

**🧩 Variable sets**

- **`The`** (named): variable

**🚦 Exit codes**

- `1`: The text is not a number `printf` can read


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

### `__dybatpho_validate_alias`

Register an alias for a type that is already known.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Alias name |
| `$2` | string | Canonical type name |

**🧩 Variable sets**

- __DYBATPHO_VALIDATE_ALIASES

**🚦 Exit codes**

- `1`: Stop the script when the canonical type is not registered


---

### `__dybatpho_validate_error`

Record one reason the value was rejected.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Reason, phrased to follow the name of what was validated |

**🧩 Variable sets**

- **`DYBATPHO_VALIDATE_ERRORS`** (Appends): the reason


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


---

### `__dybatpho_validate_is_string`

Accept any value, including the empty string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: Always


---

### `__dybatpho_validate_is_nonempty`

Return success when a value holds something other than whitespace.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is not blank
- `1`: The value is empty or only whitespace


---

### `__dybatpho_validate_is_int`

Return success when a value is an integer, with an optional sign.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an integer
- `1`: The value is not


---

### `__dybatpho_validate_is_uint`

Return success when a value is a non-negative integer with no sign.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an unsigned integer
- `1`: The value is not


---

### `__dybatpho_validate_is_number`

Return success when a value is a decimal number, with an optional
sign, fraction, and exponent.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a number
- `1`: The value is not


---

### `__dybatpho_validate_is_bool`

Return success when a value is one of the words the library reads
as a boolean, in either direction and in any case.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a boolean
- `1`: The value is not


---

### `__dybatpho_validate_is_port`

Return success when a value is a TCP or UDP port number.
Port 0 is refused: it asks the kernel to choose rather than naming a port,
so a configuration that carries it has not been configured.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a port number from 1 to 65535
- `1`: The value is not


---

### `__dybatpho_validate_is_email`

Return success when a value is an email address.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an email address
- `1`: The value is not


---

### `__dybatpho_validate_is_url`

Return success when a value is an absolute URL: a scheme, `://`,
and a remainder that holds no whitespace.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a URL
- `1`: The value is not


---

### `__dybatpho_validate_is_hostname`

Return success when a value is a host name.
The whole name is limited to 253 characters and each label to 63, which is
what DNS accepts; a label may not start or end with a hyphen, and a single
trailing dot is allowed because it is how a fully qualified name is written.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a host name
- `1`: The value is not


---

### `__dybatpho_validate_is_ipv4`

Return success when a value is an IPv4 address.
A leading zero is refused rather than ignored, because `inet_aton` and the
software built on it read `010` as octal: an address that means two things
is not one this library will agree to. `dybatpho::is_ipv4` in the `network`
module answers the same question the same way, and the two are pinned
against each other in `test/validate.bats`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an IPv4 address
- `1`: The value is not


---

### `__dybatpho_validate_is_ipv6`

Return success when a value is an IPv6 address.
`::` may appear once and stands for a run of zero groups; the last two
groups may instead be written as a dotted IPv4 address. A zone index such as
`%eth0` is refused: it names an interface rather than a part of the address.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an IPv6 address
- `1`: The value is not


---

### `__dybatpho_validate_is_ip`

Return success when a value is an IP address of either version.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is an IPv4 or IPv6 address
- `1`: The value is not


---

### `__dybatpho_validate_is_cidr`

Return success when a value is a CIDR block: an IP address, a
slash, and a prefix length that fits the address's version.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a CIDR block
- `1`: The value is not


---

### `__dybatpho_validate_is_mac`

Return success when a value is a MAC address written with colons
or hyphens.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a MAC address
- `1`: The value is not


---

### `__dybatpho_validate_is_semver`

Return success when a value is a semantic version, with or
without the leading `v` the library accepts everywhere else.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a semantic version
- `1`: The value is not


---

### `__dybatpho_validate_is_uuid`

Return success when a value is a UUID in the canonical
eight-four-four-four-twelve hexadecimal form.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a UUID
- `1`: The value is not


---

### `__dybatpho_validate_is_hex`

Return success when a value is hexadecimal, with an optional
`0x` prefix.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is hexadecimal
- `1`: The value is not


---

### `__dybatpho_validate_is_alpha`

Return success when a value is one or more ASCII letters.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is alphabetic
- `1`: The value is not


---

### `__dybatpho_validate_is_alnum`

Return success when a value is one or more ASCII letters or digits.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is alphanumeric
- `1`: The value is not


---

### `__dybatpho_validate_is_slug`

Return success when a value is a lowercase slug: words of letters
and digits joined by single hyphens.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a slug
- `1`: The value is not

**🔗 See also**

- [- `dybatpho::string_slugify](#dybatphostring_slugify)


---

### `__dybatpho_validate_is_identifier`

Return success when a value is usable as a shell variable name.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a shell variable name
- `1`: The value is not


---

### `__dybatpho_validate_is_date`

Return success when a value is a calendar date written as
`YYYY-MM-DD`. The day is checked against the length of the month, February
included, so `2023-02-29` is refused rather than accepted as well-formed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a date
- `1`: The value is not


---

### `__dybatpho_validate_is_time`

Return success when a value is a wall-clock time written as
`HH:MM` or `HH:MM:SS`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a time
- `1`: The value is not


---

### `__dybatpho_validate_is_duration`

Return success when a value is a duration: either a bare number
of seconds, or one or more `<number><unit>` pairs using `ns`, `us`, `ms`,
`s`, `m`, `h`, `d`, or `w`, as in `1h30m`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The value is a duration
- `1`: The value is not


---

### `__dybatpho_validate_is_path`

Return success when a value names a path that exists, of any kind.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The path exists
- `1`: It does not


---

### `__dybatpho_validate_is_file`

Return success when a value names an existing regular file.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The file exists
- `1`: It does not


---

### `__dybatpho_validate_is_dir`

Return success when a value names an existing directory.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The directory exists
- `1`: It does not


---

### `__dybatpho_validate_is_symlink`

Return success when a value names an existing symbolic link.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The link exists
- `1`: It does not


---

### `__dybatpho_validate_is_readable`

Return success when a value names a path this process can read.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The path is readable
- `1`: It is not


---

### `__dybatpho_validate_is_writable`

Return success when a value names a path this process can write.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The path is writable
- `1`: It is not


---

### `__dybatpho_validate_is_executable`

Return success when a value names a path this process can execute.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The path is executable
- `1`: It is not


---

### `__dybatpho_validate_is_abspath`

Return success when a value is an absolute path. Unlike the other
path types this asks nothing of the filesystem: it is about the shape of the
path, so it answers for a file that has not been created yet.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The path is absolute
- `1`: It is not


---

### `__dybatpho_validate_is_parent_dir`

Return success when a value names a path whose parent directory
exists. This is the check an output file wants: the file itself is about to
be created, but the directory it lands in has to be there already.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value to test |

**🚦 Exit codes**

- `0`: The parent directory exists
- `1`: It does not


---

### `__dybatpho_validate_register_builtins`

Bind every built-in type to its predicate and description.
Called when the module is sourced, and again by `dybatpho::validate_reset`.

_Function has no arguments._

**🧩 Variable sets**

- __DYBATPHO_VALIDATE_PREDICATES
- __DYBATPHO_VALIDATE_DESCRIPTIONS
- __DYBATPHO_VALIDATE_ALIASES
