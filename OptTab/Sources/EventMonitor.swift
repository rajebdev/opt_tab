import Cocoa

class EventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (NSEvent) -> NSEvent?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        // Create event tap using CGEvent for true global monitoring
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                    let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()

                    if let nsEvent = NSEvent(cgEvent: event) {
                        if let result = monitor.handler(nsEvent) {
                            return Unmanaged.passRetained(result.cgEvent!)
                        } else {
                            // Handler returned nil, meaning consume the event
                            return nil
                        }
                    }

                    return Unmanaged.passRetained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            print("❌ Failed to create event tap. Make sure Accessibility permissions are granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("✅ Event tap created and enabled")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }
}
