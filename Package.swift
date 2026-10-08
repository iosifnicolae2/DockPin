// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DockPin",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DockPinCore"),
        .executableTarget(name: "DockPin", dependencies: ["DockPinCore"]),
        .testTarget(name: "DockPinCoreTests", dependencies: ["DockPinCore"]),
    ]
)
