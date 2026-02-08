#!/usr/bin/env bash
# Clears all user data for the production app (dist JokerOfTime.app).
# - Keychain: credentials (service JokerOfTime, account default)
# - UserDefaults: io.github.randym.JokerOfTime (settings, session prefs)
# Run with: yarn run clear-production-data

set -e
BUNDLE_ID="io.github.randym.JokerOfTime"
KEYCHAIN_SERVICE="JokerOfTime"
KEYCHAIN_ACCOUNT="default"
PREFS="$HOME/Library/Preferences/${BUNDLE_ID}.plist"

echo "Clearing production app user data..."

# Keychain: stored credentials (production only)
if security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" 2>/dev/null; then
  echo "  Keychain credentials removed."
else
  echo "  Keychain: no credentials found (or already cleared)."
fi

# UserDefaults: all production settings and session prefs
if [[ -f "$PREFS" ]]; then
  rm -f "$PREFS"
  echo "  UserDefaults (preferences) removed."
else
  echo "  UserDefaults: no preferences file found."
fi

echo "Done. Production app user data cleared. Quit the app if running, then relaunch."
