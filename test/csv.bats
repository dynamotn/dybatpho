setup() {
  load test_helper
  QUOTED_CSV="$(printf 'name,note,qty\n"Doe, John",ok,3\n"He said ""hi""","line one\nline two",10\nplain,x,7')"
}

@test "dybatpho::csv_read keeps a delimiter inside a quoted field in one field" {
  # This is the case `dybatpho::table_csv` refuses: splitting on every comma
  # turns one value into two columns and nothing says so.
  run_traced dybatpho::csv_read "$(printf 'name,note\n"Doe, John",ok')" rows
  assert_success

  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'name,note\n"Doe, John",ok')" records
  [ "${#records[@]}" -eq 2 ]
  dybatpho::csv_fields "${records[1]}" fields
  [ "${#fields[@]}" -eq 2 ]
  [ "${fields[0]}" = "Doe, John" ]
  [ "${fields[1]}" = "ok" ]
}

@test "dybatpho::csv_read reads a doubled quote as one literal quote" {
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'a\n"He said ""hi"""')" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[0]}" = 'He said "hi"' ]
}

@test "dybatpho::csv_read keeps a line break inside a quoted field in one record" {
  local -a records=() fields=()
  dybatpho::csv_read "${QUOTED_CSV}" records
  [ "${#records[@]}" -eq 4 ]
  dybatpho::csv_fields "${records[2]}" fields
  [ "${fields[1]}" = "$(printf 'line one\nline two')" ]
}

@test "dybatpho::csv_read leaves a quote that is not a field boundary alone" {
  # `5" pipe` is data, not CSV quoting.
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'size,note\n5" pipe,ok')" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[0]}" = '5" pipe' ]
  [ "${fields[1]}" = "ok" ]
}

@test "dybatpho::csv_read keeps stray text after a closing quote in that one field" {
  # `"a"x` is not valid CSV, but it is one field. At the end of a record the
  # stray text used to come back a second time as a field of its own.
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'a,b\n1,"two"x\n"one"x,2\n"one"x,')" records
  [ "${#records[@]}" -eq 4 ]

  dybatpho::csv_fields "${records[1]}" fields
  [ "${#fields[@]}" -eq 2 ]
  [ "${fields[1]}" = "twox" ]

  dybatpho::csv_fields "${records[2]}" fields
  [ "${#fields[@]}" -eq 2 ]
  [ "${fields[0]}" = "onex" ]
  [ "${fields[1]}" = "2" ]

  dybatpho::csv_fields "${records[3]}" fields
  [ "${#fields[@]}" -eq 2 ]
  [ "${fields[0]}" = "onex" ]
  [ "${fields[1]}" = "" ]

  run_traced dybatpho::csv_col "$(printf 'a,b\n1,"two"x')" b
  assert_success
  assert_output "twox"
}

@test "dybatpho::csv_read handles empty fields, a trailing delimiter and an empty input" {
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'a,b,c\n1,,')" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${#fields[@]}" -eq 3 ]
  [ "${fields[1]}" = "" ]
  [ "${fields[2]}" = "" ]

  dybatpho::csv_read "" records
  [ "${#records[@]}" -eq 0 ]
}

@test "dybatpho::csv_read reads a file, stdin, and strips a CRLF line ending" {
  local file="${BATS_TEST_TMPDIR}/in.csv"
  printf 'name,qty\r\napi,3\r\n' > "${file}"

  local -a records=() fields=()
  dybatpho::csv_read "${file}" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[1]}" = "3" ]

  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/stdin.sh"
  printf '%s\n' "printf 'a,b\nx,y\n' | { . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules csv && dybatpho::csv_header -; }" > "${script}"
  run_traced bash "${script}"
  assert_success
  assert_output - << EOF
a
b
EOF
}

@test "the csv readers and writer use an array whatever the caller named it" {
  # Each of these reads or fills the array through the name the caller chose,
  # so a name shared with one of the function's own locals lost the records.
  local name
  for name in input target text delimiter record source; do
    unset "${name}"
    local -a "${name}=()"
    dybatpho::csv_read $'a,b\n1,2' "${name}"
    local -n records="${name}"
    assert_equal "${#records[@]}" 2
    assert_equal "$(dybatpho::csv_write "${name}")" $'a,b\n1,2'
    dybatpho::csv_fields $'1\037x,y\0373' "${name}"
    assert_equal "${records[1]}" "x,y"
    unset -n records
  done
}

@test "dybatpho::csv_read refuses input holding the separator it joins fields with" {
  run --separate-stderr dybatpho::csv_read "$(printf 'a\nx\037y')" records
  assert_failure
  assert_stderr --partial "unit separator"
}

@test "a refused unit separator is reported under the function that was called" {
  # The refusal named the function one frame too far up -- whatever called the
  # public function -- so the message pointed away from the call at fault.
  run --separate-stderr dybatpho::csv_read "$(printf 'a\nx\037y')" records
  assert_failure
  assert_stderr --partial "dybatpho::csv_read: The input contains the ASCII unit separator"

  run --separate-stderr dybatpho::csv_col "$(printf 'a\nx\037y')" a
  assert_failure
  assert_stderr --partial "dybatpho::csv_col: The input contains the ASCII unit separator"
}

