# json.sh

Utilities for working with JSON and YAML data

> 🧭 Source: [src/json.sh](../src/json.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for querying, validating, formatting, and
converting JSON and YAML documents through `yq`, with `jq` kept as a JSON
fallback where practical.



### 🚀 Highlights

- [`__dybatpho_json_cmd`](#__dybatpho_json_cmd) — Resolve the preferred command for JSON helpers.
- [`dybatpho::json_query`](#dybatphojson_query) — Query a JSON document with `yq`, or `jq` as a fallback.
- [`dybatpho::json_has`](#dybatphojson_has) — Return success when a JSON document satisfies a filter.
- [`dybatpho::json_pretty`](#dybatphojson_pretty) — Pretty-print a JSON document.
- [`dybatpho::json_to_yaml`](#dybatphojson_to_yaml) — Convert a JSON document to YAML.
- [`dybatpho::yaml_query`](#dybatphoyaml_query) — Query a YAML document with `yq`.
- [`dybatpho::yaml_has`](#dybatphoyaml_has) — Return success when a YAML document satisfies a `yq` expression.
- [`dybatpho::yaml_pretty`](#dybatphoyaml_pretty) — Pretty-print a YAML document.
- [`dybatpho::yaml_to_json`](#dybatphoyaml_to_json) — Convert a YAML document to JSON.
- [`dybatpho::json_string`](#dybatphojson_string) — Encode a string as a JSON string value, surrounding quotes included. Use this instead of wrapping text in quotes by hand: a value containing a quotation mark, a backslash, or a newline breaks hand-built JSON and this does not.
- [`dybatpho::json_object`](#dybatphojson_object) — Build a JSON object from name and value pairs. Every value is escaped, so no caller has to think about quoting. A name ending in `:json` marks a value that is already a JSON document and is inserted as-is, which is how you nest an object or an array.
- [`dybatpho::json_eval`](#dybatphojson_eval) — Evaluate a filter against a JSON document held in a variable. Unlike `dybatpho::json_query`, which reads a file, this works on a document a script is still assembling.
- [`dybatpho::json_get`](#dybatphojson_get) — Evaluate a filter and print the result as a bare scalar. Strings come back without surrounding quotes, so the result drops straight into a shell variable.
- [`dybatpho::json_valid`](#dybatphojson_valid) — Return success when a JSON document held in a variable is valid.

<a id="see-also"></a>
## 🔗 See also

- [example/json_ops.sh](../example/json_ops.sh)

<a id="tips"></a>
## 💡 Tips

- The YAML helpers target the Mike Farah `yq` command line (`yq eval ...`)
- JSON helpers prefer `yq` because it can read JSON directly, and fall back to `jq` when needed

### `dybatpho::json_object`

- Build nested structures from the inside out, passing each finished document through a `:json` name

### `dybatpho::json_eval`

- Write filters in the subset both backends share: `yq` has no `def`, and spells `ascii_downcase` as `downcase`

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_json_cmd`

Resolve the preferred command for JSON helpers.

**📤 Output on stdout**

- `yq` or `jq`

**🚦 Exit codes**

- `0`: A supported JSON helper command exists
- `127`: Neither `yq` nor `jq` is installed


---

### `dybatpho::json_query`

Query a JSON document with `yq`, or `jq` as a fallback.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | Query filter |
| `$@` | string | Extra arguments forwarded to the selected backend |

**📤 Output on stdout**

- Result of the JSON query

**🚦 Exit codes**

- `0`: Query succeeded
- `127`: Neither `yq` nor `jq` is installed


---

### `dybatpho::json_has`

Return success when a JSON document satisfies a filter.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | Query filter |

**🚦 Exit codes**

- `0`: The filter succeeds
- `1`: The filter fails
- `127`: Neither `yq` nor `jq` is installed


---

### `dybatpho::json_pretty`

Pretty-print a JSON document.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | Optional output file path |

**📤 Output on stdout**

- Pretty JSON when no output file is provided

**🚦 Exit codes**

- `0`: Formatting succeeded
- `127`: Neither `yq` nor `jq` is installed


---

### `dybatpho::json_to_yaml`

Convert a JSON document to YAML.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path or `-` for stdin |
| `$2` | string | Optional output file path |

**📤 Output on stdout**

- YAML output when no output file is provided

**🚦 Exit codes**

- `0`: Conversion succeeded
- `127`: `yq` is not installed


---

### `dybatpho::yaml_query`

Query a YAML document with `yq`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin |
| `$2` | string | yq expression |
| `$@` | string | Extra arguments forwarded to `yq eval` |

**📤 Output on stdout**

- Result of the yq query

**🚦 Exit codes**

- `0`: Query succeeded
- `127`: `yq` is not installed


---

### `dybatpho::yaml_has`

Return success when a YAML document satisfies a `yq` expression.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin |
| `$2` | string | yq expression |

**🚦 Exit codes**

- `0`: The expression succeeds
- `1`: The expression fails
- `127`: `yq` is not installed


---

### `dybatpho::yaml_pretty`

Pretty-print a YAML document.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin |
| `$2` | string | Optional output file path |

**📤 Output on stdout**

- Pretty YAML when no output file is provided

**🚦 Exit codes**

- `0`: Formatting succeeded
- `127`: `yq` is not installed


---

### `dybatpho::yaml_to_json`

Convert a YAML document to JSON.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path or `-` for stdin |
| `$2` | string | Optional output file path |

**📤 Output on stdout**

- JSON output when no output file is provided

**🚦 Exit codes**

- `0`: Conversion succeeded
- `127`: `yq` is not installed


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

**📤 Output on stdout**

- Quoted JSON string

**🚦 Exit codes**

- `0`: The value was encoded
- `1`: Missing argument
- `127`: Neither `yq` nor `jq` is installed


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
- `1`: An odd number of arguments, or an invalid nested document
- `127`: Neither `yq` nor `jq` is installed


---

### `dybatpho::json_eval`

Evaluate a filter against a JSON document held in a variable.
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
| `$2` | string | Filter |

**📤 Output on stdout**

- Compact JSON result

**🚦 Exit codes**

- `0`: The filter succeeded
- `1`: Invalid input or filter
- `127`: Neither `yq` nor `jq` is installed

**🔗 See also**

- [dybatpho::json_get](#dybatphojson_get)


---

### `dybatpho::json_get`

Evaluate a filter and print the result as a bare scalar.
Strings come back without surrounding quotes, so the result drops straight
into a shell variable.

**🧪 Example**

```bash
local text
text=$(dybatpho::json_get "${response}" '.choices[0].message.content // ""')

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON document |
| `$2` | string | Filter |

**📤 Output on stdout**

- Filter result, unquoted for scalars

**🚦 Exit codes**

- `0`: The filter succeeded
- `1`: Invalid input or filter
- `127`: Neither `yq` nor `jq` is installed

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
- `127`: Neither `yq` nor `jq` is installed

