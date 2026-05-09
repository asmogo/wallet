---
name: ios-sim-screenshots
description: Drive an iOS Simulator from the command line to capture screenshots of specific app screens (not just the launch screen). Build, install, launch, navigate by tapping coordinates calculated from screenshots, and save PNGs to a docs folder. Use when an agent needs to produce app screenshots for a README, design review, or release notes — and the user can't or doesn't want to take them by hand.
---

# iOS Simulator Screenshots

Drives the iOS Simulator headlessly from Bash + `cliclick` + `osascript`. The model takes a screenshot, looks at it via the Read tool, computes pixel coordinates of the next button, clicks, and repeats. Works for any SwiftUI/UIKit app that doesn't require external services to navigate.

## Prerequisites

- Xcode.app installed at `/Applications/Xcode.app`
- `cliclick` (`brew install cliclick` if missing — required for sending taps)
- `xcode-select -p` may point at CommandLineTools, which lacks `simctl`. **Do not** run `sudo xcode-select -s …` — instead prefix every `xcrun` / `xcodebuild` call with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. No sudo required.
- macOS Accessibility permission must be granted for whatever process runs `cliclick` (Terminal, iTerm, Claude Code). First call may silently fail until granted.

## Workflow

### 1. Boot a simulator and open the Simulator app

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
```

`boot` is idempotent and returns "already booted" harmlessly.

### 2. Build the app for the simulator

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project YourApp.xcodeproj \
  -scheme YourApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/app-dd build
```

**Do NOT** add `CODE_SIGNING_ALLOWED=NO` if the app touches the Keychain. Without proper signing the simulator returns `errSecMissingEntitlement` (status `-34018`) on every keychain write, which silently breaks wallet creation, login, etc. The default "Sign to Run Locally" identity is enough — just omit the flag.

This is a long build; run with `run_in_background: true` and wait for the completion notification.

### 3. Install and launch

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl uninstall booted com.example.app  # safe even if not installed
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install   booted /tmp/app-dd/Build/Products/Debug-iphonesimulator/YourApp.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch    booted com.example.app
```

Sleep ~2–3 seconds after launch before the first screenshot — SwiftUI splash transitions take a moment.

### 4. Calibrate coordinates (do this once per session)

The image is in **device pixels**; clicks land in **screen points**. You need both.

```sh
osascript -e 'tell application "System Events" to tell process "Simulator"
  set p to position of window 1
  set s to size of window 1
  return (item 1 of p) & "," & (item 2 of p) & "," & (item 1 of s) & "," & (item 2 of s)
end tell'
```

Returns e.g. `1919,178,456,972` → window origin `(1919, 178)`, size `456×972` (points).

Combined with screenshot dimensions (e.g. `1206×2622` for iPhone 17 Pro), derive:

- `scale = image_width / window_width` (e.g. `1206/456 ≈ 2.645`)
- `title_bar_pt = 28` (standard macOS title bar height)
- `screen_x = window_x + image_x / scale`
- `screen_y = window_y + title_bar_pt + image_y / scale`

Where `image_x`, `image_y` are pixel coordinates measured **on the original screenshot**, not on a downscaled preview.

### 5. Screenshot → look → click → repeat

```sh
# capture
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io booted screenshot /tmp/step.png
```

Then `Read` the PNG via the Read tool. Identify the button you want, read its pixel coords from the image, run them through the formula above, then click:

```sh
osascript -e 'tell application "Simulator" to activate'  # ensure focus
sleep 1                                                  # let activation settle
cliclick m:<x>,<y> dd:<x>,<y> du:<x>,<y>                 # move, mouse-down, mouse-up
sleep 2                                                  # let UI animate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io booted screenshot /tmp/next.png
```

Save keepers to your screenshots folder with `cp` once verified.

## Gotchas (learned the hard way)

- **A single `cliclick c:` often misses SwiftUI buttons.** Use the explicit move + mouse-down + mouse-up triple (`m: dd: du:`). `c:` works for some buttons (e.g. plain `Button { … }`) but fails on others (sheets, list rows). Default to the triple.
- **The first click after `Simulator` regains focus may be eaten by macOS** to activate the window. Always `osascript -e 'tell application "Simulator" to activate'` then `sleep 1` before the first click of a sequence — or accept that the very first click may need to be re-sent.
- **Image previews shown back to the model are downscaled.** When the Read tool reports e.g. "displayed at 920x2000, multiply by 1.31 to map to original 1206x2622," do that math — clicking off the displayed coordinates puts you 30% off-target.
- **Scale is asymmetric in practice.** Window height includes the title bar; image height doesn't. Subtract a ~28pt title bar and use the **width-based scale** for both axes. Off-by-a-few-points is fine for fat buttons, fatal for tab bar items at the screen edge.
- **Tab bar at screen edge.** Bottom navigation lands very close to `window_y + window_height`. If the click silently goes nowhere, the cursor is below the window — nudge `image_y` up by 30–50px or shrink the assumed title bar.
- **Keychain on sim needs proper signing.** Symptom: app shows red text like `Failed to save to Keychain (status: -34018)` after the first action. Fix: rebuild without `CODE_SIGNING_ALLOWED=NO`; uninstall + reinstall (state from the broken install can stick around).
- **`xcrun simctl io booted screenshot` always writes a PNG** even if you give a `.jpg` extension — name accordingly.
- **Don't `sudo xcode-select -s`.** It changes a global setting, may prompt for a password you can't see, and isn't needed. `DEVELOPER_DIR=…` env-prefix every command instead.

## Suggested screenshot set for a typical app README

1. Launch / splash (no interaction needed, just delay)
2. Onboarding entry screen
3. Main / home view (post-setup; create a fresh account if needed)
4. A primary action sheet (Send / Compose / Add — captures the core flow)
5. Settings or profile view (high signal, easy to reach via tab bar)

Three to five screenshots is usually enough for a README. Don't chase coverage of every screen — the cost of navigating compounds with each tap, and brittle clicks waste tokens.

## Cleanup

The simulator stays booted between sessions, which is fine. To shut it down explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl shutdown booted
```

Build artifacts in `/tmp/app-dd` are safe to leave; macOS will clean `/tmp` on reboot.