@test "dybatpho::csv_read refuses a variable name that belongs to the library" {
  run --separate-stderr dybatpho::csv_read "a" __dybatpho_rows
  assert_failure
  assert_stderr --partial "is reserved"
}

@test "dybatpho::csv_fields splits a record back into its values" {
  local -a fields=()
  run_traced dybatpho::csv_fields "$(printf 'a\037b\037c')" fields
  assert_success

  dybatpho::csv_fields "$(printf 'a\037b\037c')" fields
  [ "${#fields[@]}" -eq 3 ]
  [ "${fields[2]}" = "c" ]

  dybatpho::csv_fields "" fields
  [ "${#fields[@]}" -eq 1 ]
  [ "${fields[0]}" = "" ]
}

@test "dybatpho::csv_write quotes only the fields that need it" {
  local -a records=()
  dybatpho::csv_read "${QUOTED_CSV}" records
  run_traced dybatpho::csv_write records
  assert_success
  assert_output - << EOF
name,note,qty
"Doe, John",ok,3
"He said ""hi""","line one
line two",10
plain,x,7
EOF
}

@test "dybatpho::csv_write round-trips a value that contains a carriage return" {
  local -a records=() fields=()
  local record
  record="$(printf 'a\037one\rtwo')"
  records=("$(printf 'k\037v')" "${record}")

  local text
  text="$(dybatpho::csv_write records)"
  [[ "${text}" == *'"one'$'\r''two"'* ]] || {
    printf 'a carriage return was not quoted: %q\n' "${text}" >&2
    return 1
  }

  local -a again=()
  dybatpho::csv_read "${text}" again
  dybatpho::csv_fields "${again[1]}" fields
  [ "${fields[1]}" = "$(printf 'one\rtwo')" ]
}

@test "dybatpho::csv_header prints the column names and says nothing for empty input" {
  run_traced dybatpho::csv_header "${QUOTED_CSV}"
  assert_success
  assert_output - << EOF
name
note
qty
EOF

  run_traced dybatpho::csv_header ""
  assert_success
  assert_output ""
}

@test "dybatpho::csv_col prints one column chosen by name" {
  run_traced dybatpho::csv_col "${QUOTED_CSV}" "qty"
  assert_success
  assert_output - << EOF
3
10
7
EOF
}

@test "dybatpho::csv_col reads a short row as an empty value" {
  run_traced dybatpho::csv_col "$(printf 'a,b\n1\n2,3')" "b"
  assert_success
  assert_output - << EOF

3
EOF
}

@test "dybatpho::csv_col stops instead of dropping a field from a wider row" {
  run --separate-stderr dybatpho::csv_col "$(printf 'a,b\n1,2,3')" "a"
  assert_failure
  assert_stderr --partial "Row 1 has 3 fields but the header names 2"
}

@test "dybatpho::csv_col names the columns there are when asked for one there is not" {
  run --separate-stderr dybatpho::csv_col "${QUOTED_CSV}" "missing"
  assert_failure
  assert_stderr --partial "No such column: missing"
  assert_stderr --partial "name note qty"
}

@test "dybatpho::csv_col says nothing for an empty input" {
  run_traced dybatpho::csv_col "" "a"
  assert_success
  assert_output ""
}

@test "dybatpho::csv_filter keeps the rows matching eq, ne and contains" {
  run_traced dybatpho::csv_filter "$(printf 'name,env\napi,prod\nweb,dev\ndb,prod')" "env" eq "prod"
  assert_success
  assert_output - << EOF
name,env
api,prod
db,prod
EOF

  run_traced dybatpho::csv_filter "$(printf 'name,env\napi,prod\nweb,dev')" "env" ne "prod"
  assert_success
  assert_line --index 1 "web,dev"

  run_traced dybatpho::csv_filter "$(printf 'name,env\napi,prod\nweb,dev')" "name" contains "e"
  assert_success
  assert_line --index 1 "web,dev"
}

@test "dybatpho::csv_filter compares numbers as numbers and text as text" {
  # `9` sorts after `10` as text, which is the answer a report does not want.
  run_traced dybatpho::csv_filter "$(printf 'name,qty\na,9\nb,10\nc,2')" "qty" gt "5"
  assert_success
  assert_output - << EOF
name,qty
a,9
b,10
EOF

  run_traced dybatpho::csv_filter "$(printf 'name,qty\na,9\nb,10\nc,2')" "qty" lt "5"
  assert_success
  assert_line --index 1 "c,2"

  run_traced dybatpho::csv_filter "$(printf 'name,tag\na,alpha\nb,zulu')" "tag" gt "m"
  assert_success
  assert_line --index 1 "b,zulu"

  run_traced dybatpho::csv_filter "$(printf 'name,tag\na,alpha\nb,zulu')" "tag" lt "m"
  assert_success
  assert_line --index 1 "a,alpha"
}

