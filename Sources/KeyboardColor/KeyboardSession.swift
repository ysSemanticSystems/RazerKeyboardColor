//
//  KeyboardSession.swift
//  KeyboardColor
//
//  Finds the Ornata lighting interface and exchanges 90-byte feature reports with it.
//  The interface is opened without seizing it, so keystrokes keep going to the system.
//

import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

enum KeyboardLink {
    case connected
    case notFound
    case blocked
}

struct ReportError: Error {
    var message: String
}

enum KeyboardWrite {
    case waiting
    case applied
    case notApplied
}

struct KeyboardSnapshot: Sendable {
    var link: KeyboardLink
    var write: KeyboardWrite
    var productName: String
    var brightness: UInt8?
    var detail: String
}

final class KeyboardSession: @unchecked Sendable {
    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var productName = "Razer Ornata V3 X"
    /// True after this process has called `IOHIDRequestAccess`. A second call would stack a dialog or ask when macOS will not show one.
    private var askedThisLaunch = false

    /// Reads brightness and prints the link state. Used by `--probe`. Closes the device before returning.
    /// Does not request Input Monitoring. A modal prompt here would stall the check.
    func probe() -> String {
        let found = openLightingDevice(requestsAccess: false)
        var lines = ["link \(found.link)", "detail \(found.detail)", "product \(productName)"]
        if found.link == .connected {
            switch exchange(RazerReport.getBrightness()) {
            case .success(let response):
                if let level = RazerReport.brightness(from: response) {
                    lines.append("brightness \(level)")
                } else {
                    lines.append("brightness unreadable \(response.prefix(12).map { String(format: "%02x", $0) }.joined())")
                }
            case .failure(let error):
                lines.append("brightness failed \(error.message)")
            }
        }
        close()
        return lines.joined(separator: "\n") + "\n"
    }

    /// Opens the lighting report and reads brightness. Does not send a color.
    func refresh() -> KeyboardSnapshot {
        let found = openLightingDevice(requestsAccess: true)
        var brightness: UInt8?
        var write: KeyboardWrite = .waiting
        var detail = found.detail
        if found.link == .connected {
            switch exchange(RazerReport.getBrightness()) {
            case .success(let response):
                if let level = RazerReport.brightness(from: response) {
                    brightness = level
                    detail = "Read brightness from the keyboard."
                } else {
                    write = .notApplied
                    detail = "The keyboard answered, but the brightness byte was missing."
                }
            case .failure(let error):
                write = .notApplied
                detail = error.message
            }
        }
        return KeyboardSnapshot(
            link: found.link,
            write: write,
            productName: productName,
            brightness: brightness,
            detail: detail
        )
    }

    /// Sends the effect report, then the brightness register. Brightness is a second command.
    func apply(effect report: [UInt8], brightness: UInt8) -> KeyboardSnapshot {
        let found = openLightingDevice(requestsAccess: true)
        guard found.link == .connected else {
            return KeyboardSnapshot(
                link: found.link,
                write: .notApplied,
                productName: productName,
                brightness: nil,
                detail: found.detail
            )
        }
        if case .failure(let error) = exchange(report) {
            return KeyboardSnapshot(
                link: .connected,
                write: .notApplied,
                productName: productName,
                brightness: nil,
                detail: error.message
            )
        }
        if case .failure(let error) = exchange(RazerReport.setBrightness(brightness)) {
            return KeyboardSnapshot(
                link: .connected,
                write: .notApplied,
                productName: productName,
                brightness: nil,
                detail: error.message
            )
        }
        return KeyboardSnapshot(
            link: .connected,
            write: .applied,
            productName: productName,
            brightness: brightness,
            detail: "Sent to the keyboard."
        )
    }

