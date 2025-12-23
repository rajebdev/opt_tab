import ApplicationServices
import Cocoa

// MARK: - ClickableView for mouse interaction
class ClickableView: NSView {
    var clickHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
}

class ArrowButton: NSView {
    var clickHandler: (() -> Void)?
    private let isNext: Bool

    init(frame: NSRect, isNext: Bool) {
        self.isNext = isNext
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer?.cornerRadius = frame.width / 2
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        // Add arrow symbol - perfectly centered
        let arrowLabel = NSTextField(frame: bounds)
        arrowLabel.stringValue = isNext ? "›" : "‹"
        arrowLabel.alignment = .center
        arrowLabel.isEditable = false
        arrowLabel.isBordered = false
        arrowLabel.isSelectable = false
        arrowLabel.backgroundColor = .clear
        arrowLabel.textColor = .white
        arrowLabel.font = NSFont.systemFont(ofSize: 36, weight: .bold)

        // Center vertically by adjusting frame
        arrowLabel.cell?.usesSingleLineMode = true
        arrowLabel.cell?.truncatesLastVisibleLine = true

        // Fine-tune vertical centering
        let textHeight = arrowLabel.font!.boundingRectForFont.height
        let yOffset = (bounds.height - textHeight) / 2
        arrowLabel.frame = NSRect(x: 0, y: yOffset - 2, width: bounds.width, height: textHeight + 4)

        addSubview(arrowLabel)
    }

    override func mouseDown(with event: NSEvent) {
        // Visual feedback
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        clickHandler?()

        // Reset after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(
            rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

// MARK: - Private API Declarations
// SkyLight.framework private APIs for better window capture
typealias CGSConnectionID = UInt32

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// CGSHWCaptureWindowList can capture minimized windows (unlike CGWindowListCreateImage)
/// Performance: Faster, Quality: Medium, Can capture: minimized + other spaces
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowList: UnsafeMutablePointer<CGWindowID>,
    _ windowCount: UInt32,
    _ options: CGSWindowCaptureOptions
) -> Unmanaged<CFArray>

class AppSwitcher {
    private var window: NSWindow?
    private var collectionView: NSCollectionView?
    private var windows: [WindowInfo] = []
    private var selectedIndex: Int = 0
    private var isShowing: Bool = false
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalFlagsMonitor: Any?

    // Cache app icons to avoid duplication (one icon per app, not per window)
    private var appIconCache: [pid_t: NSImage] = [:]

    // Pagination support
    private var allWindows: [WindowInfo] = []  // All windows (unfiltered)
    private var currentPage: Int = 0
    private let itemsPerPage: Int = 16

    struct WindowInfo {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let ownerName: String
        let windowTitle: String
        let originalAXTitle: String  // Original title dari AX API untuk matching
        let thumbnail: NSImage
        let appIconPID: pid_t  // Store PID instead of icon itself
        let bounds: CGRect
    }

    func show() {
        guard !isShowing else {
            // Already showing, just cycle to next app
            selectNext()
            return
        }

        isShowing = true

        // Clear previous data before getting new windows
        autoreleasepool {
            self.windows.removeAll(keepingCapacity: false)
            self.allWindows.removeAll(keepingCapacity: false)
            self.appIconCache.removeAll(keepingCapacity: false)
        }

        // Get all windows (without limit)
        allWindows = getAllWindows()
        currentPage = 0

        let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
        print("🪟 Found \(allWindows.count) windows across \(totalPages) page(s)")

        // Set current page windows
        updateCurrentPageWindows()

        for (i, win) in windows.enumerated() {
            let globalIndex = currentPage * itemsPerPage + i
            print("  [\(globalIndex)] \(win.ownerName) - \(win.windowTitle)")
            print("      → Original AX: [\(win.originalAXTitle)], WindowID: \(win.windowID)")
        }

        if allWindows.count <= 1 {
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

        // Aggressive memory cleanup for thumbnails and cached images
        clearAllMemory()

        // Clear windows arrays immediately to release thumbnail memory ASAP
        // Keep only selected window info before async
        let selectedInfo = selectedWindowInfo
        self.windows.removeAll(keepingCapacity: false)
        self.allWindows.removeAll(keepingCapacity: false)

        // Clear icon cache to free memory
        self.appIconCache.removeAll(keepingCapacity: false)

        // Small delay to ensure overlay is hidden before switching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Use captured window info directly
            self.activateWindow(windowInfo: selectedInfo)
        }
    }

