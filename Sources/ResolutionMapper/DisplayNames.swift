import CoreGraphics
import Foundation

enum DisplayNames {
    static func name(for id: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(id) != 0 {
            return "Built-in Display"
        }

        if CGDisplayVendorNumber(id) == 0x1234, CGDisplayModelNumber(id) == 0x5678 {
            return "Mapper Virtual"
        }

        if CGDisplayVendorNumber(id) == 4268, CGDisplayModelNumber(id) == 16772 {
            return "DELL P2719H"
        }

        return "Display \(id)"
    }
}
