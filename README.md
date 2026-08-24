# DroidDrive

A native macOS app for browsing your Android phone's storage over USB.
Built with SwiftUI; talks to the phone through `adb` (Android platform tools).

## One-time phone setup

1. Connect the phone with a USB cable.
2. Enable **Developer options**: Settings → About phone → tap **Build number** 7 times.
3. In Settings → **Developer options**, turn on **USB debugging**.
4. When the phone shows **“Allow USB debugging?”**, tap **Allow**
   (check “Always allow from this computer” so you're never asked again).

The app walks you through these steps on screen until the phone appears.

## Features

- Live device detection (plug in / unplug any time; multiple devices supported)
- Browse all shared storage starting at `/sdcard`, with a clickable path bar
- **Double-click** a file to download and open it on the Mac
- **Download** selected files/folders anywhere on the Mac (toolbar or right-click)
- **Upload** files or folders from the Mac to the current phone folder
- **New folder**, **Rename**, **Delete** (with confirmation) on the phone
- Storage used/free summary for the phone

## Building

```sh
./build_app.sh        # produces DroidDrive.app in this folder
open DroidDrive.app
```

Requires Xcode command-line tools and `adb`
(`brew install android-platform-tools` — already installed on this Mac).

To keep it around, drag `DroidDrive.app` into `/Applications`.
