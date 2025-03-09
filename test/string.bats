setup() {
  load test_helper
}

@test "dybatpho::trim output string" {
  run dybatpho::trim "	Hello,   dybatpho   "
  assert_success
  assert_output "Hello,   dybatpho"
}

@test "dybatpho::split output string" {
  run dybatpho::split "apples,oranges,pears,grapes" ","
  assert_success
  assert_output << EOF
apples
oranges
pears
grapes
EOF
  run dybatpho::split "hello---world---my---name---is---dynamo" ","
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

@test "dybatpho::url_encode output string" {
  run dybatpho::url_encode "https://github.com/dynamotn/dybatpho/?f=This is sample string"
  assert_success
  assert_output "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
}

@test "dybatpho::url_decode output string" {
  run dybatpho::url_decode "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
  assert_success
  assert_output "https://github.com/dynamotn/dybatpho/?f=This is sample string"
}

@test "dybatpho::lower output string" {
  run dybatpho::lower "dYbaTPHO"
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::upper output string" {
  run dybatpho::upper "dYbaTPHO"
  assert_success
  assert_output "DYBATPHO"
}

@test "dybatpho::reverse output string" {
  run dybatpho::reverse "dYbaTPHO"
  assert_success
  assert_output "DyBAtpho"
}
