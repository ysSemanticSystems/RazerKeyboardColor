//
//  Tips.swift
//  KeyboardColor
//
//  Holds the sentence each control speaks on hover and to VoiceOver.
//  The sentence names the action, what it reads, and the failure that sentence can hide.
//

import Foundation

enum Tips {
    static let color = "Chooses the color sent with Solid and Breathing. The well is not a color read from the keys, so it can show a color the keyboard is not using until a command succeeds."
    static let preview = "Shows the last command this window got the keyboard to accept. Before that, and during Spectrum or Off, it is not a picture of the keys."
    static let intensity = "Sets backlight brightness from 0% to 100%. Opening the window reads the keyboard byte and shows it as a percent, so the slider can be one step off the stored value. 0% dims the current effect. Off is a separate control. If the read fails, the slider keeps the last value this window used."
    static let solid = "Lights every key in the color above and leaves it there. It does not read the effect back, so a failed write can leave the previous pattern lit."
    static let breathing = "Fades every key in and out in the color above. It does not read the effect back, so a failed write can leave the previous pattern lit."
    static let spectrum = "Cycles the backlight through colors on the keyboard. The color well is not sent. A failed write can leave the previous pattern lit."
    static let off = "Turns the backlight effect off. This is separate from 0% intensity, which only dims the current effect. A failed write can leave the previous pattern lit."
    static let refresh = "Reads the keyboard again. It does not clear a color this window already sent. It can still say Connected when the keyboard is plugged in but macOS is blocking lighting control."
    static let connected = "The lighting control is open. Connected can stay up for a moment after the cable is pulled, until the next send or Look again."
    static let notFound = "No Ornata V3 X lighting control is available. A sleeping hub can look the same as an unplugged keyboard."
    static let blocked = "macOS is blocking lighting control. The keys can still type."
    static let waiting = "This window has not yet had a command accepted. The keys can still be lit from earlier."
    static let applied = "The keyboard accepted the last effect, color, and intensity from this window. It does not report the effect back, so a change outside this window can leave the keys different."
    static let effectOn = "Names the effect this window last got the keyboard to accept. The keyboard does not report its effect, so this stays blank until a command succeeds, and a change outside this window can leave the keys on a different effect."
    static let notApplied = "The last command was not accepted. The keys can still show the previous pattern."
}
