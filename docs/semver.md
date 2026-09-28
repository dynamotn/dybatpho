# semver.sh

Utilities for working with Semantic Versioning (semver)

> 🧭 Source: [src/semver.sh](../src/semver.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

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
- [`__dybatpho_semver_fill`](#__dybatpho_semver_fill) — Fill a partial version out to `major.minor.patch`. A range may name only part of a version, and `1.2` has to become `1.2.0` before it can be compared against anything.
- [`__dybatpho_semver_specificity`](#__dybatpho_semver_specificity) — Print how many parts of a version a range actually named. `^1` and `^1.0.0` bound different ranges, so the caret and tilde rules need to know which parts were written down.
- [`__dybatpho_semver_expand`](#__dybatpho_semver_expand) — Expand one range comparator into plain `<operator> <version>` bounds. Every shorthand a range may use — a caret, a tilde, a wildcard, a partial version — turns into one or two simple comparisons here, so that the matching itself only ever compares two complete versions. The bounds are appended to a caller-supplied array rather than printed: a command substitution would validate inside a subshell, where a rejected comparator could not stop the caller from reporting a match.
- [`__dybatpho_semver_holds`](#__dybatpho_semver_holds) — Return success when a version satisfies one comparison.
- [`dybatpho::semver_satisfies`](#dybatphosemver_satisfies) — Return success when a version satisfies a range. Ranges are written the way npm and Cargo write them: `^1.2.3` for anything compatible, `~1.2.3` for patch updates, plain comparisons such as `>=1.2.0`, partial versions and wildcards such as `1.2.x`, several comparators separated by spaces meaning all of them, and `||` meaning either.
- [`dybatpho::semver_sort`](#dybatphosemver_sort) — Print versions in order, lowest first. Ordering follows the specification rather than string order, so `1.10.0` comes after `1.9.0` and a pre-release comes before the release it precedes.
- [`dybatpho::semver_max`](#dybatphosemver_max) — Print the highest of a list of versions.
- [`dybatpho::semver_coerce`](#dybatphosemver_coerce) — Normalize a version, as a real command reports it, into a semver string the rest of this module accepts. `dybatpho::semver_satisfies` insists on a complete version, and this is what turns what a command actually printed into one. `dybatpho::semver_compare` only looks at `major.minor.patch`, and almost nothing in the wild says its version that way: `tar` answers `1.35`, `yq` answers `v4.53.3` buried in a sentence, and `unzip` answers `6.00`. This fills the missing fields with zero, drops a leading `v`, and strips the leading zeros semver forbids. A version with more than three fields, as several Windows tools report, is cut down to the first three. A trailing `-something` is only kept as a pre-release when it opens with a word that names one. Distributions patch tools and say so in that same place: this host's `grep` answers `3.12-modified`, and Debian builds answer things like `1.2.3-1ubuntu2`. Read as semver, those rank *below* the plain release, so `>=3.12` would reject the very grep that satisfies it. A build marker is dropped; `1.7.1-rc1` keeps its pre-release and still ranks below `1.7.1`, which is what a pre-release is supposed to do.

<a id="see-also"></a>
## 🔗 See also

- [https://semver.org/](https://semver.org/)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::semver_satisfies`

- A pre-release only satisfies a range that names a pre-release of the same `major.minor.patch`, so `^1.0.0` does not quietly accept `2.0.0-alpha`

### `dybatpho::semver_sort`

- A leading `v` is accepted and preserved, so a list of tags sorts as it is

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


---

### `__dybatpho_semver_fill`

Fill a partial version out to `major.minor.patch`.
A range may name only part of a version, and `1.2` has to become `1.2.0`
before it can be compared against anything.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Partial version such as `1`, `1.2`, or `1.2.3` |

**📤 Output on stdout**

- The version with its missing parts set to zero


---

### `__dybatpho_semver_specificity`

Print how many parts of a version a range actually named.
`^1` and `^1.0.0` bound different ranges, so the caret and tilde rules need
to know which parts were written down.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version or partial version |

**📤 Output on stdout**

- `1`, `2`, or `3`


---

### `__dybatpho_semver_expand`

Expand one range comparator into plain `<operator> <version>` bounds.
Every shorthand a range may use — a caret, a tilde, a wildcard, a partial
version — turns into one or two simple comparisons here, so that the
matching itself only ever compares two complete versions.
The bounds are appended to a caller-supplied array rather than printed: a
command substitution would validate inside a subshell, where a rejected
comparator could not stop the caller from reporting a match.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array the bounds are appended to |
| `$2` | string | A single comparator such as `^1.2`, `>=1.0.0`, or `1.2.x` |

**🧩 Variable sets**

- **`The`** (named): array, with one `<operator> <version>` entry per bound

**🚦 Exit codes**

- `1`: The comparator cannot be understood


---

### `__dybatpho_semver_holds`

Return success when a version satisfies one comparison.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version to test |
| `$2` | string | Operator, one of `=`, `>`, `>=`, `<`, or `<=` |
| `$3` | string | Version to compare against |

**🚦 Exit codes**

- `0`: The comparison holds
- `1`: It does not


---

### `dybatpho::semver_satisfies`

Return success when a version satisfies a range.
Ranges are written the way npm and Cargo write them: `^1.2.3` for anything
compatible, `~1.2.3` for patch updates, plain comparisons such as `>=1.2.0`,
partial versions and wildcards such as `1.2.x`, several comparators
separated by spaces meaning all of them, and `||` meaning either.

**🧪 Examples**

```bash
dybatpho::semver_satisfies "1.4.2" "^1.2"        # yes
dybatpho::semver_satisfies "2.0.0" "^1.2"        # no
dybatpho::semver_satisfies "1.2.9" "~1.2.3"      # yes
dybatpho::semver_satisfies "1.5.0" ">=1.2 <1.9"  # yes
dybatpho::semver_satisfies "3.1.0" "^1.0 || ^3.0"

```

```bash
dybatpho::semver_satisfies "$(jq -r .version package.json)" ">=18" \
  || dybatpho::die "Node 18 or newer is required"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Version to test |
| `$2` | string | Range expression |

**🚦 Exit codes**

- `0`: The version satisfies the range
- `1`: It does not


---

### `dybatpho::semver_sort`

Print versions in order, lowest first.
Ordering follows the specification rather than string order, so `1.10.0`
comes after `1.9.0` and a pre-release comes before the release it precedes.

**🧪 Example**

```bash
dybatpho::semver_sort 1.10.0 1.9.0 2.0.0-rc.1 2.0.0
git tag --list 'v*' | dybatpho::semver_sort

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Versions to sort, or none to read them from standard input |

**📥 Input on stdin**

- One version per line, when no argument is given

**📤 Output on stdout**

- The versions, one per line, lowest first

**🚦 Exit codes**

- `1`: One of the inputs is not a valid version


---

### `dybatpho::semver_max`

Print the highest of a list of versions.

**🧪 Example**

```bash
latest="$(dybatpho::semver_max 1.10.0 1.9.0 2.0.0-rc.1)"
latest="$(git tag --list 'v*' | dybatpho::semver_max)"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Versions to compare, or none to read them from standard input |

**📥 Input on stdin**

- One version per line, when no argument is given

**📤 Output on stdout**

- The highest version, as it was written

**🚦 Exit codes**

- `1`: No version was given, or one of them is not valid


---

### `dybatpho::semver_coerce`

Normalize a version, as a real command reports it, into a semver
string the rest of this module accepts.
`dybatpho::semver_satisfies` insists on a complete version, and this is what
turns what a command actually printed into one.
`dybatpho::semver_compare` only looks at `major.minor.patch`, and almost
nothing in the wild says its version that way: `tar` answers `1.35`, `yq`
answers `v4.53.3` buried in a sentence, and `unzip` answers `6.00`. This
fills the missing fields with zero, drops a leading `v`, and strips the
leading zeros semver forbids.

A version with more than three fields, as several Windows tools report, is
cut down to the first three.

A trailing `-something` is only kept as a pre-release when it opens with a
word that names one. Distributions patch tools and say so in that same
place: this host's `grep` answers `3.12-modified`, and Debian builds answer
things like `1.2.3-1ubuntu2`. Read as semver, those rank *below* the plain
release, so `>=3.12` would reject the very grep that satisfies it. A build
marker is dropped; `1.7.1-rc1` keeps its pre-release and still ranks below
`1.7.1`, which is what a pre-release is supposed to do.

**🧪 Example**

```bash
dybatpho::semver_coerce 1.35                   # 1.35.0
dybatpho::semver_coerce "git version 2.43.0"   # 2.43.0
dybatpho::semver_coerce v4                     # 4.0.0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | A version, or any text with one in it |

**📤 Output on stdout**

- The version as `major.minor.patch`, with the pre-release kept

**🚦 Exit codes**

- `0`: A version was found
- `1`: Stop the script when the text holds no version

**🔗 See also**

- [- `dybatpho::command_version](#dybatphocommand_version)
