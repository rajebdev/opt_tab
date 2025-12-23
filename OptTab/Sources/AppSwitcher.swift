import ApplicationServices
import Cocoa

class AppSwitcher {
    private var window: NSWindow?
    private var collectionView: NSCollectionView?
    private var windows: [WindowInfo] = []
    private var selectedIndex: Int = 0
    private var isShowing: Bool = false
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?

    struct WindowInfo {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let ownerName: String
        let windowTitle: String
        let originalAXTitle: String  // Original title dari AX API untuk matching
        let thumbnail: NSImage
        let appIcon: NSImage
        let bounds: CGRect
    }

    func show() {
        guard !isShowing else {
            // Already showing, just cycle to next app
            selectNext()
            return
        }

        isShowing = true

        // Get all windows
        windows = getAllWindows()

        // Limit to 16 windows to reduce WindowServer memory usage
        if windows.count > 16 {
            windows = Array(windows.prefix(16))
        }

        print("🪟 Found \(windows.count) windows:")
        for (i, win) in windows.enumerated() {
            print("  [\(i)] \(win.ownerName) - \(win.windowTitle)")
            print("      → Original AX: [\(win.originalAXTitle)], WindowID: \(win.windowID)")
        }

        if windows.count <= 1 {
            isShowing = false
            return
        }

        // Select the second window (first after current)
        selectedIndex = 1

        // Show window
        showWindow()
        // Setup key monitoring
        setupKeyMonitoring()
    }

    func hide() {
        guard isShowing else { return }

        print("🔄 Switching to index [\(selectedIndex)]: \(windows[selectedIndex].windowTitle)")
        print("      → Original AX title: [\(windows[selectedIndex].originalAXTitle)]")
        print("      → WindowID: \(windows[selectedIndex].windowID)")

        // IMPORTANT: Capture selected window info BEFORE any async operations
        // to avoid race conditions where windows array might change
        let selectedWindowInfo = windows[selectedIndex]

        isShowing = false

        // Remove event monitors
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }

        // Hide window FIRST before activating the selected window
        window?.orderOut(nil)

