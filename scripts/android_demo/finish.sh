#!/usr/bin/env bash
set -euo pipefail
: "${DEMO_OUTPUT:?}" "${DEMO_RUNTIME:?}"
mkdir -p "$DEMO_OUTPUT"
if [[ -f "$DEMO_RUNTIME/requests.jsonl" ]]; then
  cp "$DEMO_RUNTIME/requests.jsonl" "$DEMO_OUTPUT/backend-requests.jsonl"
fi
if [[ -f "$DEMO_RUNTIME/.demo-only" ]]; then
  bash tools/demo_backend/stop.sh "$DEMO_RUNTIME"
fi
if [[ ! -s "$DEMO_OUTPUT/summary.md" ]]; then
  printf 'Recording did not finish; inspect workflow logs. No verified declaration video.\n' > "$DEMO_OUTPUT/summary.md"
fi
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  cat "$DEMO_OUTPUT/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
