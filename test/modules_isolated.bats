setup() {
  load test_helper
}

# The module tests load the whole library through `test/test_helper.bash`, so a
# module that calls into another one it never declared still passes them: the
# other module happens to be loaded. These tests load each module the way a
# script asking for it alone would, in a fresh shell, so a missing dependency
# edge fails here instead of in a user's script.

PRISTINE='while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'

# Print the functions a shell has after loading one module, one per line.
# Written to a file rather than passed to `bash -c`, for the reason
# `test/init.bats` gives.
functions_with_only() {
  local script="${BATS_TEST_TMPDIR}/only-${1}.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf '. %q --modules %s\n' "${DYBATPHO_DIR}/init.sh" "${1}"
    printf '%s\n' 'compgen -A function'
  } > "${script}"
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
}

# Print the functions a source file defines, one per line.
functions_of() {
  sed -nE 's/^function ([A-Za-z_][A-Za-z_0-9:]*).*/\1/p' "$@"
}

@test "every module loads in a shell that asked for it alone" {
  local module broken=""
  for module in $(dybatpho::module_list all); do
    functions_with_only "${module}" > /dev/null 2>&1 || broken="${broken} ${module}"
  done
  assert_equal "${broken}" ""
}

@test "every library function a module calls is there when the module is loaded alone" {
  # A call is covered when loading the module alone defines the function, when
  # it belongs to a soft dependency loaded on demand, when it belongs to a
  # module the file only reaches behind a `declare -F` guard -- an optional
  # hook -- or when the module removes the function itself after using it.
  local -A owner=()
  local file name module
  for file in "${DYBATPHO_DIR}"/src/*.sh; do
    module="$(basename "${file}" .sh)"
    while read -r name; do owner["${name}"]="${module}"; done < <(functions_of "${file}")
  done
  while read -r name; do owner["${name}"]="init"; done < <(functions_of "${DYBATPHO_DIR}/init.sh")

  local missing="" defined allowed dep guarded called
  for module in $(dybatpho::module_list all); do
    file="${DYBATPHO_DIR}/src/${module}.sh"
    defined=" $(functions_with_only "${module}" | tr '\n' ' ') "
    allowed=" ${__dybatpho_module_soft_deps[${module}]-} "
    for guarded in $(grep -oE 'declare -F __dybatpho_[a-z_0-9]+' "${file}" | awk '{print $3}'); do
      dep="${owner[${guarded}]-}"
      [[ -z "${dep}" ]] || allowed="${allowed}${dep} "
    done
    allowed="${allowed}$(sed -nE 's/^[[:space:]]*unset -f ([A-Za-z_][A-Za-z_0-9:]*).*/\1/p' "${file}" | tr '\n' ' ') "
    called="$(grep -vE '^[[:space:]]*#' "${file}" \
      | grep -oE '(dybatpho::[a-z_0-9:]*[a-z_0-9]|__dybatpho_[a-z_0-9]+)' | sort -u)"
    for name in ${called}; do
      dep="${owner[${name}]-}"
      [[ -n "${dep}" ]] || continue
      [[ "${defined}" == *" ${name} "* ]] && continue
      [[ "${allowed}" == *" ${dep} "* || "${allowed}" == *" ${name} "* ]] && continue
      missing="${missing}"$'\n'"${module} -> ${name} (${dep})"
    done
  done
  assert_equal "${missing}" ""
}
