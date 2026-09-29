# config.sh

Utilities for loading configuration from files and environment variables.

> 🧭 Source: [src/config.sh](../src/config.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Configuration files are loaded in the order provided, so later files
override earlier files. Environment variables loaded with
`dybatpho::config_env` are applied last.

`dybatpho::config_profile` builds the usual two-file overlay on top of that
order: a base `config.yaml` followed by the `config.<profile>.yaml` beside
it, which may be absent. `dybatpho::config_load --optional` is the same
tolerance for any other list of files.

`dybatpho::config_set` changes a value in memory and
`dybatpho::config_save` writes chosen keys back to a file in the format
that file already uses: a dotenv rewrite keeps its comments, its blank
lines, and the order of its assignments, while JSON, YAML, and TOML are
rewritten through `jq` and `yq` so the rest of the document survives.

Keys can also be given a typed schema with `dybatpho::config_schema`.
`dybatpho::config_validate` then applies declared defaults, enforces
required keys, types, ranges, and enum choices, and reports every
violation together with the key that caused it. The types come from the
`validate` module rather than from a list kept here, so a schema may
declare `email`, `port`, `ipv4`, `semver`, `dir` or any type registered
with `dybatpho::validate_register`, and the message a rejected value
produces is worded the same way everywhere in the library. The same schema renders a
configuration reference through `dybatpho::config_doc`, and tells
`dybatpho::config_save` which values to write as numbers or booleans
rather than as strings.

### 🚀 Highlights

- [`__dybatpho_config_set`](#__dybatpho_config_set) — Store one configuration value, rejecting a key that is not a name: the key becomes part of a variable name and of the schema, so a stray character would land somewhere it cannot be looked up again.
- [`__dybatpho_config_load_dotenv`](#__dybatpho_config_load_dotenv) — Read a dotenv file into the configuration: `KEY=value` a line, with `export` prefixes, quotes and trailing comments removed.
- [`__dybatpho_config_load_structured`](#__dybatpho_config_load_structured) — Read a JSON, YAML or TOML file into the configuration, flattening it to the dotted keys the rest of the module uses.
- [`dybatpho::config_load`](#dybatphoconfig_load) — Load one or more configuration files, merging them left to right.
- [`dybatpho::config_profile`](#dybatphoconfig_profile) — Load a base configuration file and the profile overlay beside it. The overlay is the base name with the profile inserted before the extension, so `config.yaml` with profile `prod` reads `config.prod.yaml` after it. The base file is required; the overlay is not, which is what lets the same call work on a machine that has no profile-specific file.
- [`dybatpho::config_env`](#dybatphoconfig_env) — Load environment variables after an optional prefix.
- [`dybatpho::config_set`](#dybatphoconfig_set) — Set a configuration value in memory. The value joins the ones loaded from files and the environment, so a later `dybatpho::config_validate` checks it like any other, and `dybatpho::config_save` can write it back to a file.
- [`dybatpho::config_get`](#dybatphoconfig_get) — Print a configuration value.
- [`dybatpho::config_require`](#dybatphoconfig_require) — Require configuration keys to be present.
- [`dybatpho::config_export`](#dybatphoconfig_export) — Export loaded values as shell variables.
- [`__dybatpho_config_dotenv_value`](#__dybatpho_config_dotenv_value) — Render one value the way a dotenv file has to carry it. A value made only of characters the loader reads back verbatim is written bare; anything else is double-quoted, because that is the only form whose escapes the loader expands. The double quote itself is left alone on purpose: the loader strips the outer pair by position rather than by parsing, and `printf '%b'` has no `\"` escape to undo.
- [`__dybatpho_config_save_dotenv`](#__dybatpho_config_save_dotenv) — Rewrite the named keys into a dotenv file. Every line that assigns one of the keys is replaced in place, so comments, blank lines, unrelated assignments, and the order of the file all survive. Keys the file does not mention are appended in the order they were given.
- [`__dybatpho_config_save_structured`](#__dybatpho_config_save_structured) — Rewrite the named keys into a JSON, YAML, or TOML file. Each key is assigned on its own rather than merged from a second document, which is what keeps the file's own comments, indentation, and block style: a node imported from JSON carries its flow style with it and reflows everything around it. Values reach `jq` and `yq` through the environment, never through the command line, so a configured secret does not become world-readable in `/proc`. Only the declared schema makes a value a number or a boolean; without one it is written as a string.
- [`dybatpho::config_save`](#dybatphoconfig_save) — Write configuration values back to a file, in the format that file already uses. The extension selects the format, the file is created when it does not exist, and the rewrite is atomic, so a reader sees either the previous file or the complete new one. A dotenv file keeps its comments, blank lines, and assignment order; JSON, YAML, and TOML are rewritten with `jq` and `yq`, which leaves the keys this call does not name untouched. A value is written as a number or a boolean only when `dybatpho::config_schema` declared it as `int` or `bool`; otherwise it is written as a string.
- [`__dybatpho_config_schema_type`](#__dybatpho_config_schema_type) — Normalize a schema type name to its canonical form. Every type the `validate` module knows is a configuration type, so a schema can declare `email`, `port`, `semver`, `dir` or anything else registered there without `config` carrying a second copy of the check. `enum` is the one name `config` owns: it is not a type but a `choices` rule, which the validator receives as such.
- [`__dybatpho_config_schema_clear`](#__dybatpho_config_schema_clear) — Drop every attribute previously declared for a key.
- [`__dybatpho_config_schema_attr`](#__dybatpho_config_schema_attr) — Print a schema attribute, or a fallback when it is not declared.
- [`__dybatpho_config_schema_constraints`](#__dybatpho_config_schema_constraints) — Describe the range and choice constraints declared for a key.
- [`dybatpho::config_schema`](#dybatphoconfig_schema) — Declare validation rules for a configuration key.
- [`dybatpho::config_schema_reset`](#dybatphoconfig_schema_reset) — Forget every declared configuration schema.
- [`__dybatpho_config_schema_error`](#__dybatpho_config_schema_error) — Record a validation failure for a configuration key.
- [`__dybatpho_config_schema_check`](#__dybatpho_config_schema_check) — Validate a single value against the type declared for its key. The checking itself belongs to the `validate` module: this turns the declared attributes into its rules and gives each reason it reports the key that caused it.
- [`dybatpho::config_validate`](#dybatphoconfig_validate) — Validate configured values against all declared schemas. Missing optional keys take their declared default, and every violation is reported with the key that caused it.
- [`__dybatpho_config_doc_cell`](#__dybatpho_config_doc_cell) — Render one Markdown table cell, escaping pipes and marking empties.
- [`__dybatpho_config_doc_json_value`](#__dybatpho_config_doc_json_value) — Render one JSON value, emitting `null` for an undeclared attribute.
- [`dybatpho::config_doc`](#dybatphoconfig_doc) — Render documentation for every declared configuration key.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::config_load`

- Pass `--` before a file whose own name starts with `--`.

### `dybatpho::config_env`

- Environment variables override values loaded from configuration files.

### `dybatpho::config_save`

- Name the keys explicitly when `dybatpho::config_env` was used, so an unrelated environment variable is not persisted along with them.

### `dybatpho::config_schema`

- Call `dybatpho::config_validate` after all files and environment overlays are loaded.
- Declaring the same key twice replaces its previous rules instead of merging them.

### `dybatpho::config_doc`

- Pipe the Markdown output into a `CONFIGURATION.md` file to keep docs in sync with the schema.

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_config_set`

Store one configuration value, rejecting a key that is not a
name: the key becomes part of a variable name and of the schema, so a
stray character would land somewhere it cannot be looked up again.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Value |

**🧩 Variable sets**

- DYBATPHO_CONFIG

**🚦 Exit codes**

- `1`: Stop the script when the key is not a valid name


---

### `__dybatpho_config_load_dotenv`

Read a dotenv file into the configuration: `KEY=value` a line,
with `export` prefixes, quotes and trailing comments removed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | File to read |

**🧩 Variable sets**

- DYBATPHO_CONFIG


---

### `__dybatpho_config_load_structured`

Read a JSON, YAML or TOML file into the configuration, flattening
it to the dotted keys the rest of the module uses.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Format: `json`, `yaml` or `toml` |
| `$2` | path | File to read |

**🧩 Variable sets**

- DYBATPHO_CONFIG

**🚦 Exit codes**

- `1`: Stop the script when the document's root is not a mapping


---

### `dybatpho::config_load`

Load one or more configuration files, merging them left to right.

**🧪 Examples**

```bash
dybatpho::config_load defaults.yaml production.yaml

```

```bash
# A machine-local override that may simply not be there.
dybatpho::config_load --optional /etc/app.env "${HOME}/.config/app.env"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional `--optional`, to skip files that do not exist instead of failing |
| `$@` | string | Files in dotenv, JSON, YAML, or TOML format, in increasing precedence order |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG`** (Merged): values, where a later file replaces an earlier one

**🚦 Exit codes**

- `1`: A required file is missing, or a file has an unsupported format or invalid configuration


---

### `dybatpho::config_profile`

Load a base configuration file and the profile overlay beside it.
The overlay is the base name with the profile inserted before the
extension, so `config.yaml` with profile `prod` reads `config.prod.yaml`
after it. The base file is required; the overlay is not, which is what lets
the same call work on a machine that has no profile-specific file.

**🧪 Examples**

```bash
dybatpho::config_profile ./config.yaml prod

```

```bash
# The profile comes from the environment when it is not passed.
DYBATPHO_CONFIG_PROFILE=staging dybatpho::config_profile ./config.json

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Base configuration file, whose extension selects the format |
| `$2` | string | Profile name, defaulting to `DYBATPHO_CONFIG_PROFILE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CONFIG_PROFILE`** | string | Profile used when none is passed |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG`** (Base): values, overlaid by the profile file when it exists

**🚦 Exit codes**

- `1`: No profile is given, the profile name is invalid, or the base file is missing or unreadable


---

### `dybatpho::config_env`

Load environment variables after an optional prefix.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional prefix, such as `APP_` |


---

### `dybatpho::config_set`

Set a configuration value in memory.
The value joins the ones loaded from files and the environment, so a later
`dybatpho::config_validate` checks it like any other, and
`dybatpho::config_save` can write it back to a file.

**🧪 Example**

```bash
dybatpho::config_set PORT 9090
dybatpho::config_save ./config.yaml PORT

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Value |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG`** (The): key is added or replaced

**🚦 Exit codes**

- `1`: The key is invalid


---

### `dybatpho::config_get`

Print a configuration value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Optional default value |

**📤 Output on stdout**

- Configuration value

**🚦 Exit codes**

- `1`: Key is missing and no default was supplied


---

### `dybatpho::config_require`

Require configuration keys to be present.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Configuration keys |

**🚦 Exit codes**

- `1`: At least one key is missing


---

### `dybatpho::config_export`

Export loaded values as shell variables.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional prefix for exported variable names |

**🚦 Exit codes**

- `1`: A key cannot be represented as a shell variable


---

### `__dybatpho_config_dotenv_value`

Render one value the way a dotenv file has to carry it.
A value made only of characters the loader reads back verbatim is written
bare; anything else is double-quoted, because that is the only form whose
escapes the loader expands. The double quote itself is left alone on
purpose: the loader strips the outer pair by position rather than by
parsing, and `printf '%b'` has no `\"` escape to undo.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |

**📤 Output on stdout**

- The value, bare or double-quoted


---

### `__dybatpho_config_save_dotenv`

Rewrite the named keys into a dotenv file.
Every line that assigns one of the keys is replaced in place, so comments,
blank lines, unrelated assignments, and the order of the file all survive.
Keys the file does not mention are appended in the order they were given.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination file, which is created when it does not exist |
| `$@` | string | Configuration keys to write |

**🚦 Exit codes**

- `1`: A key cannot be spelled as a dotenv name, or the write fails


---

### `__dybatpho_config_save_structured`

Rewrite the named keys into a JSON, YAML, or TOML file.
Each key is assigned on its own rather than merged from a second document,
which is what keeps the file's own comments, indentation, and block style:
a node imported from JSON carries its flow style with it and reflows
everything around it.

Values reach `jq` and `yq` through the environment, never through the
command line, so a configured secret does not become world-readable in
`/proc`. Only the declared schema makes a value a number or a boolean;
without one it is written as a string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Format: `json`, `yaml`, or `toml` |
| `$2` | string | Destination file, which is created when it does not exist |
| `$@` | string | Configuration keys to write |

**🚦 Exit codes**

- `1`: `jq` or `yq` is missing, the file cannot be parsed, or the write fails


---

### `dybatpho::config_save`

Write configuration values back to a file, in the format that
file already uses. The extension selects the format, the file is created
when it does not exist, and the rewrite is atomic, so a reader sees either
the previous file or the complete new one.

A dotenv file keeps its comments, blank lines, and assignment order; JSON,
YAML, and TOML are rewritten with `jq` and `yq`, which leaves the keys this
call does not name untouched. A value is written as a number or a boolean
only when `dybatpho::config_schema` declared it as `int` or `bool`;
otherwise it is written as a string.

**🧪 Examples**

```bash
dybatpho::config_set PORT 9090
dybatpho::config_save ./config.yaml PORT

```

```bash
# Persist everything that is currently loaded.
dybatpho::config_save "${HOME}/.config/app.env"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination file in dotenv, JSON, YAML, or TOML format |
| `$@` | string | Configuration keys to write, defaulting to every loaded key in name order |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the write instead of performing it |

**🚦 Exit codes**

- `1`: A key is invalid or unset, the format is unsupported, or the write fails


---

### `__dybatpho_config_schema_type`

Normalize a schema type name to its canonical form.
Every type the `validate` module knows is a configuration type, so a schema
can declare `email`, `port`, `semver`, `dir` or anything else registered
there without `config` carrying a second copy of the check. `enum` is the
one name `config` owns: it is not a type but a `choices` rule, which the
validator receives as such.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Declared type |

**📤 Output on stdout**

- Canonical type name, or `enum`

**🚦 Exit codes**

- `1`: The type is not supported

**🔗 See also**

- [- `dybatpho::validate_types](#dybatphovalidate_types)


---

### `__dybatpho_config_schema_clear`

Drop every attribute previously declared for a key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |


---

### `__dybatpho_config_schema_attr`

Print a schema attribute, or a fallback when it is not declared.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Attribute name |
| `$3` | string | Optional fallback value |

**📤 Output on stdout**

- Attribute value


---

### `__dybatpho_config_schema_constraints`

Describe the range and choice constraints declared for a key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |

**📤 Output on stdout**

- Human readable constraints, or an empty string when none are declared


---

### `dybatpho::config_schema`

Declare validation rules for a configuration key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Type: any name `dybatpho::validate_types` prints — `string`, `int`, `bool`, `url`, `email`, `port`, `semver`, `dir`, a type of your own — or `enum` |
| `$@` | string | Rules: `required:true`, `default:value`, `min:number`, `max:number`, `choices:a,b`, `description:text` |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG_SCHEMA`** (Declared): attributes, keyed by `<key>.<attribute>`
- **`DYBATPHO_CONFIG_SCHEMA_KEYS`** (Declaration): order used by validation and documentation

**🚦 Exit codes**

- `1`: The key, type, or a rule is invalid


---

### `dybatpho::config_schema_reset`

Forget every declared configuration schema.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_CONFIG_SCHEMA`**: Emptied
- **`DYBATPHO_CONFIG_SCHEMA_KEYS`**: Emptied


---

### `__dybatpho_config_schema_error`

Record a validation failure for a configuration key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Reason describing the violation |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG_ERRORS`** (Appends): the formatted message


---

### `__dybatpho_config_schema_check`

Validate a single value against the type declared for its key.
The checking itself belongs to the `validate` module: this turns the
declared attributes into its rules and gives each reason it reports the key
that caused it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Effective value |

**🧩 Variable sets**

- **`DYBATPHO_CONFIG_ERRORS`** (Appends): one message per violation


---

### `dybatpho::config_validate`

Validate configured values against all declared schemas.
Missing optional keys take their declared default, and every violation is
reported with the key that caused it.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_CONFIG`** (Applies): declared defaults for missing keys
- **`DYBATPHO_CONFIG_ERRORS`** (One): message per violation, in declaration order

**🚦 Exit codes**

- `1`: A required key is missing or a value violates its schema


---

### `__dybatpho_config_doc_cell`

Render one Markdown table cell, escaping pipes and marking empties.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cell text |
| `$2` | string | Optional `code` to wrap a non-empty cell in backticks |

**📤 Output on stdout**

- Markdown cell text, or `-` when the value is empty


---

### `__dybatpho_config_doc_json_value`

Render one JSON value, emitting `null` for an undeclared attribute.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Attribute value |
| `$2` | string | Optional `declared` to emit an empty string instead of `null` |

**📤 Output on stdout**

- Quoted JSON string, or `null`


---

### `dybatpho::config_doc`

Render documentation for every declared configuration key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional format: `markdown` (default), `text`, or `json` |
| `$2` | string | Optional title used by the `markdown` and `text` formats |

**📤 Output on stdout**

- Configuration reference in the requested format

**🚦 Exit codes**

- `1`: The format is not supported
