//
//  KeyboardColorApp.swift
//  KeyboardColor
//
//  Opens the Keyboard color window, or answers a command-line check and exits.
//  The process stays a normal app so the window can come forward and accept a stop signal.
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
            FileHandle.standardOutput.write(Data("packet check passed\n".utf8))
            Darwin.exit(0)
        }
        // A parent that tracks this process stops it with SIGTERM. The default GUI handler would ignore that.
        signal(SIGTERM) { _ in
            Darwin.exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Keyboard color") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
