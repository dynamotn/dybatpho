# Feature Specification: Configuration Utilities

## Problem Statement

Shell scripts commonly duplicate unsafe `.env` parsing and inconsistent
configuration precedence rules.

## Requirements

- Load dotenv, JSON, and YAML files without sourcing shell code.
- Apply files from left to right, with later files taking precedence.
- Apply prefixed environment variables as the highest-precedence source.
- Provide value lookup, required-key validation, and optional export to shell variables.
- Reject missing files, unsupported formats, invalid keys, and malformed structured data.

## User Workflow

```bash
dybatpho::config_load defaults.env production.yaml
dybatpho::config_env APP_
dybatpho::config_require HOST
host="$(dybatpho::config_get HOST)"
dybatpho::config_export
```
