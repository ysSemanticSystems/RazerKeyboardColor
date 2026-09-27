import AppKit
import Darwin
import SwiftUI

@main
struct KeyboardColorApp: App {
    init() {
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
