#!/usr/bin/env python3
"""Execute production Foundation logic on macOS without operating an iPad.

The clock and catalog-loading methods are extracted verbatim from main.m.
UI labels are test doubles: these checks do not establish native rendering,
Core Animation performance, photo decoding or device compatibility.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "App"
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=SOURCE / "main.m")
parser.add_argument("--catalog", type=Path)
parser.add_argument("--expected-count", type=int)
parser.add_argument("--cancellation-proof-dir", type=Path)
parser.add_argument("--reduced-motion-proof-dir", type=Path)
args = parser.parse_args()
if (args.catalog is None) != (args.expected_count is None):
    parser.error("--catalog and --expected-count must be supplied together")
text = args.source.read_text()


def method(name):
    start = re.search(r"^- \([^\n)]+\)" + name + r" \{", text, re.M)
    if not start:
        raise RuntimeError("Production method missing: " + name)
    end = re.search(r"^[-+] \(", text[start.end():], re.M)
    return text[start.start():start.end() + end.start() if end else len(text)]


def class_method(class_name, name):
    implementation = re.search(r"^@implementation\s+" + re.escape(class_name) + r"\b", text, re.M)
    if not implementation:
        raise RuntimeError("Production implementation missing: " + class_name)
    remainder = text[implementation.end():]
    next_implementation = re.search(r"^@implementation\s+", remainder, re.M)
    block = remainder[:next_implementation.start()] if next_implementation else remainder
    start = re.search(r"^- \([^\n)]+\)" + name + r" \{", block, re.M)
    if not start:
        raise RuntimeError("Production class method missing: " + class_name + " " + name)
    end = re.search(r"^[-+] \(", block[start.end():], re.M)
    if end:
        stop = start.end() + end.start()
    else:
        class_end = re.search(r"^@end\b", block[start.end():], re.M)
        stop = start.end() + class_end.start() if class_end else len(block)
    return block[start.start():stop]


def calendar_helper():
    start = text.find("static NSCalendar *IWDisplayCalendar(void) {")
    if start < 0:
        return "static NSCalendar *IWDisplayCalendar(void) { return [NSCalendar currentCalendar]; }"
    end = text.index("\n}", start) + 2
    return text[start:end]


def weather_cache_helper():
    start = text.find("static NSDictionary *IWValidatedWeatherCache(id raw) {")
    if start < 0:
        return "static NSDictionary *IWValidatedWeatherCache(id raw) { return [raw isKindOfClass:[NSDictionary class]] ? raw : nil; }"
    return text[start:text.index("\n}", start) + 2]


HARNESS = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "IWMediaCatalog.h"
#import <objc/runtime.h>
#include <math.h>
@class UIAccessibilityCustomAction;
static NSString *IWAppPath;
typedef NS_ENUM(NSInteger, IWEditTarget) { IWEditTargetNone, IWEditTargetBackground, IWEditTargetClock, IWEditTargetDate, IWEditTargetCalendar, IWEditTargetWeather };
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) { UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed };
static CGFloat IWDigitCardClampOpacity(CGFloat value) { return value; }
static id IWThemePink(CGFloat alpha) { return @"pink"; }
static CGFloat IWControlGap(void) { return 12.0; }
static CGFloat IWControlSize(void) { return 60.0; }
@class UIEvent;
#define IW_TARGET_SELECTION_WIRED __TARGET_SELECTION_WIRED__
#define IW_ACCESSIBILITY_ACTIONS_WIRED __ACCESSIBILITY_ACTIONS_WIRED__
__CALENDAR__
__WEATHER_CACHE__
static NSCalendar *buddhistCalendar(id self, SEL selector) {
    return [NSCalendar calendarWithIdentifier:NSCalendarIdentifierBuddhist];
}
static NSDate *IWFixedNow;
static NSDate *fixedDate(id self, SEL selector) { return IWFixedNow; }
@interface UILabel : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic) BOOL hidden;
@end
@implementation UILabel
@end
@interface TestRasterLayer : NSObject
@property(nonatomic) CGFloat rasterizationScale;
@end
@implementation TestRasterLayer
@end
@interface UIView : NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic,strong) NSDictionary *labels;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic,strong) TestRasterLayer *layer;
- (id)viewWithTag:(NSInteger)tag;
- (void)setNeedsLayout;
@end
@implementation UIView
- (id)viewWithTag:(NSInteger)tag { return self.labels[@(tag)]; }
- (void)setNeedsLayout {}
@end
@interface UIControl : UIView @end
@implementation UIControl @end
@interface UIScreen : NSObject
@property(nonatomic) CGFloat scale;
+ (UIScreen *)mainScreen;
@end
@implementation UIScreen
+ (UIScreen *)mainScreen {
    static UIScreen *screen;
    if (!screen) { screen = [UIScreen new]; screen.scale = 2.0; }
    return screen;
}
@end
@interface UIPanGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) CGPoint translation;
- (CGPoint)translationInView:(UIView *)view;
@end
@implementation UIPanGestureRecognizer
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.translation; }
@end
@interface IWGalleryController : NSObject @end
@implementation IWGalleryController @end
@interface IWFlipDigitLabel : UILabel
@property(nonatomic) NSInteger updates;
@property(nonatomic) NSInteger animatedUpdates;
- (void)setDigitText:(NSString *)text animated:(BOOL)animated;
@end
@implementation IWFlipDigitLabel
- (void)setDigitText:(NSString *)text animated:(BOOL)animated {
    self.updates += 1; self.text = text;
    if (animated) self.animatedUpdates += 1;
}
@end
static NSString * const AVPlayerItemDidPlayToEndTimeNotification = @"TestPlayerFinished";
static NSString * const AVPlayerItemFailedToPlayToEndTimeNotification = @"TestPlayerFailed";
@interface TestPlayer : NSObject
@property(nonatomic,strong) id currentItem;
@end
@implementation TestPlayer
@end
@interface ClockHarness : NSObject {
@public
    NSArray *_digitLabels, *_countdownDayLabels, *_colonViews, *_wallpapers;
    UILabel *_dateLabel;
    BOOL _gta6CountdownMode, _showSeconds, _hour24, _dateVisible;
    BOOL _videoMinimized;
    UIView *_videoOverlay;
    NSInteger _dateLanguage, _wallpaperIndex, _userLoads;
    NSString *_savedWallpaperKey;
    TestPlayer *_remoteVideoPlayer;
    BOOL _usingRemoteVideoPlayer, _castError;
    NSInteger _closeCalls;
    BOOL _editMode, _controlsHidden, _calendarHiddenForClockEdit;
    IWEditTarget _editTarget;
    NSDictionary *_editSnapshot;
    CGFloat _clockOffsetX, _clockOffsetY, _clockScale, _dateOffsetX, _dateOffsetY, _dateScale;
    CGFloat _calendarScale, _calendarOffsetX, _calendarOffsetY, _calendarOpacity;
    CGFloat _weatherScale, _weatherOffsetX, _weatherOffsetY;
    CGFloat _digitCardOpacity, _digitCardBorderWidth, _backgroundX, _backgroundY, _backgroundZoom;
    id _digitCardBorderColor;
    UIView *_borderControl, *_opacityControl;
    CGFloat _editControlsOffsetX, _editControlsOffsetY;
    CGPoint _editControlsPanStart;
    BOOL _testDateHit, _testClockHit;
    UILabel *_menuButton, *_calendarPanel;
    NSInteger _stateSaves, _backgroundSaves;
    NSInteger _persistCalls, _debugWrites;
    NSDictionary *_savedValues;
    NSArray *_homeCards;
    UILabel *_homeUpdatedLabel;
    NSString *_castLastId, *_castSrc, *_castTitle;
}
@property(nonatomic,strong) UIView *view;
@property(nonatomic,strong) id presentedViewController;
- (void)tick;
- (void)loadWallpapers;
- (void)updateCalendarPanel;
- (void)appendUserWallpapersToItems:(NSMutableArray *)items;
- (void)remoteVideoFinished:(NSNotification *)notification;
- (void)removeRemoteVideoObservers;
- (void)closeVideo;
- (NSString *)userWallpaperDirectory;
- (BOOL)canDeleteWallpaperAtIndex:(NSInteger)index;
- (void)cancelEditMode;
- (void)updateBorderControlVisibility;
- (void)updateOpacityControlVisibility;
- (void)handleEditControlsPan:(UIPanGestureRecognizer *)recognizer;
- (BOOL)moveEditControlsToOrigin:(CGPoint)origin persist:(BOOL)persist;
- (BOOL)accessibilityMoveEditControlsLeft:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsRight:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsUp:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsDown:(UIAccessibilityCustomAction *)action;
- (void)selectClockOrDateEditTargetAtPoint:(CGPoint)point;
- (BOOL)pointHitsView:(id)view rootPoint:(CGPoint)point;
- (BOOL)pointHitsVisibleClockDigit:(CGPoint)point;
- (void)applyCalendarTransform;
- (void)applyWeatherTransform;
- (void)updateWeatherEditAppearance;
- (void)applyCalendarOpacity;
- (void)applyClockTransforms;
- (void)applyDigitCardOpacity;
- (void)applyDigitCardBorderStyle;
- (void)applyBackgroundTransform;
- (void)hideEditToolbarAnimated;
- (void)updateMenuButtons;
- (void)saveBackgroundAdjustment;
- (void)saveState;
- (NSDictionary *)jsonAtPath:(NSString *)path;
- (void)resetHomePlaceholders:(NSString *)updatedText;
- (void)loadHomeStatus;
- (NSString *)formatTemperature:(id)value;
- (NSString *)formatHumidity:(id)value;
- (NSString *)formatHomeUpdated:(NSString *)value;
- (void)loadCastStatus;
- (void)calendarTouchUp:(UIControl *)control forEvent:(UIEvent *)event;
- (void)weatherTouchUp:(UIControl *)control forEvent:(UIEvent *)event;
- (void)persistCurrentEditValues;
- (void)writeDebugState:(NSString *)context;
@end
@implementation ClockHarness
- (void)updateCalendarPanel {}
- (void)closeVideo { _closeCalls++; }
- (NSString *)userWallpaperDirectory { return [IWAppPath stringByAppendingPathComponent:@"assets/user"]; }
- (void)applyCalendarTransform {}
- (void)applyWeatherTransform {}
- (void)updateWeatherEditAppearance {}
- (void)applyCalendarOpacity {}
- (void)applyClockTransforms {}
- (void)applyDigitCardOpacity {}
- (void)applyDigitCardBorderStyle {}
- (void)applyBackgroundTransform {}
- (BOOL)pointHitsView:(id)view rootPoint:(CGPoint)point { return view == (id)_dateLabel && _testDateHit; }
- (BOOL)pointHitsVisibleClockDigit:(CGPoint)point { (void)point; return _testClockHit; }
- (void)hideEditToolbarAnimated {}
- (void)updateMenuButtons {}
- (void)saveBackgroundAdjustment { _backgroundSaves++; }
- (void)saveState { _stateSaves++; _savedValues = @{@"clockX": @(_clockOffsetX), @"dateX": @(_dateOffsetX), @"calendarScale": @(_calendarScale), @"weatherX": @(_weatherOffsetX), @"weatherY": @(_weatherOffsetY), @"weatherScale": @(_weatherScale)}; }
- (void)persistCurrentEditValues { _persistCalls++; }
- (void)writeDebugState:(NSString *)context { (void)context; _debugWrites++; }
- (void)appendUserWallpapersToItems:(NSMutableArray *)items {
    _userLoads++;
    [items addObject:@{@"index": @([items count]), @"key": @"user-fixture"}];
}
__METHODS__
@end
static NSInteger checks = 0, failures = 0;
static void check(BOOL condition, NSString *name) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", name.UTF8String); }
}
static void testEditControlsPan(ClockHarness *clock, IWEditTarget target, BOOL editMode, BOOL expectedMove, NSString *name) {
    clock->_editMode = editMode;
    clock->_editTarget = target;
    clock->_editControlsOffsetX = 0.0;
    clock->_editControlsOffsetY = 0.0;
    clock.view = [UIView new];
    clock.view.bounds = CGRectMake(0.0, 0.0, 1024.0, 768.0);
    clock->_borderControl = [UIView new];
    clock->_opacityControl = [UIView new];
    clock->_borderControl.frame = CGRectMake(0.0, 0.0, 262.0, 180.0);
    clock->_opacityControl.frame = CGRectMake(0.0, 0.0, 334.0, 40.0);
    UIPanGestureRecognizer *pan = [UIPanGestureRecognizer new];
    NSInteger saves = clock->_stateSaves;
    pan.state = UIGestureRecognizerStateBegan;
    pan.translation = CGPointMake(0.0, 0.0);
    [clock handleEditControlsPan:pan];
    pan.state = UIGestureRecognizerStateChanged;
    pan.translation = CGPointMake(48.0, 30.0);
    [clock handleEditControlsPan:pan];
    BOOL moved = clock->_editControlsOffsetX == 48.0 && clock->_editControlsOffsetY == 30.0;
    check(moved == expectedMove, [name stringByAppendingString:@" move gesture changes offsets only when supported"]);
    pan.state = UIGestureRecognizerStateEnded;
    [clock handleEditControlsPan:pan];
    check(clock->_stateSaves == saves + (expectedMove ? 1 : 0), [name stringByAppendingString:@" end persists only accepted movement"]);
    CGFloat expectedY = target == IWEditTargetCalendar ? 48.0 : 48.0 + 184.0;
    check(clock->_opacityControl.frame.origin.x == (expectedMove ? 68.0 : 0.0) &&
          clock->_opacityControl.frame.origin.y == (expectedMove ? expectedY : 0.0),
          [name stringByAppendingString:@" slider frame follows move target"]);
    check(clock->_borderControl.frame.origin.x == (expectedMove ? 68.0 : 0.0) &&
          clock->_borderControl.frame.origin.y == (expectedMove ? 48.0 : 0.0),
          [name stringByAppendingString:@" border frame follows move target"]);
}
static void testClockDateTargetSwitch(ClockHarness *clock) {
    clock->_editMode = YES;
    clock->_dateLabel = [UILabel new];
    clock->_borderControl = [UIView new];
    clock->_opacityControl = [UIView new];
    clock->_borderControl.hidden = YES;
    clock->_opacityControl.hidden = YES;
    clock->_editTarget = IWEditTargetDate;
    clock->_testClockHit = YES;
    clock->_testDateHit = NO;
    [clock selectClockOrDateEditTargetAtPoint:CGPointMake(100.0, 100.0)];
    check(clock->_editTarget == IWEditTargetClock && !clock->_borderControl.hidden && !clock->_opacityControl.hidden,
          @"Date-to-Clock target switch reveals clock border controls");
    clock->_editTarget = IWEditTargetClock;
    clock->_testClockHit = NO;
    clock->_testDateHit = YES;
    [clock selectClockOrDateEditTargetAtPoint:CGPointMake(100.0, 100.0)];
    check(clock->_editTarget == IWEditTargetDate && clock->_borderControl.hidden && !clock->_opacityControl.hidden,
          @"Clock-to-Date target switch hides border controls and keeps opacity control");
}
static void testEditControlsAccessibility(ClockHarness *clock) {
    check(IW_ACCESSIBILITY_ACTIONS_WIRED, @"move button publishes four directional accessibility actions");
    for (NSNumber *targetValue in @[@(IWEditTargetClock), @(IWEditTargetDate), @(IWEditTargetCalendar)]) {
        IWEditTarget target = (IWEditTarget)targetValue.integerValue;
        clock->_editMode = YES;
        clock->_editTarget = target;
        clock.view = [UIView new];
        clock.view.bounds = CGRectMake(0.0, 0.0, 1024.0, 768.0);
        clock->_editControlsOffsetX = 0.0;
        clock->_editControlsOffsetY = 0.0;
        clock->_borderControl = [UIView new];
        clock->_opacityControl = [UIView new];
        NSInteger saves = clock->_stateSaves;
        check([clock accessibilityMoveEditControlsRight:nil], @"allowed target accepts right accessibility move");
        check(clock->_editControlsOffsetX == 16.0 && clock->_stateSaves == saves + 1,
              @"right accessibility move updates and persists offset");
        check([clock accessibilityMoveEditControlsLeft:nil] && clock->_editControlsOffsetX == 0.0,
              @"left accessibility move returns controls to original x");
        check([clock accessibilityMoveEditControlsUp:nil] && clock->_editControlsOffsetY == -16.0,
              @"up accessibility move updates y");
        check([clock accessibilityMoveEditControlsDown:nil] && clock->_editControlsOffsetY == 0.0,
              @"down accessibility move returns controls to original y");
        CGFloat expectedOpacityY = 202.0;
        if (target == IWEditTargetCalendar) expectedOpacityY = 18.0;
        check(clock->_opacityControl.frame.origin.x == 20.0 && clock->_opacityControl.frame.origin.y == expectedOpacityY,
              @"accessibility movement preserves per-target panel placement");
    }
    for (NSNumber *targetValue in @[@(IWEditTargetNone), @(IWEditTargetBackground), @(IWEditTargetWeather)]) {
        clock->_editMode = targetValue.integerValue != IWEditTargetNone;
        clock->_editTarget = (IWEditTarget)targetValue.integerValue;
        CGFloat x = clock->_editControlsOffsetX = 27.0;
        CGFloat y = clock->_editControlsOffsetY = 33.0;
        NSInteger saves = clock->_stateSaves;
        check(![clock accessibilityMoveEditControlsRight:nil] &&
              clock->_editControlsOffsetX == x && clock->_editControlsOffsetY == y && clock->_stateSaves == saves,
              @"non-edit, background, and weather targets reject accessibility move");
    }
    clock->_editMode = YES;
    clock->_editTarget = IWEditTargetClock;
    clock.view.bounds = CGRectMake(0.0, 0.0, 1024.0, 768.0);
    clock->_editControlsOffsetX = 4000.0;
    check([clock accessibilityMoveEditControlsRight:nil] && clock->_editControlsOffsetX == 670.0,
          @"accessibility movement clamps horizontal edge to viewport");
    clock->_editControlsOffsetY = 4000.0;
    check([clock accessibilityMoveEditControlsDown:nil] && clock->_editControlsOffsetY == 508.0,
          @"accessibility movement clamps vertical edge to viewport");
}
static void testEditControlsPanCancelled(ClockHarness *clock, IWEditTarget target, NSString *name) {
    clock->_editMode = YES;
    clock->_editTarget = target;
    clock->_editControlsOffsetX = 0.0;
    clock->_editControlsOffsetY = 0.0;
    clock.view = [UIView new];
    clock.view.bounds = CGRectMake(0.0, 0.0, 1024.0, 768.0);
    clock->_borderControl = [UIView new];
    clock->_opacityControl = [UIView new];
    UIPanGestureRecognizer *pan = [UIPanGestureRecognizer new];
    NSInteger saves = clock->_stateSaves;
    pan.state = UIGestureRecognizerStateBegan;
    pan.translation = CGPointMake(0.0, 0.0);
    [clock handleEditControlsPan:pan];
    pan.state = UIGestureRecognizerStateChanged;
    pan.translation = CGPointMake(36.0, 18.0);
    [clock handleEditControlsPan:pan];
    pan.state = UIGestureRecognizerStateCancelled;
    [clock handleEditControlsPan:pan];
    check(clock->_editControlsOffsetX == 36.0 && clock->_editControlsOffsetY == 18.0 && clock->_stateSaves == saves + 1,
          [name stringByAppendingString:@" cancelled move keeps and persists accepted position"]);
}
static void testPanelRasterizationTerminalCallbacks(ClockHarness *clock, BOOL weather) {
    IWEditTarget matchingTarget = weather ? IWEditTargetWeather : IWEditTargetCalendar;
    IWEditTarget otherTarget = weather ? IWEditTargetCalendar : IWEditTargetWeather;
    NSString *name = weather ? @"Weather" : @"Calendar";
    CGFloat originalScale = [UIScreen mainScreen].scale;
    UIControl *control = [UIControl new]; control.layer = [TestRasterLayer new];
    /* The inspected production Down handlers set 1x while dragging; seed that resulting state to isolate Up. */

    [UIScreen mainScreen].scale = 2.0;
    clock->_editMode = YES; clock->_editTarget = matchingTarget;
    control.layer.rasterizationScale = 1.0;
    NSInteger saves = clock->_persistCalls;
    if (weather) [clock weatherTouchUp:control forEvent:nil]; else [clock calendarTouchUp:control forEvent:nil];
    check(control.layer.rasterizationScale == 2.0,
          [name stringByAppendingString:@" matching edit Up restores Retina cache scale"]);
    check(clock->_persistCalls == saves + 1,
          [name stringByAppendingString:@" matching edit Up persists once"]);

    clock->_editMode = NO; clock->_editTarget = IWEditTargetNone;
    control.layer.rasterizationScale = 1.0; saves = clock->_persistCalls;
    if (weather) [clock weatherTouchUp:control forEvent:nil]; else [clock calendarTouchUp:control forEvent:nil];
    check(control.layer.rasterizationScale == 2.0,
          [name stringByAppendingString:@" late non-edit Up restores Retina cache scale"]);
    check(clock->_persistCalls == saves,
          [name stringByAppendingString:@" late non-edit Up does not persist"]);

    clock->_editMode = YES; clock->_editTarget = otherTarget;
    control.layer.rasterizationScale = 1.0; saves = clock->_persistCalls;
    if (weather) [clock weatherTouchUp:control forEvent:nil]; else [clock calendarTouchUp:control forEvent:nil];
    check(control.layer.rasterizationScale == 2.0,
          [name stringByAppendingString:@" mismatched-target Up restores Retina cache scale"]);
    check(clock->_persistCalls == saves,
          [name stringByAppendingString:@" mismatched-target Up does not persist"]);

    [UIScreen mainScreen].scale = 1.0;
    clock->_editMode = YES; clock->_editTarget = matchingTarget;
    control.layer.rasterizationScale = 1.0; saves = clock->_persistCalls;
    if (weather) [clock weatherTouchUp:control forEvent:nil]; else [clock calendarTouchUp:control forEvent:nil];
    check(control.layer.rasterizationScale == 1.0,
          [name stringByAppendingString:@" matching edit Up remains correct at 1x screen scale"]);
    check(clock->_persistCalls == saves + 1,
          [name stringByAppendingString:@" 1x matching edit Up preserves persistence"]);
    [UIScreen mainScreen].scale = originalScale;
}
static NSArray *digits(NSInteger count) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) [items addObject:[IWFlipDigitLabel new]];
    return items;
}
static void writeStatus(NSString *name, NSString *json) {
    [json writeToFile:[IWAppPath stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    IWAppPath = [NSString stringWithUTF8String:argv[1]];
    ClockHarness *clock = [ClockHarness new];
    testPanelRasterizationTerminalCallbacks(clock, NO);
    testPanelRasterizationTerminalCallbacks(clock, YES);
    check(IW_TARGET_SELECTION_WIRED, @"both raw-touch and pan-fallback target selection refresh control visibility");
    testEditControlsPan(clock, IWEditTargetClock, YES, YES, @"Clock edit");
    testEditControlsPan(clock, IWEditTargetDate, YES, YES, @"Date edit");
    testEditControlsPan(clock, IWEditTargetCalendar, YES, YES, @"Calendar edit");
    testEditControlsPan(clock, IWEditTargetWeather, YES, NO, @"Weather edit");
    testEditControlsPan(clock, IWEditTargetBackground, YES, NO, @"Background edit");
    testEditControlsPan(clock, IWEditTargetClock, NO, NO, @"Non-edit mode");
    testEditControlsPanCancelled(clock, IWEditTargetDate, @"Date edit");
    testEditControlsPanCancelled(clock, IWEditTargetCalendar, @"Calendar edit");
    testClockDateTargetSwitch(clock);
    testEditControlsAccessibility(clock);
    clock->_digitLabels = digits(6); clock->_countdownDayLabels = digits(3);
    clock->_colonViews = digits(3); clock->_dateLabel = [UILabel new];
    clock->_hour24 = YES; clock->_dateVisible = YES;
    [clock tick];
    for (NSInteger i = 0; i < 6; i++) {
        IWFlipDigitLabel *digit = clock->_digitLabels[i];
        check(digit.updates == (i < 4 ? 1 : 0), @"hidden seconds perform no digit work");
        check(digit.hidden == (i >= 4), @"seconds visibility matches setting");
    }
    clock->_showSeconds = YES; [clock tick];
    for (IWFlipDigitLabel *digit in clock->_digitLabels) check(!digit.hidden && digit.updates > 0, @"enabling seconds updates all digits");
    NSInteger secondsUpdates = ((IWFlipDigitLabel *)clock->_digitLabels[5]).updates;
    clock->_showSeconds = NO; [clock tick];
    check(((IWFlipDigitLabel *)clock->_digitLabels[5]).updates == secondsUpdates, @"disabling seconds stops further updates");
    clock->_gta6CountdownMode = YES; [clock tick];
    for (IWFlipDigitLabel *digit in clock->_digitLabels) check(!digit.hidden && digit.text.length == 1, @"countdown retains seconds");
    for (IWFlipDigitLabel *digit in clock->_countdownDayLabels) check(!digit.hidden && digit.text.length == 1, @"countdown retains day digits");
    check(clock->_dateLabel.hidden, @"countdown date visibility");
    clock->_gta6CountdownMode = NO;
    for (NSInteger language = 0; language < 4; language++) {
        clock->_dateLanguage = language; [clock tick];
        check(clock->_dateLabel.text.length > 0 && !clock->_dateLabel.hidden, @"normal date restored in every existing language");
    }
    clock->_showSeconds = YES;
    for (NSInteger overlay = 0; overlay < 3; overlay++) {
        clock.presentedViewController = overlay == 0 ? [IWGalleryController new] : nil;
        clock->_videoOverlay = overlay == 1 ? [UIView new] : nil;
        NSInteger animatedBefore = 0;
        for (IWFlipDigitLabel *digit in clock->_digitLabels) { digit.text = @"X"; animatedBefore += digit.animatedUpdates; }
        [clock tick];
        NSInteger animatedAfter = 0;
        for (IWFlipDigitLabel *digit in clock->_digitLabels) animatedAfter += digit.animatedUpdates;
        check(overlay == 2 ? animatedAfter > animatedBefore : animatedAfter == animatedBefore, @"covered clock does not animate and visible clock resumes animation");
    }
    IWFixedNow = [NSDate date];
    Method dateMethod = class_getClassMethod([NSDate class], @selector(date));
    IMP originalDate = method_setImplementation(dateMethod, (IMP)fixedDate);
    [clock tick];
    NSInteger unchangedUpdates = 0;
    for (IWFlipDigitLabel *digit in clock->_digitLabels) unchangedUpdates += digit.updates;
    [clock tick];
    NSInteger unchangedUpdatesAfter = 0;
    for (IWFlipDigitLabel *digit in clock->_digitLabels) unchangedUpdatesAfter += digit.updates;
    check(unchangedUpdates == unchangedUpdatesAfter, @"unchanged tick does not repaint digits or interrupt an active same-target flip");
    method_setImplementation(dateMethod, originalDate);
    Method currentCalendar = class_getClassMethod([NSCalendar class], @selector(currentCalendar));
    IMP originalCalendar = method_setImplementation(currentCalendar, (IMP)buddhistCalendar);
    check([IWDisplayCalendar().calendarIdentifier isEqual:NSCalendarIdentifierGregorian], @"Gregorian dates do not inherit a Buddhist system calendar");
    [clock tick];
    method_setImplementation(currentCalendar, originalCalendar);

    check(IWMediaCatalogItems(nil, IWAppPath, NULL).count == 0, @"missing optional catalog");
    check(IWMediaCatalogItems(@"window.WALLPAPERS = [broken];", IWAppPath, NULL).count == 0, @"malformed catalog");
    check(IWMediaCatalogItems(@"{}", IWAppPath, NULL).count == 0, @"non-array catalog");
    NSString *catalog = @"window.WALLPAPERS = [null,{\"src\":42},{\"src\":\"./assets/one.jpg?x=1\",\"key\":\"one\",\"thumb\":null},{\"src\":\"../outside.jpg\"},{\"src\":\"./assets/two.jpg\",\"key\":\"two\",\"label\":false},{\"src\":\"./assets/duplicate.jpg\",\"key\":\"one\"}];";
    NSArray *items = IWMediaCatalogItems(catalog, IWAppPath, NULL);
    check(items.count == 2, @"invalid and duplicate entries skipped");
    check([items[0][@"index"] integerValue] == 0 && [items[1][@"index"] integerValue] == 1, @"selection indexes remain contiguous after rejected entries");
    check([items[0][@"imagePath"] isEqual:[IWAppPath stringByAppendingPathComponent:@"assets/one.jpg"]], @"relative path and query normalization");
    check([items[0][@"imagePath"] isEqual:items[0][@"thumbPath"]], @"missing thumbnail uses source image");
    check([items[1][@"label"] isEqual:@""], @"malformed metadata normalized");
    for (NSString *path in @[@"../outside.jpg", @"/tmp/outside.jpg", @"file:///tmp/outside.jpg", @"../../app-neighbor/outside.jpg"]) {
        check(IWCatalogMediaPath(path, IWAppPath) == nil, @"catalog cannot reference outside media root");
    }
    NSArray *video = IWMediaCatalogItems(@"[{\"type\":\"video\",\"src\":\"poster.jpg\",\"video\":\"movie.mp4\"}]", IWAppPath, NULL);
    check(video.count == 1 && [video[0][@"type"] isEqual:@"video"], @"existing video interface retained");
    NSArray *categorized = IWMediaCatalogItems(@"[{\"src\":\"person.jpg\",\"category\":\"people\",\"label\":\"杰森 01\"},{\"src\":\"legacy.jpg\",\"category\":42}]", IWAppPath, NULL);
    check([categorized[0][@"category"] isEqual:@"people"] && [categorized[0][@"label"] isEqual:@"杰森 01"], @"category survives parsing independently of the short display name");
    check([categorized[1][@"category"] isEqual:@""], @"malformed category remains an unclassified legacy image");
    if (argc == 4) {
        NSString *catalogText = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[2]] encoding:NSUTF8StringEncoding error:nil];
        check(IWMediaCatalogItems(catalogText, IWAppPath, NULL).count == (NSUInteger)atol(argv[3]), @"historical catalog retains every existing entry");
    }

    @try {
        [clock loadWallpapers];
        check(clock->_userLoads == 1 && clock->_wallpapers.count == 1, @"user imports load without bundled catalog");
        NSString *file = [IWAppPath stringByAppendingPathComponent:@"wallpapers.generated.js"];
        [catalog writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [clock loadWallpapers];
        check(clock->_userLoads == 2 && clock->_wallpapers.count == 3, @"bad bundled entries do not block user media");
        clock->_savedWallpaperKey = @"two"; clock->_wallpaperIndex = 0;
        [clock loadWallpapers];
        check(clock->_wallpaperIndex == 1, @"stable identity restores selected wallpaper after catalog rows move");
        clock->_savedWallpaperKey = nil; clock->_wallpaperIndex = 6;
        [clock loadWallpapers];
        check(clock->_wallpaperIndex == 2, @"legacy imported selection survives rejected bundled rows");
        clock->_savedWallpaperKey = nil; clock->_wallpaperIndex = 4;
        [clock loadWallpapers];
        check(clock->_wallpaperIndex == 1, @"legacy bundled selection survives rejected earlier rows");
        clock->_savedWallpaperKey = @"missing"; clock->_wallpaperIndex = 1;
        [clock loadWallpapers];
        check(clock->_wallpaperIndex == 0, @"missing selected identity has a valid fallback");
    } @catch (NSException *exception) {
        check(NO, [@"production catalog loader threw " stringByAppendingString:exception.name]);
    }
    clock->_remoteVideoPlayer = [TestPlayer new];
    clock->_remoteVideoPlayer.currentItem = [NSObject new];
    clock->_usingRemoteVideoPlayer = YES;
    id oldItem = [NSObject new];
    [clock remoteVideoFinished:[NSNotification notificationWithName:AVPlayerItemDidPlayToEndTimeNotification object:oldItem]];
    check(clock->_closeCalls == 0, @"old remote completion cannot close replacement");
    [clock remoteVideoFinished:[NSNotification notificationWithName:AVPlayerItemDidPlayToEndTimeNotification object:clock->_remoteVideoPlayer.currentItem]];
    check(clock->_closeCalls == 1 && !clock->_castError, @"current remote completion closes playback");
    clock->_usingRemoteVideoPlayer = NO;
    [clock remoteVideoFinished:[NSNotification notificationWithName:AVPlayerItemDidPlayToEndTimeNotification object:clock->_remoteVideoPlayer.currentItem]];
    check(clock->_closeCalls == 1, @"remote notification cannot close local playback");
    clock->_usingRemoteVideoPlayer = YES;
    [clock remoteVideoFinished:[NSNotification notificationWithName:AVPlayerItemFailedToPlayToEndTimeNotification object:clock->_remoteVideoPlayer.currentItem]];
    check(clock->_closeCalls == 2 && clock->_castError, @"remote failure sets error and closes playback");
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (NSString *name in @[AVPlayerItemDidPlayToEndTimeNotification, AVPlayerItemFailedToPlayToEndTimeNotification])
        [center addObserver:clock selector:@selector(remoteVideoFinished:) name:name object:clock->_remoteVideoPlayer.currentItem];
    [clock removeRemoteVideoObservers];
    [center postNotificationName:AVPlayerItemDidPlayToEndTimeNotification object:clock->_remoteVideoPlayer.currentItem];
    [center postNotificationName:AVPlayerItemFailedToPlayToEndTimeNotification object:clock->_remoteVideoPlayer.currentItem];
    check(clock->_closeCalls == 2, @"both item observers are removed on teardown");
    clock->_wallpapers = @[
        @{@"fileName": @"user-valid.jpg", @"imagePath": [IWAppPath stringByAppendingPathComponent:@"assets/user/user-valid.jpg"]},
        @{@"fileName": @"user-bundled.jpg", @"imagePath": [IWAppPath stringByAppendingPathComponent:@"assets/user-bundled/user-bundled.jpg"]},
        @{@"fileName": @"builtin.jpg", @"imagePath": [IWAppPath stringByAppendingPathComponent:@"assets/user/builtin.jpg"]}
    ];
    check([clock canDeleteWallpaperAtIndex:0], @"user import remains deletable");
    check(![clock canDeleteWallpaperAtIndex:1], @"neighbor directory cannot be deleted as user media");
    check(![clock canDeleteWallpaperAtIndex:2], @"non-user file remains protected");
    check(![clock canDeleteWallpaperAtIndex:-1] && ![clock canDeleteWallpaperAtIndex:3], @"out of range deletion remains protected");
    clock->_menuButton = [UILabel new]; clock->_calendarPanel = [UILabel new];
    NSDictionary *snapshot = @{@"clockX": @10, @"clockY": @20, @"clockZoom": @1, @"dateX": @30, @"dateY": @40, @"dateZoom": @1, @"digitCardOpacity": @0.7, @"digitCardBorderColor": @"original", @"digitCardBorderWidth": @2};
    for (NSNumber *target in @[@(IWEditTargetClock), @(IWEditTargetDate)]) {
        clock->_editMode = YES; clock->_editTarget = target.integerValue; clock->_editSnapshot = snapshot;
        clock->_clockOffsetX = 999; clock->_dateOffsetX = 999; clock->_digitCardBorderColor = @"changed";
        clock->_calendarHiddenForClockEdit = YES; clock->_calendarPanel.hidden = YES;
        NSInteger saves = clock->_stateSaves;
        [clock cancelEditMode];
        check(clock->_clockOffsetX == 10 && clock->_dateOffsetX == 30, @"cancel restores both clock and date layout");
        check([clock->_digitCardBorderColor isEqual:@"original"] && clock->_digitCardBorderWidth == 2, @"cancel restores border after changing edit target");
        check(clock->_stateSaves == saves + 1 && [clock->_savedValues[@"clockX"] integerValue] == 10, @"cancel persists restored layout after gesture saves");
        check(!clock->_calendarPanel.hidden && !clock->_calendarHiddenForClockEdit, @"cancel restores temporarily hidden calendar for either edit target");
        check(!clock->_editMode && clock->_editSnapshot == nil, @"cancel clears editing session");
    }
    clock->_editMode = YES; clock->_editTarget = IWEditTargetCalendar;
    clock->_editSnapshot = @{@"calendarScale": @1.2, @"calendarX": @10, @"calendarY": @20, @"calendarOpacity": @0.6};
    [clock cancelEditMode];
    check(fabs(clock->_calendarScale - 1.2) < 0.001 && fabs([clock->_savedValues[@"calendarScale"] doubleValue] - 1.2) < 0.001, @"cancel persists restored calendar");
    clock->_editMode = YES; clock->_editTarget = IWEditTargetWeather;
    clock->_editSnapshot = @{@"weatherScale": @1.2, @"weatherX": @10, @"weatherY": @20};
    clock->_weatherScale = 1.5; clock->_weatherOffsetX = 999; clock->_weatherOffsetY = 999;
    [clock cancelEditMode];
    check(fabs(clock->_weatherScale - 1.2) < 0.001 && clock->_weatherOffsetX == 10 && clock->_weatherOffsetY == 20, @"cancel restores weather layout");
    check(fabs([clock->_savedValues[@"weatherScale"] doubleValue] - 1.2) < 0.001 && [clock->_savedValues[@"weatherX"] doubleValue] == 10 && [clock->_savedValues[@"weatherY"] doubleValue] == 20, @"cancel persists restored weather after gesture saves");
    clock->_editMode = YES; clock->_editTarget = IWEditTargetBackground;
    clock->_editSnapshot = @{@"x": @10, @"y": @20, @"zoom": @1.5};
    [clock cancelEditMode];
    check(clock->_backgroundX == 10 && clock->_backgroundSaves == 1, @"cancel persists restored wallpaper framing");
    NSInteger saves = clock->_stateSaves;
    [clock cancelEditMode];
    check(clock->_stateSaves == saves && clock->_backgroundSaves == 1, @"cancel outside editing does not overwrite stored layout");
    clock.view = [UIView new]; clock->_homeUpdatedLabel = [UILabel new];
    NSMutableArray *cards = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *card = [UIView new];
        card.labels = @{@1: [UILabel new], @2: [UILabel new], @3: [UILabel new]};
        [cards addObject:card];
    }
    clock->_homeCards = cards;
    @try {
        NSMutableDictionary *cache = [@{@"temperature": @20, @"high": @25, @"low": @15, @"precipitationProbability": @30, @"code": @2, @"isDay": @YES, @"latitude": @51.5, @"longitude": @-0.1, @"fetchedAt": [NSDate date], @"provider": @"Open-Meteo"} mutableCopy];
        check(IWValidatedWeatherCache(cache) != nil, @"valid persisted weather remains available offline");
        for (id invalid in @[[NSNull null], @[], @{}, @"20", @YES]) {
            cache[@"temperature"] = invalid;
            check(IWValidatedWeatherCache(cache) == nil, @"malformed cached temperature is discarded before display");
        }
        cache[@"temperature"] = @20; cache[@"longitude"] = @181;
        check(IWValidatedWeatherCache(cache) == nil, @"invalid cached coordinate is never reused for network fetch");
        cache[@"longitude"] = @-0.1; cache[@"code"] = @2.5;
        check(IWValidatedWeatherCache(cache) == nil, @"invalid cached condition code is discarded");
        cache[@"code"] = @2; cache[@"fetchedAt"] = @"bad";
        check(IWValidatedWeatherCache(cache) == nil, @"invalid cached fetch date is discarded");
        check(IWValidatedWeatherCache(@[]) == nil, @"malformed cache root is discarded");
        for (NSString *json in @[@"[]", @"{}", @"{\"items\":null,\"updatedAt\":null}", @"{\"items\":[null,3,\"bad\"],\"updatedAt\":3}"]) {
            writeStatus(@"home-status.json", json); [clock loadHomeStatus];
            check([[(UILabel *)[(UIView *)cards[0] viewWithTag:2] text] isEqual:@"--"], @"missing or malformed home items keep placeholders");
        }
        writeStatus(@"home-status.json", @"{\"items\":[null,{\"label\":\"客厅\",\"temperature\":22.5,\"humidity\":54},false,{\"label\":null,\"value\":{},\"meta\":[]}],\"updatedAt\":null}");
        [clock loadHomeStatus];
        UIView *first = cards[0], *second = cards[1], *third = cards[2];
        check([[(UILabel *)[first viewWithTag:1] text] isEqual:@"客厅"] && [[(UILabel *)[first viewWithTag:2] text] isEqual:@"22.5°"], @"valid home entry survives invalid neighbors");
        check([[(UILabel *)[first viewWithTag:3] text] isEqual:@"54%"], @"valid humidity is preserved");
        check([[(UILabel *)[second viewWithTag:1] text] isEqual:@"--"] && [[(UILabel *)[second viewWithTag:2] text] isEqual:@"--"] && [[(UILabel *)[second viewWithTag:3] text] isEqual:@"--"], @"malformed home fields are safe strings");
        check(third.hidden && !first.hidden && !second.hidden, @"invalid rows do not create visible empty cards");
        check([clock->_homeUpdatedLabel.text isEqual:@"等待数据"], @"invalid update time has a usable placeholder");
        for (id invalid in @[[NSNull null], @{}, @[], @"nan", @"12bad"]) {
            check([[clock formatTemperature:invalid] isEqual:@"--"], @"invalid temperature does not display fake data");
            check([[clock formatHumidity:invalid] isEqual:@"--%"], @"invalid humidity does not display fake data");
        }
        check([[clock formatTemperature:@"-2.3"] isEqual:@"-2.3°"], @"numeric string temperature remains supported");
        check([[clock formatHomeUpdated:(id)[NSNull null]] isEqual:@"等待数据"], @"invalid timestamp cannot crash formatter");
        for (NSString *json in @[@"[]", @"{}", @"{\"id\":null,\"src\":null,\"title\":[]}", @"{\"src\":3}"]) {
            writeStatus(@"cast-state.json", json); [clock loadCastStatus];
            check(clock->_castSrc == nil && clock->_castLastId == nil, @"malformed cast status clears stale source");
        }
        writeStatus(@"cast-state.json", @"{\"src\":\"assets/video/test.mp4?token=fixture\",\"id\":\"fixture\",\"title\":null}");
        [clock loadCastStatus];
        check([clock->_castSrc isEqual:[IWAppPath stringByAppendingPathComponent:@"assets/video/test.mp4"]], @"valid relative Cast file is preserved");
        check([clock->_castLastId isEqual:@"fixture"] && [clock->_castTitle isEqual:@"投送视频"], @"Cast fields have typed fallbacks");
        writeStatus(@"cast-state.json", [@"{\"src\":\"" stringByAppendingFormat:@"%@\"}", [@"x" stringByPaddingToLength:65536 withString:@"x" startingAtIndex:0]]);
        [clock loadCastStatus];
        check(clock->_castSrc == nil, @"oversized local status cannot populate controls");
    } @catch (NSException *exception) {
        check(NO, [@"production status handling threw " stringByAppendingString:exception.name]);
    }
    printf("{\"checks\":%ld,\"failures\":%ld}\n", (long)checks, (long)failures);
    return failures ? 1 : 0;
}}
'''

CANCELLATION_HARNESS = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
/* Swipe, transforms, persistence, debug output, and pull animation are counted test doubles.
   These checks prove production-method routing, not actual UIKit drawing or action outcomes. */
#define SHARED_CANCEL_EXTRACTED __SHARED_CANCEL_EXTRACTED__
typedef NS_ENUM(NSInteger, IWEditTarget) { IWEditTargetNone, IWEditTargetBackground, IWEditTargetClock, IWEditTargetDate, IWEditTargetCalendar, IWEditTargetWeather };
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) { UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed };
static CGFloat IWEditDragGain(void) { return 1.25; }
@interface FixtureView : NSObject
@property(nonatomic) BOOL hidden;
@end
@implementation FixtureView
@end
@interface FixtureTouch : NSObject
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(id)view;
@end
@implementation FixtureTouch
- (CGPoint)locationInView:(id)view { (void)view; return self.point; }
@end
typedef FixtureTouch UITouch;
@interface UIEvent : NSObject @end
@implementation UIEvent @end
@interface UIPanGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) CGPoint translation;
@property(nonatomic) CGPoint point;
@property(nonatomic) NSUInteger touches;
- (CGPoint)translationInView:(id)view;
- (CGPoint)locationInView:(id)view;
- (NSUInteger)numberOfTouches;
@end
@implementation UIPanGestureRecognizer
- (CGPoint)translationInView:(id)view { (void)view; return self.translation; }
- (CGPoint)locationInView:(id)view { (void)view; return self.point; }
- (NSUInteger)numberOfTouches { return self.touches; }
@end
@class CancellationHarness;
@interface CancellationHarness : NSObject {
@public
    FixtureView *_videoOverlay, *_calendarPanel, *_weatherPanel;
    BOOL _editMode, _surfaceTouchActive, _surfaceGestureIgnored, _surfaceMultiTouchIgnored;
    BOOL _pullReady, _pullRefreshing, _panFallbackTracking;
    IWEditTarget _editTarget;
    CGPoint _surfaceStart;
    NSString *_surfaceIntent;
    CGFloat _editStartX, _editStartY, _clockOffsetX, _clockOffsetY, _dateOffsetX, _dateOffsetY;
    CGFloat _calendarOffsetX, _calendarOffsetY, _weatherOffsetX, _weatherOffsetY;
    CGFloat _backgroundX, _backgroundY, _backgroundZoom;
    CGFloat _editStartDistance;
    CFAbsoluteTime _lastMultiTouchAt;
    NSInteger _swipeCalls, _persistCalls, _writeCalls, _resetPullCalls, _transformCalls, _setPullCalls;
    NSInteger _missingSharedCancelCalls;
    CGPoint _lastSwipe;
}
@property(nonatomic,strong) id view;
- (void)surfaceTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)surfaceTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)resetSurfaceTouchState;
- (void)controllerWrapperCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)handleBackgroundPan:(UIPanGestureRecognizer *)recognizer;
- (BOOL)pointHitsView:(id)view rootPoint:(CGPoint)point;
- (BOOL)isControlPoint:(CGPoint)point;
- (BOOL)isSystemGestureEdgePoint:(CGPoint)point;
- (BOOL)recentSurfaceMultiTouch;
- (void)markSurfaceMultiTouchIgnored;
- (void)selectClockOrDateEditTargetAtPoint:(CGPoint)point;
- (void)updateSurfacePull:(CGPoint)translation;
- (void)setPullOffset:(CGFloat)value ready:(BOOL)ready;
- (void)handleSurfaceSwipe:(CGPoint)translation;
- (void)persistCurrentEditValues;
- (void)writeDebugState:(NSString *)context;
- (void)resetPullIndicator;
- (void)appendTouchDebug:(NSString *)text;
- (void)applyClockTransforms;
- (void)applyCalendarTransform;
- (void)applyWeatherTransform;
- (void)applyBackgroundTransform;
@end

@implementation CancellationHarness
__SURFACE_ENDED__
__SHARED_CANCEL__
__RESET_SURFACE__
__BACKGROUND_PAN__
__CONTROLLER_CANCEL__
- (BOOL)pointHitsView:(id)view rootPoint:(CGPoint)point { (void)view; (void)point; return NO; }
- (BOOL)isControlPoint:(CGPoint)point { (void)point; return NO; }
- (BOOL)isSystemGestureEdgePoint:(CGPoint)point { (void)point; return NO; }
- (BOOL)recentSurfaceMultiTouch { return _surfaceMultiTouchIgnored; }
- (void)markSurfaceMultiTouchIgnored { _surfaceMultiTouchIgnored = YES; _surfaceIntent = @"pinch"; _pullReady = NO; }
- (void)selectClockOrDateEditTargetAtPoint:(CGPoint)point { (void)point; }
- (void)updateSurfacePull:(CGPoint)translation { _pullReady = translation.y >= 96.0; }
- (void)setPullOffset:(CGFloat)value ready:(BOOL)ready { (void)value; (void)ready; _setPullCalls++; }
- (void)handleSurfaceSwipe:(CGPoint)translation { _swipeCalls++; _lastSwipe = translation; }
- (void)persistCurrentEditValues { _persistCalls++; }
- (void)writeDebugState:(NSString *)context { (void)context; _writeCalls++; }
- (void)resetPullIndicator { _resetPullCalls++; _pullReady = NO; _pullRefreshing = NO; _surfaceIntent = @""; }
- (void)appendTouchDebug:(NSString *)text { (void)text; }
- (void)applyClockTransforms { _transformCalls++; }
- (void)applyCalendarTransform { _transformCalls++; }
- (void)applyWeatherTransform { _transformCalls++; }
- (void)applyBackgroundTransform { _transformCalls++; }
@end

@interface SurfaceTouchWrapper : NSObject { @public CancellationHarness *_owner; }
- (void)surfaceWrapperCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
@end
@implementation SurfaceTouchWrapper
__SURFACE_CANCEL_WRAPPER__
@end

@interface RootSurfaceTouchWrapper : NSObject { @public CancellationHarness *_owner; }
- (void)rootSurfaceWrapperCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
@end
@implementation RootSurfaceTouchWrapper
__ROOT_SURFACE_CANCEL_WRAPPER__
@end

static NSInteger checks = 0, failures = 0;
static void check(BOOL ok, NSString *name) {
    checks++;
    if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", name.UTF8String); }
}
static CancellationHarness *freshHarness(BOOL editing, CGPoint start, BOOL activeRefresh) {
    CancellationHarness *h = [CancellationHarness new];
    h.view = [NSObject new];
    h->_editMode = editing;
    h->_editTarget = editing ? IWEditTargetClock : IWEditTargetNone;
    h->_clockOffsetX = h->_editStartX = 15.0;
    h->_clockOffsetY = h->_editStartY = 7.0;
    h->_dateOffsetX = h->_editStartX;
    h->_surfaceStart = start;
    h->_surfaceTouchActive = YES;
    h->_surfaceGestureIgnored = NO;
    h->_surfaceMultiTouchIgnored = NO;
    h->_surfaceIntent = @"vertical";
    h->_pullReady = YES;
    h->_pullRefreshing = activeRefresh;
    h->_panFallbackTracking = YES;
    return h;
}
static NSSet *touchesAt(CGPoint p) {
    FixtureTouch *touch = [FixtureTouch new]; touch.point = p;
    return [NSSet setWithObject:touch];
}
static void assertCancelled(CancellationHarness *h, NSString *name) {
    check(h->_swipeCalls == 0 && h->_persistCalls == 0 && h->_transformCalls == 0,
          [name stringByAppendingString:@" has no swipe, edit persistence, or transform action"]);
    check(h->_missingSharedCancelCalls == 0,
          [name stringByAppendingString:@" does not fall through to a missing shared cancellation implementation"]);
    check(!h->_panFallbackTracking && !h->_surfaceTouchActive && !h->_surfaceGestureIgnored &&
          !h->_surfaceMultiTouchIgnored && !h->_pullReady && h->_surfaceIntent.length == 0,
          [name stringByAppendingString:@" clears touch, pull, and pan fallback state"]);
    check(h->_resetPullCalls == (h->_pullRefreshing ? 0 : 1),
          [name stringByAppendingString:@" resets pull indicator only when refresh is inactive"]);
}
static void testRawCancelledWrappers(void) {
    CGPoint start = CGPointMake(300.0, 320.0);
    CancellationHarness *h = freshHarness(NO, start, NO);
    SurfaceTouchWrapper *surface = [SurfaceTouchWrapper new]; surface->_owner = h;
    [surface surfaceWrapperCancelled:touchesAt(start) withEvent:nil];
    assertCancelled(h, @"IWSurfaceView cancelled tap");

    CGPoint end = CGPointMake(start.x, start.y - 120.0);
    h = freshHarness(NO, start, YES); h->_pullReady = YES;
    surface->_owner = h;
    [surface surfaceWrapperCancelled:touchesAt(end) withEvent:nil];
    assertCancelled(h, @"IWSurfaceView cancelled ready pull");
    check(h->_pullRefreshing && h->_resetPullCalls == 0, @"cancel preserves an in-flight pull refresh");

    h = freshHarness(NO, start, NO);
    RootSurfaceTouchWrapper *rootSurface = [RootSurfaceTouchWrapper new]; rootSurface->_owner = h;
    [rootSurface rootSurfaceWrapperCancelled:touchesAt(CGPointMake(start.x, start.y - 130.0)) withEvent:nil];
    assertCancelled(h, @"IWRootSurfaceView cancelled upward swipe");

    h = freshHarness(NO, start, NO); rootSurface->_owner = h;
    [rootSurface rootSurfaceWrapperCancelled:touchesAt(CGPointMake(start.x + 130.0, start.y)) withEvent:nil];
    assertCancelled(h, @"IWRootSurfaceView cancelled horizontal swipe");

    h = freshHarness(NO, start, NO);
    [h controllerWrapperCancelled:touchesAt(start) withEvent:nil];
    assertCancelled(h, @"IWRootViewController cancelled tap");

    h = freshHarness(YES, start, NO); h->_panFallbackTracking = YES;
    [h controllerWrapperCancelled:touchesAt(CGPointMake(start.x + 16.0, start.y)) withEvent:nil];
    assertCancelled(h, @"IWRootViewController cancelled edit touch");
}
static void testEndedControlsStillWork(void) {
    CGPoint start = CGPointMake(300.0, 320.0);
    CancellationHarness *h = freshHarness(NO, start, NO);
    [h surfaceTouchesEnded:touchesAt(start) withEvent:nil];
    check(h->_swipeCalls == 1 && h->_persistCalls == 0, @"normal raw-touch Ended still dispatches its surface action");
    h = freshHarness(YES, start, NO);
    [h surfaceTouchesEnded:touchesAt(CGPointMake(start.x + 16.0, start.y)) withEvent:nil];
    check(h->_persistCalls == 1 && h->_swipeCalls == 0, @"normal edit-touch Ended still persists the accepted edit");
}
static void testPanTerminal(UIGestureRecognizerState terminal, BOOL editing, NSString *name) {
    CGPoint start = CGPointMake(300.0, 320.0);
    CancellationHarness *h = freshHarness(editing, start, NO);
    h->_surfaceTouchActive = NO; h->_panFallbackTracking = NO;
    UIPanGestureRecognizer *pan = [UIPanGestureRecognizer new];
    pan.touches = 1; pan.point = start;
    pan.state = UIGestureRecognizerStateBegan; pan.translation = CGPointZero;
    [h handleBackgroundPan:pan];
    pan.state = UIGestureRecognizerStateChanged;
    pan.translation = editing ? CGPointMake(12.0, 0.0) : CGPointMake(0.0, 120.0);
    [h handleBackgroundPan:pan];
    NSInteger transformsBeforeTerminal = h->_transformCalls;
    NSInteger persistenceBeforeTerminal = h->_persistCalls;
    pan.state = terminal;
    [h handleBackgroundPan:pan];
    if (terminal == UIGestureRecognizerStateEnded) {
        check(editing ? h->_persistCalls == persistenceBeforeTerminal + 1 : h->_swipeCalls == 1,
              [name stringByAppendingString:@" normal Ended action remains active"]);
    } else {
        check(h->_swipeCalls == 0 && h->_persistCalls == persistenceBeforeTerminal,
              [name stringByAppendingString:@" cancellation does not swipe or persist"]);
        check(h->_transformCalls == transformsBeforeTerminal,
              [name stringByAppendingString:@" cancellation does not apply another transform"]);
        check(!h->_panFallbackTracking && !h->_surfaceTouchActive && !h->_pullReady && h->_surfaceIntent.length == 0,
              [name stringByAppendingString:@" cancellation resets pan and surface state"]);
    }
}
int main(void) { @autoreleasepool {
    testRawCancelledWrappers();
    testEndedControlsStillWork();
    testPanTerminal(UIGestureRecognizerStateCancelled, NO, @"Background pan Cancelled");
    testPanTerminal(UIGestureRecognizerStateFailed, NO, @"Background pan Failed");
    testPanTerminal(UIGestureRecognizerStateCancelled, YES, @"Edit background pan Cancelled");
    testPanTerminal(UIGestureRecognizerStateFailed, YES, @"Edit background pan Failed");
    testPanTerminal(UIGestureRecognizerStateEnded, NO, @"Background pan Ended");
    testPanTerminal(UIGestureRecognizerStateEnded, YES, @"Edit background pan Ended");
    printf("{\"touchCancellationChecks\":%ld,\"touchCancellationFailures\":%ld,\"sharedCancelMethodExtracted\":%d}\n",
           (long)checks, (long)failures, (int)SHARED_CANCEL_EXTRACTED);
    return failures ? 1 : 0;
}}
'''

REDUCED_MOTION_CALENDAR_HARNESS = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

static BOOL TestReduceMotion;
BOOL UIAccessibilityIsReduceMotionEnabled(void) { return TestReduceMotion; }

__CALENDAR_HELPER__
__TRANSITION_ENUM__
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) {
    UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan,
    UIGestureRecognizerStateChanged, UIGestureRecognizerStateEnded,
    UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed
};
typedef NS_ENUM(NSInteger, UISwipeGestureRecognizerDirection) {
    UISwipeGestureRecognizerDirectionUp = 1 << 0,
    UISwipeGestureRecognizerDirectionDown = 1 << 1,
    UISwipeGestureRecognizerDirectionLeft = 1 << 2,
    UISwipeGestureRecognizerDirectionRight = 1 << 3
};
typedef NSUInteger UIViewAnimationOptions;
enum {
    UIViewAnimationOptionCurveEaseOut = 1 << 0,
    UIViewAnimationOptionBeginFromCurrentState = 1 << 1,
    UIViewAnimationOptionTransitionCrossDissolve = 1 << 2
};
@class UIView;
static NSMutableArray *PendingCompletions;
static NSMutableArray *AnimationDurations;
static NSMutableArray *TransitionDurations;
static NSMutableArray *CreatedSnapshots;
static NSInteger SnapshotCalls;
static NSInteger CalendarUpdates;

@interface UISwipeGestureRecognizer : NSObject
@property(nonatomic) UISwipeGestureRecognizerDirection direction;
@property(nonatomic) UIGestureRecognizerState state;
@end
@implementation UISwipeGestureRecognizer
@end

@interface UIView : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL userInteractionEnabled;
@property(nonatomic) NSInteger tag;
@property(nonatomic,strong) NSMutableArray *subviews;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic) BOOL removed;
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)afterUpdates;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (void)addSubview:(UIView *)view;
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling;
- (void)removeFromSuperview;
- (UIView *)viewWithTag:(NSInteger)tag;
- (void)layoutIfNeeded;
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL))completion;
+ (void)transitionWithView:(UIView *)view duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL))completion;
@end
@implementation UIView
- (instancetype)init {
    self=[super init];
    if(self){_alpha=1.0;_transform=CGAffineTransformIdentity;_userInteractionEnabled=YES;_subviews=[NSMutableArray array];}
    return self;
}
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)afterUpdates {
    (void)afterUpdates; SnapshotCalls++;
    UIView *snapshot=[UIView new]; snapshot.frame=self.frame; snapshot.bounds=self.bounds;
    [CreatedSnapshots addObject:snapshot]; return snapshot;
}
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { (void)view; return rect; }
- (void)addSubview:(UIView *)view {
    if(!view)return; [view removeFromSuperview]; view.superview=self; [_subviews addObject:view];
}
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling {
    if(!view)return; [view removeFromSuperview]; view.superview=self;
    NSUInteger index=[_subviews indexOfObjectIdenticalTo:sibling];
    if(index==NSNotFound)[_subviews addObject:view];else[_subviews insertObject:view atIndex:index+1];
}
- (void)removeFromSuperview {
    if(self.superview){[self.superview.subviews removeObjectIdenticalTo:self];self.superview=nil;}
    self.removed=YES;
}
- (UIView *)viewWithTag:(NSInteger)tag {
    if(self.tag==tag)return self;
    for(UIView *child in self.subviews){UIView *found=[child viewWithTag:tag];if(found)return found;}
    return nil;
}
- (void)layoutIfNeeded {}
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL))completion {
    (void)delay;(void)options;[AnimationDurations addObject:@(duration)];
    if(animations)animations();
    if(completion)[PendingCompletions addObject:[^{completion(YES);} copy]];
}
+ (void)transitionWithView:(UIView *)view duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL))completion {
    (void)view;(void)options;[TransitionDurations addObject:@(duration)];
    if(animations)animations();
    if(completion)[PendingCompletions addObject:[^{completion(YES);} copy]];
}
@end

@interface CalendarMotionHarness : NSObject {
@public
    UIView *_calendarPanel;
    BOOL _editMode, _calendarMonthTransitioning;
    NSInteger _calendarDisplayYear, _calendarDisplayMonth, _calendarSelectedDay, _dateLanguage;
    NSString *_calendarRenderedDayKey;
    IWWallpaperTransitionStyle _wallpaperTransitionStyle;
}
@property(nonatomic,strong) UIView *view;
- (void)handleCalendarMonthSwipe:(UISwipeGestureRecognizer *)recognizer;
- (void)returnCalendarToToday:(UISwipeGestureRecognizer *)recognizer;
- (void)updateCalendarPanel;
- (void)appendTouchDebug:(NSString *)text;
@end
@implementation CalendarMotionHarness
- (void)updateCalendarPanel { CalendarUpdates++; }
- (void)appendTouchDebug:(NSString *)text { (void)text; }
__PRODUCTION_METHODS__
@end

static NSInteger checks=0, failures=0;
static void check(BOOL ok, NSString *name) {
    checks++;
    if(!ok){failures++;fprintf(stderr,"FAIL: %s\n",name.UTF8String);}
}
static void resetMotionFixtures(void) {
    PendingCompletions=[NSMutableArray array];AnimationDurations=[NSMutableArray array];
    TransitionDurations=[NSMutableArray array];CreatedSnapshots=[NSMutableArray array];
    SnapshotCalls=0;CalendarUpdates=0;
}
static void finishMotionAnimations(void) {
    NSArray *pending=[PendingCompletions copy];[PendingCompletions removeAllObjects];
    for(void(^completion)(void) in pending)completion();
}
static BOOL closeValue(CGFloat a,CGFloat b) { return fabs(a-b)<0.001; }
static CalendarMotionHarness *newCalendarHarness(NSInteger year,NSInteger month) {
    CalendarMotionHarness *h=[CalendarMotionHarness new];
    h->_calendarPanel=[UIView new];h->_calendarPanel.bounds=CGRectMake(0,0,252,200);
    h->_calendarPanel.frame=CGRectMake(50,70,252,200);h->_calendarPanel.alpha=1.0;
    h.view=[UIView new];h.view.bounds=CGRectMake(0,0,1024,768);
    h->_calendarDisplayYear=year;h->_calendarDisplayMonth=month;h->_calendarSelectedDay=18;
    h->_calendarRenderedDayKey=@"previous-render";h->_wallpaperTransitionStyle=IWWallpaperTransitionStyleSlide;
    [h.view addSubview:h->_calendarPanel];return h;
}
static void testCalendarMonthSwipe(BOOL reduceMotion,NSInteger year,NSInteger month,
                                   UISwipeGestureRecognizerDirection direction,
                                   NSInteger expectedYear,NSInteger expectedMonth,NSString *name) {
    resetMotionFixtures();TestReduceMotion=reduceMotion;
    CalendarMotionHarness *h=newCalendarHarness(year,month);
    UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.direction=direction;
    [h handleCalendarMonthSwipe:swipe];
    check(h->_calendarDisplayYear==expectedYear&&h->_calendarDisplayMonth==expectedMonth,
          [name stringByAppendingString:@" uses Gregorian month/year rollover"]);
    check(h->_calendarSelectedDay==0&&h->_calendarRenderedDayKey==nil&&CalendarUpdates==1,
          [name stringByAppendingString:@" clears selected day and refreshes panel"]);
    if(reduceMotion){
        check(SnapshotCalls==0&&AnimationDurations.count==0&&TransitionDurations.count==0,
              [name stringByAppendingString:@" skips snapshots and spatial animations"]);
        check(!h->_calendarMonthTransitioning&&closeValue(h->_calendarPanel.alpha,1.0),
              [name stringByAppendingString:@" leaves panel visible and transition unlocked"]);
        check(CreatedSnapshots.count==0, [name stringByAppendingString:@" allocates no transition snapshots"]);
    }else{
        check(SnapshotCalls==2&&AnimationDurations.count==1&&TransitionDurations.count==0,
              [name stringByAppendingString:@" retains the normal snapshot animation"]);
        check(h->_calendarMonthTransitioning&&closeValue(h->_calendarPanel.alpha,0.0),
              [name stringByAppendingString:@" locks transition until animation completion"]);
        check(closeValue([AnimationDurations[0] doubleValue],0.26),
              [name stringByAppendingString:@" preserves slide timing"]);
        finishMotionAnimations();
        check(!h->_calendarMonthTransitioning&&closeValue(h->_calendarPanel.alpha,1.0),
              [name stringByAppendingString:@" completion unlocks and restores panel"]);
        check(CreatedSnapshots.count==2&&[(UIView *)CreatedSnapshots[0] removed]&&[(UIView *)CreatedSnapshots[1] removed],
              [name stringByAppendingString:@" completion removes both snapshots"]);
    }
}
static void testCalendarSwipeGuards(void) {
    for(NSInteger guard=0;guard<2;guard++){
        resetMotionFixtures();TestReduceMotion=YES;
        CalendarMotionHarness *h=newCalendarHarness(2026,12);
        if(guard==0)h->_editMode=YES;else h->_calendarMonthTransitioning=YES;
        UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.direction=UISwipeGestureRecognizerDirectionLeft;
        [h handleCalendarMonthSwipe:swipe];
        check(h->_calendarDisplayYear==2026&&h->_calendarDisplayMonth==12&&h->_calendarSelectedDay==18&&CalendarUpdates==0,
              guard==0?@"edit mode blocks month swipe":@"in-flight transition blocks month swipe");
        check(SnapshotCalls==0&&AnimationDurations.count==0&&TransitionDurations.count==0,
              @"guarded month swipe has no snapshots or animations");
    }
}
static void testReturnToToday(BOOL reduceMotion,NSString *name) {
    resetMotionFixtures();TestReduceMotion=reduceMotion;
    NSCalendar *calendar=IWDisplayCalendar();
    NSDateComponents *today=[calendar components:(NSCalendarUnitYear|NSCalendarUnitMonth) fromDate:[NSDate date]];
    NSInteger year=today.year,month=today.month==1?12:today.month-1;
    if(today.month==1)year--;
    CalendarMotionHarness *h=newCalendarHarness(year,month);
    UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.state=UIGestureRecognizerStateEnded;
    [h returnCalendarToToday:swipe];
    check(h->_calendarDisplayYear==0&&h->_calendarDisplayMonth==0&&h->_calendarSelectedDay==0&&CalendarUpdates==1,
          [name stringByAppendingString:@" resets displayed month and selected day"]);
    check(TransitionDurations.count==1&&closeValue([TransitionDurations[0] doubleValue],0.26)&&AnimationDurations.count==0,
          [name stringByAppendingString:@" retains the safe cross-dissolve"]);
    check(h->_calendarMonthTransitioning,[name stringByAppendingString:@" holds transition lock through dissolve"]);
    finishMotionAnimations();
    check(!h->_calendarMonthTransitioning,[name stringByAppendingString:@" unlocks after dissolve completion"]);
}
static void testReturnToTodayWithinCurrentMonth(void) {
    NSDateComponents *today=[IWDisplayCalendar() components:(NSCalendarUnitYear|NSCalendarUnitMonth) fromDate:[NSDate date]];
    for(NSInteger scenario=0;scenario<3;scenario++){
        resetMotionFixtures();TestReduceMotion=YES;
        CalendarMotionHarness *h=newCalendarHarness(scenario==2?0:today.year,scenario==2?0:today.month);
        h->_calendarSelectedDay=scenario==1?0:18;
        UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.state=UIGestureRecognizerStateEnded;
        [h returnCalendarToToday:swipe];
        check(h->_calendarDisplayYear==0&&h->_calendarDisplayMonth==0&&h->_calendarSelectedDay==0&&CalendarUpdates==1,
              @"current-month return clears explicit browsing and selected day for live today tracking");
        check(TransitionDurations.count==1&&h->_calendarMonthTransitioning,
              @"current-month return retains safe dissolve when state changes");
        finishMotionAnimations();
        check(!h->_calendarMonthTransitioning&&CreatedSnapshots.count==0,
              @"current-month return cleans up without spatial snapshots");
    }
    resetMotionFixtures();CalendarMotionHarness *h=newCalendarHarness(0,0);h->_calendarSelectedDay=0;
    UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.state=UIGestureRecognizerStateEnded;
    [h returnCalendarToToday:swipe];
    check(CalendarUpdates==0&&TransitionDurations.count==0&&!h->_calendarMonthTransitioning,
          @"already tracking today without selection remains a no-op");
}
static void testTodayGuards(void) {
    resetMotionFixtures();TestReduceMotion=YES;
    CalendarMotionHarness *h=newCalendarHarness(2026,12);
    UISwipeGestureRecognizer *swipe=[UISwipeGestureRecognizer new];swipe.state=UIGestureRecognizerStateChanged;
    [h returnCalendarToToday:swipe];
    check(h->_calendarDisplayYear==2026&&h->_calendarDisplayMonth==12&&CalendarUpdates==0&&TransitionDurations.count==0,
          @"return-to-today requires ended recognizer");
}
int main(void) { @autoreleasepool {
    testCalendarMonthSwipe(YES,2026,12,UISwipeGestureRecognizerDirectionLeft,2027,1,@"Reduce Motion December to January");
    testCalendarMonthSwipe(NO,2027,1,UISwipeGestureRecognizerDirectionRight,2026,12,@"Normal January to December");
    testCalendarSwipeGuards();
    testReturnToToday(YES,@"Reduce Motion return to today");
    testReturnToToday(NO,@"Normal return to today");
    testTodayGuards();
    testReturnToTodayWithinCurrentMonth();
    printf("{\"reducedMotionCalendarChecks\":%ld,\"reducedMotionCalendarFailures\":%ld}\n",(long)checks,(long)failures);
    return failures?1:0;
}}
'''

with tempfile.TemporaryDirectory(prefix="wizard-native-regressions-") as directory:
    output = Path(directory)
    harness = output / "regressions.m"
    panel_cache_methods = {
        "calendarTouchDown": method(r"calendarTouchDown:\(UIControl \*\)control forEvent:\(UIEvent \*\)event"),
        "calendarTouchUp": method(r"calendarTouchUp:\(UIControl \*\)control forEvent:\(UIEvent \*\)event"),
        "weatherTouchDown": method(r"weatherTouchDown:\(UIControl \*\)control forEvent:\(UIEvent \*\)event"),
        "weatherTouchUp": method(r"weatherTouchUp:\(UIControl \*\)control forEvent:\(UIEvent \*\)event"),
    }
    methods = [method("tick"), method("loadWallpapers"), method(r"canDeleteWallpaperAtIndex:\(NSInteger\)index"), method("cancelEditMode"), method("updateBorderControlVisibility"), method("updateOpacityControlVisibility"), method(r"handleEditControlsPan:\(UIPanGestureRecognizer \*\)recognizer"), method(r"moveEditControlsToOrigin:\(CGPoint\)origin persist:\(BOOL\)persist"), method(r"selectClockOrDateEditTargetAtPoint:\(CGPoint\)p")]
    methods += [panel_cache_methods["calendarTouchUp"], panel_cache_methods["weatherTouchUp"]]
    methods += [method(r"accessibilityMoveEditControlsLeft:\(UIAccessibilityCustomAction \*\)action"), method(r"accessibilityMoveEditControlsRight:\(UIAccessibilityCustomAction \*\)action"), method(r"accessibilityMoveEditControlsUp:\(UIAccessibilityCustomAction \*\)action"), method(r"accessibilityMoveEditControlsDown:\(UIAccessibilityCustomAction \*\)action")]
    for name in [r"jsonAtPath:\(NSString \*\)path", r"resetHomePlaceholders:\(NSString \*\)updatedText", "loadHomeStatus", r"formatTemperature:\(id\)value", r"formatHumidity:\(id\)value", r"formatHomeUpdated:\(NSString \*\)value", "loadCastStatus"]:
        methods.append(method(name))
    for name in ["removeRemoteVideoObservers", "remoteVideoFinished:"]:
        if name.endswith(":"):
            match = re.search(r"^- \(void\)remoteVideoFinished:[^\n]+\{", text, re.M)
            if match:
                end = re.search(r"^[-+] \(", text[match.end():], re.M)
                methods.append(text[match.start():match.end() + end.start() if end else len(text)])
            else:
                methods.append("- (void)remoteVideoFinished:(NSNotification *)notification {}")
        else:
            methods.append(method(name) if "- (void)" + name + " {" in text else "- (void)" + name + " {}")
    target_callers = [
        method(r"surfaceTouchesBegan:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event"),
        method(r"handleBackgroundPan:\(UIPanGestureRecognizer \*\)recognizer"),
    ]
    target_selection_wired = all("[self selectClockOrDateEditTargetAtPoint:p]" in body for body in target_callers)
    toolbar = method("buildEditToolbar")
    action_selectors = ["accessibilityMoveEditControls" + direction + ":" for direction in ("Left", "Right", "Up", "Down")]
    accessibility_actions_wired = "accessibilityCustomActions" in toolbar and all(selector in toolbar for selector in action_selectors)
    harness.write_text(HARNESS.replace("__CALENDAR__", calendar_helper()).replace("__WEATHER_CACHE__", weather_cache_helper()).replace("__TARGET_SELECTION_WIRED__", "YES" if target_selection_wired else "NO").replace("__ACCESSIBILITY_ACTIONS_WIRED__", "YES" if accessibility_actions_wired else "NO").replace("__METHODS__", "\n".join(methods)))
    binary = output / "regressions"
    compile_argv = ["xcrun", "clang", "-fobjc-arc", "-Werror", "-Wno-deprecated-declarations", "-framework", "Foundation", "-I", str(SOURCE), str(harness), "-o", str(binary)]
    proof_root = args.cancellation_proof_dir.resolve() if args.cancellation_proof_dir else None
    base_proof = None
    if proof_root:
        proof_root.mkdir(parents=True, exist_ok=True)
        base_proof = proof_root / "base-suite"
        if base_proof.exists() and any(base_proof.iterdir()):
            raise RuntimeError("Refusing to overwrite calendar/native base-suite proof artifacts")
        base_proof.mkdir(exist_ok=True)
        (base_proof / "regressions.m").write_text(harness.read_text())
        (base_proof / "method-binding.json").write_text(json.dumps({
            "source_path": str(args.source.resolve()),
            "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
            "panel_touch_method_sha256": {name: hashlib.sha256(body.encode()).hexdigest()
                                          for name, body in panel_cache_methods.items()},
            "executed_production_methods": ["calendarTouchUp", "weatherTouchUp"],
            "inspected_not_executed_methods": ["calendarTouchDown", "weatherTouchDown"],
            "cache_fixture": "The harness seeds rasterizationScale=1.0, the value assigned by inspected Down handlers; it does not claim actual image rasterization."
        }, indent=2, sort_keys=True) + "\n")
    compile_result = subprocess.run(compile_argv, capture_output=True, text=True)
    if base_proof:
        (base_proof / "compile.json").write_text(json.dumps({
            "argv": compile_argv, "returncode": compile_result.returncode,
            "stdout": compile_result.stdout, "stderr": compile_result.stderr
        }, indent=2) + "\n")
    if compile_result.returncode:
        print(compile_result.stdout, end="")
        print(compile_result.stderr, end="")
        raise SystemExit(compile_result.returncode)
    if base_proof:
        (base_proof / "regressions").write_bytes(binary.read_bytes())
    command = [str(binary), directory]
    if args.catalog:
        command += [str(args.catalog.resolve()), str(args.expected_count)]
    result = subprocess.run(command, capture_output=True, text=True)
    if base_proof:
        (base_proof / "run.stdout").write_text(result.stdout)
        (base_proof / "run.stderr").write_text(result.stderr)
        (base_proof / "run-result.json").write_text(json.dumps({"argv": command, "returncode": result.returncode}, indent=2) + "\n")
    print(result.stdout, end="")
    print(result.stderr, end="")
    cancellation_methods = {
        "surfaceTouchesEnded": method(r"surfaceTouchesEnded:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event"),
        "resetSurfaceTouchState": method("resetSurfaceTouchState"),
        "handleBackgroundPan": method(r"handleBackgroundPan:\(UIPanGestureRecognizer \*\)recognizer"),
        "IWSurfaceView.touchesCancelled": class_method("IWSurfaceView", r"touchesCancelled:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event"),
        "IWRootSurfaceView.touchesCancelled": class_method("IWRootSurfaceView", r"touchesCancelled:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event"),
        "IWRootViewController.touchesCancelled": class_method("IWRootViewController", r"touchesCancelled:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event"),
    }
    try:
        cancellation_methods["surfaceTouchesCancelled"] = method(r"surfaceTouchesCancelled:\(NSSet \*\)touches withEvent:\(UIEvent \*\)event")
        shared_cancel_extracted = True
    except RuntimeError:
        shared_cancel_extracted = False
        cancellation_methods["surfaceTouchesCancelled"] = r'''- (void)surfaceTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)touches; (void)event;
    _missingSharedCancelCalls++;
}'''

    def alias_cancel_wrapper(class_name, alias):
        body = cancellation_methods[class_name + ".touchesCancelled"]
        body, count = re.subn(r"^- \(void\)touchesCancelled:", "- (void)" + alias, body, count=1, flags=re.M)
        if count != 1:
            raise RuntimeError("Could not alias cancellation selector for " + class_name)
        return body

    controller_wrapper, controller_alias_count = re.subn(
        r"^- \(void\)touchesCancelled:", "- (void)controllerWrapperCancelled:",
        cancellation_methods["IWRootViewController.touchesCancelled"], count=1, flags=re.M)
    if controller_alias_count != 1:
        raise RuntimeError("Could not alias root-controller cancellation selector")
    cancel_harness = (CANCELLATION_HARNESS
        .replace("__SHARED_CANCEL_EXTRACTED__", "1" if shared_cancel_extracted else "0")
        .replace("__SURFACE_ENDED__", cancellation_methods["surfaceTouchesEnded"])
        .replace("__SHARED_CANCEL__", cancellation_methods["surfaceTouchesCancelled"])
        .replace("__RESET_SURFACE__", cancellation_methods["resetSurfaceTouchState"])
        .replace("__BACKGROUND_PAN__", cancellation_methods["handleBackgroundPan"])
        .replace("__CONTROLLER_CANCEL__", controller_wrapper)
        .replace("__SURFACE_CANCEL_WRAPPER__", alias_cancel_wrapper("IWSurfaceView", "surfaceWrapperCancelled:"))
        .replace("__ROOT_SURFACE_CANCEL_WRAPPER__", alias_cancel_wrapper("IWRootSurfaceView", "rootSurfaceWrapperCancelled:")))
    proof_root = args.cancellation_proof_dir
    if proof_root:
        proof_root = proof_root.resolve()
        proof_root.mkdir(parents=True, exist_ok=True)
        proof_files = ["touch-cancellation-regressions.m", "touch-cancellation-regressions", "compile.json",
                       "input-binding.json", "base-suite.stdout", "base-suite.stderr",
                       "run.stdout", "run.stderr", "run-result.json"]
        existing = [name for name in proof_files if (proof_root / name).exists()]
        if existing:
            raise RuntimeError("Refusing to overwrite cancellation proof artifacts: " + ", ".join(existing))
        cancel_dir = proof_root
        (cancel_dir / "base-suite.stdout").write_text(result.stdout)
        (cancel_dir / "base-suite.stderr").write_text(result.stderr)
    else:
        cancel_dir = output / "cancellation"
        cancel_dir.mkdir()
    cancel_source = cancel_dir / "touch-cancellation-regressions.m"
    cancel_binary = cancel_dir / "touch-cancellation-regressions"
    cancel_source.write_text(cancel_harness)
    compile_argv = ["xcrun", "clang", "-fobjc-arc", "-Werror", "-Wno-deprecated-declarations",
                    "-framework", "Foundation", "-framework", "CoreGraphics", str(cancel_source), "-o", str(cancel_binary)]
    compile_result = subprocess.run(compile_argv, capture_output=True, text=True)
    if proof_root:
        (cancel_dir / "compile.json").write_text(json.dumps({
            "argv": compile_argv, "returncode": compile_result.returncode,
            "stdout": compile_result.stdout, "stderr": compile_result.stderr
        }, indent=2) + "\n")
        (cancel_dir / "input-binding.json").write_text(json.dumps({
            "source_path": str(args.source.resolve()),
            "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
            "test_script_path": str(Path(__file__).resolve()),
            "test_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "extracted_method_sha256": {name: hashlib.sha256(body.encode()).hexdigest()
                                        for name, body in cancellation_methods.items()},
            "shared_cancel_method_extracted_from_source": shared_cancel_extracted,
            "scope": "Source-extracted wrappers, surface-end, reset-state, and background-pan methods execute against counted Swipe/apply/persist/debug/pull test doubles. This verifies production-method routing, not actual UIKit drawing or action outcomes. No device acceptance."
        }, indent=2, sort_keys=True) + "\n")
    if compile_result.returncode:
        print(compile_result.stdout, end="")
        print(compile_result.stderr, end="")
        if proof_root:
            (cancel_dir / "run-result.json").write_text(json.dumps({"returncode": compile_result.returncode, "stage": "compile"}) + "\n")
        raise SystemExit(compile_result.returncode)
    cancellation_result = subprocess.run([str(cancel_binary)], capture_output=True, text=True)
    if proof_root:
        (cancel_dir / "run.stdout").write_text(cancellation_result.stdout)
        (cancel_dir / "run.stderr").write_text(cancellation_result.stderr)
        (cancel_dir / "run-result.json").write_text(json.dumps({
            "returncode": cancellation_result.returncode, "stage": "execute",
            "shared_cancel_method_extracted_from_source": shared_cancel_extracted
        }, indent=2) + "\n")
    print(cancellation_result.stdout, end="")
    print(cancellation_result.stderr, end="")
    existing_suite_exit = result.returncode or cancellation_result.returncode

motion_proof_dir = args.reduced_motion_proof_dir.resolve() if args.reduced_motion_proof_dir else None
if motion_proof_dir:
    motion_proof_dir.mkdir(parents=True, exist_ok=True)
    motion_files = ["calendar-reduced-motion-regressions.m", "calendar-reduced-motion-regressions",
                    "compile.json", "input-binding.json", "base-suite.stdout", "base-suite.stderr",
                    "cancellation-suite.stdout", "cancellation-suite.stderr", "suite-results.json",
                    "run.stdout", "run.stderr", "run-result.json"]
    existing = [name for name in motion_files if (motion_proof_dir / name).exists()]
    if existing:
        raise RuntimeError("Refusing to overwrite reduced-motion proof artifacts: " + ", ".join(existing))
    (motion_proof_dir / "base-suite.stdout").write_text(result.stdout)
    (motion_proof_dir / "base-suite.stderr").write_text(result.stderr)
    (motion_proof_dir / "cancellation-suite.stdout").write_text(cancellation_result.stdout)
    (motion_proof_dir / "cancellation-suite.stderr").write_text(cancellation_result.stderr)
    (motion_proof_dir / "suite-results.json").write_text(json.dumps({
        "base": {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr},
        "touch_cancellation": {
            "returncode": cancellation_result.returncode,
            "shared_cancel_method_extracted_from_source": shared_cancel_extracted,
            "stdout": cancellation_result.stdout,
            "stderr": cancellation_result.stderr
        }
    }, indent=2, sort_keys=True) + "\n")

calendar_methods = {
    "handleCalendarMonthSwipe": class_method("IWRootViewController", r"handleCalendarMonthSwipe:\(UISwipeGestureRecognizer \*\)recognizer"),
    "returnCalendarToToday": class_method("IWRootViewController", r"returnCalendarToToday:\(UISwipeGestureRecognizer \*\)recognizer"),
}
transition_enum_start = text.find("typedef NS_ENUM(NSInteger, IWWallpaperTransitionStyle)")
if transition_enum_start < 0:
    raise RuntimeError("Production wallpaper transition enum missing")
transition_enum_end = text.index("\n};", transition_enum_start) + 3
transition_enum = text[transition_enum_start:transition_enum_end]
display_calendar = calendar_helper()
if "return [NSCalendar currentCalendar]" in display_calendar:
    raise RuntimeError("Production Gregorian display calendar helper missing")
motion_harness_text = (REDUCED_MOTION_CALENDAR_HARNESS
    .replace("__CALENDAR_HELPER__", display_calendar)
    .replace("__TRANSITION_ENUM__", transition_enum)
    .replace("__PRODUCTION_METHODS__", "\n".join(calendar_methods.values())))
with tempfile.TemporaryDirectory(prefix="wizard-reduced-motion-calendar-") as directory:
    output = Path(directory)
    harness_path = output / "calendar-reduced-motion-regressions.m"
    binary_path = output / "calendar-reduced-motion-regressions"
    harness_path.write_text(motion_harness_text)
    compile_argv = ["xcrun", "clang", "-fobjc-arc", "-Werror", "-Wno-deprecated-declarations",
                    "-framework", "Foundation", "-framework", "CoreGraphics", str(harness_path), "-o", str(binary_path)]
    compile_result = subprocess.run(compile_argv, capture_output=True, text=True)
    if motion_proof_dir:
        (motion_proof_dir / "calendar-reduced-motion-regressions.m").write_text(motion_harness_text)
        (motion_proof_dir / "compile.json").write_text(json.dumps({
            "argv": compile_argv, "returncode": compile_result.returncode,
            "stdout": compile_result.stdout, "stderr": compile_result.stderr
        }, indent=2) + "\n")
        (motion_proof_dir / "input-binding.json").write_text(json.dumps({
            "source_path": str(args.source.resolve()),
            "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
            "test_script_path": str(Path(__file__).resolve()),
            "test_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "extracted_method_sha256": {name: hashlib.sha256(body.encode()).hexdigest()
                                        for name, body in calendar_methods.items()},
            "display_calendar_helper_sha256": hashlib.sha256(display_calendar.encode()).hexdigest(),
            "transition_enum_sha256": hashlib.sha256(transition_enum.encode()).hexdigest(),
            "executed_production_methods": list(calendar_methods),
            "executed_production_calendar_helper": True,
            "renderer_double": "updateCalendarPanel counts calls; production swipe date arithmetic and Gregorian helper are extracted verbatim. UIKit snapshot, view insertion, animation and completion APIs are controlled doubles.",
            "scope": "Month/year transition behavior, selected-day reset, Reduced Motion spatial-animation boundary, edit/in-flight guards, and adjacent Today cross-dissolve behavior. No UIKit/device acceptance."
        }, indent=2, sort_keys=True) + "\n")
    if compile_result.returncode:
        print(compile_result.stdout, end="")
        print(compile_result.stderr, end="")
        if motion_proof_dir:
            (motion_proof_dir / "run-result.json").write_text(json.dumps({"returncode": compile_result.returncode, "stage": "compile"}) + "\n")
        raise SystemExit(compile_result.returncode)
    if motion_proof_dir:
        (motion_proof_dir / "calendar-reduced-motion-regressions").write_bytes(binary_path.read_bytes())
    motion_result = subprocess.run([str(binary_path)], capture_output=True, text=True)
    if motion_proof_dir:
        (motion_proof_dir / "run.stdout").write_text(motion_result.stdout)
        (motion_proof_dir / "run.stderr").write_text(motion_result.stderr)
        (motion_proof_dir / "run-result.json").write_text(json.dumps({
            "returncode": motion_result.returncode, "stage": "execute",
            "reduced_motion_method_extracted_from_source": True
        }, indent=2) + "\n")
    print(motion_result.stdout, end="")
    print(motion_result.stderr, end="")
    raise SystemExit(existing_suite_exit or motion_result.returncode)
