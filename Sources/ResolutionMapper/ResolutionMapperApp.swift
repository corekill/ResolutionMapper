import SwiftUI

@main
struct ResolutionMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DisplayMapperModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .background(WindowAccessor { window in
                    MainWindowController.shared.attach(window)
                })
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Resolution Mapper", systemImage: "display.2") {
            Button("Open Resolution Mapper") {
                MainWindowController.shared.show()
            }
            Divider()
            Button("Apply Last Mapping") {
                model.applyLastMapping()
            }
            Button("Unmap Selected Monitor") {
                model.unmapSelected()
            }
            if model.phoneRemoteEnabled {
                Button("Copy Phone Remote Link") {
                    model.copyRemoteURL()
                }
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !NSApp.windows.contains(where: { $0.isVisible }) {
            MainWindowController.shared.show()
        }
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private weak var window: NSWindow?

    func attach(_ window: NSWindow) {
        self.window = window
        window.delegate = self
        window.setFrameAutosaveName("ResolutionMapperMainWindow")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
