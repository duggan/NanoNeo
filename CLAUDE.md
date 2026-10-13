# NanoNeo

NanoNeo is a macOS menu bar app that saves AlphaWord files from an AlphaSmart
Neo / Neo 2 to the Mac over USB. It replaces the Neo's "Send" key, which types files out as
keystrokes.

## Design rules

- The Neo is an **inbox**. Text flows one way, Neo → Mac. The only thing written to
  the Neo is a cleared slot, after that slot's text is safely on the Mac.
- Each sync, for each non-empty AlphaWord slot:
  1. Save the text as a **new** file named `YYYY-MM-DD HHMM <first line>.txt`. The
     first line is trimmed to about 50 characters, `/` and `:` are stripped, and
     `Untitled` is used if it's blank. On a name clash, add ` 2`, ` 3` and so on.
     Never overwrite an existing file.
  2. Write to a temporary file, fsync it, `renamex_np(RENAME_EXCL)` it into place,
     then read it back and compare it with the device's text.
  3. Only after that check passes, clear the slot. Clearing is optional
     (`clearSlots`, on by default).
- Once a file is saved, the Mac owns it and the app never modifies or deletes it.
  There's no merging, no conflict files and no database.
- `~/Library/Application Support/NanoNeo/state.json` holds, for each slot, a
  SHA-256 of the last saved text and the path it was saved to. If a clear failed,
  the next sync sees the same text and the same unchanged file, skips the save,
  and retries the clear. If the saved file was moved or edited, it saves again.
- The default folder `~/Documents/Neo` is usually iCloud-synced, so app state never
  lives in it.
- Plug-in is detected with IOKit matching notifications. The Neo re-enumerates as a
  keyboard at the end of every sync, so keyboard-mode arrivals are ignored for
  10 s after a sync.

## USB protocol

- Vendor `0x081E`. Keyboard (HID) mode is product `0xBD04`. Comms mode is product
  `0xBD01`, a vendor-specific device with bulk endpoints and 8-byte packets.
- **Keyboard → comms, with no permissions:** send HID SET_REPORT output reports
  `0xE0, 0xE1, 0xE2, 0xE3, 0xE4` as raw control requests (`bmRequestType 0x21`,
  `bRequest 9`, `wValue 0x0200`, `wIndex 0`) on the device's default pipe, via
  `IOUSBHostDevice`. macOS's keyboard driver owns the interface, not the device,
  so the open succeeds without Input Monitoring or root. (Opening the keyboard
  through IOHIDManager needs Input Monitoring; neotools/libusb detach the driver,
  which needs root.) The Neo re-enumerates as `0xBD01` after about 2.6 s. If it
  doesn't, retry once after 4 s.
- **Comms mode:** open interface 0 with `IOUSBHostInterface`. Matching must include
  `bConfigurationValue` as well as `bInterfaceNumber`. `ioData` buffers have a
  fixed length. No kernel driver claims the interface.
- **Comms → keyboard:** hello, reset, switch to the system applet, then
  `REQUEST_RESTART`. A full sync with both mode switches takes about 4 s.
- **Empty slot:** an empty AlphaWord slot is 512 bytes of `0xA7`, with alloc 512 and
  min 512. To clear a slot, write exactly that through the normal raw-write path.
  neotools' `clear_file` sets the sizes to 0 instead, which the Neo never does
  itself.
- Writing a slot can make it AlphaWord's "current" file (flag `0x02`) and sets
  `0x01` until the next restart. This has no practical effect.
- Reference implementations: [lykahb/neotools](https://github.com/lykahb/neotools)
  (Python, GPL-3.0; `device.py`, `message.py`, `file.py`, `text_file.py`). Our
  protocol code and character map are ported from it. It's based on
  [tSoniq/alphasync](https://github.com/tSoniq/alphasync), the original Mac C++
  driver.
- Tested on a Neo 2 running System 3 Neo 3.4 (Feb 2009). Swift decoding matches
  neotools byte for byte.

## Layout

- `Sources/NeoKit/`: the library.
  - `USB/`: `ModeSwitch` and the IOUSBHost bulk transport.
  - `Protocol/`: `Message` and `NeoDevice`.
  - `Text/`: the AlphaWord decoder and the en-US character map (generated from
    neotools).
  - `Inbox/`: naming, `InboxState` and `InboxSync`.
  - `NeoSession.sync()` runs a complete sync.
- `Sources/NanoNeoApp/`: the SwiftUI `MenuBarExtra` app, with Settings and a
  first-run Welcome window (`Windows.swift`). UserDefaults keys: `autoSync`
  (default true), `clearSlots` (default true), `destinationPath` (default
  `~/Documents/Neo`) and `hasSeenWelcome`. With auto-sync on, it also syncs at
  launch if a Neo is already connected, except while the Welcome window is up.
- `LegacyMigration.swift` runs once at first launch, before the model exists. The
  app was briefly called NeoSync during development. The migration quits a running
  NeoSync (`ie.duggan.NeoSync`), copies its UserDefaults
  settings, and moves `~/Library/Application Support/NeoSync` to `NanoNeo`. The
  `migratedFromNeoSync` key marks it as done.
- `Sources/nanoneo/`: a developer CLI for hardware testing: `mode`, `info`, `list`,
  `read`, `raw`, `clear`, `keyboard`, and `sync --dest --state --no-clear`.
  **`sync` and `clear` modify the device.**
- `Tests/NeoKitTests/`: pure unit tests (`swift test`). No hardware is needed.
- `Makefile`: `make sign`, `run`, `test`, `icons`, `dmg` and `release`. It builds a
  universal app with a Developer ID signature and hardened runtime, not sandboxed,
  with bundle ID `ie.duggan.NanoNeo`. Notarization uses the keychain profile
  `nanoneo` (see `make notary-setup`). DMGs need `create-dmg`.
- `Resources/art/make_icons.py` draws all the artwork as SVG: a top-down Neo 2
  traced from a photo. The bell silhouette, screen and keyboard are deliberate,
  with no sync symbol. `make icons` (Inkscape) renders `NanoNeo.icns`, the menu bar
  template PNGs and the DMG background into `Resources/`. Commit them.
  While syncing, the menu bar icon blinks between `MenuBarIconTemplate` and
  `MenuBarIconSyncingTemplate` (screen lit).
- `make demo` renders `Resources/art/demo/scene.html` (a mock desktop driven by
  `render(t)`) frame by frame with Playwright into `docs/demo.gif`, the README demo.

## Working on hardware

- Syncing clears slots. Back up first: `nanoneo sync --no-clear --dest <dir> --state <file>`.
- The app can't tell a restart caused by the CLI from a real plug-in, so quit the
  app before testing with the CLI, or expect a harmless empty sync.
