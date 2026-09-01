# 012: Remove press transforms under Reduce Motion

- **Status**: DONE
- **Implementation commits**: Android `38548cf7`, iOS `e44241a9`
- **Severity**: HIGH
- **Category**: accessibility and interaction feedback
- **Estimated scope**: 4 files, small

## Problem

The shared button styles on both platforms still shrink controls to 97% when
the operating system asks the app to reduce motion. Android changes the
animation duration through its global scale, but still applies the transform.
The iOS seed-entry progress rail also animates its current tick without reading
Reduce Motion.

```swift
// ios/CashuWallet/Views/Components/PressableButtonStyle.swift:10, current
.scaleEffect(configuration.isPressed ? 0.97 : 1.0)
```

```kotlin
// android/app/src/main/java/com/cashu/me/ui/components/Buttons.kt:96, current
targetValue = if (pressed) PressedScale else 1f,
```

```swift
// ios/CashuWallet/Views/Main/SeedWordEntry.swift:307, current
.animation(.snappy(duration: 0.25), value: entry.index)
```

## Target

- When Reduce Motion is off, retain the existing asymmetric 0.97 press:
  `.snappy(duration: 0.09)` down and `.snappy(duration: 0.18)` up on iOS;
  `fastEffectsSpec` down and `defaultEffectsSpec` up on Android.
- When Reduce Motion is on, scale remains exactly `1.0` / `1f`. Opacity and
  native highlight feedback may remain because they do not move geometry.
- Disable both seed-rail animations under Reduce Motion while preserving the
  immediate selected/completed state change.
- On iOS 26+, do not request interactive glass while Reduce Motion is on.

## Repo conventions to follow

- iOS reads `@Environment(\.accessibilityReduceMotion)` and supplies a nil
  animation, as `MethodActionRowButtonStyle` already does.
- Android reads `rememberReducedMotion()`, as `rememberBounceScale` already
  does.
- Do not change the settled 0.97 scale or the asymmetric timing.

## Steps

1. Update `PressableButtonStyle.swift` to return scale 1 and nil animation
   under Reduce Motion.
2. Update `FullWidthCapsuleButtonStyle` and
   `FlatSheetSecondaryButtonStyle` in `LiquidGlassModifiers.swift` with the
   same gate; preserve pressed opacity.
3. Update `rememberPressScale` in `Buttons.kt` so its reduced-motion target is
   always 1f.
4. Update `SeedWordProgressRail` in `SeedWordEntry.swift` so both implicit
   animations become nil under Reduce Motion.

## Boundaries

- Do NOT change button layout, labels, color roles, or action handling.
- Do NOT change the 0.97 scale or current spring/timing values when motion is
  enabled.
- Do NOT add dependencies or alter Android's global animator-scale detection.

## Verification

- **Mechanical**: run the focused iOS build and Android unit/instrumentation
  compile tasks; run `git diff --check`.
- **Feel check**: press primary, secondary, chip, and text controls rapidly on
  each platform. With motion enabled, compression must remain immediate and
  release must settle without overshoot. With Reduce Motion / animator scale 0,
  the control must not change size while pressed, but pressed opacity or native
  highlight feedback must remain visible.
- **Done when**: all shared press paths remain at scale 1 with reduced motion,
  and the seed rail snaps between states without interpolation.
