# Keyboard color for the Razer Ornata V3 X

A MacOS application which sets the RGB color, brightness, and lighting effects of the Razer Ornata V3 X. The keyboard lights as one zone. Solid, Breathing, Spectrum, and Off. No Razer Synapse.

<p align="center">
  <a href="#run"><img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white" alt="Requires macOS 14 or later"></a>
  <a href="#run"><img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Built with Swift 6"></a>
  <a href="#what-it-sets"><img src="https://img.shields.io/badge/Razer-Ornata%20V3%20X-44D62C" alt="Made for the Razer Ornata V3 X"></a>
  <a href="#what-it-sets"><img src="https://img.shields.io/badge/RGB-backlight-0AA2C0" alt="RGB keyboard backlight"></a>
</p>

<p align="center">
  <img src="RazerKeyboardColorPreview.png" alt="Keyboard color, a macOS window for the Razer Ornata V3 X RGB backlight. Connected, waiting to send, with color, intensity, Solid, Breathing, Spectrum, and Off." width="560">
</p>

Use this instead of installing half a gigabyte of spyware.

## Run

```sh
./run.sh
```

That builds `KeyboardColor` and opens the window. It does not listen on a port. It talks only to the Razer lighting. It doesn't need every permission under the f***ing sun.

## What it sets

- **Color** for Solid and Breathing. The well is a color you send. The keys do not report a color back.
- **Intensity** from 0% to 100%. Opening the window reads brightness from the keyboard. 0% dims the current effect. Off is its own control.
- **Effect:** Solid, Breathing, Spectrum, or Off. The accepted effect is marked after a command succeeds.

One lighting zone. Live updates. Look again reads brightness again and leaves a color this window already sent.

## What you need

- macOS 14 or later
- A Razer Ornata V3 X on USB
- Swift. `./run.sh` builds the window from this repository

If the window says **Blocked**, macOS is hiding lighting control. The keys can still type. Input Monitoring can clear that.

## How it talks to the keyboard

The app opens the Ornata lighting control and leaves the keys to the system. It does not seize the keyboard, and it does not write a color when the window opens.
