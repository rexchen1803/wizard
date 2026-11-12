#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <unistd.h>

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (void)lockUIFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (BOOL)unlockUIFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (void)startUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (BOOL)_finishUIUnlockFromSource:(NSUInteger)source withOptions:(NSDictionary *)options;
- (BOOL)isUILocked;
- (BOOL)isLockScreenVisible;
@end

@interface SpringBoard : UIApplication
- (void)_simulateLockButtonPress;
- (void)_lockButtonDown:(id)arg1 fromSource:(int)arg2;
- (void)_lockButtonUp:(id)arg1 fromSource:(int)arg2;
@end

@interface SBBacklightController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)screenIsOn;
- (void)_undimFromSource:(NSInteger)source;
- (void)setBacklightFactor:(float)factor source:(NSInteger)source;
- (void)turnOnScreenFullyWithBacklightSource:(NSInteger)source;
@end

@interface SBUserAgent : NSObject
+ (instancetype)sharedUserAgent;
- (void)dimScreen:(BOOL)animated;
- (void)undimScreen;
@end

static NSString * const kWizardPowerPrefsPath = @"/var/mobile/Library/Preferences/com.rex.wizardpower.plist";
static NSString * const kWizardPowerLogPath = @"/tmp/wizardpower.log";
static UIDeviceBatteryState gLastBatteryState = UIDeviceBatteryStateUnknown;
static BOOL gLastPowerConnected = NO;
static BOOL gLastPowerConnectedKnown = NO;
static NSUInteger gPowerEdgeGeneration = 0;
static NSTimeInterval gLastWakeActionAt = 0;
static NSTimeInterval gLastLockActionAt = 0;
static BOOL gControlledLockActive = NO;
static BOOL (*gOriginalShouldTurnOnScreen)(id, SEL, NSInteger) = NULL;
static BOOL (*gOriginalUnlockUI)(id, SEL, int, NSDictionary *) = NULL;
static void (*gOriginalStartUnlockUI)(id, SEL, int, NSDictionary *) = NULL;
static BOOL (*gOriginalFinishUnlockUI)(id, SEL, int, NSDictionary *) = NULL;

static BOOL WPScreenIsOn(void);
static BOOL WPPressPhysicalLockButton(NSString *reason);
static void WPLockScreen(NSString *reason, BOOL respectAutomationPrefs);
static void WPUnlockAndOpenWizard(NSString *reason, BOOL respectAutomationPrefs);
static BOOL WPDimSystemLockedScreen(void);
extern CFTypeRef IOPSCopyPowerSourcesInfo(void);
extern CFStringRef IOPSGetProvidingPowerSourceType(CFTypeRef blob);
extern CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob);
extern CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps);

