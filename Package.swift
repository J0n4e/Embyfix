// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "EmbyFlix",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "EmbyFlix", path: "Sources")]
)
