//
//  KeyboardColorApp.swift
//  KeyboardColor
//
//  Opens the Keyboard color window, or answers a command-line check and exits.
//  The process stays a normal app, loads AppIcon.icns for the Dock, and accepts a stop signal.
//

import AppKit
import Darwin
import SwiftUI

@main
struct KeyboardColorApp: App {
    init() {
        // Both flags finish before SwiftUI starts, so a check never flashes a window.
        if CommandLine.arguments.contains("--probe") {
            let text = KeyboardSession().probe()
            FileHandle.standardOutput.write(Data(text.utf8))
            Darwin.exit(0)
        }
        if CommandLine.arguments.contains("--check") {
            RazerReport.check()
            LightingPermission.check()
            FileHandle.standardOutput.write(Data("packet check passed\n".utf8))
            Darwin.exit(0)
        }
        // A parent that tracks this process stops it with SIGTERM. The default GUI handler would ignore that.
        signal(SIGTERM) { _ in
            Darwin.exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
        applyDockIcon()
    }

    /// Prefer the app bundle so a copy in Applications still shows the mark. Bundle.module is the SwiftPM build.
    private func applyDockIcon() {
        let urls = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
        ]
        for url in urls {
            if let url, let icon = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = icon
                return
            }
        }
    }

    var body: some Scene {
        WindowGroup("Razer Color Manager") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
