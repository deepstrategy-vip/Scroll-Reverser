// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SRScrollZoomModifier) {
    SRScrollZoomModifierControl=0,
    SRScrollZoomModifierCommand=1,
};

typedef NS_ENUM(NSInteger, SRScrollZoomDirection) {
    SRScrollZoomDirectionOut=-1,
    SRScrollZoomDirectionNone=0,
    SRScrollZoomDirectionIn=1,
};

typedef struct {
    double accumulatedPoints;
    uint64_t lastInputNanoseconds;
    uint64_t lastEmissionNanoseconds;
    SRScrollZoomDirection lastDirection;
    pid_t targetPID;
} SRScrollZoomState;

FOUNDATION_EXPORT const double SRScrollZoomContinuousThresholdPoints;
FOUNDATION_EXPORT const uint64_t SRScrollZoomIdleResetNanoseconds;
FOUNDATION_EXPORT const uint64_t SRScrollZoomMinimumEmissionIntervalNanoseconds;
FOUNDATION_EXPORT const int64_t SRScrollZoomSyntheticEventTag;

CGEventFlags SRScrollZoomRequiredEventFlag(NSInteger modifierSetting);
BOOL SRScrollZoomModifierMatches(CGEventFlags eventFlags, NSInteger modifierSetting);
double SRScrollZoomNormalizedDelta(BOOL continuous,
                                   int64_t axisDelta,
                                   int64_t pointDelta,
                                   double fixedPointDelta);
SRScrollZoomDirection SRScrollZoomDirectionForDelta(double delta, BOOL reverseVertical);
CGKeyCode SRScrollZoomKeyCodeForDirection(SRScrollZoomDirection direction);
CGEventFlags SRScrollZoomOutputEventFlags(SRScrollZoomDirection direction);
BOOL SRScrollZoomShouldEndCaptureForModifier(BOOL modifierMatches, BOOL phaseIsNormal);
void SRScrollZoomResetState(SRScrollZoomState *state);
SRScrollZoomDirection SRScrollZoomUpdateState(SRScrollZoomState *state,
                                              BOOL continuous,
                                              double effectiveDelta,
                                              BOOL suppressEmission,
                                              uint64_t nowNanoseconds,
                                              pid_t targetPID);