static BOOL WPBoolPref(NSString *key, BOOL fallback) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kWizardPowerPrefsPath];
    id value = prefs[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static BOOL WPWakeEnabled(void) {
    if (!WPBoolPref(@"Enabled", YES)) return NO;
    if (!WPBoolPref(@"UnlockOnPowerConnected", YES)) return NO;
    return WPBoolPref(@"OpenWizardOnPowerConnected", YES);
}

static BOOL WPSleepEnabled(void) {
    return WPBoolPref(@"Enabled", YES) && WPBoolPref(@"LockOnPowerDisconnected", YES);
}

static void WPLog(NSString *format, ...) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardpower-debug"]) return;
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], body];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kWizardPowerLogPath];
    if (!handle) {
        [line writeToFile:kWizardPowerLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static NSString *WPBatteryStateName(UIDeviceBatteryState state) {
    switch (state) {
        case UIDeviceBatteryStateUnplugged: return @"unplugged";
        case UIDeviceBatteryStateCharging: return @"charging";
        case UIDeviceBatteryStateFull: return @"full";
        case UIDeviceBatteryStateUnknown:
        default: return @"unknown";
    }
}

static BOOL WPUIDevicePowerConnected(void) {
    UIDeviceBatteryState state = [[UIDevice currentDevice] batteryState];
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static BOOL WPIOKitPowerConnected(BOOL *known) {
    if (known) *known = NO;
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return NO;

    BOOL connected = NO;
    CFStringRef type = IOPSGetProvidingPowerSourceType(info);
    if (type) {
        if (known) *known = YES;
        if (CFEqual(type, CFSTR("AC Power")) || CFEqual(type, CFSTR("USB Power"))) {
            connected = YES;
        } else if (CFEqual(type, CFSTR("Battery Power"))) {
            connected = NO;
        }
    }

    CFArrayRef list = IOPSCopyPowerSourcesList(info);
    if (list) {
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex i = 0; i < count; i += 1) {
            CFTypeRef source = CFArrayGetValueAtIndex(list, i);
            NSDictionary *description = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, source);
            if (![description isKindOfClass:[NSDictionary class]]) continue;
            id external = [description objectForKey:@"ExternalConnected"];
            id state = [description objectForKey:@"Power Source State"];
            id charging = [description objectForKey:@"Is Charging"];
            if ([external respondsToSelector:@selector(boolValue)]) {
                if (known) *known = YES;
                if ([external boolValue]) connected = YES;
            }
            if ([state isKindOfClass:[NSString class]]) {
                if (known) *known = YES;
                if ([state isEqualToString:@"AC Power"] || [state isEqualToString:@"USB Power"]) connected = YES;
                else if ([state isEqualToString:@"Battery Power"]) connected = NO;
            }
            if ([charging respondsToSelector:@selector(boolValue)] && [charging boolValue]) {
                if (known) *known = YES;
                connected = YES;
            }
        }
        CFRelease(list);
    }

    CFRelease(info);
    return connected;
}

static BOOL WPPowerConnectedNow(void) {
    BOOL known = NO;
    BOOL connected = WPIOKitPowerConnected(&known);
    if (known) return connected;
    return WPUIDevicePowerConnected();
}

static NSString *WPPowerConnectedName(BOOL connected) {
    return connected ? @"powered" : @"battery";
}

static void WPOpenWizard(void) {
    NSURL *url = [NSURL URLWithString:@"wizardsystem://main"];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(openURL:)]) {
        [app openURL:url];
        WPLog(@"open Wizard URL requested");
    }
}

static void WPScheduleOpenWizard(void) {
    WPOpenWizard();
}

static BOOL WPShouldRunWakeAction(NSString *reason) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (gLastWakeActionAt > 0 && now - gLastWakeActionAt < 2.0) {
        WPLog(@"%@ skipped duplicate %.2fs", reason ?: @"wake", now - gLastWakeActionAt);
        return NO;
    }
    gLastWakeActionAt = now;
    return YES;
}

static void WPForceDisplayOn(void) {
    void *backBoard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
    void (*setBlanked)(int) = backBoard ? (void (*)(int))dlsym(backBoard, "_BKSDisplaySetScreenBlanked") : NULL;
    void (*setFactor)(float, float) = backBoard ? (void (*)(float, float))dlsym(backBoard, "BKSHIDServicesSetBacklightFactorWithFadeDuration") : NULL;
    if (setBlanked) setBlanked(0);
    if (setFactor) setFactor(1.0f, 0.18f);
    if (backBoard) dlclose(backBoard);

    Class backlightClass = NSClassFromString(@"SBBacklightController");
    id backlight = [backlightClass respondsToSelector:@selector(sharedInstance)] ? [backlightClass sharedInstance] : nil;
    if (backlight && [backlight respondsToSelector:@selector(turnOnScreenFullyWithBacklightSource:)]) {
        [backlight turnOnScreenFullyWithBacklightSource:1];
    }
    if (backlight && [backlight respondsToSelector:@selector(_undimFromSource:)]) {
        [backlight _undimFromSource:1];
    }
    if (backlight && [backlight respondsToSelector:@selector(setBacklightFactor:source:)]) {
        [backlight setBacklightFactor:1.0f source:1];
    }
    Class userAgentClass = NSClassFromString(@"SBUserAgent");
    id userAgent = [userAgentClass respondsToSelector:@selector(sharedUserAgent)] ? [userAgentClass sharedUserAgent] : nil;
    if (userAgent && [userAgent respondsToSelector:@selector(undimScreen)]) {
        [userAgent undimScreen];
    }
    WPLog(@"force display on blanked=%d factor=%d", setBlanked != NULL, setFactor != NULL);
}