@test "dybatpho::csv_filter rejects an operator it does not have" {
  run --separate-stderr dybatpho::csv_filter "a,b" "a" "matches" "x"
  assert_failure
  assert_stderr --partial "Unknown operator: matches"
}

@test "dybatpho::csv_filter says nothing for an empty input" {
  run_traced dybatpho::csv_filter "" "a" eq "x"
  assert_success
  assert_output ""
}

@test "dybatpho::csv_to_json builds an array of objects keyed by the header" {
  run_traced dybatpho::csv_to_json "$(printf 'name,qty\n"Doe, John",3')"
  assert_success
  assert_output '[{"name":"Doe, John","qty":"3"}]'
}

@test "dybatpho::csv_to_json escapes a quote and a line break in a value" {
  run_traced dybatpho::csv_to_json "${QUOTED_CSV}"
  assert_success
  assert_output --partial '"name":"He said \"hi\""'
  assert_output --partial '"note":"line one\nline two"'
}

@test "dybatpho::csv_to_json renders an empty input and a header-only input as an empty array" {
  run_traced dybatpho::csv_to_json ""
  assert_success
  assert_output "[]"

  run_traced dybatpho::csv_to_json "a,b"
  assert_success
  assert_output "[]"
}

@test "dybatpho::csv_from_json converts an array of objects back to CSV" {
  run_traced dybatpho::csv_from_json '[{"name":"Doe, John","qty":"3"},{"name":"x","qty":"10"}]'
  assert_success
  assert_output - << EOF
name,qty
"Doe, John",3
x,10
EOF
}

@test "dybatpho::csv_from_json round-trips the values csv_to_json wrote" {
  local json converted
  json="$(dybatpho::csv_to_json "${QUOTED_CSV}")"
  run_traced dybatpho::csv_from_json "${json}"
  assert_success
  assert_output "${QUOTED_CSV}"
}

@test "dybatpho::csv_from_json reads a file and stdin" {
  local file="${BATS_TEST_TMPDIR}/in.json"
  printf '[{"a":"1"}]' > "${file}"
  run_traced dybatpho::csv_from_json "${file}"
  assert_success
  assert_output - << EOF
a
1
EOF

  local script="${BATS_TEST_TMPDIR}/from_stdin.sh"
  printf '%s\n' "printf '[{\"a\":\"1\"}]' | { . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules csv && dybatpho::csv_from_json -; }" > "${script}"
  run_traced bash "${script}"
  assert_success
  assert_line --index 1 "1"
}

@test "dybatpho::csv_from_json needs jq and says so, even with yq installed" {
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/no_jq.sh"
  cat > "${script}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules csv
# \`dybatpho::is command\` asks \`command -v\`, so jq has to be missing from
# the path; shadowing the name is not enough.
command -v jq > /dev/null && exit 3
dybatpho::csv_from_json '[{"name":"x"}]'
SCRIPT

  PATH="$(path_without jq)" run -127 --separate-stderr bash "${script}"
  assert_stderr --partial "dybatpho::csv_from_json: jq is not installed"
}

@test "dybatpho::csv_from_json writes nothing for an empty array" {
  # An empty array is an array of objects with none in it. `jq` used to stop
  # on it, reading the header from a first object that is not there.
  run_traced --separate-stderr dybatpho::csv_from_json '[]'
  assert_success
  assert_output ""
  assert_equal "${stderr}" ""
}

@test "dybatpho::csv_from_json reports a document that is not an array of objects" {
  run --separate-stderr dybatpho::csv_from_json '{"a":1}'
  assert_failure
  assert_stderr --partial "not an array of objects"
}

@test "DYBATPHO_CSV_DELIMITER reads and writes the files that use another delimiter" {
  # `env` cannot run a shell function, so the variable is set for the call.
  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::csv_col "$(printf 'name;note\n"a;b";ok')" "name"
  assert_success
  assert_output "a;b"

  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::csv_filter "$(printf 'name;qty\na;9\nb;2')" "qty" gt "5"
  assert_success
  assert_output - << EOF
name;qty
a;9
EOF
}

@test "DYBATPHO_CSV_DELIMITER=tab reads and writes TSV" {
  local tsv
  tsv="$(printf 'name\tnote\n"a\tb"\tok,fine\nplain\tx')"
  DYBATPHO_CSV_DELIMITER=tab \
    run_traced dybatpho::csv_col "${tsv}" "name"
  assert_success
  assert_output "$(printf 'a\tb\nplain')"

  # `\t` names a tab as well, for the scripts that already write it that way.
  DYBATPHO_CSV_DELIMITER='\t' \
    run_traced dybatpho::csv_filter "${tsv}" "note" contains ","
  assert_success
  assert_output "$(printf 'name\tnote\n"a\tb"\tok,fine')"

  local -a records=() fields=()
  DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_read "${tsv}" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[0]}" = "$(printf 'a\tb')" ]
  [ "${fields[1]}" = "ok,fine" ]
}

