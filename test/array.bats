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
  assert_equal "$(dybatpho::array_unique "arr" "--")" "5
4
3
2
1"
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
  run ! dybatpho::array_contains "arr" "baz"
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
  run ! dybatpho::array_index_of "arr" "orange"
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
  run dybatpho::array_map "arr" "_explode_on_world"
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
  run ! dybatpho::array_find "arr" "_is_python"
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
  run dybatpho::array_every "arr" "_is_lowercase_word"
  assert_failure

  arr=("Bash" "go")
  dybatpho::array_some "arr" "_is_lowercase_word"

  arr=("Bash" "123")
  run dybatpho::array_some "arr" "_is_lowercase_word"
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
  run dybatpho::array_first "arr"
  assert_failure

  run dybatpho::array_last "arr"
  assert_failure
}

@test "dybatpho::array_join empty array" {
  arr=()
  run_traced dybatpho::array_join "arr" ","
  assert_success
  refute_output
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

  run dybatpho::array_some "arr" "_always_true"
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
  run ! dybatpho::array_some "arr" "_is_long"

  arr=()
  run ! dybatpho::array_some "arr" "_is_long"
}

@test "dybatpho::array_some fails for invalid predicate" {
  arr=("a" "b")
  run --separate-stderr dybatpho::array_some "arr" "not_a_real_function"
  assert_failure
  assert_stderr --partial "Invalid predicate function"
}
