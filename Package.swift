// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolutionMapper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "ResolutionMapper",
            dependencies: ["VirtualDisplayBridge"],
            path: "Sources/ResolutionMapper",
            resources: [.process("../../Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