@test "DYBATPHO_CSV_DELIMITER refuses a delimiter the parser cannot use" {
  # An empty delimiter used to spin the parser forever; the others are already
  # part of the format and would split a value or a record in the wrong place.
  local bad
  for bad in "" ";;" '"' $'\n' $'\r' $'\037'; do
    DYBATPHO_CSV_DELIMITER="${bad}" \
      run --separate-stderr dybatpho::csv_header "a,b"
    assert_failure
    assert_stderr --partial "dybatpho::csv_header: Invalid delimiter"
  done

  DYBATPHO_CSV_DELIMITER="" \
    run --separate-stderr dybatpho::csv_write records
  assert_failure
  assert_stderr --partial "Invalid delimiter"
}

@test "dybatpho::csv_convert rewrites CSV as TSV and back" {
  run_traced dybatpho::csv_convert "${QUOTED_CSV}" tab
  assert_success
  # The comma no longer needs quotes once a tab separates the fields, while the
  # quote and the line break still do.
  assert_output - << EOF
name	note	qty
Doe, John	ok	3
"He said ""hi"""	"line one
line two"	10
plain	x	7
EOF

  local tsv
  tsv="$(dybatpho::csv_convert "${QUOTED_CSV}" tab)"
  DYBATPHO_CSV_DELIMITER=tab \
    run_traced dybatpho::csv_convert "${tsv}" ","
  assert_success
  assert_output "$(dybatpho::csv_convert "${QUOTED_CSV}" ",")"

  # A tab inside a value is quoted when the output is TSV.
  run_traced dybatpho::csv_convert "$(printf 'a,b\n"x\ty",z')" tab
  assert_success
  assert_output "$(printf 'a\tb\n"x\ty"\tz')"
}

@test "dybatpho::csv_convert reads stdin and refuses an unusable target delimiter" {
  run_traced dybatpho::csv_convert - ";" <<< "$(printf 'a,b\n"c;d",e')"
  assert_success
  assert_output "$(printf 'a;b\n"c;d";e')"

  run --separate-stderr dybatpho::csv_convert "a,b" ";;"
  assert_failure
  assert_stderr --partial "dybatpho::csv_convert: Invalid delimiter"

  run_traced dybatpho::csv_convert "" tab
  assert_success
  assert_output ""
}

@test "dybatpho::csv_select keeps the named columns in the order given" {
  run_traced dybatpho::csv_select "${QUOTED_CSV}" qty name
  assert_success
  assert_output - << 'EOF'
qty,name
3,"Doe, John"
10,"He said ""hi"""
7,plain
EOF
}

@test "dybatpho::csv_select takes positions, repeats a column and pads a short row" {
  run_traced dybatpho::csv_select "$(printf 'a,b,c\n1,2,3\n4,5')" 3 1 a
  assert_success
  assert_output - << 'EOF'
c,a,a
3,1,1
,4,4
EOF

  # A header literally named `2` is reached by name before position.
  run_traced dybatpho::csv_select "$(printf 'x,2\nleft,right')" 2
  assert_success
  assert_output "$(printf '2\nright')"
}

@test "dybatpho::csv_select reads stdin, keeps the delimiter and passes an empty input" {
  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::csv_select - note <<< "$(printf 'name;note\na;"x;y"')"
  assert_success
  assert_output "$(printf 'note\n"x;y"')"

  run_traced dybatpho::csv_select "" name
  assert_success
  assert_output ""
}

@test "dybatpho::csv_select reports a column that is neither a name nor a position" {
  run --separate-stderr dybatpho::csv_select "$(printf 'a,b\n1,2')" 3
  assert_failure
  assert_stderr --partial "No such column: 3. The header has 2 columns: a b"

  run --separate-stderr dybatpho::csv_select "$(printf 'a,b\n1,2')" 0
  assert_failure
  assert_stderr --partial "No such column: 0"

  run --separate-stderr dybatpho::csv_select "$(printf 'a,b\n1,2')"
  assert_failure
  assert_stderr --partial "Name at least one column"

  run --separate-stderr dybatpho::csv_select "$(printf 'a\n1,2')" a
  assert_failure
  assert_stderr --partial "Row 1 has 2 fields"
}

@test "dybatpho::csv_sort orders numbers by value, keeps ties stable and blanks last" {
  local csv
  csv="$(printf 'n,v\na,10\nb,9\nc,\nd,010.0\ne,-1.5\nf,-0.5\ng,-0.45\nh,-0\ni,.25\nj,-12\nk,+3')"
  run_traced dybatpho::csv_sort "${csv}" v
  assert_success
  assert_output - << 'EOF'
n,v
j,-12
e,-1.5
f,-0.5
g,-0.45
h,-0
i,.25
k,+3
b,9
a,10
d,010.0
c,
EOF

  # Descending keeps equal keys in their input order too, and the blank last.
  run_traced dybatpho::csv_sort "${csv}" 2 desc
  assert_success
  assert_line --index 1 "a,10"
  assert_line --index 2 "d,010.0"
  assert_line --index 11 "c,"
}