        // Clear window content to free memory
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }

        // Small delay to ensure overlay is hidden before switching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Use captured window info directly
            self.activateWindow(windowInfo: selectedWindowInfo)

            // Clear windows array to release thumbnail memory
            self.windows.removeAll()
        }
    }

    private func getAllWindows() -> [WindowInfo] {
        var windowInfos: [WindowInfo] = []

        // Get running apps from Dock (regular apps only)
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Filter only apps that appear in Dock
        let dockApps = runningApps.filter { app in
            return app.activationPolicy == .regular
        }

        // Sort: current app first, then others
        let currentApp = workspace.frontmostApplication
        let sortedApps = dockApps.sorted { app1, app2 in
            if app1.processIdentifier == currentApp?.processIdentifier {
                return true
            }
            if app2.processIdentifier == currentApp?.processIdentifier {
                return false
            }
            return app1.localizedName ?? "" < app2.localizedName ?? ""
        }

        // For each app, get all its windows
        for app in sortedApps {
            guard let appIcon = app.icon else { continue }
            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier

            // Get windows for this app using AX API
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?

            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )

            if result == .success, let windows = windowsRef as? [AXUIElement] {
                for window in windows {
                    // Get window title
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

                    // Get the actual window title - don't use appName as fallback
                    guard let windowTitle = titleRef as? String, !windowTitle.isEmpty else {
                        // Skip windows without a title (system windows, etc.)
                        if appName.contains("Chrome") {
                            print("  [DEBUG] Skipping Chrome window with no title")
                        }
                        continue
                    }

                    // Debug for Chrome
                    if appName.contains("Chrome") {
                        print("  [DEBUG] Found Chrome window: [\(windowTitle)]")
                    }

                    // Check if minimized
                    var minimizedRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(
                        window, kAXMinimizedAttribute as CFString, &minimizedRef)
                    let isMinimized = (minimizedRef as? Bool) ?? false

                    // Get window position and size
                    var positionRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(
                        window, kAXPositionAttribute as CFString, &positionRef)
                    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

                    var point = CGPoint.zero
                    var size = CGSize.zero

                    if let positionRef = positionRef {
                        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
                    }
                    if let sizeRef = sizeRef {
                        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                    }

                    let bounds = CGRect(origin: point, size: size)

                    // Skip very small windows
                    guard size.width > 100 && size.height > 50 else { continue }

                    // Get window ID for thumbnail (try to find matching CGWindow)
                    var windowID: CGWindowID = 0
                    let options: CGWindowListOption = [.excludeDesktopElements]
                    if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                        as? [[String: Any]]
                    {
                        // Try to match by exact title
                        for windowDict in windowList {
                            if let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                                ownerPID == pid,
                                let wid = windowDict[kCGWindowNumber as String] as? CGWindowID
                            {
                                let windowName =
                                    windowDict[kCGWindowName as String] as? String ?? ""

                                // Only use exact title match - no fallback
                                if windowName == windowTitle {
                                    windowID = wid
                                    if appName.contains("Chrome") {
                                        print(
                                            "  [MAP] Chrome window '\(windowTitle)' -> ID: \(wid)")
                                    }
                                    break
                                }
                            }
                        }

                        // If no match found, log it
                        if windowID == 0 && appName.contains("Chrome") {
                            print(
                                "  [MAP] Chrome window '\(windowTitle)' -> NO MATCH (minimized: \(isMinimized))"
                            )
                        }
                    }

                    // Capture thumbnail (pass icon for fallback)
                    let thumbnail = captureWindowThumbnail(
                        windowID: windowID, bounds: bounds, isMinimized: isMinimized,
                        appIcon: appIcon)

                    // Format title - never show just app name
                    let prefix = isMinimized ? "🔽 " : ""
                    let displayTitle = prefix + "\(appName): \(windowTitle)"

                    // Validate before adding
                    if appName.contains("Chrome") {
                        print(
                            "  [ADD] Chrome: displayTitle='\(displayTitle)', originalAX='\(windowTitle)', ID=\(windowID)"
                        )
                    }

                    windowInfos.append(
                        WindowInfo(
                            windowID: windowID,
                            ownerPID: pid,
                            ownerName: appName,
                            windowTitle: displayTitle,
                            originalAXTitle: windowTitle,  // Store original AX title
                            thumbnail: thumbnail,
                            appIcon: appIcon,
                            bounds: bounds
                        ))
                }
            }
        }

        return windowInfos
    }

    private func captureWindowThumbnail(
        windowID: CGWindowID, bounds: CGRect, isMinimized: Bool, appIcon: NSImage
    ) -> NSImage {
        // Smaller thumbnail size to reduce WindowServer memory
        let targetWidth: CGFloat = 200
        let targetHeight: CGFloat = 100

        // For minimized windows or if windowID is 0, just use app icon
        if isMinimized {
            return createIconPlaceholder(
                width: targetWidth, height: targetHeight, icon: appIcon)
        }

        if windowID == 0 {
            return createIconPlaceholder(
                width: targetWidth, height: targetHeight, icon: appIcon)
        }

        // Use lower resolution to save memory
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .nominalResolution]

        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            options
        ), cgImage.width > 10, cgImage.height > 10 {
            // Convert to NSImage with proper scaling
            let image = NSImage(
                cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
            return image
        }

        // Return app icon placeholder if capture fails
        return createIconPlaceholder(width: targetWidth, height: targetHeight, icon: appIcon)
    }

    private func createIconPlaceholder(width: CGFloat, height: CGFloat, icon: NSImage)
        -> NSImage
    {
        let placeholder = NSImage(size: NSSize(width: width, height: height))
        placeholder.lockFocus()

        // Draw gradient background
        let gradient = NSGradient(
            colors: [
                NSColor(white: 0.25, alpha: 1.0),
                NSColor(white: 0.15, alpha: 1.0),
            ])
        gradient?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

        // Draw app icon in center (larger)
        let iconSize: CGFloat = 80
        let iconRect = NSRect(
            x: (width - iconSize) / 2,
            y: (height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        icon.draw(in: iconRect)

        placeholder.unlockFocus()
        return placeholder
    }

    private func showWindow() {
        // Always get the screen where mouse cursor is (active screen)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.frame

        if window == nil {
            createWindow(screen: screen)
            print("  → Window created")
        } else {
            // Update window frame to match current screen
            window?.setFrame(screenFrame, display: true)
        }

        updateWindowContent()

        // Window is already full screen, just ensure it's on the right screen
        window?.setFrameOrigin(NSPoint(x: screenFrame.origin.x, y: screenFrame.origin.y))
        print(
            "  → Window positioned at (\(screenFrame.origin.x), \(screenFrame.origin.y)) with size \(screenFrame.width)x\(screenFrame.height)"
        )

        window?.makeKeyAndOrderFront(nil)
        window?.level = .screenSaver  // Very high level to ensure visibility
        window?.orderFrontRegardless()
        print("  → Window should now be VISIBLE on screen!")
    }

    private func createWindow(screen: NSScreen) {
        // Get screen size for full screen overlay
        let screenFrame = screen.frame

        window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = NSColor.clear  // Transparan penuh
        window?.hasShadow = false
        window?.isMovableByWindowBackground = false
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Create content view - transparan juga
        let contentView = NSView(frame: window!.contentRect(forFrameRect: window!.frame))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        window?.contentView = contentView
    }

    private func updateWindowContent() {
        guard let contentView = window?.contentView else { return }

        // Clear existing subviews
        contentView.subviews.forEach { $0.removeFromSuperview() }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Grid layout settings
        let itemWidth: CGFloat = 280
        let itemHeight: CGFloat = 200
        let spacing: CGFloat = 30
        let padding: CGFloat = 20  // Padding di sekitar grid

        // Calculate grid dimensions
        let columns = 4
        let rows = Int(ceil(Double(windows.count) / Double(columns)))

        // Calculate total grid size
        let totalWidth = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * spacing
        let totalHeight = CGFloat(rows) * itemHeight + CGFloat(rows - 1) * spacing

        // Create background rect container dengan padding
        let containerWidth = totalWidth + (padding * 2)
        let containerHeight = totalHeight + (padding * 2)

        // Center container di tengah screen (bukan pakai offset +50)
        let containerX = (screenFrame.width - containerWidth) / 2
        let containerY = (screenFrame.height - containerHeight) / 2

        let containerView = NSView(
            frame: NSRect(
                x: containerX,
                y: containerY,
                width: containerWidth,
                height: containerHeight
            ))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        containerView.layer?.cornerRadius = 16
        contentView.addSubview(containerView)

        // Calculate starting position untuk grid (relatif terhadap screen)
        let startX = containerX + padding
        let startY = containerY + padding

        print("  → Displaying \(windows.count) windows in \(columns)x\(rows) grid")

        // Create window items in grid
        for (index, windowInfo) in windows.enumerated() {
            let col = index % columns
            let row = index / columns

            let x = startX + CGFloat(col) * (itemWidth + spacing)
            let y = startY + CGFloat(rows - 1 - row) * (itemHeight + spacing)

            let itemView = createWindowItemView(
                windowInfo: windowInfo, isSelected: index == selectedIndex)
            itemView.frame = NSRect(x: x, y: y, width: itemWidth, height: itemHeight)
            contentView.addSubview(itemView)
        }
    }

    private func createWindowItemView(windowInfo: WindowInfo, isSelected: Bool) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor =
            isSelected
            ? NSColor.systemBlue.withAlphaComponent(0.9).cgColor  // Solid untuk selected
            : NSColor(white: 0.2, alpha: 0.95).cgColor  // Solid dark grey untuk normal
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = isSelected ? 3 : 1
        view.layer?.borderColor =
            isSelected ? NSColor.systemBlue.cgColor : NSColor.white.withAlphaComponent(0.3).cgColor

        // Thumbnail (larger)
        let thumbnailView = NSImageView(frame: NSRect(x: 15, y: 60, width: 250, height: 120))
        thumbnailView.image = windowInfo.thumbnail
        thumbnailView.imageScaling = .scaleProportionallyDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.borderWidth = 1
        thumbnailView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        view.addSubview(thumbnailView)

        // App icon (larger)
        let iconView = NSImageView(frame: NSRect(x: 15, y: 15, width: 32, height: 32))
        iconView.image = windowInfo.appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(iconView)

        // Window title (larger and multi-line)
        let titleLabel = NSTextField(frame: NSRect(x: 52, y: 12, width: 213, height: 38))
        titleLabel.stringValue = windowInfo.windowTitle
        titleLabel.alignment = .left
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        view.addSubview(titleLabel)

        return view
    }

    private func selectNext() {
        selectedIndex = (selectedIndex + 1) % windows.count
        updateWindowContent()
    }

    private func selectPrevious() {
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        updateWindowContent()
    }

    private func setupKeyMonitoring() {
        // Monitor for Tab key (cycle through apps)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.isShowing else { return event }

            // Tab - next app (consume all Tab presses when showing)
            if event.keyCode == 48 {
                self.selectNext()
                return nil  // Always consume Tab when switcher is showing
            }

            // Escape - cancel
            if event.keyCode == 53 {
                print("❌ Cancelled")
                self.isShowing = false
                self.window?.orderOut(nil)
                return nil
            }

            // Consume all key events when switcher is showing to prevent them reaching other apps
            return nil
        }

        // Local monitor for modifier key changes
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard let self = self, self.isShowing else { return event }

            // Option key released
            if !event.modifierFlags.contains(.option) {
                print("⬇️  Option released (local)")
                self.hide()
                return nil
            }

            return event
        }

        // Global monitor for modifier key changes (backup)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard let self = self, self.isShowing else { return }

            // Option key released
            if !event.modifierFlags.contains(.option) {
                print("⬇️  Option released (global)")
                DispatchQueue.main.async {
                    self.hide()
                }
            }
        }
    }

    private func activateWindow(windowInfo: WindowInfo) {
        // Use original AX title for matching (no emoji or formatting)
        let targetTitle = windowInfo.originalAXTitle
        let isMinimized = windowInfo.windowTitle.contains("🔽")
        let pid = windowInfo.ownerPID
        let windowID = windowInfo.windowID

        print("  → Attempting to activate: [\(targetTitle)]")
        print("  → Display title: [\(windowInfo.windowTitle)]")
        print("  → WindowID: \(windowID)")
        print("  → Is minimized: \(isMinimized)")

        // For minimized windows, DON'T activate app first
        // This prevents Chrome from bringing the currently active window to front
        if isMinimized {
            print("  → Window is minimized - un-minimizing first WITHOUT app activation")
            self.raiseSpecificWindow(
                pid: pid, windowID: windowID, targetTitle: targetTitle, shouldActivateApp: false)
        } else {
            // For non-minimized windows, activate app first
            let runningApps = NSWorkspace.shared.runningApplications
            if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                print("  → Activating app: \(app.localizedName ?? "Unknown")")
                app.activate(options: .activateIgnoringOtherApps)

                // Wait for app to be active before manipulating windows
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.raiseSpecificWindow(
                        pid: pid, windowID: windowID, targetTitle: targetTitle,
                        shouldActivateApp: false)
                }
            }
        }
    }

    private func raiseSpecificWindow(
        pid: pid_t, windowID: CGWindowID, targetTitle: String, shouldActivateApp: Bool
    ) {
        // Try to bring specific window to front using AX API
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        if result == .success,
            let axWindows = windowsRef as? [AXUIElement]
        {
            print("  → Found \(axWindows.count) AX windows")

            // First try to match by CGWindowID via CGWindowList
            let options: CGWindowListOption = [.excludeDesktopElements]
            var cgWindowToAXWindow: [CGWindowID: AXUIElement] = [:]

            if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
            {
                // Build mapping from CGWindowID to window title
                for windowDict in windowList {
                    if let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                        ownerPID == pid,
                        let wid = windowDict[kCGWindowNumber as String] as? CGWindowID,
                        let windowName = windowDict[kCGWindowName as String] as? String
                    {
                        // Try to find matching AX window by title
                        for axWindow in axWindows {
                            var titleRef: CFTypeRef?
                            AXUIElementCopyAttributeValue(
                                axWindow, kAXTitleAttribute as CFString, &titleRef)
                            let axTitle = (titleRef as? String) ?? ""

                            if axTitle == windowName {
                                cgWindowToAXWindow[wid] = axWindow
                                break
                            }
                        }
                    }
                }
            }

            // Try to find window by CGWindowID first
            if let matchedWindow = cgWindowToAXWindow[windowID] {
                print("  ✅ Matched window by WindowID: \(windowID)")
                self.processWindow(matchedWindow, pid: pid, shouldActivateApp: shouldActivateApp)
                return
            }

            // Fallback: Find the SPECIFIC window that matches by title
            for (index, window) in axWindows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let windowTitle = (titleRef as? String) ?? ""

                print("  → Checking window [\(index)]: [\(windowTitle)]")

                // Skip empty titles and only match non-empty targetTitle
                guard !targetTitle.isEmpty && !windowTitle.isEmpty else { continue }

                // Match by title (exact or contains)
                if windowTitle == targetTitle || windowTitle.contains(targetTitle) {
                    print("  ✅ Matched window by title: \(windowTitle)")
                    self.processWindow(window, pid: pid, shouldActivateApp: shouldActivateApp)
                    return
                }
            }

            print("  ⚠️ No matching window found for: [\(targetTitle)] with ID: \(windowID)")
        } else {
            print("  ❌ Failed to get windows from AX API: \(result.rawValue)")
        }
    }

    private func processWindow(_ window: AXUIElement, pid: pid_t, shouldActivateApp: Bool) {
        // Check if window is minimized
        var minimizedRef: CFTypeRef?
        let minResult = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedRef
        )

        let isMinimized = (minResult == .success && (minimizedRef as? Bool) == true)
        print("  → Window minimized status: \(isMinimized)")

        if isMinimized {
            print("  → Window is minimized, un-minimizing...")

            // Un-minimize the window
            let setResult = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )

            print("  → Un-minimize result: \(setResult.rawValue)")

            // Chrome needs longer delay - wait for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("  → Now raising window after delay")

                // IMPORTANT: Activate app AFTER un-minimize to avoid focusing wrong window
                let runningApps = NSWorkspace.shared.runningApplications
                if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                    print("  → Activating app AFTER un-minimize")
                    app.activate(options: .activateIgnoringOtherApps)
                }

                // Small delay for app activation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AXUIElementSetAttributeValue(
                        window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)

                    // Force focus on the window
                    AXUIElementSetAttributeValue(
                        window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                }
            }
        } else {
            // For non-minimized windows, raise immediately
            print("  → Window is not minimized, raising immediately")
            AXUIElementSetAttributeValue(
                window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }
}
