#!/usr/bin/env bash
# This script reads library results through `$(...)`, which is how the library returns them. A failure there prints
# its own diagnostic, and in an assignment its status reaches `set -e` through `inherit_errexit` (Bash 4.4+).
# dyshellint disable=BSG047 # values come back on stdout
# @file init_modules.sh
# @brief Example showing how to bootstrap dybatpho with a subset of modules.
#
# A release script only needs a handful of modules, so it asks for them by name
# instead of paying for the whole library. Anything else it turns out to need
# later is loaded on demand.
# @description
#   Shows what a selective bootstrap covers: which modules a selection loads,
#   what is still unloaded, and how a module asked for later arrives on demand.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules git semver

dybatpho::register_common_handlers

dybatpho::header "REQUESTED MODULE SET"
dybatpho::print "requested: git semver"
module_list_8=$(dybatpho::module_list loaded | tr '\n' ' ')
module_list_7=${module_list_8}
dybatpho::print "loaded:    ${module_list_7}"
dybatpho::info "The core modules come along with every module set"

# A module set is a contract the script can check before it relies on one.
# shellcheck disable=SC2310 # `module_loaded` is a question; the example asks it
if dybatpho::module_loaded semver; then
  semver_bump=$(dybatpho::semver_bump "1.4.2" minor)
  dybatpho::print "next minor release: ${semver_bump}"
fi

# shellcheck disable=SC2310 # `module_loaded` is a question; the example asks it
if ! dybatpho::module_loaded network; then
  dybatpho::info "network is not loaded, so curl helpers stay out of this shell"
fi

dybatpho::header "LOADING A MODULE ON DEMAND"
# The release notes turn out to need a table, and table depends on text, so
# asking for `table` brings both in.
dybatpho::load table
module_list_6=$(dybatpho::module_list loaded | tr '\n' ' ')
module_list_5=${module_list_6}
dybatpho::print "loaded now: ${module_list_5}"
dybatpho::info "table pulled in its text dependency automatically"

text_indent=$(dybatpho::text_indent "release notes are indented by two spaces")
dybatpho::print "${text_indent}"

dybatpho::header "SOFT DEPENDENCIES"
# Rendering CSV is `table`'s job, but parsing it is `csv`'s, which `table` does
# not load up front. The first call that needs it loads it in this shell -- not
# inside `$(...)`, where the module would be gone with the subshell.
dybatpho::table_from_csv $'module,tier\njson,stable\ntui,experimental' markdown
# shellcheck disable=SC2310 # `module_loaded` is a question; the example asks it
if dybatpho::module_loaded csv; then
  dybatpho::info "csv was loaded on demand by dybatpho::table_from_csv"
fi

dybatpho::header "STABILITY TIERS"
for module in semver table; do
  # Both names are registered, so `module_tier` cannot stop inside `$(...)`.
  tier=$(dybatpho::module_tier "${module}")
  dybatpho::print "${module}: ${tier}"
done
module_list_9=$(dybatpho::module_list experimental | wc -l)
dybatpho::print "experimental modules: ${module_list_9// /}"

dybatpho::header "AVAILABLE MODULES"
module_list_4=$(dybatpho::module_list core | tr '\n' ' ')
module_list_3=${module_list_4}
dybatpho::print "core:     ${module_list_3}"
module_list_2=$(dybatpho::module_list optional | tr '\n' ' ')
module_list=${module_list_2}
dybatpho::print "optional: ${module_list}"

dybatpho::success "Module demo complete"