static BOOL WPShouldTurnOnScreenForBacklightSource(id self, SEL command, NSInteger source) {
    if (gControlledLockActive && source == 2) {
        WPLog(@"blocked controlled-lock charging backlight source=%ld", (long)source);
        return NO;
    }
    return gOriginalShouldTurnOnScreen ? gOriginalShouldTurnOnScreen(self, command, source) : YES;
}

static BOOL WPUnlockUI(id self, SEL command, int source, NSDictionary *options) {
    if (gControlledLockActive && source == 17) {
        WPLog(@"blocked controlled-lock automatic unlock source=%d stage=request", source);
        return NO;
    }
    return gOriginalUnlockUI ? gOriginalUnlockUI(self, command, source, options) : NO;
}

static void WPStartUnlockUI(id self, SEL command, int source, NSDictionary *options) {
    if (gControlledLockActive && source == 17) {
        WPLog(@"blocked controlled-lock automatic unlock source=%d stage=start", source);
        return;
    }
    if (gOriginalStartUnlockUI) gOriginalStartUnlockUI(self, command, source, options);
}

static BOOL WPFinishUnlockUI(id self, SEL command, int source, NSDictionary *options) {
    if (gControlledLockActive && source == 17) {
        WPLog(@"blocked controlled-lock automatic unlock source=%d stage=finish", source);
        return NO;
    }
    return gOriginalFinishUnlockUI ? gOriginalFinishUnlockUI(self, command, source, options) : NO;
}

static void WPInstallControlledLockGuards(void) {
    Class backlightClass = NSClassFromString(@"SBBacklightController");
    Method backlightMethod = backlightClass ? class_getInstanceMethod(backlightClass, @selector(shouldTurnOnScreenForBacklightSource:)) : NULL;
    if (backlightMethod) {
        gOriginalShouldTurnOnScreen = (BOOL (*)(id, SEL, NSInteger))method_getImplementation(backlightMethod);
        method_setImplementation(backlightMethod, (IMP)WPShouldTurnOnScreenForBacklightSource);
    }

    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    Method requestMethod = managerClass ? class_getInstanceMethod(managerClass, @selector(unlockUIFromSource:withOptions:)) : NULL;
    Method startMethod = managerClass ? class_getInstanceMethod(managerClass, @selector(startUIUnlockFromSource:withOptions:)) : NULL;
    Method finishMethod = managerClass ? class_getInstanceMethod(managerClass, @selector(_finishUIUnlockFromSource:withOptions:)) : NULL;
    if (requestMethod) {
        gOriginalUnlockUI = (BOOL (*)(id, SEL, int, NSDictionary *))method_getImplementation(requestMethod);
        method_setImplementation(requestMethod, (IMP)WPUnlockUI);
    }
    if (startMethod) {
        gOriginalStartUnlockUI = (void (*)(id, SEL, int, NSDictionary *))method_getImplementation(startMethod);
        method_setImplementation(startMethod, (IMP)WPStartUnlockUI);
    }
    if (finishMethod) {
        gOriginalFinishUnlockUI = (BOOL (*)(id, SEL, int, NSDictionary *))method_getImplementation(finishMethod);
        method_setImplementation(finishMethod, (IMP)WPFinishUnlockUI);
    }
    WPLog(@"controlled-lock guards installed backlight=%d request=%d start=%d finish=%d", backlightMethod != NULL, requestMethod != NULL, startMethod != NULL, finishMethod != NULL);
}

static BOOL WPAutomatedWakeIsCurrent(NSUInteger generation) {
    return generation == gPowerEdgeGeneration && WPWakeEnabled() && WPPowerConnectedNow();
}