    private func getAllWindows() -> [WindowInfo] {
        var windowInfos: [WindowInfo] = []
        windowInfos.reserveCapacity(32)  // Pre-allocate for larger expected size

        // Clear icon cache at start
        appIconCache.removeAll(keepingCapacity: false)

        // Fetch CGWindowList once for all windows (memory efficient)
        let options: CGWindowListOption = [.excludeDesktopElements]
        let cgWindowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]

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
            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier

            // Cache app icon once per app (memory efficient)
            if appIconCache[pid] == nil {
                guard let appIcon = app.icon else { continue }
                appIconCache[pid] = appIcon
            }

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

                    // Get window ID for thumbnail (use pre-fetched list)
                    var windowID: CGWindowID = 0
                    if let windowList = cgWindowList {
                        // Try multiple matching strategies for Chrome/Electron apps
                        for windowDict in windowList {
                            if let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                                ownerPID == pid,
                                let wid = windowDict[kCGWindowNumber as String] as? CGWindowID
                            {
                                let windowName =
                                    windowDict[kCGWindowName as String] as? String ?? ""

                                // Strategy 1: Exact match
                                if windowName == windowTitle {
                                    windowID = wid
                                    if appName.contains("Chrome") {
                                        print(
                                            "  [MAP] Chrome window '\(windowTitle)' -> ID: \(wid) (exact)"
                                        )
                                    }
                                    break
                                }

                                // Strategy 2: Chrome/Electron - CGWindow title is prefix of AX title
                                // AX: "Page Title - Google Chrome - Profile"
                                // CG: "Page Title"
                                if windowTitle.hasPrefix(windowName) && !windowName.isEmpty
                                    && windowName.count > 3
                                {
                                    windowID = wid
                                    if appName.contains("Chrome") {
                                        print(
                                            "  [MAP] Chrome window '\(windowTitle)' -> ID: \(wid) (prefix match: '\(windowName)')"
                                        )
                                    }
                                    break
                                }

                                // Strategy 3: Try to match first part before " - "
                                if let firstPart = windowTitle.components(separatedBy: " - ").first,
                                    firstPart.count > 3,
                                    windowName == firstPart
                                {
                                    windowID = wid
                                    if appName.contains("Chrome") {
                                        print(
                                            "  [MAP] Chrome window '\(windowTitle)' -> ID: \(wid) (first part match)"
                                        )
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
                    // Now can capture minimized windows using CGSHWCaptureWindowList!
                    let thumbnail = captureWindowThumbnail(
                        windowID: windowID, bounds: bounds, isMinimized: isMinimized,
                        appIcon: appIconCache[pid]!)

                    // Format title - show minimize indicator
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
                            appIconPID: pid,  // Store PID instead of duplicating icon
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
        // 2x retina size for sharp display (UI shows 230x110)
        let targetWidth: CGFloat = 460
        let targetHeight: CGFloat = 220

        // Use icon placeholder only if windowID is invalid (0)
        if windowID == 0 {
            return createIconPlaceholder(
                width: targetWidth, height: targetHeight, icon: appIcon)
        }

        // Use autoreleasepool to ensure CGImage is released immediately
        return autoreleasepool {
            // Use CGSHWCaptureWindowList - can capture minimized windows!
            // More memory efficient than CGWindowListCreateImage with better performance
            var windowId = windowID
            let connectionId = CGSMainConnectionID()

            // Use bestResolution for sharper thumbnails
            let captureOptions: CGSWindowCaptureOptions = [
                .ignoreGlobalClipShape,
                .bestResolution,
            ]

            let imageList =
                CGSHWCaptureWindowList(
                    connectionId,
                    &windowId,
                    1,
                    captureOptions
                ).takeRetainedValue() as! [CGImage]

            if let cgImage = imageList.first, cgImage.width > 10, cgImage.height > 10 {
                // Resize immediately to reduce memory footprint
                // Don't store full-size CGImage in memory!
                let resizedImage = resizeImage(
                    cgImage, targetWidth: targetWidth, targetHeight: targetHeight)
                return resizedImage
            }

            // Return app icon placeholder if capture fails
            return createIconPlaceholder(width: targetWidth, height: targetHeight, icon: appIcon)
        }
    }

    private func resizeImage(_ cgImage: CGImage, targetWidth: CGFloat, targetHeight: CGFloat)
        -> NSImage
    {
        // Use autoreleasepool to ensure intermediate objects are freed
        return autoreleasepool {
            // Calculate aspect-fit size
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)
            let aspectRatio = imageWidth / imageHeight
            let targetAspectRatio = targetWidth / targetHeight

            var drawWidth: CGFloat
            var drawHeight: CGFloat

            if aspectRatio > targetAspectRatio {
                // Image is wider - fit to width
                drawWidth = targetWidth
                drawHeight = targetWidth / aspectRatio
            } else {
                // Image is taller - fit to height
                drawHeight = targetHeight
                drawWidth = targetHeight * aspectRatio
            }

            // Create smaller bitmap context to save memory
            let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little)

            guard
                let context = CGContext(
                    data: nil,
                    width: Int(drawWidth),
                    height: Int(drawHeight),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                )
            else {
                // Fallback if context creation fails
                return NSImage(
                    cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
            }

            // High quality interpolation for sharp thumbnails
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))

            guard let resizedCGImage = context.makeImage() else {
                return NSImage(
                    cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
            }

            // Create NSImage - autoreleasepool will release resizedCGImage after this
            let result = NSImage(
                cgImage: resizedCGImage, size: NSSize(width: drawWidth, height: drawHeight))
            return result
        }
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

        // Grid layout settings - slightly smaller to reduce rendering memory
        let itemWidth: CGFloat = 260
        let itemHeight: CGFloat = 180
        let spacing: CGFloat = 25
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

        // Add page indicator if multiple pages
        let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
        if totalPages > 1 {
            let pageIndicator = NSTextField(
                frame: NSRect(
                    x: containerX,
                    y: containerY - 35,
                    width: containerWidth,
                    height: 25
                ))
            pageIndicator.stringValue =
                "Page \(currentPage + 1) of \(totalPages) • Press Tab to continue"
            pageIndicator.alignment = .center
            pageIndicator.isEditable = false
            pageIndicator.isBordered = false
            pageIndicator.backgroundColor = .clear
            pageIndicator.textColor = .white
            pageIndicator.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            contentView.addSubview(pageIndicator)

            // Add arrow buttons for page navigation
            let buttonSize: CGFloat = 60
            let buttonY = containerY + (containerHeight - buttonSize) / 2

            // Previous page button (left arrow) - show only if not on first page
            if currentPage > 0 {
                let prevButton = createArrowButton(
                    frame: NSRect(
                        x: containerX - buttonSize - 30, y: buttonY, width: buttonSize,
                        height: buttonSize),
                    isNext: false
                )
                contentView.addSubview(prevButton)
            }

            // Next page button (right arrow) - show only if not on last page
            if currentPage < totalPages - 1 {
                let nextButton = createArrowButton(
                    frame: NSRect(
                        x: containerX + containerWidth + 30, y: buttonY, width: buttonSize,
                        height: buttonSize),
                    isNext: true
                )
                contentView.addSubview(nextButton)
            }
        }

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
                windowInfo: windowInfo, isSelected: index == selectedIndex, index: index)
            itemView.frame = NSRect(x: x, y: y, width: itemWidth, height: itemHeight)
            contentView.addSubview(itemView)
        }
    }

