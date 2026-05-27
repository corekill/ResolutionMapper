import SwiftUI

@main
struct ResolutionMapperApp: App {
    @StateObject private var model = DisplayMapperModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Resolution Mapper", systemImage: "display.2") {
            Button("Open Resolution Mapper") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Apply Last Mapping") {
                model.applyLastMapping()
            }
            Button("Unmap Selected Monitor") {
                model.unmapSelected()
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
