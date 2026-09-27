import Foundation
import IOKit
import IOKit.hid

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

    func probe() -> String {
        let found = openLightingDevice()
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

    func refresh() -> KeyboardSnapshot {
        let found = openLightingDevice()
        var brightness: UInt8?
        var write: KeyboardWrite = .waiting
        var detail = found.detail
        if found.link == .connected {
            switch exchange(RazerReport.getBrightness()) {
            case .success(let response):
                if let level = RazerReport.brightness(from: response) {
                    brightness = level
                    detail = "Read backlight brightness \(level) of 255 from the keyboard."
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

    func apply(effect report: [UInt8], brightness: UInt8) -> KeyboardSnapshot {
        let found = openLightingDevice()
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
            detail: "Sent the lighting report and brightness \(brightness) of 255."
        )
    }

    private func openLightingDevice() -> (link: KeyboardLink, detail: String) {
        lock.lock()
        defer { lock.unlock() }

        if let device, featureLength(device) >= RazerReport.featureLength {
            return (.connected, "Lighting report is open.")
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
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.2, false)

        let devices = copyDevices(manager)
        let lighting = devices
            .filter { featureLength($0) >= RazerReport.featureLength }
            .sorted { usageRank($0) < usageRank($1) }

        guard let device = lighting.first else {
            if opened == kIOReturnNotPermitted {
                return (.blocked, "macOS blocked the lighting report. Input Monitoring can hide the keyboard from this window even while the keys still type.")
            }
            let seen = devices.map { describe($0) }.joined(separator: "; ")
            if seen.isEmpty {
                return (.notFound, "No Razer Ornata V3 X is on USB. A hub that is asleep can look the same as an unplugged keyboard.")
            }
            return (.notFound, "The keyboard is on USB, but none of its reports are the 90-byte lighting report. Saw \(seen).")
        }

        let deviceOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if deviceOpen != kIOReturnSuccess && deviceOpen != kIOReturnExclusiveAccess {
            if deviceOpen == kIOReturnNotPermitted {
                return (.blocked, "macOS blocked the lighting report. Input Monitoring can hide the keyboard from this window even while the keys still type.")
            }
            return (.notFound, "The lighting report would not open (\(hex(deviceOpen))).")
        }

        self.device = device
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String, !name.isEmpty {
            productName = name
        }
        return (.connected, "Opened the \(featureLength(device))-byte lighting report on \(productName).")
    }

    private func exchange(_ request: [UInt8]) -> Result<[UInt8], ReportError> {
        lock.lock()
        let device = self.device
        lock.unlock()
        guard let device else {
            return .failure(ReportError(message: "The lighting report is not open."))
        }

        var last = "The keyboard did not accept the lighting report."
        for _ in 0..<5 {
            let sent = setFeature(device, request)
            if sent != kIOReturnSuccess {
                last = "The lighting report was not sent (\(hex(sent)))."
                usleep(10_000)
                continue
            }
            usleep(1_000)
            switch getFeature(device) {
            case .success(let response):
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
            return .failure(ReportError(message: "The keyboard did not return the lighting report (\(hex(code)))."))
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

    private func usageRank(_ device: IOHIDDevice) -> Int {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
        if page == 1 && usage == 2 { return 0 }
        return 1
    }

    private func describe(_ device: IOHIDDevice) -> String {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? -1
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? -1
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? -1
        return String(format: "pid 0x%04X usage %d/%d feature %d", product, page, usage, featureLength(device))
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