    private func createWindowItemView(windowInfo: WindowInfo, isSelected: Bool, index: Int)
        -> NSView
    {
        let view = ClickableView()
        view.clickHandler = { [weak self] in
            guard let self = self else { return }
            self.selectedIndex = index
            // Immediately hide and switch to the clicked window
            self.hide()
        }
        view.wantsLayer = true
        view.layer?.backgroundColor =
            isSelected
            ? NSColor.systemBlue.withAlphaComponent(0.9).cgColor  // Solid untuk selected
            : NSColor(white: 0.2, alpha: 0.95).cgColor  // Solid dark grey untuk normal
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = isSelected ? 3 : 1
        view.layer?.borderColor =
            isSelected ? NSColor.systemBlue.cgColor : NSColor.white.withAlphaComponent(0.3).cgColor

        // Thumbnail (adjusted to match smaller size for memory efficiency)
        let thumbnailView = NSImageView(frame: NSRect(x: 15, y: 55, width: 230, height: 110))
        thumbnailView.image = windowInfo.thumbnail
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown  // Fill entire area
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true  // Crop overflow
        thumbnailView.layer?.borderWidth = 1
        thumbnailView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        view.addSubview(thumbnailView)

        // App icon (larger) - get from cache
        let iconView = NSImageView(frame: NSRect(x: 15, y: 15, width: 32, height: 32))
        iconView.image = appIconCache[windowInfo.appIconPID]
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
        selectedIndex += 1

        // Check if we reached end of current page
        if selectedIndex >= windows.count {
            // Move to next page
            let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
            currentPage = (currentPage + 1) % totalPages

            // Update windows for new page
            updateCurrentPageWindows()

            // Reset to first item of new page
            selectedIndex = 0

            print("📄 Switched to page \(currentPage + 1)/\(totalPages)")
        }

        updateWindowContent()
    }

