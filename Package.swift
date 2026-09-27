// swift-tools-version: 6.0

//
//  Package.swift
//  KeyboardColor
//
//  Builds the macOS window that sets Ornata V3 X backlight color and brightness.
//  AppKit and IOKit stay system frameworks so the executable does not embed them.
//

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
