# Find calls, inside a command substitution, to a function that can stop the
# script with `dybatpho::die`.
#
# `dybatpho::die` ends the shell it runs in. Inside `$(...)` that is only the
# subshell the substitution created, so a refusal meant to stop the script ends
# the substitution instead, and the caller carries on with whatever was
# captured -- usually nothing. AGENT.md forbids validating inside a command
# substitution for that reason; this finds the places that still do.
#
# A function can stop the script when its body calls `dybatpho::die`, or when
# it calls a function that can, worked out to a fixed point over every function
# in the files given. The argument checks -- `dybatpho::expect_args` and its
# kin -- are left out of that spread: they refuse a call the caller wrote
# wrong, not input the caller was handed, and counting them would mark nearly
# every function in the library.
#
# A site is left alone when the substitution's status is read on the spot: the
# line, or the line after one that ends in `\`, goes on with `|| return`,
# `|| dybatpho::die`, `|| exit`, `|| {`, or `|| <var>=`. That still prints the
# refusal from inside the subshell, but the caller no longer carries on.
#
# Output: one line per site, `file<TAB>function<TAB>callee<TAB>line`, with the
# file relative to the directory the scan ran from.
#
# Usage: awk -f test/die-in-substitution.awk src/*.sh scripts/*.sh init.sh

BEGIN {
  skip["dybatpho::expect_args"] = 1
  skip["dybatpho::expect_ref"] = 1
  skip["dybatpho::expect_envs"] = 1
  skip["dybatpho::still_has_args"] = 1
  skip["dybatpho::die"] = 1
  skip["dybatpho::fatal"] = 1
  skip["dybatpho::require"] = 1
  skip["__dybatpho_helpers_need_module"] = 1
  name_re = "(dybatpho::[a-z_0-9:]+|__dybatpho_[a-z_0-9]+)"
  edges = 0
  sites = 0
}

FNR == 1 {
  fn = ""
  pending = 0
}

/^function [A-Za-z_][A-Za-z_0-9:]* / {
  fn = $2
  next
}

/^}$/ {
  fn = ""
  pending = 0
  next
}

fn == "" { next }

/^[[:space:]]*#/ { next }

{
  text = $0

  # A substitution on the line before, left open with `\`, guarded here.
  if (pending && text ~ /^[[:space:]]*\|\|[[:space:]]*(return|dybatpho::die|exit|\{|[A-Za-z_][A-Za-z_0-9]*=)/) {
    guarded[pending] = 1
  }
  pending = 0

  if (text ~ /dybatpho::die/ && !(fn in skip)) {
    can[fn] = 1
  }

  rest = text
  while (match(rest, name_re)) {
    callee = substr(rest, RSTART, RLENGTH)
    if (callee != fn && !(callee in skip)) {
      edges++
      edge_from[edges] = fn
      edge_to[edges] = callee
    }
    rest = substr(rest, RSTART + RLENGTH)
  }

  rest = text
  while (match(rest, "\\$\\(" name_re)) {
    sites++
    site_file[sites] = FILENAME
    site_fn[sites] = fn
    site_callee[sites] = substr(rest, RSTART + 2, RLENGTH - 2)
    site_line[sites] = FNR
    after = substr(rest, RSTART + RLENGTH)
    if (after ~ /\)"?[[:space:]]*\|\|[[:space:]]*(return|dybatpho::die|exit|\{|[A-Za-z_][A-Za-z_0-9]*=)/) {
      guarded[sites] = 1
    } else if (text ~ /\\$/) {
      pending = sites
    }
    rest = after
  }
}

END {
  changed = 1
  while (changed) {
    changed = 0
    for (e = 1; e <= edges; e++) {
      if ((edge_to[e] in can) && !(edge_from[e] in can) && !(edge_from[e] in skip)) {
        can[edge_from[e]] = 1
        changed = 1
      }
    }
  }
  for (s = 1; s <= sites; s++) {
    if ((site_callee[s] in can) && !(s in guarded)) {
      printf "%s\t%s\t%s\t%s\n", site_file[s], site_fn[s], site_callee[s], site_line[s]
    }
  }
}
