# DroidDrive

Finder, except the disk is in your pocket.

Plug a USB cable into an Android phone and the files show up like they belong on the Mac. Photos, videos, dumps, the mysterious `Download` folder you swore you’d clean up. Double-click opens. Upload copies the other way. No MTP ritual, no 2012 Android File Transfer, no `adb pull /sdcard/DCIM/Camera/IMG_2048.jpg` because you forgot the path again.

Native SwiftUI. macOS 14+. The phone talks through `adb`.

## What it actually does

- **Sees the phone the moment you plug it in.** Unplug, it waits. Plug a second phone, pick it from the header.
- **Starts at `/sdcard`.** Click the path bar like breadcrumbs. Go up. Refresh. Treat it like a folder, because it is one.
- **Double-click a file** to pull it and open it on the Mac. Photos, videos, PDFs, the APK you shouldn’t install, whatever.
- **Download** selected files or folders anywhere on the Mac. Toolbar or right-click.
- **Upload** files or folders from the Mac into the folder you’re looking at.
- **New folder, rename, delete** on the phone — delete asks first, then it’s gone.
- **Storage line** in the header: used · free. So you know why the camera just failed.

The empty states are the setup wizard. If `adb` is missing, if nothing is plugged in, if the phone is still asking “Allow USB debugging?”, the window tells you instead of dying silently.

## One-time phone handshake

Do this once. After that, the cable is enough.

1. Connect the phone with USB.
2. Enable **Developer options**: Settings → About phone → tap **Build number** seven times. (Yes, seven. Google’s idea of a secret handshake.)
3. Settings → **Developer options** → turn on **USB debugging**.
4. When the phone asks **“Allow USB debugging?”**, tap **Allow**. Check **Always allow from this computer** if you never want to see that dialog again.

Unlock the phone while you do this. A locked screen with a pending prompt looks like a dead cable.

## Build

```sh
./build_app.sh        # writes DroidDrive.app in this folder
open DroidDrive.app
```

Needs Xcode command-line tools and `adb`:

```sh
brew install android-platform-tools
```

The app does not inherit your shell `PATH` when you launch it from Finder, so it looks for `adb` in the usual places (Homebrew, Android SDK, `/usr/local`). If it still can’t find it, install the formula above and relaunch.

Drag `DroidDrive.app` into `/Applications` if you want it to stay.

## Why this exists

Android on a Mac is still a USB problem pretending to be a files problem. DroidDrive is a thin, native window over `adb` — list, pull, push, mkdir, mv, rm — with a table, a path bar, and the manners of a Mac app. That’s the whole trick.
