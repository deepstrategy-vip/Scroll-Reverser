# Handoff

## Current state

- Date: 2026-08-17
- Task mode: release (local signed installation; no public release)
- Branch: `feature/modifier-scroll-zoom`
- Upstream base: `pilotmoon/scroll-reverser` at `187bf39`
- Scope: preserve independent mouse scroll reversal and add configurable
  Control/Command + mouse-wheel application zoom.

The implementation is committed and pushed. The new preference is off by
default and is exposed in the Scrolling pane as **Application Zoom**. It only
handles regular-mouse vertical scroll events whose modifier chord exactly
matches the selected Control or Command setting. The original wheel event is
consumed and the target application receives Command + keypad plus/minus.
WizNote (`cn.wiznote.desktop`) is a targeted compatibility exception: zoom in
uses its declared main-keyboard Command+= shortcut, while zoom out and other
applications keep the existing keypad mapping.

A local Developer ID-signed build is installed at
`~/Applications/Scroll Reverser Zoom.app` with bundle identifier
`com.deepstrategy.scroll-reverser-zoom`. It is configured for vertical regular
mouse reversal, no trackpad reversal, and logical Command + wheel application
zoom. Karabiner globally swaps Control and Command on this Mac, so the selected
logical Command trigger is activated by the user's physical Control key.
The installed binary was assembled from source commit `3f45a2f`. LinearMouse
remains installed but is not running and has been removed from login items;
Scroll Reverser Zoom is registered to start at login.

## Design decisions

- Zoom uses the already reversed vertical direction. This matches LinearMouse's
  processing order and keeps the physical direction consistent with the user's
  Scroll Reverser setting.
- The original event's target PID is preferred; the foreground application is a
  fallback. State resets when the target changes.
- Application-specific key mapping is limited to confirmed incompatibilities.
  WizNote ignores keypad plus for zoom in, so only that bundle and direction
  receive main-keyboard Command+=; no shortcut is double-posted.
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
- Focused mapping tests cover WizNote zoom in/out, Chrome, unknown and nil
  bundle identifiers, the no-direction case, and Command-without-Shift flags.
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
  `build/Scroll Reverser Zoom.app`, signed with the user's Developer ID and the
  hardened runtime, verified with `codesign`, and installed under
  `~/Applications`. The build is not notarized, so it is not a distributable
  public release.
- Accessibility and Input Monitoring are both granted to the installed app.
  Runtime logs report `permissions: ax 1, im 1`; its active scroll-wheel event
  tap and passive gesture event tap are both enabled.
- The installed defaults were verified with the master switch on,
  `ReverseMouse=1`, `ReverseTrackpad=0`, `ReverseY=1`,
  `ModifierScrollZoomEnabled=1`, and logical Command selected as the modifier
  (`ModifierScrollZoomModifier=1`).
- Login-item verification reports `ProxyBridge, Scroll Reverser Zoom`;
  LinearMouse is no longer registered to launch automatically.
- End-to-end session event tests passed against the running installed app:
  an ordinary `+1` wheel event was observed downstream as reversed
  `axis1=-3, point1=-24`, and a Control + wheel event produced the tagged
  Command + keypad-minus application shortcut.
- A physical-event capture identified the apparent Control failure as the
  existing Karabiner Control/Command swap: the physical Control key arrived as
  `keyCode 55` with the Command flag. After selecting logical Command, three
  physical Control + GPW5 wheel events were all consumed by the zoom path and
  none leaked downstream; the user confirmed Chrome page zoom works.
- After installing the `3f45a2f` build, an end-to-end event test targeted
  WizNote and captured the application-bound synthetic key as key code 24
  (main-keyboard `=`), Command set, and Shift clear. The one test zoom-in step
  was immediately balanced with one zoom-out step so the user's note view was
  not left altered.
- Independent core review found no blocking memory-management, event-consumption,
  recursion, modifier-release, or PID-routing issue.

## Remaining verification

This Mac has Command Line Tools but no complete Xcode installation, so an
authoritative Xcode build and `ibtool` compilation of the modified XIB could not
be run. The local test app therefore reuses the upstream compiled nib and the
controller's guarded programmatic fallback for the new controls.

Before treating the fork as a distributable release:

1. Build the project once with a complete Xcode installation and the intended
   Developer ID configuration.
2. Notarize the resulting build and validate it on a clean macOS account.
3. Repeat the modifier test on a clean macOS account without Karabiner's global
   Control/Command swap so both UI choices receive independent release testing.
4. Run a 10–15 minute A/B observation against the existing WindowServer cursor
   stutter. Compare the same workflow with the app fully quit; do not infer
   causality from a single subjective event.

The generated `build/` artifact is intentionally ignored. The installed app is
kept running for the ongoing stutter observation but is not a notarized release.
To roll back, turn off **Start at login** in Scroll Reverser Zoom, quit it, and
re-enable LinearMouse's login item; no source or repository rollback is needed.
