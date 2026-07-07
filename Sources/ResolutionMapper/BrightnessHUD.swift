import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class BrightnessHUDController {
    static let shared = BrightnessHUDController()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(displayID: CGDirectDisplayID?, displayName: String, percent: Int, nits: Int?) {
        let screen = targetScreen(displayID: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let size = NSSize(width: 286, height: 154)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        let panel = self.panel ?? createPanel(frame: frame)
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: BrightnessHUDView(
                displayName: displayName,
                percent: percent,
                nits: nits
            )
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel?.animator().alphaValue = 0
                } completionHandler: { [weak self, weak panel] in
                    Task { @MainActor in
                        panel?.orderOut(nil)
                        panel?.alphaValue = 1
                        if self?.panel === panel {
                            self?.panel = nil
                        }
                    }
                }
            }
        }
    }

    private func createPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
            .transient,
        ]
        return panel
    }

    private func targetScreen(displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }
    }
}

private struct BrightnessHUDView: View {
    let displayName: String
    let percent: Int
    let nits: Int?

    private var normalizedPercent: Double {
        Double(max(0, min(100, percent))) / 100
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 31, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(percent)%")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        if let nits {
                            Text("~\(nits) nits")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                                .monospacedDigit()
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            segmentedBar
        }
        .padding(18)
        .frame(width: 286, height: 154)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.32), radius: 24, y: 12)
    }

    private var segmentedBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Double(index + 1) / 16 <= normalizedPercent ? Color.cyan : Color.white.opacity(0.18))
                    .frame(height: 13)
            }
        }
    }
}
