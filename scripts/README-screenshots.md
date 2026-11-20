# Screenshot Capture Script

Automatically captures screenshots of all windows and dialogs in both English and Japanese locales.

## Prerequisites

### 1. Accessibility Permissions

The script needs Accessibility permissions to control the app and capture screenshots.

**To grant permissions:**

1. Open **System Settings** (or **System Preferences** on older macOS)
2. Go to **Privacy & Security** > **Accessibility**
3. Click the **+** button and add:
   - **Terminal** (if running from Terminal)
   - **Cursor** (if running from Cursor)
   - Or the app you're using to run this script
4. Make sure it's **enabled** (checkbox checked)

**Quick link to open Accessibility settings:**
```bash
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
```

### 2. Screen Recording Permissions (may be required)

Some macOS versions also require Screen Recording permissions:
1. Go to **Privacy & Security** > **Screen Recording**
2. Enable for the same app (Terminal/Cursor/etc.)

## Usage

```bash
./scripts/capture-screenshots.swift
```

The script will:
1. Build the app in production mode (no dev-only UI)
2. Launch the app with English locale
3. Capture menu bar menu, Settings, About, and all 14 dialogs
4. Quit and restart with Japanese locale
5. Capture all screenshots again
6. Save to `screenshots/en/` and `screenshots/ja/` directories

## Output

Screenshots are saved with consistent naming:
- `menu.png` - Menu bar dropdown menu
- `settings.png` - Settings window (production version)
- `about.png` - About window
- `start-work.png` - Start work prompt
- `stop-work-early.png` - Stop work (early) prompt
- `stop-work-on-time.png` - Stop work (on time) prompt
- `stop-work-late.png` - Stop work (late/overtime) prompt
- `already-clocked-in.png` - Already clocked in alert
- `already-clocked-out.png` - Already clocked out alert
- `not-clocked-in.png` - Not clocked in alert
- `cannot-clock-out.png` - Cannot clock out alert
- `credentials-required.png` - Credentials required prompt
- `login-failed.png` - Login failed alert
- `network-offline.png` - Network offline alert
- `cannot-reach-site.png` - Cannot reach site alert
- `node-not-found.png` - Node.js not found alert
- `something-went-wrong.png` - Something went wrong alert

## Troubleshooting

**"Accessibility permissions required" error:**
- Grant Accessibility permissions as described above
- Make sure the app you're running the script from is enabled

**"Failed to capture window" errors:**
- Make sure Screen Recording permissions are granted
- Try running the script again (timing issues)

**"Dialog window not found" warnings:**
- The app may need more time to initialize
- Check that screenshot mode is enabled (the script sets this automatically)
- Verify the app is running in production mode

**Menu capture fails:**
- Make sure the menu bar menu is visible when capturing
- The script waits for the menu to appear, but timing can vary