static void WPUnlockAndOpenWizard(NSString *reason, BOOL respectAutomationPrefs) {
    NSUInteger wakeGeneration = gPowerEdgeGeneration;
    if (respectAutomationPrefs && !WPAutomatedWakeIsCurrent(wakeGeneration)) {
        WPLog(@"%@ ignored: automatic wake disabled", reason ?: @"wake");
        return;
    }
    if (!WPShouldRunWakeAction(reason)) return;
    gControlledLockActive = NO;
    gLastLockActionAt = 0;

    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    id manager = [managerClass respondsToSelector:@selector(sharedInstance)] ? [managerClass sharedInstance] : nil;
    BOOL locked = manager && [manager respondsToSelector:@selector(isUILocked)] ? [manager isUILocked] : NO;
    BOOL visible = manager && [manager respondsToSelector:@selector(isLockScreenVisible)] ? [manager isLockScreenVisible] : NO;
    WPLog(@"%@ action locked=%d visible=%d", reason ?: @"wake", locked, visible);

    if (locked && !WPScreenIsOn()) {
        WPPressPhysicalLockButton(@"wake locked screen");
        WPLog(@"physical wake button requested");
    }

    WPForceDisplayOn();

    if (manager && [manager respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
        BOOL accepted = [manager unlockUIFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
        WPLog(@"unlockUI immediate accepted=%d", accepted);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (respectAutomationPrefs && !WPAutomatedWakeIsCurrent(wakeGeneration)) return;
        WPForceDisplayOn();
        if (manager && [manager respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
            BOOL accepted = [manager unlockUIFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"unlockUI 0.75s accepted=%d", accepted);
        }
        if (manager && [manager respondsToSelector:@selector(startUIUnlockFromSource:withOptions:)]) {
            [manager startUIUnlockFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"startUIUnlock 0.75s requested");
        }
        if (manager && [manager respondsToSelector:@selector(_finishUIUnlockFromSource:withOptions:)]) {
            BOOL finished = [manager _finishUIUnlockFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"finishUIUnlock 0.75s accepted=%d", finished);
        }
        WPScheduleOpenWizard();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (respectAutomationPrefs && !WPAutomatedWakeIsCurrent(wakeGeneration)) return;
        WPForceDisplayOn();
        if (manager && [manager respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
            BOOL accepted = [manager unlockUIFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"unlockUI 1.6s accepted=%d", accepted);
        }
        if (manager && [manager respondsToSelector:@selector(startUIUnlockFromSource:withOptions:)]) {
            [manager startUIUnlockFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"startUIUnlock 1.6s requested");
        }
        if (manager && [manager respondsToSelector:@selector(_finishUIUnlockFromSource:withOptions:)]) {
            BOOL finished = [manager _finishUIUnlockFromSource:17 withOptions:@{@"SBUIUnlockOptionsTurnOnScreenFirstKey": @YES}];
            WPLog(@"finishUIUnlock 1.6s accepted=%d", finished);
        }
        WPScheduleOpenWizard();
    });
}

static void WPSchedulePowerConnectedFallback(void) {
    NSUInteger generation = gPowerEdgeGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!WPAutomatedWakeIsCurrent(generation)) {
            WPLog(@"power connected fallback blocked: wake automation disabled");
            return;
        }
        // Connecting power can illuminate the lock screen before this fallback
        // runs.  Screen-on is therefore not proof that Wizard was restored.
        // Complete the unlock/open sequence only while its power edge is current.
        WPUnlockAndOpenWizard(@"power connected", YES);
    });
}

static BOOL WPScreenIsOn(void) {
    Class backlightClass = NSClassFromString(@"SBBacklightController");
    id backlight = [backlightClass respondsToSelector:@selector(sharedInstance)] ? [backlightClass sharedInstance] : nil;
    if (backlight && [backlight respondsToSelector:@selector(screenIsOn)]) {
        return [backlight screenIsOn];
    }
    return YES;
}

static BOOL WPDeviceIsLocked(BOOL *known) {
    if (known) *known = NO;
    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    id manager = [managerClass respondsToSelector:@selector(sharedInstance)] ? [managerClass sharedInstance] : nil;
    if (!manager || ![manager respondsToSelector:@selector(isUILocked)]) return NO;
    if (known) *known = YES;
    return [manager isUILocked];
}

static BOOL WPPressPhysicalLockButton(NSString *reason) {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_lockButtonDown:fromSource:)] &&
        [app respondsToSelector:@selector(_lockButtonUp:fromSource:)]) {
        [(SpringBoard *)app _lockButtonDown:nil fromSource:1];
        usleep(120000);
        [(SpringBoard *)app _lockButtonUp:nil fromSource:1];
        WPLog(@"physical lock button down/up requested %@", reason ?: @"");
        return YES;
    }
    if ([app respondsToSelector:@selector(_simulateLockButtonPress)]) {
        [(SpringBoard *)app _simulateLockButtonPress];
        WPLog(@"simulated lock button requested %@", reason ?: @"");
        return YES;
    }
    WPLog(@"physical lock button unavailable %@", reason ?: @"");
    return NO;
}

