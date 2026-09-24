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
    private var lastActionTime: CFTimeInterval = 0
    
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
            
            // Debounce: if we recently triggered an action (within 0.4s), ignore
            if now - lastActionTime < 0.4 {
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
            
            if dist < 8.0 && elapsed < 0.6 {
                let clickPoint = point
                let frontAtDown = frontAppAtDown
                let hadVisible = hadVisibleWindowsAtDown
                
                DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                    self?.handleDockClick(at: clickPoint, frontAppAtDown: frontAtDown, hadVisibleAtDown: hadVisible)
                }
            }
            
            // Reset state
            frontAppAtDown = nil
            hadVisibleWindowsAtDown = false
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleDockClick(at point: CGPoint, frontAppAtDown: NSRunningApplication?, hadVisibleAtDown: Bool) {
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
        
        let runningApps = NSWorkspace.shared.runningApplications
        guard let matchedApp = runningApps.first(where: { app in
            if let dockBundleId = itemURL.flatMap({ Bundle(url: $0)?.bundleIdentifier }),
               dockBundleId == app.bundleIdentifier {
                return true
            }
            if let itemURL = itemURL, let appURL = app.bundleURL,
               itemURL.standardizedFileURL.resolvingSymlinksInPath().path == appURL.standardizedFileURL.resolvingSymlinksInPath().path {
                return true
            }
            if let title = title, !title.isEmpty {
                if app.localizedName?.localizedCaseInsensitiveCompare(title) == .orderedSame ||
                   app.bundleURL?.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(title) == .orderedSame {
                    return true
                }
            }
            return false
        }) else { return }
        
        let wasFrontmostAtDown = (frontAppAtDown?.processIdentifier == matchedApp.processIdentifier)
        
        if wasFrontmostAtDown && hadVisibleAtDown {
            // Case 1: Was frontmost and had visible windows -> MINIMIZE ALL
            lastActionTime = CACurrentMediaTime()
            DispatchQueue.main.async {
                WindowManager.shared.minimizeWindows(for: matchedApp)
            }
        } else {
            // Case 2: Clicked to restore / bring to front
            // If the app has minimized windows, restore ALL of them together
            let minimized = WindowManager.shared.getMinimizedWindows(for: matchedApp)
            if !minimized.isEmpty {
                lastActionTime = CACurrentMediaTime()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    WindowManager.shared.restoreMinimizedWindows(for: matchedApp)
                }
            }
        }
    }
}
