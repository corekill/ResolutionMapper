import CoreImage.CIFilterBuiltins
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: DisplayMapperModel
    @State private var titleClickCount = 0
    @State private var pairingCodeInput = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.10), Color(red: 0.11, green: 0.12, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.08))
                main
                footer
            }
            .foregroundStyle(.white)
            .padding(22)

            if model.sparkleBurst {
                SparkleBurstView()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "display.2")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("Resolution Mapper")
                    .font(.system(size: 26, weight: .bold))
                    .onTapGesture {
                        titleClickCount += 1
                        if titleClickCount >= 7 {
                            titleClickCount = 0
                            model.triggerEasterEgg()
                        }
                    }
                Text("Virtual display mapping for stubborn monitors")
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Button {
                model.refreshDisplays()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ToolButtonStyle())
        }
        .padding(.bottom, 18)
    }

    private var main: some View {
        HStack(alignment: .top, spacing: 18) {
            monitorPanel
            VStack(spacing: 18) {
                resolutionPanel
                comfortPanel
            }
            VStack(spacing: 18) {
                mappingPanel
                phoneRemotePanel
            }
        }
        .padding(.top, 18)
        .frame(maxWidth: 980, alignment: .center)
    }

    private var monitorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monitor")
                .font(.headline)

            Picker("Target", selection: Binding(
                get: { model.selectedTargetID ?? 0 },
                set: { model.selectedTargetID = $0 }
            )) {
                ForEach(model.targetDisplays) { display in
                    Text(display.label).tag(display.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.displays) { display in
                    DisplayRow(display: display) {
                        model.removeVirtualDisplay(id: display.id)
                    }
                }
            }
        }
        .panelStyle(width: 285)
    }

    private var resolutionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resolution")
                .font(.headline)

            Toggle("Custom", isOn: $model.useCustomResolution)
                .toggleStyle(.switch)

            if model.useCustomResolution {
                HStack {
                    TextField("Width", text: $model.customWidth)
                        .textFieldStyle(.roundedBorder)
                    Text("x")
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("Height", text: $model.customHeight)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("HiDPI mode", isOn: $model.useHiDPI)
                    .toggleStyle(.checkbox)
            } else {
                VStack(spacing: 8) {
                    ForEach(ResolutionPreset.all) { preset in
                        PresetButton(
                            preset: preset,
                            selected: model.selectedPreset == preset
                        ) {
                            model.selectedPreset = preset
                        }
                    }
                }
            }

            Text("Sharper text usually means less aggressive scaling. Try Soft QHD for reading, QHD Space for room, or 4K Downsample for fine lines.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle(width: 300)
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mapping")
                .font(.headline)

            HStack {
                StatTile(title: "Requested", value: "\(model.requestedWidth)x\(model.requestedHeight)")
                StatTile(title: "Mode", value: model.requestedHiDPI ? "HiDPI" : "LoDPI")
            }

            Button {
                model.applySelectedMapping()
            } label: {
                Label(model.isBusy ? "Applying..." : "Map Monitor", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isBusy)

            HStack(spacing: 10) {
                Button {
                    model.unmapSelected()
                } label: {
                    Label("Unmap", systemImage: "rectangle.on.rectangle.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolButtonStyle())

                Button {
                    model.removeVirtualDisplays()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolButtonStyle())
            }

            Toggle("Restore on login", isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: model.launchAtLogin) { _, _ in
                    model.toggleLaunchAtLogin()
                }

            Text(model.status)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle(width: 335)
    }

    private var comfortPanel: some View {
        comfortControls
            .panelStyle(width: 300)
    }

    private var phoneRemotePanel: some View {
        phoneRemoteControls
            .panelStyle(width: 335)
    }

    private var comfortControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comfort")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            if !model.dimmingDisplays.isEmpty {
                Picker("Dim Display", selection: Binding(
                    get: { model.selectedDimmingDisplayID ?? 0 },
                    set: { model.selectDimmingDisplay(id: $0) }
                )) {
                    ForEach(model.dimmingDisplays) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Toggle("Dim below minimum", isOn: Binding(
                get: { model.softwareDimmingEnabled },
                set: { model.setSoftwareDimming(enabled: $0) }
            ))
            .toggleStyle(.switch)

            HStack {
                Slider(value: Binding(
                    get: { model.softwareDimmingAmount },
                    set: { model.setSoftwareDimmingAmount($0) }
                ), in: 0...0.85)
                .disabled(!model.softwareDimmingEnabled)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(model.selectedEffectiveBrightnessPercent)%")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Text("~\(model.selectedEffectiveNits) nits")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(width: 62, alignment: .trailing)
            }

            Stepper(value: Binding(
                get: { model.selectedDisplayMaxNits },
                set: { model.setSelectedDisplayMaxNits($0) }
            ), in: 80...2000, step: 10) {
                Text("Panel max \(model.selectedDisplayMaxNits) nits")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var phoneRemoteControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phone Remote")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            Toggle("LAN web remote", isOn: Binding(
                get: { model.phoneRemoteEnabled },
                set: { model.setPhoneRemoteEnabled($0) }
            ))
            .toggleStyle(.switch)

            if model.phoneRemoteEnabled {
                HStack(alignment: .top, spacing: 10) {
                    QRCodeView(text: model.remoteURL)
                        .frame(width: 96, height: 96)
                        .opacity(model.remoteURL.isEmpty ? 0.25 : 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.remoteURL.isEmpty ? "Starting..." : model.remoteURL)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(3)
                            .textSelection(.enabled)

                        if model.authorizedRemoteDeviceCount > 0 {
                            Text("\(model.authorizedRemoteDeviceCount) phone\(model.authorizedRemoteDeviceCount == 1 ? "" : "s") authorized")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                Button {
                    model.copyRemoteURL()
                } label: {
                    Label("Copy QR Link", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ToolButtonStyle())
                .disabled(model.remoteURL.isEmpty)

                if !model.remotePairingDeviceName.isEmpty {
                    Text("Pairing \(model.remotePairingDeviceName)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 8) {
                    TextField("Code", text: $pairingCodeInput)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        model.authorizePhoneRemote(code: pairingCodeInput)
                        pairingCodeInput = ""
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 28)
                    }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(pairingCodeInput.filter(\.isNumber).count < 4)
                }

                if model.authorizedRemoteDeviceCount > 0 {
                    Button {
                        model.forgetPhoneRemotes()
                    } label: {
                        Label("Forget Phones", systemImage: "iphone.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolButtonStyle())
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Virtual displays are session-based; keep the app running for active mappings.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Link(destination: URL(string: "https://ko-fi.com/corekill")!) {
                Label("Donate", systemImage: "heart")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.62))
            .buttonStyle(.plain)

            Text("Created by corekill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.top, 16)
    }
}

struct DisplayRow: View {
    let display: DisplayItem
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.isVirtual ? "sparkles.tv" : display.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundStyle(display.isVirtual ? .pink : .cyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(Int(display.pixels.width))x\(Int(display.pixels.height))\(display.inMirrorSet ? " mirrored" : "")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer()

            if display.isVirtual {
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Remove virtual display")
            }
        }
        .padding(10)
        .background(.white.opacity(display.inMirrorSet ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PresetButton: View {
    let preset: ResolutionPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .cyan : .white.opacity(0.42))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(preset.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(10)
            .background(.white.opacity(selected ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SparkleBurstView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                Image(systemName: index.isMultiple(of: 3) ? "heart.fill" : "sparkle")
                    .font(.system(size: index.isMultiple(of: 4) ? 28 : 18, weight: .bold))
                    .foregroundStyle([Color.pink, .cyan, .mint, .yellow][index % 4])
                    .offset(
                        x: animate ? CGFloat((index % 6) - 3) * 88 : 0,
                        y: animate ? CGFloat((index / 3) - 3) * 72 : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .scaleEffect(animate ? 1.7 : 0.35)
                    .rotationEffect(.degrees(animate ? Double(index * 37) : 0))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.55)) {
                animate = true
            }
        }
    }
}

struct QRCodeView: View {
    let text: String
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.12))
            }
        }
    }

    private func makeImage() -> NSImage? {
        guard !text.isEmpty else { return nil }
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: outputImage.extent.width, height: outputImage.extent.height))
    }
}

extension View {
    func panelStyle(width: CGFloat) -> some View {
        self
            .frame(width: width, alignment: .topLeading)
            .padding(16)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
    }
}

struct ToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [.cyan, .mint], startPoint: .leading, endPoint: .trailing)
                    .opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(.black.opacity(0.82))
    }
}
