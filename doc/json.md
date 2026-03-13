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

<a id="see-also"></a>
## 🔗 See also

- [example/json_ops.sh](../example/json_ops.sh)

<a id="tips"></a>
## 💡 Tips

- The YAML helpers target the Mike Farah `yq` command line (`yq eval ...`)
- JSON helpers prefer `yq` because it can read JSON directly, and fall back to `jq` when needed

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

