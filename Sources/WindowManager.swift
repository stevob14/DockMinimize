import Cocoa
import ApplicationServices

final class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    /// Returns all visible (non-minimized) standard document/app windows for the application.
    func getVisibleWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let appElem = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        
        return windows.filter { win in
            // Check if already minimized
            var minRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false
            if isMin { return false }
            
            // Filter out desktop, system panels, etc.
            var subRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subRef)
            let subrole = subRef as? String
            
            var minBtnRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &minBtnRef)
            
            return subrole == "AXStandardWindow" || minBtnRef != nil
        }
    }
    
    /// Minimizes all visible standard windows of the application with native animation.
    func minimizeWindows(for app: NSRunningApplication) {
        let visibleWindows = getVisibleWindows(for: app)
        guard !visibleWindows.isEmpty else { return }
        
        for win in visibleWindows {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }
}