    private func selectPrevious() {
        selectedIndex -= 1

        // Check if we went before first item
        if selectedIndex < 0 {
            // Move to previous page
            let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
            currentPage = (currentPage - 1 + totalPages) % totalPages

            // Update windows for new page
            updateCurrentPageWindows()

            // Go to last item of previous page
            selectedIndex = windows.count - 1

            print("📄 Switched to page \(currentPage + 1)/\(totalPages)")
        }

        updateWindowContent()
    }

    private func updateCurrentPageWindows() {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, allWindows.count)
        windows = Array(allWindows[startIndex..<endIndex])
    }

    private func createArrowButton(frame: NSRect, isNext: Bool) -> ArrowButton {
        let button = ArrowButton(frame: frame, isNext: isNext)
        button.clickHandler = { [weak self] in
            guard let self = self else { return }
            if isNext {
                self.goToNextPage()
            } else {
                self.goToPreviousPage()
            }
        }
        return button
    }

    private func goToNextPage() {
        let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
        if currentPage < totalPages - 1 {
            currentPage += 1
            updateCurrentPageWindows()
            selectedIndex = 0  // Reset to first item of new page
            updateWindowContent()
            print("📄 Navigated to page \(currentPage + 1)/\(totalPages)")
        }
    }

    private func goToPreviousPage() {
        let totalPages = (allWindows.count + itemsPerPage - 1) / itemsPerPage
        if currentPage > 0 {
            currentPage -= 1
            updateCurrentPageWindows()
            selectedIndex = 0  // Reset to first item of new page
            updateWindowContent()
            print("📄 Navigated to page \(currentPage + 1)/\(totalPages)")
        }
    }

    private func setupKeyMonitoring() {
        // Monitor for Tab key (cycle through apps)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.isShowing else { return event }

            // Tab key - next/previous item with pagination support
            if event.keyCode == 48 {
                // Check if Shift is pressed for reverse navigation
                if event.modifierFlags.contains(.shift) {
                    self.selectPrevious()
                } else {
                    self.selectNext()
                }
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

    // MARK: - Memory Management
    /// Aggressively clear all cached thumbnails and images to free memory
    private func clearAllMemory() {
        autoreleasepool {
            // Clear all thumbnails in windows array
            windows.forEach { windowInfo in
                // Force deallocation by removing all references
                _ = windowInfo.thumbnail
            }

            // Clear all thumbnails in allWindows array
            allWindows.forEach { windowInfo in
                _ = windowInfo.thumbnail
            }

            // Clear all subviews and their images
            window?.contentView?.subviews.forEach { subview in
                clearViewHierarchy(subview)
                subview.removeFromSuperview()
            }

            // Clear collection view items
            if let collectionView = collectionView {
                collectionView.visibleItems().forEach { item in
                    if let imageView = item.view.subviews.first(where: { $0 is NSImageView })
                        as? NSImageView
                    {
                        imageView.image = nil
                    }
                }
                collectionView.reloadData()
            }

            // Clear cached app icons
            appIconCache.forEach { (_, icon) in
                _ = icon
            }

            print("🧹 Memory cleared: thumbnails, caches, and UI elements released")
        }
    }

    /// Recursively clear all images in view hierarchy
    private func clearViewHierarchy(_ view: NSView) {
        // Clear image if it's an NSImageView
        if let imageView = view as? NSImageView {
            imageView.image = nil
        }

        // Recursively clear all subviews
        view.subviews.forEach { subview in
            clearViewHierarchy(subview)
        }
    }
}