static BOOL WPCallPrivateVoidFunction(const char *frameworkPath, const char *symbolName) {
    void *handle = dlopen(frameworkPath, RTLD_LAZY);
    void (*function)(void) = handle ? (void (*)(void))dlsym(handle, symbolName) : NULL;
    if (function) function();
    if (handle) dlclose(handle);
    WPLog(@"iPad2 lock symbol %s available=%d", symbolName, function != NULL);
    return function != NULL;
}

static void WPLogFinalLockState(NSString *reason) {
    BOOL known = NO;
    BOOL locked = WPDeviceIsLocked(&known);
    WPLog(@"%@ known=%d locked=%d screenOn=%d controlled=%d", reason ?: @"lock final verification", known, locked, WPScreenIsOn(), gControlledLockActive);
}

static void WPScheduleLockStabilityChecks(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WPLogFinalLockState(@"lock stability 2s");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WPLogFinalLockState(@"lock stability 8s");
    });
}

static BOOL WPDimSystemLockedScreen(void) {
    Class userAgentClass = NSClassFromString(@"SBUserAgent");
    id userAgent = [userAgentClass respondsToSelector:@selector(sharedUserAgent)] ? [userAgentClass sharedUserAgent] : nil;
    if (userAgent && [userAgent respondsToSelector:@selector(dimScreen:)]) {
        [userAgent dimScreen:YES];
        WPLog(@"SBUserAgent dimScreen requested after system lock");
        return YES;
    }
    WPLog(@"SBUserAgent dimScreen unavailable");

    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    void (*dimScreen)(void) = handle ? (void (*)(void))dlsym(handle, "SBDimScreen") : NULL;
    if (!dimScreen) {
        if (handle) dlclose(handle);
        WPLog(@"SBDimScreen runtime symbol unavailable");
        return NO;
    }
    dimScreen();
    dlclose(handle);
    WPLog(@"SBDimScreen runtime request after system lock");
    return YES;
}

static void WPVerifyPhysicalLockFallback(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        WPLogFinalLockState(@"lock physical fallback verification");
        WPScheduleLockStabilityChecks();
    });
}

static void WPLockScreen(NSString *reason, BOOL respectAutomationPrefs) {
    if (respectAutomationPrefs && !WPSleepEnabled()) {
        WPLog(@"%@ ignored: automatic sleep disabled", reason ?: @"lock");
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (gLastLockActionAt > 0 && now - gLastLockActionAt < 2.0) {
        WPLog(@"power disconnected lock skipped duplicate %.2fs", now - gLastLockActionAt);
        return;
    }
    gLastLockActionAt = now;
    gControlledLockActive = YES;

    WPLog(@"%@ action using iPad2 lock sequence", reason ?: @"lock");
    BOOL requested = WPPressPhysicalLockButton(@"iPad2 sequence");
    requested = WPCallPrivateVoidFunction("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", "GSEventLockDevice") || requested;
    requested = WPCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBLockDevice") || requested;
    requested = WPCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBSLockDevice") || requested;
    requested = WPCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBDimScreen") || requested;
    if (!requested) {
        gControlledLockActive = NO;
        WPLog(@"lock failed: no supported SpringBoard API");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL known = NO;
        BOOL locked = WPDeviceIsLocked(&known);
        WPLog(@"lock verification known=%d locked=%d screenOn=%d", known, locked, WPScreenIsOn());
        if (known && locked) {
            if (!WPScreenIsOn()) {
                WPLogFinalLockState(@"lock complete");
                WPScheduleLockStabilityChecks();
                return;
            }
            if (!WPDimSystemLockedScreen()) {
                if (WPPressPhysicalLockButton(@"after system lock dim unavailable")) {
                    WPVerifyPhysicalLockFallback();
                } else {
                    WPLog(@"lock incomplete: system locked but display still on");
                }
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                BOOL dimKnown = NO;
                BOOL dimLocked = WPDeviceIsLocked(&dimKnown);
                BOOL dimScreenOn = WPScreenIsOn();
                WPLog(@"lock dim verification known=%d locked=%d screenOn=%d", dimKnown, dimLocked, dimScreenOn);
                if (dimKnown && dimLocked && !dimScreenOn) {
                    WPScheduleLockStabilityChecks();
                } else if (dimKnown && dimLocked && WPPressPhysicalLockButton(@"after dim verification failed")) {
                    WPVerifyPhysicalLockFallback();
                } else {
                    WPLog(@"lock dim verification failed without safe fallback");
                }
            });
            return;
        }
        Class managerClass = NSClassFromString(@"SBLockScreenManager");
        id manager = [managerClass respondsToSelector:@selector(sharedInstance)] ? [managerClass sharedInstance] : nil;
        if (!manager || ![manager respondsToSelector:@selector(lockUIFromSource:withOptions:)]) {
            WPLog(@"physical lock verification failed and manager fallback unavailable");
            return;
        }
        [manager lockUIFromSource:1 withOptions:@{}];
        WPLog(@"lock manager fallback requested");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL fallbackKnown = NO;
            BOOL fallbackLocked = WPDeviceIsLocked(&fallbackKnown);
            if (fallbackKnown && fallbackLocked && WPScreenIsOn()) WPDimSystemLockedScreen();
            WPLogFinalLockState(@"lock manager fallback verification");
            WPScheduleLockStabilityChecks();
        });
    });
}

