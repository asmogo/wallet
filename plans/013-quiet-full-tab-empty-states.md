# 013: Keep recurring full-tab empty states still

- **Status**: DONE
- **Implementation commits**: Android `38548cf7`, iOS `e44241a9`
- **Severity**: MEDIUM
- **Category**: repeated entrance motion
- **Estimated scope**: 2 files, small

## Problem

Wallet and History empty states are part of frequently revisited tab
destinations, but both platforms replay a compound fade, 0.96 scale, 8-point
rise, and icon bounce whenever the subtree mounts. The product motion rules
already removed History-row entrances for exactly this remount behavior.

```swift
// ios/CashuWallet/Views/Components/ActivityOrbView.swift:170, current
.scaleEffect(reduceMotion ? 1 : (isPresented ? 1 : 0.96))
.offset(y: reduceMotion ? 0 : (isPresented ? 0 : 8))
```

```kotlin
// android/app/src/main/java/com/cashu/me/ui/components/EmptyState.kt:102, current
val iconBounce = rememberBounceScale(trigger = Unit, bounceOnEntry = true)
```

## Target

- Full-screen/full-tab empty states render immediately at opacity 1, scale 1,
  offset 0, with no entry bounce.
- Section/compact empty states keep the existing one-shot entrance because
  they follow a rarer, user-caused state change inside a sheet or section.
- Existing accessibility grouping, layout, icon opacity, and CTAs remain
  unchanged.

## Repo conventions to follow

- `NativeEmptyState.Style.fullScreen` and `EmptyStateSize.FullScreen` already
  identify the high-frequency tab variant without adding an API.
- Preserve the existing spring recipe for the non-full-screen variants.
- Reduced Motion remains opacity-or-nothing for the retained section motion.

## Steps

1. In `ActivityOrbView.swift`, derive whether entrance motion is allowed from
   `style != .fullScreen`; initialize and render full-screen state at rest and
   do not trigger its symbol bounce.
2. In `EmptyState.kt`, derive the same decision from
   `size != EmptyStateSize.FullScreen`; keep the root graphics layer and icon
   bounce at rest for FullScreen.
3. Update comments so they describe frequent-tab restraint and the retained
   section behavior.

## Boundaries

- Do NOT remove motion from section/sheet empty states.
- Do NOT change empty-state copy, dimensions, icon choices, or actions.
- Do NOT restore per-row History entrance animation.

## Verification

- **Mechanical**: compile both app targets and run UI tests that mount empty
  states; run `git diff --check`.
- **Feel check**: revisit empty Wallet and History tabs repeatedly. Their empty
  content must remain calm and stationary. Trigger a section empty state in a
  sheet and confirm its current subtle entrance still occurs once. Enable
  Reduce Motion and confirm the section state has no spatial movement.
- **Done when**: no full-tab remount produces rise, scale, or bounce, while rare
  section empty states retain their intentional entrance.
