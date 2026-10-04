# Find functions whose plain locals a caller's code or a caller's variable name
# can reach.
#
# Bash scopes variables dynamically: a function's locals are visible to every
# function it calls, and a nameref resolves its target from where it is used.
# Two kinds of function therefore have to keep every local under the library's
# `__dybatpho_` prefix:
#
# - `runs`: a function that runs code the caller handed it -- `"$@"`, a
#   positional argument, `eval` of an expansion, or a command or callback held
#   in a variable named for what it holds (`command`, `handler`, `callback`,
#   `predicate`, `mapper`, `producer`, `launcher`, `action`, `spec`,
#   `comparator`, `hook`, ...). A variable holding an external program, such
#   as `tool` or `curl`, does not count: a program runs in its own process and
#   cannot see the shell's variables. The
#   caller's code runs in the function's scope, so a plain local such as
#   `status` or `name` hides the caller's variable of the same name from it, and
#   the code can overwrite the function's state through it.
# - `name`: a public function that takes the name of a caller's variable to
#   fill or read (it checks the name with `dybatpho::expect_ref`, or binds a
#   nameref to it). A caller variable named like one of its plain locals
#   resolves to that local instead, and the result never reaches the caller.
#
# A function that hands code on -- `"$@"`, or a variable named for a command --
# to a function that runs it counts too, since its locals are in scope while the
# code runs; that is spread to a fixed point, except through a function the
# allowlist marks `stop`. A nested function counts toward the function it is
# defined in, since it runs inside that function's scope.
#
# Output: one line per plain local, `file<TAB>function<TAB>kind<TAB>local<TAB>line`,
# with the file relative to the directory the scan ran from and the line where
# the function starts.
#
# Known gap: code reached through a registry, such as the tools `dybatpho::ai_run`
# looks up by name, is caught where it runs (`__dybatpho_ai_tool_invoke`) but not
# in the function that started the lookup.
#
# Usage: awk -v allow=test/scope-leak.allow -f test/scope-leak.awk src/*.sh scripts/*.sh init.sh

function flush(   name) {
  if (fn == "") return
  fn_file[fn] = file
  fn_start[fn] = start
  if (runs) fn_runs[fn] = 1
  if (takes_name && fn ~ /^dybatpho::/) fn_name[fn] = 1
  for (name in plain) fn_plain[fn] = fn_plain[fn] " " name
  fn = ""
  runs = 0
  takes_name = 0
  delete plain
}

function add_locals(text,   rest, count, i, word, toks) {
  rest = text
  sub(/^[ \t]*local[ \t]+/, "", rest)
  # Drop quoted values, substitutions and array literals, which can hold spaces.
  gsub(/"[^"]*"/, "", rest)
  gsub(/'[^']*'/, "", rest)
  gsub(/\([^()]*\)/, "", rest)
  count = split(rest, toks, /[ \t]+/)
  for (i = 1; i <= count; i++) {
    word = toks[i]
    if (word == "" || word ~ /^-/) continue
    sub(/=.*/, "", word)
    sub(/\+$/, "", word)
    if (word !~ /^[A-Za-z_][A-Za-z_0-9]*$/) continue
    if (word ~ /^__dybatpho/) continue
    plain[word] = 1
  }
}

FNR == 1 {
  flush()
  file = FILENAME
  pending = ""
}

{
  line = $0
  # Join continuation lines, so a declaration or a command split over several
  # lines is read whole.
  if (pending != "") {
    line = pending " " line
    pending = ""
  }
  if (line ~ /\\$/) {
    sub(/\\$/, "", line)
    pending = line
    next
  }
}

line ~ /^function [A-Za-z_:][A-Za-z_0-9:]* \{/ {
  flush()
  fn = line
  sub(/^function /, "", fn)
  sub(/ .*/, "", fn)
  start = FNR
  next
}

fn != "" && line ~ /^}/ {
  flush()
  next
}

fn == "" { next }

