// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WizBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WizKit", path: "Sources/WizKit"),
        .executableTarget(name: "WizBar", dependencies: ["WizKit"], path: "Sources/WizBar"),
        .testTarget(name: "WizKitTests", dependencies: ["WizKit"], path: "Tests/WizKitTests"),
    ]
)
