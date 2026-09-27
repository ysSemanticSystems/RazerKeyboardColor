import Foundation

enum Tips {
    static let color = "Sends this color to the whole Ornata V3 X backlight when the effect is Solid or Breathing. The well shows the last color this window sent, not a color read from the keys, so Spectrum or another program can leave the keyboard on a different color."
    static let preview = "Shows the color and intensity this window will send. It is not a view of the keys, so the keyboard can be dark or on another effect while this swatch stays bright."
    static let intensity = "Sets backlight brightness from 0 to 255 on the Ornata V3 X. Opening the window reads that byte back from the keyboard. If the read fails, the slider keeps the last value this window used and the keys can be brighter or dimmer than the number shows."
    static let solid = "Lights every key in the color above and leaves it there. It does not read the effect back, so a failed write can leave the previous pattern lit."
    static let breathing = "Fades every key in and out in the color above. It does not read the effect back, so a failed write can leave the previous pattern lit."
    static let spectrum = "Cycles the backlight through colors on the keyboard. The color well is not sent. A failed write can leave the previous pattern lit."
    static let off = "Turns the backlight off. A failed write can leave the previous pattern lit."
    static let refresh = "Scans USB again for a Razer Ornata V3 X lighting report. It can still say Connected when the keyboard is plugged in but macOS is blocking that report."
    static let link = "Says whether the 90-byte lighting report is open. Connected can stay up for a moment after the cable is pulled, until the next send or Look again."

    static func preset(_ name: String) -> String {
        "Sets every key to \(name) and the Solid effect. It does not read the keys, so a failed write can leave the previous color lit."
    }
}
