#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
swift package clean
/bin/rm -rf .build
if [[ -d dist ]]; then
  chflags -R nouchg dist 2>/dev/null || true
  xattr -cr dist 2>/dev/null || true
fi
if ! /bin/rm -rf dist 2>/dev/null; then
  # Try emptying then removing; sometimes works when rm -rf fails
  find "$REPO_ROOT/dist" -mindepth 1 -delete 2>/dev/null
  rmdir "$REPO_ROOT/dist" 2>/dev/null && true
fi
if [[ -d dist ]]; then
  echo "dist could not be removed (something has a handle open)."
  echo "Processes using files under dist:"
  lsof +D "$REPO_ROOT/dist" 2>/dev/null || true
  echo "Close Joker of Time, unmount the DMG, or quit the process above and run clean again."
  exit 1
fi
/bin/rm -rf .dev
