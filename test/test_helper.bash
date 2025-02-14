DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
. "${DYBATPHO_DIR}/init"

bats_require_minimum_version 1.5.0
