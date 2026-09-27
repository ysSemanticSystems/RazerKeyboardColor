import Foundation

enum RazerReport {
    static let vendorID = 0x1532
    static let productIDs: Set<Int> = [0x02A2, 0x0294]
    static let transactionID: UInt8 = 0x1F
    static let commandClass: UInt8 = 0x0F
    static let stored: UInt8 = 0x01
    static let backlight: UInt8 = 0x05
    static let featureLength = 90

    static func solid(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        report(
            command: 0x02,
            dataSize: 0x09,
            arguments: [stored, backlight, 0x01, 0x00, 0x00, 0x01, red, green, blue]
        )
    }

    static func breathing(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        report(
            command: 0x02,
            dataSize: 0x09,
            arguments: [stored, backlight, 0x02, 0x01, 0x00, 0x01, red, green, blue]
        )
    }

    static func spectrum() -> [UInt8] {
        report(command: 0x02, dataSize: 0x06, arguments: [stored, backlight, 0x03])
    }

    static func off() -> [UInt8] {
        report(command: 0x02, dataSize: 0x06, arguments: [stored, backlight, 0x00])
    }

    static func setBrightness(_ brightness: UInt8) -> [UInt8] {
        report(command: 0x04, dataSize: 0x03, arguments: [stored, backlight, brightness])
    }

    static func getBrightness() -> [UInt8] {
        report(command: 0x84, dataSize: 0x03, arguments: [stored, backlight])
    }

    static func brightness(from response: [UInt8]) -> UInt8? {
        guard response.count >= 11 else { return nil }
        let status = response[0]
        guard status == 0x01 || status == 0x02 else { return nil }
        return response[10]
    }

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
