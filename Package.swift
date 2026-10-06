// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLoom",
    platforms: [.macOS("15.2")],
    products: [
        .executable(name: "OpenLoom", targets: ["OpenLoom"]),
        .library(name: "OpenLoomCore", targets: ["OpenLoomCore"]),
        .executable(name: "OpenLoomPrivacyProbe", targets: ["OpenLoomPrivacyProbe"]),
    ],
    targets: [
        .target(name: "OpenLoomCore", path: "general/macos/Sources/OpenLoomCore"),
        .executableTarget(name: "OpenLoom", dependencies: ["OpenLoomCore"], path: "general/macos/Sources/OpenLoom"),
        .executableTarget(name: "OpenLoomPrivacyProbe", path: "general/macos/Diagnostics"),
        .testTarget(name: "OpenLoomCoreTests", dependencies: ["OpenLoomCore"], path: "general/macos/Tests/OpenLoomCoreTests"),
    ],
    swiftLanguageModes: [.v6]
)
