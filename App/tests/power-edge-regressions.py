#!/usr/bin/env python3
"""Compile source-extracted SpringBoard power-edge guards with fake effects."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/WizardPowerTweak/Tweak.xm"


def extract_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"production function not found: {signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"function body not found: {signature}")

    depth = 0
    state = "code"
    escaped = False
    i = brace
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if ch == '"':
                state = "string"
            elif ch == "'":
                state = "char"
            elif ch == "/" and nxt == "/":
                state = "line-comment"
                i += 1
            elif ch == "/" and nxt == "*":
                state = "block-comment"
                i += 1
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source[start : i + 1]
        elif state in ("string", "char"):
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif (state == "string" and ch == '"') or (state == "char" and ch == "'"):
                state = "code"
        elif state == "line-comment":
            if ch == "\n":
                state = "code"
        elif state == "block-comment" and ch == "*" and nxt == "/":
            state = "code"
            i += 1
        i += 1
    raise SystemExit(f"unterminated function body: {signature}")


source = SOURCE.read_text()
functions = [
    extract_function(source, "static BOOL WPAutomatedWakeIsCurrent(NSUInteger generation) {"),
    extract_function(source, "static void WPUnlockAndOpenWizard(NSString *reason, BOOL respectAutomationPrefs) {"),
    extract_function(source, "static void WPSchedulePowerConnectedFallback(void) {"),
    extract_function(source, "static void WPCheckPowerState(NSString *source) {"),
    extract_function(source, "static void WPLog(NSString *format, ...) {"),
    extract_function(source, "static void WPInit(void) {"),
]

generated = r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdarg.h>
#include <math.h>

#define NSBundle WPTestBundle
#define NSNotificationCenter WPTestNotificationCenter
#define NSTimer WPTestTimer
#define NSFileManager WPTestFileManager
#define NSFileHandle WPTestFileHandle
#define CFNotificationCenterAddObserver(...) (gDarwinObserverRegistrationCount += 1)
#define dispatch_async(queue, block) ((void)0)

typedef NS_ENUM(NSInteger, UIDeviceBatteryState) {
    UIDeviceBatteryStateUnknown,
    UIDeviceBatteryStateUnplugged,
    UIDeviceBatteryStateCharging,
    UIDeviceBatteryStateFull
};
static NSString * const UIDeviceBatteryStateDidChangeNotification = @"UIDeviceBatteryStateDidChangeNotification";

static NSUInteger gPowerEdgeGeneration;
static BOOL gLastPowerConnected;
static BOOL gLastPowerConnectedKnown;
static NSTimeInterval gLastLockActionAt;
static BOOL gControlledLockActive;
static BOOL gFakePowerConnected;
static UIDeviceBatteryState gLastBatteryState;
static NSMutableDictionary *gFakePrefs;
static NSMutableArray *gScheduledCalls;
static int64_t gFakeNowNanos;
static NSUInteger gOpenWizardCount;
static NSUInteger gForceDisplayCount;
static NSUInteger gLockRequestCount;
static NSUInteger gCheckCount;
static NSUInteger gFailureCount;
static NSUInteger gBatteryMonitoringEnableCount;
static NSUInteger gBatteryObserverCount;
static NSUInteger gPollTimerCount;
static NSUInteger gGuardInstallCount;
static NSUInteger gDarwinObserverRegistrationCount;
static NSUInteger gDebugMarkerCheckCount;
static NSUInteger gLogFileOpenCount;
static NSString * const kWizardPowerLogPath = @"/tmp/wizardpower.log";
static NSString *gObservedBatteryNotification;
static NSString *gObservedDebugMarkerPath;
static NSString *gObservedLogFilePath;
static NSString *gFakeBundleIdentifier;
static BOOL gFakeDebugMarkerExists;
static NSTimeInterval gObservedPollInterval;
static BOOL gObservedPollRepeats;

@interface WPTestBundle : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
+ (instancetype)mainBundle;
@end
@implementation WPTestBundle
+ (instancetype)mainBundle {
    static WPTestBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ bundle = [[self alloc] init]; });
    bundle.bundleIdentifier = gFakeBundleIdentifier;
    return bundle;
}
@end

@interface UIDevice : NSObject
@property (nonatomic, assign) UIDeviceBatteryState batteryState;
+ (instancetype)currentDevice;
- (void)setBatteryMonitoringEnabled:(BOOL)enabled;
@end
@implementation UIDevice
+ (instancetype)currentDevice {
    static UIDevice *device;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ device = [[self alloc] init]; device.batteryState = UIDeviceBatteryStateUnplugged; });
    return device;
}
- (void)setBatteryMonitoringEnabled:(BOOL)enabled { if (enabled) gBatteryMonitoringEnableCount += 1; }
@end

@interface WPTestNotificationCenter : NSObject
+ (instancetype)defaultCenter;
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *notification))block;
@end
@implementation WPTestNotificationCenter
+ (instancetype)defaultCenter { static WPTestNotificationCenter *center; static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{ center = [[self alloc] init]; }); return center; }
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *))block {
    (void)object; (void)queue; (void)block;
    gBatteryObserverCount += 1;
    gObservedBatteryNotification = [name copy];
    return self;
}
@end

@interface WPTestTimer : NSObject
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector userInfo:(id)userInfo repeats:(BOOL)repeats;
@end
@implementation WPTestTimer
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector userInfo:(id)userInfo repeats:(BOOL)repeats {
    (void)target; (void)selector; (void)userInfo;
    gPollTimerCount += 1;
    gObservedPollInterval = interval;
    gObservedPollRepeats = repeats;
    return [self new];
}
@end

@interface WPTestFileManager : NSObject
+ (instancetype)defaultManager;
- (BOOL)fileExistsAtPath:(NSString *)path;
@end
@implementation WPTestFileManager
+ (instancetype)defaultManager { static WPTestFileManager *manager; static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; }); return manager; }
- (BOOL)fileExistsAtPath:(NSString *)path { gDebugMarkerCheckCount += 1; gObservedDebugMarkerPath = [path copy]; return gFakeDebugMarkerExists; }
@end

@interface WPTestFileHandle : NSObject
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path;
- (void)seekToEndOfFile;
- (void)writeData:(NSData *)data;
- (void)closeFile;
@end
@implementation WPTestFileHandle
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path { gLogFileOpenCount += 1; gObservedLogFilePath = [path copy]; return [self new]; }
- (void)seekToEndOfFile {}
- (void)writeData:(NSData *)data { (void)data; }
- (void)closeFile {}
@end

@interface WizardPowerPoller : NSObject
+ (void)tick:(NSTimer *)timer;
@end
@implementation WizardPowerPoller
+ (void)tick:(NSTimer *)timer { (void)timer; }
@end

static void IWTestSchedule(int64_t deadline, dispatch_block_t block);
static dispatch_time_t IWTestDispatchTime(dispatch_time_t when, int64_t delta) {
    int64_t base = when == DISPATCH_TIME_NOW ? gFakeNowNanos : (int64_t)when;
    return (dispatch_time_t)(base + delta);
}
#define dispatch_time(when, delta) IWTestDispatchTime((when), (delta))
#define dispatch_get_main_queue() ((dispatch_queue_t)NULL)
#define dispatch_after(when, queue, block) IWTestSchedule((int64_t)(when), (block))

static void IWCheck(BOOL condition, NSString *message) {
    gCheckCount += 1;
    if (!condition) {
        gFailureCount += 1;
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
    }
}

@interface IWScheduledCall : NSObject
@property (nonatomic, assign) int64_t deadline;
@property (nonatomic, copy) dispatch_block_t block;
@end
@implementation IWScheduledCall @end

static void IWTestSchedule(int64_t deadline, dispatch_block_t block) {
    IWScheduledCall *call = [[IWScheduledCall alloc] init];
    call.deadline = deadline;
    call.block = block;
    [gScheduledCalls addObject:call];
}

static void IWAdvanceTo(int64_t target) {
    for (;;) {
        NSUInteger nextIndex = NSNotFound;
        int64_t nextDeadline = INT64_MAX;
        NSUInteger i;
        for (i = 0; i < [gScheduledCalls count]; i += 1) {
            IWScheduledCall *candidate = [gScheduledCalls objectAtIndex:i];
            if (candidate.deadline <= target && candidate.deadline < nextDeadline) {
                nextIndex = i;
                nextDeadline = candidate.deadline;
            }
        }
        if (nextIndex == NSNotFound) break;
        IWScheduledCall *call = [gScheduledCalls objectAtIndex:nextIndex];
        [gScheduledCalls removeObjectAtIndex:nextIndex];
        gFakeNowNanos = call.deadline;
        dispatch_block_t block = call.block;
        call.block = nil;
        if (block) block();
    }
    gFakeNowNanos = target;
}

@interface SBLockScreenManager : NSObject
@property (nonatomic, assign) NSUInteger unlockCount;
@property (nonatomic, assign) NSUInteger startCount;
@property (nonatomic, assign) NSUInteger finishCount;
@property (nonatomic, assign) BOOL locked;
@property (nonatomic, assign) BOOL visible;
+ (instancetype)sharedInstance;
- (BOOL)unlockUIFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (void)startUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (BOOL)_finishUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (BOOL)isUILocked;
- (BOOL)isLockScreenVisible;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance {
    static SBLockScreenManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}
- (BOOL)unlockUIFromSource:(NSUInteger)source withOptions:(NSDictionary *)options {
    (void)source; (void)options;
    self.unlockCount += 1;
    return YES;
}
- (void)startUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options {
    (void)source; (void)options;
    self.startCount += 1;
}
- (BOOL)_finishUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options {
    (void)source; (void)options;
    self.finishCount += 1;
    return YES;
}
- (BOOL)isUILocked { return self.locked; }
- (BOOL)isLockScreenVisible { return self.visible; }
@end

static BOOL WPBoolPref(NSString *key, BOOL fallback) {
    id value = [gFakePrefs objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}
static BOOL WPWakeEnabled(void) {
    return WPBoolPref(@"Enabled", YES) &&
           WPBoolPref(@"UnlockOnPowerConnected", YES) &&
           WPBoolPref(@"OpenWizardOnPowerConnected", YES);
}
static BOOL WPPowerConnectedNow(void) { return gFakePowerConnected; }
static NSString *WPPowerConnectedName(BOOL connected) { return connected ? @"powered" : @"battery"; }
static BOOL WPShouldRunWakeAction(NSString *reason) { (void)reason; return YES; }
static BOOL WPScreenIsOn(void) { return YES; }
static BOOL WPPressPhysicalLockButton(NSString *reason) { (void)reason; return NO; }
static void WPForceDisplayOn(void) { gForceDisplayCount += 1; }
static void WPScheduleOpenWizard(void) { gOpenWizardCount += 1; }
static void WPLockScreen(NSString *reason, BOOL respectAutomationPrefs) {
    (void)reason; (void)respectAutomationPrefs;
    gLockRequestCount += 1;
}
static void WPLog(NSString *format, ...);
static NSString *WPBatteryStateName(UIDeviceBatteryState state) { (void)state; return @"fake"; }
static void WPHandleBatteryState(UIDeviceBatteryState state) { (void)state; }
static void WPInstallControlledLockGuards(void) { gGuardInstallCount += 1; }

static BOOL WPAutomatedWakeIsCurrent(NSUInteger generation);
static void WPUnlockAndOpenWizard(NSString *reason, BOOL respectAutomationPrefs);
static void WPSchedulePowerConnectedFallback(void);
static void WPCheckPowerState(NSString *source);
'''

generated += "\n".join(functions)
generated += r'''

static void IWReset(BOOL initiallyPowered) {
    gFakeNowNanos = 0;
    gFakePowerConnected = initiallyPowered;
    gPowerEdgeGeneration = 0;
    gLastPowerConnected = initiallyPowered;
    gLastPowerConnectedKnown = YES;
    gLastLockActionAt = 0;
    gControlledLockActive = NO;
    gFakePrefs = [@{
        @"Enabled": @YES,
        @"UnlockOnPowerConnected": @YES,
        @"OpenWizardOnPowerConnected": @YES,
        @"LockOnPowerDisconnected": @YES
    } mutableCopy];
    gScheduledCalls = [NSMutableArray array];
    gOpenWizardCount = 0;
    gForceDisplayCount = 0;
    gLockRequestCount = 0;
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    manager.unlockCount = 0;
    manager.startCount = 0;
    manager.finishCount = 0;
    manager.locked = NO;
    manager.visible = NO;
}

static void IWResetInitializationFixture(NSString *bundleIdentifier) {
    gFakeBundleIdentifier = [bundleIdentifier copy];
    gFakePowerConnected = YES;
    gLastBatteryState = UIDeviceBatteryStateUnknown;
    gLastPowerConnected = NO;
    gLastPowerConnectedKnown = NO;
    gBatteryMonitoringEnableCount = 0;
    gBatteryObserverCount = 0;
    gPollTimerCount = 0;
    gGuardInstallCount = 0;
    gDarwinObserverRegistrationCount = 0;
    gDebugMarkerCheckCount = 0;
    gLogFileOpenCount = 0;
    gObservedBatteryNotification = nil;
    gObservedDebugMarkerPath = nil;
    gObservedLogFilePath = nil;
    gObservedPollInterval = 0.0;
    gObservedPollRepeats = NO;
    gFakeDebugMarkerExists = NO;
    gScheduledCalls = [NSMutableArray array];
}

static void IWTestSpringBoardInitializationAndDiagnosticLogging(void) {
    IWResetInitializationFixture(@"com.example.other-app");
    WPInit();
    IWCheck(gBatteryMonitoringEnableCount == 0 && gBatteryObserverCount == 0 &&
            gPollTimerCount == 0 && gGuardInstallCount == 0,
            @"non-SpringBoard process does not install the power observer or poller");

    IWResetInitializationFixture(@"com.apple.springboard");
    WPInit();
    IWCheck(gBatteryMonitoringEnableCount == 1, @"SpringBoard initialization enables local battery monitoring");
    IWCheck(gBatteryObserverCount == 1 &&
            [gObservedBatteryNotification isEqualToString:UIDeviceBatteryStateDidChangeNotification],
            @"SpringBoard retains the local battery-state observer");
    IWCheck(gPollTimerCount == 1 && fabs(gObservedPollInterval - 0.25) < 0.0001 && gObservedPollRepeats,
            @"SpringBoard retains the quarter-second local power poller");
    IWCheck(gGuardInstallCount == 1, @"SpringBoard still installs physical lock and wake guards");
    IWCheck(gDarwinObserverRegistrationCount == 0,
            @"SpringBoard initialization registers no Darwin notification controls");
    IWCheck(gDebugMarkerCheckCount > 0 &&
            [gObservedDebugMarkerPath isEqualToString:@"/tmp/wizardpower-debug"] && gLogFileOpenCount == 0,
            @"default power initialization checks its diagnostic marker and writes no activity log");

    WPLog(@"disabled diagnostic log probe");
    IWCheck(gLogFileOpenCount == 0, @"WPLog remains silent when the diagnostic marker is absent");
    gFakeDebugMarkerExists = YES;
    WPLog(@"enabled diagnostic log probe");
    IWCheck(gLogFileOpenCount == 1 && [gObservedLogFilePath isEqualToString:kWizardPowerLogPath],
            @"WPLog opens the expected log only when diagnostics are enabled");
}

static void IWTestDisconnectBeforeFallback(void) {
    IWReset(NO);
    gFakePowerConnected = YES;
    WPCheckPowerState(@"test connect");
    NSUInteger connectedGeneration = gPowerEdgeGeneration;
    gFakePowerConnected = NO;
    WPCheckPowerState(@"test disconnect");
    IWCheck(gPowerEdgeGeneration == connectedGeneration + 1, @"disconnect advances edge generation");
    IWAdvanceTo(650000000LL);
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    IWCheck(manager.unlockCount == 0 && gOpenWizardCount == 0,
            @"disconnect before fallback suppresses stale automatic wake and open");
    IWCheck(gLockRequestCount == 1, @"disconnect still requests the configured lock path");
}

static void IWTestStableConnectCompletesWake(void) {
    IWReset(NO);
    gFakePowerConnected = YES;
    WPCheckPowerState(@"test connect");
    IWAdvanceTo(650000000LL);
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    IWCheck(manager.unlockCount == 1 && gOpenWizardCount == 0,
            @"stable connect performs immediate unlock before scheduled retries");
    IWAdvanceTo(1400000000LL);
    IWCheck(manager.unlockCount == 2 && gOpenWizardCount == 1,
            @"first current retry unlocks and opens Wizard");
    IWAdvanceTo(2250000000LL);
    IWCheck(manager.unlockCount == 3 && gOpenWizardCount == 2,
            @"second current retry remains enabled for a stable connection");
}

static void IWTestDisconnectAfterImmediateWake(void) {
    IWReset(NO);
    gFakePowerConnected = YES;
    WPCheckPowerState(@"test connect");
    IWAdvanceTo(650000000LL);
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    IWCheck(manager.unlockCount == 1, @"connect fallback performs its immediate unlock");

    gFakePowerConnected = NO;
    WPCheckPowerState(@"test disconnect");
    IWAdvanceTo(2250000000LL);
    IWCheck(manager.unlockCount == 1 && gOpenWizardCount == 0,
            @"disconnect suppresses both later wake retries and Wizard opens");
}

static void IWTestDisabledWakePreference(void) {
    IWReset(NO);
    [gFakePrefs setObject:@NO forKey:@"UnlockOnPowerConnected"];
    gFakePowerConnected = YES;
    WPCheckPowerState(@"test connect with wake disabled");
    IWAdvanceTo(650000000LL);
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    IWCheck(manager.unlockCount == 0 && gOpenWizardCount == 0 && gForceDisplayCount == 0,
            @"disabled wake preference blocks fallback before UI effects");
}

static void IWTestManualWakeIgnoresPowerAutomation(void) {
    IWReset(NO);
    [gFakePrefs setObject:@NO forKey:@"Enabled"];
    [gFakePrefs setObject:@NO forKey:@"UnlockOnPowerConnected"];
    [gFakePrefs setObject:@NO forKey:@"OpenWizardOnPowerConnected"];
    WPUnlockAndOpenWizard(@"manual test", NO);
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    IWCheck(manager.unlockCount == 1, @"manual wake remains allowed while unplugged with automation disabled");
    IWAdvanceTo(1600000000LL);
    IWCheck(manager.unlockCount == 3 && gOpenWizardCount == 2,
            @"manual wake retries are not blocked by automated power guards");
}

int main(void) {
    @autoreleasepool {
        gCheckCount = 0;
        gFailureCount = 0;
        IWTestSpringBoardInitializationAndDiagnosticLogging();
        IWTestDisconnectBeforeFallback();
        IWTestStableConnectCompletesWake();
        IWTestDisconnectAfterImmediateWake();
        IWTestDisabledWakePreference();
        IWTestManualWakeIgnoresPowerAutomation();
        printf("power edge regressions: %lu checks, %lu failures\n",
               (unsigned long)gCheckCount, (unsigned long)gFailureCount);
        return gFailureCount ? 1 : 0;
    }
}
'''

with tempfile.TemporaryDirectory(prefix="wizard-power-edge-") as temporary:
    generated_path = Path(temporary) / "power-edge-harness.m"
    binary_path = Path(temporary) / "power-edge-harness"
    generated_path.write_text(generated)
    subprocess.run(
        [
            "/usr/bin/clang",
            "-fobjc-arc",
            "-fblocks",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
            "-framework",
            "Foundation",
            str(generated_path),
            "-o",
            str(binary_path),
        ],
        check=True,
    )
    subprocess.run([str(binary_path)], check=True)
