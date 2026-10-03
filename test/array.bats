setup() {
  load test_helper
}

@test "dybatpho::array_print output" {
  arr=()
  run_traced dybatpho::array_print "arr"
  assert_success
  refute_output
  arr=(2 33 55 "b c" 11)
  run_traced dybatpho::array_print "arr"
  assert_line --index 0 2
  assert_line --index 1 33
  assert_line --index 2 55
  assert_line --index 3 "b c"
  assert_line --index 4 11
}

@test "dybatpho::array_reverse output" {
  arr=()
  run_traced dybatpho::array_reverse "arr"
  assert_success
  refute_output
  run_traced dybatpho::array_reverse "arr" "--"
  assert_success
  refute_output
  arr=(1)
  run_traced dybatpho::array_reverse "arr" "--"
  assert_success
  assert_line --index 0 1
  arr=(1 2 "b c" 4 5)
  run_traced dybatpho::array_reverse "arr" "--"
  assert_success
  assert_line --index 0 5
  assert_line --index 1 4
  assert_line --index 2 "b c"
  assert_line --index 3 2
  assert_line --index 4 1
}

@test "dybatpho::array_reverse with sparse array" {
  arr=([5]="hello" [3]="world")
  run_traced dybatpho::array_reverse "arr" "--"
  assert_success
  assert_line --index 0 "hello"
  assert_line --index 1 "world"
}

@test "dybatpho::array_unique output" {
  arr=()
  run_traced dybatpho::array_unique "arr" "--"
  assert_success
  refute_output
  arr=(1 1 2 2 3 3 3 3 3 4 4 4 4 4 5 5 5 5 5 5)
  assert_equal "$(dybatpho::array_unique "arr" "--")" "1
2
3
4
5"
}

@test "dybatpho::array_unique keeps the first occurrence in order" {
  arr=(zebra apple mango apple banana zebra kiwi)
  assert_equal "$(dybatpho::array_unique "arr" "--")" "zebra
apple
mango
banana
kiwi"
}

@test "dybatpho::array_unique with spaces in elements" {
  # shellcheck disable=2034
  arr=("hello world" "hello world" "foo bar")
  run_traced dybatpho::array_unique "arr" "--"
  assert_success
  assert_line --index 0 "hello world"
  assert_line --index 1 "foo bar"
}

@test "dybatpho::array_contains finds matching element" {
  arr=("apple" "banana" "cherry")
  dybatpho::array_contains "arr" "banana"
}

@test "dybatpho::array_contains handles missing or spaced element" {
  arr=("hello world" "foo" "bar")
  dybatpho::array_contains "arr" "hello world"

  # Called directly so the non-matching branch runs in this shell.
  run_traced ! dybatpho::array_contains "arr" "baz"
}

@test "dybatpho::array_index_of prints first matching index" {
  arr=("apple" "banana" "banana" "cherry")
  assert_equal "$(dybatpho::array_index_of "arr" "banana")" "1"
}

@test "dybatpho::array_index_of supports sparse arrays" {
  arr=([3]="hello" [7]="world")
  assert_equal "$(dybatpho::array_index_of "arr" "world")" "7"
}

@test "dybatpho::array_index_of fails when element is missing" {
  arr=("apple" "banana")
  run_traced ! dybatpho::array_index_of "arr" "orange"
  assert_equal "$(dybatpho::array_index_of "arr" "orange" || true)" ""
}

@test "dybatpho::array_compact removes empty elements" {
  arr=("apple" "" "banana" "" "cherry")
  run_traced dybatpho::array_compact "arr" "--"
  assert_success
  assert_output << EOF
apple
banana
cherry
EOF
}

@test "dybatpho::array_compact preserves spaced strings and sparse arrays" {
  arr=([2]="" [4]="hello world" [7]="foo")
  run_traced dybatpho::array_compact "arr" "--"
  assert_success
  assert_line --index 0 "hello world"
  assert_line --index 1 "foo"
}

@test "dybatpho::array_filter keeps only matching values" {
  _keep_go_like() {
    [[ "$1" == go* ]]
  }
  arr=("go" "bash" "golang" "rust")
  run_traced dybatpho::array_filter "arr" "_keep_go_like" "--"
  assert_success
  assert_output << EOF
go
golang
EOF
}

