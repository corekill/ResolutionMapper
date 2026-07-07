import AppKit

@MainActor
final class ScreenDimmer {
    private var panels: [String: NSPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var enabled = false
    private var amount = 0.0

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncPanels()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func set(enabled: Bool, amount: Double) {
        self.enabled = enabled
        self.amount = clamp(amount)
        syncPanels()
    }

    func refreshScreens() {
        syncPanels()
    }

    private func syncPanels() {
        guard enabled, amount > 0.005 else {
            removeAllPanels()
            return
        }

        let liveKeys = Set(NSScreen.screens.map(screenKey))
        for key in panels.keys where !liveKeys.contains(key) {
            panels[key]?.orderOut(nil)
            panels.removeValue(forKey: key)
        }

        for screen in NSScreen.screens {
            let key = screenKey(screen)
            let panel = panels[key] ?? createPanel(for: screen)
            panels[key] = panel
            panel.setFrame(screen.frame, display: true)
            panel.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(amount))
            panel.orderFrontRegardless()
        }
    }

    private func createPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(amount))
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        return panel
    }

    private func removeAllPanels() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func screenKey(_ screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(screen.localizedName)-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))-\(Int(frame.height))"
    }

    private func clamp(_ value: Double) -> Double {
        Swift.max(0, Swift.min(0.92, value))
    }
}
