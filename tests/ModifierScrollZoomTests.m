// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "../ModifierScrollZoom.h"
#import <Carbon/Carbon.h>
#import <assert.h>
#import <stdio.h>

static uint64_t Milliseconds(uint64_t value)
{
    return value*1000000;
}

static void TestModifierMatching(void)
{
    assert(SRScrollZoomRequiredEventFlag(SRScrollZoomModifierControl)==kCGEventFlagMaskControl);
    assert(SRScrollZoomRequiredEventFlag(SRScrollZoomModifierCommand)==kCGEventFlagMaskCommand);
    assert(SRScrollZoomRequiredEventFlag(999)==kCGEventFlagMaskControl);

    assert(SRScrollZoomModifierMatches(kCGEventFlagMaskControl, SRScrollZoomModifierControl));
    assert(SRScrollZoomModifierMatches(kCGEventFlagMaskControl|kCGEventFlagMaskAlphaShift,
                                       SRScrollZoomModifierControl));
    assert(!SRScrollZoomModifierMatches(kCGEventFlagMaskControl|kCGEventFlagMaskShift,
                                        SRScrollZoomModifierControl));
    assert(!SRScrollZoomModifierMatches(kCGEventFlagMaskCommand,
                                        SRScrollZoomModifierControl));
    assert(SRScrollZoomModifierMatches(kCGEventFlagMaskCommand, SRScrollZoomModifierCommand));
    assert(!SRScrollZoomModifierMatches(0, SRScrollZoomModifierCommand));
}

static void TestDeltaNormalizationAndDirection(void)
{
    assert(SRScrollZoomNormalizedDelta(NO, 2, 16, 2.0)==2.0);
    assert(SRScrollZoomNormalizedDelta(NO, 0, -8, -1.0)==-8.0);
    assert(SRScrollZoomNormalizedDelta(YES, 2, 16, 2.0)==16.0);
    assert(SRScrollZoomNormalizedDelta(YES, 2, 0, 2.0)==16.0);
    assert(SRScrollZoomNormalizedDelta(YES, -2, 0, 0.0)==-16.0);

    assert(SRScrollZoomDirectionForDelta(1.0, NO)==SRScrollZoomDirectionIn);
    assert(SRScrollZoomDirectionForDelta(-1.0, NO)==SRScrollZoomDirectionOut);
    assert(SRScrollZoomDirectionForDelta(1.0, YES)==SRScrollZoomDirectionOut);
    assert(SRScrollZoomDirectionForDelta(-1.0, YES)==SRScrollZoomDirectionIn);
    assert(SRScrollZoomDirectionForDelta(0.0, YES)==SRScrollZoomDirectionNone);
    assert(SRScrollZoomKeyCodeForDirection(SRScrollZoomDirectionIn)==kVK_ANSI_KeypadPlus);
    assert(SRScrollZoomKeyCodeForDirection(SRScrollZoomDirectionOut)==kVK_ANSI_KeypadMinus);
    assert(SRScrollZoomKeyCodeForDirection(SRScrollZoomDirectionNone)==UINT16_MAX);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionIn, @"cn.wiznote.desktop")==kVK_ANSI_Equal);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionOut, @"cn.wiznote.desktop")==kVK_ANSI_KeypadMinus);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionIn, @"com.pdfeditor.pdfeditormac")==kVK_ANSI_Equal);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionOut, @"com.pdfeditor.pdfeditormac")==kVK_ANSI_KeypadMinus);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionIn, @"com.google.Chrome")==kVK_ANSI_KeypadPlus);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionIn, nil)==kVK_ANSI_KeypadPlus);
    assert(SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
               SRScrollZoomDirectionNone, @"cn.wiznote.desktop")==UINT16_MAX);
    assert(SRScrollZoomOutputEventFlags(SRScrollZoomDirectionIn)==kCGEventFlagMaskCommand);
    assert(SRScrollZoomOutputEventFlags(SRScrollZoomDirectionOut)==kCGEventFlagMaskCommand);
    assert((SRScrollZoomOutputEventFlags(SRScrollZoomDirectionIn)&
            kCGEventFlagMaskShift)==0);
    assert(SRScrollZoomShouldEndCaptureForModifier(NO, YES));
    assert(!SRScrollZoomShouldEndCaptureForModifier(NO, NO));
    assert(!SRScrollZoomShouldEndCaptureForModifier(YES, YES));
}

