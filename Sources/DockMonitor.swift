import Cocoa
import ApplicationServices

final class DockMonitor {
    static let shared = DockMonitor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var mouseDownPoint: CGPoint = .zero
    private var mouseDownTime: CFTimeInterval = 0
    private var frontAppAtDown: NSRunningApplication?
    private var hadVisibleWindowsAtDown: Bool = false
    private var lastMinimizeTime: CFTimeInterval = 0
    
    private(set) var isRunning: Bool = false
    
    private init() {}
    
    func start() -> Bool {
        guard !isRunning, AXIsProcessTrusted() else { return isRunning }
        
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<DockMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleEvent(type: type, event: event)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPtr
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }
    
    func stop() {
        guard isRunning else { return }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        
        let point = event.location
        let now = CACurrentMediaTime()
        
        if type == .leftMouseDown {
            mouseDownPoint = point
            mouseDownTime = now
            
            // Debounce: if we recently minimized (within 0.4s), ignore to avoid immediate re-trigger
            if now - lastMinimizeTime < 0.4 {
                frontAppAtDown = nil
                hadVisibleWindowsAtDown = false
                return Unmanaged.passUnretained(event)
            }
            
            let front = NSWorkspace.shared.frontmostApplication
            frontAppAtDown = front
            if let front = front {
                let visible = WindowManager.shared.getVisibleWindows(for: front)
                hadVisibleWindowsAtDown = !visible.isEmpty
            } else {
                hadVisibleWindowsAtDown = false
            }
        } else if type == .leftMouseUp {
            let elapsed = now - mouseDownTime
            let dist = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            
            // Only minimize if it was a clean click AND the app had visible windows BEFORE the click started
            if dist < 8.0 && elapsed < 0.6 && hadVisibleWindowsAtDown, let app = frontAppAtDown {
                let clickPoint = point
                DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                    self?.checkAndMinimize(at: clickPoint, targetApp: app)
                }
            }
            
            // Reset state
            frontAppAtDown = nil
            hadVisibleWindowsAtDown = false
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func checkAndMinimize(at point: CGPoint, targetApp: NSRunningApplication) {
        let systemWide = AXUIElementCreateSystemWide()
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hitRef) == .success,
              let hit = hitRef else { return }
        
        // Verify element belongs to Dock process
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              pid == dockPID else { return }
        
        // Find AXDockItem element
        var item: AXUIElement? = hit
        for _ in 0..<4 {
            guard let cur = item else { break }
            var role: AnyObject?
            AXUIElementCopyAttributeValue(cur, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXDockItem" { break }
            var parent: AnyObject?
            if AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parent) == .success, let p = parent {
                item = (p as! AXUIElement)
            } else {
                item = nil
            }
        }
        guard let dockItem = item else { return }
        
        // Ensure it's an application icon
        var subrole: AnyObject?
        AXUIElementCopyAttributeValue(dockItem, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) == "AXApplicationDockItem" else { return }
        
        // Verify this dock item matches targetApp
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(dockItem, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String
        
        var urlRef: AnyObject?
        AXUIElementCopyAttributeValue(dockItem, "AXURL" as CFString, &urlRef)
        let itemURL: URL? = {
            if let cf = urlRef {
                if CFGetTypeID(cf) == CFURLGetTypeID() { return (cf as! URL) }
                if let s = cf as? String { return URL(string: s) }
            }
            return nil
        }()
        
        var isMatch = false
        if let dockBundleId = itemURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
           dockBundleId == targetApp.bundleIdentifier {
            isMatch = true
        } else if let itemURL = itemURL, let appURL = targetApp.bundleURL,
                  itemURL.standardizedFileURL.resolvingSymlinksInPath().path == appURL.standardizedFileURL.resolvingSymlinksInPath().path {
            isMatch = true
        } else if let title = title, !title.isEmpty {
            if targetApp.localizedName?.localizedCaseInsensitiveCompare(title) == .orderedSame ||
               targetApp.bundleURL?.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(title) == .orderedSame {
                isMatch = true
            }
        }
        
        guard isMatch else { return }
        
        // Record minimize time and execute minimize with native animation
        lastMinimizeTime = CACurrentMediaTime()
        DispatchQueue.main.async {
            WindowManager.shared.minimizeWindows(for: targetApp)
        }
    }
}
