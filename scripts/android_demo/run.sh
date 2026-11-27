#!/usr/bin/env bash
set -euo pipefail
: "${DEMO_OUTPUT:?}" "${DEMO_RUNTIME:?}"
mkdir -p "$DEMO_OUTPUT"
bash tools/demo_backend/serve.sh "$DEMO_RUNTIME" 8765 > "$DEMO_OUTPUT/backend-server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
python3 - "$DEMO_OUTPUT" <<'PY'
import json, pathlib, sys, time, urllib.request
for attempt in range(50):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8765/demo/health', timeout=2) as reply:
            health = json.load(reply)
        assert health['demo_only'] is True
        pathlib.Path(sys.argv[1], 'backend-health.json').write_text(json.dumps(health, indent=2))
        break
    except (OSError, ValueError):
        time.sleep(.2)
else:
    raise SystemExit('Isolated backend did not become healthy')
PY
# No adb reverse: radio-off must also disconnect the app from the fixture.
adb wait-for-device
adb install build/app/outputs/flutter-apk/app-debug.apk
python3 scripts/android_demo/driver.py --runtime "$DEMO_RUNTIME" --output "$DEMO_OUTPUT"
