import Cocoa
import ApplicationServices

final class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    /// Returns all standard document/app windows for the application.
    func getAllStandardWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let appElem = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        
        return windows.filter { win in
            var subRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subRef)
            let subrole = subRef as? String
            
            var minBtnRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &minBtnRef)
            
            return subrole == "AXStandardWindow" || minBtnRef != nil
        }
    }
    
    /// Returns all visible (non-minimized) standard windows.
    func getVisibleWindows(for app: NSRunningApplication) -> [AXUIElement] {
        return getAllStandardWindows(for: app).filter { win in
            var minRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false
            return !isMin
        }
    }
    
    /// Returns all minimized standard windows.
    func getMinimizedWindows(for app: NSRunningApplication) -> [AXUIElement] {
        return getAllStandardWindows(for: app).filter { win in
            var minRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false
            return isMin
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
    
    /// Restores (unminimizes) all minimized standard windows of the application.
    func restoreMinimizedWindows(for app: NSRunningApplication) {
        let minimized = getMinimizedWindows(for: app)
        guard !minimized.isEmpty else { return }
        
        for win in minimized {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        app.activate(options: [.activateAllWindows])
    }
}
