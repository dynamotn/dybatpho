setup() {
  load test_helper
}

@test "dybatpho::goos linux" {
  stub uname ": echo 'Linux'" ": echo 'GNU/Linux'"
  run dybatpho::goos
  assert_success
  assert_output "linux"
  unstub uname
}

@test "dybatpho::goos android" {
  stub uname ": echo 'Linux'" ": echo 'Android'"
  run dybatpho::goos
  assert_success
  assert_output "android"
  unstub uname
}

@test "dybatpho::goos cygwin" {
  stub uname ": echo 'CYGWIN_NT-6.1-WOW64'"
  run dybatpho::goos
  assert_success
  assert_output "windows"
  unstub uname
}

@test "dybatpho::goos mingw" {
  stub uname ": echo 'MINGW64_NT-10.0-22631'"
  run dybatpho::goos
  assert_success
  assert_output "windows"
  unstub uname
}

@test "dybatpho::goos msys" {
  stub uname ": echo 'MSYS_NT-6.1'"
  run dybatpho::goos
  assert_success
  assert_output "windows"
  unstub uname
}

@test "dybatpho::goos macos" {
  stub uname ": echo 'Darwin'"
  run dybatpho::goos
  assert_success
  assert_output "darwin"
  unstub uname
}

@test "dybatpho::goarch arm64" {
  stub uname ": echo 'aarch64'"
  run dybatpho::goarch
  assert_success
  assert_output "arm64"
  unstub uname
}

@test "dybatpho::goarch armv7" {
  stub uname ": echo 'armv7'"
  run dybatpho::goarch
  assert_success
  assert_output "arm"
  unstub uname
}

@test "dybatpho::goarch i386" {
  stub uname ": echo 'i386'"
  run dybatpho::goarch
  assert_success
  assert_output "386"
  unstub uname
}

@test "dybatpho::goarch i686" {
  stub uname ": echo 'i686'"
  run dybatpho::goarch
  assert_success
  assert_output "386"
  unstub uname
}

@test "dybatpho::goarch x86" {
  stub uname ": echo 'x86'"
  run dybatpho::goarch
  assert_success
  assert_output "386"
  unstub uname
}

@test "dybatpho::goarch i86pc" {
  stub uname ": echo 'i86pc'"
  run dybatpho::goarch
  assert_success
  assert_output "amd64"
  unstub uname
}

@test "dybatpho::goarch x86_64" {
  stub uname ": echo 'x86_64'"
  run dybatpho::goarch
  assert_success
  assert_output "amd64"
  unstub uname
}

@test "dybatpho::goarch mips64" {
  stub uname ": echo 'mips64'"
  run dybatpho::goarch
  assert_success
  assert_output "mips64"
  unstub uname
}
