#!/usr/bin/env bash
set -euo pipefail
runtime=$(cd "${1:?Runtime required}" && pwd)
port=${2:-8765}
[[ $(cat "$runtime/.demo-only") == LG_ANDROID_DEMO ]] || exit 2
[[ $port =~ ^[0-9]+$ ]] && ((port > 1024 && port < 65536)) || exit 2
code_dir=$(cd "$(dirname "$0")" && pwd)
# Android emulator 10.0.2.2 (or an adb reverse tunnel) reaches this host loopback listener.
export LG_DEMO_RUNTIME="$runtime"
export PHP_CLI_SERVER_WORKERS=${PHP_CLI_SERVER_WORKERS:-4}
exec php -d session.save_path="$runtime/sessions" -d upload_max_filesize=50M -d post_max_size=52M -d max_execution_time=180 -d expose_php=0 -S "127.0.0.1:$port" -t "$runtime/mtt" "$code_dir/router.php"
