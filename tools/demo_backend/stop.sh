#!/usr/bin/env bash
# Stops only the isolated DB. Keep runtime/logs for diagnosis; no deletion.
set -euo pipefail
runtime=$(cd "${1:?Runtime required}" && pwd)
[[ $(cat "$runtime/.demo-only") == LG_ANDROID_DEMO ]] || exit 2
"${MARIADB_ADMIN_BIN:-mariadb-admin}" --no-defaults --socket="$runtime/db.sock" -u root shutdown
