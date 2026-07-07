import AppKit

@MainActor
final class ScreenDimmer {
    private var panels: [String: NSPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var levelsByDisplayID: [CGDirectDisplayID: Double] = [:]

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

    func set(levelsByDisplayID: [CGDirectDisplayID: Double]) {
        self.levelsByDisplayID = levelsByDisplayID.mapValues(clamp)
        syncPanels()
    }

    func refreshScreens() {
        syncPanels()
    }

    private func syncPanels() {
        guard !levelsByDisplayID.isEmpty else {
            removeAllPanels()
            return
        }

        let activeScreens = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID, Double)? in
            guard let displayID = displayID(for: screen) else { return nil }
            let amount = levelsByDisplayID[displayID] ?? 0
            guard amount > 0.005 else { return nil }
            return (screen, displayID, amount)
        }

        guard !activeScreens.isEmpty else {
            removeAllPanels()
            return
        }

        let liveKeys = Set(activeScreens.map { screenKey($0.0, displayID: $0.1) })
        for key in panels.keys where !liveKeys.contains(key) {
            panels[key]?.orderOut(nil)
            panels.removeValue(forKey: key)
        }

        for (screen, displayID, amount) in activeScreens {
            let key = screenKey(screen, displayID: displayID)
            let panel = panels[key] ?? createPanel(for: screen, amount: amount)
            panels[key] = panel
            panel.setFrame(screen.frame, display: true)
            panel.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(amount))
            panel.orderFrontRegardless()
        }
    }

    private func createPanel(for screen: NSScreen, amount: Double) -> NSPanel {
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

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func screenKey(_ screen: NSScreen, displayID: CGDirectDisplayID) -> String {
        let frame = screen.frame
        return "\(displayID)-\(screen.localizedName)-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))-\(Int(frame.height))"
    }

    private func clamp(_ value: Double) -> Double {
        Swift.max(0, Swift.min(0.92, value))
    }
}
