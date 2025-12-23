import Carbon
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var appSwitcher: AppSwitcher?
    var eventMonitor: EventMonitor?
    var useColoredIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "useColoredIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "useColoredIcon") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessibilityEnabled {
            print("")
            print("⚠️  ⚠️  ⚠️  ACCESSIBILITY PERMISSION REQUIRED ⚠️  ⚠️  ⚠️")
            print("")
            print("📋 Steps to enable:")
            print("   1. Open System Settings")
            print("   2. Go to Privacy & Security → Accessibility")
            print("   3. Click the '+' button or toggle ON for Terminal")
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
            }

            return event
        }
        eventMonitor?.start()

        // Create menu bar icon (optional - for easy quit)
        setupMenuBar()

        print("")
        print("✅ OptTab started. Press Option+Tab to switch apps.")
        print("📍 Menu bar icon is in the top-right corner")
        print("")
    }

    func checkPermissionsTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            let accessibilityEnabled = AXIsProcessTrusted()
            if accessibilityEnabled {
                print("")
                print("✅ ✅ ✅ Accessibility permission granted! Option+Tab now active! ✅ ✅ ✅")
                print("")
                timer.invalidate()
            }
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
                button.image = NSImage(contentsOfFile: "OptTab/Resources/MenuBarIcon.png")
            }
        } else {
            // Use template icon (black/white auto-adapt)
            if let templateIcon = NSImage(contentsOfFile: "OptTab/Resources/MenuBarIcon.png") {
                button.image = templateIcon
            } else {
                button.image = NSImage(
                    systemSymbolName: "square.grid.2x2", accessibilityDescription: "OptTab")
            }
        }
    }

    func generateColoredMenuBarIcon() -> NSImage? {
        // Load app icon and resize to menu bar size
        guard let appIcon = NSImage(contentsOfFile: "OptTab/Resources/AppIcon.png") else {
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
            "Lightweight Alt+Tab replacement for macOS\n\nShortcut: Option+Tab\nVersion: 1.0.0"
        alert.alertStyle = .informational

        // Try to load app icon
        if let appIcon = NSImage(contentsOfFile: "OptTab/Resources/AppIcon.png") {
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