{
  code = line
  if (code ~ /^[ \t]*#/) next
  if (code ~ /^[ \t]*local[ \t]/) {
    if (code ~ /^[ \t]*local[ \t]+-[a-zA-Z]*n/) takes_name = 1
    add_locals(code)
  }
  if (code ~ /dybatpho::expect_ref/) takes_name = 1
  # Code in command position: at the start of a statement, after a keyword or
  # a list operator, or as the first word of a substitution or a subshell. The
  # operands of `[[ ]]` and array literals are not commands, so they are taken
  # out first; a case pattern ends in `)`, which a command word is not followed
  # by.
  while (match(code, /\[\[ /)) {
    rest = substr(code, RSTART + 3)
    if (!match(rest, / \]\]/)) break
    code = substr(code, 1, index(code, "[[ ") - 1) substr(rest, RSTART + 3)
  }
  gsub(/\+?=\([^()]*\)/, "=", code)
  head = "(^|;|&&|\\|\\||!|\\(|\\$\\(|then|do|else|if|while|until)[ \t]*"
  callable = "(command|cmd|handler|callback|predicate|mapper|producer|launcher|action|spec|comparator|hook|before|map)"
  tail = "([ \t)]|$)"
  # Assignments in front of a command apply to it alone; the command word follows.
  head = head "([A-Za-z_][A-Za-z_0-9]*=(\"[^\"$]*\"|\"\\$\\{[A-Za-z_][A-Za-z_0-9]*\\}\"|[^ \t()$\"]*)[ \t]+)*"
  if (code ~ (head "\"\\$@\"" tail) || code ~ (head "\"\\$[0-9]\"" tail) \
    || code ~ (head "\"\\$\\{([A-Za-z_0-9]*_)?" callable "(\\[@\\])?\\}\"" tail) \
    || code ~ /(^|;|&&|\|\||!|\(|\$\()[ \t]*eval[ \t]+"?\$/) {
    if (code !~ /^[ \t]*(printf|echo|local|declare|return)[ \t]/) runs = 1
  }
  # A call that hands code on: the first argument after the callee is the
  # caller's command -- `"$@"`, or a variable named for one.
  first = "(\"\\$@\"|\"\\$\\{([A-Za-z_0-9]*_)?" callable "(_args|_argv)?(\\[@\\])?\\}\")"
  # `"$@"` further along counts as well, unless the first argument is a bare
  # word -- the name of a program, which runs in its own process.
  call = "(^|[;&|!(]|\\$\\(|then|do|if)[ \t]*[A-Za-z_][A-Za-z_0-9:]*[ \t]+"
  if (match(code, call first) \
    || (match(code, call "[\"$][^ \t]*[ \t].*\"\\$@\"") && code !~ /^[ \t]*(local|printf|echo)[ \t]/)) {
    callee = substr(code, RSTART, RLENGTH)
    sub(/^[^A-Za-z_]*/, "", callee)
    sub(/[ \t].*$/, "", callee)
    passes[fn] = passes[fn] " " callee
  }
}

END {
  flush()
  # A function reviewed in the allowlist runs only code it trusts, so it does
  # not spread to the functions that call it.
  if (allow != "") {
    while ((getline entry < allow) > 0) {
      if (entry ~ /^#/ || entry == "") continue
      split(entry, field, "\t")
      if (field[3] == "stop") safe[field[2]] = 1
    }
  }
  # A function that hands its caller's code on with `"$@"` to a function that
  # runs it has its own locals in scope while that code runs, so it runs the
  # code too. Spread that to a fixed point.
  changed = 1
  while (changed) {
    changed = 0
    for (f in passes) {
      if (f in fn_runs) continue
      n = split(passes[f], callees, " ")
      for (i = 1; i <= n; i++) {
        if ((callees[i] in fn_runs) && !(callees[i] in safe)) { fn_runs[f] = 1; changed = 1; break }
      }
    }
  }
  for (f in fn_file) {
    kinds = ""
    if (f in fn_runs) kinds = "runs"
    if (f in fn_name) kinds = kinds (kinds == "" ? "" : " ") "name"
    if (kinds == "" || fn_plain[f] == "") continue
    nk = split(kinds, kind_list, " ")
    np = split(fn_plain[f], names, " ")
    for (k = 1; k <= nk; k++)
      for (i = 1; i <= np; i++)
        if (names[i] != "") printf "%s\t%s\t%s\t%s\t%s\n", fn_file[f], f, kind_list[k], names[i], fn_start[f]
  }
}
