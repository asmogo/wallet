# Button Follow-Up Fixes

Three issues remain after the button audit. Please fix all three.

## 1. X (close) and Camera/Scan buttons should use Liquid Glass

On the initial bottom sheets (Send Ecash, Pay Lightning, Receive), the circular X (dismiss) button and the camera/scan icon button in the toolbar use plain dark circles. These should use `.liquidGlass(interactive: true)` so they render as proper Liquid Glass buttons on iOS 26+, matching the style used elsewhere in the app.

## 2. Primary action buttons are still not full-width

The "Send" button on the Send Ecash screen is still a small centered pill. It must be full-width with `.frame(maxWidth: .infinity)` and standard horizontal padding, same as the "Continue" button in the Receive Ecash bottom sheet. Check all primary action buttons — if any are still constrained to a fixed/intrinsic width, fix them.

## 3. "Get Quote" button on Pay Lightning is unreadable in light mode + rename it

The "Get Quote" button has a black background with dark text, making it invisible in light mode. This should have been caught in the button audit. Fix it by using `.glassButton(prominent: true)` with `.frame(maxWidth: .infinity)` so it adapts correctly to both light and dark mode. Also rename the label from **"Get Quote"** to **"Continue"**.
