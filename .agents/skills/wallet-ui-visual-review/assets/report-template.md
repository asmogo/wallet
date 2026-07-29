# Wallet UI visual review

- Target: TARGET
- Base: BASE_REF
- Before: `BEFORE_SHA`
- After: `AFTER_SHA`

## Routing

| Platform | Decision | Reason |
|---|---|---|
| Android | CAPTURED_OR_SKIPPED | ANDROID_REASON |
| iOS | CAPTURED_OR_SKIPPED | IOS_REASON |

## Capture environments

| Environment | Runtime | Device and viewport | Appearance | Locale and text |
|---|---|---|---|---|
| ENVIRONMENT_ID | EXACT_OS_VERSION_AND_BUILD | DEVICE_VIEWPORT_SCALE_OR_DENSITY | THEME | LOCALE_TEXT_SCALE |

Runtime policy: newest stable common runtime, or DISCLOSED_EXPLICIT_FALLBACK.

## Diff-to-screen analysis

- FINDING_OR_HYPOTHESIS
- INDIRECT_EFFECT_OR_INTENTIONAL_NON_CHANGE
- VERSION_BOUNDARY_REASON_IF_ANY

## SURFACE — STATE

Expected change: EXPECTED_CHANGE.

| Before | After |
|---|---|
| ![Before: ACCESSIBLE_DESCRIPTION](RELATIVE_BEFORE_IMAGE.png) | ![After: ACCESSIBLE_DESCRIPTION](RELATIVE_AFTER_IMAGE.png) |

Fixture: SYNTHETIC_FIXTURE_DISCLOSURE.

## Limitations and noise

- BEHAVIOR_NOT_PROVEN_BY_SCREENSHOT
- KNOWN_VISUAL_NOISE_OR_NONE
- MISSING_RUNTIME_HARDWARE_OR_STATE_COVERAGE_OR_NONE
