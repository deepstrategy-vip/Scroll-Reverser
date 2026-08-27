// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "ModifierScrollZoom.h"
#import <Carbon/Carbon.h>
#import <math.h>
#import <string.h>

const double SRScrollZoomContinuousThresholdPoints=24.0;
const uint64_t SRScrollZoomIdleResetNanoseconds=180000000;
const uint64_t SRScrollZoomMinimumEmissionIntervalNanoseconds=50000000;
const int64_t SRScrollZoomSyntheticEventTag=0x53525A4F4F4D; // "SRZOOM"

// Applications that bind zoom in to Command+= on the main row and ignore the
// numeric-keypad plus key accepted by most applications.
static BOOL _zoomInPrefersMainRowEqual(NSString *bundleIdentifier)
{
    static NSSet<NSString *> *bundleIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleIdentifiers=[NSSet setWithObjects:
            @"cn.wiznote.desktop",          // WizNote
            @"com.pdfeditor.pdfeditormac",  // PDFgear
            nil];
    });
    return bundleIdentifier!=nil&&[bundleIdentifiers containsObject:bundleIdentifier];
}

static SRScrollZoomModifier _sanitizedModifier(NSInteger modifierSetting)
{
    return modifierSetting==SRScrollZoomModifierCommand ?
        SRScrollZoomModifierCommand : SRScrollZoomModifierControl;
}

CGEventFlags SRScrollZoomRequiredEventFlag(NSInteger modifierSetting)
{
    switch (_sanitizedModifier(modifierSetting)) {
        case SRScrollZoomModifierCommand:
            return kCGEventFlagMaskCommand;
        case SRScrollZoomModifierControl:
        default:
            return kCGEventFlagMaskControl;
    }
}

BOOL SRScrollZoomModifierMatches(CGEventFlags eventFlags, NSInteger modifierSetting)
{
    const CGEventFlags chordMask=kCGEventFlagMaskCommand |
                                 kCGEventFlagMaskControl |
                                 kCGEventFlagMaskAlternate |
                                 kCGEventFlagMaskShift;
    return (eventFlags&chordMask)==SRScrollZoomRequiredEventFlag(modifierSetting);
}

double SRScrollZoomNormalizedDelta(BOOL continuous,
                                   int64_t axisDelta,
                                   int64_t pointDelta,
                                   double fixedPointDelta)
{
    if (continuous) {
        if (pointDelta!=0) {
            return (double)pointDelta;
        }
        if (fixedPointDelta!=0.0) {
            // CGEvent point deltas are normally about 8x the fixed-point delta.
            return fixedPointDelta*8.0;
        }
        return (double)axisDelta*8.0;
    }

    if (axisDelta!=0) {
        return (double)axisDelta;
    }
    if (pointDelta!=0) {
        return (double)pointDelta;
    }
    return fixedPointDelta;
}

SRScrollZoomDirection SRScrollZoomDirectionForDelta(double delta, BOOL reverseVertical)
{
    const double effectiveDelta=reverseVertical ? -delta : delta;
    if (effectiveDelta>0.0) {
        return SRScrollZoomDirectionIn;
    }
    if (effectiveDelta<0.0) {
        return SRScrollZoomDirectionOut;
    }
    return SRScrollZoomDirectionNone;
}

CGKeyCode SRScrollZoomKeyCodeForDirection(SRScrollZoomDirection direction)
{
    switch (direction) {
        case SRScrollZoomDirectionIn:
            return kVK_ANSI_KeypadPlus;
        case SRScrollZoomDirectionOut:
            return kVK_ANSI_KeypadMinus;
        case SRScrollZoomDirectionNone:
        default:
            return UINT16_MAX;
    }
}

CGKeyCode SRScrollZoomKeyCodeForDirectionAndBundleIdentifier(
    SRScrollZoomDirection direction,
    NSString *bundleIdentifier)
{
    if (direction==SRScrollZoomDirectionIn&&
        _zoomInPrefersMainRowEqual(bundleIdentifier)) {
        return kVK_ANSI_Equal;
    }
    return SRScrollZoomKeyCodeForDirection(direction);
}

CGEventFlags SRScrollZoomOutputEventFlags(SRScrollZoomDirection direction)
{
    (void)direction;
    return kCGEventFlagMaskCommand;
}

BOOL SRScrollZoomShouldEndCaptureForModifier(BOOL modifierMatches, BOOL phaseIsNormal)
{
    return !modifierMatches&&phaseIsNormal;
}

void SRScrollZoomResetState(SRScrollZoomState *state)
{
    if (state) {
        memset(state, 0, sizeof(*state));
    }
}

SRScrollZoomDirection SRScrollZoomUpdateState(SRScrollZoomState *state,
                                              BOOL continuous,
                                              double effectiveDelta,
                                              BOOL suppressEmission,
                                              uint64_t nowNanoseconds,
                                              pid_t targetPID)
{
    if (!state||targetPID<=0) {
        return SRScrollZoomDirectionNone;
    }

    const SRScrollZoomDirection direction=SRScrollZoomDirectionForDelta(effectiveDelta, NO);
    const BOOL clockWentBack=state->lastInputNanoseconds>nowNanoseconds;
    const BOOL wasIdle=!clockWentBack&&state->lastInputNanoseconds!=0&&
                       nowNanoseconds-state->lastInputNanoseconds>SRScrollZoomIdleResetNanoseconds;
    const BOOL targetChanged=state->targetPID!=0&&state->targetPID!=targetPID;

    if (clockWentBack||wasIdle||targetChanged) {
        SRScrollZoomResetState(state);
    }

    if (direction!=SRScrollZoomDirectionNone&&
        state->lastDirection!=SRScrollZoomDirectionNone&&
        state->lastDirection!=direction) {
        state->accumulatedPoints=0.0;
    }

    state->lastInputNanoseconds=nowNanoseconds;
    state->targetPID=targetPID;
    if (direction!=SRScrollZoomDirectionNone) {
        state->lastDirection=direction;
    }

    if (suppressEmission||direction==SRScrollZoomDirectionNone) {
        state->accumulatedPoints=0.0;
        return SRScrollZoomDirectionNone;
    }

    if (continuous) {
        state->accumulatedPoints+=effectiveDelta;
        if (fabs(state->accumulatedPoints)<SRScrollZoomContinuousThresholdPoints) {
            return SRScrollZoomDirectionNone;
        }
    }

    const BOOL rateLimited=continuous&&state->lastEmissionNanoseconds!=0&&
                           nowNanoseconds>=state->lastEmissionNanoseconds&&
                           nowNanoseconds-state->lastEmissionNanoseconds<SRScrollZoomMinimumEmissionIntervalNanoseconds;
    if (rateLimited) {
        return SRScrollZoomDirectionNone;
    }

    const SRScrollZoomDirection result=continuous ?
        SRScrollZoomDirectionForDelta(state->accumulatedPoints, NO) : direction;
    if (continuous) {
        state->accumulatedPoints-=result*SRScrollZoomContinuousThresholdPoints;
    }
    // A discrete wheel event represents one intentional detent, so preserve a
    // one-detent/one-zoom-step mapping. Only smooth, high-frequency streams
    // need the emission gate.
    state->lastEmissionNanoseconds=continuous ? nowNanoseconds : 0;
    return result;
}
