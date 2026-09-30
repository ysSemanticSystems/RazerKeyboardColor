//
//  ContentView.swift
//  KeyboardColor
//
//  Draws the color, intensity, and effect controls and sends them to the keyboard.
//  A refresh reads brightness only. It must not write a color, or opening the window would change the lights.
//

import AppKit
import SwiftUI

/// Effects the Ornata V3 X backlight accepts. Wave and per-key color are not on this board.
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

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var color = Color(red: 0, green: 0.8, blue: 0.35)
    /// Percent on the slider. The keyboard stores a byte, so this is rounded on the way in and out.
    @Published var brightness = 100.0
    @Published var effect: LightEffect = .solid
    @Published var link: KeyboardLink = .notFound
    @Published var write: KeyboardWrite = .waiting
    @Published var productName = "Razer Ornata V3 X"
    @Published var detail = "Looking for the keyboard."

    private let session = KeyboardSession()
    /// True while refresh is writing published values, so those writes do not send a report.
    private var suppress = false
    /// False until the open-time read has settled. A color echo during that read must not send.
    private var armApply = false
    /// True only while the pointer is on the slider. A brightness read must not count as a drag.
    private var sliding = false
    /// Value just read. Dragging the slider without leaving this value does not send.
    private var readBrightness: Double?
    /// Color held after a read. The well can echo it; that echo is not a new choice.
    private var heldColor: (UInt8, UInt8, UInt8)?
    private var applyTask: Task<Void, Never>?

    func refresh() {
        armApply = false
        // A brightness read is not a color read. Clearing Applied would claim the last command was dropped.
        let keptApplied = write == .applied
        let snapshot = session.refresh()
        suppress = true
        productName = snapshot.productName
        link = snapshot.link
        if let level = snapshot.brightness {
            brightness = Self.percent(from: level)
            readBrightness = brightness
            detail = "Brightness on the keyboard is \(Int(brightness.rounded()))%."
            write = snapshot.link == .connected && keptApplied ? .applied : .waiting
        } else if snapshot.link != .connected {
            write = .waiting
            detail = snapshot.detail
        } else {
            write = snapshot.write
            detail = snapshot.detail
        }
        sliding = false
        heldColor = Self.bytes(from: color)
        suppress = false
        // onChange from the brightness read runs before this hop, so it cannot send a color.
        Task { @MainActor in
            armApply = true
        }
    }

    func setSliding(_ editing: Bool) {
        sliding = editing
    }

    func choose(_ effect: LightEffect) {
        self.effect = effect
        scheduleApply()
    }

    func colorChanged() {
        guard armApply else { return }
        guard effect == .solid || effect == .breathing else { return }
        let rgb = Self.bytes(from: color)
        if let heldColor, rgb == heldColor { return }
        heldColor = nil
        scheduleApply()
    }

    func brightnessChanged() {
        guard sliding else { return }
        if let readBrightness, brightness == readBrightness { return }
        readBrightness = nil
        scheduleApply()
    }

    /// Coalesces slider and color-well updates. The board answers one report at a time.
    private func scheduleApply() {
        guard !suppress else { return }
        applyTask?.cancel()
        let effect = effect
        let color = color
        let brightness = Self.byte(from: brightness)
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

    func openInputMonitoring() {
        if NSWorkspace.shared.open(LightingPermission.settingsURL) { return }
        detail = LightingPermission.settingsDidNotOpen
    }

    /// The board stores brightness as a byte. The slider is a percent, so 100% is 255 and 0% is 0.
    static func percent(from byte: UInt8) -> Double {
        (Double(byte) * 100 / 255).rounded()
    }

    static func byte(from percent: Double) -> UInt8 {
        UInt8(clamping: Int((percent / 100 * 255).rounded()))
    }

    /// The well can be in a display color space. The keyboard wants 8-bit sRGB.
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
        button
            .help(effect.tip)
            .accessibilityLabel(applied ? "\(effect.title), on" : effect.title)
            .accessibilityHint(effect.tip)
            .accessibilityAddTraits(applied ? .isSelected : [])
    }

    /// The filled button and the word "on" mark the effect the keyboard accepted. Color is not the only signal.
    @ViewBuilder
    private var button: some View {
        if applied {
            Button(action: action) {
                Label("\(effect.title) on", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button(effect.title, action: action)
                .buttonStyle(.bordered)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = KeyboardModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if model.link == .blocked {
                blockedPanel
            } else {
                preview
            }
            colorRow
            intensityRow
            effectRow
            if model.link != .blocked {
                Text(model.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(model.detail)
            }
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
            Text(model.productName)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                statusWord(model.link.title, tint: model.link.tint, tip: model.link.tip)
                if LightingPermission.showsWriteState(link: model.link) {
                    statusWord(model.write.title, tint: model.write.tint, tip: model.write.tip)
                    if model.link == .connected, model.write == .applied {
                        effectMark
                    }
                }
                Button("Look again") {
                    model.refresh()
                }
                .help(Tips.refresh)
                .accessibilityHint(Tips.refresh)
            }
        }
    }

    /// Replaces the color swatch. A gray "No keyboard" bar would hide that Input Monitoring is the reason the controls are off.
    private var blockedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Blocked", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .help(Tips.blocked)
                .accessibilityLabel("Blocked")
                .accessibilityHint(Tips.blocked)
            Text(model.detail)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button(LightingPermission.settingsButton) {
                model.openInputMonitoring()
            }
            .buttonStyle(.borderedProminent)
            .help(Tips.openInputMonitoring)
            .accessibilityHint(Tips.openInputMonitoring)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange, lineWidth: 1)
        }
    }

    /// The last accepted command. Before a write succeeds, the well is only a choice in this window.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            previewShape
                .frame(height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.separator)
                }
            previewCaptionView
        }
        .help(Tips.preview)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(previewCaption)
        .accessibilityHint(Tips.preview)
    }

    @ViewBuilder
    private var previewShape: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        switch previewKind {
        case .disconnected:
            shape.fill(Color.secondary.opacity(0.2))
        case .unsent:
            shape.fill(model.color.opacity(0.25))
        case .color:
            shape.fill(model.color.opacity(model.brightness / 100))
        case .spectrum:
            shape.fill(
                LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .off:
            shape.fill(Color(white: 0.12))
        }
    }

    private var previewKind: PreviewKind {
        guard model.link == .connected else { return .disconnected }
        guard model.write == .applied else { return .unsent }
        switch model.effect {
        case .solid, .breathing: return .color
        case .spectrum: return .spectrum
        case .off: return .off
        }
    }

    @ViewBuilder
    private var previewCaptionView: some View {
        switch previewKind {
        case .disconnected, .unsent:
            Text(previewCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        case .color, .spectrum, .off:
            Label(previewCaption, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
    }

    private var previewCaption: String {
        switch previewKind {
        case .disconnected: "No keyboard"
        case .unsent: "Not sent"
        case .color: "\(model.effect.title) on, \(Int(model.brightness.rounded()))%"
        case .spectrum: "Spectrum on"
        case .off: "Off"
        }
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
                Text(colorNote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!LightingPermission.lightingControlsEnabled(link: model.link))
    }

    private var colorNote: String {
        guard model.link == .connected else {
            return LightingPermission.unavailableNote(link: model.link)
        }
        guard model.write == .applied else {
            return "Not sent. This is not the color on the keys."
        }
        switch model.effect {
        case .solid, .breathing:
            return "On the keys."
        case .spectrum:
            return "Held here. The keys are cycling through colors."
        case .off:
            return "Held here. The backlight is off."
        }
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intensity")
                    .font(.headline)
                Spacer()
                Text(intensityReadout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(intensityReadoutLabel)
            }
            Slider(value: $model.brightness, in: 0...100, step: 1) {
                Text("Intensity")
            } onEditingChanged: { editing in
                model.setSliding(editing)
            }
            .help(Tips.intensity)
            .accessibilityLabel("Intensity")
            .accessibilityHint(Tips.intensity)
            .accessibilityValue(intensityReadoutLabel)
            .onChange(of: model.brightness) { _, _ in
                model.brightnessChanged()
            }
        }
        .disabled(!LightingPermission.lightingControlsEnabled(link: model.link))
    }

    /// A percent before a successful read would claim a brightness the keyboard did not report.
    private var intensityReadout: String {
        guard LightingPermission.lightingControlsEnabled(link: model.link) else {
            return "Unavailable"
        }
        return "\(Int(model.brightness.rounded()))%"
    }

    private var intensityReadoutLabel: String {
        guard LightingPermission.lightingControlsEnabled(link: model.link) else {
            return "Unavailable"
        }
        return "\(Int(model.brightness.rounded())) percent"
    }

    private var effectRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effect")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(LightEffect.allCases) { effect in
                    EffectButton(
                        effect: effect,
                        applied: model.link == .connected && model.write == .applied && model.effect == effect
                    ) {
                        model.choose(effect)
                    }
                }
            }
        }
        .disabled(!LightingPermission.lightingControlsEnabled(link: model.link))
    }

    /// Shown only after a write succeeds. The keyboard never reports which effect is lit.
    private var effectMark: some View {
        Label(model.effect.title, systemImage: "checkmark.circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.green)
            .help(Tips.effectOn)
            .accessibilityLabel("\(model.effect.title) on")
            .accessibilityHint(Tips.effectOn)
    }

    private func statusWord(_ word: String, tint: Color, tip: String) -> some View {
        Text(word)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .help(tip)
            .accessibilityHint(tip)
    }
}

/// Words carry the state. Color repeats the word and is never the only signal.
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

    var tip: String {
        switch self {
        case .connected: Tips.connected
        case .notFound: Tips.notFound
        case .blocked: Tips.blocked
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

    var tip: String {
        switch self {
        case .waiting: Tips.waiting
        case .applied: Tips.applied
        case .notApplied: Tips.notApplied
        }
    }
}

private enum PreviewKind {
    case disconnected
    case unsent
    case color
    case spectrum
    case off
}
