setup() {
  load test_helper
}

@test "dybatpho::trim output string" {
  run dybatpho::trim "	Hello,   dybatpho   "
  assert_success
  assert_output "Hello,   dybatpho"
}

@test "dybatpho::trim with empty string" {
  run dybatpho::trim ""
  assert_success
  assert_output ""
}

@test "dybatpho::trim with only spaces" {
  run dybatpho::trim "   "
  assert_success
  assert_output ""
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

@test "dybatpho::split with empty delimiter" {
  run dybatpho::split "hello" ""
  assert_success
  assert_output "hello"
}

@test "dybatpho::split with empty string" {
  run dybatpho::split "" ","
  assert_success
  assert_output ""
}

@test "dybatpho::url_encode output string" {
  run dybatpho::url_encode "https://github.com/dynamotn/dybatpho/?f=This is sample string"
  assert_success
  assert_output "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
}

@test "dybatpho::url_encode with special characters" {
  run dybatpho::url_encode "hello world!@#$%^&*()"
  assert_success
  assert_output "hello%20world%21%40%23%24%25%5E%26%2A%28%29"
}

@test "dybatpho::url_decode output string" {
  run dybatpho::url_decode "https%3A%2F%2Fgithub.com%2Fdynamotn%2Fdybatpho%2F%3Ff%3DThis%20is%20sample%20string"
  assert_success
  assert_output "https://github.com/dynamotn/dybatpho/?f=This is sample string"
}

@test "dybatpho::url_decode with plus sign" {
  run dybatpho::url_decode "hello+world"
  assert_success
  assert_output "hello world"
}

@test "dybatpho::lower output string" {
  run dybatpho::lower "dYbaTPHO"
  assert_success
  assert_output "dybatpho"
}

@test "dybatpho::lower with empty string" {
  run dybatpho::lower ""
  assert_success
  assert_output ""
}

@test "dybatpho::upper output string" {
  run dybatpho::upper "dYbaTPHO"
  assert_success
  assert_output "DYBATPHO"
}

@test "dybatpho::upper with empty string" {
  run dybatpho::upper ""
  assert_success
  assert_output ""
}
