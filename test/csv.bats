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
  assert_output << EOF
a
b
EOF
}

@test "dybatpho::csv_read refuses input holding the separator it joins fields with" {
  run --separate-stderr dybatpho::csv_read "$(printf 'a\nx\037y')" records
  assert_failure
  assert_stderr --partial "unit separator"
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
  assert_output << EOF
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
  assert_output << EOF
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
  assert_output << EOF
3
10
7
EOF
}

@test "dybatpho::csv_col reads a short row as an empty value" {
  run_traced dybatpho::csv_col "$(printf 'a,b\n1\n2,3')" "b"
  assert_success
  assert_output << EOF

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
  assert_output << EOF
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
  assert_output << EOF
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
  assert_output << EOF
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
  assert_output << EOF
a
1
EOF

  local script="${BATS_TEST_TMPDIR}/from_stdin.sh"
  printf '%s\n' "printf '[{\"a\":\"1\"}]' | { . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules csv && dybatpho::csv_from_json -; }" > "${script}"
  run_traced bash "${script}"
  assert_success
  assert_line --index 1 "1"
}

@test "dybatpho::csv_from_json writes the same CSV when only yq is installed" {
  # The two backends quote differently on their own, so the conversion is read
  # back and written out by this module either way. Nothing proved the yq half
  # of that: `jq` is installed here, so the other branch always won.
  command -v yq > /dev/null || skip "yq is not installed"

  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/yq_only.sh"
  cat > "${script}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules csv
# \`dybatpho::coalesce_cmd\` asks \`command -v\`, so jq has to be missing from
# the path; shadowing the name is not enough.
command -v jq > /dev/null && exit 3
dybatpho::csv_from_json '[{"name":"Doe, John","note":"line one\nline two","qty":"3"},{"name":"x","note":"ok","qty":"10"}]'
SCRIPT

  PATH="$(path_without jq)" run_traced bash "${script}"
  assert_success
  assert_output << EOF
name,note,qty
"Doe, John","line one
line two",3
x,ok,10
EOF
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
  assert_output << EOF
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
  assert_output << EOF
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
  assert_output << 'EOF'
qty,name
3,"Doe, John"
10,"He said ""hi"""
7,plain
EOF
}

@test "dybatpho::csv_select takes positions, repeats a column and pads a short row" {
  run_traced dybatpho::csv_select "$(printf 'a,b,c\n1,2,3\n4,5')" 3 1 a
  assert_success
  assert_output << 'EOF'
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
  assert_output << 'EOF'
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
  assert_output << 'EOF'
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
  assert_output << 'EOF'
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
  assert_output << 'EOF'
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
  assert_output << 'EOF'
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
