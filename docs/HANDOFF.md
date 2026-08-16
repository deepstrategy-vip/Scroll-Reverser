# Handoff

## Current state

- Date: 2026-08-16
- Task mode: implementation
- Branch: `feature/modifier-scroll-zoom`
- Upstream base: `pilotmoon/scroll-reverser` at `187bf39`
- Scope: preserve independent mouse scroll reversal and add configurable
  Control/Command + mouse-wheel application zoom.

The implementation is complete in the working tree. The new preference is off
by default and is exposed in the Scrolling pane as **Application Zoom**. It only
handles regular-mouse vertical scroll events whose modifier chord exactly
matches the selected Control or Command setting. The original wheel event is
consumed and the target application receives Command + keypad plus/minus.

## Design decisions

- Zoom uses the already reversed vertical direction. This matches LinearMouse's
  processing order and keeps the physical direction consistent with the user's
  Scroll Reverser setting.
- The original event's target PID is preferred; the foreground application is a
  fallback. State resets when the target changes.
- Discrete wheels emit one shortcut per detent. Continuous wheels use a 24-point
  accumulator, a 50 ms emission gate, and a 180 ms idle reset.
- Momentum tails are consumed without emitting extra shortcuts. Releasing the
  trigger modifier during an ordinary continuous scroll immediately returns
  control to normal scrolling.
- The event tap still listens only for scroll events, so synthesized keyboard
  events cannot recurse into it.
- The feature currently follows Scroll Reverser's master enable switch. This is
  intentional for the requested combined reverse-scroll + zoom setup.

## Verification completed

- `./tests/run-unit-tests.sh`: passed.
- Objective-C source syntax/link check with the Command Line Tools SDK: passed;
  only two pre-existing `dispatch_after(0.05, ...)` conversion warnings remain
  in upstream debug/test window controllers.
- `git diff --check`: passed.
- `PrefsWindow.xib`: well-formed XML; object IDs, bindings, and stack-view
  entries received independent review.
- English, Simplified Chinese, and Traditional Chinese strings: `plutil -lint`
  passed.
- `ScrollReverser.xcodeproj/project.pbxproj`: `plutil -lint` passed.
- A local arm64 test application was assembled at
  `build/Scroll Reverser Zoom.app`, ad-hoc signed, verified with `codesign`, and
  launched successfully. Its first-run and permissions preferences windows both
  loaded without a crash. No Accessibility or Input Monitoring permission was
  granted during this smoke test.
- Independent core review found no blocking memory-management, event-consumption,
  recursion, modifier-release, or PID-routing issue.

## Remaining verification

This Mac has Command Line Tools but no complete Xcode installation, so an
authoritative Xcode build and `ibtool` compilation of the modified XIB could not
be run. The local test app therefore reuses the upstream compiled nib and the
controller's guarded programmatic fallback for the new controls.

Before treating the fork as a signed release:

1. Build the project once with a complete Xcode installation and the intended
   Developer ID configuration.
2. Grant permissions manually, enable only mouse reversal plus Application
   Zoom, and verify both Control and Command choices with the Logitech GPW5.
3. Run a 10–15 minute A/B observation against the existing WindowServer cursor
   stutter. Compare the same workflow with the app fully quit; do not infer
   causality from a single subjective event.

The generated `build/` artifact is intentionally ignored and is not a release.