@test "dybatpho::array_filter supports sparse arrays" {
  _keep_non_empty() {
    [[ -n "$1" ]]
  }
  arr=([2]="" [5]="hello" [9]="world")
  run_traced dybatpho::array_filter "arr" "_keep_non_empty" "--"
  assert_success
  assert_line --index 0 "hello"
  assert_line --index 1 "world"
}

@test "dybatpho::array_filter fails for invalid predicate" {
  arr=("a" "b")
  run --separate-stderr dybatpho::array_filter "arr" "not_a_real_function"
  assert_failure
  assert_stderr --partial "Invalid predicate function"
}

@test "dybatpho::array_map transforms each value" {
  _upper_word() {
    printf '%s\n' "${1^^}"
  }
  arr=("go" "bash" "dybatpho")
  run_traced dybatpho::array_map "arr" "_upper_word" "--"
  assert_success
  assert_output << EOF
GO
BASH
DYBATPHO
EOF
}

@test "dybatpho::array_map supports sparse arrays and mapper failures" {
  _wrap_word() {
    printf '<%s>\n' "$1"
  }
  _explode_on_world() {
    [[ "$1" == "world" ]] && return 7
    printf '%s\n' "$1"
  }
  arr=([2]="hello" [9]="world")
  run_traced dybatpho::array_map "arr" "_wrap_word" "--"
  assert_success
  assert_line --index 0 "<hello>"
  assert_line --index 1 "<world>"

  arr=("hello" "world")
  run_traced dybatpho::array_map "arr" "_explode_on_world"
  assert_failure 7
}

@test "dybatpho::array_map fails for invalid mapper" {
  arr=("a" "b")
  run --separate-stderr dybatpho::array_map "arr" "not_a_real_function"
  assert_failure
  assert_stderr --partial "Invalid mapper function"
}

@test "dybatpho::array_find prints first matching value" {
  _is_go_like() {
    [[ "$1" == go* ]]
  }
  arr=("bash" "golang" "go" "rust")
  assert_equal "$(dybatpho::array_find "arr" "_is_go_like")" "golang"
}

