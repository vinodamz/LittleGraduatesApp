#!/usr/bin/env bash
# Fresh, secret-free MTT runtime for Android demonstrations. Never uses a supplied DB.
set -euo pipefail
if [[ $# != 2 ]]; then echo "Usage: bash tools/demo_backend/setup.sh MTT_CHECKOUT NEW_RUNTIME_DIR" >&2; exit 2; fi
code_dir=$(cd "$(dirname "$0")" && pwd)
source_dir=$(cd "$1" && pwd)
runtime=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$2")
[[ ! -e "$runtime" ]] || { echo 'Refusing to reuse an existing runtime directory.' >&2; exit 2; }
python3 -c 'import shutil,sys,pathlib; free=shutil.disk_usage(pathlib.Path(sys.argv[1]).parent).free; sys.exit(0 if free >= 256*1024*1024 else "Need at least 256 MiB free for isolated MariaDB")' "$runtime"
[[ ${#runtime} -lt 85 ]] || { echo 'Use a shorter runtime path for the MariaDB socket.' >&2; exit 2; }
for tool in php python3 git tar; do command -v "$tool" >/dev/null; done
mariadb_bin=${MARIADB_BIN:-mariadb}
server_bin=${MARIADBD_BIN:-mariadbd}
install_bin=${MARIADB_INSTALL_DB_BIN:-mariadb-install-db}
admin_bin=${MARIADB_ADMIN_BIN:-mariadb-admin}
for tool in "$mariadb_bin" "$server_bin" "$install_bin" "$admin_bin"; do command -v "$tool" >/dev/null; done
php -r 'foreach (["pdo_mysql", "mbstring", "fileinfo", "gd"] as $e) if (!extension_loaded($e)) {fwrite(STDERR,"Missing PHP extension: $e\n");exit(1);}'
source_commit=$(git -C "$source_dir" rev-parse HEAD)
mkdir -m 700 "$runtime"
printf 'LG_ANDROID_DEMO\n' > "$runtime/.demo-only"
mkdir "$runtime/mtt" "$runtime/db" "$runtime/sessions"
# Archive committed code only: never copy a developer's config, uploads or database.
git -C "$source_dir" archive HEAD api includes sql migrate.php | tar -x -C "$runtime/mtt" --exclude='includes/config.php' --exclude='sql/odoo_dump'
printf '%s\n' "$source_commit" > "$runtime/mtt-commit.txt"
base_args=()
if [[ -n ${DEMO_MARIADB_BASEDIR:-} ]]; then base_args+=(--basedir="$DEMO_MARIADB_BASEDIR"); fi
"$install_bin" --no-defaults "${base_args[@]}" --datadir="$runtime/db" --auth-root-authentication-method=normal --skip-test-db --innodb-log-file-size=16M --innodb-buffer-pool-size=64M > "$runtime/db-init.log" 2>&1
# A separate session keeps the socket DB alive after this setup shell/CI step exits.
server_pid=$(python3 - "$runtime/db-stdout.log" "$server_bin" --no-defaults "${base_args[@]}" --datadir="$runtime/db" --socket="$runtime/db.sock" --pid-file="$runtime/db.pid" --skip-networking --user="$(id -un)" --innodb-buffer-pool-size=64M --innodb-log-file-size=16M --log-error="$runtime/db.log" <<'PY_LAUNCH'
import subprocess, sys
with open(sys.argv[1], 'ab') as log:
    process = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
print(process.pid)
PY_LAUNCH
)
setup_ready=0
cleanup_failed() { if [[ $setup_ready != 1 ]]; then kill "$server_pid" 2>/dev/null || true; fi; }
trap cleanup_failed EXIT
ready=0
for attempt in {1..100}; do
  if "$admin_bin" --no-defaults --socket="$runtime/db.sock" -u root ping >/dev/null 2>&1; then ready=1; break; fi
  kill -0 "$server_pid" 2>/dev/null || { cat "$runtime/db.log" >&2; exit 1; }
  sleep 0.2
done
[[ $ready == 1 ]] || { echo 'Demo database did not start.' >&2; exit 1; }
"$mariadb_bin" --no-defaults --socket="$runtime/db.sock" -u root -e 'CREATE DATABASE lg_android_demo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
php "$code_dir/configure.php" "$runtime"
"$mariadb_bin" --no-defaults --socket="$runtime/db.sock" -u root lg_android_demo < "$runtime/mtt/sql/schema.sql"
php "$runtime/mtt/migrate.php" > "$runtime/migrations.log" 2>&1
# The upstream migrator historically returned zero for a connection diagnostic failure.
if grep -qE 'DIAGNOSTIC ERROR|Done WITH FAILURES|FAILED:' "$runtime/migrations.log"; then cat "$runtime/migrations.log" >&2; exit 1; fi
php "$code_dir/seed.php" "$runtime"
python3 "$code_dir/make_media.py" "$runtime/demo-material.png"
python3 - "$runtime" "${DEMO_UPLOAD_DELAY_SECONDS:-20}" <<'PY'
from pathlib import Path
import sys
value=int(sys.argv[2])
if not 0 <= value <= 120: raise SystemExit('Delay must be 0..120 seconds')
Path(sys.argv[1], 'upload-delay-seconds').write_text(str(value)+'\n')
PY
setup_ready=1
trap - EXIT
printf 'Ready: %s\nMTT commit: %s\n' "$runtime" "$source_commit"
printf 'Next: bash %s/serve.sh %s 8765\n' "$code_dir" "$runtime"
