#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MOCK_PID=""
cleanup() {
  if [[ -n "$MOCK_PID" ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    echo "Stopping mock server (PID $MOCK_PID)..."
    kill "$MOCK_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Building helper and injecting local env..."
node scripts/build-dist.js
node scripts/inject-env.js local

if [[ ! -f "$REPO_ROOT/.dev/cli.js" ]]; then
  echo "Helper build failed: .dev/cli.js not found"
  exit 1
fi

echo "Starting mock KOT server on port 4301..."
(
  node --env-file=.env.local -e "console.log('KOT_BASE_URL configured:', process.env.KOT_BASE_URL || '(not set)');"
  exec npx http-server mock-site -p 4301
) &
MOCK_PID=$!
sleep 1

echo "Running Swift app (dev)..."
swift run JokerOfTime
