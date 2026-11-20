#!/usr/bin/env swift

import Foundation
import AppKit
import CoreGraphics
import Cocoa

// MARK: - Configuration

let bundleID = "io.github.randym.JokerOfTime"
let appPath = "dist/JokerOfTime.app"
let screenshotsDir = "docs/screenshots"
let locales = ["en", "ja"]

// MARK: - Screenshot Dialog Kinds

enum ScreenshotDialogKind: String, CaseIterable {
    case startWork = "start-work"
    case stopWorkEarly = "stop-work-early"
    case stopWorkOnTime = "stop-work-on-time"
    case stopWorkLate = "stop-work-late"
    case alreadyClockedIn = "already-clocked-in"
    case alreadyClockedOut = "already-clocked-out"
    case notClockedIn = "not-clocked-in"
    case cannotClockOut = "cannot-clock-out"
    case credentialsRequired = "credentials-required"
    case loginFailed = "login-failed"
    case networkOffline = "network-offline"
    case cannotReachSite = "cannot-reach-site"
    case nodeNotFound = "node-not-found"
    case somethingWentWrong = "something-went-wrong"
}

// MARK: - Utilities

func runCommand(_ command: String) -> (output: String, exitCode: Int32) {
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", command]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    process.launch()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    return (output, process.terminationStatus)
}

