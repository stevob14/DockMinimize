import Cocoa
import ApplicationServices

final class WindowManager {
    static let shared = WindowManager()
    
    private init() {}
    
    /// Returns all standard document/app windows for the application, optionally filtered by title (e.g. for Trash).
    func getAllStandardWindows(for app: NSRunningApplication, withTitle targetTitle: String? = nil) -> [AXUIElement] {
        let appElem = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        
        let standardWindows = windows.filter { win in
            var subRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subRef)
            let subrole = subRef as? String
            
            var minBtnRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &minBtnRef)
            
            return subrole == "AXStandardWindow" || minBtnRef != nil
        }
        
        if let targetTitle = targetTitle, !targetTitle.isEmpty {
            let matching = standardWindows.filter { win in
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""
                return title.localizedCaseInsensitiveCompare(targetTitle) == .orderedSame
            }
            if !matching.isEmpty {
                return matching
            }
        }
        
        return standardWindows
    }
    
    /// Returns all visible (non-minimized) standard windows.
    func getVisibleWindows(for app: NSRunningApplication, withTitle targetTitle: String? = nil) -> [AXUIElement] {
        return getAllStandardWindows(for: app, withTitle: targetTitle).filter { win in
            var minRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false
            return !isMin
        }
    }
    
    /// Returns all minimized standard windows.
    func getMinimizedWindows(for app: NSRunningApplication, withTitle targetTitle: String? = nil) -> [AXUIElement] {
        return getAllStandardWindows(for: app, withTitle: targetTitle).filter { win in
            var minRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef)
            let isMin = (minRef as? Bool) ?? false
            return isMin
        }
    }
    
    /// Minimizes all visible standard windows of the application with native animation.
    func minimizeWindows(for app: NSRunningApplication, withTitle targetTitle: String? = nil) {
        let visibleWindows = getVisibleWindows(for: app, withTitle: targetTitle)
        guard !visibleWindows.isEmpty else { return }
        
        for win in visibleWindows {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }
    
    /// Restores (unminimizes) all minimized standard windows of the application.
    func restoreMinimizedWindows(for app: NSRunningApplication, withTitle targetTitle: String? = nil) {
        let minimized = getMinimizedWindows(for: app, withTitle: targetTitle)
        guard !minimized.isEmpty else { return }
        
        for win in minimized {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        app.activate(options: [.activateAllWindows])
    }
}
