// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardColor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeyboardColor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