func waitForAppToLaunch() -> Bool {
    print("Waiting for app to launch...")
    for _ in 0..<30 {
        let running = NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == bundleID
        }
        if running != nil {
            // Give it a bit more time to fully initialize
            Thread.sleep(forTimeInterval: 2.0)
            return true
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    return false
}

func findWindow(withTitleContains titleSubstring: String) -> CGWindowID? {
    let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    print("  🔍 Searching for window with title containing '\(titleSubstring)'...")
    print("  🔍 Found \(windowList.count) total windows on screen")
    var candidateWindows: [(id: CGWindowID, name: String, layer: Int, bounds: [String: Any])] = []
    for windowInfo in windowList {
        if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
           (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
           let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID {
            let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
            print("  🔍 Joker of Time window: name='\(windowName)' layer=\(layer) id=\(windowID)")
            
            // Check title match first
            if windowName.contains(titleSubstring) {
                print("  ✅ Found matching window by title!")
                return windowID
            }
            
            // Collect candidate windows (normal windows, layer 0, reasonable size)
            if layer == 0, let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat,
               width > 200 && height > 200 {
                candidateWindows.append((id: windowID, name: windowName, layer: layer, bounds: bounds))
            }
        }
    }
    
    // If no title match but we have candidates, use the first one (Settings window might have empty name)
    if candidateWindows.count > 0 {
        print("  ⚠️  No title match, but found \(candidateWindows.count) candidate window(s)")
        print("  💡 Using first candidate: id=\(candidateWindows[0].id) name='\(candidateWindows[0].name)'")
        return candidateWindows[0].id
    }
    
    print("  ⚠️  No matching window found")
    return nil
}

func waitForWindow(withTitleContains titleSubstring: String, timeout: TimeInterval = 5.0) -> CGWindowID? {
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout {
        if let windowID = findWindow(withTitleContains: titleSubstring) {
            Thread.sleep(forTimeInterval: 0.3) // Give SwiftUI a moment to render
            return windowID
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
}

func waitForMenuWindow(timeout: TimeInterval = 3.0) -> CGWindowID? {
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        print("  🔍 Checking for menu window... Found \(windowList.count) windows")
        for windowInfo in windowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let y = bounds["Y"] as? CGFloat,
               let layer = windowInfo[kCGWindowLayer as String] as? Int {
                let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
                let height = bounds["Height"] as? CGFloat ?? 0
                let width = bounds["Width"] as? CGFloat ?? 0
                
                // Menu windows: layer 25 (menu level)
                // Y coordinate: macOS uses bottom-left origin, but CGWindowListCopyWindowInfo might use top-left
                // Menus appear near the top, so Y could be negative (relative to screen) or large positive
                // Check for layer 25 OR small window near top of screen
                let isMenuWindow = (layer == 25) || 
                                  (height < 500 && width < 400 && (abs(y) > 100 || y > 20) && (windowName.isEmpty || windowName.contains("menu")))
                
                if isMenuWindow {
                    print("  ✅ Found menu window: layer=\(layer) y=\(y) height=\(height) name='\(windowName)' id=\(windowID)")
                    return windowID
                } else {
                    // Debug: log windows that are close but don't match
                    if y > 20 && y < 300 && height < 500 {
                        print("  🔍 Close match (not selected): layer=\(layer) y=\(y) height=\(height) name='\(windowName)' id=\(windowID)")
                    }
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("  ⚠️  Menu window not found after \(timeout) seconds")
    return nil
}

func captureWindow(_ windowID: CGWindowID, to path: String) -> Bool {
    // Try window capture first
    var (output, exitCode) = runCommand("screencapture -l\(windowID) '\(path)'")
    if exitCode == 0 {
        return true
    }
    
    // If window capture fails, try region-based capture using window bounds
    print("  ⚠️  Window capture failed, trying region-based capture...")
    if let windowInfo = getWindowInfo(windowID) {
        if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
           let x = bounds["X"] as? CGFloat,
           let y = bounds["Y"] as? CGFloat,
           let width = bounds["Width"] as? CGFloat,
           let height = bounds["Height"] as? CGFloat {
            // screencapture -R uses format: x,y,width,height with top-left origin
            // CGWindowListCopyWindowInfo bounds are in screen coordinates
            // Need to handle negative coordinates (windows off-screen or coordinate system differences)
            let screenHeight = getScreenHeight()
            let screenWidth = NSScreen.main?.frame.width ?? 1920
            
            // Convert Y coordinate: CGWindowListCopyWindowInfo uses bottom-left origin
            let screenY: CGFloat
            if y < 0 {
                // Negative Y might mean it's measured from top (inverted) or off-screen
                // Try absolute value first
                screenY = abs(y)
            } else {
                // Positive Y means it's from bottom, convert to top-left origin
                screenY = screenHeight - y - height
            }
            
            // Handle X coordinate: if negative, window might be off-screen or coordinate issue
            let screenX: CGFloat
            if x < 0 {
                // Negative X - might be off-screen or coordinate system issue
                // For menu bar items, they're usually on the right side
                // Try to calculate from screen width
                screenX = max(0, screenWidth + x) // If x is -587 and screen is 1920, try 1920-587=1333
            } else {
                screenX = x
            }
            
            // Only attempt capture if coordinates are reasonable
            if screenX >= 0 && screenY >= 0 && screenX < screenWidth && screenY < screenHeight {
                let region = "\(Int(screenX)),\(Int(screenY)),\(Int(width)),\(Int(height))"
                print("  🔍 Attempting region capture: \(region) (original x=\(x), y=\(y), screenWidth=\(screenWidth), screenHeight=\(screenHeight))")
                (output, exitCode) = runCommand("screencapture -R \(region) '\(path)'")
                if exitCode == 0 {
                    print("  ✅ Captured using region: \(region)")
                    return true
                } else {
                    print("  ⚠️  Region capture also failed: \(output)")
                }
            } else {
                print("  ⚠️  Invalid coordinates after conversion: x=\(screenX), y=\(screenY) (original x=\(x), y=\(y))")
            }
        }
    }
    
    print("  ❌ Failed to capture window: \(output)")
    return false
}

func captureMenuWindow(_ windowID: CGWindowID, to path: String) -> Bool {
    // Try window capture first
    var (output, exitCode) = runCommand("screencapture -l\(windowID) '\(path)'")
    if exitCode == 0 {
        return true
    }
    
    // If window capture fails, try region-based capture using window bounds
    print("  ⚠️  Menu window capture failed, trying region-based capture...")
    if let windowInfo = getWindowInfo(windowID) {
        if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
           let x = bounds["X"] as? CGFloat,
           let y = bounds["Y"] as? CGFloat,
           let width = bounds["Width"] as? CGFloat,
           let height = bounds["Height"] as? CGFloat {
            // screencapture -R uses format: x,y,width,height with top-left origin
            // CGWindowListCopyWindowInfo bounds are in screen coordinates
            // Need to handle negative coordinates (windows off-screen or coordinate system differences)
            let screenHeight = getScreenHeight()
            let screenWidth = NSScreen.main?.frame.width ?? 1920
            
            // Convert Y coordinate: CGWindowListCopyWindowInfo uses bottom-left origin
            let screenY: CGFloat
            if y < 0 {
                // Negative Y might mean it's measured from top (inverted) or off-screen
                // Try absolute value first
                screenY = abs(y)
            } else {
                // Positive Y means it's from bottom, convert to top-left origin
                screenY = screenHeight - y - height
            }
            
            // Handle X coordinate: if negative, window might be off-screen or coordinate issue
            let screenX: CGFloat
            if x < 0 {
                // Negative X - might be off-screen or coordinate system issue
                // For menu bar items, they're usually on the right side
                // Try to calculate from screen width
                screenX = max(0, screenWidth + x) // If x is -587 and screen is 1920, try 1920-587=1333
            } else {
                screenX = x
            }
            
            // Only attempt capture if coordinates are reasonable
            if screenX >= 0 && screenY >= 0 && screenX < screenWidth && screenY < screenHeight {
                let region = "\(Int(screenX)),\(Int(screenY)),\(Int(width)),\(Int(height))"
                print("  🔍 Attempting menu region capture: \(region) (original x=\(x), y=\(y), screenWidth=\(screenWidth), screenHeight=\(screenHeight))")
                (output, exitCode) = runCommand("screencapture -R \(region) '\(path)'")
                if exitCode == 0 {
                    print("  ✅ Captured menu using region: \(region)")
                    return true
                } else {
                    print("  ⚠️  Menu region capture also failed: \(output)")
                }
            } else {
                print("  ⚠️  Invalid coordinates after conversion: x=\(screenX), y=\(screenY) (original x=\(x), y=\(y))")
            }
        }
    }
    
    print("  ❌ Failed to capture menu: \(output)")
    return false
}

func getWindowInfo(_ windowID: CGWindowID) -> [String: Any]? {
    let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    for windowInfo in windowList {
        if let id = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           id == windowID {
            return windowInfo
        }
    }
    return nil
}

func getScreenHeight() -> CGFloat {
    // Get the main screen height for coordinate conversion
    if let screen = NSScreen.main {
        return screen.frame.height
    }
    // Fallback: try to get from window list
    let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    var maxY: CGFloat = 0
    for windowInfo in windowList {
        if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
           let y = bounds["Y"] as? CGFloat,
           let height = bounds["Height"] as? CGFloat {
            maxY = max(maxY, y + height)
        }
    }
    return maxY > 0 ? maxY : 1080 // Default fallback
}

func triggerDialog(_ kind: ScreenshotDialogKind) {
    print("  📤 Triggering dialog: \(kind.rawValue)")
    
    // Ensure screenshot mode is enabled
    _ = runCommand("defaults write \(bundleID) JokerOfTimeScreenshotMode -bool true")
    Thread.sleep(forTimeInterval: 0.3)
    
    // Use DistributedNotificationCenter to trigger dialog programmatically
    let notificationName = "JokerOfTimeShowScreenshotDialog"
    print("  📤 Sending notification to show dialog: \(notificationName)")
    DistributedNotificationCenter.default().post(
        name: Notification.Name(notificationName),
        object: nil,
        userInfo: ["dialogKind": kind.rawValue]
    )
    
    // Ensure app is active
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
        app.activate(options: [])
    }
    
    Thread.sleep(forTimeInterval: 1.5) // Give app time to receive notification and show dialog
}

func triggerMenu() {
    // Use DistributedNotificationCenter to trigger menu programmatically
    let notificationName = "JokerOfTimeShowScreenshotMenu"
    print("  📤 Sending notification to show menu: \(notificationName)")
    DistributedNotificationCenter.default().post(
        name: Notification.Name(notificationName),
        object: nil,
        userInfo: nil
    )
    Thread.sleep(forTimeInterval: 0.5)
}

func triggerAbout() {
    // Use DistributedNotificationCenter to trigger About window programmatically
    let notificationName = "JokerOfTimeShowScreenshotAbout"
    print("  📤 Sending notification to show About: \(notificationName)")
    DistributedNotificationCenter.default().post(
        name: Notification.Name(notificationName),
        object: nil,
        userInfo: nil
    )
    Thread.sleep(forTimeInterval: 1.0)
}

// triggerMenu() is now handled inline in capture functions - no standalone function needed

func closeDialog() {
    // Close dialog by pressing Escape
    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to key code 53' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to key code 53'") // Escape key
    Thread.sleep(forTimeInterval: 0.3)
}

func closeWindow() {
    // Close window by pressing Cmd+W (works for Settings, About, etc.)
    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to keystroke \"w\" using command down' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to keystroke \"w\" using command down'")
    Thread.sleep(forTimeInterval: 0.5)
}


// MARK: - Main Capture Function

func captureScreenshots(for locale: String, filter: String? = nil) {
    print("\n📸 Capturing screenshots for locale: \(locale)")
    
    // Kill any existing instance
    print("Checking for existing app instance...")
    if let existingApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
        print("  Quitting existing instance...")
        existingApp.terminate()
        Thread.sleep(forTimeInterval: 2.0)
    }
    
    // Set locale via defaults command (affects the app when it launches)
    print("Setting locale to \(locale)...")
    let (localeOutput, localeCode) = runCommand("defaults write \(bundleID) AppleLanguages '(\(locale))'")
    if localeCode != 0 {
        print("  ⚠️  Failed to set locale: \(localeOutput)")
    }
    
    // Enable screenshot mode
    print("Enabling screenshot mode...")
    let (screenshotOutput, screenshotCode) = runCommand("defaults write \(bundleID) JokerOfTimeScreenshotMode -bool true")
    if screenshotCode != 0 {
        print("  ⚠️  Failed to enable screenshot mode: \(screenshotOutput)")
    } else {
        print("  ✅ Screenshot mode enabled")
    }
    
    // Verify screenshot mode is set
    let (verifyOutput, _) = runCommand("defaults read \(bundleID) JokerOfTimeScreenshotMode 2>/dev/null || echo 'not set'")
    print("  🔍 Screenshot mode value: \(verifyOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
    
    // Ensure app is built
    print("Building app in production mode...")
    let (buildOutput, buildCode) = runCommand("cd '\(FileManager.default.currentDirectoryPath)' && ./scripts/build-app.sh production")
    if buildCode != 0 {
        print("❌ Build failed: \(buildOutput)")
        return
    }
    
    // Launch app
    print("Launching app...")
    let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(appPath)
    guard NSWorkspace.shared.open(appURL) else {
        print("❌ Failed to launch app")
        return
    }
    
    guard waitForAppToLaunch() else {
        print("❌ App failed to launch")
        return
    }
    
    // Give app time to fully initialize (preflight, status item setup, etc.)
    print("Waiting for app to initialize...")
    Thread.sleep(forTimeInterval: 5.0) // Increased wait time
    
    // Verify app is running and screenshot mode is active
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
        print("  ✅ App is running (PID: \(app.processIdentifier))")
    } else {
        print("  ❌ App is not running!")
        return
    }
    
    // Verify screenshot mode is actually enabled in the running app
    // UserDefaults set via `defaults write` should be available, but let's verify and sync
    print("  🔍 Verifying screenshot mode in running app...")
    Thread.sleep(forTimeInterval: 1.0) // Give app time to read UserDefaults
    
    // Force UserDefaults synchronization by touching the value again
    _ = runCommand("defaults write \(bundleID) JokerOfTimeScreenshotMode -bool true")
    _ = runCommand("killall -u $USER cfprefsd 2>/dev/null || true") // Force UserDefaults cache refresh
    Thread.sleep(forTimeInterval: 0.5)
    
    let (verifyRunning, _) = runCommand("defaults read \(bundleID) JokerOfTimeScreenshotMode 2>/dev/null || echo 'not set'")
    let isEnabled = verifyRunning.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    if isEnabled {
        print("  ✅ Screenshot mode confirmed enabled")
    } else {
        print("  ⚠️  Screenshot mode may not be enabled in running app: \(verifyRunning.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("  💡 Re-enabling screenshot mode...")
        _ = runCommand("defaults write \(bundleID) JokerOfTimeScreenshotMode -bool true")
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Dismiss any launch prompts that might appear (e.g., "do you want to clock in?")
    print("Dismissing any launch prompts...")
    Thread.sleep(forTimeInterval: 1.0)
    // Press Escape to dismiss any prompts
    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to key code 53' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to key code 53'") // Escape key
    Thread.sleep(forTimeInterval: 0.5)
    // Also try clicking outside any dialogs
    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to click at {100, 100}' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to click at {100, 100}'")
    Thread.sleep(forTimeInterval: 1.0)
    
    let localeDir = "\(screenshotsDir)/\(locale)"
    try? FileManager.default.createDirectory(atPath: localeDir, withIntermediateDirectories: true)
    
    // Capture menu bar dropdown menu (the menu that appears when you click the menu bar icon)
    if filter == nil || filter == "menu" {
        print("\n📋 Capturing menu bar dropdown menu...")
    // Make sure no dialogs are open first
    closeDialog()
    Thread.sleep(forTimeInterval: 0.5)
    
    // Try notification-based method first (most reliable)
    print("  Opening menu via notification...")
    triggerMenu()
    Thread.sleep(forTimeInterval: 1.5) // Give menu more time to appear
    var menuOpened = waitForMenuWindow(timeout: 3.0) != nil
    
    if menuOpened {
        print("  ✅ Menu opened via notification")
    } else {
        print("  ⚠️  Menu window not detected, but menu may still be open. Listing all windows...")
        // List all windows to help debug
        let allWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for winInfo in allWindows {
            if let owner = winInfo[kCGWindowOwnerName as String] as? String,
               (owner == "Joker of Time" || owner == "JokerOfTime") {
                let name = winInfo[kCGWindowName as String] as? String ?? ""
                let layer = winInfo[kCGWindowLayer as String] as? Int ?? 0
                let bounds = winInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let y = bounds["Y"] as? CGFloat ?? 0
                let height = bounds["Height"] as? CGFloat ?? 0
                print("    - name='\(name)' layer=\(layer) y=\(y) height=\(height)")
            }
        }
        print("  Trying AppleScript methods as fallback...")
    }
    
    // Try multiple fallback methods to trigger the menu
    if !menuOpened {
        print("  Trying AppleScript methods to open menu...")
    
    // Method 1: Try clicking status item button via UI elements
    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
    let method1Script1 = """
    tell application "System Events"
        tell process "JokerOfTime"
            try
                set menuBar to menu bar 1
                set uiElements to UI elements of menuBar
                repeat with element in uiElements
                    try
                        if class of element is button then
                            click element
                            return true
                        end if
                    end try
                end repeat
            end try
        end tell
    end tell
    """
    let method1Script2 = """
    tell application "System Events"
        tell process "Joker of Time"
            try
                set menuBar to menu bar 1
                set uiElements to UI elements of menuBar
                repeat with element in uiElements
                    try
                        if class of element is button then
                            click element
                            return true
                        end if
                    end try
                end repeat
            end try
        end tell
    end tell
    """
    let (_, code1) = runCommand("osascript -e '\(method1Script1)' || osascript -e '\(method1Script2)'")
    if code1 == 0 {
        Thread.sleep(forTimeInterval: 0.8)
        if waitForMenuWindow(timeout: 2.0) != nil {
            menuOpened = true
            print("  ✅ Menu opened via method 1")
        }
    }
    
    // Method 2: Try clicking at right side of menu bar (where status items are)
    if !menuOpened {
        print("  Trying method 2: clicking at menu bar coordinates...")
        // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
        let method2Script1 = """
        tell application "System Events"
            tell application process "JokerOfTime"
                try
                    -- Get screen dimensions
                    set screenBounds to bounds of window 1
                    if screenBounds is not {} then
                        set screenWidth to item 3 of screenBounds
                        -- Click near right edge where status items appear
                        click at {screenWidth - 25, 5}
                    else
                        -- Fallback: use main screen
                        set screenWidth to (do shell script "system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2}'")
                        click at {screenWidth - 25, 5}
                    end if
                end try
            end tell
        end tell
        """
        let method2Script2 = """
        tell application "System Events"
            tell application process "Joker of Time"
                try
                    -- Get screen dimensions
                    set screenBounds to bounds of window 1
                    if screenBounds is not {} then
                        set screenWidth to item 3 of screenBounds
                        -- Click near right edge where status items appear
                        click at {screenWidth - 25, 5}
                    else
                        -- Fallback: use main screen
                        set screenWidth to (do shell script "system_profiler SPDisplaysDataType | grep Resolution | head -1 | awk '{print $2}'")
                        click at {screenWidth - 25, 5}
                    end if
                end try
            end tell
        end tell
        """
        let (_, _) = runCommand("osascript -e '\(method2Script1)' || osascript -e '\(method2Script2)'")
        Thread.sleep(forTimeInterval: 0.8)
        if waitForMenuWindow(timeout: 2.0) != nil {
            menuOpened = true
            print("  ✅ Menu opened via method 2")
        }
    }
    
    // Method 3: Try using CGWindowList to find menu bar icon and simulate click
    if !menuOpened {
        print("  Trying method 3: finding menu bar icon window...")
        // Status items might be accessible as windows
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for windowInfo in windowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let windowName = windowInfo[kCGWindowName as String] as? String,
               windowName.isEmpty || windowName == "Joker of Time", // Status items might have empty or app name
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let y = bounds["Y"] as? CGFloat,
               y < 50 { // Near top of screen (menu bar area)
                // Try clicking at this window's center
                if let x = bounds["X"] as? CGFloat,
                   let width = bounds["Width"] as? CGFloat,
                   let height = bounds["Height"] as? CGFloat {
                    let centerX = x + width / 2
                    let centerY = y + height / 2
                    // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
                    let clickScript1 = """
                    tell application "System Events"
                        tell process "JokerOfTime"
                            click at {\(Int(centerX)), \(Int(centerY))}
                        end tell
                    end tell
                    """
                    let clickScript2 = """
                    tell application "System Events"
                        tell process "Joker of Time"
                            click at {\(Int(centerX)), \(Int(centerY))}
                        end tell
                    end tell
                    """
                    _ = runCommand("osascript -e '\(clickScript1)' || osascript -e '\(clickScript2)'")
                    Thread.sleep(forTimeInterval: 0.8)
                    if waitForMenuWindow(timeout: 2.0) != nil {
                        menuOpened = true
                        print("  ✅ Menu opened via method 3")
                        break
                    }
                }
            }
        }
    }
    } // Close the if !menuOpened block
    
    // Now try to capture the menu
    // Menus created via NSMenu.popUp() might not show up as regular windows
    // Try multiple approaches to find and capture it
    print("  Searching for menu window to capture...")
    
    // Wait a bit for menu to fully appear
    Thread.sleep(forTimeInterval: 0.5)
    
    // Method 1: Use waitForMenuWindow (looks for layer 25 or menu-like windows)
    var menuWindowID: CGWindowID?
    if let id = waitForMenuWindow(timeout: 2.0) {
        menuWindowID = id
        print("  ✅ Found menu window via detection: \(id)")
    }
    
    // Method 2: If not found, list all windows and look for menu-like ones
    if menuWindowID == nil {
        print("  🔍 Detection failed, searching all windows...")
        let allWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        print("  🔍 Found \(allWindows.count) total windows")
        
        // Look for windows that could be the menu
        for winInfo in allWindows {
            if let owner = winInfo[kCGWindowOwnerName as String] as? String,
               (owner == "Joker of Time" || owner == "JokerOfTime"),
               let bounds = winInfo[kCGWindowBounds as String] as? [String: Any],
               let y = bounds["Y"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let layer = winInfo[kCGWindowLayer as String] as? Int,
               let winID = winInfo[kCGWindowNumber as String] as? CGWindowID {
                let name = winInfo[kCGWindowName as String] as? String ?? ""
                // Menu characteristics: layer 25 OR small window (height <500, width <400) near top
                // Y can be negative (macOS coordinate system) or positive
                if layer == 25 || (height < 500 && width < 400 && (abs(y) > 100 || y > 20)) {
                    print("  🔍 Candidate menu: layer=\(layer) y=\(y) size=\(Int(width))x\(Int(height)) name='\(name)' id=\(winID)")
                    if menuWindowID == nil {
                        menuWindowID = winID // Use first candidate
                    }
                }
            }
        }
    }
    
    // Capture if we found a window
    if let menuID = menuWindowID {
        let menuPath = "\(localeDir)/menu.png"
        print("  📸 Capturing menu window ID: \(menuID)")
        if captureMenuWindow(menuID, to: menuPath) {
            print("  ✅ Saved: \(menuPath)")
        } else {
            print("  ❌ Failed to capture menu window")
        }
        // Close menu
        // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
        _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to key code 53' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to key code 53'") // Escape key
        Thread.sleep(forTimeInterval: 0.3)
    } else {
        print("  ⚠️  Could not find menu window for capture")
        print("  💡 The menu is open but not detected as a window. This is normal for NSMenu.popUp() menus.")
        print("  💡 You may need to manually capture the menu or use a different capture method.")
    }
    Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Capture Settings window
    if filter == nil || filter == "settings" {
        print("\n⚙️  Capturing Settings window...")
    // Ensure menu is closed first
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to key code 53' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to key code 53'") // Escape key
    Thread.sleep(forTimeInterval: 0.5)
    
    // Ensure app is active before sending Cmd+,
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
        app.activate(options: [])
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Open Settings via Cmd+, (try both process names)
    print("  📤 Opening Settings window (Cmd+,)...")
    _ = runCommand("osascript -e 'tell application \"System Events\" to tell process \"JokerOfTime\" to keystroke \",\" using command down' || osascript -e 'tell application \"System Events\" to tell process \"Joker of Time\" to keystroke \",\" using command down'")
    Thread.sleep(forTimeInterval: 2.0) // Give more time for Settings to open and render
    
    // Try multiple title variations first
    let settingsTitles = locale == "ja" ? ["設定", "Settings"] : ["Settings", "設定"]
    var settingsWindowID: CGWindowID?
    for title in settingsTitles {
        if let id = waitForWindow(withTitleContains: title, timeout: 5.0) {
            settingsWindowID = id
            print("  ✅ Found Settings window by title: \(title)")
            break
        }
    }
    
    // If title search failed, look for any normal window (layer 0) with reasonable size
    if settingsWindowID == nil {
        print("  🔍 Title search failed, looking for any visible Settings-like window...")
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for windowInfo in windowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let layer = windowInfo[kCGWindowLayer as String] as? Int,
               layer == 0, // Normal window
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat,
               width > 400 && height > 300 { // Settings window should be reasonably large
                let name = windowInfo[kCGWindowName as String] as? String ?? ""
                print("  🔍 Found candidate Settings window: id=\(windowID) size=\(Int(width))x\(Int(height)) name='\(name)'")
                settingsWindowID = windowID
                break
            }
        }
    }
    
    if let windowID = settingsWindowID {
        let settingsPath = "\(localeDir)/settings.png"
        if captureWindow(windowID, to: settingsPath) {
            print("  ✅ Saved: \(settingsPath)")
        } else {
            print("  ❌ Failed to capture Settings")
        }
        closeWindow() // Close Settings window properly (Cmd+W)
    } else {
        print("  ❌ Settings window not found")
    }
    Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Capture About window
    if filter == nil || filter == "about" {
    print("\nℹ️  Capturing About window...")
    // Close any open dialogs/windows first
    closeDialog()
    closeWindow()
    Thread.sleep(forTimeInterval: 0.5)
    
        // Method 1: Try notification-based trigger (most reliable)
        print("  Opening About window via notification...")
        triggerAbout()
        Thread.sleep(forTimeInterval: 1.5) // Give About window time to appear
        
        // Method 2: Fallback to menu-based approach if notification doesn't work
        var aboutWindowID: CGWindowID?
        if waitForWindow(withTitleContains: "About", timeout: 2.0) == nil &&
           waitForWindow(withTitleContains: "このアプリについて", timeout: 0.5) == nil {
            print("  ⚠️  Notification method didn't open About, trying menu-based approach...")
            // Open the menu using notification method
            print("  Opening menu via notification...")
            triggerMenu()
            Thread.sleep(forTimeInterval: 1.5) // Give menu time to appear
            var menuOpenedForAbout = waitForMenuWindow(timeout: 2.0) != nil
            
            if !menuOpenedForAbout {
        print("  ⚠️  Notification method failed, trying AppleScript...")
        // Try the same methods to open menu
        // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
        let aboutMethod1Script1 = """
        tell application "System Events"
            tell process "JokerOfTime"
                try
                    set menuBar to menu bar 1
                    set uiElements to UI elements of menuBar
                    repeat with element in uiElements
                        try
                            if class of element is button then
                                click element
                                return true
                            end if
                        end try
                    end repeat
                end try
            end tell
        end tell
        """
        let aboutMethod1Script2 = """
        tell application "System Events"
            tell process "Joker of Time"
                try
                    set menuBar to menu bar 1
                    set uiElements to UI elements of menuBar
                    repeat with element in uiElements
                        try
                            if class of element is button then
                                click element
                                return true
                            end if
                        end try
                    end repeat
                end try
            end tell
        end tell
        """
        let (_, aboutCode1) = runCommand("osascript -e '\(aboutMethod1Script1)' || osascript -e '\(aboutMethod1Script2)'")
        if aboutCode1 == 0 {
            Thread.sleep(forTimeInterval: 0.8)
            if waitForMenuWindow(timeout: 2.0) != nil {
                menuOpenedForAbout = true
            }
        }
        
        // Fallback: click at right side
        if !menuOpenedForAbout {
            // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
            let aboutMethod2Script1 = """
            tell application "System Events"
                tell application process "JokerOfTime"
                    try
                        set screenBounds to bounds of window 1
                        if screenBounds is not {} then
                            set screenWidth to item 3 of screenBounds
                            click at {screenWidth - 25, 5}
                        end if
                    end try
                end tell
            end tell
            """
            let aboutMethod2Script2 = """
            tell application "System Events"
                tell application process "Joker of Time"
                    try
                        set screenBounds to bounds of window 1
                        if screenBounds is not {} then
                            set screenWidth to item 3 of screenBounds
                            click at {screenWidth - 25, 5}
                        end if
                    end try
                end tell
            end tell
            """
            _ = runCommand("osascript -e '\(aboutMethod2Script1)' || osascript -e '\(aboutMethod2Script2)'")
            Thread.sleep(forTimeInterval: 0.8)
            if waitForMenuWindow(timeout: 2.0) != nil {
                menuOpenedForAbout = true
            }
        }
    }
    
    if menuOpenedForAbout {
        // Now click the About menu item
        print("  🔍 Clicking About menu item...")
        let aboutTitle = locale == "ja" ? "このアプリについて" : "About"
        
        // Get menu window bounds for coordinate-based click (more reliable for popup menus)
        var menuBounds: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)?
        if let menuWindowID = waitForMenuWindow(timeout: 1.0) {
            let windowList = CGWindowListCopyWindowInfo(.optionIncludingWindow, menuWindowID) as? [[String: Any]] ?? []
            if let windowInfo = windowList.first,
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat,
               let y = bounds["Y"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                menuBounds = (x: x, y: y, width: width, height: height)
            }
        }
        
        // Method 1: Try coordinate-based click (most reliable for popup menus)
        if let bounds = menuBounds {
            let screenHeight = getScreenHeight()
            let screenWidth = NSScreen.main?.frame.width ?? 1920
            let screenX = bounds.x < 0 ? max(0, screenWidth + bounds.x) : bounds.x
            let screenY = bounds.y < 0 ? abs(bounds.y) : screenHeight - bounds.y - bounds.height
            // About is the first menu item, click near top-center of menu
            let aboutClickX = screenX + bounds.width / 2  // Center horizontally
            let aboutClickY = screenY + bounds.height - 25  // Near top (first item)
            
            // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
            let clickScript1 = """
            tell application "System Events"
                tell process "JokerOfTime"
                    click at {\(Int(aboutClickX)), \(Int(aboutClickY))}
                end tell
            end tell
            """
            let clickScript2 = """
            tell application "System Events"
                tell process "Joker of Time"
                    click at {\(Int(aboutClickX)), \(Int(aboutClickY))}
                end tell
            end tell
            """
            _ = runCommand("osascript -e '\(clickScript1)' || osascript -e '\(clickScript2)'")
            print("  ✅ Clicked About menu item at coordinates (\(Int(aboutClickX)), \(Int(aboutClickY)))")
        } else {
            // Fallback: Try AppleScript menu item search
            // Try both process names - logs show "JokerOfTime" but UI shows "Joker of Time"
            let clickAboutScript1 = """
            tell application "System Events"
                tell process "JokerOfTime"
                    try
                        set menuBarItems to menu bar items of menu bar 1
                        repeat with menuBarItem in menuBarItems
                            try
                                if exists menu of menuBarItem then
                                    set menuItems to menu items of menu of menuBarItem
                                    repeat with menuItem in menuItems
                                        try
                                            set itemName to name of menuItem
                                            if itemName contains "\(aboutTitle)" or itemName is "\(aboutTitle)" then
                                                click menuItem
                                                return true
                                            end if
                                        end try
                                    end repeat
                                end if
                            end try
                        end repeat
                    end try
                end tell
            end tell
            """
            let clickAboutScript2 = """
            tell application "System Events"
                tell process "Joker of Time"
                    try
                        set menuBarItems to menu bar items of menu bar 1
                        repeat with menuBarItem in menuBarItems
                            try
                                if exists menu of menuBarItem then
                                    set menuItems to menu items of menu of menuBarItem
                                    repeat with menuItem in menuItems
                                        try
                                            set itemName to name of menuItem
                                            if itemName contains "\(aboutTitle)" or itemName is "\(aboutTitle)" then
                                                click menuItem
                                                return true
                                            end if
                                        end try
                                    end repeat
                                end if
                            end try
                        end repeat
                    end try
                end tell
            end tell
            """
            let (aboutClickOutput, aboutClickCode) = runCommand("osascript -e '\(clickAboutScript1)' || osascript -e '\(clickAboutScript2)'")
            if aboutClickCode == 0 {
                print("  ✅ Clicked About menu item via AppleScript")
            } else {
                print("  ⚠️  AppleScript failed: \(aboutClickOutput)")
            }
        }
        
            Thread.sleep(forTimeInterval: 1.5) // Give About window time to appear
        } else {
            print("  ⚠️  Could not open menu for About")
        }
    }
    
    // Try multiple title variations - wait longer since window might take time to appear
    let aboutTitles = locale == "ja" ? ["このアプリについて", "About"] : ["About", "このアプリについて"]
    print("  🔍 Waiting for About window to appear...")
    // aboutWindowID already declared above
    for title in aboutTitles {
        if let id = waitForWindow(withTitleContains: title, timeout: 5.0) {
            aboutWindowID = id
            print("  ✅ Found About window by title: \(title)")
            break
        }
    }
    
    // Fallback: Look for any NSPanel window (About uses NSPanel with layer .statusBar = 25)
    // About window is 480x260, layer 25
    if aboutWindowID == nil {
        print("  🔍 Title search failed, looking for About-like window by characteristics...")
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        print("  🔍 Checking \(windowList.count) windows for About window...")
        for windowInfo in windowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let layer = windowInfo[kCGWindowLayer as String] as? Int,
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                let name = windowInfo[kCGWindowName as String] as? String ?? ""
                // About window: layer 25 (statusBar), size ~480x260, not the menu (menu is ~227x198)
                // Also exclude Settings window (layer 0)
                if layer == 25 && width > 400 && width < 600 && height > 200 && height < 400 && height > 250 {
                    print("  🔍 Found candidate About window: id=\(windowID) layer=\(layer) size=\(Int(width))x\(Int(height)) name='\(name)'")
                    aboutWindowID = windowID
                    break
                }
            }
        }
        
        // If still not found, list all layer 25 windows for debugging
        if aboutWindowID == nil {
            print("  🔍 No About window found. Listing all layer 25 windows:")
            for windowInfo in windowList {
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                   (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
                   let layer = windowInfo[kCGWindowLayer as String] as? Int,
                   layer == 25 {
                    let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID ?? 0
                    let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    let width = bounds["Width"] as? CGFloat ?? 0
                    let height = bounds["Height"] as? CGFloat ?? 0
                    let name = windowInfo[kCGWindowName as String] as? String ?? ""
                    print("    - id=\(windowID) size=\(Int(width))x\(Int(height)) name='\(name)'")
                }
            }
        }
    }
    
    if let windowID = aboutWindowID {
        let aboutPath = "\(localeDir)/about.png"
        if captureWindow(windowID, to: aboutPath) {
            print("  ✅ Saved: \(aboutPath)")
        } else {
            print("  ❌ Failed to capture About")
        }
        // Close About window - try multiple methods to ensure it's closed
        print("  🔒 Closing About window...")
        closeWindow() // Cmd+W
        Thread.sleep(forTimeInterval: 0.5)
        closeDialog() // Escape (in case Cmd+W didn't work)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify About window is actually closed
        var aboutStillOpen = false
        let verifyWindowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for windowInfo in verifyWindowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let layer = windowInfo[kCGWindowLayer as String] as? Int,
               layer == 25,
               let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat,
               width > 400 && height > 200 { // About window size
                aboutStillOpen = true
                print("  ⚠️  About window still appears to be open (layer=\(layer), size=\(Int(width))x\(Int(height)))")
                break
            }
        }
        if !aboutStillOpen {
            print("  ✅ About window confirmed closed")
        }
    } else {
        print("  ❌ About window not found")
        // Don't hang - the window might not be opening, continue with dialogs
    }
    Thread.sleep(forTimeInterval: 1.0) // Extra wait to ensure About is fully closed
    }
    
    // Capture dialogs
    // First, ensure all windows are closed before starting dialogs
    print("\n🔒 Ensuring all windows are closed before capturing dialogs...")
    closeDialog()
    closeWindow()
    Thread.sleep(forTimeInterval: 1.0)
    
    // Verify no layer 25 windows are open (dialogs/About use this layer)
    let preDialogWindowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    var openLayer25Windows: [(id: CGWindowID, name: String, size: String)] = []
    for windowInfo in preDialogWindowList {
        if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
           (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
           let layer = windowInfo[kCGWindowLayer as String] as? Int,
           layer == 25,
           let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
           let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
           let width = bounds["Width"] as? CGFloat,
           let height = bounds["Height"] as? CGFloat {
            let name = windowInfo[kCGWindowName as String] as? String ?? ""
            openLayer25Windows.append((id: windowID, name: name, size: "\(Int(width))x\(Int(height))"))
        }
    }
    if !openLayer25Windows.isEmpty {
        print("  ⚠️  Found \(openLayer25Windows.count) open layer 25 window(s), attempting to close:")
        for win in openLayer25Windows {
            print("    - id=\(win.id) name='\(win.name)' size=\(win.size)")
        }
        // Try to close them more aggressively
        for _ in 0..<3 {
            closeDialog()
            closeWindow()
            Thread.sleep(forTimeInterval: 0.5)
        }
    } else {
        print("  ✅ No layer 25 windows open, ready for dialogs")
    }
    Thread.sleep(forTimeInterval: 1.0)
    
    // Filter dialogs if a specific one is requested
    let dialogsToCapture: [ScreenshotDialogKind]
    if let filter = filter {
        // Check if filter matches a dialog kind
        if let matchingKind = ScreenshotDialogKind.allCases.first(where: { $0.rawValue == filter }) {
            dialogsToCapture = [matchingKind]
        } else {
            // Filter doesn't match any dialog, skip all dialogs
            dialogsToCapture = []
        }
    } else {
        // No filter, capture all dialogs
        dialogsToCapture = ScreenshotDialogKind.allCases
    }
    
    for dialogKind in dialogsToCapture {
        print("\n💬 Capturing \(dialogKind.rawValue)...")
        // Close any open windows/dialogs first
        closeDialog()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Ensure screenshot mode is enabled before triggering
        _ = runCommand("defaults write \(bundleID) JokerOfTimeScreenshotMode -bool true")
        Thread.sleep(forTimeInterval: 0.3)
        
        // Verify screenshot mode is set
        let (verifyOutput, _) = runCommand("defaults read \(bundleID) JokerOfTimeScreenshotMode 2>/dev/null || echo '0'")
        let isEnabled = verifyOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        if !isEnabled {
            print("  ⚠️  Warning: Screenshot mode verification failed, but continuing...")
        }
        
        triggerDialog(dialogKind)
        Thread.sleep(forTimeInterval: 3.0) // Give dialog more time to appear and render
        
        // Find the dialog window by looking for NSPanel windows owned by JokerOfTime
        var dialogWindowID: CGWindowID?
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        print("  🔍 Searching for dialog window... Found \(windowList.count) windows")
        
        // Prompts use NSPanel with level .statusBar (layer 25), size 420x220
        // Window titles: "Joker of Time", "Clock In", or "Clock Out" (localized)
        let expectedTitles = locale == "ja" 
            ? ["Joker of Time", "出勤", "退勤"] 
            : ["Joker of Time", "Clock In", "Clock Out"]
        
        // Method 1: Look for windows by title first (most reliable)
        for windowInfo in windowList {
            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
               (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
               let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               let windowName = windowInfo[kCGWindowName as String] as? String,
               !windowName.isEmpty {
                for expectedTitle in expectedTitles {
                    if windowName.contains(expectedTitle) || windowName == expectedTitle {
                        print("  ✅ Found dialog window by title: '\(windowName)' id=\(windowID)")
                        dialogWindowID = windowID
                        break
                    }
                }
                if dialogWindowID != nil { break }
            }
        }
        
        // Method 2: Look by layer and size (fallback if title search fails)
        if dialogWindowID == nil {
            print("  🔍 Title search failed, looking by layer and size...")
            var candidateDialogs: [(id: CGWindowID, layer: Int, width: CGFloat, height: CGFloat, name: String)] = []
            for windowInfo in windowList {
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                   (ownerName == "Joker of Time" || ownerName == "JokerOfTime"),
                   let layer = windowInfo[kCGWindowLayer as String] as? Int,
                   let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                   let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                   let width = bounds["Width"] as? CGFloat,
                   let height = bounds["Height"] as? CGFloat {
                    let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
                    // Dialogs: layer 25 (statusBar level) with size ~420x220 (not menu which is ~227x198)
                    // Also check layer 0 (normal windows) in case dialogs use different level
                    if (layer == 25 || layer == 0) && width > 300 && width < 600 && height > 150 && height < 350 {
                        candidateDialogs.append((id: windowID, layer: layer, width: width, height: height, name: windowName))
                        print("  🔍 Found candidate dialog window: layer=\(layer) size=\(Int(width))x\(Int(height)) name='\(windowName)' id=\(windowID)")
                    }
                }
            }
            // Prefer layer 25 (statusBar) dialogs, but accept layer 0 if that's all we have
            if let dialog = candidateDialogs.first(where: { $0.layer == 25 }) ?? candidateDialogs.first {
                dialogWindowID = dialog.id
                print("  ✅ Using dialog window ID: \(dialog.id) (layer=\(dialog.layer), size=\(Int(dialog.width))x\(Int(dialog.height)))")
            }
        }
        
        if dialogWindowID == nil {
            print("  ⚠️  No dialog window found. Listing all Joker of Time windows:")
            for windowInfo in windowList {
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                   (ownerName == "Joker of Time" || ownerName == "JokerOfTime") {
                    let windowName = windowInfo[kCGWindowName as String] as? String ?? "(no name)"
                    let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
                    let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID ?? 0
                    print("    - name='\(windowName)' layer=\(layer) id=\(windowID)")
                }
            }
        }
        
        if let windowID = dialogWindowID {
            let dialogPath = "\(localeDir)/\(dialogKind.rawValue).png"
            if captureWindow(windowID, to: dialogPath) {
                print("  ✅ Saved: \(dialogPath)")
            } else {
                print("  ❌ Failed to capture \(dialogKind.rawValue)")
            }
            closeDialog() // Dialogs use Escape, not Cmd+W
        } else {
            print("  ⚠️  Dialog window not found for \(dialogKind.rawValue)")
            // Don't hang - continue with next dialog
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Quit app
    print("\n🛑 Quitting app...")
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
        app.terminate()
    }
    Thread.sleep(forTimeInterval: 2.0)
    
    // Clean up: disable screenshot mode
    let (_, _) = runCommand("defaults delete \(bundleID) JokerOfTimeScreenshotMode 2>/dev/null || true")
}

// MARK: - Permission Checks

func checkAccessibilityPermissions() -> Bool {
    // Check if we can use AppleScript to control System Events
    let testScript = """
    tell application "System Events"
        get name of every process
    end tell
    """
    let (_, exitCode) = runCommand("osascript -e '\(testScript)'")
    if exitCode != 0 {
        print("⚠️  Accessibility permissions required!")
        print("")
        print("This script needs Accessibility permissions to:")
        print("  • Control the app via AppleScript")
        print("")
        print("To grant permissions:")
        print("  1. Open System Settings (or System Preferences)")
        print("  2. Go to Privacy & Security > Accessibility")
        print("  3. Click the + button and add:")
        print("     • Terminal (if running from Terminal)")
        print("     • Cursor (if running from Cursor)")
        print("     • Or the app you're using to run this script")
        print("  4. Make sure it's enabled (checkbox checked)")
        print("")
        print("Alternatively, you can run:")
        print("  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
        print("")
        return false
    }
    return true
}

func checkScreenRecordingPermissions() -> Bool {
    // Check if screencapture works (requires Screen Recording permissions)
    let (output, exitCode) = runCommand("screencapture -x /tmp/test-screen-permissions.png 2>&1")
    if exitCode != 0 && output.contains("could not create image") {
        print("⚠️  Screen Recording permissions required!")
        print("")
        print("This script needs Screen Recording permissions to capture windows.")
        print("")
        print("To grant permissions:")
        print("  1. Open System Settings (or System Preferences)")
        print("  2. Go to Privacy & Security > Screen Recording")
        print("  3. Click the + button and add:")
        print("     • Terminal (if running from Terminal)")
        print("     • Cursor (if running from Cursor)")
        print("     • Or the app you're using to run this script")
        print("  4. Make sure it's enabled (checkbox checked)")
        print("")
        print("Alternatively, you can run:")
        print("  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'")
        print("")
        // Clean up test file
        _ = runCommand("rm -f /tmp/test-screen-permissions.png")
        return false
    }
    // Clean up test file
    _ = runCommand("rm -f /tmp/test-screen-permissions.png")
    return true
}

// MARK: - Main

print("🎬 Starting screenshot capture automation")
print(String(repeating: "=", count: 50))

// Check permissions first
if !checkAccessibilityPermissions() {
    print("❌ Missing required permissions. Please grant Accessibility access and try again.")
    exit(1)
}

if !checkScreenRecordingPermissions() {
    print("❌ Missing required permissions. Please grant Screen Recording access and try again.")
    exit(1)
}

// Create screenshots directory
let fileManager = FileManager.default
let currentDir = fileManager.currentDirectoryPath
let screenshotsPath = "\(currentDir)/\(screenshotsDir)"
do {
    try fileManager.createDirectory(atPath: screenshotsPath, withIntermediateDirectories: true)
} catch {
    print("❌ Failed to create screenshots directory: \(error)")
    exit(1)
}

// Parse command-line arguments
let args = CommandLine.arguments
var filter: String? = nil
var targetLocales = locales

if args.count > 1 {
    let firstArg = args[1]
    // Check if it's a dialog kind or window name
    if ScreenshotDialogKind.allCases.contains(where: { $0.rawValue == firstArg }) {
        filter = firstArg
        print("📸 Filter: capturing only '\(firstArg)' dialog")
    } else if firstArg == "menu" || firstArg == "settings" || firstArg == "about" {
        filter = firstArg
        print("📸 Filter: capturing only '\(firstArg)' window")
    } else if firstArg == "--help" || firstArg == "-h" {
        print("Usage: \(args[0]) [dialog-name|window-name]")
        print("\nAvailable dialogs:")
        for kind in ScreenshotDialogKind.allCases {
            print("  - \(kind.rawValue)")
        }
        print("\nAvailable windows:")
        print("  - menu")
        print("  - settings")
        print("  - about")
        print("\nExamples:")
        print("  \(args[0])                    # Capture all screenshots")
        print("  \(args[0]) node-not-found      # Capture only node-not-found dialog")
        print("  \(args[0]) settings            # Capture only Settings window")
        exit(0)
    } else {
        print("⚠️  Unknown filter: '\(firstArg)'")
        print("Run with --help to see available options")
        exit(1)
    }
}

// Capture for each locale
for locale in targetLocales {
    captureScreenshots(for: locale, filter: filter)
}

// Clean up: reset locale to system default
print("\n🧹 Cleaning up...")
let (_, _) = runCommand("defaults delete \(bundleID) AppleLanguages 2>/dev/null || true")
let (_, _) = runCommand("defaults delete \(bundleID) JokerOfTimeScreenshotMode 2>/dev/null || true")

print("\n✅ Screenshot capture complete!")
print("📁 Screenshots saved to: \(screenshotsPath)/")
