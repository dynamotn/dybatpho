# semver.sh

Utilities for working with Semantic Versioning (semver)

> 🧭 Source: [src/semver.sh](../src/semver.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for parsing, validating, comparing semver strings,
and detecting the release type of a version bump.


Follows [Semantic Versioning 2.0.0](https://semver.org/) spec.
A leading `v` prefix (e.g. `v1.2.3`) is accepted and stripped automatically.

### 🚀 Highlights

- [`dybatpho::semver_valid`](#dybatphosemver_valid) — Return success when the string is a valid semver (with optional leading v).
- [`dybatpho::semver_parse`](#dybatphosemver_parse) — Parse a semver string and print its components, one per line.
- [`dybatpho::semver_compare`](#dybatphosemver_compare) — Compare two semver strings according to semver 2.0.0 precedence rules.
- [`dybatpho::semver_bump`](#dybatphosemver_bump) — Bump a semver version by the specified part.
- [`dybatpho::semver_release_type`](#dybatphosemver_release_type) — Detect the release type between two semver versions.

<a id="see-also"></a>
## 🔗 See also

- [https://semver.org/](#httpssemverorg)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::semver_valid`

Return success when the string is a valid semver (with optional leading v).

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version string to validate |

**🚦 Exit codes**

- `0`: Valid semver
- `1`: Invalid semver


---

### `dybatpho::semver_parse`

Parse a semver string and print its components, one per line.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version string to parse |

**📤 Output on stdout**

- Five lines: major, minor, patch, pre-release (empty if none), build-metadata (empty if none)

**🚦 Exit codes**

- `0`: Parsing succeeded
- `1`: The string is not a valid semver


---

### `dybatpho::semver_compare`

Compare two semver strings according to semver 2.0.0 precedence rules.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First version |
| `$2` | string | Second version |

**📝 Notes**

- Build metadata is ignored for comparison (per semver spec).

**📤 Output on stdout**

- -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2

**🚦 Exit codes**

- `0`: Always succeeds (comparison result is on stdout)


---

### `dybatpho::semver_bump`

Bump a semver version by the specified part.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version string to bump |
| `$2` | string | Part to bump: major \| minor \| patch |
| `$3` | string | Optional pre-release label to attach (e.g. "alpha.1") |
| `$4` | string | Optional build-metadata to attach (e.g. "build.42") |

**📝 Notes**

- Bumping major resets minor and patch to 0. Bumping minor resets patch to 0. Pre-release and build-metadata from the source version are always dropped; pass $3/$4 to attach new ones to the result.

**📤 Output on stdout**

- Bumped version string (no leading v, no pre-release/build unless supplied)

**🚦 Exit codes**

- `0`: Always succeeds
- `1`: The version is invalid or the part is not one of major/minor/patch


---

### `dybatpho::semver_release_type`

Detect the release type between two semver versions.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Old (base) version |
| `$2` | string | New (next) version |

**📤 Output on stdout**

- One of: major, minor, patch, pre-release, build, equal
        - major       — major number increased
        - minor       — minor number increased (major unchanged)
        - patch       — patch number increased (major & minor unchanged)
        - pre-release — numeric core is the same, pre-release label changed or added
        - build       — everything else is the same, only build-metadata differs
        - equal       — versions are identical (ignoring build-metadata per semver spec;
                        use `build` when build-metadata differs but all else is equal)

**🚦 Exit codes**

- `0`: Always succeeds
- `1`: Either argument is not a valid semver

