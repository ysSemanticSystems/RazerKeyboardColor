import AppKit
import SwiftUI

enum LightEffect: String, CaseIterable, Identifiable {
    case solid
    case breathing
    case spectrum
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .breathing: "Breathing"
        case .spectrum: "Spectrum"
        case .off: "Off"
        }
    }

    var tip: String {
        switch self {
        case .solid: Tips.solid
        case .breathing: Tips.breathing
        case .spectrum: Tips.spectrum
        case .off: Tips.off
        }
    }
}

struct Swatch: Identifiable {
    let name: String
    let color: Color
    var id: String { name }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var color = Color(red: 0, green: 0.8, blue: 0.35)
    @Published var brightness = 180.0
    @Published var effect: LightEffect = .solid
    @Published var link: KeyboardLink = .notFound
    @Published var write: KeyboardWrite = .waiting
    @Published var productName = "Razer Ornata V3 X"
    @Published var detail = "Looking for the keyboard."

    private let session = KeyboardSession()
    private var suppress = false
    private var armApply = false
    private var applyTask: Task<Void, Never>?

    let swatches = [
        Swatch(name: "White", color: .white),
        Swatch(name: "Red", color: .red),
        Swatch(name: "Green", color: .green),
        Swatch(name: "Blue", color: .blue),
        Swatch(name: "Yellow", color: .yellow),
        Swatch(name: "Purple", color: .purple),
    ]

    func refresh() {
        armApply = false
        let snapshot = session.refresh()
        suppress = true
        productName = snapshot.productName
        link = snapshot.link
        detail = snapshot.detail
        if let level = snapshot.brightness {
            brightness = Double(level)
            write = .waiting
        } else if snapshot.link != .connected {
            write = .waiting
        } else {
            write = snapshot.write
        }
        suppress = false
        Task { @MainActor in
            armApply = true
        }
    }

    func choose(_ effect: LightEffect) {
        self.effect = effect
        scheduleApply()
    }

    func choose(swatch: Swatch) {
        color = swatch.color
        effect = .solid
        scheduleApply()
    }

    func colorChanged() {
        guard armApply else { return }
        guard effect == .solid || effect == .breathing else { return }
        scheduleApply()
    }

    func brightnessChanged() {
        guard armApply else { return }
        scheduleApply()
    }

    private func scheduleApply() {
        guard !suppress else { return }
        applyTask?.cancel()
        let effect = effect
        let color = color
        let brightness = UInt8(clamping: Int(brightness.rounded()))
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let rgb = Self.bytes(from: color)
            let report: [UInt8]
            switch effect {
            case .solid:
                report = RazerReport.solid(red: rgb.0, green: rgb.1, blue: rgb.2)
            case .breathing:
                report = RazerReport.breathing(red: rgb.0, green: rgb.1, blue: rgb.2)
            case .spectrum:
                report = RazerReport.spectrum()
            case .off:
                report = RazerReport.off()
            }
            let snapshot = session.apply(effect: report, brightness: brightness)
            guard !Task.isCancelled else { return }
            productName = snapshot.productName
            link = snapshot.link
            write = snapshot.write
            detail = snapshot.detail
        }
    }

    private static func bytes(from color: Color) -> (UInt8, UInt8, UInt8) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8(clamping: Int((value * 255).rounded()))
        }
        return (byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent))
    }
}

private struct EffectButton: View {
    let effect: LightEffect
    var applied: Bool
    var action: () -> Void

    var body: some View {
        Button(applied ? "\(effect.title) on" : effect.title, action: action)
            .buttonStyle(.bordered)
            .help(effect.tip)
            .accessibilityLabel(applied ? "\(effect.title), on" : effect.title)
            .accessibilityHint(effect.tip)
            .accessibilityAddTraits(applied ? .isSelected : [])
    }
}

struct ContentView: View {
    @StateObject private var model = KeyboardModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            preview
            colorRow
            intensityRow
            effectRow
            swatchRow
            Text(model.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.detail)
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            NSApplication.shared.activate()
            model.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard color")
                .font(.title2.weight(.semibold))
            Text(model.productName)
                .font(.headline)
            HStack(spacing: 12) {
                statusWord(model.link.title, tint: model.link.tint, tip: Tips.link)
                statusWord(model.write.title, tint: model.write.tint, tip: Tips.link)
                Button("Look again") {
                    model.refresh()
                }
                .help(Tips.refresh)
                .accessibilityHint(Tips.refresh)
            }
        }
    }

    private var preview: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(model.color.opacity(model.brightness / 255))
            .frame(height: 72)
            .overlay(alignment: .bottomLeading) {
                Text("Preview")
                    .font(.caption.weight(.medium))
                    .padding(8)
                    .foregroundStyle(model.brightness > 140 ? Color.black : Color.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator)
            }
            .help(Tips.preview)
            .accessibilityLabel("Preview")
            .accessibilityHint(Tips.preview)
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.headline)
            HStack {
                ColorPicker("Backlight color", selection: $model.color, supportsOpacity: false)
                    .labelsHidden()
                    .help(Tips.color)
                    .accessibilityLabel("Backlight color")
                    .accessibilityHint(Tips.color)
                    .onChange(of: model.color) { _, _ in
                        model.colorChanged()
                    }
                Text("Sent with Solid and Breathing. Not read back from the keys.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intensity")
                    .font(.headline)
                Spacer()
                Text("\(Int(model.brightness.rounded())) of 255")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(Int(model.brightness.rounded())) of 255")
            }
            Slider(value: $model.brightness, in: 0...255, step: 1) {
                Text("Intensity")
            }
            .help(Tips.intensity)
            .accessibilityLabel("Intensity")
            .accessibilityHint(Tips.intensity)
            .accessibilityValue("\(Int(model.brightness.rounded())) of 255")
            .onChange(of: model.brightness) { _, _ in
                model.brightnessChanged()
            }
        }
    }

    private var effectRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effect")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(LightEffect.allCases) { effect in
                    EffectButton(
                        effect: effect,
                        applied: model.write == .applied && model.effect == effect
                    ) {
                        model.choose(effect)
                    }
                }
            }
        }
    }

    private var swatchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Solid colors")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(model.swatches) { swatch in
                    Button(swatch.name) {
                        model.choose(swatch: swatch)
                    }
                    .buttonStyle(.bordered)
                    .help(Tips.preset(swatch.name))
                    .accessibilityHint(Tips.preset(swatch.name))
                }
            }
        }
    }

    private func statusWord(_ word: String, tint: Color, tip: String) -> some View {
        Text(word)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .help(tip)
            .accessibilityHint(tip)
    }
}

extension KeyboardLink {
    var title: String {
        switch self {
        case .connected: "Connected"
        case .notFound: "Not found"
        case .blocked: "Blocked"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .teal
        case .notFound: .orange
        case .blocked: .orange
        }
    }
}

extension KeyboardWrite {
    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .applied: "Applied"
        case .notApplied: "Not applied"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: .primary
        case .applied: .green
        case .notApplied: .red
        }
    }
}
