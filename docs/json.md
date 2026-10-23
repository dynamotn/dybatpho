# json.sh

Utilities for working with JSON and YAML data

> 🧭 Source: [src/json.sh](../src/json.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module contains helpers for querying, validating, formatting, editing,
and converting JSON and YAML documents. Every filter a caller writes is a
`jq` filter and runs through `jq`, whatever else is installed, so a script
prints the same result on every machine.

`jq` is required by the module. The Go `yq` v4 is needed only to read YAML
(or TOML, chosen by the file extension) into JSON before `jq` sees it, to
write YAML back out, and to edit a YAML file in place, which it does so the
file's comments and layout survive. A YAML helper refuses the unrelated
Python `yq` by name rather than misreading its output.

Use `jq` 1.7 or newer. `jq` 1.6, still the packaged one on Debian 12 and
Ubuntu 22.04, reads every number as a binary double: `0.50` comes back as
`0.5`, and an integer past 2^53 loses its last digits. The module works with
it, but numbers are then not kept as written, and `dybatpho::doctor` reports
it as outdated.

### 🚀 Highlights

- [`dybatpho::json_query`](#dybatphojson_query) — Query a JSON document with a `jq` filter.
- [`dybatpho::json_has`](#dybatphojson_has) — Return success when a JSON document satisfies a `jq` filter. The filter succeeds when its last output is neither `false` nor `null`; a filter that produces nothing at all fails the same way.
- [`dybatpho::json_pretty`](#dybatphojson_pretty) — Pretty-print a JSON document.
- [`dybatpho::json_to_yaml`](#dybatphojson_to_yaml) — Convert a JSON document to YAML.
- [`dybatpho::yaml_query`](#dybatphoyaml_query) — Query a YAML document with a `jq` filter. The document is read into JSON by `yq` and the filter runs in `jq`, so it is written exactly as it would be for `dybatpho::json_query`. Each result is printed back as YAML: a scalar on its own line without quotes, a mapping or a sequence in block style.
- [`dybatpho::yaml_has`](#dybatphoyaml_has) — Return success when a YAML document satisfies a `jq` filter.
- [`dybatpho::yaml_pretty`](#dybatphoyaml_pretty) — Pretty-print a YAML document.
- [`dybatpho::yaml_to_json`](#dybatphoyaml_to_json) — Convert a YAML document to JSON. The JSON is printed by `jq`, so it is laid out exactly as `dybatpho::json_pretty` lays out the same data.
- [`dybatpho::json_string`](#dybatphojson_string) — Encode a string as a JSON string value, surrounding quotes included. Use this instead of wrapping text in quotes by hand: a value containing a quotation mark, a backslash, or a newline breaks hand-built JSON and this does not.
- [`dybatpho::json_object`](#dybatphojson_object) — Build a JSON object from name and value pairs. Every value is escaped, so no caller has to think about quoting. A name ending in `:json` marks a value that is already a JSON document and is inserted as-is, which is how you nest an object or an array.
- [`dybatpho::json_eval`](#dybatphojson_eval) — Evaluate a `jq` filter against a JSON document held in a variable. Unlike `dybatpho::json_query`, which reads a file, this works on a document a script is still assembling.
- [`dybatpho::json_get`](#dybatphojson_get) — Evaluate a `jq` filter and print the result as a bare scalar. Strings come back without surrounding quotes, so the result drops straight into a shell variable; an object or an array is printed as pretty JSON.
- [`dybatpho::json_valid`](#dybatphojson_valid) — Return success when a JSON document held in a variable is valid.
- [`dybatpho::json_set`](#dybatphojson_set) — Set the value at a path in a JSON document. The path is a list of keys separated by `.`, such as `spec.ports.0.name`, where a segment of digits indexes an array. Missing objects and arrays on the way are created. The value is stored as a string unless `--json` says it is a JSON document, which is how a number, a boolean, `null`, an array, or an object is written.
- [`dybatpho::json_del`](#dybatphojson_del) — Remove the value at a path from a JSON document. Paths use the same syntax as `dybatpho::json_set`. Deleting a path that does not exist leaves the document unchanged, and deleting an array element shifts the ones after it.
- [`dybatpho::json_merge`](#dybatphojson_merge) — Deep-merge two JSON objects, the overlay winning. Objects present in both are merged key by key; any other value, arrays included, is replaced by the overlay's. Both documents must be objects.
- [`dybatpho::yaml_set`](#dybatphoyaml_set) — Set the value at a path in a YAML document. Paths and `--json` work as in `dybatpho::json_set`. The edit is made by `yq` itself, not through JSON, so comments and the rest of the document's layout are kept as `yq` keeps them; this needs `yq` but not `jq`.
- [`dybatpho::yaml_del`](#dybatphoyaml_del) — Remove the value at a path from a YAML document. Paths work as in `dybatpho::json_set`, and an absent path is not an error.
- [`dybatpho::yaml_merge`](#dybatphoyaml_merge) — Deep-merge two YAML mappings, the overlay winning. Merging follows `dybatpho::json_merge`: mappings merge key by key, and every other value is replaced by the overlay's.

<a id="see-also"></a>

## 🔗 See also

- [example/json_ops.sh](../example/json_ops.sh)

<a id="tips"></a>

## 💡 Tips

- Write filters in `jq`'s language: `keys` is sorted, `?`, `add`, `def`, `@json` and `ascii_downcase` all work
- A filter written for `yq` (`eval`, `strenv(...)`, `tag`, `downcase`, `ireduce`) no longer works and must be rewritten for `jq`

**[`dybatpho::json_object`](#dybatphojson_object)**

- Build nested structures from the inside out, passing each finished document through a `:json` name

**[`dybatpho::json_set`](#dybatphojson_set)**

- The output file is written atomically after the whole result is known, so a failure leaves it untouched

<a id="reference"></a>

## 📚 Reference

### `dybatpho::json_query`

Query a JSON document with a `jq` filter.

**🧪 Examples**

```bash
dybatpho::json_query package.json '.version'

```

```bash
dybatpho::json_query data.json '.items[] | select(.name == $n)' --arg n api

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | `jq` filter |
| `$@` | string | Extra arguments forwarded to `jq`, such as `--arg name value` |

**📤 Output on stdout**

- Result of the query, as `jq` prints it

**🚦 Exit codes**

- `0`: Query succeeded
- `other`: `jq`'s own exit code when the document or the filter is invalid
- `127`: `jq` is not installed

---

### `dybatpho::json_has`

Return success when a JSON document satisfies a `jq` filter.
The filter succeeds when its last output is neither `false` nor `null`;
a filter that produces nothing at all fails the same way.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | `jq` filter |

**🚦 Exit codes**

- `0`: The filter succeeds
- `1`: The filter's last output is `false` or `null`, or it has none
- `other`: `jq`'s own exit code when the document or the filter is invalid
- `127`: `jq` is not installed

---

### `dybatpho::json_pretty`

Pretty-print a JSON document.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | JSON file path or `-` for stdin |
| `$2` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- Pretty JSON when no output file is provided

**🚦 Exit codes**

- `0`: Formatting succeeded
- `other`: `jq`'s own exit code when the document is invalid
- `127`: `jq` is not installed

---

### `dybatpho::json_to_yaml`

Convert a JSON document to YAML.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | JSON file path or `-` for stdin |
| `$2` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- YAML output when no output file is provided

**🚦 Exit codes**

- `0`: Conversion succeeded
- `other`: `yq`'s own exit code when the document is invalid
- `127`: The Go `yq` v4 is not installed

---

### `dybatpho::yaml_query`

Query a YAML document with a `jq` filter.
The document is read into JSON by `yq` and the filter runs in `jq`, so it is
written exactly as it would be for `dybatpho::json_query`. Each result is
printed back as YAML: a scalar on its own line without quotes, a mapping or
a sequence in block style.

**🧪 Example**

```bash
dybatpho::yaml_query compose.yaml '.services | keys[]'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin; a `.toml` or `.json` file is read in its own format |
| `$2` | string | `jq` filter |
| `$@` | string | Extra arguments forwarded to `jq`, such as `--arg name value` |

**📤 Output on stdout**

- Every result of the filter, as YAML

**🚦 Exit codes**

- `0`: Query succeeded
- `other`: The exit code of `yq` or `jq` when the document or the filter is invalid
- `127`: `jq` or the Go `yq` v4 is not installed

---

### `dybatpho::yaml_has`

Return success when a YAML document satisfies a `jq` filter.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin |
| `$2` | string | `jq` filter |

**🚦 Exit codes**

- `0`: The filter succeeds
- `1`: The filter's last output is `false` or `null`, or it has none
- `other`: The exit code of `yq` or `jq` when the document or the filter is invalid
- `127`: `jq` or the Go `yq` v4 is not installed

---

### `dybatpho::yaml_pretty`

Pretty-print a YAML document.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | YAML file path or `-` for stdin |
| `$2` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- Pretty YAML when no output file is provided

**🚦 Exit codes**

- `0`: Formatting succeeded
- `other`: `yq`'s own exit code when the document is invalid
- `127`: The Go `yq` v4 is not installed

---

### `dybatpho::yaml_to_json`

Convert a YAML document to JSON.
The JSON is printed by `jq`, so it is laid out exactly as
`dybatpho::json_pretty` lays out the same data.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | YAML file path or `-` for stdin |
| `$2` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- JSON output when no output file is provided

**🚦 Exit codes**

- `0`: Conversion succeeded
- `other`: `yq`'s own exit code when the document is invalid
- `127`: `jq` or the Go `yq` v4 is not installed

---

### `dybatpho::json_string`

Encode a string as a JSON string value, surrounding quotes included.
Use this instead of wrapping text in quotes by hand: a value containing a
quotation mark, a backslash, or a newline breaks hand-built JSON and this
does not.

**🧪 Example**

```bash
dybatpho::json_string 'he said "hi"' # "he said \"hi\""

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to encode |

**📝 Notes**

- Quoting is done in the shell, so this is the one JSON helper that does not need `jq`

**📤 Output on stdout**

- Quoted JSON string

**🚦 Exit codes**

- `0`: The value was encoded
- `1`: Missing argument

---

### `dybatpho::json_object`

Build a JSON object from name and value pairs.
Every value is escaped, so no caller has to think about quoting. A name
ending in `:json` marks a value that is already a JSON document and is
inserted as-is, which is how you nest an object or an array.

**🧪 Examples**

```bash
dybatpho::json_object status ok message 'it "worked"'
# {"status":"ok","message":"it \"worked\""}

```

```bash
dybatpho::json_object name api ports:json '[80,443]'
# {"name":"api","ports":[80,443]}

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Alternating names and values |

**📤 Output on stdout**

- Compact JSON object

**🚦 Exit codes**

- `0`: The object was built
- `1`: An odd number of arguments
- `other`: `jq`'s own exit code when a nested document is invalid
- `127`: `jq` is not installed

---

### `dybatpho::json_eval`

Evaluate a `jq` filter against a JSON document held in a variable.
Unlike `dybatpho::json_query`, which reads a file, this works on a document a
script is still assembling.

**🧪 Example**

```bash
local messages='[]'
messages=$(dybatpho::json_eval "${messages}" \
  ". + [$(dybatpho::json_object role user content "${prompt}")]")

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON document |
| `$2` | string | `jq` filter |

**📤 Output on stdout**

- Compact JSON result

**🚦 Exit codes**

- `0`: The filter succeeded
- `other`: `jq`'s own exit code for an invalid document or filter
- `127`: `jq` is not installed

**🔗 See also**

- [dybatpho::json_get](#dybatphojson_get)

---

### `dybatpho::json_get`

Evaluate a `jq` filter and print the result as a bare scalar.
Strings come back without surrounding quotes, so the result drops straight
into a shell variable; an object or an array is printed as pretty JSON.

**🧪 Example**

```bash
local text
text=$(dybatpho::json_get "${response}" '.choices[0].message.content // ""')

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON document |
| `$2` | string | `jq` filter |

**📤 Output on stdout**

- Filter result, unquoted for strings

**🚦 Exit codes**

- `0`: The filter succeeded
- `other`: `jq`'s own exit code for an invalid document or filter
- `127`: `jq` is not installed

**🔗 See also**

- [dybatpho::json_eval](#dybatphojson_eval)

---

### `dybatpho::json_valid`

Return success when a JSON document held in a variable is valid.

**🧪 Example**

```bash
dybatpho::json_valid "${answer}" || dybatpho::warn "The model did not return JSON"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Candidate document |

**🚦 Exit codes**

- `0`: The document parses as JSON
- `1`: The document is not valid JSON
- `127`: `jq` is not installed

---

### `dybatpho::json_set`

Set the value at a path in a JSON document.
The path is a list of keys separated by `.`, such as `spec.ports.0.name`,
where a segment of digits indexes an array. Missing objects and arrays on
the way are created. The value is stored as a string unless `--json` says
it is a JSON document, which is how a number, a boolean, `null`, an array,
or an object is written.

**🧪 Examples**

```bash
dybatpho::json_set package.json version 2.0.0 package.json

```

```bash
dybatpho::json_set --json config.json server.ports '[80,443]'

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | no |  | `--json`: parse the value as JSON instead of storing a string |
| `$2` | string | yes |  | JSON file path or `-` for stdin |
| `$3` | string | yes |  | Path to set; `\.` is a dot inside a key, and `\0` the key `0` |
| `$4` | string | yes |  | Value to store |
| `$5` | string | no |  | Output file path, which may be the input file |

**📝 Notes**

- The path and the value reach `jq` as arguments, never as part of the expression, so neither needs escaping

**📤 Output on stdout**

- Pretty JSON when no output file is provided

**🚦 Exit codes**

- `0`: The value was set
- `1`: Invalid arguments, path, or `--json` value
- `other`: `jq`'s exit code when the input is invalid or the path runs through a scalar
- `127`: `jq` is not installed

---

### `dybatpho::json_del`

Remove the value at a path from a JSON document.
Paths use the same syntax as `dybatpho::json_set`. Deleting a path that does
not exist leaves the document unchanged, and deleting an array element
shifts the ones after it.

**🧪 Example**

```bash
dybatpho::json_del package.json scripts.prepublish package.json

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | JSON file path or `-` for stdin |
| `$2` | string | yes |  | Path to remove |
| `$3` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- Pretty JSON when no output file is provided

**🚦 Exit codes**

- `0`: The path was removed or was already absent
- `1`: Invalid arguments or path
- `other`: `jq`'s exit code when the input is invalid
- `127`: `jq` is not installed

---

### `dybatpho::json_merge`

Deep-merge two JSON objects, the overlay winning.
Objects present in both are merged key by key; any other value, arrays
included, is replaced by the overlay's. Both documents must be objects.

**🧪 Example**

```bash
dybatpho::json_merge defaults.json local.json > effective.json

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Base JSON file path, or `-` for stdin |
| `$2` | string | yes |  | Overlay JSON file path, or `-` for stdin |
| `$3` | string | no |  | Output file path, which may be either input |

**📤 Output on stdout**

- Pretty JSON when no output file is provided

**🚦 Exit codes**

- `0`: The documents were merged
- `1`: Invalid arguments
- `other`: `jq`'s exit code when a document is not an object or is invalid
- `127`: `jq` is not installed

---

### `dybatpho::yaml_set`

Set the value at a path in a YAML document.
Paths and `--json` work as in `dybatpho::json_set`. The edit is made by
`yq` itself, not through JSON, so comments and the rest of the document's
layout are kept as `yq` keeps them; this needs `yq` but not `jq`.

**🧪 Examples**

```bash
dybatpho::yaml_set compose.yaml services.app.image 'app:2.0' compose.yaml

```

```bash
dybatpho::yaml_set --json values.yaml replicas 3

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | no |  | `--json`: parse the value as JSON instead of storing a string |
| `$2` | string | yes |  | YAML file path or `-` for stdin |
| `$3` | string | yes |  | Path to set |
| `$4` | string | yes |  | Value to store |
| `$5` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- YAML when no output file is provided

**🚦 Exit codes**

- `0`: The value was set
- `1`: Invalid arguments, path, or `--json` value
- `other`: `yq`'s exit code when the input is invalid or the path runs through a scalar
- `127`: The Go `yq` v4 is not installed

---

### `dybatpho::yaml_del`

Remove the value at a path from a YAML document.
Paths work as in `dybatpho::json_set`, and an absent path is not an error.

**🧪 Example**

```bash
dybatpho::yaml_del compose.yaml services.debug compose.yaml

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | YAML file path or `-` for stdin |
| `$2` | string | yes |  | Path to remove |
| `$3` | string | no |  | Output file path, which may be the input file |

**📤 Output on stdout**

- YAML when no output file is provided

**🚦 Exit codes**

- `0`: The path was removed or was already absent
- `1`: Invalid arguments or path
- `other`: `yq`'s exit code when the input is invalid
- `127`: The Go `yq` v4 is not installed

---

### `dybatpho::yaml_merge`

Deep-merge two YAML mappings, the overlay winning.
Merging follows `dybatpho::json_merge`: mappings merge key by key, and
every other value is replaced by the overlay's.

**🧪 Example**

```bash
dybatpho::yaml_merge values.yaml values-prod.yaml > rendered.yaml

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Base YAML file path, or `-` for stdin |
| `$2` | string | yes |  | Overlay YAML file path, or `-` for stdin |
| `$3` | string | no |  | Output file path, which may be either input |

**📤 Output on stdout**

- YAML when no output file is provided

**🚦 Exit codes**

- `0`: The documents were merged
- `1`: Invalid arguments
- `other`: `yq`'s exit code when a document is not a mapping or is invalid
- `127`: The Go `yq` v4 is not installed
