setup() {
  load test_helper
}

@test "dybatpho::goos linux" {
  stub uname ": echo 'Linux'" ": echo 'GNU/Linux'"
  assert_equal "$(dybatpho::goos)" "linux"
  unstub uname
}

@test "dybatpho::goos android" {
  stub uname ": echo 'Linux'" ": echo 'Android'"
  assert_equal "$(dybatpho::goos)" "android"
  unstub uname
}

@test "dybatpho::goos cygwin" {
  stub uname ": echo 'CYGWIN_NT-6.1-WOW64'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos mingw" {
  stub uname ": echo 'MINGW64_NT-10.0-22631'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos msys" {
  stub uname ": echo 'MSYS_NT-6.1'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos macos" {
  stub uname ": echo 'Darwin'"
  assert_equal "$(dybatpho::goos)" "darwin"
  unstub uname
}

@test "dybatpho::platform aliases normalized operating system" {
  stub uname ": echo 'Darwin'"
  assert_equal "$(dybatpho::platform)" "darwin"
  unstub uname
}

@test "dybatpho::command_path returns the first available command" {
  assert_equal "$(dybatpho::command_path command-that-does-not-exist sh)" "$(command -v sh)"
}

@test "dybatpho::command_path fails without arguments or matches" {
  run ! dybatpho::command_path
  run ! dybatpho::command_path command-that-does-not-exist another-missing-command
}

@test "dybatpho::is_linux detects a Linux platform" {
  stub_repeated uname ": echo 'Linux'"
  dybatpho::is_linux
  run ! dybatpho::is_macos
}

@test "dybatpho::is_macos detects a macOS platform" {
  stub_repeated uname ": echo 'Darwin'"
  dybatpho::is_macos
  run ! dybatpho::is_linux
}

@test "dybatpho::goarch arm64" {
  stub uname ": echo 'aarch64'"
  assert_equal "$(dybatpho::goarch)" "arm64"
  unstub uname
}

@test "dybatpho::goarch armv7" {
  stub uname ": echo 'armv7'"
  assert_equal "$(dybatpho::goarch)" "arm"
  unstub uname
}

@test "dybatpho::goarch i386" {
  stub uname ": echo 'i386'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch i686" {
  stub uname ": echo 'i686'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch x86" {
  stub uname ": echo 'x86'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch i86pc" {
  stub uname ": echo 'i86pc'"
  assert_equal "$(dybatpho::goarch)" "amd64"
  unstub uname
}

@test "dybatpho::goarch x86_64" {
  stub uname ": echo 'x86_64'"
  assert_equal "$(dybatpho::goarch)" "amd64"
  unstub uname
}

@test "dybatpho::goarch mips64" {
  stub uname ": echo 'mips64'"
  assert_equal "$(dybatpho::goarch)" "mips64"
  unstub uname
}

@test "dybatpho::goarch unknown arch falls back to uname" {
  stub uname ": echo 'riscv64'"
  assert_equal "$(dybatpho::goarch)" "riscv64"
  unstub uname
}
