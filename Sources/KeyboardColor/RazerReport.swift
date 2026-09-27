//
//  RazerReport.swift
//  KeyboardColor
//
//  Builds the 90-byte feature reports the Ornata V3 X accepts for its backlight.
//  The keyboard stores one color for the whole deck, plus a separate brightness byte.
//

import Foundation

enum RazerReport {
    /// Razer USB vendor ID.
    static let vendorID = 0x1532

    /// Both product IDs sold as the Ornata V3 X.
    static let productIDs: Set<Int> = [0x02A2, 0x0294]

    /// Host-to-device transaction used by this generation of Ornata boards.
    static let transactionID: UInt8 = 0x1F

    /// Extended matrix command class. Older boards use 0x03 instead.
    static let commandClass: UInt8 = 0x0F

    /// Write the value into the keyboard's stored profile, not a temporary slot.
    static let stored: UInt8 = 0x01

    /// The single backlight zone. Logo and macro LEDs use different IDs.
    static let backlight: UInt8 = 0x05

    /// Feature report length advertised by the lighting interface.
    static let featureLength = 90

    /// Steady color. Effect id 0x01, then a one-color RGB triple.
    static func solid(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        report(
            command: 0x02,
            dataSize: 0x09,
            arguments: [stored, backlight, 0x01, 0x00, 0x00, 0x01, red, green, blue]
        )
    }

    /// Fade in and out. Effect id 0x02 with a single stored color.
    static func breathing(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        report(
            command: 0x02,
            dataSize: 0x09,
            arguments: [stored, backlight, 0x02, 0x01, 0x00, 0x01, red, green, blue]
        )
    }

    /// Cycle colors on the keyboard. The color well is not part of this report.
    static func spectrum() -> [UInt8] {
        report(command: 0x02, dataSize: 0x06, arguments: [stored, backlight, 0x03])
    }

    /// Effect id 0x00 turns the zone off without changing the stored color.
    static func off() -> [UInt8] {
        report(command: 0x02, dataSize: 0x06, arguments: [stored, backlight, 0x00])
    }

    /// Brightness is its own command. It is not encoded in the RGB bytes.
    static func setBrightness(_ brightness: UInt8) -> [UInt8] {
        report(command: 0x04, dataSize: 0x03, arguments: [stored, backlight, brightness])
    }

    /// Same register as setBrightness. The high bit marks the command as a read.
    static func getBrightness() -> [UInt8] {
        report(command: 0x84, dataSize: 0x03, arguments: [stored, backlight])
    }

    /// Brightness comes back as argument 2. Status 0x01 is busy and still valid; 0x02 is success.
    static func brightness(from response: [UInt8]) -> UInt8? {
        guard response.count >= 11 else { return nil }
        let status = response[0]
        guard status == 0x01 || status == 0x02 else { return nil }
        return response[10]
    }

    /// Layout: status, transaction, big-endian remaining count, protocol, size, class, command, 80 argument bytes, XOR checksum, reserved.
    /// The checksum covers bytes 2 through 87. Byte 0 stays zero on a new command.
    static func report(command: UInt8, dataSize: UInt8, arguments: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: featureLength)
        bytes[1] = transactionID
        bytes[5] = dataSize
        bytes[6] = commandClass
        bytes[7] = command
        for (index, byte) in arguments.enumerated() where index < 80 {
            bytes[8 + index] = byte
        }
        var crc: UInt8 = 0
        for index in 2..<88 {
            crc ^= bytes[index]
        }
        bytes[88] = crc
        return bytes
    }

    /// Confirms the static-red and brightness packets, including their checksums, without opening a device.
    static func check() {
        let solid = solid(red: 0xFF, green: 0x00, blue: 0x00)
        precondition(solid.count == 90)
        precondition(Array(solid.prefix(18)) == [
            0x00, 0x1F, 0x00, 0x00, 0x00, 0x09, 0x0F, 0x02,
            0x01, 0x05, 0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00, 0x00,
        ])
        precondition(solid[88] == 0xFF)
        let set = setBrightness(0x80)
        precondition(set[88] == 0x8C)
        precondition(getBrightness()[88] == 0x8C)
        var response = [UInt8](repeating: 0, count: 90)
        response[0] = 0x02
        response[10] = 0x40
        precondition(brightness(from: response) == 0x40)
        response[0] = 0x03
        precondition(brightness(from: response) == nil)
    }
}
