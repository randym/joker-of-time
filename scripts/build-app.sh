#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DMG=0
NOTARIZE=0
ENV="production"
for arg in "$@"; do
  if [[ "$arg" == "--dmg" ]]; then BUILD_DMG=1;
  elif [[ "$arg" == "--notarize" ]]; then NOTARIZE=1;
  else ENV="$arg"; fi
done
[[ -z "$ENV" ]] && ENV="production"
# Use default notary profile when --notarize is passed and none set
if [[ "$NOTARIZE" -eq 1 && -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  export NOTARY_KEYCHAIN_PROFILE="AC_PASSWORD_KEY"
fi
echo "Building release binary..."
swift build -c release

BINARY=".build/release/JokerOfTime"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"
APP_NAME="$DIST_DIR/JokerOfTime.app"
CONTENTS="$APP_NAME/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ ! -f "$BINARY" ]]; then
  echo "Build failed: $BINARY not found"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

VERSION=$(node -p "require('$REPO_ROOT/package.json').version || '1.0.0'")
cp "$BINARY" "$MACOS/JokerOfTime"
cp "$REPO_ROOT/Info.plist" "$CONTENTS/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
chmod +x "$MACOS/JokerOfTime"

# Login item helper app (launches main app with --launched-at-login when run at login)
HELPER_BINARY="$REPO_ROOT/.build/release/LoginItemHelper"
LOGIN_ITEMS="$CONTENTS/Library/LoginItems"
HELPER_APP="$LOGIN_ITEMS/LoginItemHelper.app"
if [[ -f "$HELPER_BINARY" ]]; then
  mkdir -p "$HELPER_APP/Contents/MacOS"
  cp "$HELPER_BINARY" "$HELPER_APP/Contents/MacOS/LoginItemHelper"
  chmod +x "$HELPER_APP/Contents/MacOS/LoginItemHelper"
  cp "$REPO_ROOT/LoginItemHelper/Info.plist" "$HELPER_APP/Contents/Info.plist"
else
  echo "Warning: LoginItemHelper binary not found; run 'swift build -c release' to build all targets. Login-at-launch will use main app registration."
fi

echo -n "$ENV" > "$RESOURCES/environment.txt"

# Localization (.lproj must be in Contents/Resources for NSLocalizedString)
if [[ -d "$REPO_ROOT/Localization" ]]; then
  for lproj in "$REPO_ROOT/Localization"/*.lproj; do
    [[ -d "$lproj" ]] || continue
    lang=$(basename "$lproj" .lproj)
    mkdir -p "$RESOURCES/$lang.lproj"
    cp -R "$lproj"/* "$RESOURCES/$lang.lproj/"
  done
fi

# App icons: copy .icns for the bundle icon and PNG for internal use.
if [[ -f "$REPO_ROOT/assets/JokerOfTime.icns" ]]; then
  cp "$REPO_ROOT/assets/JokerOfTime.icns" "$RESOURCES/JokerOfTime.icns"
fi
if [[ -f "$REPO_ROOT/assets/JokerOfTime.png" ]]; then
  cp "$REPO_ROOT/assets/JokerOfTime.png" "$RESOURCES/AppIcon.png"
elif [[ -f "$REPO_ROOT/assets/JokerOfTime-AppIcon.png" ]]; then
  cp "$REPO_ROOT/assets/JokerOfTime-AppIcon.png" "$RESOURCES/AppIcon.png"
fi

echo "Building helper into Resources..."
OUT_DIR="$RESOURCES" node scripts/build-dist.js

# Automation files are required; missing = build error (no runtime check in shipped app)
if [[ ! -f "$RESOURCES/cli.js" ]]; then
  echo "Build failed: automation files missing — cli.js not found in Resources. Fix the helper build and re-run."
  exit 1
fi

echo "Injecting env from .env.$ENV into Resources..."
(cd "$REPO_ROOT" && DIST_DIR="$RESOURCES" node scripts/inject-env.js "$ENV")

cp -R "$REPO_ROOT/node_modules" "$RESOURCES/"
cat > "$RESOURCES/package.json" << EOF
{"name":"joker-of-time-helper","version":"$VERSION","main":"cli.js","private":true}
EOF

# Verify automation files again after copy (automation files missing = build error)
if [[ ! -f "$RESOURCES/cli.js" || ! -f "$RESOURCES/package.json" || ! -d "$RESOURCES/node_modules" ]]; then
  echo "Build failed: automation files missing in app bundle. Ensure cli.js, package.json, and node_modules are in Resources."
  exit 1
fi

# Optional: code sign so the keychain won't prompt on first install (item is tied to app identity)
sign_id=""
if [[ -n "$SIGNING_IDENTITY" ]]; then
  sign_id="$SIGNING_IDENTITY"
else
  # Prefer Developer ID Application for distribution; fall back to Apple Development (skip revoked)
  # Use SHA-1 hash (first column) so we're unambiguous when multiple certs share the same name
  ids=$(security find-identity -v -p codesigning 2>/dev/null | grep -v "REVOKED")
  sign_id=$(echo "$ids" | grep "Developer ID Application" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]+) .*/\1/')
  [[ -z "$sign_id" ]] && sign_id=$(echo "$ids" | grep "Apple Development" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]+) .*/\1/')
fi
if [[ -n "$sign_id" ]]; then
  echo "Signing app with identity: $sign_id"
  # Hardened runtime + timestamp required for notarization (timestamp implicit with Developer ID)
  CODESIGN_FLAGS=(--force --options runtime -s "$sign_id")
  # Sign all Mach-O binaries inside Resources first (e.g. .node, esbuild)
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q Mach-O; then
      echo "  Signing nested: ${f#$APP_NAME/}"
      codesign "${CODESIGN_FLAGS[@]}" "$f"
    fi
  done < <(find "$RESOURCES" -type f -print0 2>/dev/null)
  # Then main executable, then login item helper (if present), then the main bundle
  codesign "${CODESIGN_FLAGS[@]}" "$MACOS/JokerOfTime"
  if [[ -d "$LOGIN_ITEMS/LoginItemHelper.app" ]]; then
    codesign "${CODESIGN_FLAGS[@]}" "$LOGIN_ITEMS/LoginItemHelper.app/Contents/MacOS/LoginItemHelper"
    codesign "${CODESIGN_FLAGS[@]}" "$LOGIN_ITEMS/LoginItemHelper.app"
  fi
  codesign "${CODESIGN_FLAGS[@]}" "$APP_NAME"
else
  echo "Tip: To avoid keychain 'allow access' on first install, sign the app:"
  echo "  export SIGNING_IDENTITY=\"Apple Development: Your Name (TEAMID)\""
  echo "  then re-run this script."
fi

if [[ "$BUILD_DMG" -eq 1 ]]; then
  echo "Creating DMG..."
  DMG_FINAL="$DIST_DIR/Joker of Time.dmg"
  VOL_NAME="Joker of Time"
  VOL_PATH="/Volumes/$VOL_NAME"

  # Unmount if a previous DMG left the volume mounted (avoids "Operation not permitted")
  if [[ -d "$VOL_PATH" ]]; then
    echo "Unmounting existing '$VOL_NAME' volume..."
    if ! hdiutil detach "$VOL_PATH" -force 2>/dev/null; then
      echo "Could not unmount $VOL_PATH. Eject 'Joker of Time' from Finder, then run this script again."
      exit 1
    fi
  fi
  for f in "$DIST_DIR"/*; do
    [[ "$f" == "$APP_NAME" ]] && continue
    rm -rf "$f"
  done
  rm -f "$DMG_FINAL"

  ln -sf /Applications "$DIST_DIR/Applications"
  if ! hdiutil create -volname "$VOL_NAME" -srcfolder "$DIST_DIR" -ov -format UDZO "$DMG_FINAL"; then
    rm -f "$DIST_DIR/Applications"
    echo "DMG create failed. If you see 'Operation not permitted': eject any 'Joker of Time' volume in Finder, or add Terminal to System Settings → Privacy & Security → Full Disk Access, then try again."
    exit 1
  fi
  rm -f "$DIST_DIR/Applications"

  if [[ -f "$REPO_ROOT/assets/JokerOfTime.icns" ]]; then
    echo "Setting DMG file icon..."
    TEMP_DIR=$(mktemp -d)
    cp "$REPO_ROOT/assets/JokerOfTime.icns" "$TEMP_DIR/icon.icns"
    echo "read 'icns' (-16455) \"icon.icns\";" > "$TEMP_DIR/icon.r"
    (cd "$TEMP_DIR" && xcrun Rez -append icon.r -o "$DMG_FINAL")
    xcrun SetFile -a C "$DMG_FINAL"
    rm -rf "$TEMP_DIR"
  fi

  [[ -n "$sign_id" ]] && codesign --force -s "$sign_id" "$DMG_FINAL"

  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "Submitting DMG for notarization..."
    SUBMIT_OUT=$(mktemp)
    if ! xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait 2>&1 | tee "$SUBMIT_OUT"; then
      echo "Notary submission failed."
      rm -f "$SUBMIT_OUT"
      exit 1
    fi
    if grep -qi "status: Accepted" "$SUBMIT_OUT" || grep -qi "Accepted" "$SUBMIT_OUT"; then
      echo "Stapling notarization ticket..."
      xcrun stapler staple "$DMG_FINAL"
    else
      echo "Notarization was not accepted. Fetching notary log..."
      SUB_ID=$(sed -n 's/.*id: *\([^[:space:]]*\).*/\1/p' "$SUBMIT_OUT" | head -1)
      if [[ -n "$SUB_ID" ]]; then
        xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" 2>&1 || true
      fi
      rm -f "$SUBMIT_OUT"
      exit 1
    fi
    rm -f "$SUBMIT_OUT"
  fi

  echo "Done: dist/JokerOfTime.app, dist/Joker of Time.dmg"
else
  echo "Done: dist/JokerOfTime.app (self-contained)"
fi
echo "Requires Node.js installed. Use yarn run build:dmg for a DMG, or yarn run release for a signed + notarized DMG."