@test "dybatpho::csv_sort compares text by byte and keeps multi-line values whole" {
  # `auto` falls back to text when any value is not a number.
  run_traced dybatpho::csv_sort "$(printf 'k\n10\nb\n9\nB')" k
  assert_success
  assert_output "$(printf 'k\n10\n9\nB\nb')"

  # `text` forces it even on a column of numbers.
  run_traced dybatpho::csv_sort "$(printf 'k\n10\n9\n100')" k asc text
  assert_success
  assert_output "$(printf 'k\n10\n100\n9')"

  run_traced dybatpho::csv_sort "${QUOTED_CSV}" name desc
  assert_success
  assert_output - << 'EOF'
name,note,qty
plain,x,7
"He said ""hi""","line one
line two",10
"Doe, John",ok,3
EOF
}

@test "dybatpho::csv_sort reads stdin with a configured delimiter and passes an empty input" {
  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::csv_sort - qty desc number <<< "$(printf 'name;qty\n"a;b";2\nc;30')"
  assert_success
  assert_output "$(printf 'name;qty\nc;30\n"a;b";2')"

  run_traced dybatpho::csv_sort "$(printf 'name,qty')" qty
  assert_success
  assert_output "name,qty"

  run_traced dybatpho::csv_sort "" qty
  assert_success
  assert_output ""
}

@test "dybatpho::csv_sort rejects an unknown order, comparison or value" {
  run --separate-stderr dybatpho::csv_sort "$(printf 'a\n1')" a sideways
  assert_failure
  assert_stderr --partial "Unknown order: sideways"

  run --separate-stderr dybatpho::csv_sort "$(printf 'a\n1')" a asc roman
  assert_failure
  assert_stderr --partial "Unknown comparison: roman"

  run --separate-stderr dybatpho::csv_sort "$(printf 'a\n1\nten')" a asc number
  assert_failure
  assert_stderr --partial "Row 2 has a=ten, which is not a number"

  run --separate-stderr dybatpho::csv_sort "$(printf 'a\n1')" b
  assert_failure
  assert_stderr --partial "No such column: b"
}

@test "dybatpho::csv_join pairs every match in order and drops the repeated key" {
  local left right
  left="$(printf 'svc,team\napi,core\nweb,ui\ndb,\ncache,core\nedge,ops')"
  right="$(printf 'team,owner\ncore,"Doe, J"\ncore,Ann\nui,Bob\n,Nobody')"

  run_traced dybatpho::csv_join "${left}" "${right}" team
  assert_success
  assert_output - << 'EOF'
svc,team,owner
api,core,"Doe, J"
api,core,Ann
web,ui,Bob
cache,core,"Doe, J"
cache,core,Ann
EOF
}

@test "dybatpho::csv_join left keeps every left row and pads what did not match" {
  local left right
  left="$(printf 'svc,team\napi,core\ndb,\nedge')"
  right="$(printf 'name,owner,chan\ncore,Ann,#core\n,Nobody,#x\nops,Eve')"

  # A blank key matches nothing, even a blank key on the other side, and a
  # short left row is padded before the right columns are appended.
  run_traced dybatpho::csv_join "${left}" "${right}" team left name
  assert_success
  assert_output - << 'EOF'
svc,team,owner,chan
api,core,Ann,#core
db,,,
edge,,,
EOF

  # A short right row reads as empty values under its header.
  run_traced dybatpho::csv_join "$(printf 'svc,team\nproxy,ops')" "${right}" team inner name
  assert_success
  assert_output "$(printf 'svc,team,owner,chan\nproxy,ops,Eve,')"
}

@test "dybatpho::csv_join matches keys holding glob, subscript and shell characters" {
  local left right
  left="$(printf 'k,a\n@,1\n*,2\na]b,3\n"x y",4\n$(id),5')"
  right="$(printf 'k,b\n*,S\n@,A\na]b,B\nx y,X\n$(id),D')"
  run_traced dybatpho::csv_join "${left}" "${right}" k
  assert_success
  assert_output - << 'EOF'
k,a,b
@,1,A
*,2,S
a]b,3,B
x y,4,X
$(id),5,D
EOF
}

@test "dybatpho::csv_join reads one side from stdin, keeps the delimiter and handles empty sides" {
  DYBATPHO_CSV_DELIMITER=";" \
    run_traced dybatpho::csv_join - "$(printf 'id;note\n1;"a;b"')" id <<< "$(printf 'id;name\n1;x\n2;y')"
  assert_success
  assert_output "$(printf 'id;name;note\n1;x;"a;b"')"

  run_traced dybatpho::csv_join "" "$(printf 'id,v\n1,2')" id
  assert_success
  assert_output ""

  # An empty right side has no columns to add; a left join keeps the rows.
  run_traced dybatpho::csv_join "$(printf 'id,v\n1,2')" "" id left
  assert_success
  assert_output "$(printf 'id,v\n1,2')"

  run_traced dybatpho::csv_join "$(printf 'id,v\n1,2')" "$(printf 'id\n1')" id
  assert_success
  assert_output "$(printf 'id,v\n1,2')"
}