@test "dybatpho::array_find supports sparse arrays and missing matches" {
  _has_slash() {
    [[ "$1" == */* ]]
  }
  arr=([4]="tmp/cache" [9]="var/log")
  assert_equal "$(dybatpho::array_find "arr" "_has_slash")" "tmp/cache"

  _is_python() {
    [[ "$1" == python ]]
  }
  arr=("bash" "go")
  run_traced ! dybatpho::array_find "arr" "_is_python"
  assert_equal "$(dybatpho::array_find "arr" "_is_python" || true)" ""
}

@test "dybatpho::array_find fails for invalid predicate" {
  arr=("a" "b")
  run --separate-stderr dybatpho::array_find "arr" "not_a_real_function"
  assert_failure
  assert_stderr --partial "Invalid predicate function"
}

@test "dybatpho::array_every and dybatpho::array_some evaluate predicates" {
  _is_lowercase_word() {
    [[ "$1" =~ ^[a-z]+$ ]]
  }
  arr=("bash" "go" "rust")
  dybatpho::array_every "arr" "_is_lowercase_word"

  arr=("Bash" "go")
  run_traced dybatpho::array_every "arr" "_is_lowercase_word"
  assert_failure

  arr=("Bash" "go")
  dybatpho::array_some "arr" "_is_lowercase_word"

  arr=("Bash" "123")
  run_traced dybatpho::array_some "arr" "_is_lowercase_word"
  assert_failure
}

@test "dybatpho::array_reject removes matching values" {
  _is_go_like() {
    [[ "$1" == go* ]]
  }
  arr=("go" "bash" "golang" "rust")
  run_traced dybatpho::array_reject "arr" "_is_go_like" "--"
  assert_success
  assert_output << EOF
bash
rust
EOF
}

@test "dybatpho::array_first and dybatpho::array_last print array edges" {
  arr=("alpha" "beta" "gamma")
  assert_equal "$(dybatpho::array_first "arr")" "alpha"

  assert_equal "$(dybatpho::array_last "arr")" "gamma"

  arr=()
  run_traced dybatpho::array_first "arr"
  assert_failure

  run_traced dybatpho::array_last "arr"
  assert_failure
}

@test "dybatpho::array_join empty array" {
  arr=()
  run_traced dybatpho::array_join "arr" ","
  assert_success
  refute_output
}

@test "dybatpho::array_join walks a sparse array by its indexes" {
  # Counting 0..n-1 read index 0, which a sparse array may not have, and
  # stopped short of the highest index.
  local -a arr=()
  arr[2]="b"
  arr[5]="c"
  arr[9]="d"
  run_traced dybatpho::array_join "arr" ","
  assert_success
  assert_output "b,c,d"
}

@test "dybatpho::array_join single element" {
  arr=("hello")
  assert_equal "$(dybatpho::array_join "arr" ",")" "hello"
}

@test "dybatpho::array_join with comma separator" {
  arr=("a" "b" "c")
  assert_equal "$(dybatpho::array_join "arr" ",")" "a,b,c"
}

@test "dybatpho::array_join with space separator" {
  arr=("apple" "banana" "cherry")
  assert_equal "$(dybatpho::array_join "arr" " ")" "apple banana cherry"
}

@test "dybatpho::array_join with multi-character separator" {
  arr=("one" "two" "three")
  assert_equal "$(dybatpho::array_join "arr" " | ")" "one | two | three"
}

@test "dybatpho::array_join with empty separator" {
  arr=("a" "b" "c")
  assert_equal "$(dybatpho::array_join "arr" "")" "abc"
}

@test "dybatpho::array_join with special characters in separator" {
  arr=("start" "middle" "end")
  assert_equal "$(dybatpho::array_join "arr" "%%")" "start%%middle%%end"
  assert_equal "$(dybatpho::array_join "arr" "%")" "start%middle%end"
  assert_equal "$(dybatpho::array_join "arr" "-")" "start-middle-end"
  assert_equal "$(dybatpho::array_join "arr" "%q")" "start%qmiddle%qend"
}

@test "dybatpho::array_join with spaces in elements" {
  arr=("hello world" "foo bar" "test case")
  assert_equal "$(dybatpho::array_join "arr" " - ")" "hello world - foo bar - test case"
}

@test "dybatpho::array_join with numbers in array" {
  arr=(1 2 3 4 5)
  assert_equal "$(dybatpho::array_join "arr" ":")" "1:2:3:4:5"
}

@test "dybatpho::array_join with mixed content" {
  arr=("item1" 42 "item3" "test")
  assert_equal "$(dybatpho::array_join "arr" "|")" "item1|42|item3|test"
}

@test "dybatpho::array_unique skips empty elements and preserves output-free mode" {
  arr=("" "one" "" "one" "two")
  run_traced dybatpho::array_unique "arr"
  assert_success
  refute_output
  run_traced dybatpho::array_unique "arr" "--"
  assert_success
  assert_line "one"
  assert_line "two"
  refute_line ""
}

@test "dybatpho::array_filter, array_map, and array_reject support output-free mode" {
  _is_even_word() { [[ "$1" == even-* ]]; }
  _prefix_word() { printf 'mapped-%s\n' "$1"; }

  arr=("even-one" "odd" "even-two")
  run_traced dybatpho::array_filter "arr" "_is_even_word"
  assert_success
  refute_output

  arr=("one" "two")
  run_traced dybatpho::array_map "arr" "_prefix_word"
  assert_success
  refute_output

  arr=("even-one" "odd")
  run_traced dybatpho::array_reject "arr" "_is_even_word"
  assert_success
  refute_output
}

@test "dybatpho::array_every and array_some handle empty arrays" {
  _always_true() { return 0; }
  arr=()

  dybatpho::array_every "arr" "_always_true"

  run_traced dybatpho::array_some "arr" "_always_true"
  assert_failure
}

@test "dybatpho predicate array helpers reject invalid functions" {
  arr=("one")
  run --separate-stderr dybatpho::array_every "arr" "missing_predicate"
  assert_failure
  assert_stderr --partial "Invalid predicate function"

  run --separate-stderr dybatpho::array_some "arr" "missing_predicate"
  assert_failure
  assert_stderr --partial "Invalid predicate function"

  run --separate-stderr dybatpho::array_reject "arr" "missing_predicate"
  assert_failure
  assert_stderr --partial "Invalid predicate function"
}

@test "dybatpho::array_first and array_last handle sparse arrays" {
  arr=([4]="first" [9]="last")
  assert_equal "$(dybatpho::array_first "arr")" "first"

  assert_equal "$(dybatpho::array_last "arr")" "last"
}

@test "dybatpho::array_some reports whether any element matches" {
  _is_long() {
    ((${#1} > 3))
  }
  arr=("go" "rust" "c")
  dybatpho::array_some "arr" "_is_long"

  arr=("go" "c")
  run_traced ! dybatpho::array_some "arr" "_is_long"

  arr=()
  run_traced ! dybatpho::array_some "arr" "_is_long"
}

@test "dybatpho::array_some fails for invalid predicate" {
  arr=("a" "b")
  run --separate-stderr dybatpho::array_some "arr" "not_a_real_function"
  assert_failure
  assert_stderr --partial "Invalid predicate function"
}

@test "dybatpho::array_sort orders text and reverses it" {
  local fruit=(banana apple cherry)
  dybatpho::array_sort fruit
  assert_equal "${fruit[*]}" "apple banana cherry"
  dybatpho::array_sort fruit --reverse
  assert_equal "${fruit[*]}" "cherry banana apple"
}

@test "dybatpho::array_sort orders numbers by value under --numeric" {
  # The reason a shell script wants a sort at all: as text, 10 comes before 9.
  local sizes=(10 9 100 -3)
  dybatpho::array_sort sizes
  assert_equal "${sizes[*]}" "-3 10 100 9"
  sizes=(10 9 100 -3)
  dybatpho::array_sort sizes --numeric
  assert_equal "${sizes[*]}" "-3 9 10 100"
  dybatpho::array_sort sizes -n -r
  assert_equal "${sizes[*]}" "100 10 9 -3"
}

@test "dybatpho::array_sort handles the sizes where a sort does nothing" {
  local empty=()
  dybatpho::array_sort empty
  assert_equal "${#empty[@]}" "0"
  local single=(one)
  dybatpho::array_sort single
  assert_equal "${single[*]}" "one"
  local dupes=(b a b a)
  dybatpho::array_sort dupes
  assert_equal "${dupes[*]}" "a a b b"
}

@test "dybatpho::array_sort keeps an element that contains a newline" {
  # A pipe through sort(1) would split this element into two.
  local values=($'z\nz' a)
  dybatpho::array_sort values
  assert_equal "${#values[@]}" "2"
  assert_equal "${values[0]}" "a"
}

@test "dybatpho::array_sort agrees with sort(1) over random input" {
  # The comparison is decided in one place, but the merge that drives it is
  # not, and an off-by-one in a run boundary drops or duplicates elements at
  # sizes the fixed examples above never reach. `sort` is the reference.
  local -a values=() sorted=()
  local index expected actual
  for ((index = 0; index < 137; index++)); do
    values+=("$((RANDOM % 90))")
  done
  expected="$(printf '%s\n' "${values[@]}" | LC_ALL=C sort -n | tr '\n' ' ')"
  sorted=("${values[@]}")
  dybatpho::array_sort sorted --numeric
  actual="$(printf '%s ' "${sorted[@]}")"
  assert_equal "${actual}" "${expected}"

  expected="$(printf '%s\n' "${values[@]}" | LC_ALL=C sort -rn | tr '\n' ' ')"
  sorted=("${values[@]}")
  dybatpho::array_sort sorted --numeric --reverse
  actual="$(printf '%s ' "${sorted[@]}")"
  assert_equal "${actual}" "${expected}"

  expected="$(printf '%s\n' "${values[@]}" | LC_ALL=C sort | tr '\n' ' ')"
  sorted=("${values[@]}")
  LC_ALL=C dybatpho::array_sort sorted
  actual="$(printf '%s ' "${sorted[@]}")"
  assert_equal "${actual}" "${expected}"
}

@test "dybatpho::array_sort keeps equal elements in the order they arrived" {
  # The merge takes from the left run on a tie, which is what makes sorting by
  # one field leave the rest of the order alone.
  local values=(b1 a1 b2 a2 b3 a3)
  # shellcheck disable=2329
  __dybatpho_array_sorts_after() { [[ "${1:0:1}" > "${2:0:1}" ]]; }
  dybatpho::array_sort values
  assert_equal "${values[*]}" "a1 a2 a3 b1 b2 b3"
}

@test "dybatpho::array_sort prints with -- and rejects a bad option or value" {
  local fruit=(b a)
  run -0 dybatpho::array_sort fruit --
  assert_line --index 0 "a"
  assert_line --index 1 "b"
  run --separate-stderr ! dybatpho::array_sort fruit --nope
  assert_stderr --partial "Unknown option '--nope'"
  local mixed=(1 x)
  run --separate-stderr ! dybatpho::array_sort mixed --numeric
  assert_stderr --partial "is not an integer"
}

@test "dybatpho::array_sort does not shadow a caller array named like its locals" {
  # A nameref resolves in the caller's scope, so a plainly named local inside
  # would hide the caller's array and the function would sort its own copy.
  local values=(c a b)
  dybatpho::array_sort values
  assert_equal "${values[*]}" "a b c"
  local result=(3 1 2)
  dybatpho::array_sort result --numeric
  assert_equal "${result[*]}" "1 2 3"
  local seen=(y x)
  dybatpho::array_sort seen
  assert_equal "${seen[*]}" "x y"
}

@test "dybatpho::array_slice keeps a run and counts back from the end" {
  local items=(a b c d e)
  dybatpho::array_slice items 1 3
  assert_equal "${items[*]}" "b c d"
  items=(a b c d e)
  dybatpho::array_slice items -2
  assert_equal "${items[*]}" "d e"
  items=(a b c d e)
  dybatpho::array_slice items 2
  assert_equal "${items[*]}" "c d e"
}

@test "dybatpho::array_slice leaves an empty array when the run is not there" {
  local items=(a b c d e)
  dybatpho::array_slice items 10
  assert_equal "${#items[@]}" "0"
  items=(a b c)
  dybatpho::array_slice items 0 0
  assert_equal "${#items[@]}" "0"
  # A start further back than the array is long clamps to its beginning.
  items=(a b c)
  dybatpho::array_slice items -99
  assert_equal "${items[*]}" "a b c"
  items=(a b c)
  dybatpho::array_slice items 1 99
  assert_equal "${items[*]}" "b c"
}

@test "dybatpho::array_slice prints with -- in either argument position" {
  local items=(a b c)
  run -0 dybatpho::array_slice items 1 --
  assert_line --index 0 "b"
  items=(a b c)
  run -0 dybatpho::array_slice items 0 2 --
  assert_line --index 1 "b"
  run --separate-stderr ! dybatpho::array_slice items xx
  assert_stderr --partial "is not a whole number"
}

@test "dybatpho::array_union merges two arrays as a set" {
  local allowed=(read write read)
  local extra=(write admin)
  dybatpho::array_union allowed extra
  assert_equal "${allowed[*]}" "read write admin"
  local empty=()
  dybatpho::array_union allowed empty
  assert_equal "${allowed[*]}" "read write admin"
  local fresh=()
  dybatpho::array_union fresh extra
  assert_equal "${fresh[*]}" "write admin"
}

@test "dybatpho::array_intersect keeps what both arrays hold" {
  local requested=(read write admin)
  local granted=(write read)
  dybatpho::array_intersect requested granted
  assert_equal "${requested[*]}" "read write"
  local disjoint=(x y)
  dybatpho::array_intersect disjoint granted
  assert_equal "${#disjoint[@]}" "0"
}

@test "dybatpho::array_difference subtracts one array from another" {
  local wanted=(read write admin)
  local granted=(write)
  dybatpho::array_difference wanted granted
  assert_equal "${wanted[*]}" "read admin"
  # One-sided: a value only the second array holds is not added.
  local left=(a)
  local right=(b)
  dybatpho::array_difference left right
  assert_equal "${left[*]}" "a"
  local same=(a b)
  local other=(a b)
  dybatpho::array_difference same other
  assert_equal "${#same[@]}" "0"
}

@test "the set operations print with -- and keep the first array's order" {
  local first=(c a)
  local second=(b)
  run_traced -0 dybatpho::array_union first second --
  assert_line --index 0 "c"
  assert_line --index 1 "a"
  assert_line --index 2 "b"
}

@test "dybatpho::array_toposort puts a dependency before what needs it" {
  declare -A deps=([cli]="config validate" [config]="validate" [validate]="")
  local -a order=()
  run_traced -0 dybatpho::array_toposort deps order

  dybatpho::array_toposort deps order
  assert_equal "${order[*]}" "validate config cli"
}

@test "dybatpho::array_toposort orders only what the given roots reach" {
  declare -A graph=([a]="b c" [b]="d" [c]="d" [d]="" [z]="y" [y]="")
  local -a reached=()
  dybatpho::array_toposort graph reached a
  assert_equal "${reached[*]}" "d b c a"
}

@test "dybatpho::array_toposort gives the same order every run" {
  # Bash hashes the keys of an associative array in no useful order, so a
  # loader built on an unsorted walk would shuffle occasionally -- and be
  # wrong only occasionally, which is the worst way to be wrong.
  declare -A graph=([a]="b c" [b]="d" [c]="d" [d]="" [z]="y" [y]="")
  local -a first=() second=()
  dybatpho::array_toposort graph first
  dybatpho::array_toposort graph second
  assert_equal "${first[*]}" "${second[*]}"
  assert_equal "${first[*]}" "d b c a y z"
}

@test "dybatpho::array_toposort includes an entry named only as a dependency" {
  # A leaf has no entry of its own, and leaving it out would hand back an
  # order missing the thing that has to come first.
  declare -A deps=([app]="libfoo")
  local -a order=()
  dybatpho::array_toposort deps order
  assert_equal "${order[*]}" "libfoo app"
}

@test "dybatpho::array_toposort reports a cycle and still returns an order" {
  # A cycle is legitimate in some graphs: `init.sh` has `text` and `table`
  # depend on each other on purpose, because the calls resolve at run time.
  # Refusing to order such a graph would be refusing to load the library.
  declare -A cyclic=([a]="b" [b]="c" [c]="a")
  local -a order=()
  run_traced -1 dybatpho::array_toposort cyclic order

  dybatpho::array_toposort cyclic order || true
  assert_equal "${#order[@]}" "3"
}

@test "dybatpho::array_toposort orders the library's own module graph" {
  # The real graph, not a fixture: every edge that is not part of a cycle
  # must put the dependency first, or the loader would source a module before
  # something it calls.
  declare -A graph=()
  local key
  for key in "${!__dybatpho_module_deps[@]}"; do
    graph["${key}"]="${__dybatpho_module_deps[${key}]}"
  done

  local -a order=()
  # `text` and `table` form a deliberate cycle, so a cycle is expected here.
  dybatpho::array_toposort graph order || true

  local -A position=()
  local at
  for at in "${!order[@]}"; do
    position["${order[${at}]}"]="${at}"
  done

  local dependency violations=""
  for key in "${!graph[@]}"; do
    for dependency in ${graph[${key}]}; do
      ((position[${dependency}] < position[${key}])) && continue
      # An edge whose other end names this one back is part of a cycle, and
      # one of the two has to come second.
      [[ " ${graph[${dependency}]-} " == *" ${key} "* ]] && continue
      violations+="${dependency} must come before ${key}"$'\n'
    done
  done
  [ -z "${violations}" ] || fail "${violations}"
}

@test "dybatpho::array_toposort handles an empty graph" {
  declare -A empty=()
  local -a order=()
  run_traced -0 dybatpho::array_toposort empty order

  dybatpho::array_toposort empty order
  assert_equal "${#order[@]}" "0"
}

@test "dybatpho::array_closure collects everything the roots reach" {
  declare -A graph=([a]="b c" [b]="d" [c]="d" [d]="" [z]="y")
  local -a needed=()
  run_traced -0 dybatpho::array_closure graph needed a

  dybatpho::array_closure graph needed a
  assert_equal "${needed[*]}" "a b c d"

  # Sorted, so it reads as a set; the ordering question is answered by
  # `dybatpho::array_toposort`.
  dybatpho::array_closure graph needed z
  assert_equal "${needed[*]}" "y z"
}

@test "dybatpho::array_closure walks a cycle without looping forever" {
  declare -A cyclic=([a]="b" [b]="a")
  local -a needed=()
  dybatpho::array_closure cyclic needed a
  assert_equal "${needed[*]}" "a b"
}

@test "dybatpho::array_closure needs a root, and a bindable name" {
  local -a needed=()
  declare -A graph=([a]="b")

  run --separate-stderr dybatpho::array_closure graph needed
  assert_failure
  assert_stderr --partial "Expected at least one root"

  run --separate-stderr dybatpho::array_closure graph __dybatpho_needed a
  assert_failure
  assert_stderr --partial "is reserved"
}
