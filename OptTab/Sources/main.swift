import Carbon
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var appSwitcher: AppSwitcher?
    var eventMonitor: EventMonitor?
    var permissionTimer: Timer?
    var preferencesWindow: NSWindow?
    var isRecordingKey: Bool = false
    var recordingField: NSTextField?
    var keyRecordingMonitor: Any?

    var useColoredIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "useColoredIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "useColoredIcon") }
    }

    // Keybinding settings with defaults
    var switcherModifier: NSEvent.ModifierFlags {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "switcherModifier")
            return rawValue == 0 ? .option : NSEvent.ModifierFlags(rawValue: UInt(rawValue))
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "switcherModifier") }
    }

    var switcherKey: UInt16 {
        get {
            let value = UserDefaults.standard.integer(forKey: "switcherKey")
            return value == 0 ? 48 : UInt16(value)  // 48 = Tab
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "switcherKey") }
    }

    var minimizeModifier: NSEvent.ModifierFlags {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "minimizeModifier")
            return rawValue == 0 ? .option : NSEvent.ModifierFlags(rawValue: UInt(rawValue))
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "minimizeModifier") }
    }

    var minimizeKey: UInt16 {
        get {
            let value = UserDefaults.standard.integer(forKey: "minimizeKey")
            return value == 0 ? 12 : UInt16(value)  // 12 = Q
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "minimizeKey") }
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

        // Setup global hotkey with custom keybindings
        setupEventMonitor()
        eventMonitor?.start()

        // Create menu bar icon (optional - for easy quit)
        setupMenuBar()

        print("")
        print("✅ OptTab started.")
        print("✅ Switcher: \(modifierToString(switcherModifier))+\(keyCodeToString(switcherKey))")
        print("✅ Minimize: \(modifierToString(minimizeModifier))+\(keyCodeToString(minimizeKey))")
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

    func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // For keyDown events
            if event.type == .keyDown {
                // Check for switcher keybinding
                if event.modifierFlags.contains(self.switcherModifier)
                    && event.keyCode == self.switcherKey
                {
                    self.appSwitcher?.show()
                    return nil  // Consume the event
                }

                // Check for minimize keybinding
                if event.modifierFlags.contains(self.minimizeModifier)
                    && event.keyCode == self.minimizeKey
                {
                    self.appSwitcher?.minimizeCurrentWindow()
                    return nil  // Consume the event
                }
            }

            return event
        }
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

        menu.addItem(
            NSMenuItem(
                title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
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

    func stopKeyRecording() {
        // Stop any existing recording
        if let monitor = keyRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            keyRecordingMonitor = nil
        }

        // Reset recording state
        isRecordingKey = false

        // Reset any field that was recording
        if let field = recordingField {
            if field.tag == 1 {
                field.stringValue =
                    "\(modifierToString(switcherModifier)) + \(keyCodeToString(switcherKey))"
            } else if field.tag == 2 {
                field.stringValue =
                    "\(modifierToString(minimizeModifier)) + \(keyCodeToString(minimizeKey))"
            }
            field.textColor = .labelColor
        }
        recordingField = nil
    }

    @objc func showPreferences() {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Disable global hotkeys while preferences window is open
            eventMonitor?.stop()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OptTab Preferences"
        window.center()

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))

        // Title
        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 250, width: 460, height: 30))
        titleLabel.stringValue = "Keyboard Shortcuts"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        contentView.addSubview(titleLabel)

        // Switcher keybinding
        let switcherLabel = NSTextField(frame: NSRect(x: 20, y: 200, width: 150, height: 24))
        switcherLabel.stringValue = "App Switcher:"
        switcherLabel.isEditable = false
        switcherLabel.isBordered = false
        switcherLabel.backgroundColor = .clear
        switcherLabel.alignment = .right
        contentView.addSubview(switcherLabel)

        let switcherField = NSTextField(frame: NSRect(x: 180, y: 200, width: 250, height: 24))
        switcherField.stringValue =
            "\(modifierToString(switcherModifier)) + \(keyCodeToString(switcherKey))"
        switcherField.isEditable = false
        switcherField.isBordered = true
        switcherField.alignment = .center
        switcherField.tag = 1
        contentView.addSubview(switcherField)

        let switcherButton = NSButton(frame: NSRect(x: 440, y: 198, width: 40, height: 28))
        switcherButton.title = "Set"
        switcherButton.bezelStyle = .rounded
        switcherButton.target = self
        switcherButton.action = #selector(recordSwitcherKey(_:))
        contentView.addSubview(switcherButton)

        // Minimize keybinding
        let minimizeLabel = NSTextField(frame: NSRect(x: 20, y: 160, width: 150, height: 24))
        minimizeLabel.stringValue = "Minimize Window:"
        minimizeLabel.isEditable = false
        minimizeLabel.isBordered = false
        minimizeLabel.backgroundColor = .clear
        minimizeLabel.alignment = .right
        contentView.addSubview(minimizeLabel)

        let minimizeField = NSTextField(frame: NSRect(x: 180, y: 160, width: 250, height: 24))
        minimizeField.stringValue =
            "\(modifierToString(minimizeModifier)) + \(keyCodeToString(minimizeKey))"
        minimizeField.isEditable = false
        minimizeField.isBordered = true
        minimizeField.alignment = .center
        minimizeField.tag = 2
        contentView.addSubview(minimizeField)

        let minimizeButton = NSButton(frame: NSRect(x: 440, y: 158, width: 40, height: 28))
        minimizeButton.title = "Set"
        minimizeButton.bezelStyle = .rounded
        minimizeButton.target = self
        minimizeButton.action = #selector(recordMinimizeKey(_:))
        contentView.addSubview(minimizeButton)

        // Instructions
        let instructionLabel = NSTextField(frame: NSRect(x: 20, y: 100, width: 460, height: 50))
        instructionLabel.stringValue =
            "Click 'Set' and press your desired key combination.\nSupported modifiers: ⌘ Command, ⌥ Option, ⌃ Control, ⇧ Shift"
        instructionLabel.isEditable = false
        instructionLabel.isBordered = false
        instructionLabel.backgroundColor = .clear
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.lineBreakMode = .byWordWrapping
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.cell?.wraps = true
        contentView.addSubview(instructionLabel)

        // Reset button
        let resetButton = NSButton(frame: NSRect(x: 180, y: 40, width: 140, height: 32))
        resetButton.title = "Reset to Defaults"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetKeybindings)
        contentView.addSubview(resetButton)

        window.contentView = contentView

        // Setup window delegate to handle close event
        let windowDelegate = PreferencesWindowDelegate(appDelegate: self)
        window.delegate = windowDelegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Disable global hotkeys while preferences window is open
        eventMonitor?.stop()

        preferencesWindow = window
    }

    func closePreferences() {
        // Stop any active recording
        stopKeyRecording()

        // Re-enable global hotkeys
        eventMonitor?.start()

        preferencesWindow?.close()
        preferencesWindow = nil
    }

    @objc func recordSwitcherKey(_ sender: NSButton) {
        guard let window = preferencesWindow,
            let field = window.contentView?.viewWithTag(1) as? NSTextField
        else { return }

        // Stop any previous recording and reset state
        stopKeyRecording()

        field.stringValue = "Press keys..."
        field.textColor = .systemBlue
        recordingField = field
        isRecordingKey = true

        // Make field first responder to show it's focused
        window.makeFirstResponder(field)

        // Monitor for key press
        keyRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.isRecordingKey else { return event }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !modifiers.isEmpty {  // Only require a modifier, allow any key
                self.switcherModifier = modifiers
                self.switcherKey = event.keyCode

                field.stringValue =
                    "\(self.modifierToString(modifiers)) + \(self.keyCodeToString(event.keyCode))"
                field.textColor = .labelColor
                self.isRecordingKey = false
                self.recordingField = nil

                // Remove key recording monitor
                if let monitor = self.keyRecordingMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.keyRecordingMonitor = nil
                }

                // Restart event monitor with new keybindings
                self.eventMonitor?.stop()
                self.setupEventMonitor()
                self.eventMonitor?.start()

                print(
                    "✅ Switcher keybinding updated: \(self.modifierToString(modifiers))+\(self.keyCodeToString(event.keyCode))"
                )
            }

            return nil
        }
    }

    @objc func recordMinimizeKey(_ sender: NSButton) {
        guard let window = preferencesWindow,
            let field = window.contentView?.viewWithTag(2) as? NSTextField
        else { return }

        // Stop any previous recording and reset state
        stopKeyRecording()

        field.stringValue = "Press keys..."
        field.textColor = .systemBlue
        recordingField = field
        isRecordingKey = true

        // Make field first responder to show it's focused
        window.makeFirstResponder(field)

        // Monitor for key press
        keyRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.isRecordingKey else { return event }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !modifiers.isEmpty {  // Only require a modifier, allow any key
                self.minimizeModifier = modifiers
                self.minimizeKey = event.keyCode

                field.stringValue =
                    "\(self.modifierToString(modifiers)) + \(self.keyCodeToString(event.keyCode))"
                field.textColor = .labelColor
                self.isRecordingKey = false
                self.recordingField = nil

                // Remove key recording monitor
                if let monitor = self.keyRecordingMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.keyRecordingMonitor = nil
                }

                // Restart event monitor with new keybindings
                self.eventMonitor?.stop()
                self.setupEventMonitor()
                self.eventMonitor?.start()

                print(
                    "✅ Minimize keybinding updated: \(self.modifierToString(modifiers))+\(self.keyCodeToString(event.keyCode))"
                )
            }

            return nil
        }
    }

    @objc func resetKeybindings() {
        switcherModifier = .option
        switcherKey = 48  // Tab
        minimizeModifier = .option
        minimizeKey = 12  // Q

        // Update UI
        if let window = preferencesWindow {
            if let field = window.contentView?.viewWithTag(1) as? NSTextField {
                field.stringValue =
                    "\(modifierToString(switcherModifier)) + \(keyCodeToString(switcherKey))"
            }
            if let field = window.contentView?.viewWithTag(2) as? NSTextField {
                field.stringValue =
                    "\(modifierToString(minimizeModifier)) + \(keyCodeToString(minimizeKey))"
            }
        }

        // Restart event monitor
        eventMonitor?.stop()
        setupEventMonitor()
        eventMonitor?.start()

        print("✅ Keybindings reset to defaults")
    }

    func modifierToString(_ modifier: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifier.contains(.command) { result += "⌘" }
        if modifier.contains(.option) { result += "⌥" }
        if modifier.contains(.control) { result += "⌃" }
        if modifier.contains(.shift) { result += "⇧" }
        return result.isEmpty ? "None" : result
    }

    func keyCodeToString(_ keyCode: UInt16) -> String {
        // Common key codes
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 45: return "N"
        case 46: return "M"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 122: return "F1"
        case 120: return "F2"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
    }

    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "OptTab"
        alert.informativeText =
            "Lightweight Alt+Tab replacement for macOS\n\nCurrent Shortcuts:\n• \(modifierToString(switcherModifier))+\(keyCodeToString(switcherKey)) - Switch apps\n• \(modifierToString(minimizeModifier))+\(keyCodeToString(minimizeKey)) - Minimize window\n\nVersion: 1.0.0"
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

// Window delegate to handle preferences window close
class PreferencesWindowDelegate: NSObject, NSWindowDelegate {
    weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func windowWillClose(_ notification: Notification) {
        // Stop any active recording
        appDelegate?.stopKeyRecording()

        // Re-enable global hotkeys
        appDelegate?.eventMonitor?.start()

        // Clear reference
        appDelegate?.preferencesWindow = nil
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Don't show in Dock
app.run()
