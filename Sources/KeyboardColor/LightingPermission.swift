//
//  LightingPermission.swift
//  KeyboardColor
//
//  Decides when a launch may ask for Input Monitoring, and the words the window uses when it cannot.
//  The decision is pure so `--check` can run it without a keyboard and without a system dialog.
//

import Foundation
import IOKit.hidsystem

enum ListenAccess: Equatable {
    case granted
    case denied
    case unknown
}

enum PermissionStep: Equatable {
    /// Open the lighting interface. No permission UI.
    case openDevice
    /// Call `IOHIDRequestAccess` once. The system dialog appears only while the choice is still unknown.
    case requestSystemPrompt
    /// The system dialog will not appear. Show Blocked and the Settings button.
    case showSettings
}

enum LightingPermission {
    /// Shown when the window says Blocked. The README uses this same sentence.
    static let blockedDetail = "Input Monitoring is off, so this window cannot change the backlight. The keys can still type. Open Input Monitoring, allow this app, then click Look again."

    static let settingsButton = "Open Input Monitoring"

    /// Shown when the Settings URL does not open. Look again still reads the choice.
    static let settingsDidNotOpen = "System Settings did not open. Input Monitoring is under Privacy & Security. Allow this app there, then click Look again."

    /// Privacy & Security → Input Monitoring on macOS 14 and later.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!

    /// A denied listen-event choice does not show the system dialog on a later launch, so a reopen must show Settings instead of calling `IOHIDRequestAccess`.
    /// `allowPrompt` is false for `--probe` and after this launch already asked. A modal dialog there would stall the probe or stack a second prompt.
    static func step(access: ListenAccess, askedThisLaunch: Bool, allowPrompt: Bool) -> PermissionStep {
        switch access {
        case .granted:
            return .openDevice
        case .denied:
            return .showSettings
        case .unknown:
            if allowPrompt && !askedThisLaunch {
                return .requestSystemPrompt
            }
            return .showSettings
        }
    }

    static func listenAccess(_ raw: IOHIDAccessType) -> ListenAccess {
        switch raw {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .unknown
        }
    }

    /// Color, intensity, and effects send only while the lighting interface is open.
    static func lightingControlsEnabled(link: KeyboardLink) -> Bool {
        link == .connected
    }

    /// "Waiting" next to Blocked reads as a second, unexplained state.
    static func showsWriteState(link: KeyboardLink) -> Bool {
        link != .blocked
    }

    /// The note beside a disabled color well. Blocked is a permission, not a missing keyboard.
    static func unavailableNote(link: KeyboardLink) -> String {
        switch link {
        case .blocked:
            "Unavailable until Input Monitoring is allowed."
        case .notFound, .connected:
            "Unavailable until the keyboard is connected."
        }
    }

    /// Runs from `--check`. No device and no system dialog.
    static func check() {
        precondition(
            step(access: .granted, askedThisLaunch: false, allowPrompt: true) == .openDevice,
            "granted access opens the device"
        )
        precondition(
            step(access: .granted, askedThisLaunch: true, allowPrompt: false) == .openDevice,
            "granted access opens the device even when a prompt is not allowed"
        )
        precondition(
            step(access: .unknown, askedThisLaunch: false, allowPrompt: true) == .requestSystemPrompt,
            "a fresh launch asks again while Input Monitoring is still undecided"
        )
        precondition(
            step(access: .unknown, askedThisLaunch: true, allowPrompt: true) == .showSettings,
            "a second ask in the same launch must not stack another dialog"
        )
        precondition(
            step(access: .unknown, askedThisLaunch: false, allowPrompt: false) == .showSettings,
            "probe must not raise a modal dialog"
        )
        precondition(
            step(access: .denied, askedThisLaunch: false, allowPrompt: true) == .showSettings,
            "a denial must show Settings instead of requesting a dialog that will not appear"
        )
        precondition(
            step(access: .denied, askedThisLaunch: true, allowPrompt: false) == .showSettings,
            "a denial stays on Settings"
        )
        precondition(listenAccess(kIOHIDAccessTypeGranted) == .granted)
        precondition(listenAccess(kIOHIDAccessTypeDenied) == .denied)
        precondition(listenAccess(kIOHIDAccessTypeUnknown) == .unknown)
        precondition(blockedDetail.contains(settingsButton))
        precondition(blockedDetail.contains("The keys can still type."))
        precondition(blockedDetail.contains("Look again"))
        precondition(!blockedDetail.contains("No keyboard"))
        precondition(settingsDidNotOpen != blockedDetail)
        precondition(settingsDidNotOpen.contains("Look again"))
        precondition(settingsURL.absoluteString.contains("Privacy_ListenEvent"))
        precondition(lightingControlsEnabled(link: .connected))
        precondition(!lightingControlsEnabled(link: .blocked))
        precondition(!lightingControlsEnabled(link: .notFound))
        precondition(!showsWriteState(link: .blocked))
        precondition(showsWriteState(link: .connected))
        precondition(showsWriteState(link: .notFound))
        precondition(unavailableNote(link: .blocked) == "Unavailable until Input Monitoring is allowed.")
        precondition(unavailableNote(link: .notFound) == "Unavailable until the keyboard is connected.")
        precondition(unavailableNote(link: .blocked) != unavailableNote(link: .notFound))
    }
}
