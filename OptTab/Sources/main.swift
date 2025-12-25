import Carbon
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var appSwitcher: AppSwitcher?
    var eventMonitor: EventMonitor?
    var permissionTimer: Timer?
    var useColoredIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "useColoredIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "useColoredIcon") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permissions first WITHOUT showing prompt
        let accessibilityEnabled = AXIsProcessTrusted()

        if !accessibilityEnabled {
            // Only show prompt if permission is not granted
            let options: NSDictionary = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ]
            _ = AXIsProcessTrustedWithOptions(options)
            print("")
            print("⚠️  ⚠️  ⚠️  ACCESSIBILITY PERMISSION REQUIRED ⚠️  ⚠️  ⚠️")
            print("")
            print("📋 Steps to enable:")
            print("   1. Open System Settings")
            print("   2. Go to Privacy & Security → Accessibility")
            print("   3. Click the '+' button or toggle ON for OptTab")
            print("   4. Restart this app")
            print("")
            print(
                "💡 App will continue running but won't capture Option+Tab until permission is granted."
            )
            print("")

            // Keep checking periodically
            checkPermissionsTimer()
        } else {
            print("✅ Accessibility permissions granted!")
        }

        // Check Screen Recording permission (for thumbnails)
        checkScreenRecordingPermission()

        // Initialize app switcher
        appSwitcher = AppSwitcher()

        // Setup global hotkey - monitor both keyDown AND flagsChanged
        // This ensures we catch Option press before Tab
        eventMonitor = EventMonitor(mask: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // For keyDown events
            if event.type == .keyDown {
                // Check for Tab when Option is held
                if event.modifierFlags.contains(.option) && event.keyCode == 48 {  // 48 = Tab
                    self.appSwitcher?.show()
                    return nil  // Consume the event
                }

                // Check for Q when Option is held (Opt+Q to minimize)
                if event.modifierFlags.contains(.option) && event.keyCode == 12 {  // 12 = Q
                    self.appSwitcher?.minimizeCurrentWindow()
                    return nil  // Consume the event
                }
            }

            return event
        }
        eventMonitor?.start()

        // Create menu bar icon (optional - for easy quit)
        setupMenuBar()

        print("")
        print("✅ OptTab started. Press Option+Tab to switch apps.")
        print("✅ Press Option+Q to minimize current window.")
        print("📍 Menu bar icon is in the top-right corner")
        print("")
    }

    func checkPermissionsTimer() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] timer in
            let accessibilityEnabled = AXIsProcessTrusted()
            if accessibilityEnabled {
                print("")
                print("✅ ✅ ✅ Accessibility permission granted! Option+Tab now active! ✅ ✅ ✅")
                print("")
                timer.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up timer to prevent memory leak
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func checkScreenRecordingPermission() {
        // Check if we already have screen recording permission
        let hasPermission = CGPreflightScreenCaptureAccess()

        if !hasPermission {
            // Request permission by actually attempting to capture
            // This triggers the system to add the app to Privacy & Security list
            print("")
            print("🎬 Requesting Screen Recording permission for thumbnails...")
            print("")

            // Attempt a dummy screen capture to trigger permission dialog
            // This will automatically add the app to System Settings > Privacy & Security > Screen Recording
            _ = NSScreen.main?.frame ?? .zero
            if CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            ) != nil {
                // Successfully captured (permission already granted)
                print("✅ Screen Recording permission granted! Thumbnails enabled.")
            } else {
                // Failed to capture - permission dialog should appear
                print("")
                print("⚠️  SCREEN RECORDING PERMISSION NEEDED FOR THUMBNAILS")
                print("")
                print("📋 To show window thumbnails:")
                print("   1. System Settings should open automatically")
                print("   2. Go to Privacy & Security → Screen Recording")
                print("   3. Toggle ON for OptTab")
                print("   4. Restart this app")
                print("")
                print("💡 App will work without thumbnails, but icons only.")
                print("")
            }
        } else {
            print("✅ Screen Recording permission granted! Thumbnails enabled.")
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateMenuBarIcon()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About OptTab", action: #selector(about), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let iconMenuItem = NSMenuItem(
            title: "Use Colored Icon", action: #selector(toggleIconStyle), keyEquivalent: "")
        iconMenuItem.state = useColoredIcon ? .on : .off
        menu.addItem(iconMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OptTab", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        if useColoredIcon {
            // Use colored icon (non-template) - load from AppIcon.png
            if let coloredIcon = generateColoredMenuBarIcon() {
                button.image = coloredIcon
            } else {
                // Fallback to template if file not found
                if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png") {
                    button.image = NSImage(contentsOfFile: iconPath)
                } else {
                    button.image = NSImage(
                        systemSymbolName: "square.grid.2x2", accessibilityDescription: "OptTab")
                }
            }
        } else {
            // Use template icon (black/white auto-adapt)
            if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
                let templateIcon = NSImage(contentsOfFile: iconPath)
            {
                templateIcon.isTemplate = true
                button.image = templateIcon
            } else {
                button.image = NSImage(
                    systemSymbolName: "square.grid.2x2", accessibilityDescription: "OptTab")
            }
        }
    }

    func generateColoredMenuBarIcon() -> NSImage? {
        // Load app icon and resize to menu bar size
        guard let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
            let appIcon = NSImage(contentsOfFile: iconPath)
        else {
            return nil
        }

        let size = NSSize(width: 22, height: 22)
        let resizedIcon = NSImage(size: size)

        resizedIcon.lockFocus()
        appIcon.draw(in: NSRect(origin: .zero, size: size))
        resizedIcon.unlockFocus()

        resizedIcon.isTemplate = false  // NOT template for colored version

        return resizedIcon
    }

    @objc func toggleIconStyle() {
        useColoredIcon.toggle()
        updateMenuBarIcon()

        // Update menu item state
        if let menu = statusItem?.menu {
            for item in menu.items {
                if item.action == #selector(toggleIconStyle) {
                    item.state = useColoredIcon ? .on : .off
                    break
                }
            }
        }
    }

    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "OptTab"
        alert.informativeText =
            "Lightweight Alt+Tab replacement for macOS\n\nShortcuts:\n• Option+Tab - Switch apps\n• Option+Q - Minimize window\n\nVersion: 1.0.0"
        alert.alertStyle = .informational

        // Try to load app icon
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
            let appIcon = NSImage(contentsOfFile: iconPath)
        {
            alert.icon = appIcon
        }

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Don't show in Dock
app.run()
