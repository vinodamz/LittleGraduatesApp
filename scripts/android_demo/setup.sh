#!/usr/bin/env bash
set -euo pipefail
: "${DEMO_OUTPUT:?}" "${DEMO_RUNTIME:?}" "${BACKEND_REF:?}"
mkdir -p "$DEMO_OUTPUT"
printf 'Recording has not completed. Do not submit this artifact as declaration evidence.\n' > "$DEMO_OUTPUT/summary.md"
[[ $(git -C .demo-mtt rev-parse HEAD) == "$BACKEND_REF" ]]
test -f tools/demo_backend/setup.sh
test ! -e android/key.properties
sudo apt-get update -qq
sudo apt-get install -y -qq mariadb-server php8.3-cli php8.3-mysql php8.3-mbstring php8.3-gd ffmpeg
sudo update-alternatives --set php /usr/bin/php8.3
sudo systemctl stop mariadb
printf '%s\n' 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
test -r /dev/kvm && test -w /dev/kvm
{
  git rev-parse HEAD
  git -C .demo-mtt rev-parse HEAD
  uname -a
  df -h .
  java -version
  flutter --version
  php -v
  adb version
  sdkmanager --list_installed
} > "$DEMO_OUTPUT/runner.txt" 2>&1
bash tools/demo_backend/setup.sh .demo-mtt "$DEMO_RUNTIME" > "$DEMO_OUTPUT/backend-setup.log" 2>&1
test -s "$DEMO_RUNTIME/fixture.json"
