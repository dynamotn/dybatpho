setup() {
  source "${DYBATPHO_DIR}/test/lib/support/load.bash"
  source "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  source "${DYBATPHO_DIR}/init.sh"
}

@test "_trim output string" {
  run _trim "	Hello,   dybatpho   "
  assert_success
  assert_output "Hello,   dybatpho"
}

@test "_split output string" {
  run _split "apples,oranges,pears,grapes" ","
  assert_success
  assert_output << EOF
apples
oranges
pears
grapes
EOF
  run _split "hello---world---my---name---is---dynamo" ","
  assert_success
  assert_output << EOF
hello
world
my
name
is
dynamo
EOF
}

@test "_url_encode output string" {
  run _url_encode "https://github.com/dynamotn/dybatpho/?f=This is sample string"
  assert_success
  assert_output "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
}

@test "_url_decode output string" {
  run _url_decode "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
  assert_success
  assert_output "https://github.com/dynamotn/dybatpho/?f=This is sample string"
}

@test "_lower output string" {
  run _lower "dYbaTPHO"
  assert_success
  assert_output "dybatpho"
}

@test "_upper output string" {
  run _upper "dYbaTPHO"
  assert_success
  assert_output "DYBATPHO"
}

@test "_reverse output string" {
  run _reverse "dYbaTPHO"
  assert_success
  assert_output "DyBAtpho"
}
