import Cocoa
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var permissionCheckTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkAndStartMonitoring()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: "DockMinimize") {
                image.isTemplate = true
                button.image = image
            } else if let fallback = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockMinimize") {
                fallback.isTemplate = true
                button.image = fallback
            } else {
                button.title = "⤓"
            }
        }
        
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildMenu()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        statusMenu.removeAllItems()
        
        let titleItem = NSMenuItem(title: "DockMinimize", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let font = NSFont.boldSystemFont(ofSize: 13) as NSFont? {
            titleItem.attributedTitle = NSAttributedString(string: "DockMinimize", attributes: [.font: font])
        }
        statusMenu.addItem(titleItem)
        
        let isTrusted = AXIsProcessTrusted()
        let isRunning = DockMonitor.shared.isRunning
        
        let statusString: String
        if isTrusted && isRunning {
            statusString = "Status: Active ✓"
        } else if !isTrusted {
            statusString = "Status: Needs Accessibility ⚠️"
        } else {
            statusString = "Status: Starting..."
        }
        
        let statusItemEntry = NSMenuItem(title: statusString, action: #selector(statusItemClicked), keyEquivalent: "")
        statusItemEntry.target = self
        statusMenu.addItem(statusItemEntry)
        statusMenu.addItem(NSMenuItem.separator())
        
        if !isTrusted {
            let permItem = NSMenuItem(title: "Open Accessibility Settings...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            statusMenu.addItem(permItem)
            statusMenu.addItem(NSMenuItem.separator())
        }
        
        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            statusMenu.addItem(loginItem)
            statusMenu.addItem(NSMenuItem.separator())
        }
        
        let quitItem = NSMenuItem(title: "Quit DockMinimize", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
    
    @objc private func statusItemClicked() {
        if !AXIsProcessTrusted() {
            openAccessibilitySettings()
        }
    }
    
    @objc private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("[DockMinimize] Error toggling login item: \(error)")
            }
            rebuildMenu()
        }
    }
    
    @objc private func quitApp() {
        DockMonitor.shared.stop()
        NSApplication.shared.terminate(nil)
    }
    
    private func checkAndStartMonitoring() {
        if AXIsProcessTrusted() {
            _ = DockMonitor.shared.start()
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            rebuildMenu()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.permissionCheckTimer = nil
                    _ = DockMonitor.shared.start()
                    self?.rebuildMenu()
                }
            }
        }
    }
}