static void WPHandleBatteryState(UIDeviceBatteryState state) {
    if (state == gLastBatteryState) return;

    UIDeviceBatteryState previous = gLastBatteryState;
    gLastBatteryState = state;
    WPLog(@"battery state %@ -> %@", WPBatteryStateName(previous), WPBatteryStateName(state));
    if (gControlledLockActive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL known = NO;
            BOOL locked = WPDeviceIsLocked(&known);
            if (known && locked && WPScreenIsOn()) {
                WPLog(@"controlled lock re-dimming after battery state change");
                WPDimSystemLockedScreen();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    BOOL fallbackKnown = NO;
                    BOOL fallbackLocked = WPDeviceIsLocked(&fallbackKnown);
                    if (fallbackKnown && fallbackLocked && WPScreenIsOn()) {
                        WPPressPhysicalLockButton(@"controlled lock battery re-dim fallback");
                    }
                });
            }
        });
    }
}

static void WPCheckPowerState(NSString *source) {
    BOOL isPowered = WPPowerConnectedNow();
    if (gLastPowerConnectedKnown && isPowered == gLastPowerConnected) return;

    BOOL wasPowered = gLastPowerConnected;
    gLastPowerConnected = isPowered;
    gLastPowerConnectedKnown = YES;
    gPowerEdgeGeneration += 1;
    WPLog(@"power source %@ -> %@ via %@", WPPowerConnectedName(wasPowered), WPPowerConnectedName(isPowered), source ?: @"poll");

    if (!WPBoolPref(@"Enabled", YES)) {
        WPLog(@"power change ignored: automation disabled");
        return;
    }

    if (gLastPowerConnectedKnown && !wasPowered && isPowered) {
        WPSchedulePowerConnectedFallback();
    } else if (gLastPowerConnectedKnown && wasPowered && !isPowered) {
        WPLockScreen(@"power disconnected", YES);
    }
}

@interface WizardPowerPoller : NSObject
+ (void)tick:(NSTimer *)timer;
@end

@implementation WizardPowerPoller
+ (void)tick:(__unused NSTimer *)timer {
    WPHandleBatteryState([[UIDevice currentDevice] batteryState]);
    WPCheckPowerState(@"poll");
}
@end

__attribute__((constructor))
static void WPInit(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
        gLastBatteryState = [[UIDevice currentDevice] batteryState];
        gLastPowerConnected = WPPowerConnectedNow();
        gLastPowerConnectedKnown = YES;
        WPLog(@"WizardPower loaded initial=%@ power=%@", WPBatteryStateName(gLastBatteryState), WPPowerConnectedName(gLastPowerConnected));
        WPInstallControlledLockGuards();

        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *notification) {
            WPHandleBatteryState([[UIDevice currentDevice] batteryState]);
            WPCheckPowerState(@"notification");
        }];

        [NSTimer scheduledTimerWithTimeInterval:0.25
                                         target:[WizardPowerPoller class]
                                       selector:@selector(tick:)
                                       userInfo:nil
                                        repeats:YES];
    }
}