@test "dybatpho::csv_join rejects an unknown type, a missing key and two stdins" {
  run --separate-stderr dybatpho::csv_join "$(printf 'a\n1')" "$(printf 'a\n1')" a outer
  assert_failure
  assert_stderr --partial "Unknown join type: outer"

  run --separate-stderr dybatpho::csv_join "$(printf 'a\n1')" "$(printf 'b\n1')" a
  assert_failure
  assert_stderr --partial "No such column: a"

  run --separate-stderr dybatpho::csv_join - - a
  assert_failure
  assert_stderr --partial "Only one input can be read from stdin"

  run --separate-stderr dybatpho::csv_join "$(printf 'a\n1')" "$(printf 'a\n1,2')" a
  assert_failure
  assert_stderr --partial "Row 1 has 2 fields"
}

@test "dybatpho::csv_read returns the data a record with no closing quote still has" {
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'a,b\n"unterminated,x')" records
  [ "${#records[@]}" -eq 2 ]
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[0]}" = "unterminated,x" ]
}

@test "dybatpho::csv_read keeps text that follows a closing quote" {
  # `\"a\"x,b` is not valid CSV; dropping the `x` would be the silent loss this
  # module exists to prevent.
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'h1,h2\n"a"x,b')" records
  dybatpho::csv_fields "${records[1]}" fields
  [ "${fields[0]}" = "ax" ]
  [ "${fields[1]}" = "b" ]
}

@test "dybatpho::table_csv points at the csv module when it refuses a quoted field" {
  run --separate-stderr dybatpho::table_csv "$(printf 'name,note\n"Doe, John",ok')" markdown
  assert_failure
  assert_stderr --partial "dybatpho::csv_read"
}

@test "dybatpho::csv_to_json loads the json module on demand when it is not loaded" {
  # `csv` does not load `json` up front, so a script that only reads a
  # spreadsheet does not pay for it; the first conversion loads it. A child shell started from a file, without the functions
  # this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules csv\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' "dybatpho::csv_col \$'name\\nada' name"
    printf '%s\n' "dybatpho::csv_to_json \$'name\\nada'"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line --index 0 "ada"
  assert_line --index 1 '[{"name":"ada"}]'
  refute_output --partial "needs the json module"

  # A script that names it up front gets the same result.
  sed_in_place 's/--modules csv/--modules csv json/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line --index 1 '[{"name":"ada"}]'
}

@test "dybatpho::csv_col, csv_filter and csv_join take a column by position too" {
  local services=$'service,team,cost\napi,core,12\nweb,edge,7\n'
  local owners=$'team,owner\ncore,ann\nedge,bob\n'

  run_traced dybatpho::csv_col "${services}" 3
  assert_success
  assert_output "$(printf '12\n7')"

  run_traced dybatpho::csv_filter "${services}" 2 eq edge
  assert_success
  assert_output "$(printf 'service,team,cost\nweb,edge,7')"

  run_traced dybatpho::csv_join "${services}" "${owners}" 2 inner 1
  assert_success
  assert_output "$(printf 'service,team,cost,owner\napi,core,12,ann\nweb,edge,7,bob')"

  # A header literally named like a position wins over the position.
  run_traced dybatpho::csv_col $'2,1\nx,y\n' 1
  assert_output "y"
}

@test "dybatpho::csv_from_json and csv_convert accept input with no rows" {
  run_traced dybatpho::csv_from_json '[]'
  assert_success
  run_traced dybatpho::csv_convert "" tab
  assert_success
}

@test "dybatpho::csv_sort accepts a header-only table" {
  run_traced dybatpho::csv_sort "n,v" v
  assert_success
  assert_output "n,v"
}

@test "dybatpho::csv_filter orders text in ASCII whatever the locale" {
  local csv
  csv="$(printf 'n\nZed\napple\n')"
  LC_ALL=en_US.UTF-8 run_traced dybatpho::csv_filter "${csv}" n gt "Zed"
  assert_output $'n\napple'
}

@test "dybatpho::csv_read ends a record at a stray quote inside an unquoted field" {
  # Counting every quote took the inch mark in `55"` for an opening quote and
  # swallowed every following line into that one record.
  local -a records=() fields=()
  dybatpho::csv_read "$(printf 'name,size\nTV,55"\nRadio,1\n"a ""b"" c",2')" records
  assert_equal "${#records[@]}" 4
  dybatpho::csv_fields "${records[1]}" fields
  assert_equal "${fields[1]}" '55"'
  dybatpho::csv_fields "${records[2]}" fields
  assert_equal "${fields[0]}" "Radio"
  dybatpho::csv_fields "${records[3]}" fields
  assert_equal "${fields[0]}" 'a "b" c'

  # A quoted field that is still open at the line end continues on the next.
  dybatpho::csv_read "$(printf 'a,b\n"x""\ny",2\n3,4')" records
  assert_equal "${#records[@]}" 3
  dybatpho::csv_fields "${records[1]}" fields
  assert_equal "${fields[0]}" "$(printf 'x"\ny')"
}