    /// Matches vendor and product, then keeps the collection whose feature report is 90 bytes.
    /// `kIOHIDOptionsTypeNone` shares the device with the system. Seizing it would stop typing.
    private func openLightingDevice(requestsAccess: Bool) -> (link: KeyboardLink, detail: String) {
        guard mayOpenLighting(requestsAccess: requestsAccess) else {
            return (.blocked, LightingPermission.blockedDetail)
        }
        lock.lock()
        defer { lock.unlock() }

        if let device, featureLength(device) >= RazerReport.featureLength {
            return (.connected, "Connected to \(productName).")
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = RazerReport.productIDs.map { product in
            [
                kIOHIDVendorIDKey as String: RazerReport.vendorID,
                kIOHIDProductIDKey as String: product,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Matching callbacks land on the run loop. A short turn is enough to see the collections.
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.2, false)

        let devices = copyDevices(manager)
        let lighting = devices
            .filter { featureLength($0) >= RazerReport.featureLength }
            .sorted { usageRank($0) < usageRank($1) }

        guard let device = lighting.first else {
            if opened == kIOReturnNotPermitted {
                return (.blocked, LightingPermission.blockedDetail)
            }
            if devices.isEmpty {
                return (.notFound, "No Razer Ornata V3 X is on USB. A hub that is asleep can look the same as an unplugged keyboard.")
            }
            return (.notFound, "The keyboard is plugged in, but its lighting control did not appear.")
        }

        let deviceOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        // Exclusive access means the system already holds the device. Reports can still be sent.
        if deviceOpen != kIOReturnSuccess && deviceOpen != kIOReturnExclusiveAccess {
            if deviceOpen == kIOReturnNotPermitted {
                return (.blocked, LightingPermission.blockedDetail)
            }
            return (.notFound, "The lighting control would not open.")
        }

        self.device = device
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String, !name.isEmpty {
            productName = name
        }
        return (.connected, "Connected to \(productName).")
    }

    /// A denied choice does not show the system dialog again, so this must not call `IOHIDRequestAccess` after denial.
    /// The dialog is app-modal. Holding the device lock across it would deadlock a re-entrant refresh.
    private func mayOpenLighting(requestsAccess: Bool) -> Bool {
        let access = LightingPermission.listenAccess(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
        lock.lock()
        let step = LightingPermission.step(
            access: access,
            askedThisLaunch: askedThisLaunch,
            allowPrompt: requestsAccess
        )
        if step == .requestSystemPrompt {
            askedThisLaunch = true
        }
        lock.unlock()

        switch step {
        case .openDevice:
            return true
        case .requestSystemPrompt:
            if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
                return true
            }
            close()
            return false
        case .showSettings:
            close()
            return false
        }
    }

    /// Writes the report, waits, then reads it back. The board sometimes answers busy, so this tries five times.
    private func exchange(_ request: [UInt8]) -> Result<[UInt8], ReportError> {
        lock.lock()
        let device = self.device
        lock.unlock()
        guard let device else {
            return .failure(ReportError(message: "The keyboard is not connected."))
        }

        var last = "The keyboard did not accept the lighting report."
        for _ in 0..<5 {
            let sent = setFeature(device, request)
            if sent != kIOReturnSuccess {
                last = "The command was not sent (\(hex(sent)))."
                usleep(10_000)
                continue
            }
            usleep(1_000)
            switch getFeature(device) {
            case .success(let response):
                // Class and command must echo. Status 0x01 (busy) still means the board took the command.
                if response.count >= 8,
                   response[6] == request[6],
                   response[7] == request[7],
                   response[0] == 0x01 || response[0] == 0x02 {
                    return .success(response)
                }
                last = "The keyboard answered \(response.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " "))."
            case .failure(let error):
                last = error.message
            }
            usleep(10_000)
        }
        return .failure(ReportError(message: last))
    }

    /// Report id is 0, so the 90 payload bytes are the whole feature report.
    private func setFeature(_ device: IOHIDDevice, _ request: [UInt8]) -> IOReturn {
        request.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, base, request.count)
        }
    }

    private func getFeature(_ device: IOHIDDevice) -> Result<[UInt8], ReportError> {
        var buffer = [UInt8](repeating: 0, count: RazerReport.featureLength)
        var length = buffer.count
        let code = buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, base, &length)
        }
        if code != kIOReturnSuccess {
            return .failure(ReportError(message: "The keyboard did not answer (\(hex(code)))."))
        }
        return .success(Array(buffer.prefix(length)))
    }

    private func copyDevices(_ manager: IOHIDManager) -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        return (set as NSSet).allObjects.compactMap { object in
            let item = object as AnyObject
            guard CFGetTypeID(item) == IOHIDDeviceGetTypeID() else { return nil }
            return unsafeDowncast(item, to: IOHIDDevice.self)
        }
    }

    private func featureLength(_ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// The lighting collection presents as a pointer (usage page 1, usage 2) and carries the 90-byte feature.
    /// Keyboard collections on the same device do not. Prefer the pointer collection when several match.
    private func usageRank(_ device: IOHIDDevice) -> Int {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
        if page == 1 && usage == 2 { return 0 }
        return 1
    }

    private func hex(_ code: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: code))
    }

    private func close() {
        lock.lock()
        defer { lock.unlock() }
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        device = nil
        manager = nil
    }
}