static void TestDiscreteEveryTick(void)
{
    SRScrollZoomState state={0};
    assert(SRScrollZoomUpdateState(&state, NO, 1.0, NO, Milliseconds(1000), 42)==
           SRScrollZoomDirectionIn);
    assert(SRScrollZoomUpdateState(&state, NO, 1.0, NO, Milliseconds(1020), 42)==
           SRScrollZoomDirectionIn);
    assert(state.lastEmissionNanoseconds==0);

    // A new target starts a fresh rate-limit session.
    assert(SRScrollZoomUpdateState(&state, NO, -1.0, NO, Milliseconds(1060), 43)==
           SRScrollZoomDirectionOut);

    // A suppressed event is consumed by the caller but never emits a key.
    assert(SRScrollZoomUpdateState(&state, NO, 1.0, YES, Milliseconds(1120), 43)==
           SRScrollZoomDirectionNone);
}

static void TestContinuousAccumulator(void)
{
    SRScrollZoomState state={0};
    assert(SRScrollZoomUpdateState(&state, YES, 10.0, NO, Milliseconds(2000), 42)==
           SRScrollZoomDirectionNone);
    assert(SRScrollZoomUpdateState(&state, YES, 13.0, NO, Milliseconds(2010), 42)==
           SRScrollZoomDirectionNone);
    assert(SRScrollZoomUpdateState(&state, YES, 1.0, NO, Milliseconds(2020), 42)==
           SRScrollZoomDirectionIn);
    assert(state.accumulatedPoints==0.0);

    // A full threshold is retained while the 50 ms emission gate is closed.
    assert(SRScrollZoomUpdateState(&state, YES, 24.0, NO, Milliseconds(2030), 42)==
           SRScrollZoomDirectionNone);
    assert(state.accumulatedPoints==24.0);
    assert(SRScrollZoomUpdateState(&state, YES, 1.0, NO, Milliseconds(2070), 42)==
           SRScrollZoomDirectionIn);
    assert(state.accumulatedPoints==1.0);

    // Reversing direction drops stale accumulated movement.
    assert(SRScrollZoomUpdateState(&state, YES, -10.0, NO, Milliseconds(2130), 42)==
           SRScrollZoomDirectionNone);
    assert(state.accumulatedPoints==-10.0);
    assert(SRScrollZoomUpdateState(&state, YES, -14.0, NO, Milliseconds(2140), 42)==
           SRScrollZoomDirectionOut);
}

static void TestSessionReset(void)
{
    SRScrollZoomState state={0};
    assert(SRScrollZoomUpdateState(&state, YES, 12.0, NO, Milliseconds(3000), 42)==
           SRScrollZoomDirectionNone);
    assert(state.accumulatedPoints==12.0);

    // Modifier release/momentum suppression clears partial movement.
    assert(SRScrollZoomUpdateState(&state, YES, 8.0, YES, Milliseconds(3010), 42)==
           SRScrollZoomDirectionNone);
    assert(state.accumulatedPoints==0.0);

    assert(SRScrollZoomUpdateState(&state, YES, 12.0, NO, Milliseconds(3020), 42)==
           SRScrollZoomDirectionNone);
    assert(SRScrollZoomUpdateState(&state, YES, 12.0, NO, Milliseconds(3210), 42)==
           SRScrollZoomDirectionNone);
    assert(state.accumulatedPoints==12.0); // idle timeout discarded the prior 12

    SRScrollZoomResetState(&state);
    assert(state.accumulatedPoints==0.0);
    assert(state.lastInputNanoseconds==0);
    assert(state.lastEmissionNanoseconds==0);
    assert(state.lastDirection==SRScrollZoomDirectionNone);
    assert(state.targetPID==0);

    assert(SRScrollZoomUpdateState(NULL, NO, 1.0, NO, Milliseconds(4000), 42)==
           SRScrollZoomDirectionNone);
    assert(SRScrollZoomUpdateState(&state, NO, 1.0, NO, Milliseconds(4000), 0)==
           SRScrollZoomDirectionNone);
}

int main(void)
{
    @autoreleasepool {
        TestModifierMatching();
        TestDeltaNormalizationAndDirection();
        TestDiscreteEveryTick();
        TestContinuousAccumulator();
        TestSessionReset();
    }
    puts("ModifierScrollZoomTests: all tests passed");
    return 0;
}