@test "dybatpho::csv_from_json keeps false and blanks only null or a missing value" {
  # `.[$key] // ""` treats `false` as missing too.
  run_traced dybatpho::csv_from_json '[{"a":false,"b":0,"c":null,"d":"x"},{"a":true,"b":1}]'
  assert_success
  assert_output - << EOF
a,b,c,d
false,0,,x
true,1,,
EOF
}

@test "dybatpho::csv_from_json writes the same CSV with or without yq installed" {
  local document='[{"name":"Doe, John","note":"line one\nline two","n":null,"f":false}]' with
  with="$(dybatpho::csv_from_json "${document}")"
  PATH="$(path_without yq)" run_traced dybatpho::csv_from_json "${document}"
  assert_success
  assert_output "${with}"
  assert_output - << EOF
name,note,n,f
"Doe, John","line one
line two",,false
EOF
}

@test "dybatpho::csv_to_json escapes every cell without a subshell" {
  # Each cell went through `$(dybatpho::json_string ...)`: two forks a cell.
  run_traced dybatpho::csv_to_json "$(printf 'k,v\na\\b,x\ty\n')"
  assert_success
  assert_output '[{"k":"a\\b","v":"x\ty"}]'
}

# The awk engine has to print, byte for byte, what the Bash engine prints. This
# fixture carries what either could get wrong: quoted delimiters and doubled
# quotes, a line break and a CRLF inside a value, stray text after a closing
# quote, an unclosed quote at the end, Unicode, control bytes that JSON spells
# as `\u00XX`, a backslash, long decimals, signs, leading zeros, a value that
# is not plain decimal, and short rows.
csv_engine_fixture() {
  printf 'name,note,qty,code\r\n'
  printf '"Doe, John","He said ""hi""",10,007\n'
  printf 'plain,"line one\r\nline two",-3.50,+1\n'
  printf '\303\251\346\274\242\360\237\230\200,"tab\tand \\ backslash",99999999999999999999.01,.5\n'
  printf '"5"" pipe",ctl\001\b\f\177,0,-0\n'
  printf '"open"stray,"",7.,1e3\n'
  printf 'x,,,\n'
  printf 'short,1\n'
  printf '10,-99999999999999999999.5,-10,"unclosed\n'
}

# Every operation the awk engine runs, one per line, with its arguments.
csv_engine_ops() {
  cat << 'OPS'
dybatpho::csv_header
dybatpho::csv_col qty
dybatpho::csv_col 4
dybatpho::csv_select code name 2
dybatpho::csv_filter qty gt 5
dybatpho::csv_filter qty lt 0
dybatpho::csv_filter code gt a
dybatpho::csv_filter note contains line
dybatpho::csv_filter name eq plain
dybatpho::csv_filter name ne x
dybatpho::csv_sort qty
dybatpho::csv_sort qty desc number
dybatpho::csv_sort name desc text
dybatpho::csv_sort code
dybatpho::csv_convert tab
dybatpho::csv_to_json
csv_engine_read
OPS
}

csv_engine_read() {
  local -a records=()
  dybatpho::csv_read "$1" records
  printf '%q\n' ${records[@]+"${records[@]}"}
}

# Print every operation's output under the engine named in $1.
csv_engine_run_all() {
  local text op
  text="$(csv_engine_fixture)"
  local -a words=()
  while read -r -a words; do
    printf '== %s\n' "${words[*]}"
    DYBATPHO_CSV_ENGINE="$1" "${words[0]}" "${text}" "${words[@]:1}"
  done < <(csv_engine_ops)
}

@test "DYBATPHO_CSV_ENGINE=awk prints byte for byte what the Bash engine prints" {
  local expected
  expected="$(csv_engine_run_all bash)"
  run_traced csv_engine_run_all awk
  assert_success
  assert_output "${expected}"
}

@test "the csv awk engine agrees with the Bash engine under every awk installed" {
  # gawk, mawk, BusyBox and BSD awk each have their own idea of a number-looking
  # string and of regular expressions; whichever one `awk` names has to agree.
  local expected flavor found=0 bin
  expected="$(csv_engine_run_all bash)"
  for flavor in awk gawk mawk original-awk nawk /usr/bin/awk busybox; do
    command -v "${flavor}" > /dev/null || continue
    if [[ "${flavor}" == "busybox" ]]; then
      busybox awk 'BEGIN { }' 2> /dev/null || continue
    fi
    bin="${BATS_TEST_TMPDIR}/awk-${flavor//\//_}"
    mkdir -p "${bin}"
    if [[ "${flavor}" == "busybox" ]]; then
      printf '#!/bin/sh\nexec busybox awk "$@"\n' > "${bin}/awk"
    else
      printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "${flavor}")" > "${bin}/awk"
    fi
    chmod +x "${bin}/awk"
    PATH="${bin}:${PATH}" run_traced csv_engine_run_all awk
    assert_success
    assert_output "${expected}"
    found=$((found + 1))
  done
  ((found > 0))
}

