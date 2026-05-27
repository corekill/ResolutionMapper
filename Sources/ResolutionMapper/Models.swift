import CoreGraphics
import Foundation

struct DisplayItem: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let pixels: CGSize
    let isBuiltIn: Bool
    let isVirtual: Bool
    let isActive: Bool
    let mirrors: CGDirectDisplayID
    let inMirrorSet: Bool
    let identityKey: String

    var label: String {
        let size = "\(Int(pixels.width))x\(Int(pixels.height))"
        if isBuiltIn { return "\(name) - \(size)" }
        if isVirtual { return "\(name) - virtual \(size)" }
        return "\(name) - \(size)"
    }
}

struct ResolutionPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String
    let width: Int
    let height: Int
    let hiDPI: Bool

    static let all: [ResolutionPreset] = [
        .init(name: "QHD Space", detail: "2560 x 1440, current sweet spot", width: 2560, height: 1440, hiDPI: false),
        .init(name: "Soft QHD", detail: "2304 x 1296, larger and calmer text", width: 2304, height: 1296, hiDPI: false),
        .init(name: "Wide Workbench", detail: "3200 x 1800, more space", width: 3200, height: 1800, hiDPI: false),
        .init(name: "4K Downsample", detail: "3840 x 2160, sharper but smaller", width: 3840, height: 2160, hiDPI: false),
        .init(name: "Native FHD", detail: "1920 x 1080, no downsample", width: 1920, height: 1080, hiDPI: false),
    ]
}

struct SavedMapping: Codable {
    var targetDisplayID: UInt32
    var monitorKey: String?
    var width: Int
    var height: Int
    var hiDPI: Bool
}
