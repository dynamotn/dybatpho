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

### 🚀 Highlights

- [`__dybatpho_config_set`](#__dybatpho_config_set) — 
- [`__dybatpho_config_load_dotenv`](#__dybatpho_config_load_dotenv) — 
- [`__dybatpho_config_load_structured`](#__dybatpho_config_load_structured) — 
- [`dybatpho::config_load`](#dybatphoconfig_load) — Load one or more configuration files.
- [`dybatpho::config_env`](#dybatphoconfig_env) — Load environment variables after an optional prefix.
- [`dybatpho::config_get`](#dybatphoconfig_get) — Print a configuration value.
- [`dybatpho::config_require`](#dybatphoconfig_require) — Require configuration keys to be present.
- [`dybatpho::config_export`](#dybatphoconfig_export) — Export loaded values as shell variables.
- [`dybatpho::config_schema`](#dybatphoconfig_schema) — Declare validation rules for a configuration key.
- [`__dybatpho_config_schema_error`](#__dybatpho_config_schema_error) — 
- [`dybatpho::config_validate`](#dybatphoconfig_validate) — Validate configured values against all declared schemas.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::config_env`

- Environment variables override values loaded from configuration files.

### `dybatpho::config_schema`

- Call `dybatpho::config_validate` after all files and environment overlays are loaded.

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_config_set`



---

### `__dybatpho_config_load_dotenv`



---

### `__dybatpho_config_load_structured`



---

### `dybatpho::config_load`

Load one or more configuration files.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Files in dotenv, JSON, or YAML format, in increasing precedence order |

**🚦 Exit codes**

- `1`: A file is missing or has invalid configuration


---

### `dybatpho::config_env`

Load environment variables after an optional prefix.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional prefix, such as `APP_` |


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

### `dybatpho::config_schema`

Declare validation rules for a configuration key.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |
| `$2` | string | Type: string, int, bool, url, or enum |
| `$@` | string | Rules: required:true, default:value, min:number, max:number, choices:a,b |


---

### `__dybatpho_config_schema_error`



---

### `dybatpho::config_validate`

Validate configured values against all declared schemas.

**🚦 Exit codes**

- `1`: A required key is missing or a value violates its schema