@test "the csv awk engine hands an input it would refuse to the Bash engine" {
  # A wider row, an unknown column and a non-number under `number` stop the
  # script with the Bash engine's message, whichever engine was asked for.
  local text engine
  text="$(printf 'a,b\n1,2\n3,4,5\n')"
  for engine in bash awk; do
    DYBATPHO_CSV_ENGINE="${engine}" run --separate-stderr dybatpho::csv_to_json "${text}"
    assert_failure
    assert_output ""
    assert_stderr --partial "dybatpho::csv_to_json: Row 2 has 3 fields but the header names 2: 3 4 5"
    DYBATPHO_CSV_ENGINE="${engine}" run --separate-stderr dybatpho::csv_col "a,b" nope
    assert_failure
    assert_stderr --partial "dybatpho::csv_col: No such column: nope."
    DYBATPHO_CSV_ENGINE="${engine}" run --separate-stderr dybatpho::csv_sort "$(printf 'a\nx\n')" a asc number
    assert_failure
    assert_stderr --partial "dybatpho::csv_sort: Row 1 has a=x, which is not a number"
  done
}

@test "DYBATPHO_CSV_ENGINE picks the engine and refuses one it does not know" {
  # `auto` starts awk only for an input large enough to repay the process; a
  # logging stand-in for awk shows which engine ran.
  local bin="${BATS_TEST_TMPDIR}/awk-log" small large
  mkdir -p "${bin}"
  printf '#!/bin/sh\necho run >> "%s/log"\nexec %s "$@"\n' "${bin}" "$(command -v awk)" > "${bin}/awk"
  chmod +x "${bin}/awk"
  small="$(printf 'a,b\n1,2\n')"
  large="$(printf 'a,b\n'; for ((i = 0; i < 400; i++)); do printf '%d,x\n' "${i}"; done)"

  PATH="${bin}:${PATH}" run_traced dybatpho::csv_col "${small}" b
  assert_output "2"
  assert_file_not_exists "${bin}/log"
  PATH="${bin}:${PATH}" DYBATPHO_CSV_ENGINE=awk run_traced dybatpho::csv_col "${small}" b
  assert_output "2"
  assert_file_exists "${bin}/log"
  rm "${bin}/log"
  PATH="${bin}:${PATH}" run_traced dybatpho::csv_col "${large}" a
  assert_line --index 399 "399"
  assert_file_exists "${bin}/log"
  rm "${bin}/log"
  PATH="${bin}:${PATH}" DYBATPHO_CSV_ENGINE=bash run_traced dybatpho::csv_col "${large}" a
  assert_line --index 399 "399"
  assert_file_not_exists "${bin}/log"

  DYBATPHO_CSV_ENGINE=fast run --separate-stderr dybatpho::csv_col "${small}" b
  assert_failure
  assert_stderr --partial "dybatpho::csv_col: Unknown DYBATPHO_CSV_ENGINE: fast. Use auto, awk, or bash"
}

@test "the csv Bash engine runs alone when no awk is installed" {
  local expected
  expected="$(csv_engine_run_all bash)"
  PATH="$(path_without awk)" run_traced csv_engine_run_all awk
  assert_success
  assert_output "${expected}"
}

@test "dybatpho::csv_read through awk keeps a line break and the field joints apart" {
  # The awk engine hands records back one a line, so a line break inside a
  # value and the separator between fields are spelled out and restored.
  local -a records=() fields=()
  DYBATPHO_CSV_ENGINE=awk dybatpho::csv_read "$(printf 'a,b\n"x\ny",\n,\n')" records
  [ "${#records[@]}" -eq 3 ]
  dybatpho::csv_fields "${records[1]}" fields
  [ "${#fields[@]}" -eq 2 ]
  [ "${fields[0]}" = "$(printf 'x\ny')" ]
  [ "${fields[1]}" = "" ]
  dybatpho::csv_fields "${records[2]}" fields
  [ "${#fields[@]}" -eq 2 ]
  run_traced dybatpho::csv_read "$(printf 'a,b\n1,2\n')" records
  assert_success
}

@test "dybatpho::csv_col keeps a value holding invalid UTF-8 under a UTF-8 locale" {
  # Bash's pattern operators dropped such a value whole, so the row came back
  # empty from the Bash engine while the awk engine, reading bytes, kept it.
  local utf8 text engine
  # musl ships no `locale` command and understands `C.UTF-8` without one.
  utf8="C.UTF-8"
  if command -v locale > /dev/null; then
    utf8="$(locale -a 2> /dev/null | grep -iE '^(C|en_US)\.utf-?8$' | head -n 1 || true)"
  fi
  [[ -n "${utf8}" ]] || skip "no UTF-8 locale is installed"
  text="$(printf 'a;b\n\303\\-;x\n')"
  for engine in bash awk; do
    LC_ALL="${utf8}" DYBATPHO_CSV_DELIMITER=";" DYBATPHO_CSV_ENGINE="${engine}" \
      run_traced dybatpho::csv_col "${text}" a
    assert_success
    assert_output "$(printf '\303\\-')"
  done
}
