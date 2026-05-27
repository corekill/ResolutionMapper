import AppKit
import CoreGraphics
import Foundation
import VirtualDisplayBridge

@MainActor
final class DisplayMapperModel: ObservableObject {
    @Published var displays: [DisplayItem] = []
    @Published var selectedTargetID: CGDirectDisplayID?
    @Published var selectedPreset = ResolutionPreset.all[0]
    @Published var customWidth = "2560"
    @Published var customHeight = "1440"
    @Published var useCustomResolution = false
    @Published var useHiDPI = false
    @Published var launchAtLogin = true
    @Published var status = "Ready"
    @Published var isBusy = false
    @Published var sparkleBurst = false

    private var virtualDisplays: [CGDirectDisplayID: VirtualDisplayWrapper] = [:]
    private var monitorTimer: Timer?
    private var lastHadExternalTarget = false
    private var displayMonitoringReady = false
    private let defaults = UserDefaults.standard
    private let savedMappingKey = "savedMapping"
    private let monitorMappingsKey = "monitorMappings"
    private let launchAgentPath = "\(NSHomeDirectory())/Library/LaunchAgents/com.codex.resolution-mapper.plist"

    init() {
        refreshDisplays()
        restoreUIState()
        setupNotifications()
        startDisplayMonitoring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.applyLastMapping()
        }
    }

    var targetDisplays: [DisplayItem] {
        displays.filter { !$0.isBuiltIn && !$0.isVirtual }
    }

    var virtualDisplayOptions: [DisplayItem] {
        displays.filter(\.isVirtual)
    }

    var requestedWidth: Int {
        useCustomResolution ? (Int(customWidth) ?? selectedPreset.width) : selectedPreset.width
    }

    var requestedHeight: Int {
        useCustomResolution ? (Int(customHeight) ?? selectedPreset.height) : selectedPreset.height
    }

    var requestedHiDPI: Bool {
        useCustomResolution ? useHiDPI : selectedPreset.hiDPI
    }

    func refreshDisplays() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        displays = ids.prefix(Int(count)).map { id in
            DisplayItem(
                id: id,
                name: DisplayNames.name(for: id),
                pixels: CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id)),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isVirtual: CGDisplayVendorNumber(id) == 0x1234 && CGDisplayModelNumber(id) == 0x5678,
                isActive: CGDisplayIsActive(id) != 0,
                mirrors: CGDisplayMirrorsDisplay(id),
                inMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
                identityKey: Self.identityKey(for: id)
            )
        }

        if selectedTargetID == nil || !targetDisplays.contains(where: { $0.id == selectedTargetID }) {
            selectedTargetID = targetDisplays.first?.id
        }

        handleExternalDisplayPresence()
    }

    func applySelectedMapping() {
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }

            do {
                let width = clamp(requestedWidth, min: 640, max: 8192)
                let height = clamp(requestedHeight, min: 480, max: 8192)
                guard let targetID = selectedTargetID,
                      targetDisplays.contains(where: { $0.id == targetID }) else {
                    status = "Pick a physical monitor first."
                    return
                }

                let virtualID = try createVirtualDisplay(width: width, height: height, hiDPI: requestedHiDPI)
                try setMirrorWithRetry(targetID: targetID, sourceID: virtualID)
                saveLastMapping(targetID: targetID, width: width, height: height, hiDPI: requestedHiDPI)
                refreshDisplays()
                status = "Mapped \(DisplayNames.name(for: targetID)) to \(width)x\(height)."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func applyLastMapping() {
        guard let mapping = loadBestMappingForConnectedMonitor() else {
            status = "No saved mapping yet."
            return
        }

        guard let targetID = resolveTargetID(for: mapping) else {
            status = "Saved monitor is not connected."
            return
        }

        selectedTargetID = targetID
        customWidth = "\(mapping.width)"
        customHeight = "\(mapping.height)"
        useHiDPI = mapping.hiDPI
        useCustomResolution = true
        applySelectedMapping()
    }

    func unmapSelected() {
        guard let targetID = selectedTargetID else {
            status = "Pick a physical monitor first."
            return
        }

        do {
            try setMirror(targetID: targetID, sourceID: kCGNullDirectDisplay)
            refreshDisplays()
            status = "Unmapped \(DisplayNames.name(for: targetID))."
        } catch {
            status = error.localizedDescription
        }
    }

    func removeVirtualDisplays() {
        for wrapper in virtualDisplays.values {
            wrapper.invalidate()
        }
        virtualDisplays.removeAll()
        refreshDisplays()
    }

    func toggleLaunchAtLogin() {
        do {
            try writeLaunchAgent(enabled: launchAtLogin)
            status = launchAtLogin ? "Auto-restore enabled." : "Auto-restore disabled."
        } catch {
            status = error.localizedDescription
        }
    }

    func triggerEasterEgg() {
        sparkleBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            self.sparkleBurst = false
        }
    }

    private func createVirtualDisplay(width: Int, height: Int, hiDPI: Bool) throws -> CGDirectDisplayID {
        if let existing = displays.first(where: {
            $0.isVirtual && Int($0.pixels.width) == width && Int($0.pixels.height) == height
        }) {
            return existing.id
        }

        let wrapper = VirtualDisplayWrapper.create(
            withName: "Mapper Virtual \(width)x\(height)",
            vendorID: 0x1234,
            productID: 0x5678,
            serialNumber: UInt32.random(in: 1...UInt32.max),
            sizeInMillimeters: CGSize(width: 600, height: 340),
            maxPixelsWide: 8192,
            maxPixelsHigh: 8192,
            terminationQueue: .main,
            terminationHandler: {}
        )

        guard let wrapper, wrapper.displayID != 0 else {
            throw MapperError.message("Could not create a virtual display.")
        }

        guard wrapper.applyWidth(UInt(width), height: UInt(height), refreshRate: 60, hiDPI: hiDPI) else {
            throw MapperError.message("Could not apply virtual display settings.")
        }

        virtualDisplays[wrapper.displayID] = wrapper
        Thread.sleep(forTimeInterval: 0.6)
        refreshDisplays()
        return wrapper.displayID
    }

    private func setMirror(targetID: CGDirectDisplayID, sourceID: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            throw MapperError.message("Could not begin display configuration.")
        }

        let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, targetID, sourceID)
        guard mirrorError == .success else {
            CGCancelDisplayConfiguration(config)
            throw MapperError.message("Mirror setup failed: \(mirrorError.rawValue).")
        }

        let completeError = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeError == .success else {
            CGCancelDisplayConfiguration(config)
            throw MapperError.message("Display configuration failed: \(completeError.rawValue).")
        }
    }

    private func setMirrorWithRetry(targetID: CGDirectDisplayID, sourceID: CGDirectDisplayID) throws {
        var lastError: Error?

        for _ in 0..<6 {
            do {
                try setMirror(targetID: targetID, sourceID: sourceID)
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.45)
                refreshDisplays()
            }
        }

        throw lastError ?? MapperError.message("Mirror setup failed.")
    }

    private func saveLastMapping(targetID: CGDirectDisplayID, width: Int, height: Int, hiDPI: Bool) {
        let monitorKey = Self.identityKey(for: targetID)
        let mapping = SavedMapping(targetDisplayID: targetID, monitorKey: monitorKey, width: width, height: height, hiDPI: hiDPI)
        if let data = try? JSONEncoder().encode(mapping) {
            defaults.set(data, forKey: savedMappingKey)
        }

        var mappings = loadMonitorMappings()
        mappings[monitorKey] = mapping
        if let data = try? JSONEncoder().encode(mappings) {
            defaults.set(data, forKey: monitorMappingsKey)
        }

        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        try? writeLaunchAgent(enabled: launchAtLogin)
    }

    private func loadLastMapping() -> SavedMapping? {
        guard let data = defaults.data(forKey: savedMappingKey) else { return nil }
        return try? JSONDecoder().decode(SavedMapping.self, from: data)
    }

    private func loadMonitorMappings() -> [String: SavedMapping] {
        guard let data = defaults.data(forKey: monitorMappingsKey),
              let mappings = try? JSONDecoder().decode([String: SavedMapping].self, from: data) else {
            return [:]
        }
        return mappings
    }

    private func loadBestMappingForConnectedMonitor() -> SavedMapping? {
        let mappings = loadMonitorMappings()
        for display in targetDisplays {
            if let mapping = mappings[display.identityKey] {
                return mapping
            }
        }

        guard let mapping = loadLastMapping(),
              resolveTargetID(for: mapping) != nil else {
            return nil
        }
        return mapping
    }

    private func resolveTargetID(for mapping: SavedMapping) -> CGDirectDisplayID? {
        if let monitorKey = mapping.monitorKey,
           let display = targetDisplays.first(where: { $0.identityKey == monitorKey }) {
            return display.id
        }

        if let display = targetDisplays.first(where: { $0.id == mapping.targetDisplayID }) {
            return display.id
        }

        return nil
    }

    private func restoreUIState() {
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        if let mapping = loadLastMapping() {
            selectedTargetID = resolveTargetID(for: mapping) ?? mapping.targetDisplayID
            customWidth = "\(mapping.width)"
            customHeight = "\(mapping.height)"
            useCustomResolution = true
            useHiDPI = mapping.hiDPI
        }
    }

    private func setupNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
                self?.applyLastMapping()
            }
        }
    }

    private func startDisplayMonitoring() {
        lastHadExternalTarget = !targetDisplays.isEmpty
        displayMonitoringReady = true
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }
    }

    private func handleExternalDisplayPresence() {
        let hasExternalTarget = !targetDisplays.isEmpty

        if !hasExternalTarget, lastHadExternalTarget || !virtualDisplays.isEmpty {
            removeVirtualDisplaysWithoutRefresh()
            status = "External monitor disconnected. Virtual displays removed."
        }

        if displayMonitoringReady, hasExternalTarget, !lastHadExternalTarget {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.applyLastMapping()
            }
        }

        lastHadExternalTarget = hasExternalTarget
    }

    private func removeVirtualDisplaysWithoutRefresh() {
        for wrapper in virtualDisplays.values {
            wrapper.invalidate()
        }
        virtualDisplays.removeAll()
    }

    private func writeLaunchAgent(enabled: Bool) throws {
        let fileManager = FileManager.default
        let dir = URL(fileURLWithPath: launchAgentPath).deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        if enabled {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key>
              <string>com.codex.resolution-mapper</string>
              <key>ProgramArguments</key>
              <array>
                <string>/usr/bin/open</string>
                <string>-gj</string>
                <string>\(appPath)</string>
              </array>
              <key>RunAtLoad</key>
              <true/>
            </dict>
            </plist>
            """
            try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
            shell("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath], ignoreFailure: true)
            shell("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath], ignoreFailure: true)
            shell("/bin/launchctl", ["enable", "gui/\(getuid())/com.codex.resolution-mapper"], ignoreFailure: true)
        } else {
            shell("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath], ignoreFailure: true)
            try? fileManager.removeItem(atPath: launchAgentPath)
        }
    }

    private func shell(_ path: String, _ arguments: [String], ignoreFailure: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        if !ignoreFailure && process.terminationStatus != 0 {
            status = "Command failed: \(path)"
        }
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    private static func identityKey(for id: CGDirectDisplayID) -> String {
        [
            CGDisplayVendorNumber(id),
            CGDisplayModelNumber(id),
            CGDisplaySerialNumber(id),
        ]
        .map(String.init)
        .joined(separator: "-")
    }
}

enum MapperError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}
