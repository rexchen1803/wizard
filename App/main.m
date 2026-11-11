#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <QuartzCore/QuartzCore.h>
#import "IWMediaCatalog.h"
#import "IWHTTPTransport.h"
#import "IWFrameProbe.h"
#import <objc/runtime.h>
#import "IWWeatherService.h"

static NSString * const IWLastLandscapeOrientationKey = @"IWLastLandscapeOrientation";

static UIInterfaceOrientation IWCurrentLandscapeOrientation(void) {
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    if (deviceOrientation == UIDeviceOrientationLandscapeLeft) return UIInterfaceOrientationLandscapeRight;
    if (deviceOrientation == UIDeviceOrientationLandscapeRight) return UIInterfaceOrientationLandscapeLeft;
    UIInterfaceOrientation statusOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (UIInterfaceOrientationIsLandscape(statusOrientation)) return statusOrientation;
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:IWLastLandscapeOrientationKey];
    if (saved == UIInterfaceOrientationLandscapeLeft || saved == UIInterfaceOrientationLandscapeRight) {
        return (UIInterfaceOrientation)saved;
    }
    return UIInterfaceOrientationLandscapeLeft;
}

static NSString *IWWeatherDebugPath(NSString *name) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

#ifndef IW_WEATHER_DIAGNOSTICS
#define IW_WEATHER_DIAGNOSTICS 0
#endif
#import <dlfcn.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <limits.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/types.h>

typedef NS_ENUM(NSInteger, IWLocalVideoFixtureStatus) {
    IWLocalVideoFixtureStatusInvalid = -1,
    IWLocalVideoFixtureStatusAbsent = 0,
    IWLocalVideoFixtureStatusValid = 1
};

static IWLocalVideoFixtureStatus IWResolveLocalVideoFixture(NSString *nonceMarkerPath,
                                                             NSString *parentRoot,
                                                             uid_t expectedUID,
                                                             NSString **fixturePath) {
    if (fixturePath) *fixturePath = nil;
    if (![nonceMarkerPath length] || ![parentRoot length]) return IWLocalVideoFixtureStatusInvalid;

    const char *markerName = [nonceMarkerPath fileSystemRepresentation];
    const char *parentName = [parentRoot fileSystemRepresentation];
    struct stat markerInfo;
    if (!markerName || !parentName) return IWLocalVideoFixtureStatusInvalid;
    if (lstat(markerName, &markerInfo) != 0) {
        return errno == ENOENT ? IWLocalVideoFixtureStatusAbsent : IWLocalVideoFixtureStatusInvalid;
    }
    if (!S_ISREG(markerInfo.st_mode) || markerInfo.st_uid != expectedUID ||
        (markerInfo.st_mode & 07777) != 0600 || markerInfo.st_size != 20) {
        return IWLocalVideoFixtureStatusInvalid;
    }

    int markerFD = open(markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (markerFD < 0) return IWLocalVideoFixtureStatusInvalid;
    struct stat openedMarkerInfo;
    BOOL markerOK = fstat(markerFD, &openedMarkerInfo) == 0 &&
                    openedMarkerInfo.st_dev == markerInfo.st_dev &&
                    openedMarkerInfo.st_ino == markerInfo.st_ino &&
                    S_ISREG(openedMarkerInfo.st_mode) && openedMarkerInfo.st_uid == expectedUID &&
                    (openedMarkerInfo.st_mode & 07777) == 0600 && openedMarkerInfo.st_size == 20;
    char nonce[21] = {0};
    size_t nonceBytesRead = 0;
    while (markerOK && nonceBytesRead < 20) {
        ssize_t count = read(markerFD, nonce + nonceBytesRead, 20 - nonceBytesRead);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) markerOK = NO;
        else nonceBytesRead += (size_t)count;
    }
    char trailingByte = 0;
    ssize_t trailingCount = -1;
    while (markerOK) {
        trailingCount = read(markerFD, &trailingByte, 1);
        if (trailingCount < 0 && errno == EINTR) continue;
        break;
    }
    struct stat finalMarkerInfo;
    markerOK = markerOK && trailingCount == 0 && fstat(markerFD, &finalMarkerInfo) == 0 &&
               finalMarkerInfo.st_dev == openedMarkerInfo.st_dev &&
               finalMarkerInfo.st_ino == openedMarkerInfo.st_ino && S_ISREG(finalMarkerInfo.st_mode) &&
               finalMarkerInfo.st_uid == expectedUID && (finalMarkerInfo.st_mode & 07777) == 0600 &&
               finalMarkerInfo.st_size == 20;
    close(markerFD);
    if (!markerOK) return IWLocalVideoFixtureStatusInvalid;

    for (NSUInteger i = 0; i < 20; i++) {
        char value = nonce[i];
        if (!((value >= '0' && value <= '9') || (value >= 'a' && value <= 'f'))) {
            return IWLocalVideoFixtureStatusInvalid;
        }
    }

    char canonicalParent[PATH_MAX];
    if (!realpath(parentName, canonicalParent)) return IWLocalVideoFixtureStatusInvalid;
    struct stat parentInfo;
    if (stat(canonicalParent, &parentInfo) != 0 || !S_ISDIR(parentInfo.st_mode)) {
        return IWLocalVideoFixtureStatusInvalid;
    }

    char expectedRoot[PATH_MAX];
    int rootLength = snprintf(expectedRoot, sizeof(expectedRoot), "%s/.wizard-local-video-audit-%s",
                              canonicalParent, nonce);
    if (rootLength < 0 || (size_t)rootLength >= sizeof(expectedRoot)) return IWLocalVideoFixtureStatusInvalid;
    struct stat rootInfo;
    if (lstat(expectedRoot, &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode) ||
        rootInfo.st_uid != expectedUID || (rootInfo.st_mode & 07777) != 0700 ||
        rootInfo.st_dev != parentInfo.st_dev) {
        return IWLocalVideoFixtureStatusInvalid;
    }
    char canonicalRoot[PATH_MAX];
    if (!realpath(expectedRoot, canonicalRoot) || strcmp(canonicalRoot, expectedRoot) != 0) {
        return IWLocalVideoFixtureStatusInvalid;
    }

    char expectedFixture[PATH_MAX];
    int fixtureLength = snprintf(expectedFixture, sizeof(expectedFixture), "%s/fixture.mp4", expectedRoot);
    if (fixtureLength < 0 || (size_t)fixtureLength >= sizeof(expectedFixture)) return IWLocalVideoFixtureStatusInvalid;
    struct stat fixtureInfo;
    if (lstat(expectedFixture, &fixtureInfo) != 0 || !S_ISREG(fixtureInfo.st_mode) ||
        fixtureInfo.st_uid != expectedUID || fixtureInfo.st_size <= 0 ||
        fixtureInfo.st_size > 2 * 1024 * 1024 || fixtureInfo.st_dev != rootInfo.st_dev) {
        return IWLocalVideoFixtureStatusInvalid;
    }
    int fixtureFD = open(expectedFixture, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fixtureFD < 0) return IWLocalVideoFixtureStatusInvalid;
    struct stat openedFixtureInfo;
    BOOL fixtureOK = fstat(fixtureFD, &openedFixtureInfo) == 0 &&
                     openedFixtureInfo.st_dev == fixtureInfo.st_dev &&
                     openedFixtureInfo.st_ino == fixtureInfo.st_ino &&
                     S_ISREG(openedFixtureInfo.st_mode) && openedFixtureInfo.st_uid == expectedUID &&
                     openedFixtureInfo.st_size > 0 && openedFixtureInfo.st_size <= 2 * 1024 * 1024;
    close(fixtureFD);
    if (!fixtureOK) return IWLocalVideoFixtureStatusInvalid;

    char canonicalFixture[PATH_MAX];
    if (!realpath(expectedFixture, canonicalFixture) || strcmp(canonicalFixture, expectedFixture) != 0) {
        return IWLocalVideoFixtureStatusInvalid;
    }
    if (fixturePath) *fixturePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:canonicalFixture
                                                                                                  length:strlen(canonicalFixture)];
    return fixturePath && *fixturePath ? IWLocalVideoFixtureStatusValid : IWLocalVideoFixtureStatusInvalid;
}

static NSString * const IWAppPath = @"/var/mobile/Media/iPadWizard/app";

static NSString *IWCastDeviceModelName(void) {
    size_t size = 0;
    char machine[64] = {0};
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) == 0 && size > 0 && size < sizeof(machine) && sysctlbyname("hw.machine", machine, &size, NULL, 0) == 0) {
        NSString *identifier = [NSString stringWithUTF8String:machine];
        if ([identifier hasPrefix:@"iPad2,"]) return @"iPad 2";
        if ([identifier hasPrefix:@"iPad3,4"] || [identifier hasPrefix:@"iPad3,5"] || [identifier hasPrefix:@"iPad3,6"]) return @"iPad 4";
    }
    NSString *fallback = [[UIDevice currentDevice] name];
    return [fallback length] ? fallback : @"iPad";
}

typedef NS_ENUM(NSInteger, IWButtonKind) {
    IWButtonKindMenu = 1,
    IWButtonKindTheme,
    IWButtonKindHeart,
    IWButtonKindCrop,
    IWButtonKindClock,
    IWButtonKindMusic,
    IWButtonKindHome,
    IWButtonKindVideo,
    IWButtonKindCast,
    IWButtonKindDepth,
    IWButtonKindClose,
    IWButtonKindDown,
    IWButtonKindTop,
    IWButtonKindLocate,
    IWButtonKindReset,
    IWButtonKindCheck,
    IWButtonKindLanguage,
    IWButtonKindAdd,
    IWButtonKindEmpty,
    IWButtonKindPlay,
    IWButtonKindPause,
    IWButtonKindRewind,
    IWButtonKindForward,
    IWButtonKindDelete,
    IWButtonKindVolume,
    IWButtonKindMinimize,
    IWButtonKindLock,
    IWButtonKindMove,
    IWButtonKindDate,
    IWButtonKindSettings,
    IWButtonKindLab,
    IWButtonKindCalendar,
    IWButtonKindWeather,
    IWButtonKindThemeMenu
};

typedef NS_ENUM(NSInteger, IWWallpaperTransitionStyle) {
    IWWallpaperTransitionStyleSlide = 0,
    IWWallpaperTransitionStyleFade,
    IWWallpaperTransitionStyleFloat,
    IWWallpaperTransitionStyleFocus,
    IWWallpaperTransitionStyleDrift,
    IWWallpaperTransitionStyleLift
};

typedef NS_ENUM(NSInteger, IWEditTarget) {
    IWEditTargetNone = 0,
    IWEditTargetBackground,
    IWEditTargetClock,
    IWEditTargetDate,
    IWEditTargetCalendar,
    IWEditTargetWeather
};

static CGFloat IWControlSize(void) { return 46.0; }
static CGFloat IWControlRadius(void) { return IWControlSize() / 2.0; }
static CGFloat IWControlGap(void) { return 8.0; }
static CGFloat IWControlRightMargin(void) { return 22.0; }
static CGFloat IWControlBorderWidth(void) { return 1.65; }
static UIColor *IWThemePink(CGFloat alpha) { return [UIColor colorWithRed:1.0 green:73.0/255.0 blue:158.0/255.0 alpha:alpha]; }
static UIImage *IWDecodedThumbnail(NSDictionary *item) {
    UIImage *image = [UIImage imageWithContentsOfFile:[item objectForKey:@"thumbPath"]];
    if (!image) image = [UIImage imageWithContentsOfFile:[item objectForKey:@"imagePath"]];
    if (!image) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(480, 270), YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, 480, 270)];
    UIImage *decoded = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return decoded;
}

static void IWCacheThumbnail(NSCache *cache, UIImage *image, NSString *path) {
    if (!image || ![path length]) return;
    NSUInteger cost = CGImageGetBytesPerRow(image.CGImage) * CGImageGetHeight(image.CGImage);
    [cache setObject:image forKey:path cost:cost];
}

static NSCache *IWDigitSnapshotCache(void) {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
        cache.totalCostLimit = [NSProcessInfo processInfo].physicalMemory < 768ULL * 1024 * 1024 ? 2 * 1024 * 1024 : 8 * 1024 * 1024;
    });
    return cache;
}

static NSCalendar *IWDisplayCalendar(void) {
    // Month labels, the offline holiday table and the dated countdown all
    // describe the Gregorian calendar, independently of the system calendar.
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone localTimeZone];
    return calendar;
}

static NSDictionary *IWValidatedWeatherCache(id raw) {
    if (![raw isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *snapshot = raw;
    NSDictionary *ranges = @{
        @"temperature": @[@-100, @70], @"high": @[@-100, @70], @"low": @[@-100, @70],
        @"precipitationProbability": @[@0, @100], @"code": @[@0, @99], @"isDay": @[@0, @1],
        @"latitude": @[@-90, @90], @"longitude": @[@-180, @180]
    };
    for (NSString *key in ranges) {
        id value = [snapshot objectForKey:key];
        if (![value isKindOfClass:[NSNumber class]]) return nil;
        if (![key isEqualToString:@"isDay"] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
        double number = [value doubleValue];
        NSArray *range = [ranges objectForKey:key];
        if (!isfinite(number) || number < [range[0] doubleValue] || number > [range[1] doubleValue]) return nil;
        if (([key isEqualToString:@"code"] || [key isEqualToString:@"isDay"]) && floor(number) != number) return nil;
    }
    if (![[snapshot objectForKey:@"fetchedAt"] isKindOfClass:[NSDate class]]) return nil;
    if (![[snapshot objectForKey:@"provider"] isKindOfClass:[NSString class]]) return nil;
    return snapshot;
}
// 2026 offline holiday sets.  The selected calendar language also selects the
// matching regional set, so the display stays useful without a network API.
static NSDictionary *IWHolidaysForLanguage2026(NSInteger language) {
    static NSDictionary *sets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *regional = @{
            @0: @{@"1-1": @"New Year's Day", @"1-19": @"Martin Luther King Jr. Day", @"2-16": @"Presidents' Day", @"5-25": @"Memorial Day", @"6-19": @"Juneteenth", @"7-4": @"Independence Day", @"9-7": @"Labor Day", @"10-12": @"Indigenous Peoples' Day", @"11-11": @"Veterans Day", @"11-26": @"Thanksgiving", @"12-25": @"Christmas Day"},
            @1: @{@"1-1": @"元旦", @"2-17": @"春节", @"3-3": @"元宵节", @"4-5": @"清明节", @"5-1": @"劳动节", @"6-19": @"端午节", @"9-25": @"中秋节", @"10-1": @"国庆节"},
            @2: @{@"1-1": @"元旦", @"2-17": @"春節", @"2-28": @"和平紀念日", @"4-4": @"兒童節", @"4-5": @"清明節", @"6-19": @"端午節", @"9-25": @"中秋節", @"10-10": @"國慶日"},
            @3: @{@"1-1": @"元日", @"1-12": @"成人の日", @"2-11": @"建国記念の日", @"2-23": @"天皇誕生日", @"3-20": @"春分の日", @"4-29": @"昭和の日", @"5-3": @"憲法記念日", @"5-4": @"みどりの日", @"5-5": @"こどもの日", @"7-20": @"海の日", @"8-11": @"山の日", @"9-21": @"敬老の日", @"9-22": @"国民の休日", @"9-23": @"秋分の日", @"10-12": @"スポーツの日", @"11-3": @"文化の日", @"11-23": @"勤労感謝の日"}
        };
        NSDictionary *international = @{
            @0: @{@"2-14": @"Valentine's Day", @"3-8": @"International Women's Day", @"4-22": @"Earth Day", @"5-1": @"International Workers' Day", @"6-1": @"Children's Day", @"10-31": @"Halloween", @"12-25": @"Christmas Day"},
            @1: @{@"2-14": @"情人节", @"3-8": @"国际妇女节", @"4-22": @"世界地球日", @"6-1": @"儿童节", @"10-31": @"万圣节", @"12-25": @"圣诞节"},
            @2: @{@"2-14": @"情人節", @"3-8": @"國際婦女節", @"4-22": @"世界地球日", @"6-1": @"兒童節", @"10-31": @"萬聖節", @"12-25": @"聖誕節"},
            @3: @{@"2-14": @"バレンタインデー", @"3-8": @"国際女性デー", @"4-22": @"アースデイ", @"6-1": @"こどもの日", @"10-31": @"ハロウィン", @"12-25": @"クリスマス"}
        };
        NSMutableDictionary *merged = [NSMutableDictionary dictionary];
        for (NSNumber *language in regional) {
            NSMutableDictionary *holidays = [[international objectForKey:language] mutableCopy] ?: [NSMutableDictionary dictionary];
            [holidays addEntriesFromDictionary:[regional objectForKey:language]];
            [merged setObject:holidays forKey:language];
        }
        sets = merged;
    });
    return [sets objectForKey:[NSNumber numberWithInteger:language]] ?: @{};
}
static NSInteger IWCalendarFirstWeekdayForLanguage(NSInteger language) {
    // Chinese calendars conventionally start weeks on Monday; the current EN
    // and Japanese regional variants retain Sunday as their first column.
    return (language == 1 || language == 2) ? 2 : 1; // NSCalendar: Sunday=1
}
static NSArray *IWCalendarWeekdayTitlesForLanguage(NSInteger language) {
    NSArray *titles = language == 1 ? @[@"日", @"一", @"二", @"三", @"四", @"五", @"六"] :
                     (language == 2 ? @[@"日", @"一", @"二", @"三", @"四", @"五", @"六"] :
                     (language == 3 ? @[@"日", @"月", @"火", @"水", @"木", @"金", @"土"] : @[@"S", @"M", @"T", @"W", @"T", @"F", @"S"]));
    if (IWCalendarFirstWeekdayForLanguage(language) == 1) return titles;
    return @[[titles objectAtIndex:1], [titles objectAtIndex:2], [titles objectAtIndex:3], [titles objectAtIndex:4], [titles objectAtIndex:5], [titles objectAtIndex:6], [titles objectAtIndex:0]];
}
static BOOL IWColorIsThemePink(UIColor *color) {
    CGFloat r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    return color &&
        [color getRed:&r green:&g blue:&b alpha:&a] &&
        a > 0.55 &&
        fabs(r - 1.0) < 0.08 &&
        fabs(g - 73.0/255.0) < 0.08 &&
        fabs(b - 158.0/255.0) < 0.10;
}
static char IWButtonPulseActiveKey;
static void IWFlashButtonPulse(UIButton *button) {
    if (!button || !button.superview || UIAccessibilityIsReduceMotionEnabled()) return;
    // Touch-down and the action callback can both request feedback for the
    // same press. Capturing an already scaled transform would leave it shrunk.
    if (objc_getAssociatedObject(button, &IWButtonPulseActiveKey)) return;
    objc_setAssociatedObject(button, &IWButtonPulseActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGAffineTransform originalTransform = button.transform;
    BOOL activePink = IWColorIsThemePink(button.backgroundColor);
    UIColor *pulseColor = activePink ? [UIColor whiteColor] : IWThemePink(1.0);
    CGRect pulseFrame = CGRectInset(button.frame, -6.0, -6.0);
    UIView *pulse = [[UIView alloc] initWithFrame:pulseFrame];
    pulse.userInteractionEnabled = NO;
    pulse.backgroundColor = [pulseColor colorWithAlphaComponent:(activePink ? 0.38 : 0.48)];
    pulse.layer.cornerRadius = pulseFrame.size.width / 2.0;
    pulse.layer.borderWidth = 2.8;
    pulse.layer.borderColor = [[pulseColor colorWithAlphaComponent:(activePink ? 0.96 : 1.0)] CGColor];
    pulse.layer.shadowColor = [pulseColor CGColor];
    pulse.layer.shadowOpacity = activePink ? 0.92 : 1.0;
    pulse.layer.shadowRadius = activePink ? 10.0 : 12.0;
    pulse.layer.shadowOffset = CGSizeZero;
    [button.superview insertSubview:pulse belowSubview:button];

    UIView *halo = [[UIView alloc] initWithFrame:CGRectInset(button.frame, -2.0, -2.0)];
    halo.userInteractionEnabled = NO;
    halo.backgroundColor = [pulseColor colorWithAlphaComponent:(activePink ? 0.34 : 0.42)];
    halo.layer.cornerRadius = halo.bounds.size.width / 2.0;
    halo.alpha = 0.0;
    [button.superview insertSubview:halo belowSubview:button];

    pulse.transform = CGAffineTransformMakeScale(0.72, 0.72);
    pulse.alpha = 0.0;
    button.transform = CGAffineTransformScale(originalTransform, 0.95, 0.95);
    [UIView animateKeyframesWithDuration:0.42 delay:0.0 options:UIViewKeyframeAnimationOptionBeginFromCurrentState animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.24 animations:^{
            pulse.alpha = 1.0;
            halo.alpha = 1.0;
            button.transform = CGAffineTransformScale(originalTransform, 0.93, 0.93);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.14 relativeDuration:0.86 animations:^{
            pulse.alpha = 0.0;
            halo.alpha = 0.0;
            pulse.transform = CGAffineTransformMakeScale(1.16, 1.16);
            halo.transform = CGAffineTransformMakeScale(1.04, 1.04);
            button.transform = originalTransform;
        }];
    } completion:^(BOOL finished) {
        [pulse removeFromSuperview];
        [halo removeFromSuperview];
        button.transform = originalTransform;
        objc_setAssociatedObject(button, &IWButtonPulseActiveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

static void IWCallPrivateVoidFunction(const char *frameworkPath, const char *symbolName) {
    void *handle = dlopen(frameworkPath, RTLD_LAZY);
    void (*fn)(void) = handle ? (void (*)(void))dlsym(handle, symbolName) : NULL;
    if (fn) fn();
    if (handle) dlclose(handle);
}

static void IWSetBackBoardBacklight(CGFloat value, CGFloat duration) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
    void (*fn)(float, float) = handle ? (void (*)(float, float))dlsym(handle, "BKSHIDServicesSetBacklightFactorWithFadeDuration") : NULL;
    if (fn) fn((float)value, (float)duration);
    if (handle) dlclose(handle);
}

static void IWSetBackBoardScreenBlanked(BOOL blanked) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
    void (*fn)(int) = handle ? (void (*)(int))dlsym(handle, "_BKSDisplaySetScreenBlanked") : NULL;
    if (fn) fn(blanked ? 1 : 0);
    if (handle) dlclose(handle);
}

static BOOL IWSendHardwareLockButtonPress(void) {
    void *graphics = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    void *springboard = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    void (*sendSimple)(int, mach_port_t) = graphics ? (void (*)(int, mach_port_t))dlsym(graphics, "GSSendSimpleEvent") : NULL;
    mach_port_name_t (*purplePort)(void) = graphics ? (mach_port_name_t (*)(void))dlsym(graphics, "GSGetPurpleSystemEventPort") : NULL;
    mach_port_t (*springboardPort)(void) = springboard ? (mach_port_t (*)(void))dlsym(springboard, "SBSSpringBoardServerPort") : NULL;
    mach_port_t port = purplePort ? purplePort() : (springboardPort ? springboardPort() : MACH_PORT_NULL);
    BOOL sent = NO;
    if (sendSimple && port != MACH_PORT_NULL) {
        sendSimple(1010, port);
        usleep(120000);
        sendSimple(1011, port);
        sent = YES;
    }
    if (graphics) dlclose(graphics);
    if (springboard) dlclose(springboard);
    return sent;
}

static NSInteger const IWPowerConnectTag = 2004;
static NSInteger const IWPowerDisconnectTag = 2005;
static NSInteger const IWGTA6CountdownTag = 2006;
static NSInteger const IWWallpaperTransitionTag = 2007;
static NSString * const IWPowerPrefsPath = @"/var/mobile/Library/Preferences/com.rex.wizardpower.plist";
static NSString * const IWLegacyPowerPrefsPath = @"/var/mobile/Library/Preferences/com.rex.wizardsystem.power.plist";
static void IWPostWizardPowerNotification(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, true);
}
static CFStringRef const IWWizardPowerLockRequestNotification = CFSTR("com.rex.wizardpower.request-lock");
static CFStringRef const IWWizardPowerWakeRequestNotification = CFSTR("com.rex.wizardpower.request-wake");
static CGFloat IWClockScaleMin(void) { return 0.35; }
static CGFloat IWClockScaleMax(void) { return 1.60; }
static CGFloat IWDateScaleMin(void) { return 0.4808752; }
static CGFloat IWDateScaleMax(void) { return 1.45; }
static CGFloat IWCalendarScaleMin(void) { return 0.65; }
static CGFloat IWCalendarScaleMax(void) { return 1.65; }
static CGFloat IWWeatherScaleMin(void) { return 0.65; }
static CGFloat IWWeatherScaleMax(void) { return 1.65; }
static NSTimeInterval IWPanelAnimationDuration(void) { return UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.24; }
static CGFloat IWPanelSpringDamping(void) { return 0.78; }
static CGFloat IWSystemGestureEdgeInset(void) { return 56.0; }
static CGFloat IWClockDefaultOffsetX(void) { return 0.0; }
static CGFloat IWClockDefaultOffsetY(void) { return 0.0; }
static CGFloat IWClockDefaultScale(void) { return 1.0; }
static CGFloat IWDateDefaultOffsetX(void) { return 0.0; }
static CGFloat IWDateDefaultOffsetY(void) { return 0.0; }
static CGFloat IWDateDefaultScale(void) { return 1.0; }
static CGFloat IWDigitCardDefaultOpacity(void) { return 0.50; }
static CGFloat IWEditDragGain(void) { return 1.25; }
static CGFloat IWDigitCardClampOpacity(CGFloat opacity) {
    opacity = MAX(0.20, MIN(0.90, opacity));
    opacity = round(opacity * 10.0) / 10.0;
    return MAX(0.20, MIN(0.90, opacity));
}

static UIFont *IWGTAFont(CGFloat size) {
    NSArray *names = @[
        @"AvenirNextCondensed-Heavy",
        @"AvenirNextCondensed-DemiBold",
        @"HelveticaNeue-CondensedBlack",
        @"DINCondensed-Bold",
        @"Impact"
    ];
    for (NSString *name in names) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return [UIFont systemFontOfSize:size weight:UIFontWeightBlack];
}

static UIFont *IWGTATextFont(CGFloat size) {
    NSArray *names = @[
        @"AvenirNextCondensed-DemiBold",
        @"DINCondensed-Bold",
        @"HelveticaNeue-CondensedBold",
        @"AvenirNextCondensed-Heavy"
    ];
    for (NSString *name in names) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static NSString *IWLocalWiFiAddress(void) {
    struct ifaddrs *interfaces = NULL;
    NSString *address = @"0.0.0.0";
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *cursor = interfaces; cursor; cursor = cursor->ifa_next) {
            if (!cursor->ifa_addr || cursor->ifa_addr->sa_family != AF_INET) continue;
            if (!(cursor->ifa_flags & IFF_UP) || (cursor->ifa_flags & IFF_LOOPBACK)) continue;
            NSString *name = [NSString stringWithUTF8String:cursor->ifa_name ?: ""];
            if (![name hasPrefix:@"en"] && ![name hasPrefix:@"bridge"]) continue;
            char buffer[INET_ADDRSTRLEN];
            struct sockaddr_in *addr = (struct sockaddr_in *)cursor->ifa_addr;
            if (inet_ntop(AF_INET, &addr->sin_addr, buffer, sizeof(buffer))) {
                address = [NSString stringWithUTF8String:buffer];
                break;
            }
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

static NSString *IWXMLUnescape(NSString *value) {
    if (![value length]) return @"";
    NSMutableString *s = [value mutableCopy];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"&lt;" withString:@"<" options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"&gt;" withString:@">" options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"&apos;" withString:@"'" options:0 range:NSMakeRange(0, [s length])];
    return s;
}

static NSString *IWXMLValue(NSString *body, NSString *tag) {
    if (![body length] || ![tag length]) return nil;
    NSString *open = [NSString stringWithFormat:@"<%@>", tag];
    NSString *close = [NSString stringWithFormat:@"</%@>", tag];
    NSRange start = [body rangeOfString:open options:NSCaseInsensitiveSearch];
    if (start.location == NSNotFound) return nil;
    NSUInteger valueStart = NSMaxRange(start);
    NSRange search = NSMakeRange(valueStart, [body length] - valueStart);
    NSRange end = [body rangeOfString:close options:NSCaseInsensitiveSearch range:search];
    if (end.location == NSNotFound || end.location < valueStart) return nil;
    return IWXMLUnescape([body substringWithRange:NSMakeRange(valueStart, end.location - valueStart)]);
}

static NSTimeInterval IWSecondsFromCMTimeSafe(CMTime time) {
    if (!CMTIME_IS_NUMERIC(time) || CMTIME_IS_INDEFINITE(time) || CMTIME_IS_INVALID(time)) return 0.0;
    Float64 seconds = CMTimeGetSeconds(time);
    if (!isfinite(seconds) || seconds < 0) return 0.0;
    return seconds;
}

static NSTimeInterval IWSecondsSafe(NSTimeInterval seconds) {
    if (!isfinite(seconds) || seconds < 0) return 0.0;
    return seconds;
}

static CGFloat IWFloatSafe(CGFloat value) {
    if (!isfinite(value)) return 0.0;
    return value;
}


static NSString *IWXMLFirstElementValue(NSString *body, NSString *tag) {
    if (![body length] || ![tag length]) return nil;
    NSString *openNeedle = [NSString stringWithFormat:@"<%@", tag];
    NSRange start = [body rangeOfString:openNeedle options:NSCaseInsensitiveSearch];
    if (start.location == NSNotFound) return nil;
    NSRange openEnd = [body rangeOfString:@">" options:0 range:NSMakeRange(start.location, [body length] - start.location)];
    if (openEnd.location == NSNotFound) return nil;
    NSUInteger valueStart = NSMaxRange(openEnd);
    NSString *close = [NSString stringWithFormat:@"</%@>", tag];
    NSRange end = [body rangeOfString:close options:NSCaseInsensitiveSearch range:NSMakeRange(valueStart, [body length] - valueStart)];
    if (end.location == NSNotFound || end.location < valueStart) return nil;
    return IWXMLUnescape([body substringWithRange:NSMakeRange(valueStart, end.location - valueStart)]);
}

static NSString *IWHeaderValue(NSString *request, NSString *header) {
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSString *prefix = [[header stringByAppendingString:@":"] lowercaseString];
    for (NSString *line in lines) {
        if ([[line lowercaseString] hasPrefix:prefix]) {
            return [[line substringFromIndex:[prefix length]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return nil;
}

static CGSize IWMetadataResolution(NSString *body) {
    if (![body length]) return CGSizeZero;
    NSString *decoded = IWXMLUnescape(body);
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"resolution=[\\\"']([0-9]+)x([0-9]+)[\\\"']" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:decoded options:0 range:NSMakeRange(0, [decoded length])];
    if (!match || [match numberOfRanges] < 3) return CGSizeZero;
    CGFloat w = [[decoded substringWithRange:[match rangeAtIndex:1]] floatValue];
    CGFloat h = [[decoded substringWithRange:[match rangeAtIndex:2]] floatValue];
    return CGSizeMake(w, h);
}

static BOOL IWRemoteResolutionSupported(CGSize size) {
    if (CGSizeEqualToSize(size, CGSizeZero)) return YES;
    CGFloat maxSide = MAX(size.width, size.height);
    CGFloat minSide = MIN(size.width, size.height);
    return maxSide <= 1920.0 && minSide <= 1080.0;
}

static void IWCastLog(NSString *format, ...) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) return;
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body ?: @""];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/wizardcast.log"];
    if (!handle) {
        [line writeToFile:@"/tmp/wizardcast.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

@interface IWDLNACastRunContext : NSObject
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL httpReady;
@property (nonatomic, assign) BOOL ssdpReady;
@property (nonatomic, assign) NSUInteger workerCount;
@property (nonatomic, assign) int lastHTTPError;
@property (nonatomic, assign) int lastSSDPError;
// These timer fields are read and written only on the main thread.
@property (nonatomic, strong) NSTimer *aliveTimer;
@property (nonatomic, assign) BOOL didSendAlive;
@end

@implementation IWDLNACastRunContext
@end

static void IWCloseOwnedCastSocket(int *descriptor) {
    int socketFD = *descriptor;
    *descriptor = -1;
    if (socketFD >= 0) close(socketFD);
}

@interface IWDLNACastServer : NSObject
@property (nonatomic, copy) void (^playURLHandler)(NSURL *url);
@property (nonatomic, copy) void (^stateChangedHandler)(BOOL ready, NSError *error);
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSUInteger httpPort;
- (instancetype)initWithHTTPPort:(NSUInteger)httpPort ssdpPort:(NSUInteger)ssdpPort bindAddress:(in_addr_t)bindAddress joinMulticast:(BOOL)joinMulticast;
- (BOOL)start;
- (void)stop;
- (void)debugInvalidateSockets;
- (void)httpLoopForRunContext:(IWDLNACastRunContext *)context;
- (void)ssdpLoopForRunContext:(IWDLNACastRunContext *)context;
- (void)workerFinishedForContext:(IWDLNACastRunContext *)context;
- (void)emitAliveNotificationsForContext:(IWDLNACastRunContext *)context;
@end

@implementation IWDLNACastServer {
    NSLock *_lifecycleLock;
    IWDLNACastRunContext *_currentRun;
    BOOL _desiredRunning;
    NSUInteger _nextGeneration;
    NSUInteger _stateRevision;
    void (^_stateChangedHandler)(BOOL ready, NSError *error);
    NSUInteger _httpPort;
    uint16_t _ssdpPort;
    in_addr_t _bindAddress;
    BOOL _joinMulticast;
    NSString *_uuid;
    NSString *_friendlyName;
}

@synthesize stateChangedHandler = _stateChangedHandler;

- (instancetype)init {
    return [self initWithHTTPPort:8199
                         ssdpPort:1900
                      bindAddress:htonl(INADDR_ANY)
                    joinMulticast:YES];
}

- (instancetype)initWithHTTPPort:(NSUInteger)httpPort
                       ssdpPort:(NSUInteger)ssdpPort
                    bindAddress:(in_addr_t)bindAddress
                  joinMulticast:(BOOL)joinMulticast {
    self = [super init];
    if (self) {
        _lifecycleLock = [[NSLock alloc] init];
        _httpPort = httpPort;
        _ssdpPort = (uint16_t)MIN(ssdpPort, UINT16_MAX);
        _bindAddress = bindAddress;
        _joinMulticast = joinMulticast;
        NSString *deviceName = IWCastDeviceModelName();
        NSString *deviceID = [[[[UIDevice currentDevice] identifierForVendor] UUIDString] lowercaseString];
        if (![deviceID length]) deviceID = @"8f0f9d66-5f5a-4ef9-9f54-wizardcast0001";
        _uuid = [@"uuid:" stringByAppendingString:deviceID];
        _friendlyName = [NSString stringWithFormat:@"Wizard Cast (%@)", deviceName];
    }
    return self;
}

- (void)setStateChangedHandler:(void (^)(BOOL ready, NSError *error))handler {
    [_lifecycleLock lock];
    _stateChangedHandler = [handler copy];
    [_lifecycleLock unlock];
}

- (void (^)(BOOL ready, NSError *error))stateChangedHandler {
    [_lifecycleLock lock];
    void (^handler)(BOOL ready, NSError *error) = [_stateChangedHandler copy];
    [_lifecycleLock unlock];
    return handler;
}

- (BOOL)isReadyLockedForContext:(IWDLNACastRunContext *)context {
    return context && _desiredRunning && _currentRun == context &&
           !context.cancelled && context.httpReady && context.ssdpReady;
}

- (BOOL)running {
    [_lifecycleLock lock];
    BOOL ready = [self isReadyLockedForContext:_currentRun];
    [_lifecycleLock unlock];
    return ready;
}

- (NSUInteger)httpPort { return _httpPort; }

- (IWDLNACastRunContext *)newRunContextLocked {
    IWDLNACastRunContext *context = [[IWDLNACastRunContext alloc] init];
    context.generation = ++_nextGeneration;
    context.workerCount = 2;
    _currentRun = context;
    return context;
}

- (void)launchWorkersForContext:(IWDLNACastRunContext *)context {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self httpLoopForRunContext:context];
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self ssdpLoopForRunContext:context];
    });
}

- (BOOL)shouldContinueRunContext:(IWDLNACastRunContext *)context {
    [_lifecycleLock lock];
    BOOL current = _desiredRunning && _currentRun == context && !context.cancelled;
    [_lifecycleLock unlock];
    return current;
}

- (BOOL)isReadyForRunContext:(IWDLNACastRunContext *)context {
    [_lifecycleLock lock];
    BOOL ready = [self isReadyLockedForContext:context];
    [_lifecycleLock unlock];
    return ready;
}

- (void)cancelAliveTimerForContext:(IWDLNACastRunContext *)context {
    if (!context) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cancelAliveTimerForContext:context];
        });
        return;
    }
    [context.aliveTimer invalidate];
    context.aliveTimer = nil;
    context.didSendAlive = NO;
}

- (void)scheduleAliveTimerForContext:(IWDLNACastRunContext *)context delay:(NSTimeInterval)delay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scheduleAliveTimerForContext:context delay:delay];
        });
        return;
    }
    if (context.aliveTimer || ![self isReadyForRunContext:context]) return;
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay
                                             target:self
                                           selector:@selector(aliveTimerDidFire:)
                                           userInfo:context
                                            repeats:NO];
    context.aliveTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)publishStateForContext:(IWDLNACastRunContext *)context
                      revision:(NSUInteger)revision
                         error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^handler)(BOOL ready, NSError *error) = nil;
        BOOL ready = NO;
        [_lifecycleLock lock];
        BOOL currentRevision = (_stateRevision == revision);
        ready = [self isReadyLockedForContext:_currentRun];
        if (currentRevision) handler = [_stateChangedHandler copy];
        [_lifecycleLock unlock];
        if (!currentRevision) return;

        if (context) {
            if (ready && [self isReadyForRunContext:context]) {
                [self scheduleAliveTimerForContext:context delay:(context.didSendAlive ? 25.0 : 0.7)];
            } else {
                [self cancelAliveTimerForContext:context];
            }
        }
        if (handler) handler(ready, error);
    });
}

- (NSError *)socketError:(int)socketError transport:(NSString *)transport {
    if (socketError <= 0) return nil;
    NSString *description = [NSString stringWithFormat:@"%@ socket operation failed (%d)", transport, socketError];
    return [NSError errorWithDomain:@"IWDLNACastServerErrorDomain"
                               code:socketError
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)setHTTPReady:(BOOL)ready error:(int)socketError context:(IWDLNACastRunContext *)context {
    [self setTransportReady:ready isHTTP:YES error:socketError context:context];
}

- (void)setSSDPReady:(BOOL)ready error:(int)socketError context:(IWDLNACastRunContext *)context {
    [self setTransportReady:ready isHTTP:NO error:socketError context:context];
}

- (void)setTransportReady:(BOOL)ready
                   isHTTP:(BOOL)isHTTP
                    error:(int)socketError
                  context:(IWDLNACastRunContext *)context {
    NSUInteger revision = 0;
    NSError *reportedError = nil;
    BOOL shouldPublish = NO;
    [_lifecycleLock lock];
    if (_currentRun != context || context.cancelled || !_desiredRunning) {
        [_lifecycleLock unlock];
        return;
    }
    BOOL wasReady = [self isReadyLockedForContext:context];
    int lastError = isHTTP ? context.lastHTTPError : context.lastSSDPError;
    BOOL errorChanged = NO;
    if (ready) {
        if (isHTTP) context.httpReady = YES;
        else context.ssdpReady = YES;
        errorChanged = (lastError != 0);
        if (isHTTP) context.lastHTTPError = 0;
        else context.lastSSDPError = 0;
    } else {
        if (isHTTP) context.httpReady = NO;
        else context.ssdpReady = NO;
        if (socketError > 0 && lastError != socketError) {
            if (isHTTP) context.lastHTTPError = socketError;
            else context.lastSSDPError = socketError;
            errorChanged = YES;
            reportedError = [self socketError:socketError transport:(isHTTP ? @"HTTP" : @"SSDP")];
        }
    }
    int activeError = context.lastHTTPError ? context.lastHTTPError : context.lastSSDPError;
    if (activeError > 0) {
        NSString *transport = context.lastHTTPError ? @"HTTP" : @"SSDP";
        reportedError = [self socketError:activeError transport:transport];
    } else {
        reportedError = nil;
    }
    BOOL nowReady = [self isReadyLockedForContext:context];
    if (wasReady != nowReady || errorChanged) {
        revision = ++_stateRevision;
        shouldPublish = YES;
    }
    [_lifecycleLock unlock];
    if (shouldPublish) [self publishStateForContext:context revision:revision error:reportedError];
}

- (void)cancelContextLocked:(IWDLNACastRunContext *)context {
    context.cancelled = YES;
    context.httpReady = NO;
    context.ssdpReady = NO;
    context.lastHTTPError = 0;
    context.lastSSDPError = 0;
}

- (BOOL)start {
    IWDLNACastRunContext *context = nil;
    BOOL launch = NO;
    NSUInteger revision = 0;
    [_lifecycleLock lock];
    _desiredRunning = YES;
    if (_currentRun && !_currentRun.cancelled) {
        [_lifecycleLock unlock];
        return YES;
    }
    if (!_currentRun) {
        context = [self newRunContextLocked];
        launch = YES;
    } else {
        context = _currentRun; // A stopping context owns its workers until they exit.
    }
    revision = ++_stateRevision;
    [_lifecycleLock unlock];

    [self cancelAliveTimerForContext:context];
    [self publishStateForContext:context revision:revision error:nil];
    if (launch) [self launchWorkersForContext:context];
    return YES; // Accepted; readiness arrives asynchronously through stateChangedHandler.
}

- (void)stop {
    IWDLNACastRunContext *context = nil;
    NSUInteger revision = 0;
    [_lifecycleLock lock];
    if (!_desiredRunning && !_currentRun) {
        [_lifecycleLock unlock];
        return;
    }
    _desiredRunning = NO;
    context = _currentRun;
    if (context && !context.cancelled) [self cancelContextLocked:context];
    revision = ++_stateRevision;
    [_lifecycleLock unlock];

    [self cancelAliveTimerForContext:context];
    [self publishStateForContext:context revision:revision error:nil];
}

- (void)debugInvalidateSockets {
    IWDLNACastRunContext *context = nil;
    NSUInteger revision = 0;
    [_lifecycleLock lock];
    context = _currentRun;
    if (context && _desiredRunning && !context.cancelled) {
        [self cancelContextLocked:context];
        revision = ++_stateRevision;
    }
    [_lifecycleLock unlock];
    if (!revision) return;

    // Workers own their descriptors. Bounded select waits observe cancellation.
    [self cancelAliveTimerForContext:context];
    [self publishStateForContext:context revision:revision error:nil];
}

- (void)dealloc {
    [self stop];
}

- (NSString *)baseURL {
    return [NSString stringWithFormat:@"http://%@:%lu", IWLocalWiFiAddress(), (unsigned long)_httpPort];
}

- (NSString *)deviceDescription {
    NSString *base = [self baseURL];
    return [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?>"
            "<root xmlns=\"urn:schemas-upnp-org:device-1-0\">"
            "<specVersion><major>1</major><minor>0</minor></specVersion>"
            "<URLBase>%@/</URLBase>"
            "<device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>"
            "<friendlyName>%@</friendlyName><manufacturer>Behoss</manufacturer><modelName>WizardCast</modelName><UDN>%@</UDN>"
            "<serviceList>"
            "<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId><controlURL>/AVTransport/control</controlURL><eventSubURL>/AVTransport/event</eventSubURL><SCPDURL>/AVTransport.xml</SCPDURL></service>"
            "<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId><controlURL>/RenderingControl/control</controlURL><eventSubURL>/RenderingControl/event</eventSubURL><SCPDURL>/RenderingControl.xml</SCPDURL></service>"
            "<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId><controlURL>/ConnectionManager/control</controlURL><eventSubURL>/ConnectionManager/event</eventSubURL><SCPDURL>/ConnectionManager.xml</SCPDURL></service>"
            "</serviceList></device></root>", base, _friendlyName, _uuid];
}

- (NSString *)serviceDescription:(NSString *)kind {
    NSString *actions = @"";
    if ([kind isEqualToString:@"AVTransport"]) {
        actions =
        @"<action><name>SetAVTransportURI</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>CurrentURI</name><direction>in</direction><relatedStateVariable>AVTransportURI</relatedStateVariable></argument><argument><name>CurrentURIMetaData</name><direction>in</direction><relatedStateVariable>AVTransportURIMetaData</relatedStateVariable></argument></argumentList></action>"
        "<action><name>SetNextAVTransportURI</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>NextURI</name><direction>in</direction><relatedStateVariable>NextAVTransportURI</relatedStateVariable></argument><argument><name>NextURIMetaData</name><direction>in</direction><relatedStateVariable>NextAVTransportURIMetaData</relatedStateVariable></argument></argumentList></action>"
        "<action><name>Play</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>Speed</name><direction>in</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument></argumentList></action>"
        "<action><name>Pause</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument></argumentList></action>"
        "<action><name>Stop</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument></argumentList></action>"
        "<action><name>Seek</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>Unit</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekMode</relatedStateVariable></argument><argument><name>Target</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekTarget</relatedStateVariable></argument></argumentList></action>"
        "<action><name>GetTransportInfo</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>CurrentTransportState</name><direction>out</direction><relatedStateVariable>TransportState</relatedStateVariable></argument><argument><name>CurrentTransportStatus</name><direction>out</direction><relatedStateVariable>TransportStatus</relatedStateVariable></argument><argument><name>CurrentSpeed</name><direction>out</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument></argumentList></action>"
        "<action><name>GetPositionInfo</name><argumentList><argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument><argument><name>Track</name><direction>out</direction><relatedStateVariable>CurrentTrack</relatedStateVariable></argument><argument><name>TrackDuration</name><direction>out</direction><relatedStateVariable>CurrentTrackDuration</relatedStateVariable></argument><argument><name>TrackMetaData</name><direction>out</direction><relatedStateVariable>CurrentTrackMetaData</relatedStateVariable></argument><argument><name>TrackURI</name><direction>out</direction><relatedStateVariable>CurrentTrackURI</relatedStateVariable></argument><argument><name>RelTime</name><direction>out</direction><relatedStateVariable>RelativeTimePosition</relatedStateVariable></argument><argument><name>AbsTime</name><direction>out</direction><relatedStateVariable>AbsoluteTimePosition</relatedStateVariable></argument><argument><name>RelCount</name><direction>out</direction><relatedStateVariable>RelativeCounterPosition</relatedStateVariable></argument><argument><name>AbsCount</name><direction>out</direction><relatedStateVariable>AbsoluteCounterPosition</relatedStateVariable></argument></argumentList></action>";
    } else if ([kind isEqualToString:@"ConnectionManager"]) {
        actions = @"<action><name>GetProtocolInfo</name><argumentList><argument><name>Source</name><direction>out</direction><relatedStateVariable>SourceProtocolInfo</relatedStateVariable></argument><argument><name>Sink</name><direction>out</direction><relatedStateVariable>SinkProtocolInfo</relatedStateVariable></argument></argumentList></action><action><name>GetCurrentConnectionIDs</name><argumentList><argument><name>ConnectionIDs</name><direction>out</direction><relatedStateVariable>CurrentConnectionIDs</relatedStateVariable></argument></argumentList></action><action><name>GetCurrentConnectionInfo</name><argumentList><argument><name>ConnectionID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable></argument><argument><name>RcsID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_RcsID</relatedStateVariable></argument><argument><name>AVTransportID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_AVTransportID</relatedStateVariable></argument><argument><name>ProtocolInfo</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_ProtocolInfo</relatedStateVariable></argument><argument><name>PeerConnectionManager</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_ConnectionManager</relatedStateVariable></argument><argument><name>PeerConnectionID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable></argument><argument><name>Direction</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_Direction</relatedStateVariable></argument><argument><name>Status</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_ConnectionStatus</relatedStateVariable></argument></argumentList></action>";
    } else {
        actions = @"<action><name>GetVolume</name></action><action><name>SetVolume</name></action><action><name>GetMute</name></action><action><name>SetMute</name></action>";
    }
    return [NSString stringWithFormat:@"<?xml version=\"1.0\"?><scpd xmlns=\"urn:schemas-upnp-org:service-1-0\"><specVersion><major>1</major><minor>0</minor></specVersion><actionList>%@</actionList><serviceStateTable><stateVariable sendEvents=\"no\"><name>A_ARG_TYPE_InstanceID</name><dataType>ui4</dataType></stateVariable><stateVariable sendEvents=\"yes\"><name>TransportState</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>TransportStatus</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>TransportPlaySpeed</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>AVTransportURI</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>AVTransportURIMetaData</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>NextAVTransportURI</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>NextAVTransportURIMetaData</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>CurrentTrack</name><dataType>ui4</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>CurrentTrackDuration</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>CurrentTrackMetaData</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>CurrentTrackURI</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>RelativeTimePosition</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>AbsoluteTimePosition</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>RelativeCounterPosition</name><dataType>i4</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>AbsoluteCounterPosition</name><dataType>i4</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>SourceProtocolInfo</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>SinkProtocolInfo</name><dataType>string</dataType></stateVariable><stateVariable sendEvents=\"no\"><name>CurrentConnectionIDs</name><dataType>string</dataType></stateVariable></serviceStateTable></scpd>", actions];
}

- (NSData *)httpResponseWithStatus:(NSString *)status type:(NSString *)type body:(NSString *)body extraHeaders:(NSString *)extra {
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *headers = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\n%@\r\n", status, type, (unsigned long)[bodyData length], extra ?: @""];
    NSMutableData *data = [NSMutableData dataWithData:[headers dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:bodyData];
    return data;
}

- (NSString *)soapEnvelope:(NSString *)body {
    return [NSString stringWithFormat:@"<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>%@</s:Body></s:Envelope>", body ?: @""];
}

- (void)handleSOAPBody:(NSString *)body {
    NSString *uri = IWXMLValue(body, @"CurrentURI");
    if (![uri length]) uri = IWXMLValue(body, @"NextURI");
    if (![uri length]) uri = IWXMLFirstElementValue(body, @"res");
    if ([uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"]) {
        CGSize resolution = IWMetadataResolution(body);
        if (!IWRemoteResolutionSupported(resolution)) {
            IWCastLog(@"reject unsupported resolution %.0fx%.0f uri %@", resolution.width, resolution.height, uri);
            return;
        }
        if (!CGSizeEqualToSize(resolution, CGSizeZero)) {
            IWCastLog(@"accept resolution %.0fx%.0f", resolution.width, resolution.height);
        }
        IWCastLog(@"play uri %@", uri);
        NSURL *url = [NSURL URLWithString:uri];
        if (url && self.playURLHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.playURLHandler) self.playURLHandler(url);
            });
        }
    }
}

- (NSData *)responseForRequest:(NSString *)request {
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSString *first = [lines count] ? [lines objectAtIndex:0] : @"";
    NSArray *parts = [first componentsSeparatedByString:@" "];
    NSString *method = [parts count] > 0 ? [parts objectAtIndex:0] : @"";
    NSString *path = [parts count] > 1 ? [parts objectAtIndex:1] : @"/";
    IWCastLog(@"http %@ %@ soap=%@", method, path, IWHeaderValue(request, @"SOAPAction") ?: @"");
    NSRange bodyRange = [request rangeOfString:@"\r\n\r\n"];
    NSString *body = bodyRange.location == NSNotFound ? @"" : [request substringFromIndex:NSMaxRange(bodyRange)];
    if ([body length]) {
        NSString *shortBody = [body length] > 900 ? [[body substringToIndex:900] stringByAppendingString:@"..."] : body;
        IWCastLog(@"body %@", shortBody);
    }
    if ([method isEqualToString:@"SUBSCRIBE"]) {
        NSString *sid = [NSString stringWithFormat:@"uuid:%@", [[NSUUID UUID] UUIDString]];
        NSString *headers = [NSString stringWithFormat:@"SID: %@\r\nTIMEOUT: Second-1800\r\n", sid];
        return [self httpResponseWithStatus:@"200 OK" type:@"text/plain" body:@"" extraHeaders:headers];
    }
    if ([method isEqualToString:@"UNSUBSCRIBE"]) {
        return [self httpResponseWithStatus:@"200 OK" type:@"text/plain" body:@"" extraHeaders:nil];
    }
    if ([method isEqualToString:@"GET"] && ([path isEqualToString:@"/description.xml"] || [path isEqualToString:@"/"])) return [self httpResponseWithStatus:@"200 OK" type:@"text/xml; charset=\"utf-8\"" body:[self deviceDescription] extraHeaders:nil];
    if ([method isEqualToString:@"GET"] && [path rangeOfString:@"AVTransport"].location != NSNotFound) return [self httpResponseWithStatus:@"200 OK" type:@"text/xml; charset=\"utf-8\"" body:[self serviceDescription:@"AVTransport"] extraHeaders:nil];
    if ([method isEqualToString:@"GET"] && [path rangeOfString:@"ConnectionManager"].location != NSNotFound) return [self httpResponseWithStatus:@"200 OK" type:@"text/xml; charset=\"utf-8\"" body:[self serviceDescription:@"ConnectionManager"] extraHeaders:nil];
    if ([method isEqualToString:@"GET"] && [path rangeOfString:@"RenderingControl"].location != NSNotFound) return [self httpResponseWithStatus:@"200 OK" type:@"text/xml; charset=\"utf-8\"" body:[self serviceDescription:@"RenderingControl"] extraHeaders:nil];
    if ([method isEqualToString:@"POST"]) {
        [self handleSOAPBody:body];
        NSString *soapBody = @"<u:Response xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"></u:Response>";
        if ([body rangeOfString:@"GetProtocolInfo" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetProtocolInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:ConnectionManager:1\"><Source></Source><Sink>http-get:*:video/mp4:*,http-get:*:application/vnd.apple.mpegurl:*,http-get:*:*:*</Sink></u:GetProtocolInfoResponse>";
        else if ([body rangeOfString:@"GetCurrentConnectionIDs" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetCurrentConnectionIDsResponse xmlns:u=\"urn:schemas-upnp-org:service:ConnectionManager:1\"><ConnectionIDs>0</ConnectionIDs></u:GetCurrentConnectionIDsResponse>";
        else if ([body rangeOfString:@"GetCurrentConnectionInfo" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetCurrentConnectionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:ConnectionManager:1\"><RcsID>0</RcsID><AVTransportID>0</AVTransportID><ProtocolInfo>http-get:*:*:*</ProtocolInfo><PeerConnectionManager></PeerConnectionManager><PeerConnectionID>-1</PeerConnectionID><Direction>Input</Direction><Status>OK</Status></u:GetCurrentConnectionInfoResponse>";
        else if ([body rangeOfString:@"GetTransportInfo" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetTransportInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><CurrentTransportState>PLAYING</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed></u:GetTransportInfoResponse>";
        else if ([body rangeOfString:@"GetPositionInfo" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><Track>1</Track><TrackDuration>00:00:00</TrackDuration><TrackMetaData></TrackMetaData><TrackURI></TrackURI><RelTime>00:00:00</RelTime><AbsTime>00:00:00</AbsTime><RelCount>0</RelCount><AbsCount>0</AbsCount></u:GetPositionInfoResponse>";
        else if ([body rangeOfString:@"GetVolume" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><CurrentVolume>60</CurrentVolume></u:GetVolumeResponse>";
        else if ([body rangeOfString:@"GetMute" options:NSCaseInsensitiveSearch].location != NSNotFound) soapBody = @"<u:GetMuteResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><CurrentMute>0</CurrentMute></u:GetMuteResponse>";
        return [self httpResponseWithStatus:@"200 OK" type:@"text/xml; charset=\"utf-8\"" body:[self soapEnvelope:soapBody] extraHeaders:@"EXT:\r\n"];
    }
    return [self httpResponseWithStatus:@"404 Not Found" type:@"text/plain" body:@"Not Found" extraHeaders:nil];
}

- (int)waitForReadableSocket:(int)socketFD {
    if (socketFD < 0 || socketFD >= FD_SETSIZE) {
        errno = EINVAL;
        return -1;
    }
    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(socketFD, &readSet);
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 200000;
    return select(socketFD + 1, &readSet, NULL, NULL, &timeout);
}

- (BOOL)waitBeforeRetryForContext:(IWDLNACastRunContext *)context {
    for (NSUInteger i = 0; i < 10; i++) {
        if (![self shouldContinueRunContext:context]) return NO;
        usleep(100000);
    }
    return [self shouldContinueRunContext:context];
}

- (void)handleHTTPClient:(int)client context:(IWDLNACastRunContext *)context {
    @autoreleasepool {
        NSError *transportError = nil;
        if (IWHTTPPrepareAcceptedSocket(client, &transportError) &&
            [self shouldContinueRunContext:context]) {
            NSData *requestData = IWHTTPReadRequest(client, 5.0, &transportError);
            NSString *request = requestData ? [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding] : nil;
            if (request && [self shouldContinueRunContext:context]) {
                NSData *response = [self responseForRequest:request];
                if ([self shouldContinueRunContext:context]) {
                    IWHTTPSendData(client, response, 5.0, &transportError);
                }
            }
        }
        if (transportError) IWCastLog(@"http client rejected domain=%@ code=%ld", transportError.domain, (long)transportError.code);
    }
}

- (void)httpLoopForRunContext:(IWDLNACastRunContext *)context {
    @autoreleasepool {
        int listeningSocket = -1;
        @try {
            while ([self shouldContinueRunContext:context]) {
                listeningSocket = socket(AF_INET, SOCK_STREAM, 0);
                if (listeningSocket < 0) {
                    int socketError = errno;
                    IWCastLog(@"http socket failed errno=%d; retry in 1s", socketError);
                    [self setHTTPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }
                if (![self shouldContinueRunContext:context]) {
                    IWCloseOwnedCastSocket(&listeningSocket);
                    break;
                }
                int flags = fcntl(listeningSocket, F_GETFL, 0);
                if (flags < 0 || fcntl(listeningSocket, F_SETFL, flags | O_NONBLOCK) < 0) {
                    int socketError = errno;
                    IWCloseOwnedCastSocket(&listeningSocket);
                    [self setHTTPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }
                int yes = 1;
                setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
                struct sockaddr_in addr;
                memset(&addr, 0, sizeof(addr));
                addr.sin_len = sizeof(addr);
                addr.sin_family = AF_INET;
                addr.sin_addr.s_addr = _bindAddress;
                addr.sin_port = htons((uint16_t)_httpPort);
                if (bind(listeningSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
                    listen(listeningSocket, 8) < 0) {
                    int socketError = errno;
                    IWCastLog(@"http bind/listen failed errno=%d; retry in 1s", socketError);
                    IWCloseOwnedCastSocket(&listeningSocket);
                    [self setHTTPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }

                [self setHTTPReady:YES error:0 context:context];
                IWCastLog(@"http listening port=%lu", (unsigned long)_httpPort);
                NSInteger acceptErrorCount = 0;
                BOOL retryListener = NO;
                while ([self shouldContinueRunContext:context]) {
                    int selected = [self waitForReadableSocket:listeningSocket];
                    if (selected == 0) continue;
                    if (selected < 0) {
                        int socketError = errno;
                        if (socketError == EINTR) continue;
                        acceptErrorCount += 1;
                        if (acceptErrorCount >= 3) {
                            [self setHTTPReady:NO error:socketError context:context];
                            retryListener = YES;
                            break;
                        }
                        continue;
                    }
                    if (![self shouldContinueRunContext:context]) break;
                    struct sockaddr_in clientAddr;
                    socklen_t len = sizeof(clientAddr);
                    int client = accept(listeningSocket, (struct sockaddr *)&clientAddr, &len);
                    if (client < 0) {
                        int socketError = errno;
                        // Repeated readable-but-empty sockets must not spin after
                        // an interrupted connection or a legacy-iOS resume.
                        acceptErrorCount += 1;
                        IWCastLog(@"http accept failed errno=%d count=%ld", socketError, (long)acceptErrorCount);
                        if (socketError == EBADF || socketError == EINVAL || socketError == ENOTSOCK || acceptErrorCount >= 3) {
                            [self setHTTPReady:NO error:socketError context:context];
                            retryListener = YES;
                            break;
                        }
                        usleep(10000);
                        continue;
                    }
                    acceptErrorCount = 0;
                    if (![self shouldContinueRunContext:context]) {
                        close(client);
                        break;
                    }
                    @try {
                        [self handleHTTPClient:client context:context];
                    } @finally {
                        close(client);
                    }
                }
                IWCloseOwnedCastSocket(&listeningSocket);
                if (![self shouldContinueRunContext:context]) break;
                if (retryListener) [self waitBeforeRetryForContext:context];
            }
        } @catch (NSException *exception) {
            IWCastLog(@"http worker exception %@", exception.name);
            [self setHTTPReady:NO error:EIO context:context];
        } @finally {
            IWCloseOwnedCastSocket(&listeningSocket);
            [self workerFinishedForContext:context];
        }
    }
}

- (NSString *)searchTargetFromMessage:(NSString *)message {
    NSArray *lines = [message componentsSeparatedByString:@"\r\n"];
    for (NSString *line in lines) {
        NSRange r = [line rangeOfString:@"ST:" options:NSCaseInsensitiveSearch];
        if (r.location == 0) return [[line substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"urn:schemas-upnp-org:device:MediaRenderer:1";
}

- (NSString *)ssdpResponseForST:(NSString *)st {
    NSString *target = [st length] ? st : @"urn:schemas-upnp-org:device:MediaRenderer:1";
    return [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: %@/description.xml\r\nSERVER: iOS/10.3 UPnP/1.0 WizardCast/0.1\r\nST: %@\r\nUSN: %@::%@\r\n\r\n", [self baseURL], target, _uuid, target];
}

- (void)ssdpLoopForRunContext:(IWDLNACastRunContext *)context {
    @autoreleasepool {
        int listeningSocket = -1;
        @try {
            while ([self shouldContinueRunContext:context]) {
                listeningSocket = socket(AF_INET, SOCK_DGRAM, 0);
                if (listeningSocket < 0) {
                    int socketError = errno;
                    IWCastLog(@"ssdp socket failed errno=%d; retry in 1s", socketError);
                    [self setSSDPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }
                if (![self shouldContinueRunContext:context]) {
                    IWCloseOwnedCastSocket(&listeningSocket);
                    break;
                }
                int flags = fcntl(listeningSocket, F_GETFL, 0);
                if (flags < 0 || fcntl(listeningSocket, F_SETFL, flags | O_NONBLOCK) < 0) {
                    int socketError = errno;
                    IWCloseOwnedCastSocket(&listeningSocket);
                    [self setSSDPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }
                int yes = 1;
                setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
                struct sockaddr_in addr;
                memset(&addr, 0, sizeof(addr));
                addr.sin_len = sizeof(addr);
                addr.sin_family = AF_INET;
                addr.sin_addr.s_addr = _bindAddress;
                addr.sin_port = htons(_ssdpPort);
                if (bind(listeningSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
                    int socketError = errno;
                    IWCastLog(@"ssdp bind failed errno=%d; retry in 1s", socketError);
                    IWCloseOwnedCastSocket(&listeningSocket);
                    [self setSSDPReady:NO error:socketError context:context];
                    [self waitBeforeRetryForContext:context];
                    continue;
                }
                if (_joinMulticast) {
                    struct ip_mreq mreq;
                    memset(&mreq, 0, sizeof(mreq));
                    mreq.imr_multiaddr.s_addr = inet_addr("239.255.255.250");
                    mreq.imr_interface.s_addr = htonl(INADDR_ANY);
                    if (setsockopt(listeningSocket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) < 0) {
                        int socketError = errno;
                        IWCastLog(@"ssdp multicast join failed errno=%d; retry in 1s", socketError);
                        IWCloseOwnedCastSocket(&listeningSocket);
                        [self setSSDPReady:NO error:socketError context:context];
                        [self waitBeforeRetryForContext:context];
                        continue;
                    }
                }

                [self setSSDPReady:YES error:0 context:context];
                IWCastLog(@"ssdp listening");
                NSInteger receiveErrorCount = 0;
                BOOL retryListener = NO;
                while ([self shouldContinueRunContext:context]) {
                    int selected = [self waitForReadableSocket:listeningSocket];
                    if (selected == 0) continue;
                    if (selected < 0) {
                        int socketError = errno;
                        if (socketError == EINTR) continue;
                        receiveErrorCount += 1;
                        if (receiveErrorCount >= 3) {
                            [self setSSDPReady:NO error:socketError context:context];
                            retryListener = YES;
                            break;
                        }
                        continue;
                    }
                    if (![self shouldContinueRunContext:context]) break;
                    char buffer[4096];
                    struct sockaddr_in from;
                    socklen_t fromLen = sizeof(from);
                    ssize_t received = recvfrom(listeningSocket, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&from, &fromLen);
                    if (received <= 0) {
                        int socketError = errno;
                        receiveErrorCount += 1;
                        IWCastLog(@"ssdp receive failed errno=%d count=%ld", socketError, (long)receiveErrorCount);
                        if (socketError == EBADF || socketError == EINVAL || socketError == ENOTSOCK || receiveErrorCount >= 3) {
                            [self setSSDPReady:NO error:socketError context:context];
                            retryListener = YES;
                            break;
                        }
                        usleep(10000);
                        continue;
                    }
                    receiveErrorCount = 0;
                    @autoreleasepool {
                        buffer[received] = 0;
                        NSString *msg = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)received encoding:NSUTF8StringEncoding];
                        if (![msg length]) continue;
                        if ([msg rangeOfString:@"M-SEARCH" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
                        if ([msg rangeOfString:@"MediaRenderer" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                            [msg rangeOfString:@"AVTransport" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                            [msg rangeOfString:@"RenderingControl" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                            [msg rangeOfString:@"ConnectionManager" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                            [msg rangeOfString:@"upnp:rootdevice" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                            [msg rangeOfString:@"ssdp:all" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
                        NSData *data = [[self ssdpResponseForST:[self searchTargetFromMessage:msg]] dataUsingEncoding:NSUTF8StringEncoding];
                        if ([self shouldContinueRunContext:context]) {
                            sendto(listeningSocket, [data bytes], [data length], 0, (struct sockaddr *)&from, fromLen);
                        }
                    }
                }
                IWCloseOwnedCastSocket(&listeningSocket);
                if (![self shouldContinueRunContext:context]) break;
                if (retryListener) [self waitBeforeRetryForContext:context];
            }
        } @catch (NSException *exception) {
            IWCastLog(@"ssdp worker exception %@", exception.name);
            [self setSSDPReady:NO error:EIO context:context];
        } @finally {
            IWCloseOwnedCastSocket(&listeningSocket);
            [self workerFinishedForContext:context];
        }
    }
}

- (void)workerFinishedForContext:(IWDLNACastRunContext *)context {
    IWDLNACastRunContext *nextContext = nil;
    NSUInteger revision = 0;
    BOOL publishStopped = NO;
    BOOL unexpectedExit = NO;
    [_lifecycleLock lock];
    if (_currentRun == context && context.workerCount > 0) {
        context.workerCount -= 1;
        if (context.workerCount > 0 && _desiredRunning && !context.cancelled) {
            // A failed worker must retire its peer before a replacement run.
            [self cancelContextLocked:context];
            revision = ++_stateRevision;
            unexpectedExit = YES;
        }
        if (context.workerCount == 0) {
            _currentRun = nil;
            if (_desiredRunning) {
                nextContext = [self newRunContextLocked];
                revision = ++_stateRevision;
            } else {
                publishStopped = YES;
                revision = _stateRevision;
            }
        }
    }
    [_lifecycleLock unlock];

    [self cancelAliveTimerForContext:context];
    if (unexpectedExit) {
        [self publishStateForContext:context revision:revision error:[self socketError:EIO transport:@"Cast"]];
    } else if (nextContext) {
        [self publishStateForContext:nextContext revision:revision error:nil];
        [self launchWorkersForContext:nextContext];
    } else if (publishStopped) {
        [self publishStateForContext:nil revision:revision error:nil];
    }
}

- (void)aliveTimerDidFire:(NSTimer *)timer {
    IWDLNACastRunContext *context = (IWDLNACastRunContext *)timer.userInfo;
    if (context.aliveTimer == timer) context.aliveTimer = nil;
    if (![self isReadyForRunContext:context]) {
        context.didSendAlive = NO;
        return;
    }
    [self emitAliveNotificationsForContext:context];
    if ([self isReadyForRunContext:context]) {
        context.didSendAlive = YES;
        [self scheduleAliveTimerForContext:context delay:25.0];
    }
}

- (void)emitAliveNotificationsForContext:(IWDLNACastRunContext *)context {
    if (![self isReadyForRunContext:context]) return;
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock >= 0) {
        unsigned char ttl = 2;
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));
        struct sockaddr_in target;
        memset(&target, 0, sizeof(target));
        target.sin_len = sizeof(target);
        target.sin_family = AF_INET;
        target.sin_addr.s_addr = inet_addr("239.255.255.250");
        target.sin_port = htons(1900);
        for (NSString *nt in @[@"upnp:rootdevice", @"urn:schemas-upnp-org:device:MediaRenderer:1", @"urn:schemas-upnp-org:service:AVTransport:1", @"urn:schemas-upnp-org:service:RenderingControl:1", @"urn:schemas-upnp-org:service:ConnectionManager:1"]) {
            if (![self isReadyForRunContext:context]) break;
            NSString *message = [NSString stringWithFormat:@"NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: %@/description.xml\r\nNT: %@\r\nNTS: ssdp:alive\r\nSERVER: iOS/10.3 UPnP/1.0 WizardCast/0.1\r\nUSN: %@::%@\r\n\r\n", [self baseURL], nt, _uuid, nt];
            NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
            sendto(sock, [data bytes], [data length], 0, (struct sockaddr *)&target, sizeof(target));
        }
        close(sock);
    }
}

@end

@interface IWImagePickerController : UIImagePickerController
@end

@implementation IWImagePickerController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return IWCurrentLandscapeOrientation(); }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end

static BOOL IWPathIsNumberStart(char ch) {
    return (ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.';
}

static void IWSkipPathSeparators(const char **p) {
    while (**p == ' ' || **p == '\n' || **p == '\t' || **p == ',') *p += 1;
}

static CGFloat IWReadPathNumber(const char **p) {
    IWSkipPathSeparators(p);
    char *end = NULL;
    double value = strtod(*p, &end);
    *p = end;
    return (CGFloat)value;
}

static void IWDrawSVGPath(CGContextRef c, const char *path) {
    const char *p = path;
    char command = 0;
    CGPoint current = CGPointZero;
    CGPoint start = CGPointZero;
    CGPoint lastC2 = CGPointZero;
    BOOL hasLastC2 = NO;
    while (*p) {
        IWSkipPathSeparators(&p);
        if (!*p) break;
        if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z')) {
            command = *p;
            p += 1;
        }
        if (!command) break;
        BOOL relative = command >= 'a' && command <= 'z';
        char op = relative ? (char)(command - 'a' + 'A') : command;
        if (op == 'Z') {
            CGContextClosePath(c);
            current = start;
            hasLastC2 = NO;
            continue;
        }
        while (*p) {
            IWSkipPathSeparators(&p);
            if (!IWPathIsNumberStart(*p)) break;
            if (op == 'M') {
                CGFloat x = IWReadPathNumber(&p);
                CGFloat y = IWReadPathNumber(&p);
                if (relative) { x += current.x; y += current.y; }
                current = CGPointMake(x, y);
                start = current;
                CGContextMoveToPoint(c, current.x, current.y);
                op = 'L';
                command = relative ? 'l' : 'L';
                hasLastC2 = NO;
            } else if (op == 'L') {
                CGFloat x = IWReadPathNumber(&p);
                CGFloat y = IWReadPathNumber(&p);
                if (relative) { x += current.x; y += current.y; }
                current = CGPointMake(x, y);
                CGContextAddLineToPoint(c, current.x, current.y);
                hasLastC2 = NO;
            } else if (op == 'H') {
                CGFloat x = IWReadPathNumber(&p);
                if (relative) x += current.x;
                current = CGPointMake(x, current.y);
                CGContextAddLineToPoint(c, current.x, current.y);
                hasLastC2 = NO;
            } else if (op == 'V') {
                CGFloat y = IWReadPathNumber(&p);
                if (relative) y += current.y;
                current = CGPointMake(current.x, y);
                CGContextAddLineToPoint(c, current.x, current.y);
                hasLastC2 = NO;
            } else if (op == 'C') {
                CGFloat x1 = IWReadPathNumber(&p), y1 = IWReadPathNumber(&p);
                CGFloat x2 = IWReadPathNumber(&p), y2 = IWReadPathNumber(&p);
                CGFloat x = IWReadPathNumber(&p), y = IWReadPathNumber(&p);
                if (relative) {
                    x1 += current.x; y1 += current.y; x2 += current.x; y2 += current.y; x += current.x; y += current.y;
                }
                CGContextAddCurveToPoint(c, x1, y1, x2, y2, x, y);
                lastC2 = CGPointMake(x2, y2);
                current = CGPointMake(x, y);
                hasLastC2 = YES;
            } else if (op == 'S') {
                CGFloat x2 = IWReadPathNumber(&p), y2 = IWReadPathNumber(&p);
                CGFloat x = IWReadPathNumber(&p), y = IWReadPathNumber(&p);
                CGPoint x1 = hasLastC2 ? CGPointMake(current.x * 2.0 - lastC2.x, current.y * 2.0 - lastC2.y) : current;
                if (relative) { x2 += current.x; y2 += current.y; x += current.x; y += current.y; }
                CGContextAddCurveToPoint(c, x1.x, x1.y, x2, y2, x, y);
                lastC2 = CGPointMake(x2, y2);
                current = CGPointMake(x, y);
                hasLastC2 = YES;
            } else if (op == 'Q') {
                CGFloat x1 = IWReadPathNumber(&p), y1 = IWReadPathNumber(&p);
                CGFloat x = IWReadPathNumber(&p), y = IWReadPathNumber(&p);
                if (relative) { x1 += current.x; y1 += current.y; x += current.x; y += current.y; }
                CGContextAddQuadCurveToPoint(c, x1, y1, x, y);
                current = CGPointMake(x, y);
                hasLastC2 = NO;
            } else {
                break;
            }
        }
    }
}

// Google Material-derived icon paths, embedded/adapted for Core Graphics.
// Source mapping and modifications: docs/open-source/MATERIAL-ICONS.md.
// Upstream license: licenses/Material-Icons-Apache-2.0.txt (Apache-2.0).
// Retained paths match the pinned inventory; see docs/open-source/MATERIAL-ICONS.md.
static const char *IWMaterialPathForButton(IWButtonKind kind, BOOL selected) {
    switch (kind) {
        case IWButtonKindMenu: return selected ? "M7.41 15.41L12 10.83l4.59 4.58L18 14l-6-6-6 6z" : "M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6 1.41-1.41z";
        case IWButtonKindTheme: return "M12,2C6.49,2,2,6.49,2,12s4.49,10,10,10c1.38,0,2.5-1.12,2.5-2.5c0-0.61-0.23-1.2-0.64-1.67c-0.08-0.1-0.13-0.21-0.13-0.33 c0-0.28,0.22-0.5,0.5-0.5H16c3.31,0,6-2.69,6-6C22,6.04,17.51,2,12,2z M17.5,13c-0.83,0-1.5-0.67-1.5-1.5c0-0.83,0.67-1.5,1.5-1.5 s1.5,0.67,1.5,1.5C19,12.33,18.33,13,17.5,13z M14.5,9C13.67,9,13,8.33,13,7.5C13,6.67,13.67,6,14.5,6S16,6.67,16,7.5 C16,8.33,15.33,9,14.5,9z M5,11.5C5,10.67,5.67,10,6.5,10S8,10.67,8,11.5C8,12.33,7.33,13,6.5,13S5,12.33,5,11.5z M11,7.5 C11,8.33,10.33,9,9.5,9S8,8.33,8,7.5C8,6.67,8.67,6,9.5,6S11,6.67,11,7.5z";
        case IWButtonKindHeart: return "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z";
        case IWButtonKindCrop: return "M17 15h2V7c0-1.1-.9-2-2-2H9v2h8v8zM7 17V1H5v4H1v2h4v10c0 1.1.9 2 2 2h10v4h2v-4h4v-2H7z";
        case IWButtonKindClock: return "M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8z M12.5 7H11v6l5.25 3.15.75-1.23-4.5-2.67z";
        case IWButtonKindMusic: return "M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z";
        case IWButtonKindHome: return "M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z";
        case IWButtonKindVideo: return "M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z";
        case IWButtonKindCast: return "M21 3H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7zm0-4v2c4.97 0 9 4.03 9 9h2c0-6.08-4.93-11-11-11z";
        case IWButtonKindDepth: return "M11.99 18.54l-7.37-5.73L3 14.07l9 7 9-7-1.63-1.27-7.38 5.74zM12 16l7.36-5.73L21 9l-9-7-9 7 1.63 1.27L12 16z";
        case IWButtonKindClose: return "M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z";
        case IWButtonKindDown: return "M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6 1.41-1.41z";
        case IWButtonKindTop: return "M8 11h3v10h2V11h3l-4-4-4 4zM4 3v2h16V3H4z";
        case IWButtonKindLocate: return "M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3c-.46-4.17-3.77-7.48-7.94-7.94V1h-2v2.06C6.83 3.52 3.52 6.83 3.06 11H1v2h2.06c.46 4.17 3.77 7.48 7.94 7.94V23h2v-2.06c4.17-.46 7.48-3.77 7.94-7.94H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z";
        case IWButtonKindReset: return "M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z";
        case IWButtonKindCheck: return "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z";
        case IWButtonKindLanguage: return "M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z";
        case IWButtonKindAdd: return "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z";
        case IWButtonKindEmpty: return "M19 3H4.99c-1.11 0-1.98.89-1.98 2L3 19c0 1.1.88 2 1.99 2H19c1.1 0 2-.9 2-2V5c0-1.11-.9-2-2-2zm0 12h-4c0 1.66-1.35 3-3 3s-3-1.34-3-3H4.99V5H19v10z";
        case IWButtonKindPlay: return "M8 5v14l11-7z";
        case IWButtonKindPause: return "M6 19h4V5H6v14zm8-14v14h4V5h-4z";
        case IWButtonKindRewind: return "M11 18V6l-8.5 6 8.5 6zm.5-6l8.5 6V6l-8.5 6z";
        case IWButtonKindForward: return "M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z";
        case IWButtonKindDelete: return "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM8 9h8v10H8V9zm7.5-5l-1-1h-5l-1 1H5v2h14V4z";
        case IWButtonKindVolume: return "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z";
        case IWButtonKindMinimize: return "M6 19h12v2H6z";
        case IWButtonKindLock: return "M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z";
        case IWButtonKindMove: return "M10 9h4V6h3l-5-5-5 5h3v3zm-1 1H6V7l-5 5 5 5v-3h3v-4zm14 2l-5-5v3h-3v4h3v3l5-5zm-9 3h-4v3H7l5 5 5-5h-3v-3z";
        case IWButtonKindDate: return "M20 3h-1V1h-2v2H7V1H5v2H4c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 18H4V8h16v13z";
        case IWButtonKindCalendar: return "M19,4h-1V2h-2v2H8V2H6v2H5C3.89,4,3.01,4.9,3.01,6L3,20c0,1.1,0.89,2,2,2h14c1.1,0,2-0.9,2-2V6C21,4.9,20.1,4,19,4z M19,20 H5V10h14V20z M9,14H7v-2h2V14z M13,14h-2v-2h2V14z M17,14h-2v-2h2V14z M9,18H7v-2h2V18z M13,18h-2v-2h2V18z M17,18h-2v-2h2V18z";
        case IWButtonKindWeather: return "M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z";
        case IWButtonKindSettings: return "M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z";
        case IWButtonKindLab: return "M22.7 19l-9.1-9.1c.9-2.3.4-5-1.5-6.9-2-2-5-2.4-7.4-1.3L9 6 6 9 1.6 4.7C.4 7.1.9 10.1 2.9 12.1c1.9 1.9 4.6 2.4 6.9 1.5l9.1 9.1c.4.4 1 .4 1.4 0l2.3-2.3c.5-.4.5-1.1.1-1.4z";
        case IWButtonKindThemeMenu: return "M12,2C6.49,2,2,6.49,2,12s4.49,10,10,10c1.38,0,2.5-1.12,2.5-2.5c0-0.61-0.23-1.2-0.64-1.67c-0.08-0.1-0.13-0.21-0.13-0.33 c0-0.28,0.22-0.5,0.5-0.5H16c3.31,0,6-2.69,6-6C22,6.04,17.51,2,12,2z M17.5,13c-0.83,0-1.5-0.67-1.5-1.5c0-0.83,0.67-1.5,1.5-1.5 s1.5,0.67,1.5,1.5C19,12.33,18.33,13,17.5,13z M14.5,9C13.67,9,13,8.33,13,7.5C13,6.67,13.67,6,14.5,6S16,6.67,16,7.5 C16,8.33,15.33,9,14.5,9z M5,11.5C5,10.67,5.67,10,6.5,10S8,10.67,8,11.5C8,12.33,7.33,13,6.5,13S5,12.33,5,11.5z M11,7.5 C11,8.33,10.33,9,9.5,9S8,8.33,8,7.5C8,6.67,8.67,6,9.5,6S11,6.67,11,7.5z";
    }
    return "";
}

static void IWDrawMaterialIcon(CGContextRef c, IWButtonKind kind, BOOL selected, CGRect rect) {
    const char *path = IWMaterialPathForButton(kind, selected);
    CGFloat iconSize = 25.0;
    CGFloat scale = iconSize / 24.0;
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, round(CGRectGetMidX(rect) - 12.0 * scale), round(CGRectGetMidY(rect) - 12.0 * scale));
    CGContextScaleCTM(c, scale, scale);
    IWDrawSVGPath(c, path);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
}

@interface IWIconButton : UIButton
@property (nonatomic, assign) IWButtonKind kind;
@property (nonatomic, strong) UIColor *iconColor;
@end

@implementation IWIconButton

- (NSString *)accessibilityLabel {
    NSString *custom = [super accessibilityLabel];
    if ([custom length]) return custom;
    switch (self.kind) {
        case IWButtonKindMenu: return self.selected ? @"收起菜单" : @"展开菜单";
        case IWButtonKindTheme: case IWButtonKindThemeMenu: return @"主题";
        case IWButtonKindHeart: return @"收藏";
        case IWButtonKindCrop: return @"编辑壁纸";
        case IWButtonKindClock: return @"专注时钟";
        case IWButtonKindMusic: return @"音乐";
        case IWButtonKindHome: return @"家庭状态";
        case IWButtonKindVideo: return @"视频";
        case IWButtonKindCast: return @"投屏";
        case IWButtonKindDepth: return @"景深";
        case IWButtonKindClose: return @"关闭";
        case IWButtonKindDown: return @"关闭图库";
        case IWButtonKindTop: return @"回到顶部";
        case IWButtonKindLocate: return @"定位当前壁纸";
        case IWButtonKindReset: return @"重置";
        case IWButtonKindCheck: return @"完成";
        case IWButtonKindLanguage: return @"语言";
        case IWButtonKindAdd: return @"添加照片";
        case IWButtonKindEmpty: return @"清空";
        case IWButtonKindPlay: return @"播放";
        case IWButtonKindPause: return @"暂停";
        case IWButtonKindRewind: return @"快退";
        case IWButtonKindForward: return @"快进";
        case IWButtonKindDelete: return @"删除";
        case IWButtonKindVolume: return @"音量";
        case IWButtonKindMinimize: return @"最小化视频";
        case IWButtonKindLock: return @"锁屏";
        case IWButtonKindMove: return @"移动";
        case IWButtonKindDate: return @"日期";
        case IWButtonKindCalendar: return @"日历";
        case IWButtonKindWeather: return @"天气";
        case IWButtonKindSettings: return @"设置";
        case IWButtonKindLab: return @"实验功能";
    }
    return custom;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    IWFlashButtonPulse(self);
    return [super beginTrackingWithTouch:touch withEvent:event];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    UIColor *iconColor = self.iconColor ?: [UIColor whiteColor];
    CGContextSetStrokeColorWithColor(c, [iconColor CGColor]);
    CGContextSetFillColorWithColor(c, [iconColor CGColor]);
    CGContextSetLineWidth(c, 2.4);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    if (self.kind == IWButtonKindTheme) {
        CGFloat x = CGRectGetMidX(rect);
        CGFloat y = CGRectGetMidY(rect);
        NSArray *colors = @[
            IWThemePink(1.0),
            [UIColor colorWithRed:1.0 green:0.70 blue:0.42 alpha:1.0],
            [UIColor colorWithRed:0.30 green:0.89 blue:0.89 alpha:1.0]
        ];
        CGFloat barW = 7.4;
        CGFloat barH = 25.0;
        CGFloat gap = 1.9;
        CGFloat start = x - (barW * 3.0 + gap * 2.0) / 2.0;
        NSInteger i;
        for (i = 0; i < 3; i += 1) {
            UIColor *color = [colors objectAtIndex:i];
            [color setFill];
            CGRect bar = CGRectMake(round(start + i * (barW + gap)), round(y - barH / 2.0), barW, barH);
            [[UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:barW / 2.0] fill];
        }
        return;
    }
    IWDrawMaterialIcon(c, self.kind, self.selected, rect);
    return;
    CGFloat x = CGRectGetMidX(rect);
    CGFloat y = CGRectGetMidY(rect);
    CGFloat ix = x - 11.0;
    CGFloat iy = y - 11.0;

    if (self.kind == IWButtonKindClose) {
        CGContextMoveToPoint(c, x - 8.0, y - 8.0); CGContextAddLineToPoint(c, x + 8.0, y + 8.0);
        CGContextMoveToPoint(c, x + 8.0, y - 8.0); CGContextAddLineToPoint(c, x - 8.0, y + 8.0);
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindTop) {
        CGContextMoveToPoint(c, x - 9.0, y + 5.0); CGContextAddLineToPoint(c, x, y - 6.0); CGContextAddLineToPoint(c, x + 9.0, y + 5.0);
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindLocate) {
        CGContextSetLineWidth(c, 2.0);
        CGContextStrokeEllipseInRect(c, CGRectMake(x - 8.0, y - 8.0, 16.0, 16.0));
        CGContextMoveToPoint(c, x, y - 12.0); CGContextAddLineToPoint(c, x, y - 7.0);
        CGContextMoveToPoint(c, x, y + 7.0); CGContextAddLineToPoint(c, x, y + 12.0);
        CGContextMoveToPoint(c, x - 12.0, y); CGContextAddLineToPoint(c, x - 7.0, y);
        CGContextMoveToPoint(c, x + 7.0, y); CGContextAddLineToPoint(c, x + 12.0, y);
        CGContextStrokePath(c);
        CGContextFillEllipseInRect(c, CGRectMake(x - 2.4, y - 2.4, 4.8, 4.8));
        return;
    }
    if (self.kind == IWButtonKindReset) {
        CGFloat scale = 1.22;
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, x - 12.0 * scale, y - 12.0 * scale);
        CGContextScaleCTM(c, scale, scale);
        CGContextBeginPath(c);
        CGContextMoveToPoint(c, 17.65, 6.35);
        CGContextAddCurveToPoint(c, 16.20, 4.90, 14.21, 4.00, 12.00, 4.00);
        CGContextAddCurveToPoint(c, 7.58, 4.00, 4.01, 7.58, 4.01, 12.00);
        CGContextAddCurveToPoint(c, 4.01, 16.42, 7.58, 20.00, 12.00, 20.00);
        CGContextAddCurveToPoint(c, 15.73, 20.00, 18.84, 17.45, 19.73, 14.00);
        CGContextAddLineToPoint(c, 17.65, 14.00);
        CGContextAddCurveToPoint(c, 16.83, 16.33, 14.61, 18.00, 12.00, 18.00);
        CGContextAddCurveToPoint(c, 8.69, 18.00, 6.00, 15.31, 6.00, 12.00);
        CGContextAddCurveToPoint(c, 6.00, 8.69, 8.69, 6.00, 12.00, 6.00);
        CGContextAddCurveToPoint(c, 13.66, 6.00, 15.14, 6.69, 16.22, 7.78);
        CGContextAddLineToPoint(c, 13.00, 11.00);
        CGContextAddLineToPoint(c, 21.00, 11.00);
        CGContextAddLineToPoint(c, 21.00, 3.00);
        CGContextAddLineToPoint(c, 17.65, 6.35);
        CGContextClosePath(c);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
        return;
    }
    if (self.kind == IWButtonKindCheck) {
        CGContextMoveToPoint(c, x - 10.0, y);
        CGContextAddLineToPoint(c, x - 3.0, y + 8.0);
        CGContextAddLineToPoint(c, x + 11.0, y - 9.0);
        CGContextStrokePath(c);
        return;
    }
    if (self.kind == IWButtonKindMenu) {
        if (self.selected) {
            CGContextMoveToPoint(c, x - 7.0, y + 4.0); CGContextAddLineToPoint(c, x, y - 4.0); CGContextAddLineToPoint(c, x + 7.0, y + 4.0);
        } else {
            CGContextMoveToPoint(c, x - 7.0, y - 4.0); CGContextAddLineToPoint(c, x, y + 4.0); CGContextAddLineToPoint(c, x + 7.0, y - 4.0);
        }
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindTheme) {
        UIColor *a = IWThemePink(1.0);
        UIColor *b = [UIColor colorWithRed:1.0 green:0.70 blue:0.42 alpha:1.0];
        UIColor *d = [UIColor colorWithRed:0.30 green:0.89 blue:0.89 alpha:1.0];
        [a setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x - 12.5, y - 12.0, 8.0, 24.0) cornerRadius:4.0] fill];
        [b setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x - 4.0, y - 12.0, 8.0, 24.0) cornerRadius:4.0] fill];
        [d setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x + 4.5, y - 12.0, 8.0, 24.0) cornerRadius:4.0] fill];
        return;
    }
    if (self.kind == IWButtonKindHeart) {
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, x, y + 2.0);
        CGContextScaleCTM(c, 0.74, 0.74);
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(0, 9)];
        [p addCurveToPoint:CGPointMake(-12, -2) controlPoint1:CGPointMake(-9, 2) controlPoint2:CGPointMake(-12, -1)];
        [p addCurveToPoint:CGPointMake(-6, -10) controlPoint1:CGPointMake(-12, -7) controlPoint2:CGPointMake(-9, -10)];
        [p addCurveToPoint:CGPointMake(0, -6) controlPoint1:CGPointMake(-3, -10) controlPoint2:CGPointMake(-1, -8)];
        [p addCurveToPoint:CGPointMake(6, -10) controlPoint1:CGPointMake(1, -8) controlPoint2:CGPointMake(3, -10)];
        [p addCurveToPoint:CGPointMake(12, -2) controlPoint1:CGPointMake(9, -10) controlPoint2:CGPointMake(12, -7)];
        [p addCurveToPoint:CGPointMake(0, 9) controlPoint1:CGPointMake(12, -1) controlPoint2:CGPointMake(9, 2)];
        [p closePath]; [p fill]; CGContextRestoreGState(c); return;
    }
    if (self.kind == IWButtonKindCrop) {
        CGContextStrokeRectWithWidth(c, CGRectMake(ix + 4.0, iy + 4.0, 14.0, 14.0), 2.0);
        CGContextMoveToPoint(c, ix + 9.0, iy + 18.0);
        CGContextAddLineToPoint(c, ix + 18.0, iy + 18.0);
        CGContextAddLineToPoint(c, ix + 18.0, iy + 9.0);
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindClock) {
        CGContextStrokeEllipseInRect(c, CGRectMake(ix + 3.0, iy + 3.0, 16.0, 16.0));
        CGContextMoveToPoint(c, ix + 11.0, iy + 6.0);
        CGContextAddLineToPoint(c, ix + 11.0, iy + 13.0);
        CGContextAddLineToPoint(c, ix + 16.0, iy + 13.0);
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindMusic) {
        CGContextMoveToPoint(c, x - 2.0, y - 10.0); CGContextAddLineToPoint(c, x + 8.0, y - 8.0); CGContextAddLineToPoint(c, x + 8.0, y + 5.0);
        CGContextMoveToPoint(c, x - 2.0, y - 10.0); CGContextAddLineToPoint(c, x - 2.0, y + 8.0);
        CGContextStrokePath(c);
        CGContextFillEllipseInRect(c, CGRectMake(x - 10.0, y + 4.0, 8.0, 7.0));
        CGContextFillEllipseInRect(c, CGRectMake(x + 3.0, y + 2.0, 8.0, 7.0)); return;
    }
    if (self.kind == IWButtonKindHome) {
        CGContextMoveToPoint(c, ix + 5.0, iy + 10.0);
        CGContextAddLineToPoint(c, ix + 5.0, iy + 19.0);
        CGContextAddLineToPoint(c, ix + 17.0, iy + 19.0);
        CGContextAddLineToPoint(c, ix + 17.0, iy + 10.0);
        CGContextStrokePath(c);
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, ix + 11.0, iy + 10.0);
        CGContextRotateCTM(c, 45.0 * M_PI / 180.0);
        CGContextMoveToPoint(c, -6.0, 6.0);
        CGContextAddLineToPoint(c, -6.0, -6.0);
        CGContextAddLineToPoint(c, 6.0, -6.0);
        CGContextStrokePath(c);
        CGContextRestoreGState(c);
        CGContextStrokePath(c); return;
    }
    if (self.kind == IWButtonKindVideo) {
        CGContextStrokeRectWithWidth(c, CGRectMake(ix + 3.0, iy + 5.0, 14.0, 12.0), 2.0);
        CGContextMoveToPoint(c, ix + 21.0, iy + 8.0);
        CGContextAddLineToPoint(c, ix + 21.0, iy + 16.0);
        CGContextAddLineToPoint(c, ix + 14.0, iy + 12.0);
        CGContextClosePath(c); CGContextFillPath(c); return;
    }
    if (self.kind == IWButtonKindCast) {
        CGContextStrokeRectWithWidth(c, CGRectMake(ix + 3.0, iy + 5.0, 16.0, 12.0), 2.0);
        CGContextMoveToPoint(c, ix + 4.0, iy + 19.0);
        CGContextAddCurveToPoint(c, ix + 7.2, iy + 15.8, ix + 11.0, iy + 14.2, ix + 17.0, iy + 14.0);
        CGContextMoveToPoint(c, ix + 4.0, iy + 19.0);
        CGContextAddCurveToPoint(c, ix + 4.4, iy + 15.2, ix + 4.8, iy + 12.8, ix + 5.0, iy + 10.0);
        CGContextStrokePath(c); return;
    }
}

@end

@interface IWDateLabel : UILabel
@end

@implementation IWDateLabel

- (void)drawTextInRect:(CGRect)rect {
    if (![self.text length]) return;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = self.textAlignment;
    NSDictionary *baseAttrs = @{
        NSFontAttributeName: self.font ?: IWGTATextFont(18.0),
        NSForegroundColorAttributeName: self.textColor ?: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style,
        NSKernAttributeName: @(1.44)
    };
    NSDictionary *strokeAttrs = @{
        NSFontAttributeName: self.font ?: IWGTATextFont(18.0),
        NSForegroundColorAttributeName: [UIColor colorWithRed:5.0/255.0 green:11.0/255.0 blue:18.0/255.0 alpha:0.86],
        NSParagraphStyleAttributeName: style,
        NSKernAttributeName: @(1.44)
    };
    NSAttributedString *strokeString = [[NSAttributedString alloc] initWithString:self.text attributes:strokeAttrs];
    NSAttributedString *fillString = [[NSAttributedString alloc] initWithString:self.text attributes:baseAttrs];
    CGRect textRect = CGRectInset(rect, -4.0, 0);
    CGPoint offsets[] = {
        CGPointMake(-2.0, -1.0),
        CGPointMake(2.0, -1.0),
        CGPointMake(-2.0, 1.0),
        CGPointMake(2.0, 1.0)
    };
    NSInteger i;
    for (i = 0; i < 4; i += 1) {
        CGRect r = CGRectOffset(textRect, offsets[i].x, offsets[i].y);
        [strokeString drawInRect:r];
    }
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 4.0), 7.0, [[UIColor colorWithWhite:0 alpha:0.76] CGColor]);
    [fillString drawInRect:textRect];
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeZero, 18.0, [[UIColor colorWithWhite:1.0 alpha:0.26] CGColor]);
    [fillString drawInRect:textRect];
    CGContextRestoreGState(c);
}

@end

@interface IWOpacitySlider : UISlider
@end

@implementation IWOpacitySlider
- (CGRect)trackRectForBounds:(CGRect)bounds {
    CGRect track = [super trackRectForBounds:bounds];
    track.size.height = 7.0;
    track.origin.y = round((bounds.size.height - track.size.height) / 2.0);
    return track;
}
@end

@interface IWColonDot : UIView
@property (nonatomic, strong) UIColor *dotColor;
@end

@implementation IWColonDot

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.dotColor = IWThemePink(1.0);
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    CGRect dot = CGRectInset(self.bounds, 4.0, 4.0);
    CGContextSetShadowWithColor(c, CGSizeZero, 26.0, [[UIColor colorWithRed:61.0/255.0 green:222.0/255.0 blue:230.0/255.0 alpha:0.34] CGColor]);
    CGContextSetFillColorWithColor(c, [self.dotColor CGColor]);
    CGContextFillEllipseInRect(c, dot);
    CGContextSetShadowWithColor(c, CGSizeZero, 16.0, [[self.dotColor colorWithAlphaComponent:0.62] CGColor]);
    CGContextFillEllipseInRect(c, dot);
    CGContextSetShadowWithColor(c, CGSizeZero, 0, NULL);
    CGContextSetStrokeColorWithColor(c, [[UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.90] CGColor]);
    CGContextSetLineWidth(c, 2.0);
    CGContextStrokeEllipseInRect(c, CGRectInset(dot, 1.0, 1.0));
    CGContextSetStrokeColorWithColor(c, [[self.dotColor colorWithAlphaComponent:0.38] CGColor]);
    CGContextSetLineWidth(c, 1.0);
    CGContextStrokeEllipseInRect(c, CGRectInset(dot, -1.0, -1.0));
}

@end

@interface IWDigitCardBackground : UIView
@property (nonatomic, assign) CGFloat fillAlpha;
@property (nonatomic, strong) UIColor *borderColor;
@property (nonatomic, assign) CGFloat borderWidth;
@end

@implementation IWDigitCardBackground

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _fillAlpha = IWDigitCardDefaultOpacity();
    _borderColor = IWThemePink(0.82);
    _borderWidth = 3.4;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.contentScaleFactor = 2.0;
    self.layer.contentsScale = 2.0;
    return self;
}

- (void)setFillAlpha:(CGFloat)fillAlpha {
    _fillAlpha = IWDigitCardClampOpacity(fillAlpha);
    [self setNeedsDisplay];
}

- (void)setBorderColor:(UIColor *)borderColor {
    _borderColor = borderColor ?: IWThemePink(0.82);
    [self setNeedsDisplay];
}

- (void)setBorderWidth:(CGFloat)borderWidth { _borderWidth = MAX(1.0, MIN(6.0, borderWidth)); [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    CGRect b = self.bounds;
    CGFloat baseAlpha = IWDigitCardClampOpacity(_fillAlpha);
    CGFloat topAlphaA = MIN(0.95, baseAlpha + 0.14);
    CGFloat topAlphaB = MAX(0.05, baseAlpha - 0.04);
    CGFloat bottomAlphaA = MAX(0.05, baseAlpha - 0.04);
    CGFloat bottomAlphaB = MIN(0.95, baseAlpha + 0.10);
    UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:12.0];
    CGContextSaveGState(c);
    [rounded addClip];

    CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:1.0 green:243.0/255.0 blue:243.0/255.0 alpha:baseAlpha] CGColor]);
    CGContextFillRect(c, b);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[] = {0.0, 1.0};
    CGRect topRect = CGRectMake(0, 0, b.size.width, floor(b.size.height / 2.0));
    CGRect bottomRect = CGRectMake(0, CGRectGetMaxY(topRect), b.size.width, b.size.height - topRect.size.height);

    CGContextSaveGState(c);
    CGContextClipToRect(c, topRect);
    CGGradientRef topGradient = CGGradientCreateWithColors(space, (CFArrayRef)@[
        (id)[[UIColor colorWithRed:1.0 green:253.0/255.0 blue:247.0/255.0 alpha:topAlphaA] CGColor],
        (id)[[UIColor colorWithRed:245.0/255.0 green:224.0/255.0 blue:231.0/255.0 alpha:topAlphaB] CGColor]
    ], locations);
    CGContextDrawLinearGradient(c, topGradient, CGPointMake(0, 0), CGPointMake(0, CGRectGetMaxY(topRect)), 0);
    CGGradientRelease(topGradient);
    CGContextRestoreGState(c);

    CGContextSaveGState(c);
    CGContextClipToRect(c, bottomRect);
    CGGradientRef bottomGradient = CGGradientCreateWithColors(space, (CFArrayRef)@[
        (id)[[UIColor colorWithRed:237.0/255.0 green:214.0/255.0 blue:224.0/255.0 alpha:bottomAlphaA] CGColor],
        (id)[[UIColor colorWithRed:1.0 green:244.0/255.0 blue:239.0/255.0 alpha:bottomAlphaB] CGColor]
    ], locations);
    CGContextDrawLinearGradient(c, bottomGradient, CGPointMake(0, CGRectGetMinY(bottomRect)), CGPointMake(0, CGRectGetMaxY(bottomRect)), 0);
    CGGradientRelease(bottomGradient);
    CGContextRestoreGState(c);
    CGColorSpaceRelease(space);

    CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:1.0 green:194.0/255.0 blue:225.0/255.0 alpha:0.18] CGColor]);
    CGContextFillRect(c, CGRectMake(0, b.size.height - 18.0, b.size.width, 18.0));

    CGFloat half = floor(b.size.height / 2.0);
    CGContextSetFillColorWithColor(c, [[UIColor colorWithWhite:1.0 alpha:0.74] CGColor]);
    CGContextFillRect(c, CGRectMake(0, half - 2.0, b.size.width, 1.0));
    CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:31.0/255.0 green:19.0/255.0 blue:42.0/255.0 alpha:0.26] CGColor]);
    CGContextFillRect(c, CGRectMake(0, half - 1.0, b.size.width, 2.0));
    CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:236.0/255.0 green:58.0/255.0 blue:145.0/255.0 alpha:0.18] CGColor]);
    CGContextFillRect(c, CGRectMake(0, half + 1.0, b.size.width, 1.0));

    CGContextSetStrokeColorWithColor(c, [_borderColor CGColor]);
    CGContextSetLineWidth(c, _borderWidth);
    UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 1.8, 1.8) cornerRadius:10.2];
    [border stroke];

    CGContextRestoreGState(c);
}

@end

@interface IWBorderColorPalette : UIControl
@property (nonatomic, strong) UIColor *selectedColor;
@end

@implementation IWBorderColorPalette

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _selectedColor = IWThemePink(1.0);
    self.opaque = NO;
    self.layer.cornerRadius = 12.0;
    self.layer.borderWidth = 1.25;
    self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.56] CGColor];
    self.clipsToBounds = YES;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (void)setSelectedColor:(UIColor *)selectedColor { _selectedColor = selectedColor ?: IWThemePink(1.0); [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    CGRect b = self.bounds;
    NSInteger columns = 48;
    CGFloat w = b.size.width / columns;
    NSInteger i;
    for (i = 0; i < columns; i += 1) {
        UIColor *hue = [UIColor colorWithHue:(CGFloat)i / (columns - 1) saturation:0.94 brightness:1.0 alpha:1.0];
        CGContextSetFillColorWithColor(c, [hue CGColor]);
        CGContextFillRect(c, CGRectMake(i * w, 0, ceil(w + 1.0), b.size.height));
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[[UIColor colorWithWhite:0 alpha:0] CGColor], (id)[[UIColor colorWithWhite:0 alpha:0.90] CGColor]];
    CGFloat locations[] = {0.0, 1.0};
    CGGradientRef shade = CGGradientCreateWithColors(space, (CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(c, shade, CGPointMake(0, 0), CGPointMake(0, b.size.height), 0);
    CGGradientRelease(shade); CGColorSpaceRelease(space);
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if (![_selectedColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) hue = 0.92;
    CGPoint p = CGPointMake(hue * b.size.width, (1.0 - brightness) * b.size.height);
    CGContextSetFillColorWithColor(c, [[UIColor colorWithWhite:1 alpha:0.94] CGColor]);
    CGContextFillEllipseInRect(c, CGRectMake(p.x - 7, p.y - 7, 14, 14));
    CGContextSetStrokeColorWithColor(c, [[UIColor colorWithWhite:0 alpha:0.72] CGColor]);
    CGContextSetLineWidth(c, 2.0);
    CGContextStrokeEllipseInRect(c, CGRectMake(p.x - 7, p.y - 7, 14, 14));
}

- (void)updateForTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat hue = MAX(0.0, MIN(1.0, p.x / MAX(1.0, self.bounds.size.width)));
    CGFloat brightness = MAX(0.10, MIN(1.0, 1.0 - p.y / MAX(1.0, self.bounds.size.height)));
    self.selectedColor = [UIColor colorWithHue:hue saturation:0.94 brightness:brightness alpha:1.0];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self updateForTouch:touch]; return YES; }
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self updateForTouch:touch]; return YES; }
@end

@interface IWDigitSegment : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, assign) BOOL top;
@property (nonatomic, assign) BOOL flipStyle;
@property (nonatomic, assign) CGFloat cardOpacity;
@property (nonatomic, assign) CGFloat flipCardOpacity;
@property (nonatomic, strong) UIColor *strokeColor;
@end

@implementation IWDigitSegment

- (instancetype)initWithTop:(BOOL)top {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _top = top;
    _text = @"";
    _font = IWGTAFont(118.0);
    _textColor = [UIColor colorWithRed:17.0/255.0 green:17.0/255.0 blue:26.0/255.0 alpha:1.0];
    _strokeColor = IWThemePink(0.58);
    _cardOpacity = IWDigitCardDefaultOpacity();
    _flipCardOpacity = 0.98;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    self.layer.doubleSided = NO;
    self.contentScaleFactor = 2.0;
    self.layer.contentsScale = 2.0;
    return self;
}

- (void)setText:(NSString *)text { text = text ?: @""; if ([_text isEqualToString:text]) return; _text = [text copy]; [self setNeedsDisplay]; }
- (void)setFont:(UIFont *)font { font = font ?: IWGTAFont(118.0); if ([_font isEqual:font]) return; _font = font; [self setNeedsDisplay]; }
- (void)setTextColor:(UIColor *)textColor { textColor = textColor ?: [UIColor blackColor]; if ([_textColor isEqual:textColor]) return; _textColor = textColor; [self setNeedsDisplay]; }
- (void)setTop:(BOOL)top { if (_top == top) return; _top = top; [self setNeedsDisplay]; }
- (void)setFlipStyle:(BOOL)flipStyle { if (_flipStyle == flipStyle) return; _flipStyle = flipStyle; [self setNeedsDisplay]; }
- (void)setCardOpacity:(CGFloat)cardOpacity { cardOpacity = IWDigitCardClampOpacity(cardOpacity); if (_cardOpacity == cardOpacity) return; _cardOpacity = cardOpacity; [self setNeedsDisplay]; }
- (void)setFlipCardOpacity:(CGFloat)flipCardOpacity { flipCardOpacity = MAX(0.0, MIN(1.0, flipCardOpacity)); if (_flipCardOpacity == flipCardOpacity) return; _flipCardOpacity = flipCardOpacity; [self setNeedsDisplay]; }
- (void)setStrokeColor:(UIColor *)strokeColor { strokeColor = strokeColor ?: IWThemePink(0.58); if ([_strokeColor isEqual:strokeColor]) return; _strokeColor = strokeColor; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    CGRect b = self.bounds;
    CGFloat radius = 11.0;
    UIBezierPath *clipPath = [UIBezierPath bezierPath];
    if (_top) {
        [clipPath moveToPoint:CGPointMake(0, CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(0, radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(radius, 0) controlPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b) - radius, 0)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b), radius) controlPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
    } else {
        [clipPath moveToPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b) - radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b) - radius, CGRectGetMaxY(b)) controlPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(radius, CGRectGetMaxY(b))];
        [clipPath addQuadCurveToPoint:CGPointMake(0, CGRectGetMaxY(b) - radius) controlPoint:CGPointMake(0, CGRectGetMaxY(b))];
    }
    [clipPath closePath];
    if (_flipStyle) {
        CGContextSaveGState(c);
        [clipPath addClip];
        CGFloat fillAlpha = _flipStyle ? _flipCardOpacity : _cardOpacity;
        CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:1.0 green:243.0/255.0 blue:243.0/255.0 alpha:fillAlpha] CGColor]);
        CGContextFillRect(c, b);
        CGContextRestoreGState(c);
    }
    if (![_text length]) return;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    UIColor *fillColor = _flipStyle ? [UIColor colorWithRed:7.0/255.0 green:21.0/255.0 blue:33.0/255.0 alpha:1.0] : _textColor;
    NSMutableDictionary *attrs = [@{
        NSFontAttributeName: _font,
        NSForegroundColorAttributeName: fillColor,
        NSParagraphStyleAttributeName: style
    } mutableCopy];
    if (!_flipStyle) {
        [attrs setObject:_strokeColor forKey:NSStrokeColorAttributeName];
        [attrs setObject:@(-2.15) forKey:NSStrokeWidthAttributeName];
        CGContextSetShadowWithColor(UIGraphicsGetCurrentContext(), CGSizeZero, 1.2, [[_strokeColor colorWithAlphaComponent:0.48] CGColor]);
    }
    CGFloat fullHeight = b.size.height * 2.0;
    CGFloat fontHeight = _font.lineHeight;
    CGRect textRect = CGRectMake(0, floor((fullHeight - fontHeight) / 2.0) + 5.0, b.size.width, fontHeight + 8.0);
    if (!_top) textRect.origin.y -= b.size.height;
    CGContextSaveGState(c);
    [clipPath addClip];
    [_text drawInRect:textRect withAttributes:attrs];
    CGContextRestoreGState(c);
    if (!_flipStyle) CGContextSetShadowWithColor(UIGraphicsGetCurrentContext(), CGSizeZero, 0, NULL);
}

@end

@interface IWFlipPageLight : UIView
@property (nonatomic, assign) BOOL top;
@end

@implementation IWFlipPageLight

- (instancetype)initWithTop:(BOOL)top {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _top = top;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.contentScaleFactor = 2.0;
    self.layer.contentsScale = 2.0;
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!c) return;
    CGRect b = self.bounds;
    CGFloat radius = 11.0;
    UIBezierPath *clipPath = [UIBezierPath bezierPath];
    if (_top) {
        [clipPath moveToPoint:CGPointMake(0, CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(0, radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(radius, 0) controlPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b) - radius, 0)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b), radius) controlPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
    } else {
        [clipPath moveToPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b) - radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b) - radius, CGRectGetMaxY(b)) controlPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(radius, CGRectGetMaxY(b))];
        [clipPath addQuadCurveToPoint:CGPointMake(0, CGRectGetMaxY(b) - radius) controlPoint:CGPointMake(0, CGRectGetMaxY(b))];
    }
    [clipPath closePath];
    [clipPath addClip];
    if (!_top) return;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[] = {0.0, 0.62, 1.0};
    NSArray *colors = @[
        (id)[[UIColor colorWithWhite:1.0 alpha:1.0] CGColor],
        (id)[[UIColor colorWithWhite:1.0 alpha:0.30] CGColor],
        (id)[[UIColor colorWithWhite:1.0 alpha:0.0] CGColor]
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)colors, locations);
    if (gradient) {
        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 0), CGPointMake(0, CGRectGetMaxY(b)), 0);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(space);
}

@end

@interface IWFlipDigitLabel : UILabel
@property (nonatomic, assign) CGFloat cardOpacity;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, assign) CGFloat borderWidth;
- (void)setDigitText:(NSString *)text animated:(BOOL)animated;
- (void)showDebugFlipFromText:(NSString *)oldText toText:(NSString *)text phase:(CGFloat)phase;
@end

@implementation IWFlipDigitLabel {
    UIView *_externalBottomShadow;
    UIView *_contentView;
    IWDigitCardBackground *_cardBackground;
    UIView *_cardBorderOverlay;
    UIView *_topInsetHighlight;
    UIView *_bottomInsetGlow;
    IWDigitSegment *_topStatic;
    IWDigitSegment *_bottomStatic;
    IWDigitSegment *_topMask;
    IWDigitSegment *_bottomMask;
    IWDigitSegment *_topFlip;
    IWDigitSegment *_bottomFlip;
    UIView *_seam;
    UIView *_seamTopHighlight;
    UIView *_seamBottomGlow;
    CADisplayLink *_flipDisplayLink;
    NSTimeInterval _flipStartTime;
    NSString *_flipPendingText;
    UIImageView *_flipTopPage;
    UIImageView *_flipBottomPage;
    UIImageView *_flipOldBottomPage;
    UIView *_flipTopLight;
    UIView *_flipBottomLight;
    UIView *_flipTopEdgeLine;
    UIView *_flipTopShade;
    CALayer *_topStaticRevealMask;
    UIColor *_edgeAccentColor;
    CGRect _flipTopRect;
    CGRect _flipBottomRect;
    NSInteger _flipFrameIndex;
    BOOL _flipHalfSwitched;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [super setBackgroundColor:[UIColor clearColor]];
    _edgeAccentColor = IWThemePink(1.0);
    self.clipsToBounds = NO;
    self.layer.masksToBounds = NO;
    self.layer.borderWidth = 1.6;
    self.layer.borderColor = [IWThemePink(0.54) CGColor];
    self.layer.cornerRadius = 12.0;
    self.layer.shadowColor = [[UIColor colorWithRed:52.0/255.0 green:18.0/255.0 blue:58.0/255.0 alpha:0.26] CGColor];
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowRadius = 0;
    self.layer.shadowOpacity = 0.0;
    self.layer.sublayerTransform = CATransform3DIdentity;
    self.layer.allowsEdgeAntialiasing = YES;

    _externalBottomShadow = [[UIView alloc] initWithFrame:CGRectZero];
    _externalBottomShadow.userInteractionEnabled = NO;
    _externalBottomShadow.backgroundColor = [UIColor colorWithRed:230.0/255.0 green:79.0/255.0 blue:160.0/255.0 alpha:0.28];
    _externalBottomShadow.layer.cornerRadius = 4.0;
    _externalBottomShadow.layer.masksToBounds = YES;
    _externalBottomShadow.layer.allowsEdgeAntialiasing = YES;
    [self addSubview:_externalBottomShadow];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.userInteractionEnabled = NO;
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.layer.cornerRadius = 12.0;
    _contentView.layer.masksToBounds = NO;
    [self addSubview:_contentView];

    _cardBackground = [[IWDigitCardBackground alloc] initWithFrame:CGRectZero];
    [_contentView addSubview:_cardBackground];

    _cardBorderOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    _cardBorderOverlay.userInteractionEnabled = NO;
    _cardBorderOverlay.backgroundColor = [UIColor clearColor];
    _cardBorderOverlay.layer.borderWidth = 3.2;
    _cardBorderOverlay.layer.borderColor = [[_edgeAccentColor colorWithAlphaComponent:0.88] CGColor];
    _cardBorderOverlay.layer.cornerRadius = 11.0;
    _cardBorderOverlay.layer.allowsEdgeAntialiasing = YES;
    _cardBorderOverlay.layer.zPosition = 18.0;

    _topStatic = [[IWDigitSegment alloc] initWithTop:YES];
    _bottomStatic = [[IWDigitSegment alloc] initWithTop:NO];
    _topMask = [[IWDigitSegment alloc] initWithTop:YES];
    _bottomMask = [[IWDigitSegment alloc] initWithTop:NO];
    _topFlip = [[IWDigitSegment alloc] initWithTop:YES];
    _bottomFlip = [[IWDigitSegment alloc] initWithTop:NO];
    _topMask.flipStyle = YES;
    _bottomMask.flipStyle = YES;
    _topMask.hidden = YES;
    _bottomMask.hidden = YES;
    _topFlip.flipStyle = YES;
    _bottomFlip.flipStyle = YES;
    _topFlip.hidden = YES;
    _bottomFlip.hidden = YES;
    [_contentView addSubview:_topStatic];
    [_contentView addSubview:_bottomStatic];
    [_contentView addSubview:_topMask];
    [_contentView addSubview:_bottomMask];
    [_contentView addSubview:_topFlip];
    [_contentView addSubview:_bottomFlip];
    [_contentView addSubview:_cardBorderOverlay];

    _topInsetHighlight = [[UIView alloc] initWithFrame:CGRectZero];
    _topInsetHighlight.userInteractionEnabled = NO;
    _topInsetHighlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.84];
    _topInsetHighlight.hidden = YES;
    [_contentView addSubview:_topInsetHighlight];

    _bottomInsetGlow = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomInsetGlow.userInteractionEnabled = NO;
    _bottomInsetGlow.backgroundColor = [UIColor colorWithRed:1.0 green:194.0/255.0 blue:225.0/255.0 alpha:0.18];
    _bottomInsetGlow.hidden = YES;
    [_contentView addSubview:_bottomInsetGlow];

    _seam = [[UIView alloc] initWithFrame:CGRectZero];
    _seam.backgroundColor = [UIColor colorWithRed:31.0/255.0 green:19.0/255.0 blue:42.0/255.0 alpha:0.26];
    _seam.hidden = YES;
    [_contentView addSubview:_seam];

    _seamTopHighlight = [[UIView alloc] initWithFrame:CGRectZero];
    _seamTopHighlight.userInteractionEnabled = NO;
    _seamTopHighlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.74];
    _seamTopHighlight.hidden = YES;
    [_contentView addSubview:_seamTopHighlight];

    _seamBottomGlow = [[UIView alloc] initWithFrame:CGRectZero];
    _seamBottomGlow.userInteractionEnabled = NO;
    _seamBottomGlow.backgroundColor = [UIColor colorWithRed:236.0/255.0 green:58.0/255.0 blue:145.0/255.0 alpha:0.18];
    _seamBottomGlow.hidden = YES;
    [_contentView addSubview:_seamBottomGlow];
    self.cardOpacity = IWDigitCardDefaultOpacity();
    return self;
}

- (void)drawRect:(CGRect)rect {}

- (void)dealloc {
    [_flipDisplayLink invalidate];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:[UIColor clearColor]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect contentBounds = CGRectInset(self.bounds, 1.0, 1.0);
    CGFloat half = floor(contentBounds.size.height / 2.0);
    CGRect topFrame = CGRectMake(0, 0, contentBounds.size.width, half);
    CGRect bottomFrame = CGRectMake(0, half, contentBounds.size.width, contentBounds.size.height - half);
    _externalBottomShadow.frame = CGRectMake(5.0, self.bounds.size.height - 5.0, self.bounds.size.width - 10.0, 7.0);
    _contentView.frame = contentBounds;
    _contentView.layer.cornerRadius = 11.0;
    self.layer.shadowPath = [[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:12.0] CGPath];
    _cardBackground.frame = _contentView.bounds;
    _cardBorderOverlay.frame = CGRectInset(_contentView.bounds, 1.2, 1.2);
    _cardBorderOverlay.layer.cornerRadius = 10.0;
    _topStatic.frame = topFrame;
    _bottomStatic.frame = bottomFrame;
    _topFlip.frame = topFrame;
    _bottomFlip.frame = bottomFrame;
    _topMask.frame = topFrame;
    _bottomMask.frame = bottomFrame;
    _topFlip.layer.anchorPoint = CGPointMake(0.5, 1.0);
    _topFlip.layer.position = CGPointMake(CGRectGetMidX(topFrame), CGRectGetMaxY(topFrame));
    _bottomFlip.layer.anchorPoint = CGPointMake(0.5, 0.0);
    _bottomFlip.layer.position = CGPointMake(CGRectGetMidX(bottomFrame), CGRectGetMinY(bottomFrame));
    _seam.frame = CGRectMake(0, half - 1.0, contentBounds.size.width, 2.0);
    _topInsetHighlight.frame = CGRectMake(0, 0, contentBounds.size.width, 1.0);
    _bottomInsetGlow.frame = CGRectMake(0, contentBounds.size.height - 18.0, contentBounds.size.width, 18.0);
    _seamTopHighlight.frame = CGRectMake(0, half - 2.0, contentBounds.size.width, 1.0);
    _seamBottomGlow.frame = CGRectMake(0, half + 1.0, contentBounds.size.width, 1.0);
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    _topStatic.font = font;
    _bottomStatic.font = font;
    _topFlip.font = font;
    _bottomFlip.font = font;
    _topMask.font = font;
    _bottomMask.font = font;
}

- (void)setTextColor:(UIColor *)textColor {
    [super setTextColor:textColor];
    _topStatic.textColor = textColor;
    _bottomStatic.textColor = textColor;
    _topFlip.textColor = textColor;
    _bottomFlip.textColor = textColor;
    _topMask.textColor = textColor;
    _bottomMask.textColor = textColor;
}

- (void)setCardOpacity:(CGFloat)cardOpacity {
    _cardOpacity = IWDigitCardClampOpacity(cardOpacity);
    _cardBackground.fillAlpha = _cardOpacity;
    _topStatic.cardOpacity = _cardOpacity;
    _bottomStatic.cardOpacity = _cardOpacity;
    _topFlip.cardOpacity = _cardOpacity;
    _bottomFlip.cardOpacity = _cardOpacity;
    _topMask.cardOpacity = _cardOpacity;
    _bottomMask.cardOpacity = _cardOpacity;
}

- (void)setAccentColor:(UIColor *)accentColor {
    UIColor *strokeAccent = accentColor ?: IWThemePink(1.0);
    _edgeAccentColor = strokeAccent;
    self.layer.borderColor = [[_edgeAccentColor colorWithAlphaComponent:0.62] CGColor];
    _cardBackground.borderColor = [_edgeAccentColor colorWithAlphaComponent:0.84];
    _cardBorderOverlay.layer.borderColor = [[_edgeAccentColor colorWithAlphaComponent:0.90] CGColor];
    _topStatic.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
    _bottomStatic.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
    _topMask.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
    _bottomMask.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
    _topFlip.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
    _bottomFlip.strokeColor = [strokeAccent colorWithAlphaComponent:0.76];
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    CGFloat width = MAX(1.0, MIN(6.0, borderWidth));
    self.layer.borderWidth = MAX(0.6, width * 0.48);
    _cardBackground.borderWidth = width;
    _cardBorderOverlay.layer.borderWidth = width;
    [self setNeedsLayout];
}

- (CGFloat)borderWidth { return _cardBorderOverlay.layer.borderWidth; }

- (UIColor *)accentColor {
    return _edgeAccentColor;
}

- (void)setText:(NSString *)text {
    [super setText:text];
    _topStatic.hidden = NO;
    _bottomStatic.hidden = NO;
    _topStatic.text = text;
    _bottomStatic.text = text;
    _topMask.text = @"";
    _bottomMask.text = @"";
}

- (UIImage *)snapshotForDigitText:(NSString *)text includeCard:(BOOL)includeCard {
    [self layoutIfNeeded];
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%d|%@|%g|%@|%g|%@|%@|%g|%g", text, includeCard, NSStringFromCGRect(_contentView.bounds), [UIScreen mainScreen].scale, self.font.fontName, self.font.pointSize, self.textColor, _edgeAccentColor, self.cardOpacity, self.borderWidth];
    UIImage *cached = [IWDigitSnapshotCache() objectForKey:cacheKey];
    if (cached) return cached;
    NSString *topText = _topStatic.text;
    NSString *bottomText = _bottomStatic.text;
    BOOL topFlipHidden = _topFlip.hidden;
    BOOL bottomFlipHidden = _bottomFlip.hidden;
    BOOL cardHidden = _cardBackground.hidden;
    CGFloat topFlipAlpha = _topFlip.alpha;
    CGFloat bottomFlipAlpha = _bottomFlip.alpha;
    _topStatic.text = text;
    _bottomStatic.text = text;
    _topFlip.hidden = YES;
    _bottomFlip.hidden = YES;
    _cardBackground.hidden = !includeCard;
    _topFlip.alpha = 0.0;
    _bottomFlip.alpha = 0.0;
    [_contentView setNeedsLayout];
    [_contentView layoutIfNeeded];
    UIGraphicsBeginImageContextWithOptions(_contentView.bounds.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context) [_contentView.layer renderInContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    _topStatic.text = topText;
    _bottomStatic.text = bottomText;
    _topFlip.hidden = topFlipHidden;
    _bottomFlip.hidden = bottomFlipHidden;
    _cardBackground.hidden = cardHidden;
    _topFlip.alpha = topFlipAlpha;
    _bottomFlip.alpha = bottomFlipAlpha;
    if (image) {
        NSUInteger cost = CGImageGetBytesPerRow(image.CGImage) * CGImageGetHeight(image.CGImage);
        [IWDigitSnapshotCache() setObject:image forKey:cacheKey cost:cost];
    }
    return image;
}

- (UIImage *)cropImage:(UIImage *)image rect:(CGRect)rect {
    if (!image) return nil;
    CGFloat scale = image.scale;
    CGRect scaled = CGRectMake(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, scaled);
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

- (UIImage *)solidFlipPageImage:(UIImage *)image top:(BOOL)top {
    if (!image) return nil;
    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    CGRect b = CGRectMake(0, 0, size.width, size.height);
    CGFloat radius = 11.0;
    UIBezierPath *clipPath = [UIBezierPath bezierPath];
    if (top) {
        [clipPath moveToPoint:CGPointMake(0, CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(0, radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(radius, 0) controlPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b) - radius, 0)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b), radius) controlPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
    } else {
        [clipPath moveToPoint:CGPointMake(0, 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), 0)];
        [clipPath addLineToPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b) - radius)];
        [clipPath addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(b) - radius, CGRectGetMaxY(b)) controlPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))];
        [clipPath addLineToPoint:CGPointMake(radius, CGRectGetMaxY(b))];
        [clipPath addQuadCurveToPoint:CGPointMake(0, CGRectGetMaxY(b) - radius) controlPoint:CGPointMake(0, CGRectGetMaxY(b))];
    }
    [clipPath closePath];
    [clipPath addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (top) {
        CGFloat locations[] = {0.0, 1.0};
        NSArray *colors = @[
            (id)[[UIColor colorWithRed:1.0 green:253.0/255.0 blue:247.0/255.0 alpha:1.0] CGColor],
            (id)[[UIColor colorWithRed:202.0/255.0 green:184.0/255.0 blue:194.0/255.0 alpha:1.0] CGColor]
        ];
        CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)colors, locations);
        if (gradient) {
            CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), gradient, CGPointMake(0, 0), CGPointMake(0, CGRectGetMaxY(b)), 0);
            CGGradientRelease(gradient);
        }
    } else {
        CGFloat locations[] = {0.0, 1.0};
        NSArray *colors = @[
            (id)[[UIColor colorWithRed:202.0/255.0 green:184.0/255.0 blue:194.0/255.0 alpha:1.0] CGColor],
            (id)[[UIColor colorWithRed:188.0/255.0 green:171.0/255.0 blue:181.0/255.0 alpha:1.0] CGColor]
        ];
        CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)colors, locations);
        if (gradient) {
            CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), gradient, CGPointMake(0, 0), CGPointMake(0, CGRectGetMaxY(b)), 0);
            CGGradientRelease(gradient);
        }
    }
    CGColorSpaceRelease(space);
    [image drawInRect:b blendMode:kCGBlendModeNormal alpha:1.0];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)finishActiveFlipWithPendingText:(BOOL)applyPending {
    [_flipDisplayLink invalidate];
    _flipDisplayLink = nil;
    if (applyPending && [_flipPendingText length]) {
        _topStatic.hidden = NO;
        _bottomStatic.hidden = NO;
        _topStatic.text = _flipPendingText;
        _bottomStatic.text = _flipPendingText;
        [super setText:_flipPendingText];
    }
    [_flipTopPage removeFromSuperview];
    [_flipBottomPage removeFromSuperview];
    [_flipOldBottomPage removeFromSuperview];
    [_flipTopLight removeFromSuperview];
    [_flipBottomLight removeFromSuperview];
    [_flipTopEdgeLine removeFromSuperview];
    [_flipTopShade removeFromSuperview];
    _flipTopPage = nil;
    _flipBottomPage = nil;
    _flipOldBottomPage = nil;
    _flipTopLight = nil;
    _flipBottomLight = nil;
    _flipTopEdgeLine = nil;
    _flipTopShade = nil;
    _topStatic.layer.mask = nil;
    _topStaticRevealMask = nil;
    _topStatic.hidden = NO;
    _bottomStatic.hidden = NO;
    _flipHalfSwitched = NO;
    _flipFrameIndex = 0;
    _flipPendingText = nil;
}

- (CGFloat)flipEaseIn:(CGFloat)p {
    p = MAX(0.0, MIN(1.0, p));
    return p * p;
}

- (CGFloat)flipEaseOut:(CGFloat)p {
    p = MAX(0.0, MIN(1.0, p));
    CGFloat inv = 1.0 - p;
    return 1.0 - inv * inv;
}

- (CGFloat)flipTopRevealProgress:(CGFloat)p {
    p = MAX(0.0, MIN(1.0, p));
    return 0.35 * p + 0.65 * [self flipEaseOut:p];
}

- (CGFloat)flipPageLightAlphaForPhase:(CGFloat)phase topPage:(BOOL)topPage {
    if (!topPage) return 0.0;
    CGFloat firstHalf = MAX(0.0, MIN(1.0, phase / 0.5));
    return 0.08 * (1.0 - firstHalf);
}

- (void)updateFlipTopEdgeLineFrame {
    if (!_flipTopEdgeLine || !_flipTopPage) return;
    CGFloat lineHeight = 3.4 + 1.2 * MAX(0.0, MIN(1.0, (CGRectGetMinY(_flipTopPage.frame) - _flipTopRect.origin.y) / MAX(1.0, _flipTopRect.size.height)));
    _flipTopEdgeLine.frame = CGRectMake(_flipTopRect.origin.x, CGRectGetMinY(_flipTopPage.frame) - floor(lineHeight / 2.0), _flipTopRect.size.width, lineHeight);
    _flipTopEdgeLine.layer.shadowPath = [[UIBezierPath bezierPathWithRect:_flipTopEdgeLine.bounds] CGPath];
    _flipTopEdgeLine.layer.shadowOpacity = 0.72 + 0.28 * MAX(0.0, MIN(1.0, (CGRectGetMinY(_flipTopPage.frame) - _flipTopRect.origin.y) / MAX(1.0, _flipTopRect.size.height)));
}

- (void)updateFlipBottomEdgeLineFrame {
    if (!_flipTopEdgeLine || !_flipBottomPage) return;
    CGFloat local = MAX(0.0, MIN(1.0, _flipBottomPage.frame.size.height / MAX(1.0, _flipBottomRect.size.height)));
    CGFloat lineHeight = 4.6 - 0.7 * local;
    _flipTopEdgeLine.frame = CGRectMake(_flipBottomRect.origin.x, CGRectGetMaxY(_flipBottomPage.frame) - floor(lineHeight / 2.0), _flipBottomRect.size.width, lineHeight);
    _flipTopEdgeLine.layer.shadowPath = [[UIBezierPath bezierPathWithRect:_flipTopEdgeLine.bounds] CGPath];
    _flipTopEdgeLine.layer.shadowOpacity = 0.86 - 0.18 * local;
}

- (UIView *)newFlipTopEdgeLine {
    UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
    line.userInteractionEnabled = NO;
    line.backgroundColor = [_edgeAccentColor colorWithAlphaComponent:0.68];
    line.layer.zPosition = 21.0;
    line.layer.shadowColor = [[UIColor colorWithRed:80.0/255.0 green:18.0/255.0 blue:60.0/255.0 alpha:0.34] CGColor];
    line.layer.shadowOffset = CGSizeMake(0.0, 1.0);
    line.layer.shadowRadius = 1.1;
    line.layer.shadowOpacity = 0.72;
    UIView *highlight = [[UIView alloc] initWithFrame:CGRectZero];
    highlight.userInteractionEnabled = NO;
    highlight.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    highlight.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    highlight.frame = CGRectMake(0, 0, 1, 1.0);
    [line addSubview:highlight];
    return line;
}

- (UIView *)newFlipTopShade {
    UIView *shade = [[UIView alloc] initWithFrame:CGRectZero];
    shade.userInteractionEnabled = NO;
    shade.backgroundColor = [UIColor colorWithRed:28.0/255.0 green:13.0/255.0 blue:38.0/255.0 alpha:1.0];
    shade.alpha = 0.0;
    shade.layer.zPosition = 20.5;
    return shade;
}

- (void)updateTopStaticRevealHeight:(CGFloat)height {
    height = MAX(0.0, MIN(_flipTopRect.size.height, height));
    if (height <= 0.5) {
        if (!_topStaticRevealMask) {
            _topStaticRevealMask = [CALayer layer];
            _topStaticRevealMask.backgroundColor = [[UIColor blackColor] CGColor];
            _topStatic.layer.mask = _topStaticRevealMask;
        }
        _topStaticRevealMask.frame = CGRectMake(0, 0, _flipTopRect.size.width, 0.0);
        return;
    }
    if (height >= _flipTopRect.size.height - 0.5) {
        _topStatic.layer.mask = nil;
        _topStaticRevealMask = nil;
        return;
    }
    if (!_topStaticRevealMask) {
        _topStaticRevealMask = [CALayer layer];
        _topStaticRevealMask.backgroundColor = [[UIColor blackColor] CGColor];
        _topStatic.layer.mask = _topStaticRevealMask;
    }
    _topStaticRevealMask.frame = CGRectMake(0, 0, _flipTopRect.size.width, height);
}

- (void)stepFlipAnimation:(CADisplayLink *)link {
    _flipFrameIndex += 1;
    // Timer callbacks can be delayed on A5/A6 devices. Advance by elapsed
    // monotonic time so a missed frame cannot stretch into the next second.
    CGFloat phase = MIN(1.0, MAX(0.0, (CACurrentMediaTime() - _flipStartTime) / (32.0 / 45.0)));
    if (phase <= 0.5) {
        CGFloat progress = [self flipTopRevealProgress:phase / 0.5];
        CGFloat scale = MAX(0.02, 1.0 - 0.98 * progress);
        CGFloat height = MAX(1.0, floor(_flipTopRect.size.height * scale));
        _flipTopPage.frame = CGRectMake(_flipTopRect.origin.x, CGRectGetMaxY(_flipTopRect) - height, _flipTopRect.size.width, height);
        _flipTopPage.alpha = 1.0;
        _flipTopShade.frame = _flipTopPage.frame;
        _flipTopShade.alpha = 0.04 + 0.14 * progress;
        [self updateFlipTopEdgeLineFrame];
        _flipTopLight.frame = _flipTopPage.frame;
        _flipTopLight.alpha = [self flipPageLightAlphaForPhase:phase topPage:YES];
        [self updateTopStaticRevealHeight:_flipTopRect.size.height - height];
        _flipBottomPage.hidden = YES;
        _flipBottomLight.hidden = YES;
        _flipOldBottomPage.hidden = NO;
        _flipOldBottomPage.frame = _flipBottomRect;
        _flipOldBottomPage.layer.contentsRect = CGRectMake(0, 0, 1, 1);
        return;
    }

    if (!_flipHalfSwitched) {
        _flipHalfSwitched = YES;
        [_flipTopPage removeFromSuperview];
        [_flipTopLight removeFromSuperview];
        [_flipTopShade removeFromSuperview];
        _flipTopPage = nil;
        _flipTopLight = nil;
        _flipTopShade = nil;
        _flipBottomPage.hidden = NO;
        _flipBottomLight.hidden = NO;
        [self updateTopStaticRevealHeight:_flipTopRect.size.height];
    }

    CGFloat secondProgress = [self flipEaseOut:(phase - 0.5) / 0.5];
    CGFloat bottomScale = MIN(1.0, 0.02 + 0.98 * secondProgress);
    CGFloat bottomHeight = MAX(1.0, floor(_flipBottomRect.size.height * bottomScale));
    _flipBottomPage.frame = CGRectMake(_flipBottomRect.origin.x, _flipBottomRect.origin.y, _flipBottomRect.size.width, bottomHeight);
    _flipBottomPage.alpha = 1.0;
    [self updateFlipBottomEdgeLineFrame];
    _flipBottomLight.frame = _flipBottomPage.frame;
    _flipBottomLight.alpha = 0.0;
    CGFloat remaining = MAX(0.0, _flipBottomRect.size.height - bottomHeight);
    if (remaining <= 1.0) {
        _flipOldBottomPage.hidden = YES;
    } else {
        _flipOldBottomPage.hidden = NO;
        _flipOldBottomPage.frame = CGRectMake(_flipBottomRect.origin.x, _flipBottomRect.origin.y + bottomHeight, _flipBottomRect.size.width, remaining);
        _flipOldBottomPage.layer.contentsRect = CGRectMake(0, bottomHeight / _flipBottomRect.size.height, 1, remaining / _flipBottomRect.size.height);
    }
    if (phase >= 1.0) {
        [self finishActiveFlipWithPendingText:YES];
    }
}

- (void)setDigitText:(NSString *)text animated:(BOOL)animated {
    animated = animated && !self.hidden && !UIAccessibilityIsReduceMotionEnabled();
    NSString *oldText = self.text ?: @"";
    if ([oldText isEqualToString:text] && !_flipDisplayLink) return;
    if (![oldText length] || !animated || [oldText isEqualToString:text]) {
        [self finishActiveFlipWithPendingText:NO];
        self.text = text;
        return;
    }
    [self finishActiveFlipWithPendingText:NO];
    [_topFlip.layer removeAllAnimations];
    [_bottomFlip.layer removeAllAnimations];
    _topFlip.layer.transform = CATransform3DIdentity;
    _bottomFlip.layer.transform = CATransform3DIdentity;
    _topMask.hidden = YES;
    _bottomMask.hidden = YES;
    _topMask.text = @"";
    _bottomMask.text = @"";
    _topFlip.hidden = YES;
    _bottomFlip.hidden = YES;
    _topFlip.layer.transform = CATransform3DIdentity;
    _bottomFlip.layer.transform = CATransform3DIdentity;
    _topFlip.alpha = 0.0;
    _bottomFlip.alpha = 0.0;

    UIImage *oldImage = [self snapshotForDigitText:oldText includeCard:NO];
    UIImage *newImage = [self snapshotForDigitText:text includeCard:NO];
    CGFloat half = floor(_contentView.bounds.size.height / 2.0);
    CGRect topRect = CGRectMake(0, 0, _contentView.bounds.size.width, half);
    CGRect bottomRect = CGRectMake(0, half, _contentView.bounds.size.width, _contentView.bounds.size.height - half);
    UIImage *oldTop = [self cropImage:oldImage rect:topRect];
    UIImage *oldBottom = [self cropImage:oldImage rect:bottomRect];
    UIImage *newBottom = [self cropImage:newImage rect:bottomRect];
    if (!oldTop || !oldBottom || !newBottom || CGRectIsEmpty(topRect) || CGRectIsEmpty(bottomRect)) {
        self.text = text;
        return;
    }

    _topStatic.text = text;
    _bottomStatic.text = text;
    _topStatic.hidden = NO;
    _bottomStatic.hidden = YES;
    _flipTopRect = topRect;
    [self updateTopStaticRevealHeight:0.0];
    [super setText:text];

    UIImageView *topPage = [[UIImageView alloc] initWithImage:oldTop];
    topPage.frame = topRect;
    topPage.clipsToBounds = YES;
    topPage.contentMode = UIViewContentModeScaleToFill;
    topPage.layer.allowsEdgeAntialiasing = YES;
    topPage.layer.zPosition = 20.0;
    [_contentView addSubview:topPage];
    UIView *topShade = [self newFlipTopShade];
    topShade.frame = topPage.frame;
    [_contentView addSubview:topShade];
    UIView *topEdgeLine = [self newFlipTopEdgeLine];
    [_contentView addSubview:topEdgeLine];
    IWFlipPageLight *topLight = [[IWFlipPageLight alloc] initWithTop:YES];
    topLight.frame = topPage.frame;
    topLight.alpha = [self flipPageLightAlphaForPhase:0.0 topPage:YES];
    topLight.layer.zPosition = 22.0;
    [_contentView addSubview:topLight];

    UIImageView *oldBottomPage = [[UIImageView alloc] initWithImage:oldBottom];
    oldBottomPage.frame = bottomRect;
    oldBottomPage.clipsToBounds = YES;
    oldBottomPage.contentMode = UIViewContentModeScaleToFill;
    oldBottomPage.layer.allowsEdgeAntialiasing = YES;
    oldBottomPage.layer.zPosition = 15.0;
    oldBottomPage.layer.contentsRect = CGRectMake(0, 0, 1, 1);
    [_contentView addSubview:oldBottomPage];

    UIImageView *bottomPage = [[UIImageView alloc] initWithImage:newBottom];
    bottomPage.frame = bottomRect;
    bottomPage.clipsToBounds = YES;
    bottomPage.contentMode = UIViewContentModeScaleToFill;
    bottomPage.hidden = YES;
    bottomPage.alpha = 1.0;
    bottomPage.layer.allowsEdgeAntialiasing = YES;
    bottomPage.layer.zPosition = 20.0;
    bottomPage.frame = CGRectMake(bottomRect.origin.x, bottomRect.origin.y, bottomRect.size.width, MAX(1.0, floor(bottomRect.size.height * 0.02)));
    [_contentView addSubview:bottomPage];
    IWFlipPageLight *bottomLight = [[IWFlipPageLight alloc] initWithTop:NO];
    bottomLight.frame = bottomPage.frame;
    bottomLight.hidden = YES;
    bottomLight.alpha = 0.0;
    bottomLight.layer.zPosition = 21.0;
    [_contentView addSubview:bottomLight];
    _flipTopPage = topPage;
    _flipBottomPage = bottomPage;
    _flipOldBottomPage = oldBottomPage;
    _flipTopLight = topLight;
    _flipBottomLight = bottomLight;
    _flipTopEdgeLine = topEdgeLine;
    _flipTopShade = topShade;
    _flipTopRect = topRect;
    _flipBottomRect = bottomRect;
    [self updateFlipTopEdgeLineFrame];
    _flipPendingText = [text copy];
    _flipHalfSwitched = NO;
    _flipFrameIndex = 0;
    _flipStartTime = CACurrentMediaTime();
    _flipDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepFlipAnimation:)];
    _flipDisplayLink.frameInterval = 1;
    [_flipDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)showDebugFlipFromText:(NSString *)oldText toText:(NSString *)text phase:(CGFloat)phase {
    [self finishActiveFlipWithPendingText:NO];
    phase = MAX(0.0, MIN(1.0, phase));
    UIImage *oldImage = [self snapshotForDigitText:oldText includeCard:NO];
    UIImage *newImage = [self snapshotForDigitText:text includeCard:NO];
    CGFloat half = floor(_contentView.bounds.size.height / 2.0);
    CGRect topRect = CGRectMake(0, 0, _contentView.bounds.size.width, half);
    CGRect bottomRect = CGRectMake(0, half, _contentView.bounds.size.width, _contentView.bounds.size.height - half);
    UIImage *oldTop = [self cropImage:oldImage rect:topRect];
    UIImage *oldBottom = [self cropImage:oldImage rect:bottomRect];
    UIImage *newBottom = [self cropImage:newImage rect:bottomRect];
    if (!oldTop || !oldBottom || !newBottom || CGRectIsEmpty(topRect) || CGRectIsEmpty(bottomRect)) {
        self.text = text;
        return;
    }

    _topStatic.text = text;
    _bottomStatic.text = text;
    _topStatic.hidden = NO;
    _bottomStatic.hidden = YES;
    [super setText:text];

    CGFloat visibleOldBottomOffset = 0.0;
    if (phase >= 0.5) {
        CGFloat local = [self flipEaseOut:((phase - 0.5) / 0.5)];
        visibleOldBottomOffset = MAX(1.0, floor(bottomRect.size.height * MIN(1.0, 0.02 + 0.98 * local)));
    }
    CGFloat oldRemaining = MAX(0.0, bottomRect.size.height - visibleOldBottomOffset);
    if (oldRemaining > 1.0) {
        UIImageView *oldBottomPage = [[UIImageView alloc] initWithImage:oldBottom];
        oldBottomPage.frame = CGRectMake(bottomRect.origin.x, bottomRect.origin.y + visibleOldBottomOffset, bottomRect.size.width, oldRemaining);
        oldBottomPage.clipsToBounds = YES;
        oldBottomPage.contentMode = UIViewContentModeScaleToFill;
        oldBottomPage.layer.zPosition = 15.0;
        oldBottomPage.layer.contentsRect = CGRectMake(0, visibleOldBottomOffset / bottomRect.size.height, 1, oldRemaining / bottomRect.size.height);
        [_contentView addSubview:oldBottomPage];
        _flipOldBottomPage = oldBottomPage;
    }

    if (phase < 0.5) {
        CGFloat local = [self flipTopRevealProgress:(phase / 0.5)];
        CGFloat scale = MAX(0.02, 1.0 - 0.98 * local);
        CGFloat height = MAX(1.0, floor(topRect.size.height * scale));
        _flipTopRect = topRect;
        [self updateTopStaticRevealHeight:topRect.size.height - height];
        UIImageView *topPage = [[UIImageView alloc] initWithImage:oldTop];
        topPage.frame = CGRectMake(topRect.origin.x, CGRectGetMaxY(topRect) - height, topRect.size.width, height);
        topPage.clipsToBounds = YES;
        topPage.contentMode = UIViewContentModeScaleToFill;
        topPage.layer.zPosition = 20.0;
        [_contentView addSubview:topPage];
        UIView *topShade = [self newFlipTopShade];
        topShade.frame = topPage.frame;
        topShade.alpha = 0.04 + 0.14 * local;
        [_contentView addSubview:topShade];
        UIView *topEdgeLine = [self newFlipTopEdgeLine];
        [_contentView addSubview:topEdgeLine];
        IWFlipPageLight *topLight = [[IWFlipPageLight alloc] initWithTop:YES];
        topLight.frame = topPage.frame;
        topLight.alpha = [self flipPageLightAlphaForPhase:phase topPage:YES];
        topLight.layer.zPosition = 22.0;
        [_contentView addSubview:topLight];
        _flipTopPage = topPage;
        _flipTopLight = topLight;
        _flipTopEdgeLine = topEdgeLine;
        _flipTopShade = topShade;
        [self updateFlipTopEdgeLineFrame];
    } else {
        _topStatic.layer.mask = nil;
        _topStaticRevealMask = nil;
        CGFloat local = [self flipEaseOut:((phase - 0.5) / 0.5)];
        CGFloat scale = MIN(1.0, 0.02 + 0.98 * local);
        CGFloat height = MAX(1.0, floor(bottomRect.size.height * scale));
        UIImageView *bottomPage = [[UIImageView alloc] initWithImage:newBottom];
        bottomPage.frame = CGRectMake(bottomRect.origin.x, bottomRect.origin.y, bottomRect.size.width, height);
        bottomPage.clipsToBounds = YES;
        bottomPage.contentMode = UIViewContentModeScaleToFill;
        bottomPage.alpha = 1.0;
        bottomPage.layer.zPosition = 20.0;
        [_contentView addSubview:bottomPage];
        UIView *topEdgeLine = [self newFlipTopEdgeLine];
        [_contentView addSubview:topEdgeLine];
        IWFlipPageLight *bottomLight = [[IWFlipPageLight alloc] initWithTop:NO];
        bottomLight.frame = bottomPage.frame;
        bottomLight.alpha = 0.0;
        bottomLight.layer.zPosition = 22.0;
        [_contentView addSubview:bottomLight];
        _flipBottomPage = bottomPage;
        _flipBottomLight = bottomLight;
        _flipTopEdgeLine = topEdgeLine;
        _flipBottomRect = bottomRect;
        [self updateFlipBottomEdgeLineFrame];
    }
}

@end

static NSArray *IWGalleryCategoryDefinitions(void) {
    return @[
        @{@"id": @"", @"title": @"全部"},
        @{@"id": @"artwork", @"title": @"壁纸"},
        @{@"id": @"people", @"title": @"人物"},
        @{@"id": @"places", @"title": @"地点"},
        @{@"id": @"ultimate", @"title": @"终极版"},
        @{@"id": @"vintage", @"title": @"怀旧内容包"},
        @{@"id": @"video", @"title": @"视频"},
        @{@"id": @"user", @"title": @"系统照片"},
        @{@"id": @"other", @"title": @"其他"}
    ];
}

static NSString *IWGalleryCategoryForItem(NSDictionary *item) {
    id type = [item objectForKey:@"type"];
    if ([type isKindOfClass:[NSString class]] && [type isEqualToString:@"video"]) return @"video";
    id key = [item objectForKey:@"key"];
    if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"user-"]) return @"user";
    id category = [item objectForKey:@"category"];
    if ([category isKindOfClass:[NSString class]] && [category length]) {
        for (NSDictionary *definition in IWGalleryCategoryDefinitions()) {
            if ([category isEqualToString:[definition objectForKey:@"id"]]) return category;
        }
    }
    return @"other";
}

@interface IWGalleryCell : UICollectionViewCell
- (void)configure:(NSDictionary *)item image:(UIImage *)image selected:(BOOL)selected favorite:(BOOL)favorite deleteMode:(BOOL)deleteMode deleteSelected:(BOOL)deleteSelected deletable:(BOOL)deletable;
@end

@implementation IWGalleryCell {
    UIImageView *_imageView;
    UILabel *_label;
    IWIconButton *_favoriteMark;
    IWIconButton *_playMark;
    UIView *_deleteShade;
    UILabel *_deleteMark;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    self.layer.borderWidth = 2.0;
    self.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.34] CGColor];
    self.layer.cornerRadius = 8.0;
    self.clipsToBounds = YES;
    _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.clipsToBounds = YES;
    [self.contentView addSubview:_imageView];
    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.backgroundColor = [UIColor colorWithRed:12.0/255.0 green:10.0/255.0 blue:28.0/255.0 alpha:0.78];
    _label.textColor = [UIColor whiteColor];
    _label.font = IWGTATextFont(12.0);
    _label.textAlignment = NSTextAlignmentCenter;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_label];
    _favoriteMark = [IWIconButton buttonWithType:UIButtonTypeCustom];
    _favoriteMark.kind = IWButtonKindHeart;
    _favoriteMark.iconColor = IWThemePink(1.0);
    _favoriteMark.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.68];
    _favoriteMark.layer.cornerRadius = 15.0;
    _favoriteMark.layer.borderWidth = 1.4;
    _favoriteMark.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.72] CGColor];
    _favoriteMark.clipsToBounds = YES;
    _favoriteMark.hidden = YES;
    _favoriteMark.userInteractionEnabled = NO;
    [self.contentView addSubview:_favoriteMark];
    _playMark = [IWIconButton buttonWithType:UIButtonTypeCustom];
    _playMark.kind = IWButtonKindPlay;
    _playMark.iconColor = [UIColor whiteColor];
    _playMark.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.74];
    _playMark.layer.cornerRadius = 18.0;
    _playMark.layer.borderWidth = 1.4;
    _playMark.layer.borderColor = [[UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.78] CGColor];
    _playMark.clipsToBounds = YES;
    _playMark.hidden = YES;
    _playMark.userInteractionEnabled = NO;
    [self.contentView addSubview:_playMark];
    _deleteShade = [[UIView alloc] initWithFrame:CGRectZero];
    _deleteShade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.36];
    _deleteShade.hidden = YES;
    _deleteShade.userInteractionEnabled = NO;
    [self.contentView addSubview:_deleteShade];
    _deleteMark = [[UILabel alloc] initWithFrame:CGRectZero];
    _deleteMark.text = @"✓";
    _deleteMark.textAlignment = NSTextAlignmentCenter;
    _deleteMark.textColor = [UIColor whiteColor];
    _deleteMark.font = IWGTATextFont(21.0);
    _deleteMark.backgroundColor = IWThemePink(0.92);
    _deleteMark.layer.cornerRadius = 15.0;
    _deleteMark.layer.borderWidth = 1.6;
    _deleteMark.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.85] CGColor];
    _deleteMark.clipsToBounds = YES;
    _deleteMark.hidden = YES;
    _deleteMark.userInteractionEnabled = NO;
    [self.contentView addSubview:_deleteMark];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    _imageView.frame = CGRectMake(0, 0, b.size.width, b.size.height - 30.0);
    _label.frame = CGRectMake(0, b.size.height - 30.0, b.size.width, 30.0);
    _favoriteMark.frame = CGRectMake(b.size.width - 40.0, 10.0, 30.0, 30.0);
    _playMark.frame = CGRectMake(round((b.size.width - 36.0) / 2.0), round((_imageView.frame.size.height - 36.0) / 2.0), 36.0, 36.0);
    _deleteShade.frame = _imageView.frame;
    _deleteMark.frame = CGRectMake(10.0, 10.0, 30.0, 30.0);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _imageView.image = nil;
    _label.text = @"";
    _favoriteMark.hidden = YES;
    _playMark.hidden = YES;
    _deleteShade.hidden = YES;
    _deleteMark.hidden = YES;
    self.alpha = 1.0;
    [_favoriteMark setNeedsDisplay];
}

- (void)configure:(NSDictionary *)item image:(UIImage *)image selected:(BOOL)selected favorite:(BOOL)favorite deleteMode:(BOOL)deleteMode deleteSelected:(BOOL)deleteSelected deletable:(BOOL)deletable {
    _imageView.image = image;
    _label.text = [item objectForKey:@"label"] ?: @"";
    BOOL video = [[[item objectForKey:@"type"] lowercaseString] isEqualToString:@"video"];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [_label.text length] ? _label.text : @"壁纸";
    self.accessibilityValue = favorite ? (video ? @"视频，已收藏" : @"图片，已收藏") : (video ? @"视频" : @"图片");
    self.accessibilityTraits = UIAccessibilityTraitButton | ((deleteMode ? deleteSelected : selected) ? UIAccessibilityTraitSelected : 0);
    _favoriteMark.hidden = !favorite;
    [_favoriteMark setNeedsDisplay];
    _playMark.hidden = !video;
    [_playMark setNeedsDisplay];
    _deleteShade.hidden = YES;
    _deleteMark.hidden = !(deleteMode && deleteSelected);
    self.alpha = 1.0;
    if (deleteMode && deleteSelected) {
        self.layer.borderColor = [IWThemePink(1.0) CGColor];
    } else {
        self.layer.borderColor = selected ? [[UIColor whiteColor] CGColor] : [[UIColor colorWithWhite:1 alpha:0.34] CGColor];
    }
}

@end

@class IWRootViewController;

@interface IWGalleryController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate>
@property (nonatomic, strong) UIImage *backdropImage;
- (instancetype)initWithOwner:(IWRootViewController *)owner items:(NSArray *)items selected:(NSInteger)selected favorites:(NSDictionary *)favorites cache:(NSCache *)cache;
- (void)enableFavoriteConfirmMode;
- (void)locateTapped;
- (void)reloadAfterImportedIndex:(NSInteger)index;
- (void)debugOpenPhotoPicker;
- (void)debugClosePhotoPicker;
- (void)debugEnterDeleteMode;
- (void)categoryTapped;
- (void)selectCategory:(NSString *)category;
- (NSDictionary *)categoryDebugState;
@end

@interface IWMenuGlassBackdrop : UIView
@end

@implementation IWMenuGlassBackdrop {
    UIVisualEffectView *_blur;
    CAGradientLayer *_rim;
    CAShapeLayer *_rimMask;
    CGRect _rimBounds;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.layer.cornerRadius = 8.0;
    self.clipsToBounds = YES;
    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _blur.userInteractionEnabled = NO;
    [self addSubview:_blur];
    _rim = [CAGradientLayer layer];
    _rim.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.66].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor];
    _rim.locations = @[@0, @0.48, @1];
    _rim.startPoint = CGPointMake(0, 0);
    _rim.endPoint = CGPointMake(1, 1);
    _rimMask = [CAShapeLayer layer];
    _rimMask.fillColor = [UIColor clearColor].CGColor;
    _rimMask.strokeColor = [UIColor whiteColor].CGColor;
    _rimMask.lineWidth = 1.0;
    _rim.mask = _rimMask;
    [self.layer addSublayer:_rim];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transparencyChanged:) name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
    [self transparencyChanged:nil];
    return self;
}
- (void)transparencyChanged:(NSNotification *)notification {
    (void)notification;
    BOOL reduced = UIAccessibilityIsReduceTransparencyEnabled();
    _blur.hidden = reduced;
    self.backgroundColor = reduced ? [UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1] : [UIColor clearColor];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _blur.frame = self.bounds;
    if (CGRectEqualToRect(_rimBounds, self.bounds) || CGRectIsEmpty(self.bounds)) return;
    _rimBounds = self.bounds;
    _rim.frame = self.bounds;
    _rimMask.frame = self.bounds;
    _rimMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.5, 0.5) cornerRadius:7.5].CGPath;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

@interface IWRootViewController : UIViewController <UIGestureRecognizerDelegate, CLLocationManagerDelegate>
- (void)selectWallpaper:(NSInteger)index;
- (void)toggleFavorite:(NSInteger)index;
- (void)addFavorite:(NSInteger)index;
- (BOOL)isFavorite:(NSInteger)index;
- (NSArray *)galleryItemsForCurrentFilter;
- (NSArray *)allGalleryItems;
- (NSArray *)favoriteGalleryItems;
- (void)confirmFavoriteGalleryModeFromIndex:(NSInteger)index;
- (BOOL)openGalleryMediaAtIndex:(NSInteger)index;
- (NSInteger)importSystemImage:(UIImage *)image;
- (NSInteger)deleteWallpapersAtIndexes:(NSArray *)indexes;
- (BOOL)canDeleteWallpaperAtIndex:(NSInteger)index;
- (void)writeDebugState:(NSString *)context;
- (void)surfaceTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)surfaceTouchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)surfaceTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)surfaceTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (BOOL)canHandleApplicationSurfaceTouchAtPoint:(CGPoint)point;
- (void)handleApplicationSurfaceSwipeFrom:(CGPoint)start to:(CGPoint)end;
- (void)handleDebugCommand:(NSString *)command;
- (void)returnToMainScreen;
- (void)restoreDisplayAfterSystemLock;
- (void)commitEditModeForLifecycle;
- (void)persistCurrentEditValues;
- (void)selectClockOrDateEditTargetAtPoint:(CGPoint)p;
- (BOOL)moveEditControlsToOrigin:(CGPoint)origin persist:(BOOL)persist;
- (BOOL)accessibilityMoveEditControlsLeft:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsRight:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsUp:(UIAccessibilityCustomAction *)action;
- (BOOL)accessibilityMoveEditControlsDown:(UIAccessibilityCustomAction *)action;
- (void)showWeatherAttribution;
- (void)runWeatherCreditAudit;
@end

static BOOL IWApplyWallpaperLoadIfCurrent(NSUInteger generation, NSUInteger activeGeneration, NSArray *wallpapers, NSInteger wallpaperIndex, NSString *expectedKey, NSString *expectedPath, void (^update)(void)) {
    if (generation == 0 || generation != activeGeneration || wallpaperIndex < 0 || wallpaperIndex >= [wallpapers count]) return NO;
    id item = [wallpapers objectAtIndex:wallpaperIndex];
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    id key = [item objectForKey:@"key"];
    id path = [item objectForKey:@"imagePath"];
    if (![key isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSString class]] ||
        ![key isEqualToString:expectedKey] || ![path isEqualToString:expectedPath]) return NO;
    if (update) update();
    return YES;
}

static NSUInteger IWNextWallpaperLoadGeneration(NSUInteger *activeGeneration) {
    if (!activeGeneration) return 0;
    *activeGeneration += 1;
    if (*activeGeneration == 0) *activeGeneration = 1;
    return *activeGeneration;
}

@interface IWSurfaceView : UIView
@property (nonatomic, assign) IWRootViewController *owner;
@end

@implementation IWSurfaceView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(self.bounds, point);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.hidden && self.userInteractionEnabled && self.alpha > 0.01 && [self pointInside:point withEvent:event]) return self;
    return nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesCancelled:touches withEvent:event];
}

@end

@interface IWRootSurfaceView : UIView
@property (nonatomic, assign) IWRootViewController *owner;
@end

@implementation IWRootSurfaceView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if ([hit isKindOfClass:[IWSurfaceView class]]) return hit;
    UIView *view = hit;
    while (view && view != self) {
        if ([view isKindOfClass:[UIControl class]] || [view isKindOfClass:[UIScrollView class]]) return hit;
        view = view.superview;
    }
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [_owner surfaceTouchesCancelled:touches withEvent:event];
}

@end

@implementation IWGalleryController {
    IWRootViewController *_owner;
    NSArray *_items;
    NSInteger _selected;
    NSDictionary *_favorites;
    NSCache *_cache;
    NSOperationQueue *_thumbnailQueue;
    NSMutableSet *_thumbnailLoads;
    UICollectionView *_collection;
    UIRefreshControl *_refreshControl;
    UIView *_loadingPanel;
    UIView *_loadingTrack;
    UIView *_loadingFill;
    UILabel *_loading;
    UIView *_bar;
    IWIconButton *_addButton;
    IWIconButton *_favoriteButton;
    UIButton *_categoryButton;
    NSString *_categoryFilter;
    IWIconButton *_locateButton;
    IWIconButton *_closeButton;
    IWIconButton *_topButton;
    IWIconButton *_editButton;
    IWIconButton *_deleteCancelButton;
    IWIconButton *_deleteDoneButton;
    IWIconButton *_batchFavoriteButton;
    IWIconButton *_batchDeleteButton;
    UILabel *_deleteTitleLabel;
    UIPopoverController *_photoPopover;
    UILabel *_emptyLabel;
    NSMutableSet *_deleteSelection;
    NSInteger _galleryColumns;
    NSInteger _pinchBaseColumns;
    NSInteger _pendingLocateIndex;
    UIInterfaceOrientation _orientationBeforePicker;
    CGPoint _allGalleryContentOffset;
    NSInteger _preloadGeneration;
    BOOL _favoriteFilterOnly;
    BOOL _favoriteConfirmMode;
    BOOL _deleteMode;
    BOOL _loadingComplete;
    BOOL _hasAllGalleryContentOffset;
}

- (instancetype)initWithOwner:(IWRootViewController *)owner items:(NSArray *)items selected:(NSInteger)selected favorites:(NSDictionary *)favorites cache:(NSCache *)cache {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _owner = owner;
    _items = [items copy];
    _selected = selected;
    _favorites = [favorites copy] ?: @{};
    _cache = cache ?: [[NSCache alloc] init];
    _thumbnailQueue = [[NSOperationQueue alloc] init];
    _thumbnailQueue.maxConcurrentOperationCount = 2;
    _thumbnailLoads = [NSMutableSet set];
    _galleryColumns = 4;
    _pendingLocateIndex = -1;
    _orientationBeforePicker = UIInterfaceOrientationLandscapeLeft;
    _allGalleryContentOffset = CGPointZero;
    _preloadGeneration = 0;
    _deleteSelection = [[NSMutableSet alloc] init];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    return self;
}

- (void)enableFavoriteConfirmMode {
    _favoriteConfirmMode = YES;
    _favoriteFilterOnly = YES;
    _items = [[_owner favoriteGalleryItems] copy];
    if ([_items count]) _selected = [[[_items objectAtIndex:0] objectForKey:@"index"] integerValue];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return IWCurrentLandscapeOrientation(); }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)shouldAutorotate { return YES; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.alpha = 0.0;
    _collection.transform = CGAffineTransformMakeTranslation(0, 42.0);
    _bar.transform = CGAffineTransformMakeTranslation(0, -42.0);
    [UIView animateWithDuration:IWPanelAnimationDuration()
                          delay:0
         usingSpringWithDamping:IWPanelSpringDamping()
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.alpha = 1.0;
        _collection.transform = CGAffineTransformIdentity;
        _bar.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:9.0/255.0 green:8.0/255.0 blue:24.0/255.0 alpha:1.0];
    self.view.opaque = YES;
    // Reuse the decoded wallpaper without carrying clock/calendar overlays.
    UIImageView *backdrop = [[UIImageView alloc] initWithImage:self.backdropImage];
    backdrop.frame = self.view.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.contentMode = UIViewContentModeScaleAspectFill;
    backdrop.clipsToBounds = YES;
    backdrop.userInteractionEnabled = NO;
    backdrop.alpha = 0.20;
    [self.view addSubview:backdrop];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.sectionInset = UIEdgeInsetsMake(84, 28, 24, 28);
    layout.minimumInteritemSpacing = 12;
    layout.minimumLineSpacing = 16;
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collection.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.42];
    _collection.dataSource = self;
    _collection.delegate = self;
    [_collection registerClass:[IWGalleryCell class] forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:_collection];
    _refreshControl = [[UIRefreshControl alloc] init];
    _refreshControl.tintColor = [UIColor whiteColor];
    [_refreshControl addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventValueChanged];
    [_collection addSubview:_refreshControl];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    longPress.minimumPressDuration = 0.45;
    [_collection addGestureRecognizer:longPress];
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    [_collection addGestureRecognizer:pinch];

    _bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 70)];
    _bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _bar.backgroundColor = [UIColor colorWithRed:9.0/255.0 green:8.0/255.0 blue:24.0/255.0 alpha:1.0];
    [self.view addSubview:_bar];
    _addButton = [self button:IWButtonKindAdd];
    _addButton.frame = CGRectMake(28.0, 18, IWControlSize(), IWControlSize());
    _addButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [_addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_addButton];

    _favoriteButton = [self button:IWButtonKindHeart];
    _favoriteButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize() * 3.0 - IWControlGap() * 2.0, 18, IWControlSize(), IWControlSize());
    _favoriteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_favoriteButton addTarget:self action:@selector(favoriteFilterTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_favoriteButton];

    _locateButton = [self button:IWButtonKindLocate];
    _locateButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize() * 2.0 - IWControlGap(), 18, IWControlSize(), IWControlSize());
    _locateButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_locateButton addTarget:self action:@selector(locateTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_locateButton];

    _closeButton = [self button:IWButtonKindDown];
    _closeButton.frame = CGRectMake(round((self.view.bounds.size.width - IWControlSize()) / 2.0), 18, IWControlSize(), IWControlSize());
    _closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_closeButton];

    _topButton = [self button:IWButtonKindTop];
    _topButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize(), 18, IWControlSize(), IWControlSize());
    _topButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_topButton addTarget:self action:@selector(topTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_topButton];

    _editButton = [self button:IWButtonKindCheck];
    _editButton.accessibilityLabel = @"批量选择";
    _editButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize() * 4.0 - IWControlGap() * 3.0, 18, IWControlSize(), IWControlSize());
    _editButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_editButton addTarget:self action:@selector(editTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_editButton];

    _categoryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _categoryButton.layer.borderWidth = IWControlBorderWidth();
    _categoryButton.layer.cornerRadius = IWControlRadius();
    _categoryButton.clipsToBounds = YES;
    CGFloat categoryWidth = 170.0;
    _categoryButton.frame = CGRectMake(CGRectGetMinX(_editButton.frame) - IWControlGap() - categoryWidth, 18, categoryWidth, IWControlSize());
    _categoryButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _categoryButton.titleLabel.font = IWGTATextFont(15.0);
    _categoryButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _categoryButton.titleLabel.minimumScaleFactor = 0.75;
    [_categoryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _categoryButton.accessibilityLabel = @"图库分类";
    [_categoryButton addTarget:self action:@selector(categoryTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_categoryButton];

    _deleteCancelButton = [self button:IWButtonKindClose];
    _deleteCancelButton.frame = CGRectMake(28.0, 18, IWControlSize(), IWControlSize());
    _deleteCancelButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [_deleteCancelButton addTarget:self action:@selector(cancelDeleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_deleteCancelButton];

    _deleteDoneButton = [self button:IWButtonKindCheck];
    _deleteDoneButton.frame = CGRectMake(28.0 + IWControlSize() + IWControlGap(), 18, IWControlSize(), IWControlSize());
    _deleteDoneButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [_deleteDoneButton addTarget:self action:@selector(doneDeleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_deleteDoneButton];

    _batchFavoriteButton = [self button:IWButtonKindHeart];
    _batchFavoriteButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize() * 2.0 - IWControlGap(), 18, IWControlSize(), IWControlSize());
    _batchFavoriteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_batchFavoriteButton addTarget:self action:@selector(confirmFavoriteTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_batchFavoriteButton];

    _batchDeleteButton = [self button:IWButtonKindDelete];
    _batchDeleteButton.iconColor = [UIColor colorWithRed:1.0 green:70.0/255.0 blue:86.0/255.0 alpha:1.0];
    _batchDeleteButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize(), 18, IWControlSize(), IWControlSize());
    _batchDeleteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_batchDeleteButton addTarget:self action:@selector(confirmDeleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [_bar addSubview:_batchDeleteButton];

    _deleteTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(140.0, 18.0, self.view.bounds.size.width - 280.0, IWControlSize())];
    _deleteTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _deleteTitleLabel.textAlignment = NSTextAlignmentCenter;
    _deleteTitleLabel.textColor = [UIColor whiteColor];
    _deleteTitleLabel.font = IWGTATextFont(19.0);
    [_bar addSubview:_deleteTitleLabel];

    _loadingPanel = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - 184) / 2, self.view.bounds.size.height - 66, 184, 42)];
    _loadingPanel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _loadingPanel.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.68];
    _loadingPanel.layer.cornerRadius = 21.0;
    _loadingPanel.layer.borderWidth = IWControlBorderWidth();
    _loadingPanel.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.46] CGColor];
    _loadingPanel.clipsToBounds = YES;
    [self.view addSubview:_loadingPanel];

    _loading = [[UILabel alloc] initWithFrame:CGRectMake(16, 5, 152, 16)];
    _loading.text = @"0%";
    _loading.textColor = [UIColor whiteColor];
    _loading.font = IWGTATextFont(12.0);
    _loading.textAlignment = NSTextAlignmentCenter;
    [_loadingPanel addSubview:_loading];

    _loadingTrack = [[UIView alloc] initWithFrame:CGRectMake(18, 25, 148, 5)];
    _loadingTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    _loadingTrack.layer.cornerRadius = 2.5;
    _loadingTrack.clipsToBounds = YES;
    [_loadingPanel addSubview:_loadingTrack];

    _loadingFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 5)];
    _loadingFill.backgroundColor = IWThemePink(0.92);
    _loadingFill.layer.cornerRadius = 2.5;
    [_loadingTrack addSubview:_loadingFill];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"Empty";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = IWThemePink(0.96);
    _emptyLabel.font = IWGTAFont(46.0);
    _emptyLabel.layer.shadowColor = [[UIColor colorWithRed:52.0/255.0 green:18.0/255.0 blue:58.0/255.0 alpha:0.42] CGColor];
    _emptyLabel.layer.shadowOffset = CGSizeMake(0, 5.0);
    _emptyLabel.layer.shadowRadius = 12.0;
    _emptyLabel.layer.shadowOpacity = 1.0;
    _emptyLabel.userInteractionEnabled = NO;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
    if ([self cacheContainsAllItems]) {
        _loadingComplete = YES;
        _loadingPanel.hidden = YES;
        [_collection reloadData];
    } else {
        [self preloadReset:NO];
    }
    [self updateFavoriteFilterUI];
    [self updateDeleteModeUI];
    [self updateEmptyState];
}

- (IWIconButton *)button:(IWButtonKind)kind {
    IWIconButton *b = [IWIconButton buttonWithType:UIButtonTypeCustom];
    b.kind = kind;
    b.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.58];
    b.layer.borderWidth = IWControlBorderWidth();
    b.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.68] CGColor];
    b.layer.cornerRadius = IWControlRadius();
    b.clipsToBounds = YES;
    return b;
}

- (void)preloadReset:(BOOL)reset {
    NSInteger generation = ++_preloadGeneration;
    NSArray *items = [_items copy];
    if (reset) [_cache removeAllObjects];
    _loadingComplete = NO;
    _loadingPanel.hidden = NO;
    _emptyLabel.hidden = YES;
    _loading.text = @"0%";
    _loadingFill.frame = CGRectMake(0, 0, 0, _loadingTrack.bounds.size.height);
    [self updateFavoriteFilterUI];
    [self updateDeleteModeUI];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger i;
        NSInteger preloadCount = MIN((NSInteger)[items count], 12);
        NSInteger total = MAX(1, preloadCount);
        for (i = 0; i < preloadCount; i += 1) {
            NSDictionary *item = [items objectAtIndex:i];
            NSString *key = [item objectForKey:@"imagePath"];
            if (!reset && [_cache objectForKey:key]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != _preloadGeneration) return;
                    [self updateLoadingProgress:i + 1 total:total];
                });
                continue;
            }
            @autoreleasepool {
                IWCacheThumbnail(_cache, IWDecodedThumbnail(item), key);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != _preloadGeneration) return;
                [self updateLoadingProgress:i + 1 total:total];
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != _preloadGeneration) return;
            _loadingComplete = YES;
            [self updateLoadingProgress:total total:total];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (generation != _preloadGeneration) return;
                _loadingPanel.hidden = YES;
                [self updateEmptyState];
                [self updateFavoriteFilterUI];
                [self updateDeleteModeUI];
            });
            if ([_refreshControl isRefreshing]) [_refreshControl endRefreshing];
            [_collection reloadData];
            if (_pendingLocateIndex >= 0) {
                _selected = _pendingLocateIndex;
                [self scrollToSelectedAnimated:YES];
            } else {
                [_collection setContentOffset:CGPointMake(0, -_collection.contentInset.top) animated:reset];
            }
        });
    });
}

- (void)updateLoadingProgress:(NSInteger)done total:(NSInteger)total {
    CGFloat progress = total <= 0 ? 1.0 : MAX(0.0, MIN(1.0, (CGFloat)done / (CGFloat)total));
    _loading.text = [NSString stringWithFormat:@"%.0f%%", progress * 100.0];
    CGRect fill = _loadingFill.frame;
    fill.size.width = round(_loadingTrack.bounds.size.width * progress);
    fill.size.height = _loadingTrack.bounds.size.height;
    _loadingFill.frame = fill;
}

- (BOOL)cacheContainsAllItems {
    for (NSDictionary *item in _items) {
        NSString *key = [item objectForKey:@"imagePath"];
        if (![_cache objectForKey:key]) return NO;
    }
    return YES;
}

- (void)loadVisibleThumbnailAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item >= [_items count]) return;
    NSDictionary *item = [_items objectAtIndex:indexPath.item];
    NSString *path = [item objectForKey:@"imagePath"];
    if (![path length] || [_thumbnailLoads containsObject:path]) return;
    [_thumbnailLoads addObject:path];
    [_thumbnailQueue addOperationWithBlock:^{
        @autoreleasepool {
            UIImage *image = IWDecodedThumbnail(item);
            dispatch_async(dispatch_get_main_queue(), ^{
                [_thumbnailLoads removeObject:path];
                if (!image) return;
                IWCacheThumbnail(_cache, image, path);
                // Filtering/import/deletion may have replaced this position
                // while its image was being decoded. Never fill a reused cell.
                NSMutableArray *visible = [NSMutableArray array];
                for (NSIndexPath *row in [_collection indexPathsForVisibleItems]) {
                    if (row.item >= [_items count]) continue;
                    NSString *current = [[_items objectAtIndex:row.item] objectForKey:@"imagePath"];
                    if ([current isEqualToString:path]) [visible addObject:row];
                }
                if ([visible count]) [_collection reloadItemsAtIndexPaths:visible];
            });
        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_thumbnailQueue cancelAllOperations];
    [_thumbnailLoads removeAllObjects];
    [_cache removeAllObjects];
}

- (void)refreshPulled {
    [self preloadReset:YES];
}

- (void)scrollToSelected {
    [self scrollToSelectedAnimated:NO];
}

- (void)scrollToSelectedAnimated:(BOOL)animated {
    NSInteger i;
    for (i = 0; i < [_items count]; i += 1) {
        if ([[[_items objectAtIndex:i] objectForKey:@"index"] integerValue] == _selected) {
            [_collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:animated];
            return;
        }
    }
}

- (void)locateTapped {
    BOOL visible = NO;
    for (NSDictionary *item in _items) {
        if ([[item objectForKey:@"index"] integerValue] == _selected) { visible = YES; break; }
    }
    if (!visible) {
        _categoryFilter = nil;
        _favoriteFilterOnly = NO;
        _hasAllGalleryContentOffset = NO;
        _items = [[self itemsForFilter] copy];
        [_collection reloadData];
        [_collection layoutIfNeeded];
        [self updateFavoriteFilterUI];
        [self updateEmptyState];
    }
    _pendingLocateIndex = _selected;
    [self scrollToSelectedAnimated:YES];
}

- (void)reloadAfterImportedIndex:(NSInteger)index {
    _selected = index;
    _pendingLocateIndex = index;
    _favoriteFilterOnly = NO;
    _categoryFilter = nil;
    _hasAllGalleryContentOffset = NO;
    _items = [[self itemsForFilter] copy];
    NSInteger i;
    for (i = 0; i < [_items count]; i += 1) {
        NSDictionary *item = [_items objectAtIndex:i];
        NSInteger original = [[item objectForKey:@"index"] integerValue];
        if (original != index) continue;
        NSString *path = [item objectForKey:@"imagePath"];
        IWCacheThumbnail(_cache, IWDecodedThumbnail(item), path);
        break;
    }
    [_collection.collectionViewLayout invalidateLayout];
    [_collection reloadData];
    [_collection layoutIfNeeded];
    [self updateFavoriteFilterUI];
    [self updateEmptyState];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToSelectedAnimated:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToSelectedAnimated:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.95 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self scrollToSelectedAnimated:YES];
    });
}

- (NSArray *)itemsForFilter {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in [_owner allGalleryItems]) {
        if ([_categoryFilter length] && ![IWGalleryCategoryForItem(item) isEqualToString:_categoryFilter]) continue;
        NSInteger original = [[item objectForKey:@"index"] integerValue];
        if (!_favoriteFilterOnly || [_owner isFavorite:original]) [items addObject:item];
    }
    return items;
}

- (void)updateCategoryUI {
    NSString *title = @"全部";
    for (NSDictionary *definition in IWGalleryCategoryDefinitions()) {
        if ([[definition objectForKey:@"id"] isEqualToString:_categoryFilter ?: @""]) title = [definition objectForKey:@"title"];
    }
    [_categoryButton setTitle:[@"分类：" stringByAppendingString:title] forState:UIControlStateNormal];
    _categoryButton.accessibilityValue = title;
    BOOL active = [_categoryFilter length] > 0;
    _categoryButton.accessibilityTraits = UIAccessibilityTraitButton | (active ? UIAccessibilityTraitSelected : 0);
    _categoryButton.backgroundColor = active ? IWThemePink(0.72) : [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.58];
    _categoryButton.layer.borderColor = [[UIColor colorWithWhite:1 alpha:active ? 0.86 : 0.68] CGColor];
    _categoryButton.enabled = _loadingComplete;
    _categoryButton.alpha = _loadingComplete ? 1.0 : 0.42;
}

- (void)selectCategory:(NSString *)category {
    if (_deleteMode || _favoriteConfirmMode || !_loadingComplete) return;
    BOOL valid = NO;
    for (NSDictionary *definition in IWGalleryCategoryDefinitions()) {
        if ([[definition objectForKey:@"id"] isEqualToString:category]) { valid = YES; break; }
    }
    if (!valid) return;
    _categoryFilter = [category copy];
    _hasAllGalleryContentOffset = NO;
    _pendingLocateIndex = -1;
    _items = [[self itemsForFilter] copy];
    [_collection reloadData];
    [self updateFavoriteFilterUI];
    [self updateEmptyState];
    [self preloadReset:NO];
}

- (void)categoryTapped {
    if (_deleteMode || _favoriteConfirmMode || !_loadingComplete || self.presentedViewController) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"分类" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *all = [_owner allGalleryItems];
    for (NSDictionary *definition in IWGalleryCategoryDefinitions()) {
        NSString *category = [definition objectForKey:@"id"];
        NSInteger total = 0, count = 0;
        for (NSDictionary *item in all) {
            if ([category length] && ![IWGalleryCategoryForItem(item) isEqualToString:category]) continue;
            total += 1;
            if (!_favoriteFilterOnly || [_owner isFavorite:[[item objectForKey:@"index"] integerValue]]) count += 1;
        }
        if (total == 0 && [category length] && ![category isEqualToString:_categoryFilter]) continue;
        NSString *title = [NSString stringWithFormat:@"%@（%ld）", [definition objectForKey:@"title"], (long)count];
        __weak IWGalleryController *weakSelf = self;
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *selectedAction) {
            [weakSelf selectCategory:category];
        }];
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _categoryButton;
    sheet.popoverPresentationController.sourceRect = _categoryButton.bounds;
    sheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionUp;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSDictionary *)categoryDebugState {
    NSMutableArray *indexes = [NSMutableArray array];
    for (NSDictionary *item in _items) [indexes addObject:[item objectForKey:@"index"] ?: @(-1)];
    return @{@"category": _categoryFilter ?: @"", @"count": @([_items count]), @"favoriteOnly": @(_favoriteFilterOnly), @"indexes": indexes,
             @"buttonFrame": NSStringFromCGRect(_categoryButton.frame), @"buttonHidden": @(_categoryButton.hidden)};
}

- (void)updateFavoriteFilterUI {
    [self updateCategoryUI];
    UIColor *pink = IWThemePink(0.72);
    UIColor *border = _favoriteFilterOnly ? [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.86] : [UIColor colorWithWhite:1 alpha:0.68];
    if (_favoriteConfirmMode) {
        _favoriteButton.hidden = YES;
        return;
    }
    _favoriteButton.backgroundColor = _favoriteFilterOnly ? pink : [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.58];
    _favoriteButton.layer.borderColor = [border CGColor];
    _favoriteButton.enabled = _loadingComplete;
    _favoriteButton.alpha = _loadingComplete ? 1.0 : 0.42;
    [_favoriteButton setNeedsDisplay];
}

- (void)updateEmptyState {
    _emptyLabel.hidden = !([_items count] == 0 && _loadingPanel.hidden);
    if (!_emptyLabel.hidden) {
        _emptyLabel.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
        _emptyLabel.alpha = 0.0;
        [UIView animateWithDuration:0.18 animations:^{ _emptyLabel.alpha = 1.0; }];
    }
}

- (BOOL)canDeleteItem:(NSDictionary *)item {
    NSInteger original = [[item objectForKey:@"index"] integerValue];
    return [_owner canDeleteWallpaperAtIndex:original];
}

- (NSInteger)selectedDeletableCount {
    NSInteger count = 0;
    for (NSNumber *key in _deleteSelection) {
        if ([_owner canDeleteWallpaperAtIndex:[key integerValue]]) count += 1;
    }
    return count;
}

- (void)pruneSelectionToVisibleItems {
    NSMutableSet *visible = [NSMutableSet set];
    NSInteger i;
    for (i = 0; i < [_items count]; i += 1) {
        NSInteger original = [[[_items objectAtIndex:i] objectForKey:@"index"] integerValue];
        [visible addObject:[NSNumber numberWithInteger:original]];
    }
    [_deleteSelection intersectSet:visible];
}

- (void)updateDeleteModeUI {
    BOOL edit = _deleteMode;
    _addButton.hidden = edit || _favoriteConfirmMode;
    _favoriteButton.hidden = edit || _favoriteConfirmMode;
    _locateButton.hidden = edit || _favoriteConfirmMode;
    _closeButton.hidden = edit || _favoriteConfirmMode;
    _topButton.hidden = NO;
    _editButton.hidden = edit || _favoriteConfirmMode;
    _categoryButton.hidden = edit || _favoriteConfirmMode;
    _deleteCancelButton.hidden = !(edit || _favoriteConfirmMode);
    _deleteDoneButton.hidden = _favoriteConfirmMode ? YES : !edit;
    _batchFavoriteButton.hidden = !edit;
    _batchDeleteButton.hidden = !edit;
    _deleteTitleLabel.hidden = !edit;
    if (edit) {
        _topButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize() * 3.0 - IWControlGap() * 2.0, 18, IWControlSize(), IWControlSize());
    } else {
        _topButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize(), 18, IWControlSize(), IWControlSize());
    }
    if (edit) {
        NSInteger count = [_deleteSelection count];
        NSInteger deletableCount = [self selectedDeletableCount];
        _deleteTitleLabel.text = [NSString stringWithFormat:@"%ld Selected", (long)count];
        _batchFavoriteButton.alpha = count > 0 ? 1.0 : 0.42;
        _batchFavoriteButton.enabled = count > 0;
        _batchDeleteButton.alpha = deletableCount > 0 ? 1.0 : 0.42;
        _batchDeleteButton.enabled = deletableCount > 0;
    } else {
        _editButton.enabled = _loadingComplete;
        _editButton.alpha = _loadingComplete ? 1.0 : 0.42;
    }
}

- (void)setDeleteMode:(BOOL)enabled {
    if (_deleteMode == enabled) return;
    _deleteMode = enabled;
    [_deleteSelection removeAllObjects];
    [self updateDeleteModeUI];
    [_collection reloadData];
}

- (void)editTapped {
    if (_favoriteConfirmMode) return;
    if (!_loadingComplete) return;
    [self setDeleteMode:YES];
}

- (void)cancelDeleteTapped {
    if (_favoriteConfirmMode) {
        [self dismissAnimated];
        return;
    }
    [self setDeleteMode:NO];
}

- (void)doneDeleteTapped {
    if (_favoriteConfirmMode) {
        [_owner confirmFavoriteGalleryModeFromIndex:_selected];
        [self dismissAnimated];
        return;
    }
    [self setDeleteMode:NO];
}

- (void)confirmDeleteTapped {
    if (!_deleteMode || self.presentedViewController) return;
    NSInteger deletableCount = [self selectedDeletableCount];
    if (deletableCount <= 0) return;
    NSArray *indexes = [_deleteSelection allObjects];
    NSArray *itemsSnapshot = _items;
    NSString *title = [NSString stringWithFormat:@"删除 %ld 张导入照片？", (long)deletableCount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:@"将删除 Wizard 中的副本，系统相册中的原照片会保留。"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak IWGalleryController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        IWGalleryController *gallery = weakSelf;
        if (!gallery || !gallery->_deleteMode || gallery->_items != itemsSnapshot ||
            ![gallery->_deleteSelection isEqualToSet:[NSSet setWithArray:indexes]]) return;
        [gallery deleteConfirmedWallpapersAtIndexes:indexes];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteConfirmedWallpapersAtIndexes:(NSArray *)indexes {
    NSInteger selected = [_owner deleteWallpapersAtIndexes:indexes];
    _selected = selected;
    [_deleteSelection removeAllObjects];
    _deleteMode = NO;
    _pendingLocateIndex = selected;
    _items = [[self itemsForFilter] copy];
    [_collection.collectionViewLayout invalidateLayout];
    [_collection reloadData];
    [_collection layoutIfNeeded];
    [self updateFavoriteFilterUI];
    [self updateDeleteModeUI];
    [self updateEmptyState];
    [self preloadReset:YES];
}

- (void)confirmFavoriteTapped {
    if (![_deleteSelection count]) return;
    NSArray *indexes = [_deleteSelection allObjects];
    NSInteger i;
    for (i = 0; i < [indexes count]; i += 1) {
        [_owner toggleFavorite:[[indexes objectAtIndex:i] integerValue]];
    }
    _items = [[self itemsForFilter] copy];
    [self pruneSelectionToVisibleItems];
    [_collection reloadData];
    [self updateFavoriteFilterUI];
    [self updateDeleteModeUI];
    [self updateEmptyState];
}

- (void)favoriteFilterTapped {
    if (_favoriteConfirmMode) return;
    if (_deleteMode) return;
    if (!_loadingComplete) return;
    if (!_favoriteFilterOnly) {
        _allGalleryContentOffset = _collection.contentOffset;
        _hasAllGalleryContentOffset = YES;
    }
    _favoriteFilterOnly = !_favoriteFilterOnly;
    _items = [[self itemsForFilter] copy];
    [_collection reloadData];
    [_collection layoutIfNeeded];
    [self updateFavoriteFilterUI];
    [self updateEmptyState];
    if (!_favoriteFilterOnly && _hasAllGalleryContentOffset) {
        [_collection setContentOffset:_allGalleryContentOffset animated:NO];
    } else if ([_items count]) {
        [self scrollToSelectedAnimated:NO];
    }
}

- (void)pinch:(UIPinchGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _pinchBaseColumns = _galleryColumns;
        return;
    }
    if (recognizer.state != UIGestureRecognizerStateChanged && recognizer.state != UIGestureRecognizerStateEnded) return;
    NSInteger base = _pinchBaseColumns > 0 ? _pinchBaseColumns : _galleryColumns;
    NSInteger next = base;
    if (recognizer.scale > 1.42) next = MAX(3, base - 1);
    else if (recognizer.scale < 0.70) next = MIN(5, base + 1);
    if (next == _galleryColumns) return;
    _galleryColumns = next;
    [UIView animateWithDuration:0.22 animations:^{
        [_collection.collectionViewLayout invalidateLayout];
        [_collection layoutIfNeeded];
    }];
}

- (UIInterfaceOrientation)currentAppLandscapeOrientation {
    UIInterfaceOrientation status = [[UIApplication sharedApplication] statusBarOrientation];
    if (UIInterfaceOrientationIsLandscape(status)) return status;
    return UIInterfaceOrientationLandscapeLeft;
}

- (void)restoreOrientationAfterPicker {
    UIInterfaceOrientation target = UIInterfaceOrientationIsLandscape(_orientationBeforePicker) ? _orientationBeforePicker : UIInterfaceOrientationLandscapeLeft;
    if ([[UIDevice currentDevice] respondsToSelector:@selector(setValue:forKey:)]) {
        [[UIDevice currentDevice] setValue:[NSNumber numberWithInteger:target] forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }
    self.view.transform = CGAffineTransformIdentity;
    self.view.frame = self.view.window.bounds;
    [_collection.collectionViewLayout invalidateLayout];
    [_collection reloadData];
    [_collection layoutIfNeeded];
}

- (void)addTapped {
    [self performSelector:@selector(openPhotoPickerNow) withObject:nil afterDelay:0.05];
}

- (void)openPhotoPickerNow {
    if (self.presentedViewController || _photoPopover) return;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [_owner writeDebugState:@"picker-unavailable"];
        return;
    }
    _orientationBeforePicker = [self currentAppLandscapeOrientation];
    UIImagePickerController *picker = [[IWImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.contentSizeForViewInPopover = CGSizeMake(948.0, 690.0);
    _photoPopover = [[UIPopoverController alloc] initWithContentViewController:picker];
    _photoPopover.delegate = self;
    _photoPopover.popoverContentSize = CGSizeMake(948.0, 690.0);
    [_photoPopover presentPopoverFromRect:_addButton.frame inView:_addButton.superview permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)debugOpenPhotoPicker {
    [self addTapped];
}

- (void)debugClosePhotoPicker {
    if (_photoPopover) {
        [_photoPopover dismissPopoverAnimated:NO];
        _photoPopover = nil;
        [self restoreOrientationAfterPicker];
        [_owner writeDebugState:@"picker-cancelled"];
    } else if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:NO completion:^{
            [self restoreOrientationAfterPicker];
            [_owner writeDebugState:@"picker-cancelled"];
        }];
    } else {
        [self restoreOrientationAfterPicker];
        [_owner writeDebugState:@"picker-cancelled"];
    }
}

- (void)debugEnterDeleteMode {
    [self setDeleteMode:YES];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    if (_photoPopover) {
        [_photoPopover dismissPopoverAnimated:YES];
        _photoPopover = nil;
        [self restoreOrientationAfterPicker];
        [_owner writeDebugState:@"picker-cancelled"];
    } else {
        [picker dismissViewControllerAnimated:YES completion:^{
            [self restoreOrientationAfterPicker];
            [_owner writeDebugState:@"picker-cancelled"];
        }];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];
    void (^finishImport)(void) = ^{
        [self restoreOrientationAfterPicker];
        if (!image) return;
        NSInteger index = [_owner importSystemImage:image];
        if (index < 0) return;
        [_owner selectWallpaper:index];
        [self reloadAfterImportedIndex:index];
        [_owner writeDebugState:@"picker-imported"];
    };
    if (_photoPopover) {
        [_photoPopover dismissPopoverAnimated:YES];
        _photoPopover = nil;
        finishImport();
    } else {
        [picker dismissViewControllerAnimated:YES completion:finishImport];
    }
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    if (popoverController == _photoPopover) {
        _photoPopover = nil;
        [self restoreOrientationAfterPicker];
        [_owner writeDebugState:@"picker-cancelled"];
    }
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return [_items count]; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    IWGalleryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *item = [_items objectAtIndex:indexPath.item];
    NSInteger original = [[item objectForKey:@"index"] integerValue];
    BOOL deleteSelected = [_deleteSelection containsObject:[NSNumber numberWithInteger:original]];
    BOOL deletable = [self canDeleteItem:item];
    UIImage *image = [_cache objectForKey:[item objectForKey:@"imagePath"]];
    [cell configure:item image:image selected:original == _selected favorite:[_owner isFavorite:original] deleteMode:_deleteMode deleteSelected:deleteSelected deletable:deletable];
    if (!image) [self loadVisibleThumbnailAtIndexPath:indexPath];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger columns = MAX(3, MIN(5, _galleryColumns));
    CGFloat available = collectionView.bounds.size.width - 56.0 - (columns - 1) * 12.0;
    CGFloat width = floor(available / columns);
    return CGSizeMake(width, floor(width * 0.62) + 30.0);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger original = [[[_items objectAtIndex:indexPath.item] objectForKey:@"index"] integerValue];
    if (_deleteMode) {
        NSNumber *key = [NSNumber numberWithInteger:original];
        if ([_deleteSelection containsObject:key]) [_deleteSelection removeObject:key];
        else [_deleteSelection addObject:key];
        [self updateDeleteModeUI];
        [_collection reloadItemsAtIndexPaths:@[indexPath]];
        return;
    }
    if ([_owner openGalleryMediaAtIndex:original]) {
        [self dismissAnimated];
        return;
    }
    if (_favoriteConfirmMode) {
        [_owner confirmFavoriteGalleryModeFromIndex:original];
        [self dismissAnimated];
        return;
    }
    [_owner selectWallpaper:original];
    [self dismissAnimated];
}

- (void)longPress:(UILongPressGestureRecognizer *)recognizer {
    if (_favoriteConfirmMode) return;
    if (_deleteMode) return;
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *indexPath = [_collection indexPathForItemAtPoint:[recognizer locationInView:_collection]];
    if (!indexPath) return;
    NSInteger original = [[[_items objectAtIndex:indexPath.item] objectForKey:@"index"] integerValue];
    [_owner toggleFavorite:original];
    _selected = original;
    _items = [[self itemsForFilter] copy];
    [_collection reloadData];
    [self updateEmptyState];
}

- (void)topTapped { [_collection setContentOffset:CGPointMake(0, -_collection.contentInset.top) animated:YES]; }
- (void)closeTapped {
    if (_favoriteConfirmMode) {
        [self dismissAnimated];
        return;
    }
    if (_deleteMode) {
        [self setDeleteMode:NO];
        return;
    }
    [self dismissAnimated];
}

- (void)dismissAnimated {
    [_thumbnailQueue cancelAllOperations];
    [_thumbnailLoads removeAllObjects];
    _preloadGeneration += 1;
    [UIView animateWithDuration:IWPanelAnimationDuration()
                          delay:0
         usingSpringWithDamping:IWPanelSpringDamping()
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.view.alpha = 0.0;
        _collection.transform = CGAffineTransformMakeTranslation(0, 42.0);
        _bar.transform = CGAffineTransformMakeTranslation(0, 42.0);
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

@end

@implementation IWRootViewController {
    IWFrameProbe *_frameProbe;
    NSURL *_pendingCastURL;
    BOOL _castDismissingModal;
    BOOL _videoAuditRunning;
    NSDictionary *_lastLocalVideoFinish;
    UIView *_backgroundClip;
    UIImageView *_background;
    UIView *_shade;
    UIView *_surfaceLayer;
    UIView *_wallpaperPulse;
    UIView *_clockFace;
    UIView *_digitGroup;
    NSMutableArray *_digitLabels;
    NSMutableArray *_colonViews;
    UILabel *_secondsLabel;
    UILabel *_dateLabel;
    UIView *_calendarPanel;
    UILabel *_calendarMonthLabel;
    NSMutableArray *_calendarWeekdayLabels;
    NSMutableArray *_calendarDayLabels;
    NSMutableArray *_calendarHolidayDots;
    UILabel *_calendarHolidaySummaryLabel;
    UIView *_calendarHolidayToast;
    UILabel *_calendarHolidayToastLabel;
    BOOL _calendarMonthTransitioning;
    NSMutableArray *_countdownDayLabels;
    UILabel *_debugLabel;
    IWIconButton *_pullIndicator;
    UIView *_menu;
    IWIconButton *_menuButton;
    IWIconButton *_settingsButton;
    IWIconButton *_musicButton;
    IWIconButton *_castButton;
    UIView *_homePanel;
    UIView *_weatherPanel;
    UILabel *_weatherGlyphLabel;
    UILabel *_weatherTemperatureLabel;
    UILabel *_weatherConditionLabel;
    UILabel *_weatherRangeLabel;
    UILabel *_weatherCityLabel;
    UIButton *_weatherProviderButton;
    BOOL _weatherCreditAuditRunning;
    UIView *_settingsMenu;
    UILabel *_homeUpdatedLabel;
    NSMutableArray *_homeCards;
    UIView *_editToolbar;
    UIView *_opacityControl;
    UISlider *_opacitySlider;
    UIView *_borderControl;
    NSMutableArray *_borderThemeButtons;
    UISlider *_borderWidthSlider;
    IWBorderColorPalette *_borderColorPalette;
    IWIconButton *_editControlsMoveButton;
    UIButton *_editResetButton;
    UIButton *_editCancelButton;
    UIButton *_editDoneButton;
    UIButton *_secondsButton;
    UIButton *_hourButton;
    UIButton *_languageButton;
    UIButton *_powerConnectButton;
    UIButton *_powerDisconnectButton;
    UIButton *_wallpaperTransitionButton;
    UIView *_videoOverlay;
    UIView *_videoControls;
    UIView *_videoTapShield;
    UIView *_powerSleepOverlay;
    IWIconButton *_videoPlayButton;
    IWIconButton *_videoRewindButton;
    IWIconButton *_videoForwardButton;
    IWIconButton *_videoVolumeButton;
    UISlider *_videoSlider;
    UILabel *_videoCurrentLabel;
    UILabel *_videoDurationLabel;
    MPMoviePlayerController *_moviePlayer;
    AVPlayer *_remoteVideoPlayer;
    AVPlayerLayer *_remoteVideoLayer;
    MPVolumeView *_airPlayView;
    MPVolumeView *_volumeView;
    UIView *_volumePanel;
    UISlider *_volumeSlider;
    UISlider *_systemVolumeSlider;
    NSTimer *_videoTimer;
    NSTimer *_videoHideTimer;
    UIImageView *_depthBackground;
    UIImageView *_depthForeground;
    CMMotionManager *_motionManager;
    NSTimer *_timer;
    NSTimer *_castTimer;
    NSTimer *_weatherRefreshTimer;
    IWDLNACastServer *_dlnaCastServer;
    IWWeatherService *_weatherService;
    CLLocationManager *_weatherLocationManager;
    CLGeocoder *_weatherGeocoder;
    NSArray *_wallpapers;
    NSCache *_thumbCache;
    UIImageView *_coldStartOverlay;
    UIView *_coldStartTrack;
    UIView *_coldStartFill;
    NSInteger _coldStartPreloadGeneration;
    AVAudioPlayer *_player;
    NSInteger _wallpaperIndex;
    NSUInteger _wallpaperLoadGeneration;
    NSString *_savedWallpaperKey;
    BOOL _hour24;
    BOOL _showSeconds;
    BOOL _dateVisible;
    BOOL _calendarVisible;
    BOOL _calendarHiddenForClockEdit;
    NSInteger _calendarDisplayYear;
    NSInteger _calendarDisplayMonth;
    NSInteger _calendarSelectedDay;
    BOOL _gta6CountdownMode;
    NSInteger _dateLanguage;
    BOOL _cleanMode;
    BOOL _menuOpen;
    BOOL _settingsOpen;
    NSInteger _secondaryMenuMode;
    BOOL _controlsHidden;
    BOOL _promoOnly;
    BOOL _favoriteOnly;
    BOOL _homeVisible;
    BOOL _weatherVisible;
    BOOL _weatherLoading;
    BOOL _weatherError;
    BOOL _editMode;
    BOOL _musicError;
    BOOL _castError;
    BOOL _powerConnectEnabled;
    BOOL _powerDisconnectEnabled;
    BOOL _appPowerSleepActive;
    BOOL _lastPowerConnectedKnown;
    BOOL _lastPowerConnected;
    BOOL _hasBrightnessBeforeSleep;
    BOOL _closingVideo;
    BOOL _depthMode;
    BOOL _videoUserPaused;
    BOOL _videoControlsVisible;
    BOOL _videoMinimized;
    BOOL _videoVolumeVisible;
    BOOL _usingRemoteVideoPlayer;
    BOOL _videoSliderScrubbing;
    BOOL _remoteVideoSeeking;
    NSTimeInterval _remoteVideoPendingSeekTime;
    NSInteger _remoteVideoSeekGeneration;
    NSUInteger _videoCloseGeneration;
    NSString *_videoCurrentPath;
    NSURL *_videoCurrentURL;
    BOOL _surfaceGestureIgnored;
    BOOL _surfaceTouchActive;
    BOOL _surfaceMultiTouchIgnored;
    BOOL _panFallbackTracking;
    BOOL _pullReady;
    BOOL _pullRefreshing;
    NSString *_surfaceIntent;
    IWEditTarget _editTarget;
    CGFloat _backgroundX;
    CGFloat _backgroundY;
    CGFloat _backgroundZoom;
    UIColor *_wallpaperAccentColor;
    IWWallpaperTransitionStyle _wallpaperTransitionStyle;
    CGFloat _clockOffsetX;
    CGFloat _clockOffsetY;
    CGFloat _clockScale;
    CGFloat _dateOffsetX;
    CGFloat _dateOffsetY;
    CGFloat _dateScale;
    CGFloat _calendarScale;
    CGFloat _calendarOffsetX;
    CGFloat _calendarOffsetY;
    CGFloat _calendarOpacity;
    CGFloat _weatherScale;
    CGFloat _weatherOffsetX;
    CGFloat _weatherOffsetY;
    NSString *_calendarRenderedDayKey;
    UIColor *_calendarRenderedAccent;
    CGFloat _digitCardOpacity;
    UIColor *_digitCardBorderColor;
    CGFloat _digitCardBorderWidth;
    CGFloat _brightnessBeforeSleep;
    CGFloat _depthTiltX;
    CGFloat _depthTiltY;
    CGFloat _editStartX;
    CGFloat _editStartY;
    CGFloat _editStartZoom;
    CGFloat _editStartDistance;
    CGFloat _editControlsOffsetX;
    CGFloat _editControlsOffsetY;
    CGPoint _editControlsPanStart;
    NSTimeInterval _lastSurfaceActionAt;
    NSTimeInterval _lastMultiTouchAt;
    NSTimeInterval _lastVideoTapAt;
    CGPoint _surfaceStart;
    CGPoint _editStartMidpoint;
    NSMutableDictionary *_favorites;
    NSMutableDictionary *_backgroundAdjustments;
    NSDictionary *_editSnapshot;
    NSString *_castSrc;
    NSString *_castTitle;
    NSString *_castLastId;
    NSDictionary *_weatherSnapshot;
    NSString *_weatherCity;
}

- (void)dealloc {
    [_weatherRefreshTimer invalidate];
    [_weatherLocationManager stopUpdatingLocation];
    [_weatherGeocoder cancelGeocode];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_thumbCache removeAllObjects];
    [IWDigitSnapshotCache() removeAllObjects];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return IWCurrentLandscapeOrientation(); }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)loadView {
    IWRootSurfaceView *root = [[IWRootSurfaceView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root.backgroundColor = [UIColor blackColor];
    root.multipleTouchEnabled = YES;
    root.owner = self;
    self.view = root;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self surfaceTouchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self surfaceTouchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self surfaceTouchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self surfaceTouchesCancelled:touches withEvent:event];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.multipleTouchEnabled = YES;
    [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/wizardsystem-touch.log" error:nil];
    _thumbCache = [[NSCache alloc] init];
    _thumbCache.countLimit = 32;
    _thumbCache.totalCostLimit = 16 * 1024 * 1024;
    [self loadState];
    [self loadPowerAutomationPrefs];
    [self configureAudio];
    [self loadWallpapers];
    [self buildUI];
    [self setupWizardCastServer];
    if (_cleanMode) [self applyCleanMode];
    [self appendTouchDebug:@"boot"];
    [self applyWallpaper];
    [self buildColdStartOverlay];
    [self preloadGalleryForColdStart];
    [self loadCastStatus];
    [self startAppPowerAutomation];
    BOOL weatherDemo = IW_WEATHER_DIAGNOSTICS ||
                       ([[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-debug")] &&
                        [[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-demo")]);
    if (IW_WEATHER_DIAGNOSTICS || [[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-debug")]) {
        NSString *stage = [NSString stringWithFormat:@"%@ demo=%@ visible=%@\n", [NSDate date], weatherDemo ? @"yes" : @"no", _weatherVisible ? @"yes" : @"no"];
        [stage writeToFile:IWWeatherDebugPath(@"wizard-weather-boot.log") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    if (weatherDemo) [self loadWeatherDemo];
    else if (_weatherVisible) [self startWeatherUpdates];
    [self tick];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    _castTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(loadCastStatus) userInfo:nil repeats:YES];
}

- (void)setupWizardCastServer {
    _dlnaCastServer = [[IWDLNACastServer alloc] init];
    __weak IWRootViewController *weakSelf = self;
    _dlnaCastServer.playURLHandler = ^(NSURL *url) {
        [weakSelf openCastURL:url];
    };
    _dlnaCastServer.stateChangedHandler = ^(BOOL ready, NSError *error) {
        IWRootViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_castError = error != nil;
        [strongSelf updateMenuButtons];
        [strongSelf writeDebugState:ready ? @"cast-ready" : (error ? @"cast-error" : @"cast-starting")];
    };
    _castError = ![_dlnaCastServer start];
}

- (void)configureAudio {
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback error:nil];
    [s setActive:YES error:nil];
}

- (void)buildColdStartOverlay {
    UIImage *launchImage = [UIImage imageNamed:@"WizardLaunch.png"];
    if (!launchImage) return;
    _coldStartOverlay = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _coldStartOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _coldStartOverlay.image = launchImage;
    _coldStartOverlay.contentMode = UIViewContentModeScaleAspectFill;
    _coldStartOverlay.userInteractionEnabled = YES;
    [self.view addSubview:_coldStartOverlay];

    CGFloat trackWidth = 250.0;
    CGFloat trackHeight = 4.0;
    CGFloat trackY = round(self.view.bounds.size.height * 0.636);
    _coldStartTrack = [[UIView alloc] initWithFrame:CGRectMake(round((self.view.bounds.size.width - trackWidth) / 2.0), trackY, trackWidth, trackHeight)];
    _coldStartTrack.backgroundColor = [UIColor colorWithRed:33.0/255.0 green:10.0/255.0 blue:31.0/255.0 alpha:0.94];
    _coldStartTrack.layer.cornerRadius = trackHeight / 2.0;
    _coldStartTrack.clipsToBounds = YES;
    [_coldStartOverlay addSubview:_coldStartTrack];

    _coldStartFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, trackHeight)];
    _coldStartFill.backgroundColor = IWThemePink(0.94);
    _coldStartFill.layer.cornerRadius = trackHeight / 2.0;
    [_coldStartTrack addSubview:_coldStartFill];
}

- (void)updateColdStartProgress:(NSInteger)done total:(NSInteger)total generation:(NSInteger)generation {
    if (generation != _coldStartPreloadGeneration || !_coldStartFill) return;
    CGFloat progress = total <= 0 ? 1.0 : MAX(0.0, MIN(1.0, (CGFloat)done / (CGFloat)total));
    CGRect fill = _coldStartFill.frame;
    fill.size.width = round(_coldStartTrack.bounds.size.width * progress);
    _coldStartFill.frame = fill;
}

- (void)preloadGalleryForColdStart {
    NSInteger generation = ++_coldStartPreloadGeneration;
    NSArray *items = [_wallpapers copy] ?: @[];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Prime only the first visible gallery rows. Decoding the complete
        // library here kept old devices above the CPU resource limit for
        // roughly 100 seconds and delayed the actual clock experience.
        NSInteger preloadCount = MIN((NSInteger)[items count], 12);
        NSInteger total = MAX(1, preloadCount);
        NSInteger i;
        for (i = 0; i < preloadCount; i += 1) {
            NSDictionary *item = [items objectAtIndex:i];
            NSString *key = [item objectForKey:@"imagePath"];
            if (![_thumbCache objectForKey:key]) {
                @autoreleasepool {
                    IWCacheThumbnail(_thumbCache, IWDecodedThumbnail(item), key);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateColdStartProgress:i + 1 total:total generation:generation];
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != _coldStartPreloadGeneration || !_coldStartOverlay) return;
            [self updateColdStartProgress:total total:total generation:generation];
            UIImageView *overlay = _coldStartOverlay;
            UIView *track = _coldStartTrack;
            [UIView animateWithDuration:0.14 delay:0.08 options:UIViewAnimationOptionCurveEaseOut animations:^{
                track.alpha = 0.0;
            } completion:^(__unused BOOL finished) {
                [UIView animateWithDuration:0.24 delay:0.04 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    overlay.alpha = 0.0;
                } completion:^(__unused BOOL finished) {
                    [overlay removeFromSuperview];
                }];
            }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.52 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (_coldStartOverlay != overlay) return;
                _coldStartOverlay = nil;
                _coldStartTrack = nil;
                _coldStartFill = nil;
            });
        });
    });
}

- (void)loadClockLayoutForCurrentMode {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *prefix = _gta6CountdownMode ? @"gta6" : @"";
    NSString *clockXKey = [prefix length] ? @"gta6ClockOffsetX" : @"clockOffsetX";
    NSString *clockYKey = [prefix length] ? @"gta6ClockOffsetY" : @"clockOffsetY";
    NSString *clockScaleKey = [prefix length] ? @"gta6ClockScale" : @"clockScale";
    NSString *dateXKey = [prefix length] ? @"gta6DateOffsetX" : @"dateOffsetX";
    NSString *dateYKey = [prefix length] ? @"gta6DateOffsetY" : @"dateOffsetY";
    NSString *dateScaleKey = [prefix length] ? @"gta6DateScale" : @"dateScale";
    _clockOffsetX = [d objectForKey:clockXKey] ? [d floatForKey:clockXKey] : IWClockDefaultOffsetX();
    _clockOffsetY = [d objectForKey:clockYKey] ? [d floatForKey:clockYKey] : IWClockDefaultOffsetY();
    _clockScale = [d objectForKey:clockScaleKey] ? [d floatForKey:clockScaleKey] : IWClockDefaultScale();
    _dateOffsetX = [d objectForKey:dateXKey] ? [d floatForKey:dateXKey] : IWDateDefaultOffsetX();
    _dateOffsetY = [d objectForKey:dateYKey] ? [d floatForKey:dateYKey] : IWDateDefaultOffsetY();
    _dateScale = [d objectForKey:dateScaleKey] ? [d floatForKey:dateScaleKey] : IWDateDefaultScale();
    if (_clockScale < IWClockScaleMin() || _clockScale > IWClockScaleMax()) _clockScale = IWClockDefaultScale();
    if (_dateScale < IWDateScaleMin() || _dateScale > IWDateScaleMax()) _dateScale = IWDateDefaultScale();
}

- (void)loadState {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _wallpaperIndex = [d integerForKey:@"wallpaperIndex"];
    _savedWallpaperKey = [d stringForKey:@"wallpaperKey"];
    _hour24 = [d objectForKey:@"hour24"] ? [d boolForKey:@"hour24"] : YES;
    _showSeconds = [d objectForKey:@"showSeconds"] ? [d boolForKey:@"showSeconds"] : NO;
    _dateVisible = [d objectForKey:@"dateVisible"] ? [d boolForKey:@"dateVisible"] : YES;
    _calendarVisible = [d boolForKey:@"calendarVisible"];
    // Older builds allowed date and calendar to be shown together.  The
    // unified calendar button now makes these mutually exclusive modes.
    if (_calendarVisible) _dateVisible = NO;
    _calendarScale = [d objectForKey:@"calendarScale"] ? [d floatForKey:@"calendarScale"] : 1.0;
    _calendarOffsetX = [d floatForKey:@"calendarOffsetX"];
    _calendarOffsetY = [d floatForKey:@"calendarOffsetY"];
    _calendarOpacity = [d objectForKey:@"calendarOpacity"] ? [d floatForKey:@"calendarOpacity"] : 0.54;
    _calendarOpacity = IWDigitCardClampOpacity(_calendarOpacity);
    if (_calendarScale < IWCalendarScaleMin() || _calendarScale > IWCalendarScaleMax()) _calendarScale = 1.0;
    _gta6CountdownMode = [d boolForKey:@"gta6CountdownMode"];
    if ([d objectForKey:@"dateLanguage"]) _dateLanguage = [d integerForKey:@"dateLanguage"];
    else _dateLanguage = [d boolForKey:@"dateChinese"] ? 1 : 0;
    if (_dateLanguage < 0 || _dateLanguage > 3) _dateLanguage = 0;
    _cleanMode = [d boolForKey:@"cleanMode"];
    _weatherVisible = [d boolForKey:@"weatherVisible"];
    _weatherSnapshot = IWValidatedWeatherCache([d dictionaryForKey:@"weatherSnapshot"]);
    _weatherCity = [d stringForKey:@"weatherCity"] ?: @"当前位置";
    _weatherScale = [d objectForKey:@"weatherScale"] ? [d floatForKey:@"weatherScale"] : 1.0;
    _weatherOffsetX = [d floatForKey:@"weatherOffsetX"];
    _weatherOffsetY = [d floatForKey:@"weatherOffsetY"];
    if (_weatherScale < IWWeatherScaleMin() || _weatherScale > IWWeatherScaleMax()) _weatherScale = 1.0;
    _wallpaperTransitionStyle = [d integerForKey:@"wallpaperTransitionStyle"];
    NSInteger transitionVersion = [d integerForKey:@"wallpaperTransitionVersion"];
    if (transitionVersion < 2) {
        // Previous builds used Off=0 and Slide=4.  Off is retired; both now become Slide.
        if (_wallpaperTransitionStyle == 0 || _wallpaperTransitionStyle == 4) _wallpaperTransitionStyle = IWWallpaperTransitionStyleSlide;
    }
    if (_wallpaperTransitionStyle < IWWallpaperTransitionStyleSlide || _wallpaperTransitionStyle > IWWallpaperTransitionStyleLift) {
        _wallpaperTransitionStyle = IWWallpaperTransitionStyleSlide;
    }
    _favorites = [[d dictionaryForKey:@"favorites"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    _backgroundAdjustments = [[d dictionaryForKey:@"backgroundAdjustments"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
    [self loadClockLayoutForCurrentMode];
    _digitCardOpacity = IWDigitCardClampOpacity([d floatForKey:@"digitCardOpacity"]);
    _digitCardBorderWidth = [d objectForKey:@"digitCardBorderWidth"] ? [d floatForKey:@"digitCardBorderWidth"] : 3.4;
    _digitCardBorderWidth = MAX(1.0, MIN(6.0, _digitCardBorderWidth));
    CGFloat borderR = [d objectForKey:@"digitCardBorderRed"] ? [d floatForKey:@"digitCardBorderRed"] : 1.0;
    CGFloat borderG = [d objectForKey:@"digitCardBorderGreen"] ? [d floatForKey:@"digitCardBorderGreen"] : 73.0/255.0;
    CGFloat borderB = [d objectForKey:@"digitCardBorderBlue"] ? [d floatForKey:@"digitCardBorderBlue"] : 158.0/255.0;
    _digitCardBorderColor = [UIColor colorWithRed:MAX(0, MIN(1, borderR)) green:MAX(0, MIN(1, borderG)) blue:MAX(0, MIN(1, borderB)) alpha:1.0];
    _editControlsOffsetX = [d floatForKey:@"editControlsOffsetX"];
    _editControlsOffsetY = [d floatForKey:@"editControlsOffsetY"];
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    if ([d integerForKey:@"editControlsDefaultPositionVersion"] < 2) {
        CGFloat panelWidth = 262.0 + IWControlGap() + IWControlSize();
        _editControlsOffsetX = screenSize.width - panelWidth - 40.0;
        _editControlsOffsetY = 0.0;
        [d setInteger:2 forKey:@"editControlsDefaultPositionVersion"];
    }
    CGFloat maxAxis = MAX(screenSize.width, screenSize.height);
    BOOL resetDigitMaterial = NO;
    if (fabs(_clockOffsetX) > maxAxis * 1.30 || fabs(_clockOffsetY) > maxAxis * 1.00) {
        _clockOffsetX = IWClockDefaultOffsetX();
        _clockOffsetY = IWClockDefaultOffsetY();
        _clockScale = IWClockDefaultScale();
        resetDigitMaterial = YES;
    }
    if (fabs(_dateOffsetX) > maxAxis * 1.30 || fabs(_dateOffsetY) > maxAxis * 1.00) {
        _dateOffsetX = IWDateDefaultOffsetX();
        _dateOffsetY = IWDateDefaultOffsetY();
        _dateScale = IWDateDefaultScale();
        resetDigitMaterial = YES;
    }
    if (resetDigitMaterial) _digitCardOpacity = IWDigitCardDefaultOpacity();
}

- (void)loadPowerAutomationPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:IWPowerPrefsPath];
    if (!prefs) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:IWLegacyPowerPrefsPath];
        if (prefs) [prefs writeToFile:IWPowerPrefsPath atomically:YES];
    }
    if ([prefs objectForKey:@"OpenWizardOnScreenWake"]) {
        NSMutableDictionary *normalizedPrefs = [prefs mutableCopy];
        [normalizedPrefs removeObjectForKey:@"OpenWizardOnScreenWake"];
        [normalizedPrefs writeToFile:IWPowerPrefsPath atomically:YES];
        prefs = normalizedPrefs;
    }
    if (prefs) {
        id connect = [prefs objectForKey:@"UnlockOnPowerConnected"];
        id openWizard = [prefs objectForKey:@"OpenWizardOnPowerConnected"];
        id disconnect = [prefs objectForKey:@"LockOnPowerDisconnected"];
        _powerConnectEnabled = connect ? [connect boolValue] : YES;
        if (openWizard && ![openWizard boolValue]) _powerConnectEnabled = NO;
        _powerDisconnectEnabled = disconnect ? [disconnect boolValue] : YES;
    } else {
        _powerConnectEnabled = YES;
        _powerDisconnectEnabled = YES;
    }
}

- (void)savePowerAutomationPrefs {
    BOOL anyEnabled = _powerConnectEnabled || _powerDisconnectEnabled;
    NSDictionary *prefs = @{
        @"Enabled": [NSNumber numberWithBool:anyEnabled],
        @"UnlockOnPowerConnected": [NSNumber numberWithBool:_powerConnectEnabled],
        @"OpenWizardOnPowerConnected": [NSNumber numberWithBool:_powerConnectEnabled],
        @"LockOnPowerDisconnected": [NSNumber numberWithBool:_powerDisconnectEnabled]
    };
    [prefs writeToFile:IWPowerPrefsPath atomically:YES];
}

- (void)appendPowerAutomationLog:(NSString *)message {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message ?: @""];
    NSString *path = @"/tmp/wizardsystem-power.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (BOOL)appPowerConnectedNow {
    UIDeviceBatteryState state = [[UIDevice currentDevice] batteryState];
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

- (NSString *)appPowerStateName:(BOOL)connected {
    return connected ? @"powered" : @"battery";
}

- (void)startAppPowerAutomation {
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    _lastPowerConnected = [self appPowerConnectedNow];
    _lastPowerConnectedKnown = YES;
    [self appendPowerAutomationLog:[NSString stringWithFormat:@"app power monitor initial=%@", [self appPowerStateName:_lastPowerConnected]]];
    // Air's SpringBoard bridge is the sole power-edge observer.  Registering
    // this foreground app for charging/full changes wakes it during a real
    // system lock on iOS 12 and can dismiss the lock screen.
}

- (void)appPowerStateDidChange:(NSNotification *)notification {
    [self handleAppPowerConnected:[self appPowerConnectedNow] source:@"battery notification"];
}

- (void)handleAppPowerConnected:(BOOL)connected source:(NSString *)source {
    if (_lastPowerConnectedKnown && connected == _lastPowerConnected) return;
    BOOL previous = _lastPowerConnected;
    _lastPowerConnected = connected;
    _lastPowerConnectedKnown = YES;
    [self appendPowerAutomationLog:[NSString stringWithFormat:@"power %@ -> %@ via %@", [self appPowerStateName:previous], [self appPowerStateName:connected], source ?: @"unknown"]];
    // On Air, the SpringBoard bridge owns the system lock and wake transition.
    // This monitor records state only, so one physical edge produces one action.
}

- (void)enterAppPowerSleep:(NSString *)reason {
    BOOL remoteVisualCommand = [reason hasPrefix:@"remote visual"];
    if (!_powerDisconnectEnabled && !remoteVisualCommand) {
        [self appendPowerAutomationLog:[NSString stringWithFormat:@"sleep ignored disabled %@", reason ?: @""]];
        return;
    }
    if (_appPowerSleepActive) return;
    _appPowerSleepActive = YES;
    [self appendPowerAutomationLog:[NSString stringWithFormat:@"app visual sleep %@", reason ?: @""]];

    [_player pause];
    if (_videoOverlay && !_videoOverlay.hidden) [self closeVideo];
    if (_editMode) [self cancelEditMode];
    if (_depthMode) [self setDepthDemoEnabled:NO];
    _homeVisible = NO;
    _homePanel.hidden = YES;
    _menuOpen = NO;
    _menu.hidden = YES;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
    [self updateMenuButtons];

    UIScreen *screen = [UIScreen mainScreen];
    if (!_hasBrightnessBeforeSleep) {
        _brightnessBeforeSleep = screen.brightness;
        _hasBrightnessBeforeSleep = YES;
    }
    if ([screen respondsToSelector:@selector(setBrightness:)]) {
        screen.brightness = 0.02;
    }

    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    _powerSleepOverlay.frame = self.view.bounds;
    _powerSleepOverlay.alpha = 0.0;
    _powerSleepOverlay.hidden = NO;
    [self.view bringSubviewToFront:_powerSleepOverlay];
    [UIView animateWithDuration:0.18 animations:^{
        _powerSleepOverlay.alpha = 1.0;
    }];
    [self writeDebugState:@"app-power-sleep"];
}

- (void)exitAppPowerSleep:(NSString *)reason {
    BOOL remoteVisualCommand = [reason hasPrefix:@"remote visual"];
    if (!_powerConnectEnabled && !remoteVisualCommand) {
        [self appendPowerAutomationLog:[NSString stringWithFormat:@"wake ignored disabled %@", reason ?: @""]];
        return;
    }
    [self appendPowerAutomationLog:[NSString stringWithFormat:@"app visual wake %@", reason ?: @""]];

    if (_hasBrightnessBeforeSleep) {
        CGFloat restored = MAX(0.25, MIN(1.0, _brightnessBeforeSleep));
        if ([[UIScreen mainScreen] respondsToSelector:@selector(setBrightness:)]) {
            [UIScreen mainScreen].brightness = restored;
        }
        _hasBrightnessBeforeSleep = NO;
    }

    _appPowerSleepActive = NO;
    [self returnToMainScreen];
    [UIView animateWithDuration:0.18 animations:^{
        _powerSleepOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        _powerSleepOverlay.hidden = YES;
        _powerSleepOverlay.alpha = 1.0;
    }];
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [self writeDebugState:@"app-power-wake"];
}

- (void)powerSleepOverlayTapped:(id)sender {
    [self exitAppPowerSleep:@"remote visual overlay tap"];
}

- (void)saveState {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:_wallpaperIndex forKey:@"wallpaperIndex"];
    if ([_wallpapers count]) {
        _savedWallpaperKey = [[self wallpaperKey] copy];
        [d setObject:_savedWallpaperKey forKey:@"wallpaperKey"];
    }
    [d setInteger:_dateLanguage forKey:@"dateLanguage"];
    [d setBool:_hour24 forKey:@"hour24"];
    [d setBool:_showSeconds forKey:@"showSeconds"];
    [d setBool:_dateVisible forKey:@"dateVisible"];
    [d setBool:_calendarVisible forKey:@"calendarVisible"];
    [d setFloat:_calendarScale forKey:@"calendarScale"];
    [d setFloat:_calendarOffsetX forKey:@"calendarOffsetX"];
    [d setFloat:_calendarOffsetY forKey:@"calendarOffsetY"];
    [d setFloat:_calendarOpacity forKey:@"calendarOpacity"];
    [d setBool:_gta6CountdownMode forKey:@"gta6CountdownMode"];
    [d setBool:_cleanMode forKey:@"cleanMode"];
    [d setBool:_weatherVisible forKey:@"weatherVisible"];
    if (_weatherSnapshot) [d setObject:_weatherSnapshot forKey:@"weatherSnapshot"];
    if ([_weatherCity length]) [d setObject:_weatherCity forKey:@"weatherCity"];
    [d setFloat:_weatherScale forKey:@"weatherScale"];
    [d setFloat:_weatherOffsetX forKey:@"weatherOffsetX"];
    [d setFloat:_weatherOffsetY forKey:@"weatherOffsetY"];
    [d setInteger:_wallpaperTransitionStyle forKey:@"wallpaperTransitionStyle"];
    [d setInteger:2 forKey:@"wallpaperTransitionVersion"];
    [d setObject:_favorites forKey:@"favorites"];
    [d setObject:_backgroundAdjustments forKey:@"backgroundAdjustments"];
    [d setFloat:_clockOffsetX forKey:(_gta6CountdownMode ? @"gta6ClockOffsetX" : @"clockOffsetX")];
    [d setFloat:_clockOffsetY forKey:(_gta6CountdownMode ? @"gta6ClockOffsetY" : @"clockOffsetY")];
    [d setFloat:_clockScale forKey:(_gta6CountdownMode ? @"gta6ClockScale" : @"clockScale")];
    [d setFloat:_dateOffsetX forKey:(_gta6CountdownMode ? @"gta6DateOffsetX" : @"dateOffsetX")];
    [d setFloat:_dateOffsetY forKey:(_gta6CountdownMode ? @"gta6DateOffsetY" : @"dateOffsetY")];
    [d setFloat:_dateScale forKey:(_gta6CountdownMode ? @"gta6DateScale" : @"dateScale")];
    [d setFloat:_digitCardOpacity forKey:@"digitCardOpacity"];
    CGFloat borderR = 1.0, borderG = 73.0/255.0, borderB = 158.0/255.0, borderA = 1.0;
    [_digitCardBorderColor getRed:&borderR green:&borderG blue:&borderB alpha:&borderA];
    [d setFloat:_digitCardBorderWidth forKey:@"digitCardBorderWidth"];
    [d setFloat:borderR forKey:@"digitCardBorderRed"];
    [d setFloat:borderG forKey:@"digitCardBorderGreen"];
    [d setFloat:borderB forKey:@"digitCardBorderBlue"];
    [d setFloat:_editControlsOffsetX forKey:@"editControlsOffsetX"];
    [d setFloat:_editControlsOffsetY forKey:@"editControlsOffsetY"];
    [d synchronize];
}

- (void)loadWallpapers {
    NSString *path = [IWAppPath stringByAppendingPathComponent:@"wallpapers.generated.js"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSInteger legacyCatalogCount = 0;
    NSMutableArray *items = [IWMediaCatalogItems(text, IWAppPath, &legacyCatalogCount) mutableCopy];
    NSInteger bundledCount = [items count];
    NSInteger legacySelection = _wallpaperIndex;
    // User imports remain available without the optional bundled catalog.
    [self appendUserWallpapersToItems:items];
    _wallpapers = [items copy];
    _wallpaperIndex = 0;
    if ([_savedWallpaperKey length]) {
        for (NSDictionary *item in _wallpapers) {
            if ([[item objectForKey:@"key"] isEqualToString:_savedWallpaperKey]) {
                _wallpaperIndex = [[item objectForKey:@"index"] integerValue];
                break;
            }
        }
    } else {
        // Old preferences used raw catalog positions. Rejected rows must not
        // select a different photo or shift an imported photo's identity.
        for (NSInteger i = 0; i < [_wallpapers count]; i += 1) {
            NSDictionary *item = [_wallpapers objectAtIndex:i];
            NSInteger legacyIndex = i < bundledCount ? [[item objectForKey:@"legacyIndex"] integerValue] : legacyCatalogCount + i - bundledCount;
            if (legacyIndex == legacySelection) { _wallpaperIndex = i; break; }
        }
    }
    if (_wallpaperIndex < 0 || _wallpaperIndex >= [_wallpapers count]) _wallpaperIndex = 0;
}

- (NSString *)userWallpaperDirectory {
    return [IWAppPath stringByAppendingPathComponent:@"assets/user"];
}

- (UIImage *)thumbnailForImage:(UIImage *)image size:(CGSize)size {
    if (!image) return nil;
    CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
    CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
    CGRect drawRect = CGRectMake((size.width - drawSize.width) / 2.0, (size.height - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    [image drawInRect:drawRect];
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return thumb;
}

- (UIImage *)imageConstrainedToMaxLongEdge:(UIImage *)image maxLongEdge:(CGFloat)maxLongEdge {
    if (!image || maxLongEdge <= 0) return image;
    CGFloat longEdge = MAX(image.size.width, image.size.height);
    if (longEdge <= maxLongEdge) return image;
    CGFloat scale = maxLongEdge / longEdge;
    CGSize size = CGSizeMake(round(image.size.width * scale), round(image.size.height * scale));
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}

- (void)appendUserWallpapersToItems:(NSMutableArray *)items {
    NSString *dir = [self userWallpaperDirectory];
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger added = 0;
    for (NSString *file in files) {
        if (![file hasSuffix:@".jpg"] || [file rangeOfString:@"-thumb"].location != NSNotFound) continue;
        NSString *imagePath = [dir stringByAppendingPathComponent:file];
        NSString *thumbName = [[file stringByDeletingPathExtension] stringByAppendingString:@"-thumb.jpg"];
        NSString *thumbPath = [dir stringByAppendingPathComponent:thumbName];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (!image) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
            UIImage *thumb = [self thumbnailForImage:image size:CGSizeMake(640, 360)];
            NSData *thumbData = UIImageJPEGRepresentation(thumb, 0.88);
            [thumbData writeToFile:thumbPath atomically:YES];
        }
        NSInteger index = [items count];
        added += 1;
        [items addObject:@{
            @"index": [NSNumber numberWithInteger:index],
            @"key": [NSString stringWithFormat:@"user-%@", [file stringByDeletingPathExtension]],
            @"fileName": file,
            @"label": [NSString stringWithFormat:@"系统照片_%ld", (long)added],
            @"imagePath": imagePath,
            @"thumbPath": thumbPath,
            @"width": [NSNumber numberWithFloat:image.size.width],
            @"height": [NSNumber numberWithFloat:image.size.height],
            @"themeClass": @"theme-sunset",
            @"category": @"user",
            @"themeName": @"系统照片"
        }];
    }
}

- (NSInteger)importSystemImage:(UIImage *)image {
    if (!image) return -1;
    NSString *dir = [self userWallpaperDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = [NSString stringWithFormat:@"user-%0.f-%@", [[NSDate date] timeIntervalSince1970] * 1000.0, [[[NSUUID UUID] UUIDString] lowercaseString]];
    NSString *imagePath = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".jpg"]];
    NSString *thumbPath = [dir stringByAppendingPathComponent:[name stringByAppendingString:@"-thumb.jpg"]];
    UIImage *fullImage = [self imageConstrainedToMaxLongEdge:image maxLongEdge:3840.0];
    NSData *imageData = UIImageJPEGRepresentation(fullImage, 0.95);
    if (![imageData writeToFile:imagePath atomically:YES]) return -1;
    UIImage *thumb = [self thumbnailForImage:fullImage size:CGSizeMake(640, 360)];
    NSData *thumbData = UIImageJPEGRepresentation(thumb, 0.88);
    [thumbData writeToFile:thumbPath atomically:YES];
    [self loadWallpapers];
    // A clock correction can place the new file before existing imports.
    // Select the file we wrote rather than assuming the last sorted row.
    for (NSDictionary *item in _wallpapers) {
        if ([[item objectForKey:@"imagePath"] isEqualToString:imagePath]) {
            _promoOnly = NO;
            _favoriteOnly = NO;
            _wallpaperIndex = [[item objectForKey:@"index"] integerValue];
            [self saveState];
            return _wallpaperIndex;
        }
    }
    return -1;
}

- (BOOL)canDeleteWallpaperAtIndex:(NSInteger)index {
    if (index < 0 || index >= [_wallpapers count]) return NO;
    NSDictionary *item = [_wallpapers objectAtIndex:index];
    NSString *fileName = [item objectForKey:@"fileName"];
    NSString *imagePath = [item objectForKey:@"imagePath"];
    NSString *userDir = [self userWallpaperDirectory];
    NSString *parent = [[imagePath stringByDeletingLastPathComponent] stringByStandardizingPath];
    return [fileName hasPrefix:@"user-"] && [parent isEqualToString:[userDir stringByStandardizingPath]];
}

- (NSInteger)deleteWallpapersAtIndexes:(NSArray *)indexes {
    if (![indexes count] || ![_wallpapers count]) return _wallpaperIndex;
    NSString *currentKey = [self wallpaperKey];
    NSInteger oldIndex = _wallpaperIndex;
    NSMutableSet *selected = [NSMutableSet setWithArray:indexes];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger i;
    for (NSNumber *number in selected) {
        NSInteger index = [number integerValue];
        if (![self canDeleteWallpaperAtIndex:index]) continue;
        NSDictionary *item = [_wallpapers objectAtIndex:index];
        NSString *key = [item objectForKey:@"key"];
        NSString *imagePath = [item objectForKey:@"imagePath"];
        NSString *thumbPath = [[imagePath stringByDeletingPathExtension] stringByAppendingString:@"-thumb.jpg"];
        if ([fm fileExistsAtPath:imagePath] && ![fm removeItemAtPath:imagePath error:nil]) continue;
        if ([thumbPath length]) [fm removeItemAtPath:thumbPath error:nil];
        if (key) {
            [_favorites removeObjectForKey:key];
            [_backgroundAdjustments removeObjectForKey:key];
        }
        [_thumbCache removeObjectForKey:imagePath];
    }
    [_thumbCache removeAllObjects];
    [self loadWallpapers];
    NSInteger nextIndex = -1;
    for (i = 0; i < [_wallpapers count]; i += 1) {
        NSString *key = [[_wallpapers objectAtIndex:i] objectForKey:@"key"];
        if ([key isEqualToString:currentKey]) {
            nextIndex = i;
            break;
        }
    }
    if (nextIndex < 0 && [_wallpapers count]) nextIndex = MIN(oldIndex, [_wallpapers count] - 1);
    if (nextIndex < 0) nextIndex = 0;
    _wallpaperIndex = nextIndex;
    [self applyWallpaper];
    [self saveState];
    return _wallpaperIndex;
}

- (void)buildUI {
    self.view.clipsToBounds = YES;
    _backgroundClip = [[UIView alloc] initWithFrame:self.view.bounds];
    _backgroundClip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _backgroundClip.backgroundColor = [UIColor blackColor];
    _backgroundClip.clipsToBounds = YES;
    _backgroundClip.userInteractionEnabled = NO;
    [self.view addSubview:_backgroundClip];

    _background = [[UIImageView alloc] initWithFrame:_backgroundClip.bounds];
    _background.contentMode = UIViewContentModeScaleToFill;
    _background.clipsToBounds = YES;
    [_backgroundClip addSubview:_background];

    _depthBackground = [[UIImageView alloc] initWithFrame:_backgroundClip.bounds];
    _depthBackground.contentMode = UIViewContentModeScaleToFill;
    _depthBackground.hidden = YES;
    _depthBackground.clipsToBounds = NO;
    [_backgroundClip addSubview:_depthBackground];

    _depthForeground = [[UIImageView alloc] initWithFrame:_backgroundClip.bounds];
    _depthForeground.contentMode = UIViewContentModeScaleToFill;
    _depthForeground.hidden = YES;
    _depthForeground.clipsToBounds = NO;
    _depthForeground.layer.shadowColor = [[UIColor colorWithWhite:0 alpha:0.36] CGColor];
    _depthForeground.layer.shadowOffset = CGSizeMake(0, 10.0);
    _depthForeground.layer.shadowRadius = 18.0;
    _depthForeground.layer.shadowOpacity = 1.0;
    [_backgroundClip addSubview:_depthForeground];

    _shade = [[UIView alloc] initWithFrame:self.view.bounds];
    _shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    _shade.userInteractionEnabled = NO;
    [self.view addSubview:_shade];

    _surfaceLayer = [[IWSurfaceView alloc] initWithFrame:self.view.bounds];
    _surfaceLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _surfaceLayer.backgroundColor = [UIColor clearColor];
    _surfaceLayer.multipleTouchEnabled = YES;
    ((IWSurfaceView *)_surfaceLayer).owner = self;
    [self.view addSubview:_surfaceLayer];

    _wallpaperPulse = [[UIView alloc] initWithFrame:self.view.bounds];
    _wallpaperPulse.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _wallpaperPulse.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _wallpaperPulse.alpha = 0.0;
    _wallpaperPulse.userInteractionEnabled = NO;
    [self.view addSubview:_wallpaperPulse];

    _pullIndicator = (IWIconButton *)[self circleIconButton:IWButtonKindReset];
    _pullIndicator.hidden = YES;
    _pullIndicator.userInteractionEnabled = NO;
    _pullIndicator.alpha = 0.0;
    [self.view addSubview:_pullIndicator];

    _debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 18, 340, 34)];
    _debugLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    _debugLabel.hidden = YES;
    _debugLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.64];
    _debugLabel.textColor = [UIColor whiteColor];
    _debugLabel.font = IWGTATextFont(13.0);
    _debugLabel.textAlignment = NSTextAlignmentCenter;
    _debugLabel.layer.cornerRadius = 8.0;
    _debugLabel.clipsToBounds = YES;
    _debugLabel.userInteractionEnabled = NO;
    [self.view addSubview:_debugLabel];

    _clockFace = [[UIView alloc] initWithFrame:CGRectZero];
    _clockFace.tag = 91;
    _clockFace.backgroundColor = [UIColor clearColor];
    _clockFace.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _clockFace.userInteractionEnabled = NO;
    [self.view addSubview:_clockFace];

    _digitGroup = [[UIView alloc] initWithFrame:CGRectZero];
    _digitGroup.backgroundColor = [UIColor clearColor];
    _digitGroup.userInteractionEnabled = NO;
    [_clockFace addSubview:_digitGroup];

    _digitLabels = [NSMutableArray array];
    _colonViews = [NSMutableArray array];

    _dateLabel = [[IWDateLabel alloc] initWithFrame:CGRectZero];
    _dateLabel.textColor = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:1.0];
    _dateLabel.font = IWGTATextFont(18.0);
    _dateLabel.textAlignment = NSTextAlignmentCenter;
    _dateLabel.shadowColor = nil;
    _dateLabel.shadowOffset = CGSizeZero;
    [_clockFace addSubview:_dateLabel];

    _countdownDayLabels = [NSMutableArray array];
    NSInteger countdownIndex;
    for (countdownIndex = 0; countdownIndex < 3; countdownIndex += 1) {
        UILabel *digit = [self digitLabel];
        digit.hidden = YES;
        [_countdownDayLabels addObject:digit];
        [_digitGroup addSubview:digit];
    }

    NSInteger i;
    for (i = 0; i < 6; i += 1) {
        UILabel *digit = [self digitLabel];
        [_digitLabels addObject:digit];
        [_digitGroup addSubview:digit];
    }
    for (i = 0; i < 3; i += 1) {
        UIView *colon = [self colonView];
        [_colonViews addObject:colon];
        [_digitGroup addSubview:colon];
    }
    [self applyDigitCardOpacity];
    [self applyDigitCardBorderStyle];
    [self buildCalendarPanel];
    [self buildWeatherPanel];

    _menuButton = [self actionButton:IWButtonKindMenu];
    _menuButton.frame = CGRectMake(self.view.bounds.size.width - IWControlRightMargin() - IWControlSize(), 18, IWControlSize(), IWControlSize());
    _menuButton.backgroundColor = [UIColor clearColor];
    _menuButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [_menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_menuButton];

    [self buildMenu];
    [self buildEditToolbar];
    [self buildHomePanel];
    [self buildVideoOverlay];
    [self buildPowerSleepOverlay];
    [self installSurfaceGestureFallbacks];
}

- (void)installSurfaceGestureFallbacks {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundPan:)];
    pan.cancelsTouchesInView = NO;
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [self.view addGestureRecognizer:pan];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundPinch:)];
    pinch.cancelsTouchesInView = NO;
    pinch.delegate = self;
    [self.view addGestureRecognizer:pinch];

    NSArray *directions = @[
        @(UISwipeGestureRecognizerDirectionUp),
        @(UISwipeGestureRecognizerDirectionDown),
        @(UISwipeGestureRecognizerDirectionLeft),
        @(UISwipeGestureRecognizerDirectionRight)
    ];
    for (NSNumber *direction in directions) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSurfaceSwipeGesture:)];
        swipe.direction = [direction unsignedIntegerValue];
        swipe.cancelsTouchesInView = NO;
        swipe.delegate = self;
        [self.view addGestureRecognizer:swipe];
    }
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleBackgroundLongPress:)];
    longPress.minimumPressDuration = 0.55;
    longPress.cancelsTouchesInView = NO;
    longPress.delegate = self;
    [self.view addGestureRecognizer:longPress];
}

- (void)applyClockTransforms {
    _clockScale = MAX(IWClockScaleMin(), MIN(IWClockScaleMax(), _clockScale <= 0 ? 1.0 : _clockScale));
    _dateScale = MAX(IWDateScaleMin(), MIN(IWDateScaleMax(), _dateScale <= 0 ? 1.0 : _dateScale));
    CGAffineTransform clockTransform = CGAffineTransformMakeTranslation(_clockOffsetX, _clockOffsetY);
    clockTransform = CGAffineTransformScale(clockTransform, _clockScale, _clockScale);
    _digitGroup.transform = clockTransform;
    CGAffineTransform dateTransform = CGAffineTransformMakeTranslation(_dateOffsetX, _dateOffsetY);
    dateTransform = CGAffineTransformScale(dateTransform, _dateScale, _dateScale);
    _dateLabel.transform = dateTransform;
}

- (void)keepVisibleClockInsideScreen {
    CGRect visibleBounds = CGRectNull;
    NSMutableArray *views = [NSMutableArray arrayWithArray:_digitLabels ?: @[]];
    [views addObjectsFromArray:_countdownDayLabels ?: @[]];
    [views addObjectsFromArray:_colonViews ?: @[]];
    for (UIView *view in views) {
        if (view.hidden) continue;
        CGRect rect = [view convertRect:view.bounds toView:self.view];
        visibleBounds = CGRectIsNull(visibleBounds) ? rect : CGRectUnion(visibleBounds, rect);
    }
    if (CGRectIsNull(visibleBounds)) return;
    CGFloat inset = 12.0;
    CGFloat correctionX = 0.0, correctionY = 0.0;
    if (CGRectGetMinX(visibleBounds) < inset) correctionX = inset - CGRectGetMinX(visibleBounds);
    else if (CGRectGetMaxX(visibleBounds) > self.view.bounds.size.width - inset) correctionX = self.view.bounds.size.width - inset - CGRectGetMaxX(visibleBounds);
    if (CGRectGetMinY(visibleBounds) < inset) correctionY = inset - CGRectGetMinY(visibleBounds);
    else if (CGRectGetMaxY(visibleBounds) > self.view.bounds.size.height - inset) correctionY = self.view.bounds.size.height - inset - CGRectGetMaxY(visibleBounds);
    if (correctionX != 0.0 || correctionY != 0.0) {
        _clockOffsetX += correctionX;
        _clockOffsetY += correctionY;
        [self applyClockTransforms];
    }
}

- (void)applyDigitCardOpacity {
    _digitCardOpacity = IWDigitCardClampOpacity(_digitCardOpacity);
    for (UILabel *digit in _digitLabels) {
        if ([digit respondsToSelector:@selector(setCardOpacity:)]) {
            [(IWFlipDigitLabel *)digit setCardOpacity:_digitCardOpacity];
        }
    }
    for (UILabel *digit in _countdownDayLabels) {
        if ([digit respondsToSelector:@selector(setCardOpacity:)]) {
            [(IWFlipDigitLabel *)digit setCardOpacity:_digitCardOpacity];
        }
    }
    if (_opacitySlider) _opacitySlider.value = _digitCardOpacity;
}

- (void)applyCalendarOpacity {
    _calendarOpacity = IWDigitCardClampOpacity(_calendarOpacity);
    _calendarPanel.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:_calendarOpacity];
    if (_opacitySlider) _opacitySlider.value = _calendarOpacity;
}

- (void)applyDigitCardBorderStyle {
    UIColor *color = _digitCardBorderColor ?: [self themedAccent];
    _digitCardBorderWidth = MAX(1.0, MIN(6.0, _digitCardBorderWidth));
    for (UILabel *digit in _digitLabels) {
        if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
            IWFlipDigitLabel *card = (IWFlipDigitLabel *)digit;
            card.accentColor = color;
            card.borderWidth = _digitCardBorderWidth;
        }
    }
    for (UILabel *digit in _countdownDayLabels) {
        if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
            IWFlipDigitLabel *card = (IWFlipDigitLabel *)digit;
            card.accentColor = color;
            card.borderWidth = _digitCardBorderWidth;
        }
    }
    CGFloat r = 1.0, g = 73.0/255.0, b = 158.0/255.0, a = 1.0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    if (_borderWidthSlider) _borderWidthSlider.value = _digitCardBorderWidth;
    if (_borderColorPalette) _borderColorPalette.selectedColor = color;
    for (UIButton *themeButton in _borderThemeButtons) {
        CGFloat tr = 0, tg = 0, tb = 0, ta = 0;
        [themeButton.backgroundColor getRed:&tr green:&tg blue:&tb alpha:&ta];
        BOOL selected = fabs(tr - r) < 0.03 && fabs(tg - g) < 0.03 && fabs(tb - b) < 0.03;
        themeButton.layer.borderWidth = selected ? 3.0 : IWControlBorderWidth();
        themeButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:(selected ? 1.0 : 0.82)] CGColor];
        themeButton.selected = selected;
        UIAccessibilityTraits traits = themeButton.accessibilityTraits;
        if (selected) traits |= UIAccessibilityTraitSelected;
        else traits &= ~UIAccessibilityTraitSelected;
        themeButton.accessibilityTraits = traits;
    }
    for (UIView *colon in _colonViews) {
        UIView *dotA = [colon viewWithTag:1];
        UIView *dotB = [colon viewWithTag:2];
        for (IWColonDot *dot in @[(IWColonDot *)dotA, (IWColonDot *)dotB]) {
            dot.backgroundColor = [UIColor clearColor];
            dot.dotColor = color;
            [dot setNeedsDisplay];
        }
    }
    _weatherRangeLabel.textColor = [color colorWithAlphaComponent:0.92];
    _weatherCityLabel.textColor = [color colorWithAlphaComponent:0.98];
    [self updateWeatherEditAppearance];
}

- (void)updateBorderControlVisibility {
    BOOL visible = _editMode && _editTarget == IWEditTargetClock;
    _borderControl.hidden = !visible;
    if (visible) [self applyDigitCardBorderStyle];
}

- (void)updateOpacityControlVisibility {
    BOOL visible = _editMode && (_editTarget == IWEditTargetClock || _editTarget == IWEditTargetDate || _editTarget == IWEditTargetCalendar);
    _opacityControl.hidden = !visible;
    if (visible && _editTarget == IWEditTargetCalendar) [self applyCalendarOpacity];
    else if (visible) [self applyDigitCardOpacity];
    [self updateBorderControlVisibility];
}

- (void)applyDepthLayout {
    if (!_depthBackground || !_depthForeground) return;
    CGFloat w = _backgroundClip.bounds.size.width;
    CGFloat h = _backgroundClip.bounds.size.height;
    if (w <= 0 || h <= 0) return;
    CGFloat bgPad = 28.0;
    CGFloat fgPad = 46.0;
    _depthBackground.frame = CGRectMake(-bgPad - _depthTiltX * 10.0, -bgPad - _depthTiltY * 8.0, w + bgPad * 2.0, h + bgPad * 2.0);
    _depthForeground.frame = CGRectMake(-fgPad + _depthTiltX * 36.0, -fgPad + _depthTiltY * 28.0, w + fgPad * 2.0, h + fgPad * 2.0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _digitGroup.transform = CGAffineTransformIdentity;
    _dateLabel.transform = CGAffineTransformIdentity;
    CGFloat faceLeft = self.view.bounds.size.width * 0.05;
    CGFloat faceWidth = self.view.bounds.size.width - faceLeft * 2.0;
    CGFloat cssCardWidth = _gta6CountdownMode ? MIN(74.0, MAX(58.0, self.view.bounds.size.width * 0.072)) : MIN(118.0, MAX(76.0, self.view.bounds.size.width * 0.12));
    CGFloat cssCardHeight = _gta6CountdownMode ? MIN(112.0, MAX(92.0, self.view.bounds.size.width * 0.11)) : MIN(170.0, MAX(108.0, self.view.bounds.size.width * 0.17));
    CGFloat cardWidth = cssCardWidth + 2.0;
    CGFloat cardHeight = cssCardHeight + 2.0;
    CGFloat cardGap = _gta6CountdownMode ? 6.0 : 10.0;
    CGFloat colonWidth = _gta6CountdownMode ? 22.0 : 30.0;
    BOOL secondsVisible = _gta6CountdownMode || _showSeconds;
    NSInteger visibleDigits = secondsVisible ? 6 : 4;
    NSInteger visibleColons = _gta6CountdownMode ? 3 : (secondsVisible ? 2 : 1);
    NSInteger countdownDigits = _gta6CountdownMode ? 3 : 0;
    NSInteger visibleElements = visibleDigits + visibleColons + countdownDigits;
    CGFloat rowWidth = cardWidth * (visibleDigits + countdownDigits) + colonWidth * visibleColons + cardGap * (visibleElements - 1);
    CGFloat startX = (faceWidth - rowWidth) / 2.0;
    CGFloat top = 54.0;
    CGFloat bottom = _homeVisible ? 142.0 : 44.0;
    _clockFace.frame = CGRectMake(faceLeft, self.view.bounds.size.height - bottom - top - cardHeight, faceWidth, top + cardHeight);
    _digitGroup.frame = _clockFace.bounds;
    if (_pullIndicator.hidden) {
        _pullIndicator.frame = CGRectMake((self.view.bounds.size.width - IWControlSize()) / 2.0, -46.0, IWControlSize(), IWControlSize());
    }

    NSInteger i;
    CGFloat x = startX;
    for (UILabel *digit in _countdownDayLabels) digit.hidden = !_gta6CountdownMode;
    if (_gta6CountdownMode) {
        for (UILabel *digit in _countdownDayLabels) {
            digit.frame = CGRectMake(x, top, cardWidth, cardHeight);
            digit.layer.cornerRadius = 12.0;
            digit.font = IWGTAFont(cssCardHeight * 0.82);
            x += cardWidth + cardGap;
        }
        UIView *dayColon = [_colonViews objectAtIndex:0];
        dayColon.hidden = NO;
        dayColon.frame = CGRectMake(x, top, colonWidth, cardHeight);
        UIView *dayDotA = [dayColon viewWithTag:1];
        UIView *dayDotB = [dayColon viewWithTag:2];
        CGFloat dayDot = 20.0;
        dayDotA.frame = CGRectMake((colonWidth - dayDot) / 2.0, cardHeight / 2.0 - 28.0, dayDot, dayDot);
        dayDotB.frame = CGRectMake((colonWidth - dayDot) / 2.0, cardHeight / 2.0 + 8.0, dayDot, dayDot);
        dayDotA.layer.cornerRadius = dayDot / 2.0;
        dayDotB.layer.cornerRadius = dayDot / 2.0;
        x += colonWidth + cardGap;
    } else {
        [[_colonViews objectAtIndex:0] setHidden:YES];
    }
    for (i = 0; i < 6; i += 1) {
        if (i == 2 || i == 4) {
            UIView *colon = [_colonViews objectAtIndex:(i == 2 ? 1 : 2)];
            colon.hidden = !secondsVisible && i == 4;
            if (!colon.hidden) colon.frame = CGRectMake(x, top, colonWidth, cardHeight);
            UIView *dotA = [colon viewWithTag:1];
            UIView *dotB = [colon viewWithTag:2];
            CGFloat dot = 20.0;
            dotA.frame = CGRectMake((colonWidth - dot) / 2.0, cardHeight / 2.0 - 28.0, dot, dot);
            dotB.frame = CGRectMake((colonWidth - dot) / 2.0, cardHeight / 2.0 + 8.0, dot, dot);
            dotA.layer.cornerRadius = dot / 2.0;
            dotB.layer.cornerRadius = dot / 2.0;
            if (!colon.hidden) x += colonWidth + cardGap;
        }
        UILabel *digit = [_digitLabels objectAtIndex:i];
        digit.hidden = !secondsVisible && i >= 4;
        if (!digit.hidden) digit.frame = CGRectMake(x, top, cardWidth, cardHeight);
        digit.layer.cornerRadius = 12.0;
        digit.font = IWGTAFont(cssCardHeight * 0.82);
        if (!digit.hidden) x += cardWidth + cardGap;
    }
    NSInteger dateTargetIndex = secondsVisible ? 5 : 3;
    UILabel *dateTarget = [_digitLabels objectAtIndex:dateTargetIndex];
    CGFloat dateWidth = 150.0;
    CGFloat dateCenter = CGRectGetMidX(dateTarget.frame);
    CGFloat dateX = MAX(0.0, MIN(faceWidth - dateWidth, round(dateCenter - dateWidth / 2.0)));
    _dateLabel.frame = CGRectMake(dateX, 0, dateWidth, 32.0);
    _dateLabel.font = IWGTATextFont(19.0);
    [self applyClockTransforms];
    [self keepVisibleClockInsideScreen];
    [CATransaction commit];

    CGFloat menuRightColumnX = self.view.bounds.size.width - IWControlRightMargin() - IWControlSize();
    _menu.frame = CGRectMake(menuRightColumnX - 68.0, 70, 124.0, 390.0);
    CGFloat secondaryMenuHeight = _secondaryMenuMode == 2 ? 66.0 : 120.0;
    _settingsMenu.frame = CGRectMake(CGRectGetMinX(_menu.frame), CGRectGetMinY(_menu.frame) + 400.0, 124.0, secondaryMenuHeight);
    // Never assign a frame while the calendar has a transform: UIKit derives
    // a transformed frame from bounds/center, which previously desynchronised
    // the border from its date grid after a pinch.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _calendarPanel.transform = CGAffineTransformIdentity;
    NSDateComponents *calendarLayoutDate = [IWDisplayCalendar() components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:[NSDate date]];
    NSInteger calendarLayoutYear = _calendarDisplayYear ?: calendarLayoutDate.year;
    NSInteger calendarLayoutMonth = _calendarDisplayMonth ?: calendarLayoutDate.month;
    _calendarPanel.bounds = CGRectMake(0.0, 0.0, 252.0, [self calendarPanelHeightForYear:calendarLayoutYear month:calendarLayoutMonth]);
    _calendarPanel.center = CGPointMake(156.0, 183.0);
    _calendarMonthLabel.frame = CGRectMake(21.0, 13.0, 215.0, 25.0);
    CGFloat calendarCellW = 220.0 / 7.0;
    NSInteger calendarIndex;
    for (calendarIndex = 0; calendarIndex < [_calendarWeekdayLabels count]; calendarIndex += 1) {
        UILabel *label = [_calendarWeekdayLabels objectAtIndex:calendarIndex];
        label.frame = CGRectMake(16.0 + calendarIndex * calendarCellW, 44.0, calendarCellW, 18.0);
    }
    for (calendarIndex = 0; calendarIndex < [_calendarDayLabels count]; calendarIndex += 1) {
        UILabel *label = [_calendarDayLabels objectAtIndex:calendarIndex];
        NSInteger column = calendarIndex % 7;
        NSInteger row = calendarIndex / 7;
        // Keep the highlighted day capsule inside its own row.  The former
        // 26pt-high capsule on a 22pt grid made adjacent weeks overlap.
        label.frame = CGRectMake(16.0 + column * calendarCellW + (calendarCellW - 22.0) / 2.0, 64.0 + row * 22.0, 22.0, 20.0);
        label.layer.cornerRadius = 10.0;
        UIView *dot = [_calendarHolidayDots objectAtIndex:calendarIndex];
        dot.frame = CGRectMake(CGRectGetMaxX(label.frame) - 5.5, CGRectGetMinY(label.frame) + 2.0, 4.0, 4.0);
        dot.layer.cornerRadius = 2.0;
    }
    _calendarRenderedDayKey = nil;
    [self updateCalendarPanel];
    [self applyCalendarTransform];
    [CATransaction commit];
    CGFloat weatherWidth = 320.0;
    CGFloat weatherX = self.view.bounds.size.width - weatherWidth - 34.0;
    if (!_menu.hidden) {
        CGFloat scaledHalfWidth = weatherWidth * _weatherScale / 2.0;
        weatherX = MIN(weatherX, CGRectGetMinX(_menu.frame) - 14.0 - _weatherOffsetX - scaledHalfWidth - weatherWidth / 2.0);
    }
    _weatherPanel.transform = CGAffineTransformIdentity;
    _weatherPanel.bounds = CGRectMake(0.0, 0.0, weatherWidth, 112.0);
    _weatherPanel.center = CGPointMake(MAX(20.0, weatherX) + weatherWidth / 2.0, 134.0);
    [self applyWeatherTransform];
    _homePanel.frame = CGRectMake(34, self.view.bounds.size.height - 96, self.view.bounds.size.width - 68, 68);
    _homeUpdatedLabel.frame = CGRectMake(0, -28, _homePanel.bounds.size.width, 18);
    CGFloat homeGap = 12.0;
    NSInteger visibleHomeCards = 0;
    NSInteger visibleIndex = 0;
    NSInteger cardIndex;
    for (cardIndex = 0; cardIndex < [_homeCards count]; cardIndex += 1) {
        UIView *card = [_homeCards objectAtIndex:cardIndex];
        if (!card.hidden) visibleHomeCards += 1;
    }
    if (visibleHomeCards <= 0) visibleHomeCards = 1;
    CGFloat homeCardWidth = (_homePanel.bounds.size.width - homeGap * (visibleHomeCards - 1)) / visibleHomeCards;
    for (cardIndex = 0; cardIndex < [_homeCards count]; cardIndex += 1) {
        UIView *card = [_homeCards objectAtIndex:cardIndex];
        if (card.hidden) continue;
        card.frame = CGRectMake(visibleIndex * (homeCardWidth + homeGap), 0, homeCardWidth, 68.0);
        visibleIndex += 1;
    }
    _editToolbar.frame = CGRectMake((self.view.bounds.size.width - (IWControlSize() * 3.0 + IWControlGap() * 2.0)) / 2.0, 18.0, IWControlSize() * 3.0 + IWControlGap() * 2.0, IWControlSize());
    _editResetButton.frame = CGRectMake(0, 0, IWControlSize(), IWControlSize());
    _editCancelButton.frame = CGRectMake(IWControlSize() + IWControlGap(), 0, IWControlSize(), IWControlSize());
    _editDoneButton.frame = CGRectMake((IWControlSize() + IWControlGap()) * 2.0, 0, IWControlSize(), IWControlSize());
    CGFloat opacityWidth = 262.0;
    CGFloat editControlsX = MAX(0.0, MIN(self.view.bounds.size.width - (opacityWidth + IWControlGap() + IWControlSize()), 20.0 + _editControlsOffsetX));
    CGFloat editControlsY = MAX(0.0, MIN(self.view.bounds.size.height - 242.0, 18.0 + _editControlsOffsetY));
    _editControlsOffsetX = editControlsX - 20.0;
    _editControlsOffsetY = editControlsY - 18.0;
    CGFloat opacityY = _editTarget == IWEditTargetCalendar ? editControlsY : editControlsY + 184.0;
    _opacityControl.frame = CGRectMake(editControlsX, opacityY, opacityWidth + IWControlGap() + IWControlSize(), 40.0);
    _opacitySlider.frame = CGRectMake(0, 0, opacityWidth, 31.0);
    CGFloat borderWidth = opacityWidth;
    _borderControl.frame = CGRectMake(editControlsX, editControlsY, borderWidth, 180.0);
    NSInteger borderThemeIndex;
    for (borderThemeIndex = 0; borderThemeIndex < [_borderThemeButtons count]; borderThemeIndex += 1) {
        UIButton *button = [_borderThemeButtons objectAtIndex:borderThemeIndex];
        button.frame = CGRectMake(borderThemeIndex * (IWControlSize() + IWControlGap()), 0, IWControlSize(), IWControlSize());
    }
    _borderColorPalette.frame = CGRectMake(0, 54.0, borderWidth, 75.0);
    _borderWidthSlider.frame = CGRectMake(0, 137.0, borderWidth, 31.0);
    _editControlsMoveButton.frame = CGRectMake(opacityWidth + IWControlGap(), -8.0, IWControlSize(), IWControlSize());
    _videoOverlay.frame = self.view.bounds;
    UIView *playerView = [_videoOverlay viewWithTag:501];
    playerView.frame = _videoOverlay.bounds;
    _videoTapShield.frame = _videoOverlay.bounds;
    UIView *closeButton = [_videoOverlay viewWithTag:502];
    closeButton.frame = CGRectMake(28.0, 18.0, IWControlSize(), IWControlSize());
    UIView *minimizeButton = [_videoOverlay viewWithTag:503];
    minimizeButton.frame = CGRectMake(CGRectGetMaxX(closeButton.frame) + IWControlGap(), 18.0, IWControlSize(), IWControlSize());
    CGFloat controlsW = MIN(680.0, _videoOverlay.bounds.size.width - 72.0);
    _videoControls.frame = CGRectMake(round((_videoOverlay.bounds.size.width - controlsW) / 2.0), _videoOverlay.bounds.size.height - 118.0, controlsW, 86.0);
    CGFloat centerX = _videoControls.bounds.size.width / 2.0;
    _videoRewindButton.frame = CGRectMake(centerX - IWControlSize() * 1.5 - 18.0, 11.0, IWControlSize(), IWControlSize());
    _videoPlayButton.frame = CGRectMake(centerX - IWControlSize() / 2.0, 11.0, IWControlSize(), IWControlSize());
    _videoForwardButton.frame = CGRectMake(centerX + IWControlSize() / 2.0 + 18.0, 11.0, IWControlSize(), IWControlSize());
    _airPlayView.frame = CGRectMake(_videoControls.bounds.size.width - IWControlSize() - 24.0, 11.0, IWControlSize(), IWControlSize());
    _videoVolumeButton.frame = CGRectMake(_videoControls.bounds.size.width - IWControlSize() * 2.0 - IWControlGap() - 24.0, 11.0, IWControlSize(), IWControlSize());
    CGFloat volumeCenterX = CGRectGetMinX(_videoControls.frame) + CGRectGetMidX(_videoVolumeButton.frame);
    _volumePanel.frame = CGRectMake(round(volumeCenterX - 23.0), CGRectGetMinY(_videoControls.frame) - 162.0, 46.0, 150.0);
    _volumeSlider.bounds = CGRectMake(0.0, 0.0, 118.0, 32.0);
    _volumeSlider.center = CGPointMake(_volumePanel.bounds.size.width / 2.0, _volumePanel.bounds.size.height / 2.0);
    _volumeSlider.transform = CGAffineTransformMakeRotation((CGFloat)-M_PI_2);
    _volumeView.frame = CGRectMake(-1000.0, -1000.0, 1.0, 1.0);
    _volumeView.transform = CGAffineTransformIdentity;
    _videoCurrentLabel.frame = CGRectMake(18.0, 62.0, 46.0, 22.0);
    _videoDurationLabel.frame = CGRectMake(_videoControls.bounds.size.width - 64.0, 62.0, 46.0, 22.0);
    _videoSlider.frame = CGRectMake(68.0, 62.0, _videoControls.bounds.size.width - 136.0, 22.0);
    _moviePlayer.view.frame = playerView.bounds;
    _remoteVideoLayer.frame = playerView.bounds;
    [_videoOverlay bringSubviewToFront:_videoTapShield];
    [_videoOverlay bringSubviewToFront:closeButton];
    [_videoOverlay bringSubviewToFront:minimizeButton];
    [_videoOverlay bringSubviewToFront:_videoControls];
    [_videoOverlay bringSubviewToFront:_volumePanel];
    [self styleVideoVolumeViews];
    _powerSleepOverlay.frame = self.view.bounds;
    if (_appPowerSleepActive) [self.view bringSubviewToFront:_powerSleepOverlay];
    [self applyDepthLayout];
    [self applyBackgroundTransform];
}

- (UILabel *)digitLabel {
    UILabel *label = [[IWFlipDigitLabel alloc] initWithFrame:CGRectZero];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor colorWithRed:17.0/255.0 green:17.0/255.0 blue:26.0/255.0 alpha:1.0];
    label.font = IWGTAFont(118.0);
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.72;
    label.clipsToBounds = NO;
    return label;
}

- (UIView *)colonView {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [UIColor clearColor];
    UIView *a = [[IWColonDot alloc] initWithFrame:CGRectZero];
    a.tag = 1;
    [view addSubview:a];
    UIView *b = [[IWColonDot alloc] initWithFrame:CGRectZero];
    b.tag = 2;
    [view addSubview:b];
    return view;
}

- (void)buildCalendarPanel {
    // The root surface only passes UIControls through, so this must be a
    // control for its own long-press recognizer to receive device touches.
    _calendarPanel = [[UIControl alloc] initWithFrame:CGRectZero];
    _calendarPanel.hidden = !_calendarVisible;
    _calendarPanel.userInteractionEnabled = YES;
    _calendarPanel.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:_calendarOpacity];
    _calendarPanel.layer.cornerRadius = 12.0;
    _calendarPanel.layer.borderWidth = IWControlBorderWidth();
    _calendarPanel.clipsToBounds = YES;
    // The panel clips its contents, so an outer shadow cannot be shown here
    // but still forces expensive off-screen compositing on iPad 4.  Cache the
    // static calendar instead; moving/scaling then becomes one layer transform.
    _calendarPanel.layer.shadowOpacity = 0.0;
    _calendarPanel.layer.shouldRasterize = YES;
    _calendarPanel.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    [self.view addSubview:_calendarPanel];
    UILongPressGestureRecognizer *calendarLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleCalendarLongPress:)];
    calendarLongPress.minimumPressDuration = 0.55;
    calendarLongPress.cancelsTouchesInView = NO;
    [_calendarPanel addGestureRecognizer:calendarLongPress];
    UIPinchGestureRecognizer *calendarPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleCalendarPinch:)];
    calendarPinch.cancelsTouchesInView = NO;
    [_calendarPanel addGestureRecognizer:calendarPinch];
    UISwipeGestureRecognizer *calendarPrevious = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleCalendarMonthSwipe:)];
    calendarPrevious.direction = UISwipeGestureRecognizerDirectionRight;
    calendarPrevious.cancelsTouchesInView = NO;
    [_calendarPanel addGestureRecognizer:calendarPrevious];
    UISwipeGestureRecognizer *calendarNext = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleCalendarMonthSwipe:)];
    calendarNext.direction = UISwipeGestureRecognizerDirectionLeft;
    calendarNext.cancelsTouchesInView = NO;
    [_calendarPanel addGestureRecognizer:calendarNext];
    UISwipeGestureRecognizer *calendarToday = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(returnCalendarToToday:)];
    calendarToday.direction = UISwipeGestureRecognizerDirectionDown;
    calendarToday.cancelsTouchesInView = NO;
    [_calendarPanel addGestureRecognizer:calendarToday];
    UITapGestureRecognizer *calendarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCalendarTap:)];
    calendarTap.cancelsTouchesInView = NO;
    [calendarTap requireGestureRecognizerToFail:calendarPrevious];
    [calendarTap requireGestureRecognizerToFail:calendarNext];
    [calendarTap requireGestureRecognizerToFail:calendarToday];
    [_calendarPanel addGestureRecognizer:calendarTap];
    [(UIControl *)_calendarPanel addTarget:self action:@selector(calendarTouchDown:forEvent:) forControlEvents:UIControlEventTouchDown];
    [(UIControl *)_calendarPanel addTarget:self action:@selector(calendarTouchDrag:forEvent:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
    [(UIControl *)_calendarPanel addTarget:self action:@selector(calendarTouchUp:forEvent:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _calendarMonthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _calendarMonthLabel.textAlignment = NSTextAlignmentLeft;
    _calendarMonthLabel.font = IWGTATextFont(18.0);
    [_calendarPanel addSubview:_calendarMonthLabel];
    _calendarWeekdayLabels = [NSMutableArray array];
    _calendarDayLabels = [NSMutableArray array];
    _calendarHolidayDots = [NSMutableArray array];
    NSArray *weekdays = @[@"S", @"M", @"T", @"W", @"T", @"F", @"S"];
    NSInteger i;
    for (i = 0; i < 7; i += 1) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = [weekdays objectAtIndex:i];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = IWGTATextFont(11.0);
        [_calendarPanel addSubview:label];
        [_calendarWeekdayLabels addObject:label];
    }
    for (i = 0; i < 42; i += 1) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = IWGTATextFont(14.0);
        label.layer.cornerRadius = 13.0;
        label.clipsToBounds = YES;
        [_calendarPanel addSubview:label];
        [_calendarDayLabels addObject:label];
        UIView *dot = [[UIView alloc] initWithFrame:CGRectZero];
        dot.hidden = YES;
        dot.userInteractionEnabled = NO;
        [_calendarPanel addSubview:dot];
        [_calendarHolidayDots addObject:dot];
    }
    _calendarHolidaySummaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _calendarHolidaySummaryLabel.textAlignment = NSTextAlignmentLeft;
    _calendarHolidaySummaryLabel.font = IWGTATextFont(10.0);
    _calendarHolidaySummaryLabel.numberOfLines = 1;
    _calendarHolidaySummaryLabel.adjustsFontSizeToFitWidth = YES;
    _calendarHolidaySummaryLabel.minimumScaleFactor = 0.72;
    _calendarHolidaySummaryLabel.hidden = YES;
    [_calendarPanel addSubview:_calendarHolidaySummaryLabel];
    _calendarHolidayToast = [[UIView alloc] initWithFrame:CGRectZero];
    _calendarHolidayToast.hidden = YES;
    _calendarHolidayToast.userInteractionEnabled = NO;
    _calendarHolidayToast.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.82];
    _calendarHolidayToast.layer.cornerRadius = 9.0;
    _calendarHolidayToast.layer.borderWidth = IWControlBorderWidth();
    _calendarHolidayToast.layer.borderColor = [IWThemePink(0.82) CGColor];
    [self.view addSubview:_calendarHolidayToast];
    _calendarHolidayToastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _calendarHolidayToastLabel.textAlignment = NSTextAlignmentCenter;
    _calendarHolidayToastLabel.font = IWGTATextFont(12.0);
    _calendarHolidayToastLabel.textColor = [UIColor whiteColor];
    [_calendarHolidayToast addSubview:_calendarHolidayToastLabel];
    [self updateCalendarPanel];
}

- (void)handleCalendarLongPress:(UILongPressGestureRecognizer *)recognizer {
    [self appendTouchDebug:[NSString stringWithFormat:@"calendar-control-longpress state=%ld", (long)recognizer.state]];
    if (recognizer.state != UIGestureRecognizerStateBegan || _editMode || (_videoOverlay && !_videoOverlay.hidden)) return;
    [self resetPullIndicator];
    [self enterCalendarEditMode];
    CGPoint p = [recognizer locationInView:self.view];
    [self prepareCurrentEditDragBaselineAtPoint:p];
    [self markSurfaceActionHandled:@"calendar-control-longpress-edit"];
    [self writeDebugState:@"calendar-control-longpress-edit"];
}

- (void)calendarTouchDown:(UIControl *)control forEvent:(UIEvent *)event {
    [self appendTouchDebug:@"calendar-control-touchdown"];
    if (!_editMode || _editTarget != IWEditTargetCalendar) return;
    // A temporary 1x cache cuts the compositing load substantially while the
    // whole panel is being translated on the iPad 4.  Restore Retina cache at
    // rest, so text remains crisp after the finger lifts.
    control.layer.rasterizationScale = 1.0;
    UITouch *touch = [[event touchesForView:control] anyObject];
    if (touch) [self prepareCurrentEditDragBaselineAtPoint:[touch locationInView:self.view]];
}

- (void)calendarTouchDrag:(UIControl *)control forEvent:(UIEvent *)event {
    if (!_editMode || _editTarget != IWEditTargetCalendar) return;
    NSSet *touches = [event touchesForView:control];
    if ([touches count] != 1) return; // Pinch owns two-finger movement.
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    CGPoint p = [touch locationInView:self.view];
    CGPoint delta = CGPointMake((p.x - _surfaceStart.x) * IWEditDragGain(), (p.y - _surfaceStart.y) * IWEditDragGain());
    _calendarOffsetX = _editStartX + delta.x;
    _calendarOffsetY = _editStartY + delta.y;
    [self applyCalendarTransform];
}

- (void)calendarTouchUp:(UIControl *)control forEvent:(UIEvent *)event {
    (void)control; (void)event;
    control.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    if (!_editMode || _editTarget != IWEditTargetCalendar) return;
    [self persistCurrentEditValues];
    [self writeDebugState:@"calendar-direct-drag-persist"];
}

- (void)handleCalendarPinch:(UIPinchGestureRecognizer *)recognizer {
    if (!_editMode || _editTarget != IWEditTargetCalendar) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _editStartZoom = _calendarScale;
        [self appendTouchDebug:@"calendar-panel-pinch-began"];
    }
    _calendarScale = MAX(IWCalendarScaleMin(), MIN(IWCalendarScaleMax(), _editStartZoom * recognizer.scale));
    [self applyCalendarTransform];
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self persistCurrentEditValues];
        [self writeDebugState:@"calendar-panel-pinch-persist"];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        [self writeDebugState:@"calendar-panel-pinch-cancel"];
    }
}

- (void)handleCalendarMonthSwipe:(UISwipeGestureRecognizer *)recognizer {
    if (_editMode || _calendarMonthTransitioning) return;
    NSDate *now = [NSDate date];
    NSCalendar *calendar = IWDisplayCalendar();
    NSDateComponents *current = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:now];
    NSDateComponents *shown = [[NSDateComponents alloc] init];
    shown.year = _calendarDisplayYear ?: current.year;
    shown.month = _calendarDisplayMonth ?: current.month;
    shown.day = 1;
    NSDateComponents *delta = [[NSDateComponents alloc] init];
    delta.month = recognizer.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1;
    NSDate *next = [calendar dateByAddingComponents:delta toDate:[calendar dateFromComponents:shown] options:0];
    NSDateComponents *nextComponents = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:next];
    NSInteger direction = recognizer.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    UIView *outgoing = reduceMotion ? nil : [_calendarPanel snapshotViewAfterScreenUpdates:NO];
    CGRect calendarFrame = [_calendarPanel convertRect:_calendarPanel.bounds toView:self.view];
    if (outgoing) {
        outgoing.frame = calendarFrame;
        outgoing.userInteractionEnabled = NO;
        [self.view insertSubview:outgoing aboveSubview:_calendarPanel];
    }
    _calendarDisplayYear = nextComponents.year;
    _calendarDisplayMonth = nextComponents.month;
    _calendarSelectedDay = 0;
    _calendarRenderedDayKey = nil;
    [self updateCalendarPanel];
    [_calendarPanel layoutIfNeeded];
    UIView *incoming = reduceMotion ? nil : [_calendarPanel snapshotViewAfterScreenUpdates:YES];
    if (incoming && outgoing) {
        incoming.frame = calendarFrame;
        incoming.userInteractionEnabled = NO;
        [self.view insertSubview:incoming aboveSubview:outgoing];
        _calendarPanel.alpha = 0.0;
        _calendarMonthTransitioning = YES;
        NSTimeInterval duration = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 0.52 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 0.30 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 0.62 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 0.48 : 0.36)));
        CGFloat incomingScale = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 1.045 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 1.105 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 1.070 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 1.075 : 1.0)));
        CGFloat outgoingScale = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 1.025 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 1.070 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 1.020 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 1.035 : 1.0)));
        CGFloat incomingX = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 34.0 * direction : 0.0;
        CGFloat incomingY = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? -16.0 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 34.0 : 0.0);
        CGFloat outgoingX = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? -22.0 * direction : 0.0;
        CGFloat outgoingY = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 12.0 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? -22.0 : 0.0);
        if (_wallpaperTransitionStyle == IWWallpaperTransitionStyleSlide) {
            CGFloat dx = direction * calendarFrame.size.width;
            incoming.transform = CGAffineTransformMakeTranslation(dx, 0.0);
            [UIView animateWithDuration:0.26 delay:0.0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
                incoming.transform = CGAffineTransformIdentity;
                outgoing.transform = CGAffineTransformMakeTranslation(-dx, 0.0);
                outgoing.alpha = 0.0;
            } completion:^(__unused BOOL finished) {
                [outgoing removeFromSuperview];
                [incoming removeFromSuperview];
                _calendarPanel.alpha = 1.0;
                _calendarMonthTransitioning = NO;
            }];
        } else {
            incoming.alpha = 0.0;
            incoming.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(incomingScale, incomingScale), incomingX, incomingY);
            [UIView animateWithDuration:duration delay:0.0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
                incoming.alpha = 1.0;
                incoming.transform = CGAffineTransformIdentity;
                outgoing.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(outgoingScale, outgoingScale), outgoingX, outgoingY);
                outgoing.alpha = 0.0;
            } completion:^(__unused BOOL finished) {
                [outgoing removeFromSuperview];
                [incoming removeFromSuperview];
                _calendarPanel.alpha = 1.0;
                _calendarMonthTransitioning = NO;
            }];
        }
    } else {
        [outgoing removeFromSuperview];
    }
    [self appendTouchDebug:[NSString stringWithFormat:@"calendar-month %04ld-%02ld", (long)_calendarDisplayYear, (long)_calendarDisplayMonth]];
}

- (void)returnCalendarToToday:(UISwipeGestureRecognizer *)recognizer {
    if (_editMode || _calendarMonthTransitioning || recognizer.state != UIGestureRecognizerStateEnded) return;
    NSDateComponents *today = [IWDisplayCalendar() components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:[NSDate date]];
    NSInteger shownYear = _calendarDisplayYear ?: today.year;
    NSInteger shownMonth = _calendarDisplayMonth ?: today.month;
    if (shownYear == today.year && shownMonth == today.month &&
        _calendarDisplayYear == 0 && _calendarDisplayMonth == 0 && _calendarSelectedDay == 0) return;
    _calendarMonthTransitioning = YES;
    [UIView transitionWithView:_calendarPanel duration:0.26 options:(UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
        _calendarDisplayYear = 0;
        _calendarDisplayMonth = 0;
        _calendarSelectedDay = 0;
        _calendarRenderedDayKey = nil;
        [self updateCalendarPanel];
    } completion:^(__unused BOOL finished) {
        _calendarMonthTransitioning = NO;
    }];
    [self appendTouchDebug:@"calendar-return-today"];
}

- (void)showCalendarHolidayDetailForDay:(NSInteger)day year:(NSInteger)year month:(NSInteger)month {
    NSString *holiday = year == 2026 ? [IWHolidaysForLanguage2026(_dateLanguage) objectForKey:[NSString stringWithFormat:@"%ld-%ld", (long)month, (long)day]] : nil;
    // updateCalendarPanel owns the inline detail.  No detached toast and no
    // second write here, which would overwrite a festival-only name.
    _calendarHolidayToast.hidden = YES;
    [self appendTouchDebug:[NSString stringWithFormat:@"calendar-day %04ld-%02ld-%02ld %@", (long)year, (long)month, (long)day, holiday ?: @"none"]];
}

- (void)handleCalendarTap:(UITapGestureRecognizer *)recognizer {
    if (_editMode || recognizer.state != UIGestureRecognizerStateEnded) return;
    NSDate *now = [NSDate date];
    NSCalendar *calendar = IWDisplayCalendar();
    NSDateComponents *current = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:now];
    NSInteger year = _calendarDisplayYear ?: current.year;
    NSInteger month = _calendarDisplayMonth ?: current.month;
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.year = year; first.month = month; first.day = 1;
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:[calendar dateFromComponents:first]];
    NSInteger weekdayOffset = (weekday - IWCalendarFirstWeekdayForLanguage(_dateLanguage) + 7) % 7;
    NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:[calendar dateFromComponents:first]];
    CGPoint p = [recognizer locationInView:self.view];
    NSInteger i;
    for (i = 0; i < [_calendarDayLabels count]; i += 1) {
        UILabel *label = [_calendarDayLabels objectAtIndex:i];
        if (![self pointHitsView:label rootPoint:p]) continue;
        NSInteger day = i - weekdayOffset + 1;
        if (day < 1 || day > (NSInteger)days.length) return;
        _calendarSelectedDay = day;
        _calendarRenderedDayKey = nil;
        [self updateCalendarPanel];
        [self showCalendarHolidayDetailForDay:day year:year month:month];
        return;
    }
}

- (void)applyCalendarTransform {
    _calendarScale = MAX(IWCalendarScaleMin(), MIN(IWCalendarScaleMax(), _calendarScale));
    CGAffineTransform transform = CGAffineTransformMakeTranslation(_calendarOffsetX, _calendarOffsetY);
    _calendarPanel.transform = CGAffineTransformScale(transform, _calendarScale, _calendarScale);
}

- (void)applyWeatherTransform {
    _weatherScale = MAX(IWWeatherScaleMin(), MIN(IWWeatherScaleMax(), _weatherScale));
    CGAffineTransform transform = CGAffineTransformMakeTranslation(_weatherOffsetX, _weatherOffsetY);
    _weatherPanel.transform = CGAffineTransformScale(transform, _weatherScale, _weatherScale);
}

- (void)updateWeatherEditAppearance {
    UIColor *accent = _digitCardBorderColor ?: [self themedAccent];
    BOOL selected = _editMode && _editTarget == IWEditTargetWeather;
    _weatherPanel.layer.borderWidth = selected ? 3.0 : IWControlBorderWidth();
    _weatherPanel.layer.borderColor = [[accent colorWithAlphaComponent:(selected ? 0.98 : 0.62)] CGColor];
}

- (CGFloat)calendarPanelHeightForYear:(NSInteger)year month:(NSInteger)month {
    NSCalendar *calendar = IWDisplayCalendar();
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.year = year; first.month = month; first.day = 1;
    NSDate *firstDate = [calendar dateFromComponents:first] ?: [NSDate date];
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:firstDate];
    NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:firstDate];
    NSInteger offset = (weekday - IWCalendarFirstWeekdayForLanguage(_dateLanguage) + 7) % 7;
    NSInteger rows = (offset + (NSInteger)days.length + 6) / 7;
    BOOL hasHoliday = NO;
    if (year == 2026) {
        for (NSString *key in [IWHolidaysForLanguage2026(_dateLanguage) allKeys]) {
            if ([[key componentsSeparatedByString:@"-"] count] == 2 && [[[key componentsSeparatedByString:@"-"] objectAtIndex:0] integerValue] == month) { hasHoliday = YES; break; }
        }
    }
    CGFloat gridBottom = 64.0 + (rows - 1) * 22.0 + 20.0;
    return gridBottom + (hasHoliday ? 30.0 : 10.0);
}

- (void)updateCalendarPanel {
    if (!_calendarPanel) return;
    NSDate *now = [NSDate date];
    NSCalendar *calendar = IWDisplayCalendar();
    NSDateComponents *current = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:now];
    NSInteger shownYear = _calendarDisplayYear ?: current.year;
    NSInteger shownMonth = _calendarDisplayMonth ?: current.month;
    NSDateComponents *shownComponents = [[NSDateComponents alloc] init];
    shownComponents.year = shownYear; shownComponents.month = shownMonth; shownComponents.day = 1;
    NSDate *shownDate = [calendar dateFromComponents:shownComponents] ?: now;
    NSString *dayKey = [NSString stringWithFormat:@"%04ld-%02ld-%02ld-%ld-%04ld-%02ld-%ld", (long)current.year, (long)current.month, (long)current.day, (long)_dateLanguage, (long)shownYear, (long)shownMonth, (long)_calendarSelectedDay];
    UIColor *accent = _digitCardBorderColor ?: IWThemePink(1.0);
    if ([dayKey isEqualToString:_calendarRenderedDayKey] && [_calendarRenderedAccent isEqual:accent]) return;
    _calendarRenderedDayKey = [dayKey copy];
    _calendarRenderedAccent = accent;
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.year = shownYear; first.month = shownMonth; first.day = 1;
    NSDate *firstDate = [calendar dateFromComponents:first];
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:firstDate];
    NSInteger weekdayOffset = (weekday - IWCalendarFirstWeekdayForLanguage(_dateLanguage) + 7) % 7;
    NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:shownDate];
    NSDictionary *holidays = shownYear == 2026 ? IWHolidaysForLanguage2026(_dateLanguage) : @{};
    NSArray *months = @[@"JANUARY", @"FEBRUARY", @"MARCH", @"APRIL", @"MAY", @"JUNE", @"JULY", @"AUGUST", @"SEPTEMBER", @"OCTOBER", @"NOVEMBER", @"DECEMBER"];
    _calendarMonthLabel.text = _dateLanguage == 0 ? [NSString stringWithFormat:@"%@ %ld", [months objectAtIndex:MAX(0, MIN(11, shownMonth - 1))], (long)shownYear] : [NSString stringWithFormat:@"%ld年%ld月", (long)shownYear, (long)shownMonth];
    UIColor *dayText = [UIColor colorWithWhite:1.0 alpha:0.90];
    UIColor *muted = [UIColor colorWithWhite:1.0 alpha:0.54];
    _calendarPanel.layer.borderColor = [[accent colorWithAlphaComponent:0.82] CGColor];
    _calendarPanel.layer.shadowColor = [[accent colorWithAlphaComponent:0.48] CGColor];
    _calendarMonthLabel.textColor = accent;
    NSInteger i;
    NSArray *weekdayTitles = IWCalendarWeekdayTitlesForLanguage(_dateLanguage);
    for (i = 0; i < [_calendarWeekdayLabels count]; i += 1) {
        UILabel *weekdayLabel = [_calendarWeekdayLabels objectAtIndex:i];
        weekdayLabel.text = [weekdayTitles objectAtIndex:i];
        weekdayLabel.textColor = muted;
    }
    NSMutableArray *monthHolidayNames = [NSMutableArray array];
    for (i = 0; i < [_calendarDayLabels count]; i += 1) {
        UILabel *label = [_calendarDayLabels objectAtIndex:i];
        UIView *holidayDot = [_calendarHolidayDots objectAtIndex:i];
        NSInteger day = i - weekdayOffset + 1;
        BOOL valid = day >= 1 && day <= (NSInteger)days.length;
        label.text = valid ? [NSString stringWithFormat:@"%ld", (long)day] : @"";
        BOOL today = valid && shownYear == current.year && shownMonth == current.month && day == current.day;
        BOOL selected = valid && day == _calendarSelectedDay;
        // Today is the quiet outline reference; the actively selected date is
        // the strong filled state.  If both are the same date, selection wins.
        label.textColor = selected ? [UIColor whiteColor] : (today ? accent : dayText);
        label.backgroundColor = selected ? accent : [UIColor clearColor];
        label.layer.borderWidth = (today || selected) ? 1.25 : 0.0;
        label.layer.borderColor = [(today || selected ? [UIColor whiteColor] : accent) CGColor];
        NSString *holiday = valid ? [holidays objectForKey:[NSString stringWithFormat:@"%ld-%ld", (long)shownMonth, (long)day]] : nil;
        holidayDot.hidden = ![holiday length];
        if ([holiday length]) {
            holidayDot.backgroundColor = selected ? [UIColor whiteColor] : [accent colorWithAlphaComponent:0.96];
            [monthHolidayNames addObject:holiday];
        }
    }
    NSInteger calendarRows = (weekdayOffset + (NSInteger)days.length + 6) / 7;
    CGFloat summaryY = 64.0 + (calendarRows - 1) * 22.0 + 22.0;
    CGFloat panelHeight = [self calendarPanelHeightForYear:shownYear month:shownMonth];
    if (fabs(_calendarPanel.bounds.size.height - panelHeight) > 0.5) _calendarPanel.bounds = CGRectMake(0.0, 0.0, 252.0, panelHeight);
    _calendarHolidaySummaryLabel.frame = CGRectMake(21.0, summaryY, 215.0, 18.0);
    _calendarHolidaySummaryLabel.textAlignment = NSTextAlignmentLeft;
    _calendarHolidaySummaryLabel.hidden = [monthHolidayNames count] == 0 || summaryY + 18.0 > _calendarPanel.bounds.size.height - 4.0;
    if (!_calendarHolidaySummaryLabel.hidden) {
        NSString *summary = [monthHolidayNames componentsJoinedByString:@" · "];
        if (_calendarSelectedDay > 0) {
            NSString *selectedHoliday = [holidays objectForKey:[NSString stringWithFormat:@"%ld-%ld", (long)shownMonth, (long)_calendarSelectedDay]];
            NSString *none = _dateLanguage == 1 ? @"无节日" : (_dateLanguage == 2 ? @"無節日" : (_dateLanguage == 3 ? @"祝日なし" : @"No holiday"));
            if ([selectedHoliday length]) {
                summary = selectedHoliday;
            } else if (_dateLanguage == 0) {
                NSArray *shortMonths = @[@"JAN", @"FEB", @"MAR", @"APR", @"MAY", @"JUN", @"JUL", @"AUG", @"SEP", @"OCT", @"NOV", @"DEC"];
                summary = [NSString stringWithFormat:@"%@ %ld · %@", [shortMonths objectAtIndex:MAX(0, MIN(11, shownMonth - 1))], (long)_calendarSelectedDay, none];
            } else {
                summary = [NSString stringWithFormat:@"%ld月%ld日 · %@", (long)shownMonth, (long)_calendarSelectedDay, none];
            }
        }
        _calendarHolidaySummaryLabel.text = [NSString stringWithFormat:@"• %@", summary];
        _calendarHolidaySummaryLabel.textColor = [accent colorWithAlphaComponent:0.94];
    }
    [self applyCalendarTransform];
}

- (void)buildEditToolbar {
    _editToolbar = [[UIView alloc] initWithFrame:CGRectZero];
    _editToolbar.hidden = YES;
    _editToolbar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_editToolbar];

    _editResetButton = [self circleIconButton:IWButtonKindReset];
    [_editResetButton addTarget:self action:@selector(resetEditMode) forControlEvents:UIControlEventTouchUpInside];
    [_editToolbar addSubview:_editResetButton];

    _editCancelButton = [self circleIconButton:IWButtonKindClose];
    [_editCancelButton addTarget:self action:@selector(cancelEditMode) forControlEvents:UIControlEventTouchUpInside];
    [_editToolbar addSubview:_editCancelButton];

    _editDoneButton = [self circleIconButton:IWButtonKindCheck];
    _editDoneButton.backgroundColor = IWThemePink(0.72);
    [_editDoneButton addTarget:self action:@selector(finishEditMode) forControlEvents:UIControlEventTouchUpInside];
    [_editToolbar addSubview:_editDoneButton];

    _opacityControl = [[UIView alloc] initWithFrame:CGRectZero];
    _opacityControl.hidden = YES;
    _opacityControl.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    _opacityControl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_opacityControl];

    _opacitySlider = [[IWOpacitySlider alloc] initWithFrame:CGRectZero];
    _opacitySlider.accessibilityLabel = @"透明度";
    _opacitySlider.minimumValue = 0.2;
    _opacitySlider.maximumValue = 0.9;
    _opacitySlider.value = _digitCardOpacity;
    _opacitySlider.minimumTrackTintColor = IWThemePink(0.86);
    _opacitySlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.34];
    if ([_opacitySlider respondsToSelector:@selector(setThumbTintColor:)]) {
        _opacitySlider.thumbTintColor = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:1.0];
    }
    [_opacitySlider addTarget:self action:@selector(opacitySliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_opacityControl addSubview:_opacitySlider];

    _editControlsMoveButton = (IWIconButton *)[self circleIconButton:IWButtonKindMove];
    _editControlsMoveButton.accessibilityLabel = @"移动编辑控件";
    UIPanGestureRecognizer *editControlsPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEditControlsPan:)];
    [_editControlsMoveButton addGestureRecognizer:editControlsPan];
    _editControlsMoveButton.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:@"向左移动编辑控件" target:self selector:@selector(accessibilityMoveEditControlsLeft:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向右移动编辑控件" target:self selector:@selector(accessibilityMoveEditControlsRight:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向上移动编辑控件" target:self selector:@selector(accessibilityMoveEditControlsUp:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"向下移动编辑控件" target:self selector:@selector(accessibilityMoveEditControlsDown:)]
    ];
    [_opacityControl addSubview:_editControlsMoveButton];

    NSInteger i;

    _borderControl = [[UIView alloc] initWithFrame:CGRectZero];
    _borderControl.hidden = YES;
    _borderControl.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_borderControl];
    _borderThemeButtons = [NSMutableArray array];
    NSArray *themeColors = @[
        IWThemePink(1.0),
        [UIColor colorWithRed:1.0 green:0.70 blue:0.42 alpha:1.0],
        [UIColor colorWithRed:0.30 green:0.89 blue:0.89 alpha:1.0],
        [UIColor colorWithRed:0.08 green:0.07 blue:0.12 alpha:1.0],
        [UIColor colorWithWhite:0.96 alpha:1.0]
    ];
    NSArray *themeAccessibilityLabels = @[@"粉色边框", @"橙色边框", @"青色边框", @"深色边框", @"浅色边框"];
    for (i = 0; i < [themeColors count]; i += 1) {
        UIButton *themeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        themeButton.tag = 8100 + i;
        themeButton.accessibilityLabel = [themeAccessibilityLabels objectAtIndex:i];
        [themeButton setTitle:@"✓" forState:UIControlStateSelected];
        [themeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        themeButton.titleLabel.font = [UIFont boldSystemFontOfSize:25.0];
        themeButton.backgroundColor = [themeColors objectAtIndex:i];
        themeButton.layer.cornerRadius = IWControlRadius();
        themeButton.layer.borderWidth = IWControlBorderWidth();
        themeButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.82] CGColor];
        themeButton.layer.shadowColor = [[UIColor blackColor] CGColor];
        themeButton.layer.shadowOpacity = 0.22;
        themeButton.layer.shadowRadius = 3.0;
        themeButton.layer.shadowOffset = CGSizeMake(0.0, 1.0);
        [themeButton addTarget:self action:@selector(borderThemeSwatchTouchDown:) forControlEvents:UIControlEventTouchDown];
        [themeButton addTarget:self action:@selector(borderThemeSwatchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_borderControl addSubview:themeButton];
        [_borderThemeButtons addObject:themeButton];
    }
    _borderWidthSlider = [[IWOpacitySlider alloc] initWithFrame:CGRectZero];
    _borderWidthSlider.accessibilityLabel = @"边框宽度";
    _borderWidthSlider.minimumValue = 1.0;
    _borderWidthSlider.maximumValue = 6.0;
    _borderWidthSlider.minimumTrackTintColor = IWThemePink(0.92);
    _borderWidthSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.30];
    [_borderWidthSlider addTarget:self action:@selector(borderWidthSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_borderControl addSubview:_borderWidthSlider];
    _borderColorPalette = [[IWBorderColorPalette alloc] initWithFrame:CGRectZero];
    _borderColorPalette.layer.borderWidth = 2.0;
    _borderColorPalette.layer.borderColor = [IWThemePink(0.94) CGColor];
    [_borderColorPalette addTarget:self action:@selector(borderColorPaletteChanged:) forControlEvents:UIControlEventValueChanged];
    [_borderControl addSubview:_borderColorPalette];
}

- (void)animateEditToolbarDropIn {
    if (!_editToolbar || _editToolbar.hidden) return;
    NSArray *buttons = @[_editResetButton, _editCancelButton, _editDoneButton];
    NSInteger i;
    for (i = 0; i < [buttons count]; i += 1) {
        UIView *button = [buttons objectAtIndex:i];
        [button.layer removeAllAnimations];
        button.transform = CGAffineTransformMakeTranslation(0.0, -64.0);
        button.alpha = 0.0;
    }
    [UIView animateWithDuration:IWPanelAnimationDuration()
                          delay:0.0
         usingSpringWithDamping:IWPanelSpringDamping()
          initialSpringVelocity:0.85
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        NSInteger j;
        for (j = 0; j < [buttons count]; j += 1) {
            UIView *button = [buttons objectAtIndex:j];
            button.transform = CGAffineTransformIdentity;
            button.alpha = 1.0;
        }
    } completion:nil];
}

- (void)hideEditToolbarAnimated {
    if (!_editToolbar || _editToolbar.hidden) return;
    NSArray *buttons = @[_editResetButton, _editCancelButton, _editDoneButton];
    NSMutableArray *views = [buttons mutableCopy];
    if (!_opacityControl.hidden) [views addObject:_opacityControl];
    if (!_borderControl.hidden) [views addObject:_borderControl];
    [UIView animateWithDuration:IWPanelAnimationDuration()
                          delay:0.0
         usingSpringWithDamping:IWPanelSpringDamping()
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        NSInteger i;
        for (i = 0; i < [views count]; i += 1) {
            UIView *view = [views objectAtIndex:i];
            view.transform = CGAffineTransformMakeTranslation(0.0, -64.0);
            view.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        NSInteger i;
        for (i = 0; i < [views count]; i += 1) {
            UIView *view = [views objectAtIndex:i];
            view.transform = CGAffineTransformIdentity;
        }
        // A new editor can open before the previous drop-out animation's
        // completion runs (for example weather -> clock).  That stale
        // completion must not hide or reposition the new editor's controls.
        if (_editMode) return;
        _editToolbar.hidden = YES;
        _opacityControl.hidden = YES;
        _borderControl.hidden = YES;
        for (i = 0; i < [views count]; i += 1) {
            UIView *view = [views objectAtIndex:i];
            view.alpha = 1.0;
        }
    }];
}

- (void)resetEditToolbarButtonPresentation {
    NSArray *buttons = @[_editResetButton, _editCancelButton, _editDoneButton];
    NSInteger i;
    for (i = 0; i < [buttons count]; i += 1) {
        UIView *button = [buttons objectAtIndex:i];
        [button.layer removeAllAnimations];
        button.transform = CGAffineTransformIdentity;
        button.alpha = 1.0;
    }
}

- (void)opacitySliderChanged:(UISlider *)slider {
    CGFloat step = (0.9 - 0.2) / 7.0;
    CGFloat value = IWDigitCardClampOpacity(0.2 + round((slider.value - 0.2) / step) * step);
    if (_editMode && _editTarget == IWEditTargetCalendar) {
        _calendarOpacity = value;
        [self applyCalendarOpacity];
    } else {
        _digitCardOpacity = value;
        [self applyDigitCardOpacity];
    }
}

- (BOOL)moveEditControlsToOrigin:(CGPoint)origin persist:(BOOL)persist {
    if (!_editMode || (_editTarget != IWEditTargetClock &&
                       _editTarget != IWEditTargetDate &&
                       _editTarget != IWEditTargetCalendar)) return NO;
    CGFloat panelWidth = 262.0 + IWControlGap() + IWControlSize();
    CGFloat originX = MAX(0.0, MIN(self.view.bounds.size.width - panelWidth, origin.x));
    CGFloat originY = MAX(0.0, MIN(self.view.bounds.size.height - 242.0, origin.y));
    _editControlsOffsetX = originX - 20.0;
    _editControlsOffsetY = originY - 18.0;
    CGRect borderFrame = _borderControl.frame;
    borderFrame.origin = CGPointMake(originX, originY);
    _borderControl.frame = borderFrame;
    CGRect opacityFrame = _opacityControl.frame;
    opacityFrame.origin = CGPointMake(originX, _editTarget == IWEditTargetCalendar ? originY : originY + 184.0);
    _opacityControl.frame = opacityFrame;
    if (persist) [self saveState];
    return YES;
}

- (BOOL)accessibilityMoveEditControlsLeft:(UIAccessibilityCustomAction *)action {
    (void)action;
    CGPoint origin = CGPointMake(20.0 + _editControlsOffsetX - 16.0, 18.0 + _editControlsOffsetY);
    return [self moveEditControlsToOrigin:origin persist:YES];
}

- (BOOL)accessibilityMoveEditControlsRight:(UIAccessibilityCustomAction *)action {
    (void)action;
    CGPoint origin = CGPointMake(20.0 + _editControlsOffsetX + 16.0, 18.0 + _editControlsOffsetY);
    return [self moveEditControlsToOrigin:origin persist:YES];
}

- (BOOL)accessibilityMoveEditControlsUp:(UIAccessibilityCustomAction *)action {
    (void)action;
    CGPoint origin = CGPointMake(20.0 + _editControlsOffsetX, 18.0 + _editControlsOffsetY - 16.0);
    return [self moveEditControlsToOrigin:origin persist:YES];
}

- (BOOL)accessibilityMoveEditControlsDown:(UIAccessibilityCustomAction *)action {
    (void)action;
    CGPoint origin = CGPointMake(20.0 + _editControlsOffsetX, 18.0 + _editControlsOffsetY + 16.0);
    return [self moveEditControlsToOrigin:origin persist:YES];
}

- (void)handleEditControlsPan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _editControlsPanStart = CGPointMake(_editControlsOffsetX, _editControlsOffsetY);
    }
    CGPoint translation = [recognizer translationInView:self.view];
    CGPoint origin = CGPointMake(20.0 + _editControlsPanStart.x + translation.x,
                                 18.0 + _editControlsPanStart.y + translation.y);
    BOOL persist = recognizer.state == UIGestureRecognizerStateEnded ||
                   recognizer.state == UIGestureRecognizerStateCancelled ||
                   recognizer.state == UIGestureRecognizerStateFailed;
    [self moveEditControlsToOrigin:origin persist:persist];
}

- (void)borderThemeSwatchTouchDown:(UIButton *)button {
    IWFlashButtonPulse(button);
}

- (void)borderWidthSliderChanged:(UISlider *)slider {
    CGFloat step = (6.0 - 1.0) / 7.0;
    _digitCardBorderWidth = 1.0 + round((slider.value - 1.0) / step) * step;
    slider.value = _digitCardBorderWidth;
    [self applyDigitCardBorderStyle];
}

- (void)borderColorPaletteChanged:(IWBorderColorPalette *)palette {
    _digitCardBorderColor = palette.selectedColor;
    [self applyDigitCardBorderStyle];
}

- (void)borderThemeSwatchTapped:(UIButton *)button {
    _digitCardBorderColor = button.backgroundColor ?: IWThemePink(1.0);
    for (UIButton *themeButton in _borderThemeButtons) {
        themeButton.layer.borderWidth = themeButton == button ? 3.0 : IWControlBorderWidth();
        themeButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:(themeButton == button ? 1.0 : 0.82)] CGColor];
        themeButton.selected = themeButton == button;
        UIAccessibilityTraits traits = themeButton.accessibilityTraits;
        if (themeButton == button) traits |= UIAccessibilityTraitSelected;
        else traits &= ~UIAccessibilityTraitSelected;
        themeButton.accessibilityTraits = traits;
    }
    [self applyDigitCardBorderStyle];
}

- (UIButton *)circleIconButton:(IWButtonKind)kind {
    IWIconButton *button = [IWIconButton buttonWithType:UIButtonTypeCustom];
    button.kind = kind;
    button.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.68];
    button.layer.borderWidth = IWControlBorderWidth();
    button.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.68] CGColor];
    button.layer.cornerRadius = IWControlRadius();
    button.clipsToBounds = YES;
    return button;
}

- (void)buildWeatherPanel {
    UIColor *accent = _digitCardBorderColor ?: [self themedAccent];
    _weatherPanel = [[UIControl alloc] initWithFrame:CGRectZero];
    _weatherPanel.hidden = !_weatherVisible || _cleanMode;
    _weatherPanel.backgroundColor = [self themedButtonBackground];
    _weatherPanel.layer.borderWidth = IWControlBorderWidth();
    _weatherPanel.layer.borderColor = [[accent colorWithAlphaComponent:0.62] CGColor];
    _weatherPanel.layer.cornerRadius = 12.0;
    _weatherPanel.layer.shadowOpacity = 0.0;
    _weatherPanel.clipsToBounds = YES;
    // Cache the static, text-heavy panel so dragging translates one layer
    // instead of re-compositing its emoji and labels for every touch update.
    _weatherPanel.layer.shouldRasterize = YES;
    _weatherPanel.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    _weatherPanel.userInteractionEnabled = YES;
    [self.view addSubview:_weatherPanel];

    UILongPressGestureRecognizer *weatherLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleWeatherLongPress:)];
    weatherLongPress.delegate = self;
    weatherLongPress.minimumPressDuration = 0.55;
    weatherLongPress.cancelsTouchesInView = NO;
    [_weatherPanel addGestureRecognizer:weatherLongPress];
    UIPinchGestureRecognizer *weatherPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleWeatherPinch:)];
    weatherPinch.cancelsTouchesInView = NO;
    [_weatherPanel addGestureRecognizer:weatherPinch];
    [(UIControl *)_weatherPanel addTarget:self action:@selector(weatherTouchDown:forEvent:) forControlEvents:UIControlEventTouchDown];
    [(UIControl *)_weatherPanel addTarget:self action:@selector(weatherTouchDrag:forEvent:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
    [(UIControl *)_weatherPanel addTarget:self action:@selector(weatherTouchUp:forEvent:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _weatherGlyphLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 29.0, 52.0, 58.0)];
    _weatherGlyphLabel.text = @"☁️";
    _weatherGlyphLabel.textColor = [UIColor whiteColor];
    _weatherGlyphLabel.font = [UIFont fontWithName:@"AppleColorEmoji" size:42.0] ?: [UIFont systemFontOfSize:42.0];
    _weatherGlyphLabel.textAlignment = NSTextAlignmentCenter;
    _weatherGlyphLabel.adjustsFontSizeToFitWidth = YES;
    _weatherGlyphLabel.minimumScaleFactor = 0.82;
    [_weatherPanel addSubview:_weatherGlyphLabel];

    _weatherTemperatureLabel = [[UILabel alloc] initWithFrame:CGRectMake(72.0, 28.0, 88.0, 46.0)];
    _weatherTemperatureLabel.text = @"--°";
    _weatherTemperatureLabel.textColor = [UIColor whiteColor];
    _weatherTemperatureLabel.font = IWGTAFont(40.0);
    _weatherTemperatureLabel.adjustsFontSizeToFitWidth = YES;
    _weatherTemperatureLabel.minimumScaleFactor = 0.82;
    [_weatherPanel addSubview:_weatherTemperatureLabel];

    _weatherConditionLabel = [[UILabel alloc] initWithFrame:CGRectMake(164.0, 34.0, 140.0, 24.0)];
    _weatherConditionLabel.text = [self weatherTextEnglish:@"Waiting for weather" simplified:@"等待天气" traditional:@"等待天氣" japanese:@"天気を待機中"];
    _weatherConditionLabel.textColor = [UIColor whiteColor];
    _weatherConditionLabel.font = IWGTATextFont(16.0);
    _weatherConditionLabel.textAlignment = NSTextAlignmentRight;
    _weatherConditionLabel.adjustsFontSizeToFitWidth = YES;
    _weatherConditionLabel.minimumScaleFactor = 0.78;
    _weatherConditionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_weatherPanel addSubview:_weatherConditionLabel];

    _weatherRangeLabel = [[UILabel alloc] initWithFrame:CGRectMake(72.0, 75.0, 232.0, 18.0)];
    _weatherRangeLabel.text = @"--° — --°  ·  ☂ --%";
    _weatherRangeLabel.textColor = [accent colorWithAlphaComponent:0.92];
    _weatherRangeLabel.font = IWGTATextFont(13.0);
    _weatherRangeLabel.textAlignment = NSTextAlignmentRight;
    _weatherRangeLabel.adjustsFontSizeToFitWidth = YES;
    _weatherRangeLabel.minimumScaleFactor = 0.76;
    _weatherRangeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_weatherPanel addSubview:_weatherRangeLabel];

    _weatherCityLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 8.0, 168.0, 18.0)];
    _weatherCityLabel.text = [self weatherDisplayCityName];
    _weatherCityLabel.textColor = [accent colorWithAlphaComponent:0.98];
    _weatherCityLabel.font = IWGTATextFont(12.0);
    _weatherCityLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_weatherPanel addSubview:_weatherCityLabel];

    _weatherProviderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _weatherProviderButton.frame = CGRectMake(192.0, 0.0, 112.0, 44.0);
    _weatherProviderButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    _weatherProviderButton.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 10.0, 0);
    _weatherProviderButton.titleLabel.font = IWGTATextFont(12.0);
    [_weatherProviderButton setTitle:@"Open-Meteo" forState:UIControlStateNormal];
    [_weatherProviderButton setAttributedTitle:[[NSAttributedString alloc] initWithString:@"Open-Meteo" attributes:@{NSFontAttributeName: IWGTATextFont(12.0), NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.98], NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)}] forState:UIControlStateNormal];
    [_weatherProviderButton addTarget:self action:@selector(showWeatherAttribution) forControlEvents:UIControlEventTouchUpInside];
    _weatherProviderButton.hidden = YES;
    [_weatherPanel addSubview:_weatherProviderButton];

    if (_weatherSnapshot) [self applyWeatherSnapshot:_weatherSnapshot stale:YES];
}

- (void)handleWeatherLongPress:(UILongPressGestureRecognizer *)recognizer {
    [self appendTouchDebug:[NSString stringWithFormat:@"weather-control-longpress state=%ld", (long)recognizer.state]];
    if (recognizer.state != UIGestureRecognizerStateBegan || _editMode || (_videoOverlay && !_videoOverlay.hidden)) return;
    [self resetPullIndicator];
    [self enterWeatherEditMode];
    CGPoint p = [recognizer locationInView:self.view];
    [self prepareCurrentEditDragBaselineAtPoint:p];
    [self markSurfaceActionHandled:@"weather-control-longpress-edit"];
    [self writeDebugState:@"weather-control-longpress-edit"];
}

- (void)weatherTouchDown:(UIControl *)control forEvent:(UIEvent *)event {
    if (!_editMode || _editTarget != IWEditTargetWeather) return;
    // Match the calendar's drag-time cache policy: a 1x cache is cheaper to
    // translate while the finger is down, then returns to Retina at rest.
    control.layer.rasterizationScale = 1.0;
    UITouch *touch = [[event touchesForView:control] anyObject];
    if (touch) [self prepareCurrentEditDragBaselineAtPoint:[touch locationInView:self.view]];
}

- (void)weatherTouchDrag:(UIControl *)control forEvent:(UIEvent *)event {
    if (!_editMode || _editTarget != IWEditTargetWeather) return;
    NSSet *touches = [event touchesForView:control];
    if ([touches count] != 1) return;
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    CGPoint p = [touch locationInView:self.view];
    CGPoint delta = CGPointMake((p.x - _surfaceStart.x) * IWEditDragGain(), (p.y - _surfaceStart.y) * IWEditDragGain());
    _weatherOffsetX = _editStartX + delta.x;
    _weatherOffsetY = _editStartY + delta.y;
    [self applyWeatherTransform];
}

- (void)weatherTouchUp:(UIControl *)control forEvent:(UIEvent *)event {
    (void)event;
    control.layer.rasterizationScale = [[UIScreen mainScreen] scale];
    if (!_editMode || _editTarget != IWEditTargetWeather) return;
    [self persistCurrentEditValues];
    [self writeDebugState:@"weather-direct-drag-persist"];
}

- (void)handleWeatherPinch:(UIPinchGestureRecognizer *)recognizer {
    if (!_editMode || _editTarget != IWEditTargetWeather) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _editStartZoom = _weatherScale;
        [self appendTouchDebug:@"weather-panel-pinch-began"];
    }
    _weatherScale = MAX(IWWeatherScaleMin(), MIN(IWWeatherScaleMax(), _editStartZoom * recognizer.scale));
    [self applyWeatherTransform];
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self persistCurrentEditValues];
        [self writeDebugState:@"weather-panel-pinch-persist"];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        [self writeDebugState:@"weather-panel-pinch-cancel"];
    }
}

- (NSString *)weatherTextEnglish:(NSString *)english
                     simplified:(NSString *)simplified
                    traditional:(NSString *)traditional
                       japanese:(NSString *)japanese {
    if (_dateLanguage == 1) return simplified;
    if (_dateLanguage == 2) return traditional;
    if (_dateLanguage == 3) return japanese;
    return english;
}

- (NSString *)weatherDisplayCityName {
    NSString *name = [_weatherCity length] ? _weatherCity : [self weatherTextEnglish:@"Current location" simplified:@"当前位置" traditional:@"目前位置" japanese:@"現在地"];
    if (_dateLanguage != 1 && _dateLanguage != 2) return name;
    // Keep a recognisable place name, but omit generic administrative suffixes
    // such as 市、区、县 from the compact weather-card heading.
    NSArray *suffixes = @[@"特别行政区", @"特別行政區", @"自治区", @"自治區", @"自治州", @"地区", @"地區", @"市", @"区", @"區", @"县", @"縣"];
    for (NSString *suffix in suffixes) {
        if ([name hasSuffix:suffix] && !([suffix isEqualToString:@"区"] && [name hasSuffix:@"新区"]) && !([suffix isEqualToString:@"區"] && [name hasSuffix:@"新區"])) {
            NSString *trimmed = [name substringToIndex:[name length] - [suffix length]];
            if ([trimmed length]) return trimmed;
        }
    }
    return name;
}

- (NSString *)weatherConditionForCode:(NSInteger)code {
    if (code == 0) return [self weatherTextEnglish:@"Clear" simplified:@"晴" traditional:@"晴" japanese:@"晴れ"];
    if (code == 1) return [self weatherTextEnglish:@"Mostly clear" simplified:@"大致晴朗" traditional:@"大致晴朗" japanese:@"おおむね晴れ"];
    if (code == 2) return [self weatherTextEnglish:@"Partly cloudy" simplified:@"多云" traditional:@"多雲" japanese:@"晴れ時々くもり"];
    if (code == 3) return [self weatherTextEnglish:@"Overcast" simplified:@"阴" traditional:@"陰" japanese:@"くもり"];
    if (code == 45 || code == 48) return [self weatherTextEnglish:@"Fog" simplified:@"有雾" traditional:@"有霧" japanese:@"霧"];
    if (code >= 51 && code <= 57) return [self weatherTextEnglish:@"Drizzle" simplified:@"毛毛雨" traditional:@"毛毛雨" japanese:@"霧雨"];
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return [self weatherTextEnglish:@"Rain" simplified:@"有雨" traditional:@"有雨" japanese:@"雨"];
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return [self weatherTextEnglish:@"Snow" simplified:@"有雪" traditional:@"有雪" japanese:@"雪"];
    if (code >= 95) return [self weatherTextEnglish:@"Thunderstorm" simplified:@"雷暴" traditional:@"雷暴" japanese:@"雷雨"];
    return [self weatherTextEnglish:@"Changing" simplified:@"天气变化" traditional:@"天氣變化" japanese:@"変わりやすい"];
}

- (NSString *)weatherGlyphForCode:(NSInteger)code isDay:(BOOL)isDay {
    if (code == 0) return isDay ? @"☀️" : @"🌙";
    if (code == 1) return isDay ? @"🌤️" : @"☁️";
    if (code == 2) return @"⛅️";
    if (code == 3) return @"☁️";
    if (code == 45 || code == 48) return @"🌫️";
    if (code >= 51 && code <= 57) return @"🌦️";
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return @"🌨️";
    if (code >= 95) return @"⛈️";
    return @"🌧️";
}

- (void)applyWeatherSnapshot:(NSDictionary *)snapshot stale:(BOOL)stale {
    if (![snapshot isKindOfClass:[NSDictionary class]]) return;
    double temperature = [[snapshot objectForKey:@"temperature"] doubleValue];
    double high = [[snapshot objectForKey:@"high"] doubleValue];
    double low = [[snapshot objectForKey:@"low"] doubleValue];
    NSInteger rain = [[snapshot objectForKey:@"precipitationProbability"] integerValue];
    NSInteger code = [[snapshot objectForKey:@"code"] integerValue];
    BOOL isDay = [[snapshot objectForKey:@"isDay"] boolValue];
    _weatherGlyphLabel.text = [self weatherGlyphForCode:code isDay:isDay];
    _weatherTemperatureLabel.text = [NSString stringWithFormat:@"%.0f°", temperature];
    _weatherConditionLabel.text = [self weatherConditionForCode:code];
    _weatherRangeLabel.text = [NSString stringWithFormat:@"%.0f° — %.0f°  ·  ☂ %ld%%", low, high, (long)rain];
    _weatherCityLabel.text = [self weatherDisplayCityName];
    _weatherProviderButton.hidden = ![@"Open-Meteo" isEqual:[snapshot objectForKey:@"provider"]];
    _weatherProviderButton.accessibilityLabel = [self weatherTextEnglish:@"Weather data by Open-Meteo" simplified:@"天气数据：Open-Meteo" traditional:@"天氣資料：Open-Meteo" japanese:@"天気データ：Open-Meteo"];
    _weatherPanel.hidden = _cleanMode || !_weatherVisible;
}

- (void)showWeatherMessage:(NSString *)message {
    _weatherGlyphLabel.text = @"☁️";
    _weatherTemperatureLabel.text = @"--°";
    _weatherConditionLabel.text = [message length] ? message : [self weatherTextEnglish:@"Weather unavailable" simplified:@"天气不可用" traditional:@"天氣無法使用" japanese:@"天気を取得できません"];
    _weatherRangeLabel.text = [self weatherTextEnglish:@"Retry next hour" simplified:@"下个整点重试" traditional:@"下一個整點重試" japanese:@"次の正時に再試行"];
    _weatherCityLabel.text = [self weatherDisplayCityName];
    _weatherProviderButton.hidden = YES;
}

- (void)showWeatherAttribution {
    if (_weatherProviderButton.hidden || self.presentedViewController) return;
    NSString *title = [self weatherTextEnglish:@"Weather data" simplified:@"天气数据" traditional:@"天氣資料" japanese:@"天気データ"];
    NSString *message = [self weatherTextEnglish:@"Weather data by Open-Meteo, licensed under CC BY 4.0. Forecast display localized and condensed by Wizard." simplified:@"天气数据由 Open-Meteo 提供，按 CC BY 4.0 许可使用。Wizard 对预报进行了本地化和简化显示。" traditional:@"天氣資料由 Open-Meteo 提供，依 CC BY 4.0 授權使用。Wizard 將預報本地化並精簡顯示。" japanese:@"天気データは Open-Meteo 提供、CC BY 4.0 ライセンス。Wizard が予報を翻訳し、表示を要約しています。"];
    UIAlertController *detail = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [detail addAction:[UIAlertAction actionWithTitle:@"Open-Meteo.com" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://open-meteo.com/"]];
    }]];
    [detail addAction:[UIAlertAction actionWithTitle:@"CC BY 4.0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://creativecommons.org/licenses/by/4.0/"]];
    }]];
    [detail addAction:[UIAlertAction actionWithTitle:[self weatherTextEnglish:@"Close" simplified:@"关闭" traditional:@"關閉" japanese:@"閉じる"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:detail animated:YES completion:nil];
}

- (void)runWeatherCreditAudit {
    if (_weatherCreditAuditRunning || _weatherVisible || _weatherLoading || _cleanMode || _editMode ||
        self.presentedViewController || _videoCurrentURL) return;
    _weatherCreditAuditRunning = YES;
    NSString *priorCity = _weatherCity;
    BOOL priorHidden = _weatherPanel.hidden, priorCreditHidden = _weatherProviderButton.hidden;
    NSArray *labels = @[_weatherGlyphLabel, _weatherTemperatureLabel, _weatherConditionLabel, _weatherRangeLabel, _weatherCityLabel];
    NSMutableArray *priorText = [NSMutableArray array];
    for (UILabel *label in labels) [priorText addObject:label.text ?: @""];
    _weatherVisible = YES;
    _weatherCity = [self weatherTextEnglish:@"Preview" simplified:@"预览" traditional:@"預覽" japanese:@"プレビュー"];
    NSDictionary *fixture = @{@"temperature": @21, @"high": @24, @"low": @18, @"precipitationProbability": @20, @"code": @1, @"isDay": @YES, @"provider": @"Open-Meteo"};
    NSMutableDictionary *report = [@{@"sourceFingerprint": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WizardSourceFingerprint"] ?: @"", @"syntheticFixture": @YES} mutableCopy];
    [self applyWeatherSnapshot:fixture stale:NO];
    report[@"freshCreditVisible"] = @(!_weatherProviderButton.hidden);
    NSMutableDictionary *other = [fixture mutableCopy];
    other[@"provider"] = @"Other provider";
    [self applyWeatherSnapshot:other stale:NO];
    report[@"otherProviderCreditHidden"] = @(_weatherProviderButton.hidden);
    other[@"provider"] = [NSNull null];
    [self applyWeatherSnapshot:other stale:NO];
    report[@"malformedProviderCreditHidden"] = @(_weatherProviderButton.hidden);
    [self showWeatherMessage:@"Preview"];
    report[@"noDataCreditHidden"] = @(_weatherProviderButton.hidden);
    [self applyWeatherSnapshot:fixture stale:YES];
    report[@"staleCreditVisible"] = @(!_weatherProviderButton.hidden);
    report[@"cityDoesNotOverlapCredit"] = @(CGRectGetMaxX(_weatherCityLabel.frame) <= CGRectGetMinX(_weatherProviderButton.frame));
    report[@"creditTargetAtLeast44Points"] = @(_weatherProviderButton.bounds.size.width >= 44 && _weatherProviderButton.bounds.size.height >= 44);
    report[@"creditActionConnected"] = @([[_weatherProviderButton actionsForTarget:self forControlEvent:UIControlEventTouchUpInside] containsObject:@"showWeatherAttribution"]);
    NSString *temporary = NSTemporaryDirectory();
    [self captureDebugScreenshotToPath:[temporary stringByAppendingPathComponent:@"wizardsystem-weather-credit-card.png"] afterDelay:0.35];
    __block UIAlertController *ownedDetail = nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showWeatherAttribution];
        if ([self.presentedViewController isKindOfClass:[UIAlertController class]]) ownedDetail = (UIAlertController *)self.presentedViewController;
        report[@"detailPresented"] = @(ownedDetail != nil);
        report[@"detailTitle"] = ownedDetail.title ?: @"";
        NSMutableArray *actions = [NSMutableArray array];
        for (UIAlertAction *action in ownedDetail.actions) [actions addObject:action.title ?: @""];
        report[@"detailActions"] = actions;
        [self captureDebugScreenshotToPath:[temporary stringByAppendingPathComponent:@"wizardsystem-weather-credit-detail.png"] afterDelay:0.45];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ownedDetail && self.presentedViewController == ownedDetail) [self dismissViewControllerAnimated:NO completion:nil];
        _weatherCity = priorCity;
        _weatherVisible = NO;
        _weatherPanel.hidden = priorHidden;
        _weatherProviderButton.hidden = priorCreditHidden;
        for (NSUInteger i = 0; i < labels.count; i++) ((UILabel *)labels[i]).text = priorText[i];
        _weatherCreditAuditRunning = NO;
        report[@"weatherHiddenRestored"] = @(_weatherPanel.hidden == priorHidden && !_weatherVisible);
        report[@"applicationState"] = @([UIApplication sharedApplication].applicationState);
        report[@"completedAtEpoch"] = @([[NSDate date] timeIntervalSince1970]);
        [[NSJSONSerialization dataWithJSONObject:report options:0 error:nil] writeToFile:[temporary stringByAppendingPathComponent:@"wizardsystem-weather-credit-audit.json"] options:NSDataWritingAtomic error:nil];
    });
}

- (void)scheduleNextWeatherRefresh {
    [_weatherRefreshTimer invalidate];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour) fromDate:[NSDate date]];
    NSDate *thisHour = [calendar dateFromComponents:components];
    NSDate *nextHour = [calendar dateByAddingUnit:NSCalendarUnitHour value:1 toDate:thisHour options:0];
    NSTimeInterval delay = MAX(1.0, [nextHour timeIntervalSinceNow]);
    _weatherRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(weatherRefreshTimerFired:) userInfo:nil repeats:NO];
}

- (void)refreshWeatherLanguagePresentation {
    if (_weatherSnapshot) {
        NSDate *fetchedAt = [_weatherSnapshot objectForKey:@"fetchedAt"];
        BOOL stale = ![fetchedAt isKindOfClass:[NSDate class]] || -[fetchedAt timeIntervalSinceNow] > 3600.0;
        [self applyWeatherSnapshot:_weatherSnapshot stale:stale];
    } else {
        _weatherCityLabel.text = [self weatherDisplayCityName];
    }
}

- (void)startWeatherUpdates {
    if (!_weatherVisible) return;
    _weatherPanel.hidden = _cleanMode;
    if (_weatherSnapshot) {
        NSDate *fetchedAt = [_weatherSnapshot objectForKey:@"fetchedAt"];
        BOOL stale = ![fetchedAt isKindOfClass:[NSDate class]] || -[fetchedAt timeIntervalSinceNow] > 3600.0;
        [self applyWeatherSnapshot:_weatherSnapshot stale:stale];
    } else {
        [self showWeatherMessage:[self weatherTextEnglish:@"Locating" simplified:@"正在定位" traditional:@"正在定位" japanese:@"位置情報を取得中"]];
    }
    [self scheduleNextWeatherRefresh];
    [self requestWeatherLocation];
}

- (void)stopWeatherUpdates {
    [_weatherRefreshTimer invalidate];
    _weatherRefreshTimer = nil;
    [_weatherLocationManager stopUpdatingLocation];
    [_weatherGeocoder cancelGeocode];
    _weatherLoading = NO;
}

- (void)weatherRefreshTimerFired:(NSTimer *)timer {
    (void)timer;
    [self requestWeatherLocation];
    [self scheduleNextWeatherRefresh];
}

- (void)requestWeatherLocation {
    if (!_weatherVisible || _weatherLoading) return;
    if (![CLLocationManager locationServicesEnabled]) {
        NSNumber *latitude = [_weatherSnapshot objectForKey:@"latitude"];
        NSNumber *longitude = [_weatherSnapshot objectForKey:@"longitude"];
        if (latitude && longitude) [self fetchWeatherForLatitude:[latitude doubleValue] longitude:[longitude doubleValue]];
        else { _weatherError = YES; [self showWeatherMessage:[self weatherTextEnglish:@"Location is off" simplified:@"定位未开启" traditional:@"定位未開啟" japanese:@"位置情報がオフです"]]; }
        return;
    }
    if (!_weatherLocationManager) {
        _weatherLocationManager = [[CLLocationManager alloc] init];
        _weatherLocationManager.delegate = self;
        _weatherLocationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
        _weatherLocationManager.distanceFilter = 5000.0;
    }
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self showWeatherMessage:[self weatherTextEnglish:@"Allow location access" simplified:@"请允许定位" traditional:@"請允許定位" japanese:@"位置情報を許可してください"]];
        [_weatherLocationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        NSNumber *latitude = [_weatherSnapshot objectForKey:@"latitude"];
        NSNumber *longitude = [_weatherSnapshot objectForKey:@"longitude"];
        if (latitude && longitude) [self fetchWeatherForLatitude:[latitude doubleValue] longitude:[longitude doubleValue]];
        else { _weatherError = YES; [self showWeatherMessage:[self weatherTextEnglish:@"Location permission required" simplified:@"需要定位权限" traditional:@"需要定位權限" japanese:@"位置情報の許可が必要です"]]; }
    } else {
        [self showWeatherMessage:[self weatherTextEnglish:@"Updating" simplified:@"正在更新" traditional:@"正在更新" japanese:@"更新中"]];
        [_weatherLocationManager requestLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [manager requestLocation];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        _weatherError = YES;
        [self showWeatherMessage:[self weatherTextEnglish:@"Location permission required" simplified:@"需要定位权限" traditional:@"需要定位權限" japanese:@"位置情報の許可が必要です"]];
        [self updateMenuButtons];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = [locations lastObject];
    if (!location) return;
    [manager stopUpdatingLocation];
    [self reverseGeocodeWeatherLocation:location];
    [self fetchWeatherForLatitude:location.coordinate.latitude longitude:location.coordinate.longitude];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager; (void)error;
    NSNumber *latitude = [_weatherSnapshot objectForKey:@"latitude"];
    NSNumber *longitude = [_weatherSnapshot objectForKey:@"longitude"];
    if (latitude && longitude) [self fetchWeatherForLatitude:[latitude doubleValue] longitude:[longitude doubleValue]];
    else {
        _weatherError = YES;
        [self showWeatherMessage:[self weatherTextEnglish:@"Location failed" simplified:@"定位失败" traditional:@"定位失敗" japanese:@"位置情報を取得できません"]];
        [self updateMenuButtons];
    }
}

- (void)reverseGeocodeWeatherLocation:(CLLocation *)location {
    if (!location) return;
    [_weatherGeocoder cancelGeocode];
    _weatherGeocoder = [[CLGeocoder alloc] init];
    __weak IWRootViewController *weakSelf = self;
    [_weatherGeocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        (void)error;
        CLPlacemark *placemark = [placemarks firstObject];
        NSString *city = placemark.locality ?: placemark.subAdministrativeArea ?: placemark.administrativeArea;
        if (![city length]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            IWRootViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_weatherCity = city;
            strongSelf->_weatherCityLabel.text = [strongSelf weatherDisplayCityName];
            [strongSelf saveState];
        });
    }];
}

- (void)fetchWeatherForLatitude:(double)latitude longitude:(double)longitude {
    if (_weatherLoading) return;
    _weatherLoading = YES;
    _weatherError = NO;
    if (!_weatherService) _weatherService = [[IWWeatherService alloc] init];
    __weak IWRootViewController *weakSelf = self;
    [_weatherService fetchWeatherForLatitude:latitude longitude:longitude completion:^(NSDictionary *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            IWRootViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_weatherLoading = NO;
            if (snapshot) {
                strongSelf->_weatherSnapshot = snapshot;
                strongSelf->_weatherError = NO;
                [strongSelf applyWeatherSnapshot:snapshot stale:NO];
                [strongSelf saveState];
            } else {
                strongSelf->_weatherError = YES;
                if (strongSelf->_weatherSnapshot) [strongSelf applyWeatherSnapshot:strongSelf->_weatherSnapshot stale:YES];
                else [strongSelf showWeatherMessage:[strongSelf weatherTextEnglish:@"Weather unavailable" simplified:@"天气不可用" traditional:@"天氣無法使用" japanese:@"天気を取得できません"]];
            }
            [strongSelf writeWeatherDebugResult:error];
            [strongSelf updateMenuButtons];
            [strongSelf writeDebugState:@"weather-update"];
            if (IW_WEATHER_DIAGNOSTICS ||
                ([[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-debug")] &&
                 [[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-demo")])) {
                [strongSelf captureDebugScreenshotToPath:IWWeatherDebugPath(@"wizard-weather-screenshot.png") afterDelay:0.8];
            }
        });
    }];
}

- (void)writeWeatherDebugResult:(NSError *)error {
    if (!IW_WEATHER_DIAGNOSTICS && ![[NSFileManager defaultManager] fileExistsAtPath:IWWeatherDebugPath(@"wizard-weather-debug")]) return;
    NSDictionary *result = @{
        @"visible": [NSNumber numberWithBool:_weatherVisible],
        @"loading": [NSNumber numberWithBool:_weatherLoading],
        @"error": error.localizedDescription ?: @"",
        @"city": _weatherCity ?: @"",
        @"temperature": [_weatherSnapshot objectForKey:@"temperature"] ?: @0,
        @"high": [_weatherSnapshot objectForKey:@"high"] ?: @0,
        @"low": [_weatherSnapshot objectForKey:@"low"] ?: @0,
        @"precipitationProbability": [_weatherSnapshot objectForKey:@"precipitationProbability"] ?: @0,
        @"code": [_weatherSnapshot objectForKey:@"code"] ?: @0,
        @"provider": [_weatherSnapshot objectForKey:@"provider"] ?: @"",
        @"scale": [NSNumber numberWithFloat:_weatherScale],
        @"offsetX": [NSNumber numberWithFloat:_weatherOffsetX],
        @"offsetY": [NSNumber numberWithFloat:_weatherOffsetY],
        @"editTarget": [NSNumber numberWithInteger:_editTarget]
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (data) [data writeToFile:IWWeatherDebugPath(@"wizard-weather.json") atomically:YES];
}

- (void)loadWeatherDemo {
    _weatherVisible = YES;
    _weatherCity = @"上海（测试）";
    _weatherPanel.hidden = _cleanMode;
    [self showWeatherMessage:[self weatherTextEnglish:@"Updating" simplified:@"正在更新" traditional:@"正在更新" japanese:@"更新中"]];
    [self fetchWeatherForLatitude:31.2304 longitude:121.4737];
    [self saveState];
    [self updateMenuButtons];
}

- (void)buildHomePanel {
    _homePanel = [[UIView alloc] initWithFrame:CGRectZero];
    _homePanel.hidden = YES;
    _homePanel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_homePanel];

    _homeUpdatedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _homeUpdatedLabel.text = @"等待接入 Home Assistant";
    _homeUpdatedLabel.textColor = [UIColor colorWithWhite:1 alpha:0.84];
    _homeUpdatedLabel.font = IWGTATextFont(13.0);
    _homeUpdatedLabel.textAlignment = NSTextAlignmentRight;
    [_homePanel addSubview:_homeUpdatedLabel];

    _homeCards = [NSMutableArray array];
    NSArray *labels = @[@"客厅", @"卧室", @"空气"];
    NSInteger i;
    for (i = 0; i < [labels count]; i += 1) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.backgroundColor = [UIColor colorWithRed:18.0/255.0 green:13.0/255.0 blue:38.0/255.0 alpha:0.5];
        card.layer.borderWidth = 1.0;
        card.layer.borderColor = [[UIColor colorWithRed:78.0/255.0 green:232.0/255.0 blue:232.0/255.0 alpha:0.34] CGColor];
        card.layer.cornerRadius = 8.0;
        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, 120, 20)];
        name.tag = 1;
        name.text = [labels objectAtIndex:i];
        name.textColor = [UIColor colorWithWhite:1 alpha:0.78];
        name.font = IWGTATextFont(12.0);
        [card addSubview:name];
        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(15, 30, 100, 32)];
        value.tag = 2;
        value.text = @"--";
        value.textColor = [UIColor whiteColor];
        value.font = IWGTAFont(27.0);
        [card addSubview:value];
        UILabel *meta = [[UILabel alloc] initWithFrame:CGRectMake(110, 37, 80, 22)];
        meta.tag = 3;
        meta.text = i == 2 ? @"PM2.5" : @"--%";
        meta.textColor = [UIColor colorWithRed:1.0 green:145.0/255.0 blue:198.0/255.0 alpha:0.9];
        meta.font = IWGTATextFont(16.0);
        [card addSubview:meta];
        [_homePanel addSubview:card];
        [_homeCards addObject:card];
    }
    [self loadHomeStatus];
}

- (void)buildVideoOverlay {
    _videoOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _videoOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _videoOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.86];
    _videoOverlay.hidden = YES;
    _videoControlsVisible = YES;
    [self.view addSubview:_videoOverlay];

    UIView *playerView = [[UIView alloc] initWithFrame:CGRectZero];
    playerView.tag = 501;
    playerView.backgroundColor = [UIColor blackColor];
    [_videoOverlay addSubview:playerView];

    _videoTapShield = [[UIControl alloc] initWithFrame:CGRectZero];
    _videoTapShield.backgroundColor = [UIColor clearColor];
    _videoTapShield.userInteractionEnabled = YES;
    [(UIControl *)_videoTapShield addTarget:self action:@selector(videoTapShieldPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_videoOverlay addSubview:_videoTapShield];

    IWIconButton *close = [self actionButton:IWButtonKindClose];
    close.tag = 502;
    [close addTarget:self action:@selector(closeVideo) forControlEvents:UIControlEventTouchUpInside];
    [_videoOverlay addSubview:close];

    IWIconButton *minimize = [self actionButton:IWButtonKindDown];
    minimize.accessibilityLabel = @"最小化视频";
    minimize.tag = 503;
    [minimize addTarget:self action:@selector(minimizeVideo) forControlEvents:UIControlEventTouchUpInside];
    [_videoOverlay addSubview:minimize];

    _videoControls = [[UIView alloc] initWithFrame:CGRectZero];
    _videoControls.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.42];
    _videoControls.layer.borderWidth = IWControlBorderWidth();
    _videoControls.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.22] CGColor];
    _videoControls.layer.cornerRadius = 8.0;
    [_videoOverlay addSubview:_videoControls];

    _airPlayView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    _airPlayView.showsVolumeSlider = NO;
    _airPlayView.showsRouteButton = YES;
    _airPlayView.tintColor = [UIColor whiteColor];
    _airPlayView.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
    _airPlayView.layer.borderWidth = IWControlBorderWidth();
    _airPlayView.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.62] CGColor];
    _airPlayView.layer.cornerRadius = IWControlRadius();
    _airPlayView.clipsToBounds = YES;
    [_videoControls addSubview:_airPlayView];

    _videoVolumeButton = [self actionButton:IWButtonKindVolume];
    [_videoVolumeButton addTarget:self action:@selector(videoVolumeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_videoControls addSubview:_videoVolumeButton];

    _volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    _volumeView.showsVolumeSlider = YES;
    _volumeView.showsRouteButton = NO;
    _volumeView.alpha = 0.0;
    _volumeView.userInteractionEnabled = NO;
    [_videoOverlay addSubview:_volumeView];

    _volumePanel = [[UIView alloc] initWithFrame:CGRectZero];
    _volumePanel.hidden = YES;
    _volumePanel.alpha = 0.0;
    _volumePanel.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.76];
    _volumePanel.layer.cornerRadius = 8.0;
    _volumePanel.layer.borderWidth = IWControlBorderWidth();
    _volumePanel.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.28] CGColor];
    _volumePanel.clipsToBounds = YES;
    [_videoOverlay addSubview:_volumePanel];

    _volumeSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _volumeSlider.accessibilityLabel = @"视频音量";
    _volumeSlider.minimumValue = 0.0;
    _volumeSlider.maximumValue = 1.0;
    _volumeSlider.minimumTrackTintColor = IWThemePink(1.0);
    _volumeSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    if ([_volumeSlider respondsToSelector:@selector(setThumbTintColor:)]) {
        _volumeSlider.thumbTintColor = IWThemePink(1.0);
    }
    [_volumeSlider addTarget:self action:@selector(volumeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_volumePanel addSubview:_volumeSlider];

    _videoRewindButton = [self actionButton:IWButtonKindRewind];
    [_videoRewindButton addTarget:self action:@selector(videoRewindTapped) forControlEvents:UIControlEventTouchUpInside];
    [_videoControls addSubview:_videoRewindButton];

    _videoPlayButton = [self actionButton:IWButtonKindPause];
    [_videoPlayButton addTarget:self action:@selector(videoPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [_videoControls addSubview:_videoPlayButton];

    _videoForwardButton = [self actionButton:IWButtonKindForward];
    [_videoForwardButton addTarget:self action:@selector(videoForwardTapped) forControlEvents:UIControlEventTouchUpInside];
    [_videoControls addSubview:_videoForwardButton];

    _videoSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _videoSlider.accessibilityLabel = @"播放进度";
    _videoSlider.minimumValue = 0.0;
    _videoSlider.maximumValue = 1.0;
    _videoSlider.minimumTrackTintColor = IWThemePink(0.92);
    _videoSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.26];
    if ([_videoSlider respondsToSelector:@selector(setThumbTintColor:)]) {
        _videoSlider.thumbTintColor = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:1.0];
    }
    [_videoSlider addTarget:self action:@selector(videoSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_videoSlider addTarget:self action:@selector(videoSliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
    [_videoSlider addTarget:self action:@selector(videoSliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_videoControls addSubview:_videoSlider];

    _videoCurrentLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _videoCurrentLabel.text = @"0:00";
    _videoCurrentLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    _videoCurrentLabel.font = IWGTATextFont(12.0);
    _videoCurrentLabel.textAlignment = NSTextAlignmentCenter;
    [_videoControls addSubview:_videoCurrentLabel];

    _videoDurationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _videoDurationLabel.text = @"0:00";
    _videoDurationLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    _videoDurationLabel.font = IWGTATextFont(12.0);
    _videoDurationLabel.textAlignment = NSTextAlignmentCenter;
    [_videoControls addSubview:_videoDurationLabel];

    _moviePlayer = [[MPMoviePlayerController alloc] init];
    _moviePlayer.controlStyle = MPMovieControlStyleNone;
    _moviePlayer.shouldAutoplay = NO;
    _moviePlayer.scalingMode = MPMovieScalingModeAspectFit;
    _moviePlayer.allowsAirPlay = YES;
    _moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [playerView addSubview:_moviePlayer.view];
    _remoteVideoLayer = [AVPlayerLayer playerLayerWithPlayer:nil];
    _remoteVideoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    _remoteVideoLayer.frame = playerView.bounds;
    _remoteVideoLayer.hidden = YES;
    [playerView.layer addSublayer:_remoteVideoLayer];
    UITapGestureRecognizer *playerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(videoOverlayTapped:)];
    playerTap.cancelsTouchesInView = NO;
    [playerView addGestureRecognizer:playerTap];
    UITapGestureRecognizer *movieTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(videoOverlayTapped:)];
    movieTap.cancelsTouchesInView = NO;
    [_moviePlayer.view addGestureRecognizer:movieTap];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:) name:MPMoviePlayerPlaybackDidFinishNotification object:_moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoAccessibilityStatusChanged:) name:UIAccessibilityVoiceOverStatusChanged object:nil];
}

- (void)buildPowerSleepOverlay {
    _powerSleepOverlay = [[UIControl alloc] initWithFrame:self.view.bounds];
    _powerSleepOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _powerSleepOverlay.backgroundColor = [UIColor blackColor];
    _powerSleepOverlay.hidden = YES;
    _powerSleepOverlay.userInteractionEnabled = YES;
    [(UIControl *)_powerSleepOverlay addTarget:self action:@selector(powerSleepOverlayTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_powerSleepOverlay];
}

- (IWIconButton *)actionButton:(IWButtonKind)kind {
    IWIconButton *b = [IWIconButton buttonWithType:UIButtonTypeCustom];
    b.kind = kind;
    b.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
    b.layer.borderWidth = IWControlBorderWidth();
    b.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.62] CGColor];
    b.layer.cornerRadius = IWControlRadius();
    b.clipsToBounds = YES;
    return b;
}

- (NSString *)currentThemeClass {
    if (_wallpaperIndex < 0 || _wallpaperIndex >= [_wallpapers count]) return @"theme-sunset";
    NSString *theme = [[_wallpapers objectAtIndex:_wallpaperIndex] objectForKey:@"themeClass"];
    return [theme length] ? theme : @"theme-sunset";
}

- (BOOL)isDriveTheme { return [[self currentThemeClass] isEqualToString:@"theme-drive"]; }
- (BOOL)isMarinaTheme { return [[self currentThemeClass] isEqualToString:@"theme-marina"]; }

- (UIColor *)dominantAccentColorForImage:(UIImage *)image {
    if (!image) return nil;
    NSInteger sampleSize = 18;
    unsigned char *data = calloc(sampleSize * sampleSize * 4, sizeof(unsigned char));
    if (!data) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(data, sampleSize, sampleSize, 8, sampleSize * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!c) {
        free(data);
        return nil;
    }
    CGContextClearRect(c, CGRectMake(0, 0, sampleSize, sampleSize));
    CGContextDrawImage(c, CGRectMake(0, 0, sampleSize, sampleSize), image.CGImage);
    CGFloat red = 0.0, green = 0.0, blue = 0.0, total = 0.0;
    NSInteger i;
    for (i = 0; i < sampleSize * sampleSize; i += 1) {
        CGFloat r = data[i * 4] / 255.0;
        CGFloat g = data[i * 4 + 1] / 255.0;
        CGFloat b = data[i * 4 + 2] / 255.0;
        CGFloat maxV = MAX(r, MAX(g, b));
        CGFloat minV = MIN(r, MIN(g, b));
        CGFloat sat = maxV <= 0.001 ? 0.0 : (maxV - minV) / maxV;
        CGFloat bright = maxV;
        if (bright < 0.24 || bright > 0.96 || sat < 0.18) continue;
        CGFloat weight = sat * sat * (0.35 + bright);
        red += r * weight;
        green += g * weight;
        blue += b * weight;
        total += weight;
    }
    CGContextRelease(c);
    free(data);
    if (total <= 0.001) return nil;
    red /= total;
    green /= total;
    blue /= total;
    CGFloat maxV = MAX(red, MAX(green, blue));
    if (maxV < 0.72) {
        CGFloat boost = 0.72 / MAX(0.01, maxV);
        red = MIN(1.0, red * boost);
        green = MIN(1.0, green * boost);
        blue = MIN(1.0, blue * boost);
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0];
}

- (UIColor *)themedDigitBackground {
    if ([self isMarinaTheme]) return [UIColor colorWithRed:233.0/255.0 green:251.0/255.0 blue:246.0/255.0 alpha:0.56];
    if ([self isDriveTheme]) return [UIColor colorWithRed:1.0 green:240.0/255.0 blue:221.0/255.0 alpha:0.56];
    return [UIColor colorWithRed:1.0 green:243.0/255.0 blue:243.0/255.0 alpha:0.56];
}

- (UIColor *)themedDigitText {
    if ([self isMarinaTheme]) return [UIColor colorWithRed:14.0/255.0 green:35.0/255.0 blue:53.0/255.0 alpha:1.0];
    if ([self isDriveTheme]) return [UIColor colorWithRed:23.0/255.0 green:17.0/255.0 blue:27.0/255.0 alpha:1.0];
    return [UIColor colorWithRed:20.0/255.0 green:18.0/255.0 blue:31.0/255.0 alpha:1.0];
}

- (UIColor *)themedDigitBorder {
    return IWThemePink(0.88);
}

- (UIColor *)themedAccent {
    if (_wallpaperAccentColor) return [_wallpaperAccentColor colorWithAlphaComponent:0.95];
    if ([self isMarinaTheme]) return [UIColor colorWithRed:42.0/255.0 green:191.0/255.0 blue:198.0/255.0 alpha:0.9];
    if ([self isDriveTheme]) return [UIColor colorWithRed:1.0 green:126.0/255.0 blue:80.0/255.0 alpha:0.9];
    return IWThemePink(0.9);
}

- (UIColor *)themedButtonBackground {
    if ([self isMarinaTheme]) return [UIColor colorWithRed:8.0/255.0 green:30.0/255.0 blue:47.0/255.0 alpha:0.50];
    if ([self isDriveTheme]) return [UIColor colorWithRed:45.0/255.0 green:18.0/255.0 blue:41.0/255.0 alpha:0.50];
    return [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
}

- (UIColor *)themedButtonBorder {
    if ([self isMarinaTheme]) return [UIColor colorWithRed:209.0/255.0 green:1.0 blue:249.0/255.0 alpha:0.68];
    if ([self isDriveTheme]) return [UIColor colorWithRed:1.0 green:218.0/255.0 blue:179.0/255.0 alpha:0.68];
    return [UIColor colorWithWhite:1 alpha:0.62];
}

- (void)updateThemeColors {
    UIColor *digitBackground = [self themedDigitBackground];
    UIColor *digitText = [self themedDigitText];
    UIColor *digitBorder = [self themedDigitBorder];
    UIColor *accent = [self themedAccent];
    UIColor *activeAccent = _digitCardBorderColor ?: accent;
    _dateLabel.textColor = [UIColor colorWithRed:1.0 green:248.0/255.0 blue:232.0/255.0 alpha:1.0];
    if ([self isMarinaTheme]) _dateLabel.textColor = [UIColor colorWithRed:244.0/255.0 green:1.0 blue:248.0/255.0 alpha:1.0];
    for (UILabel *digit in _digitLabels) {
        if ([self isMarinaTheme] || [self isDriveTheme]) digit.backgroundColor = digitBackground;
        else digit.backgroundColor = [UIColor colorWithRed:1.0 green:243.0/255.0 blue:243.0/255.0 alpha:0.50];
        digit.textColor = digitText;
        digit.layer.borderColor = [digitBorder CGColor];
        if ([digit respondsToSelector:@selector(setAccentColor:)]) [(IWFlipDigitLabel *)digit setAccentColor:(_digitCardBorderColor ?: IWThemePink(1.0))];
        if ([self isMarinaTheme] || [self isDriveTheme]) digit.layer.shadowColor = [[accent colorWithAlphaComponent:0.36] CGColor];
        else digit.layer.shadowColor = [[UIColor colorWithRed:52.0/255.0 green:18.0/255.0 blue:58.0/255.0 alpha:0.26] CGColor];
    }
    [self applyDigitCardOpacity];
    for (UIView *colon in _colonViews) {
        UIView *dotA = [colon viewWithTag:1];
        UIView *dotB = [colon viewWithTag:2];
        UIColor *colonColor = activeAccent;
        for (IWColonDot *dot in @[(IWColonDot *)dotA, (IWColonDot *)dotB]) {
            dot.backgroundColor = [UIColor clearColor];
            dot.dotColor = colonColor;
            [dot setNeedsDisplay];
        }
    }
    _menu.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.30];
    if ([self isMarinaTheme]) _menu.backgroundColor = [UIColor colorWithRed:8.0/255.0 green:24.0/255.0 blue:40.0/255.0 alpha:0.30];
    if ([self isDriveTheme]) _menu.backgroundColor = [UIColor colorWithRed:35.0/255.0 green:15.0/255.0 blue:34.0/255.0 alpha:0.30];
    for (UIView *card in _homeCards) {
        card.backgroundColor = [self themedButtonBackground];
        card.layer.borderColor = [[accent colorWithAlphaComponent:0.40] CGColor];
        UILabel *name = [card viewWithTag:1];
        UILabel *meta = [card viewWithTag:3];
        name.textColor = [digitBorder colorWithAlphaComponent:0.9];
        meta.textColor = [accent colorWithAlphaComponent:0.92];
    }
    _weatherPanel.backgroundColor = [self themedButtonBackground];
    _weatherTemperatureLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.98];
    _weatherConditionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    _weatherRangeLabel.textColor = [activeAccent colorWithAlphaComponent:0.92];
    _weatherCityLabel.textColor = [activeAccent colorWithAlphaComponent:0.98];
    [self updateWeatherEditAppearance];
    [self applyDigitCardBorderStyle];
    [self updateCalendarPanel];
    [self updateMenuButtons];
}

- (void)addBadgeToButton:(UIButton *)button {
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(30, 26, 14, 14)];
    badge.tag = 909;
    badge.hidden = YES;
    badge.backgroundColor = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.92];
    badge.textColor = [UIColor colorWithRed:23.0/255.0 green:16.0/255.0 blue:32.0/255.0 alpha:1.0];
    badge.font = IWGTATextFont(10.0);
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 7.0;
    badge.clipsToBounds = YES;
    badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [button addSubview:badge];
}

- (void)addBetaWarningBadgeToButton:(UIButton *)button {
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(31, 27, 13, 13)];
    badge.tag = 919;
    badge.backgroundColor = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.96];
    badge.textColor = [UIColor colorWithRed:23.0/255.0 green:16.0/255.0 blue:32.0/255.0 alpha:1.0];
    badge.font = IWGTATextFont(10.0);
    badge.text = @"!";
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 6.5;
    badge.clipsToBounds = YES;
    badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [button addSubview:badge];
}

- (void)buildMenu {
    _menu = [[UIView alloc] initWithFrame:CGRectZero];
    _menu.hidden = YES;
    _menu.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.30];
    _menu.layer.borderWidth = IWControlBorderWidth();
    _menu.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.18] CGColor];
    _menu.layer.cornerRadius = 8.0;
    _menu.layer.shadowColor = [[UIColor colorWithRed:5.0/255.0 green:7.0/255.0 blue:18.0/255.0 alpha:0.20] CGColor];
    _menu.layer.shadowOffset = CGSizeMake(0, 14.0);
    _menu.layer.shadowRadius = 17.0;
    _menu.layer.shadowOpacity = 1.0;
    [_menu addSubview:[[IWMenuGlassBackdrop alloc] initWithFrame:_menu.bounds]];
    _menu.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_menu];

    CGFloat leftX = 10.0;
    CGFloat rightX = 68.0;
    CGFloat rowGap = 54.0;

    NSArray *stable = @[
        @(IWButtonKindThemeMenu), @(IWWallpaperTransitionTag),
        @(IWButtonKindClock), @2001,
        @2002, @2003,
        @(IWButtonKindCalendar), @(IWButtonKindWeather),
        @(IWButtonKindHeart), @(IWButtonKindVideo),
        @(IWButtonKindMusic), @(IWButtonKindLock),
        @(IWButtonKindLab)
    ];
    NSInteger i;
    for (i = 0; i < [stable count]; i += 1) {
        NSNumber *n = [stable objectAtIndex:i];
        NSInteger kind = [n integerValue];
        UIButton *b = kind == IWWallpaperTransitionTag ? [self textButton:[self wallpaperTransitionLabel] tag:IWWallpaperTransitionTag] : (kind == 2001 ? [self textButton:@"Sec" tag:2001] : (kind == 2002 ? [self textButton:@"24" tag:2002] : (kind == 2003 ? [self textButton:[self dateLanguageLabel] tag:2003] : [self actionButton:kind])));
        CGFloat x = (i % 2) == 0 ? leftX : rightX;
        CGFloat y = 10.0 + (i / 2) * rowGap;
        CGFloat width = IWControlSize();
        if (i == [stable count] - 1 && kind == IWButtonKindLab) {
            x = leftX;
            width = rightX + IWControlSize() - leftX;
        }
        b.frame = CGRectMake(x, y, width, IWControlSize());
        b.tag = [n integerValue];
        if (kind != IWWallpaperTransitionTag && kind != 2001 && kind != 2002 && kind != 2003) [b addTarget:self action:@selector(menuAction:) forControlEvents:UIControlEventTouchUpInside];
        if (kind == IWButtonKindMusic) _musicButton = (IWIconButton *)b;
        else if (kind == IWButtonKindLab) _settingsButton = (IWIconButton *)b;
        else if (kind == IWWallpaperTransitionTag) _wallpaperTransitionButton = b;
        else if (kind == 2001) _secondsButton = b;
        else if (kind == 2002) _hourButton = b;
        else if (kind == 2003) _languageButton = b;
        [_menu addSubview:b];
    }

    _settingsMenu = [[UIView alloc] initWithFrame:CGRectZero];
    _settingsMenu.hidden = YES;
    _settingsMenu.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.36];
    _settingsMenu.layer.borderWidth = IWControlBorderWidth();
    _settingsMenu.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.18] CGColor];
    _settingsMenu.layer.cornerRadius = 8.0;
    _settingsMenu.layer.shadowColor = [[UIColor colorWithWhite:0 alpha:0.30] CGColor];
    _settingsMenu.layer.shadowOffset = CGSizeMake(0, 10.0);
    _settingsMenu.layer.shadowRadius = 14.0;
    _settingsMenu.layer.shadowOpacity = 1.0;
    [self.view addSubview:_settingsMenu];
    NSArray *settings = @[@(IWButtonKindHome), @(IWButtonKindCast), @(IWPowerConnectTag), @(IWPowerDisconnectTag)];
    for (i = 0; i < [settings count]; i += 1) {
        NSInteger kind = [[settings objectAtIndex:i] integerValue];
        UIButton *b = kind == IWPowerConnectTag ? [self textButton:@"Wake" tag:IWPowerConnectTag] : (kind == IWPowerDisconnectTag ? [self textButton:@"Sleep" tag:IWPowerDisconnectTag] : [self actionButton:kind]);
        CGFloat x = (i % 2) == 0 ? leftX : rightX;
        CGFloat y = 10.0 + (i / 2) * rowGap;
        b.frame = CGRectMake(x, y, IWControlSize(), IWControlSize());
        if (kind == IWButtonKindHome || kind == IWButtonKindCast) [b addTarget:self action:@selector(menuAction:) forControlEvents:UIControlEventTouchUpInside];
        if (kind == IWButtonKindCast) _castButton = (IWIconButton *)b;
        else if (kind == IWPowerConnectTag) { _powerConnectButton = b; b.titleLabel.font = IWGTATextFont(12.0); }
        else if (kind == IWPowerDisconnectTag) { _powerDisconnectButton = b; b.titleLabel.font = IWGTATextFont(12.0); }
        if (kind == IWButtonKindHome || kind == IWButtonKindCast) [self addBetaWarningBadgeToButton:b];
        [_settingsMenu addSubview:b];
    }

}

- (UIButton *)textButton:(NSString *)title tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    b.backgroundColor = [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
    b.layer.borderWidth = IWControlBorderWidth();
    b.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.62] CGColor];
    b.layer.cornerRadius = IWControlRadius();
    b.clipsToBounds = YES;
    b.titleLabel.font = IWGTATextFont(15.0);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(menuAction:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buttonTouchDown:(UIButton *)button {
    IWFlashButtonPulse(button);
}

- (NSString *)dateLanguageLabel {
    if (_dateLanguage == 1) return @"中";
    if (_dateLanguage == 2) return @"繁";
    if (_dateLanguage == 3) return @"日";
    return @"EN";
}

- (void)tick {
    NSDate *now = [NSDate date];
    BOOL animateClock = ![self.presentedViewController isKindOfClass:[IWGalleryController class]] && (!_videoOverlay || _videoOverlay.hidden || _videoMinimized);

    [self updateCalendarPanel];
    NSCalendar *calendar = IWDisplayCalendar();
    NSDateComponents *components = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:now];
    NSInteger hour = [components hour];
    NSInteger minute = [components minute];
    NSInteger second = [components second];
    if (_gta6CountdownMode) {
        NSDateComponents *targetComponents = [[NSDateComponents alloc] init];
        targetComponents.year = 2026;
        targetComponents.month = 11;
        targetComponents.day = 19;
        targetComponents.hour = 0;
        targetComponents.minute = 0;
        targetComponents.second = 0;
        NSDate *target = [calendar dateFromComponents:targetComponents];
        NSTimeInterval remaining = target ? [target timeIntervalSinceDate:now] : 0.0;
        NSInteger totalSeconds = remaining > 0.0 ? (NSInteger)ceil(remaining) : 0;
        NSInteger days = totalSeconds / 86400;
        NSInteger remainder = totalSeconds % 86400;
        hour = remainder / 3600;
        minute = (remainder % 3600) / 60;
        second = remainder % 60;
        NSString *dayText = [NSString stringWithFormat:@"%03ld", (long)MIN(999, days)];
        NSInteger dayIndex;
        for (dayIndex = 0; dayIndex < [_countdownDayLabels count]; dayIndex += 1) {
            UILabel *digit = [_countdownDayLabels objectAtIndex:dayIndex];
            NSString *nextText = [dayText substringWithRange:NSMakeRange(dayIndex, 1)];
            if ([digit.text isEqualToString:nextText]) continue;
            if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
                [(IWFlipDigitLabel *)digit setDigitText:nextText animated:(animateClock && [digit.text length])];
            } else {
                digit.text = nextText;
            }
        }
    }
    if (!_hour24) {
        if (!_gta6CountdownMode) {
            hour = hour % 12;
            if (hour == 0) hour = 12;
        }
    }
    BOOL secondsVisible = (_gta6CountdownMode || _showSeconds);
    NSString *time = [NSString stringWithFormat:@"%02ld%02ld%02ld", (long)hour, (long)minute, (long)second];
    NSInteger i;
    for (i = 0; i < [_digitLabels count]; i += 1) {
        UILabel *digit = [_digitLabels objectAtIndex:i];
        if (!secondsVisible && i >= 4) {
            digit.hidden = YES;
            continue;
        }
        digit.hidden = NO;
        NSString *nextText = i < [time length] ? [time substringWithRange:NSMakeRange(i, 1)] : @"0";
        if ([digit.text isEqualToString:nextText]) continue;
        if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
            [(IWFlipDigitLabel *)digit setDigitText:nextText animated:(animateClock && [digit.text length])];
        } else {
            digit.text = nextText;
        }
    }
    if ([_colonViews count] > 0) [[_colonViews objectAtIndex:0] setHidden:!_gta6CountdownMode];
    if ([_colonViews count] > 2) [[_colonViews objectAtIndex:2] setHidden:!(_gta6CountdownMode || _showSeconds)];
    for (UILabel *digit in _countdownDayLabels) digit.hidden = !_gta6CountdownMode;
    _dateLabel.hidden = _gta6CountdownMode || !_dateVisible;
    if (_gta6CountdownMode) {
        return;
    }
    NSArray *days = @[@"SUN", @"MON", @"TUE", @"WED", @"THU", @"FRI", @"SAT"];
    NSArray *months = @[@"JAN", @"FEB", @"MAR", @"APR", @"MAY", @"JUN", @"JUL", @"AUG", @"SEP", @"OCT", @"NOV", @"DEC"];
    NSArray *cnDays = @[@"周日", @"周一", @"周二", @"周三", @"周四", @"周五", @"周六"];
    NSArray *twDays = @[@"週日", @"週一", @"週二", @"週三", @"週四", @"週五", @"週六"];
    NSArray *jpDays = @[@"日", @"月", @"火", @"水", @"木", @"金", @"土"];
    NSInteger weekday = MAX(1, MIN(7, [components weekday]));
    NSInteger month = MAX(1, MIN(12, [components month]));
    if (_dateLanguage == 1) {
        _dateLabel.text = [NSString stringWithFormat:@"%ld月%ld日 %@", (long)month, (long)[components day], [cnDays objectAtIndex:weekday - 1]];
    } else if (_dateLanguage == 2) {
        _dateLabel.text = [NSString stringWithFormat:@"%ld月%ld日 %@", (long)month, (long)[components day], [twDays objectAtIndex:weekday - 1]];
    } else if (_dateLanguage == 3) {
        _dateLabel.text = [NSString stringWithFormat:@"%ld月%ld日(%@)", (long)month, (long)[components day], [jpDays objectAtIndex:weekday - 1]];
    } else {
        _dateLabel.text = [NSString stringWithFormat:@"%@ %@ %ld", [days objectAtIndex:weekday - 1], [months objectAtIndex:month - 1], (long)[components day]];
    }
}

- (void)toggleMenu {
    BOOL opening = !_menuOpen;
    _menuOpen = opening;
    if (!opening) { _settingsOpen = NO; _secondaryMenuMode = 0; }
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    _menuButton.selected = _menuOpen;
    [_menuButton setNeedsDisplay];
    [self updateMenuButtons];
    [self flashButtonBackground:_menuButton];
    if (opening) {
        _menu.hidden = NO;
        _menu.alpha = 0.0;
        _menu.transform = CGAffineTransformMakeTranslation(0.0, -28.0);
        [UIView animateWithDuration:IWPanelAnimationDuration()
                              delay:0.0
             usingSpringWithDamping:IWPanelSpringDamping()
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            _menu.alpha = 1.0;
            _menu.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:IWPanelAnimationDuration()
                              delay:0.0
             usingSpringWithDamping:IWPanelSpringDamping()
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            _menu.alpha = 0.0;
            _menu.transform = CGAffineTransformMakeTranslation(0.0, -28.0);
        } completion:^(BOOL finished) {
            if (_menuOpen) return;
            _menu.hidden = YES;
            _menu.alpha = 1.0;
            _menu.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)clearSecondaryMenu {
    for (UIView *view in [_settingsMenu.subviews copy]) [view removeFromSuperview];
}

- (void)buildLabSecondaryMenu {
    [self clearSecondaryMenu];
    NSArray *items = @[@(IWButtonKindHome), @(IWButtonKindCast), @(IWPowerConnectTag), @(IWPowerDisconnectTag)];
    NSInteger i;
    for (i = 0; i < [items count]; i += 1) {
        NSInteger kind = [[items objectAtIndex:i] integerValue];
        UIButton *button = nil;
        if (kind == IWPowerConnectTag) button = [self textButton:@"Wake" tag:IWPowerConnectTag];
        else if (kind == IWPowerDisconnectTag) button = [self textButton:@"Sleep" tag:IWPowerDisconnectTag];
        else button = [self actionButton:kind];
        button.frame = CGRectMake((i % 2) == 0 ? 10.0 : 68.0, 10.0 + (i / 2) * 54.0, IWControlSize(), IWControlSize());
        if (kind == IWButtonKindHome || kind == IWButtonKindCast) [button addTarget:self action:@selector(menuAction:) forControlEvents:UIControlEventTouchUpInside];
        if (kind == IWButtonKindCast) _castButton = (IWIconButton *)button;
        else if (kind == IWPowerConnectTag) { _powerConnectButton = button; button.titleLabel.font = IWGTATextFont(12.0); }
        else if (kind == IWPowerDisconnectTag) { _powerDisconnectButton = button; button.titleLabel.font = IWGTATextFont(12.0); }
        if (kind == IWButtonKindHome || kind == IWButtonKindCast) [self addBetaWarningBadgeToButton:button];
        [_settingsMenu addSubview:button];
    }
}

- (void)buildThemeSecondaryMenu {
    [self clearSecondaryMenu];
    IWIconButton *themeCycle = [self actionButton:IWButtonKindTheme];
    themeCycle.tag = 9300;
    themeCycle.frame = CGRectMake(10.0, 10.0, IWControlSize(), IWControlSize());
    [themeCycle addTarget:self action:@selector(themeCycleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_settingsMenu addSubview:themeCycle];
    UIButton *countdown = [self textButton:@"VI" tag:IWGTA6CountdownTag];
    countdown.frame = CGRectMake(68.0, 10.0, IWControlSize(), IWControlSize());
    [_settingsMenu addSubview:countdown];
}

- (void)showSecondaryMenu:(NSInteger)mode {
    if (!_menuOpen) return;
    if (_settingsOpen && _secondaryMenuMode == mode) {
        _settingsOpen = NO;
        _secondaryMenuMode = 0;
    } else {
        _secondaryMenuMode = mode;
        _settingsOpen = YES;
        if (mode == 1) [self buildLabSecondaryMenu];
        else [self buildThemeSecondaryMenu];
    }
    _settingsMenu.hidden = !_settingsOpen;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    _settingsMenu.alpha = 1.0;
    [self updateMenuButtons];
    if (_settingsOpen) {
        _settingsMenu.transform = CGAffineTransformMakeTranslation(16.0, 0.0);
        _settingsMenu.alpha = 0.0;
        [UIView animateWithDuration:0.20 animations:^{
            _settingsMenu.transform = CGAffineTransformIdentity;
            _settingsMenu.alpha = 1.0;
        }];
    }
}

- (void)toggleSettingsMenu { [self showSecondaryMenu:1]; }

- (void)toggleThemeMenu { [self showSecondaryMenu:2]; }

- (void)promoThemeTapped:(UIButton *)button {
    NSArray *indexes = [self promoWallpaperIndexes];
    NSInteger index = button.tag - 9301;
    if (index >= 0 && index < [indexes count]) [self selectWallpaper:[[indexes objectAtIndex:index] integerValue]];
    [self updateMenuButtons];
}

- (void)themeCycleTapped:(UIButton *)button {
    [self cyclePromoWallpaper];
    [self updateMenuButtons];
}

- (void)flashButtonBackground:(UIButton *)button {
    IWFlashButtonPulse(button);
}

- (void)flashButtonBorder:(UIButton *)button {
    if (!button) return;
    CGColorRef original = button.layer.borderColor ? CGColorRetain(button.layer.borderColor) : NULL;
    CGFloat originalWidth = button.layer.borderWidth;
    UIColor *pink = IWThemePink(1.0);
    button.layer.borderWidth = MAX(originalWidth, 2.2);
    button.layer.borderColor = [pink CGColor];
    [UIView animateWithDuration:0.16 delay:0.10 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        button.layer.borderWidth = originalWidth;
        button.layer.borderColor = original;
    } completion:^(BOOL finished) {
        if (original) CGColorRelease(original);
    }];
}

- (void)returnToMainScreen {
    _pendingCastURL = nil;
    if (self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
    [self closeVideo];
    if (_editMode) [self commitEditModeForLifecycle];
    if (_depthMode) [self setDepthDemoEnabled:NO];
    _homeVisible = NO;
    _homePanel.hidden = YES;
    _menuOpen = NO;
    _menu.hidden = YES;
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
    [self updateMenuButtons];
    [self.view setNeedsLayout];
}

- (void)closeMenuForSystemAction {
    _menuOpen = NO;
    _menu.hidden = YES;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
}

- (void)lockDeviceNow {
    [self closeMenuForSystemAction];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    IWSendHardwareLockButtonPress();
    IWCallPrivateVoidFunction("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", "GSEventLockDevice");
    IWCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBLockDevice");
    IWCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBSLockDevice");
    IWCallPrivateVoidFunction("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", "SBDimScreen");
}

- (void)restoreDisplayAfterSystemLock {
    IWSetBackBoardScreenBlanked(NO);
    IWSetBackBoardBacklight(1.0, 0.18);
}

- (void)commitEditModeForLifecycle {
    if (!_editMode) return;
    [self finishEditMode];
    _panFallbackTracking = NO;
    [self resetSurfaceTouchState];
    [self writeDebugState:@"edit-lifecycle-commit"];
}

- (void)persistCurrentEditValues {
    if (!_editMode) return;
    if (_editTarget == IWEditTargetBackground) [self saveBackgroundAdjustment];
    else [self saveState];
}

- (void)menuAction:(UIButton *)sender {
    IWButtonKind kind = sender.tag;
    if (kind == IWButtonKindTheme || kind == IWButtonKindThemeMenu) [self toggleThemeMenu];
    else if (kind == IWButtonKindCrop) [self enterEditMode];
    else if (kind == IWButtonKindHeart) [self toggleFavoriteGallery];
    else if (kind == IWButtonKindClock) { _cleanMode = !_cleanMode; [self applyCleanMode]; [self saveState]; }
    else if (kind == IWButtonKindDate) { _dateVisible = !_dateVisible; [self tick]; [self applyCleanMode]; [self saveState]; }
    else if (kind == IWButtonKindCalendar) {
        // One concise visibility cycle: off -> compact date -> calendar.
        if (!_dateVisible && !_calendarVisible) {
            _dateVisible = YES;
        } else if (_dateVisible && !_calendarVisible) {
            _dateVisible = NO;
            _calendarVisible = YES;
        } else {
            _dateVisible = NO;
            _calendarVisible = NO;
            _calendarDisplayYear = 0;
            _calendarDisplayMonth = 0;
            _calendarSelectedDay = 0;
            _calendarHolidayToast.hidden = YES;
        }
        _calendarPanel.hidden = !_calendarVisible;
        [self tick];
        [self updateCalendarPanel];
        [self saveState];
    }
    else if (kind == IWButtonKindMusic) [self toggleMusic];
    else if (kind == IWButtonKindLab) [self toggleSettingsMenu];
    else if (kind == IWButtonKindHome) { _homeVisible = !_homeVisible; if (_homeVisible) [self loadHomeStatus]; _homePanel.hidden = _cleanMode || !_homeVisible; [self.view setNeedsLayout]; }
    else if (kind == IWButtonKindWeather) {
        _weatherVisible = !_weatherVisible;
        _weatherPanel.hidden = _cleanMode || !_weatherVisible;
        if (_weatherVisible) [self startWeatherUpdates];
        else [self stopWeatherUpdates];
        [self saveState];
    }
    else if (sender.tag == 2001) { _showSeconds = !_showSeconds; [self tick]; [self.view setNeedsLayout]; [self.view layoutIfNeeded]; [self saveState]; }
    else if (sender.tag == 2002) { _hour24 = !_hour24; [self tick]; [self saveState]; }
    else if (sender.tag == 2003) { _dateLanguage = (_dateLanguage + 1) % 4; [self tick]; [self refreshWeatherLanguagePresentation]; [self saveState]; }
    else if (sender.tag == IWGTA6CountdownTag) {
        [self saveState];
        _gta6CountdownMode = !_gta6CountdownMode;
        [self loadClockLayoutForCurrentMode];
        [self tick];
        [self saveState];
        [self.view setNeedsLayout];
    }
    else if (sender.tag == IWPowerConnectTag) { _powerConnectEnabled = !_powerConnectEnabled; [self savePowerAutomationPrefs]; }
    else if (sender.tag == IWPowerDisconnectTag) { _powerDisconnectEnabled = !_powerDisconnectEnabled; [self savePowerAutomationPrefs]; }
    else if (sender.tag == IWWallpaperTransitionTag) {
        // Order simple photo transitions before progressively more cinematic motion.
        switch (_wallpaperTransitionStyle) {
            case IWWallpaperTransitionStyleSlide: _wallpaperTransitionStyle = IWWallpaperTransitionStyleFade; break;
            case IWWallpaperTransitionStyleFade: _wallpaperTransitionStyle = IWWallpaperTransitionStyleFloat; break;
            case IWWallpaperTransitionStyleFloat: _wallpaperTransitionStyle = IWWallpaperTransitionStyleDrift; break;
            case IWWallpaperTransitionStyleDrift: _wallpaperTransitionStyle = IWWallpaperTransitionStyleLift; break;
            case IWWallpaperTransitionStyleLift: _wallpaperTransitionStyle = IWWallpaperTransitionStyleFocus; break;
            default: _wallpaperTransitionStyle = IWWallpaperTransitionStyleSlide; break;
        }
        [self saveState];
    }
    else if (kind == IWButtonKindVideo) [self openLocalVideo];
    else if (kind == IWButtonKindCast) [self toggleWizardCast];
    else if (kind == IWButtonKindDepth) [self toggleDepthDemo];
    else if (kind == IWButtonKindLock) [self lockDeviceNow];
    [self updateMenuButtons];
}

- (NSString *)wallpaperTransitionLabel {
    switch (_wallpaperTransitionStyle) {
        case IWWallpaperTransitionStyleFade: return @"Fade";
        case IWWallpaperTransitionStyleFloat: return @"Float";
        case IWWallpaperTransitionStyleFocus: return @"Focus";
        case IWWallpaperTransitionStyleDrift: return @"Drift";
        case IWWallpaperTransitionStyleLift: return @"Lift";
        case IWWallpaperTransitionStyleSlide: return @"Slide";
        default: return @"Slide";
    }
}

- (void)applyCleanMode {
    _digitGroup.hidden = _cleanMode;
    _dateLabel.hidden = _gta6CountdownMode || !_dateVisible;
    _homePanel.hidden = _cleanMode || !_homeVisible;
    _weatherPanel.hidden = _cleanMode || !_weatherVisible;
    _menu.hidden = !_menuOpen;
    _menuButton.selected = _menuOpen;
    [_menuButton setNeedsDisplay];
    _controlsHidden = NO;
    _menuButton.hidden = NO;
}

- (void)updateMenuButtons {
    UIColor *inactiveBackground = [self themedButtonBackground];
    UIColor *inactiveBorder = [self themedButtonBorder];
    UIColor *activeBackground = IWThemePink(0.72);
    UIColor *activeBorder = [UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:0.86];
    NSArray *buttonContainers = @[_menu, _settingsMenu ?: [[UIView alloc] init]];
    for (UIView *container in buttonContainers) for (UIView *view in [container subviews]) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        UIButton *button = (UIButton *)view;
        if (button.tag == IWButtonKindCalendar && [button isKindOfClass:[IWIconButton class]]) {
            // The single control represents three states.  In compact-date
            // mode retain the earlier date glyph; calendar mode keeps its
            // distinct grid glyph, so the current state is legible at once.
            ((IWIconButton *)button).kind = _calendarVisible ? IWButtonKindCalendar : (_dateVisible ? IWButtonKindDate : IWButtonKindCalendar);
            [button setNeedsDisplay];
        }
        BOOL active = NO;
        if (button.tag == IWButtonKindHeart) active = _favoriteOnly;
        else if (button.tag == IWButtonKindTheme || button.tag == IWButtonKindThemeMenu) active = _settingsOpen && _secondaryMenuMode == 2;
        else if (button.tag == IWButtonKindLab) active = _settingsOpen && _secondaryMenuMode == 1;
        else if (button.tag == IWButtonKindClock) active = !_cleanMode;
        else if (button.tag == IWButtonKindDate) active = _dateVisible;
        else if (button.tag == IWButtonKindCalendar) active = _dateVisible || _calendarVisible;
        else if (button.tag == IWButtonKindHome) active = _homeVisible;
        else if (button.tag == IWButtonKindWeather) active = _weatherVisible;
        else if (button.tag == IWButtonKindMusic) active = _player.playing;
        else if (button.tag == IWButtonKindCast) active = _dlnaCastServer.running;
        else if (button.tag == IWButtonKindDepth) active = _depthMode;
        else if (button.tag == 2001) active = _showSeconds;
        else if (button.tag == 2002) active = _hour24;
        else if (button.tag == 2003) active = NO;
        else if (button.tag == IWGTA6CountdownTag) active = _gta6CountdownMode;
        else if (button.tag == IWPowerConnectTag) active = _powerConnectEnabled;
        else if (button.tag == IWPowerDisconnectTag) active = _powerDisconnectEnabled;
        else if (button.tag == IWWallpaperTransitionTag) active = NO;
        BOOL error = (button.tag == IWButtonKindMusic && _musicError) ||
                     (button.tag == IWButtonKindCast && _castError) ||
                     (button.tag == IWButtonKindWeather && _weatherError);
        button.layer.borderWidth = IWControlBorderWidth();
        if (error) {
            button.backgroundColor = [UIColor colorWithRed:180.0/255.0 green:58.0/255.0 blue:42.0/255.0 alpha:0.62];
            button.layer.borderColor = [[UIColor colorWithRed:1.0 green:184.0/255.0 blue:108.0/255.0 alpha:0.9] CGColor];
        } else if (active) {
            button.backgroundColor = activeBackground;
            button.layer.borderColor = [activeBorder CGColor];
        } else {
            button.backgroundColor = inactiveBackground;
            button.layer.borderColor = [inactiveBorder CGColor];
        }
    }
    _settingsMenu.hidden = !(_menuOpen && _settingsOpen);
    _menuButton.selected = _menuOpen;
    _menuButton.backgroundColor = _menuOpen ? [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.66] : [UIColor clearColor];
    _menuButton.layer.borderWidth = IWControlBorderWidth();
    _menuButton.layer.borderColor = [[self themedButtonBorder] CGColor];
    [_menuButton setNeedsDisplay];
    [self updateStatusBadges];
    [_secondsButton setTitle:@"Sec" forState:UIControlStateNormal];
    [_hourButton setTitle:(_hour24 ? @"24" : @"12") forState:UIControlStateNormal];
    [_languageButton setTitle:[self dateLanguageLabel] forState:UIControlStateNormal];
    [_wallpaperTransitionButton setTitle:[self wallpaperTransitionLabel] forState:UIControlStateNormal];
    _wallpaperTransitionButton.titleLabel.font = IWGTATextFont((_wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat || _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift) ? 11.0 : 12.0);
    _secondsButton.enabled = !_gta6CountdownMode;
    _hourButton.enabled = !_gta6CountdownMode;
    _languageButton.enabled = !_gta6CountdownMode;
    _secondsButton.alpha = _gta6CountdownMode ? 0.42 : 1.0;
    _hourButton.alpha = _gta6CountdownMode ? 0.42 : 1.0;
    _languageButton.alpha = _gta6CountdownMode ? 0.42 : 1.0;
}

- (void)updateStatusBadges {
    UILabel *musicBadge = [_musicButton viewWithTag:909];
    musicBadge.hidden = YES;
    musicBadge.text = _player.playing ? @"P" : @"!";
    UILabel *castBadge = [_castButton viewWithTag:909];
    castBadge.hidden = YES;
}

- (NSArray *)displayItems {
    if (_promoOnly) {
        NSMutableArray *items = [NSMutableArray array];
        NSSet *promos = [NSSet setWithObjects:@"gta6-026-jason-and-lucia-01-landscape", @"gta6-027-jason-and-lucia-02-landscape", @"gta6-028-jason-and-lucia-03-landscape", nil];
        NSInteger i;
        for (i = 0; i < [_wallpapers count]; i += 1) {
            NSString *key = [[_wallpapers objectAtIndex:i] objectForKey:@"key"];
            if ([promos containsObject:key]) [items addObject:[_wallpapers objectAtIndex:i]];
        }
        return items;
    }
    if (!_favoriteOnly) return _wallpapers;
    NSMutableArray *items = [NSMutableArray array];
    NSInteger i;
    for (i = 0; i < [_wallpapers count]; i += 1) {
        if ([self isFavorite:i]) [items addObject:[_wallpapers objectAtIndex:i]];
    }
    return items;
}

- (NSArray *)favoriteGalleryItems {
    NSMutableArray *items = [NSMutableArray array];
    NSInteger i;
    for (i = 0; i < [_wallpapers count]; i += 1) {
        if ([self isFavorite:i]) [items addObject:[_wallpapers objectAtIndex:i]];
    }
    return items;
}

- (NSArray *)galleryItemsForCurrentFilter {
    return [self displayItems];
}

- (NSArray *)allGalleryItems {
    return _wallpapers ?: @[];
}

- (void)selectFirstItemIfNeeded:(NSArray *)items {
    if (![items count]) return;
    NSInteger i;
    for (i = 0; i < [items count]; i += 1) {
        NSInteger original = [[[items objectAtIndex:i] objectForKey:@"index"] integerValue];
        if (original == _wallpaperIndex) return;
    }
    [self selectWallpaper:[[[items objectAtIndex:0] objectForKey:@"index"] integerValue]];
}

- (NSArray *)promoWallpaperIndexes {
    NSMutableArray *indexes = [NSMutableArray array];
    NSSet *promos = [NSSet setWithObjects:@"gta6-026-jason-and-lucia-01-landscape", @"gta6-027-jason-and-lucia-02-landscape", @"gta6-028-jason-and-lucia-03-landscape", nil];
    NSInteger i;
    for (i = 0; i < [_wallpapers count]; i += 1) {
        NSString *key = [[_wallpapers objectAtIndex:i] objectForKey:@"key"];
        if ([promos containsObject:key]) [indexes addObject:[NSNumber numberWithInteger:i]];
    }
    return indexes;
}

- (void)cyclePromoWallpaper {
    NSArray *indexes = [self promoWallpaperIndexes];
    if (![indexes count]) return;
    NSInteger position = -1;
    NSInteger i;
    for (i = 0; i < [indexes count]; i += 1) {
        if ([[indexes objectAtIndex:i] integerValue] == _wallpaperIndex) {
            position = i;
            break;
        }
    }
    NSInteger next = (position + 1 + [indexes count]) % [indexes count];
    [self selectWallpaper:[[indexes objectAtIndex:next] integerValue]];
    _promoOnly = NO;
}

- (void)toggleFavoriteGallery {
    if (_favoriteOnly) {
        _favoriteOnly = NO;
        _promoOnly = NO;
        _menuOpen = NO;
        _menu.hidden = YES;
        _controlsHidden = NO;
        _menuButton.hidden = NO;
        _menuButton.selected = NO;
        [_menuButton setNeedsDisplay];
        [self updateMenuButtons];
        [self saveState];
        return;
    }
    _promoOnly = NO;
    [self openFavoriteGalleryPreview];
}

- (void)openFavoriteGalleryPreview {
    if (_editMode) return;
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]]) return;
    _menuOpen = NO;
    _menu.hidden = YES;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    NSArray *items = [self favoriteGalleryItems];
    IWGalleryController *g = [[IWGalleryController alloc] initWithOwner:self items:items selected:_wallpaperIndex favorites:_favorites cache:_thumbCache];
    g.backdropImage = _background.image;
    [g enableFavoriteConfirmMode];
    [self presentViewController:g animated:NO completion:nil];
}

- (void)confirmFavoriteGalleryModeFromIndex:(NSInteger)index {
    NSArray *items = [self favoriteGalleryItems];
    if (![items count]) return;
    NSInteger target = [[items objectAtIndex:0] objectForKey:@"index"] ? [[[items objectAtIndex:0] objectForKey:@"index"] integerValue] : 0;
    NSInteger i;
    for (i = 0; i < [items count]; i += 1) {
        NSInteger original = [[[items objectAtIndex:i] objectForKey:@"index"] integerValue];
        if (original == index) {
            target = original;
            break;
        }
    }
    _favoriteOnly = YES;
    _promoOnly = NO;
    [self selectWallpaper:target];
    _menuOpen = NO;
    _menu.hidden = YES;
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
    [self updateMenuButtons];
}

- (void)openGallery {
    if (_editMode) return;
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]]) return;
    _menuOpen = NO;
    _menu.hidden = YES;
    _menuButton.selected = NO;
    [_menuButton setNeedsDisplay];
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    IWGalleryController *g = [[IWGalleryController alloc] initWithOwner:self items:[self allGalleryItems] selected:_wallpaperIndex favorites:_favorites cache:_thumbCache];
    g.backdropImage = _background.image;
    [self presentViewController:g animated:NO completion:nil];
}

- (void)selectWallpaper:(NSInteger)index {
    [self selectWallpaper:index slideDirection:0];
}

- (BOOL)openGalleryMediaAtIndex:(NSInteger)index {
    if (index < 0 || index >= [_wallpapers count]) return NO;
    NSDictionary *item = [_wallpapers objectAtIndex:index];
    if (![[[item objectForKey:@"type"] lowercaseString] isEqualToString:@"video"]) return NO;
    NSString *path = [item objectForKey:@"videoPath"];
    if (![path length]) return NO;
    [self openMoviePath:path];
    return YES;
}

- (void)selectWallpaper:(NSInteger)index slideDirection:(NSInteger)direction {
    if (index < 0 || index >= [_wallpapers count]) return;
    if ([[[[_wallpapers objectAtIndex:index] objectForKey:@"type"] lowercaseString] isEqualToString:@"video"]) {
        [self openGalleryMediaAtIndex:index];
        return;
    }
    if (_depthMode) [self setDepthDemoEnabled:NO];
    UIImage *oldImage = _background.image;
    CGRect oldFrame = _background.frame;
    UIView *oldView = nil;
    CGFloat stageWidth = _backgroundClip.bounds.size.width;
    [[_backgroundClip viewWithTag:777] removeFromSuperview];
    if (oldImage && stageWidth > 0 && !UIAccessibilityIsReduceMotionEnabled()) {
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:oldFrame];
        imageView.tag = 777;
        imageView.image = oldImage;
        imageView.contentMode = UIViewContentModeScaleToFill;
        imageView.clipsToBounds = YES;
        [_backgroundClip addSubview:imageView];
        oldView = imageView;
    }
    _wallpaperIndex = index;
    _controlsHidden = NO;
    NSUInteger loadGeneration = IWNextWallpaperLoadGeneration(&_wallpaperLoadGeneration);
    NSString *expectedKey = [[self wallpaperKey] copy];
    NSString *path = [[[_wallpapers objectAtIndex:_wallpaperIndex] objectForKey:@"imagePath"] copy];
    [self loadBackgroundAdjustment];
    [self updateThemeColors];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!IWApplyWallpaperLoadIfCurrent(loadGeneration, _wallpaperLoadGeneration, _wallpapers, _wallpaperIndex, expectedKey, path, ^{
                _background.image = img;
                _wallpaperAccentColor = [self dominantAccentColorForImage:img];
                [self updateThemeColors];
                [self applyBackgroundTransform];
            })) {
                [oldView removeFromSuperview];
                return;
            }
            if (UIAccessibilityIsReduceMotionEnabled()) {
                [_background.layer removeAllAnimations];
                _background.transform = CGAffineTransformIdentity;
                _background.alpha = 1.0;
                [oldView removeFromSuperview];
                return;
            }
            if (_wallpaperTransitionStyle == IWWallpaperTransitionStyleSlide) {
                CGFloat dx = (direction >= 0 ? stageWidth : -stageWidth);
                _background.transform = CGAffineTransformMakeTranslation(dx, 0);
                [UIView animateWithDuration:0.26 delay:0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
                    _background.transform = CGAffineTransformIdentity;
                    oldView.transform = CGAffineTransformMakeTranslation(-dx, 0);
                    oldView.alpha = 0.0;
                } completion:^(__unused BOOL finished) {
                    if (!IWApplyWallpaperLoadIfCurrent(loadGeneration, _wallpaperLoadGeneration, _wallpapers, _wallpaperIndex, expectedKey, path, ^{
                        [oldView removeFromSuperview];
                        _background.transform = CGAffineTransformIdentity;
                    })) [oldView removeFromSuperview];
                }];
                return;
            }

            NSTimeInterval duration = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 0.52 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 0.30 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 0.62 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 0.48 : 0.36)));
            CGFloat incomingScale = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 1.045 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 1.105 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 1.070 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 1.075 : 1.0)));
            CGFloat outgoingScale = _wallpaperTransitionStyle == IWWallpaperTransitionStyleFloat ? 1.025 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleFocus ? 1.070 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 1.020 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 1.035 : 1.0)));
            CGFloat incomingX = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 34.0 : 0.0;
            CGFloat incomingY = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? -16.0 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? 34.0 : 0.0);
            CGFloat outgoingX = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? -22.0 : 0.0;
            CGFloat outgoingY = _wallpaperTransitionStyle == IWWallpaperTransitionStyleDrift ? 12.0 : (_wallpaperTransitionStyle == IWWallpaperTransitionStyleLift ? -22.0 : 0.0);
            _background.alpha = 0.0;
            _background.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(incomingScale, incomingScale), incomingX, incomingY);
            [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState) animations:^{
                _background.alpha = 1.0;
                _background.transform = CGAffineTransformIdentity;
                oldView.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(outgoingScale, outgoingScale), outgoingX, outgoingY);
                oldView.alpha = 0.0;
            } completion:^(BOOL finished) {
                if (!IWApplyWallpaperLoadIfCurrent(loadGeneration, _wallpaperLoadGeneration, _wallpapers, _wallpaperIndex, expectedKey, path, ^{
                    [oldView removeFromSuperview];
                    _background.transform = CGAffineTransformIdentity;
                    _background.alpha = 1.0;
                })) [oldView removeFromSuperview];
            }];
        });
    });
    [self saveState];
}

- (void)animateWallpaperPulse {
    _wallpaperPulse.alpha = 1.0;
    [UIView animateWithDuration:0.22 animations:^{
        _wallpaperPulse.alpha = 0.0;
    }];
}

- (BOOL)isFavorite:(NSInteger)index {
    if (index < 0 || index >= [_wallpapers count]) return NO;
    NSString *key = [[_wallpapers objectAtIndex:index] objectForKey:@"key"];
    return key && [[_favorites objectForKey:key] boolValue];
}

- (void)toggleFavorite:(NSInteger)index {
    if (index < 0 || index >= [_wallpapers count]) return;
    NSString *key = [[_wallpapers objectAtIndex:index] objectForKey:@"key"];
    if (!key) return;
    if ([_favorites objectForKey:key]) [_favorites removeObjectForKey:key];
    else [_favorites setObject:@YES forKey:key];
    [self saveState];
}

- (void)addFavorite:(NSInteger)index {
    if (index < 0 || index >= [_wallpapers count]) return;
    NSString *key = [[_wallpapers objectAtIndex:index] objectForKey:@"key"];
    if (!key) return;
    [_favorites setObject:@YES forKey:key];
    [self saveState];
}

- (void)applyWallpaper {
    NSUInteger loadGeneration = IWNextWallpaperLoadGeneration(&_wallpaperLoadGeneration);
    if (_wallpaperIndex < 0 || _wallpaperIndex >= [_wallpapers count]) {
        [_background.layer removeAllAnimations];
        [[_backgroundClip viewWithTag:777] removeFromSuperview];
        _background.image = nil;
        _background.alpha = 1.0;
        _background.transform = CGAffineTransformIdentity;
        return;
    }
    NSString *expectedKey = [[self wallpaperKey] copy];
    NSString *path = [[[_wallpapers objectAtIndex:_wallpaperIndex] objectForKey:@"imagePath"] copy];
    [self loadBackgroundAdjustment];
    [self updateThemeColors];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            IWApplyWallpaperLoadIfCurrent(loadGeneration, _wallpaperLoadGeneration, _wallpapers, _wallpaperIndex, expectedKey, path, ^{
                _background.image = img;
                _wallpaperAccentColor = [self dominantAccentColorForImage:img];
                [self updateThemeColors];
                [self applyBackgroundTransform];
            });
        });
    });
}

- (void)setDepthDemoEnabled:(BOOL)enabled {
    _depthMode = enabled;
    if (!enabled) {
        [_motionManager stopDeviceMotionUpdates];
        _depthBackground.hidden = YES;
        _depthForeground.hidden = YES;
        _background.hidden = NO;
        _depthTiltX = 0;
        _depthTiltY = 0;
        [self updateMenuButtons];
        return;
    }
    NSString *key = [self wallpaperKey];
    NSString *base = [IWAppPath stringByAppendingPathComponent:[NSString stringWithFormat:@"assets/depth/%@-bg.jpg", key]];
    NSString *fg = [IWAppPath stringByAppendingPathComponent:[NSString stringWithFormat:@"assets/depth/%@-fg.png", key]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:base] || ![[NSFileManager defaultManager] fileExistsAtPath:fg]) {
        base = [IWAppPath stringByAppendingPathComponent:@"assets/depth/gta6-depth-bg.jpg"];
        fg = [IWAppPath stringByAppendingPathComponent:@"assets/depth/gta6-depth-fg.png"];
    }
    UIImage *baseImage = [UIImage imageWithContentsOfFile:base];
    UIImage *fgImage = [UIImage imageWithContentsOfFile:fg];
    if (!baseImage || !fgImage) {
        _depthMode = NO;
        [self updateMenuButtons];
        return;
    }
    _depthBackground.image = baseImage;
    _depthForeground.image = fgImage;
    _background.hidden = YES;
    _depthBackground.hidden = NO;
    _depthForeground.hidden = NO;
    [self applyDepthLayout];
    if (!_motionManager) _motionManager = [[CMMotionManager alloc] init];
    if ([_motionManager isDeviceMotionAvailable]) {
        _motionManager.deviceMotionUpdateInterval = 1.0 / 30.0;
        __weak IWRootViewController *weakSelf = self;
        [_motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *motion, NSError *error) {
            IWRootViewController *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf->_depthMode || error) return;
            strongSelf->_depthTiltX = MAX(-1.0, MIN(1.0, motion.gravity.x));
            strongSelf->_depthTiltY = MAX(-1.0, MIN(1.0, -motion.gravity.y));
            [strongSelf applyDepthLayout];
        }];
    }
    [self updateMenuButtons];
}

- (void)toggleDepthDemo {
    [self setDepthDemoEnabled:!_depthMode];
}

- (NSString *)wallpaperKey {
    if (_wallpaperIndex < 0 || _wallpaperIndex >= [_wallpapers count]) return @"default";
    return [[_wallpapers objectAtIndex:_wallpaperIndex] objectForKey:@"key"] ?: @"default";
}

- (void)loadBackgroundAdjustment {
    NSDictionary *value = [_backgroundAdjustments objectForKey:[self wallpaperKey]];
    _backgroundX = [[value objectForKey:@"x"] floatValue];
    _backgroundY = [[value objectForKey:@"y"] floatValue];
    _backgroundZoom = [[value objectForKey:@"zoom"] floatValue];
    if (_backgroundZoom < 1.0) _backgroundZoom = 1.0;
    if (_backgroundZoom > 3.0) _backgroundZoom = 3.0;
}

- (void)saveBackgroundAdjustment {
    [_backgroundAdjustments setObject:@{
        @"x": [NSNumber numberWithFloat:_backgroundX],
        @"y": [NSNumber numberWithFloat:_backgroundY],
        @"zoom": [NSNumber numberWithFloat:_backgroundZoom]
    } forKey:[self wallpaperKey]];
    [self saveState];
}

- (void)applyBackgroundTransform {
    if (![_wallpapers count]) return;
    NSDictionary *item = [_wallpapers objectAtIndex:_wallpaperIndex];
    CGFloat imageWidth = [[item objectForKey:@"width"] floatValue];
    CGFloat imageHeight = [[item objectForKey:@"height"] floatValue];
    if (imageWidth <= 0 || imageHeight <= 0) {
        imageWidth = _background.image.size.width > 0 ? _background.image.size.width : _backgroundClip.bounds.size.width;
        imageHeight = _background.image.size.height > 0 ? _background.image.size.height : _backgroundClip.bounds.size.height;
    }
    CGFloat stageWidth = _backgroundClip.bounds.size.width;
    CGFloat stageHeight = _backgroundClip.bounds.size.height;
    if (stageWidth <= 0 || stageHeight <= 0 || imageWidth <= 0 || imageHeight <= 0) return;

    _backgroundZoom = MAX(1.0, MIN(3.0, _backgroundZoom));
    CGFloat coverScale = MAX(stageWidth / imageWidth, stageHeight / imageHeight) * 1.04;
    CGFloat displayWidth = ceil(imageWidth * coverScale * _backgroundZoom);
    CGFloat displayHeight = ceil(imageHeight * coverScale * _backgroundZoom);
    CGFloat maxX = MAX(0.0, round((displayWidth - stageWidth) / 2.0) - 3.0);
    CGFloat maxY = MAX(0.0, round((displayHeight - stageHeight) / 2.0) - 3.0);
    _backgroundX = MAX(-maxX, MIN(maxX, _backgroundX));
    _backgroundY = MAX(-maxY, MIN(maxY, _backgroundY));

    _background.transform = CGAffineTransformIdentity;
    _background.frame = CGRectMake(floor((stageWidth - displayWidth) / 2.0 + _backgroundX),
                                   floor((stageHeight - displayHeight) / 2.0 + _backgroundY),
                                   ceil(displayWidth),
                                   ceil(displayHeight));
}

- (void)enterEditMode {
    _editMode = YES;
    _editTarget = IWEditTargetBackground;
    _menuOpen = NO;
    _menu.hidden = YES;
    _controlsHidden = NO;
    _editSnapshot = @{
        @"x": [NSNumber numberWithFloat:_backgroundX],
        @"y": [NSNumber numberWithFloat:_backgroundY],
        @"zoom": [NSNumber numberWithFloat:_backgroundZoom]
    };
    _editToolbar.hidden = NO;
    [self updateOpacityControlVisibility];
    [self animateEditToolbarDropIn];
    _menuButton.hidden = YES;
    [self updateMenuButtons];
}

- (void)enterClockEditMode {
    // Weather edit can leave an animated toolbar completion in flight.  Lay
    // out the shared toolbar synchronously before presenting its clock state.
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self applyClockTransforms];
    _editMode = YES;
    _editTarget = IWEditTargetClock;
    _menuOpen = NO;
    _menu.hidden = YES;
    _calendarHiddenForClockEdit = _calendarVisible && !_calendarPanel.hidden;
    if (_calendarHiddenForClockEdit) _calendarPanel.hidden = YES;
    _controlsHidden = NO;
    _editSnapshot = @{
        @"clockX": [NSNumber numberWithFloat:_clockOffsetX],
        @"clockY": [NSNumber numberWithFloat:_clockOffsetY],
        @"clockZoom": [NSNumber numberWithFloat:_clockScale],
        @"dateX": [NSNumber numberWithFloat:_dateOffsetX],
        @"dateY": [NSNumber numberWithFloat:_dateOffsetY],
        @"dateZoom": [NSNumber numberWithFloat:_dateScale],
        @"digitCardOpacity": [NSNumber numberWithFloat:_digitCardOpacity],
        @"digitCardBorderColor": _digitCardBorderColor ?: IWThemePink(1.0),
        @"digitCardBorderWidth": [NSNumber numberWithFloat:_digitCardBorderWidth]
    };
    _editToolbar.hidden = NO;
    [self resetEditToolbarButtonPresentation];
    [self updateOpacityControlVisibility];
    [self applyClockTransforms];
    [self animateEditToolbarDropIn];
    _menuButton.hidden = YES;
    [self updateMenuButtons];
}

- (void)enterDateEditMode {
    [self enterClockEditMode];
    _editTarget = IWEditTargetDate;
    if (_calendarHiddenForClockEdit) {
        _calendarPanel.hidden = NO;
        _calendarHiddenForClockEdit = NO;
    }
    [self updateOpacityControlVisibility];
}

- (void)enterCalendarEditMode {
    _editMode = YES;
    _editTarget = IWEditTargetCalendar;
    _menuOpen = NO;
    _settingsOpen = NO;
    _menu.hidden = YES;
    _settingsMenu.hidden = YES;
    _controlsHidden = NO;
    _calendarHolidayToast.hidden = YES;
    _editSnapshot = @{
        @"calendarScale": [NSNumber numberWithFloat:_calendarScale],
        @"calendarX": [NSNumber numberWithFloat:_calendarOffsetX],
        @"calendarY": [NSNumber numberWithFloat:_calendarOffsetY],
        @"calendarOpacity": [NSNumber numberWithFloat:_calendarOpacity]
    };
    _editToolbar.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self resetEditToolbarButtonPresentation];
    [self updateOpacityControlVisibility];
    [self animateEditToolbarDropIn];
    _menuButton.hidden = YES;
    [self updateMenuButtons];
}

- (void)enterWeatherEditMode {
    _editMode = YES;
    _editTarget = IWEditTargetWeather;
    _menuOpen = NO;
    _settingsOpen = NO;
    _menu.hidden = YES;
    _settingsMenu.hidden = YES;
    _controlsHidden = NO;
    _editSnapshot = @{
        @"weatherScale": [NSNumber numberWithFloat:_weatherScale],
        @"weatherX": [NSNumber numberWithFloat:_weatherOffsetX],
        @"weatherY": [NSNumber numberWithFloat:_weatherOffsetY]
    };
    _editToolbar.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self resetEditToolbarButtonPresentation];
    [self updateOpacityControlVisibility];
    [self updateWeatherEditAppearance];
    [self animateEditToolbarDropIn];
    _menuButton.hidden = YES;
    [self updateMenuButtons];
}

- (void)finishEditMode {
    IWEditTarget target = _editTarget;
    _editMode = NO;
    _editTarget = IWEditTargetNone;
    _editSnapshot = nil;
    [self hideEditToolbarAnimated];
    _menuButton.hidden = _controlsHidden;
    if (target == IWEditTargetBackground) [self saveBackgroundAdjustment];
    else [self saveState];
    if (_calendarHiddenForClockEdit) {
        _calendarPanel.hidden = NO;
        _calendarHiddenForClockEdit = NO;
    }
    [self updateWeatherEditAppearance];
    [self updateMenuButtons];
}

- (void)cancelEditMode {
    if (!_editMode || !_editSnapshot) return;
    IWEditTarget target = _editTarget;
    if (_editTarget == IWEditTargetWeather) {
        _weatherScale = [[_editSnapshot objectForKey:@"weatherScale"] floatValue];
        _weatherOffsetX = [[_editSnapshot objectForKey:@"weatherX"] floatValue];
        _weatherOffsetY = [[_editSnapshot objectForKey:@"weatherY"] floatValue];
        [self applyWeatherTransform];
    } else if (_editTarget == IWEditTargetCalendar) {
        _calendarScale = [[_editSnapshot objectForKey:@"calendarScale"] floatValue];
        _calendarOffsetX = [[_editSnapshot objectForKey:@"calendarX"] floatValue];
        _calendarOffsetY = [[_editSnapshot objectForKey:@"calendarY"] floatValue];
        _calendarOpacity = IWDigitCardClampOpacity([[_editSnapshot objectForKey:@"calendarOpacity"] floatValue]);
        [self applyCalendarTransform];
        [self applyCalendarOpacity];
    } else if ([_editSnapshot objectForKey:@"clockX"]) {
        _clockOffsetX = [[_editSnapshot objectForKey:@"clockX"] floatValue];
        _clockOffsetY = [[_editSnapshot objectForKey:@"clockY"] floatValue];
        _clockScale = [[_editSnapshot objectForKey:@"clockZoom"] floatValue];
        _dateOffsetX = [[_editSnapshot objectForKey:@"dateX"] floatValue];
        _dateOffsetY = [[_editSnapshot objectForKey:@"dateY"] floatValue];
        _dateScale = [[_editSnapshot objectForKey:@"dateZoom"] floatValue];
        _digitCardOpacity = IWDigitCardClampOpacity([[_editSnapshot objectForKey:@"digitCardOpacity"] floatValue]);
        _digitCardBorderColor = [_editSnapshot objectForKey:@"digitCardBorderColor"] ?: IWThemePink(1.0);
        _digitCardBorderWidth = [[_editSnapshot objectForKey:@"digitCardBorderWidth"] floatValue];
        [self applyClockTransforms];
        [self applyDigitCardOpacity];
        [self applyDigitCardBorderStyle];
    } else {
        _backgroundX = [[_editSnapshot objectForKey:@"x"] floatValue];
        _backgroundY = [[_editSnapshot objectForKey:@"y"] floatValue];
        _backgroundZoom = [[_editSnapshot objectForKey:@"zoom"] floatValue];
        [self applyBackgroundTransform];
    }
    _editMode = NO;
    _editTarget = IWEditTargetNone;
    _editSnapshot = nil;
    [self hideEditToolbarAnimated];
    _menuButton.hidden = _controlsHidden;
    if (_calendarHiddenForClockEdit) {
        _calendarPanel.hidden = NO;
        _calendarHiddenForClockEdit = NO;
    }
    // Gesture completion may already have persisted the edit. Cancelling
    // must also restore that durable state, not only the current view.
    if (target == IWEditTargetBackground) [self saveBackgroundAdjustment];
    else [self saveState];
    [self updateWeatherEditAppearance];
    [self updateMenuButtons];
}

- (void)resetEditMode {
    if (_editTarget == IWEditTargetWeather) {
        _weatherScale = 1.0;
        _weatherOffsetX = 0.0;
        _weatherOffsetY = 0.0;
        [self applyWeatherTransform];
    } else if (_editTarget == IWEditTargetCalendar) {
        _calendarScale = 1.0;
        _calendarOffsetX = 0.0;
        _calendarOffsetY = 0.0;
        _calendarOpacity = 0.54;
        [self applyCalendarTransform];
        [self applyCalendarOpacity];
    } else if (_editTarget == IWEditTargetClock) {
        _clockOffsetX = IWClockDefaultOffsetX();
        _clockOffsetY = IWClockDefaultOffsetY();
        _clockScale = IWClockDefaultScale();
        _dateOffsetX = IWDateDefaultOffsetX();
        _dateOffsetY = IWDateDefaultOffsetY();
        _dateScale = IWDateDefaultScale();
        _digitCardOpacity = IWDigitCardDefaultOpacity();
        _digitCardBorderColor = IWThemePink(1.0);
        _digitCardBorderWidth = 3.4;
        [self applyClockTransforms];
        [self applyDigitCardOpacity];
        [self applyDigitCardBorderStyle];
    } else if (_editTarget == IWEditTargetDate) {
        _clockOffsetX = IWClockDefaultOffsetX();
        _clockOffsetY = IWClockDefaultOffsetY();
        _clockScale = IWClockDefaultScale();
        _dateOffsetX = IWDateDefaultOffsetX();
        _dateOffsetY = IWDateDefaultOffsetY();
        _dateScale = IWDateDefaultScale();
        _digitCardOpacity = IWDigitCardDefaultOpacity();
        [self applyClockTransforms];
        [self applyDigitCardOpacity];
    } else {
        _backgroundX = 0;
        _backgroundY = 0;
        _backgroundZoom = 1.0;
        [self applyBackgroundTransform];
    }
    [self finishEditMode];
}

- (NSArray *)activeSurfaceTouches:(NSSet *)touches event:(UIEvent *)event {
    NSSet *active = [event touchesForView:_surfaceLayer];
    if (![active count]) active = touches;
    return [active allObjects];
}

- (CGFloat)distanceBetweenTouch:(UITouch *)a andTouch:(UITouch *)b {
    CGPoint pa = [a locationInView:self.view];
    CGPoint pb = [b locationInView:self.view];
    CGFloat dx = pa.x - pb.x;
    CGFloat dy = pa.y - pb.y;
    return sqrt(dx * dx + dy * dy);
}

- (CGPoint)midpointBetweenTouch:(UITouch *)a andTouch:(UITouch *)b {
    CGPoint pa = [a locationInView:self.view];
    CGPoint pb = [b locationInView:self.view];
    return CGPointMake((pa.x + pb.x) / 2.0, (pa.y + pb.y) / 2.0);
}

- (void)resetSurfaceTouchState {
    _surfaceTouchActive = NO;
    _surfaceGestureIgnored = NO;
    _surfaceMultiTouchIgnored = NO;
    _surfaceIntent = @"";
    _pullReady = NO;
    _editStartDistance = 0;
}

- (void)markSurfaceMultiTouchIgnored {
    _surfaceMultiTouchIgnored = YES;
    _lastMultiTouchAt = CFAbsoluteTimeGetCurrent();
    _surfaceIntent = @"pinch";
    _pullReady = NO;
    [self setPullOffset:0.0 ready:NO];
}

- (BOOL)recentSurfaceMultiTouch {
    return _surfaceMultiTouchIgnored || (_lastMultiTouchAt > 0 && CFAbsoluteTimeGetCurrent() - _lastMultiTouchAt < 0.70);
}

- (BOOL)surfaceActionWasJustHandled {
    return _lastSurfaceActionAt > 0 && CFAbsoluteTimeGetCurrent() - _lastSurfaceActionAt < 0.28;
}

- (void)markSurfaceActionHandled:(NSString *)source {
    _lastSurfaceActionAt = CFAbsoluteTimeGetCurrent();
    if ([source length]) [self appendTouchDebug:[NSString stringWithFormat:@"action %@", source]];
}

- (void)prepareCurrentEditDragBaselineAtPoint:(CGPoint)p {
    _surfaceStart = p;
    _surfaceIntent = @"";
    _pullReady = NO;
    _surfaceGestureIgnored = NO;
    if (_editTarget == IWEditTargetClock) {
        _editStartX = _clockOffsetX;
        _editStartY = _clockOffsetY;
        _editStartZoom = _clockScale;
    } else if (_editTarget == IWEditTargetDate) {
        _editStartX = _dateOffsetX;
        _editStartY = _dateOffsetY;
        _editStartZoom = _dateScale;
    } else if (_editTarget == IWEditTargetCalendar) {
        _editStartX = _calendarOffsetX;
        _editStartY = _calendarOffsetY;
        _editStartZoom = _calendarScale;
    } else if (_editTarget == IWEditTargetWeather) {
        _editStartX = _weatherOffsetX;
        _editStartY = _weatherOffsetY;
        _editStartZoom = _weatherScale;
    } else {
        _editStartX = _backgroundX;
        _editStartY = _backgroundY;
        _editStartZoom = _backgroundZoom;
    }
}

- (void)selectClockOrDateEditTargetAtPoint:(CGPoint)p {
    if (!_editMode || (_editTarget != IWEditTargetClock && _editTarget != IWEditTargetDate)) return;
    IWEditTarget target = _editTarget;
    if ([self pointHitsView:_dateLabel rootPoint:p]) target = IWEditTargetDate;
    else if ([self pointHitsVisibleClockDigit:p]) target = IWEditTargetClock;
    if (target == _editTarget) return;
    _editTarget = target;
    [self updateOpacityControlVisibility];
}

- (void)appendTouchDebug:(NSString *)message {
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) {
        _debugLabel.hidden = YES;
        return;
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message ?: @""];
    NSString *path = @"/tmp/wizardsystem-touch.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) {
        _debugLabel.hidden = NO;
        _debugLabel.text = message;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideTouchDebug) object:nil];
        [self performSelector:@selector(hideTouchDebug) withObject:nil afterDelay:0.7];
    }
}

- (void)hideTouchDebug {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) {
        _debugLabel.hidden = NO;
        _debugLabel.text = @"TOUCH DEBUG READY";
    } else {
        _debugLabel.hidden = YES;
    }
}

- (void)surfaceTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_videoOverlay && !_videoOverlay.hidden) return;
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]]) return;
    NSArray *active = [self activeSurfaceTouches:touches event:event];
    if (![active count]) return;
    UITouch *first = [active objectAtIndex:0];
    CGPoint p = [first locationInView:self.view];
    if ([self touchIsInsideCalendarPanel:first]) {
        _surfaceGestureIgnored = YES;
        _surfaceTouchActive = NO;
        [self appendTouchDebug:@"calendar-touch blocked from root surface"];
        return;
    }
    if ([self touchIsInsideWeatherPanel:first]) {
        _surfaceGestureIgnored = YES;
        _surfaceTouchActive = NO;
        [self appendTouchDebug:@"weather-touch blocked from root surface"];
        return;
    }
    _surfaceGestureIgnored = [self isControlPoint:p] || [self isSystemGestureEdgePoint:p];
    [self appendTouchDebug:[NSString stringWithFormat:@"begin x=%.1f y=%.1f active=%lu ignored=%d edit=%d", p.x, p.y, (unsigned long)[active count], _surfaceGestureIgnored, _editMode]];
    if (_surfaceGestureIgnored) return;
    _surfaceTouchActive = YES;
    _surfaceStart = p;
    _surfaceIntent = @"";
    _pullReady = NO;
    if (!_editMode && [active count] >= 2) {
        [self markSurfaceMultiTouchIgnored];
        return;
    }
    [self selectClockOrDateEditTargetAtPoint:p];
    if (_editMode && _editTarget == IWEditTargetClock) {
        _editStartX = _clockOffsetX;
        _editStartY = _clockOffsetY;
        _editStartZoom = _clockScale;
    } else if (_editMode && _editTarget == IWEditTargetDate) {
        _editStartX = _dateOffsetX;
        _editStartY = _dateOffsetY;
        _editStartZoom = _dateScale;
    } else if (_editMode && _editTarget == IWEditTargetCalendar) {
        _editStartX = _calendarOffsetX;
        _editStartY = _calendarOffsetY;
        _editStartZoom = _calendarScale;
    } else if (_editMode && _editTarget == IWEditTargetWeather) {
        _editStartX = _weatherOffsetX;
        _editStartY = _weatherOffsetY;
        _editStartZoom = _weatherScale;
    } else {
        _editStartX = _backgroundX;
        _editStartY = _backgroundY;
        _editStartZoom = _backgroundZoom;
    }
    if (_editMode && [active count] >= 2) {
        UITouch *second = [active objectAtIndex:1];
        _surfaceIntent = @"pinch";
        _editStartDistance = MAX(1.0, [self distanceBetweenTouch:first andTouch:second]);
        _editStartMidpoint = [self midpointBetweenTouch:first andTouch:second];
    }
}

- (void)surfaceTouchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_surfaceTouchActive || _surfaceGestureIgnored) return;
    NSArray *active = [self activeSurfaceTouches:touches event:event];
    if (![active count]) return;
    if (!_editMode && [active count] >= 2) {
        [self markSurfaceMultiTouchIgnored];
        return;
    }
    UITouch *first = [active objectAtIndex:0];
    CGPoint p = [first locationInView:self.view];

    if (_editMode && [active count] >= 2) {
        UITouch *second = [active objectAtIndex:1];
        if (![_surfaceIntent isEqualToString:@"pinch"]) {
            _surfaceIntent = @"pinch";
            if (_editTarget == IWEditTargetClock) {
                _editStartX = _clockOffsetX;
                _editStartY = _clockOffsetY;
                _editStartZoom = _clockScale;
            } else if (_editTarget == IWEditTargetDate) {
                _editStartX = _dateOffsetX;
                _editStartY = _dateOffsetY;
                _editStartZoom = _dateScale;
            } else if (_editTarget == IWEditTargetCalendar) {
                _editStartX = _calendarOffsetX;
                _editStartY = _calendarOffsetY;
                _editStartZoom = _calendarScale;
            } else if (_editTarget == IWEditTargetWeather) {
                _editStartX = _weatherOffsetX;
                _editStartY = _weatherOffsetY;
                _editStartZoom = _weatherScale;
            } else {
                _editStartX = _backgroundX;
                _editStartY = _backgroundY;
                _editStartZoom = _backgroundZoom;
            }
            _editStartDistance = MAX(1.0, [self distanceBetweenTouch:first andTouch:second]);
            _editStartMidpoint = [self midpointBetweenTouch:first andTouch:second];
        }
        CGFloat distance = MAX(1.0, [self distanceBetweenTouch:first andTouch:second]);
        CGPoint midpoint = [self midpointBetweenTouch:first andTouch:second];
        CGFloat nextScale = _editStartZoom * (distance / _editStartDistance);
        if (_editTarget == IWEditTargetClock) {
            _clockScale = MAX(IWClockScaleMin(), MIN(IWClockScaleMax(), nextScale));
            _clockOffsetX = _editStartX + midpoint.x - _editStartMidpoint.x;
            _clockOffsetY = _editStartY + midpoint.y - _editStartMidpoint.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetDate) {
            _dateScale = MAX(IWDateScaleMin(), MIN(IWDateScaleMax(), nextScale));
            _dateOffsetX = _editStartX + midpoint.x - _editStartMidpoint.x;
            _dateOffsetY = _editStartY + midpoint.y - _editStartMidpoint.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetCalendar) {
            _calendarScale = MAX(IWCalendarScaleMin(), MIN(IWCalendarScaleMax(), nextScale));
            _calendarOffsetX = _editStartX + midpoint.x - _editStartMidpoint.x;
            _calendarOffsetY = _editStartY + midpoint.y - _editStartMidpoint.y;
            [self applyCalendarTransform];
        } else if (_editTarget == IWEditTargetWeather) {
            _weatherScale = MAX(IWWeatherScaleMin(), MIN(IWWeatherScaleMax(), nextScale));
            _weatherOffsetX = _editStartX + midpoint.x - _editStartMidpoint.x;
            _weatherOffsetY = _editStartY + midpoint.y - _editStartMidpoint.y;
            [self applyWeatherTransform];
        } else {
            _backgroundZoom = MAX(1.0, MIN(3.0, nextScale));
            _backgroundX = _editStartX + midpoint.x - _editStartMidpoint.x;
            _backgroundY = _editStartY + midpoint.y - _editStartMidpoint.y;
            [self applyBackgroundTransform];
        }
        return;
    }

    CGPoint t = CGPointMake(p.x - _surfaceStart.x, p.y - _surfaceStart.y);
    if (_editMode) {
        CGPoint editDelta = CGPointMake(t.x * IWEditDragGain(), t.y * IWEditDragGain());
        if (_editTarget == IWEditTargetClock) {
            _clockOffsetX = _editStartX + editDelta.x;
            _clockOffsetY = _editStartY + editDelta.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetDate) {
            _dateOffsetX = _editStartX + editDelta.x;
            _dateOffsetY = _editStartY + editDelta.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetCalendar) {
            _calendarOffsetX = _editStartX + editDelta.x;
            _calendarOffsetY = _editStartY + editDelta.y;
            [self applyCalendarTransform];
        } else if (_editTarget == IWEditTargetWeather) {
            _weatherOffsetX = _editStartX + editDelta.x;
            _weatherOffsetY = _editStartY + editDelta.y;
            [self applyWeatherTransform];
        } else {
            _backgroundX = _editStartX + t.x;
            _backgroundY = _editStartY + t.y;
            [self applyBackgroundTransform];
        }
        [self appendTouchDebug:[NSString stringWithFormat:@"edit-drag dx=%.1f dy=%.1f", t.x, t.y]];
        return;
    }
    if (![self recentSurfaceMultiTouch]) [self updateSurfacePull:t];
}

- (void)surfaceTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_surfaceTouchActive || _surfaceGestureIgnored) {
        [self resetSurfaceTouchState];
        return;
    }
    UITouch *touch = [touches anyObject];
    CGPoint p = touch ? [touch locationInView:self.view] : _surfaceStart;
    CGPoint t = CGPointMake(p.x - _surfaceStart.x, p.y - _surfaceStart.y);
    [self appendTouchDebug:[NSString stringWithFormat:@"end dx=%.1f dy=%.1f intent=%@ pull=%d edit=%d", t.x, t.y, _surfaceIntent ?: @"", _pullReady, _editMode]];
    if (_editMode) {
        if (_editTarget == IWEditTargetBackground) [self applyBackgroundTransform];
        [self applyClockTransforms];
        [self applyCalendarTransform];
        [self applyWeatherTransform];
        [self persistCurrentEditValues];
        [self writeDebugState:@"edit-touch-persist"];
        [self resetSurfaceTouchState];
        return;
    }
    if ([self recentSurfaceMultiTouch]) {
        [self setPullOffset:0.0 ready:NO];
        [self resetSurfaceTouchState];
        return;
    }
    [self handleSurfaceSwipe:t];
    [self resetSurfaceTouchState];
}

- (void)surfaceTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    (void)touches;
    (void)event;
    _panFallbackTracking = NO;
    if (!_pullRefreshing) [self resetPullIndicator];
    [self resetSurfaceTouchState];
    [self writeDebugState:(_editMode ? @"edit-touch-cancel" : @"surface-touch-cancel")];
}

- (void)handleBackgroundPan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        [self surfaceTouchesCancelled:nil withEvent:nil];
        return;
    }
    if (_videoOverlay && !_videoOverlay.hidden) {
        _panFallbackTracking = NO;
        [self resetSurfaceTouchState];
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (!_editMode && [recognizer numberOfTouches] >= 2) {
            _panFallbackTracking = NO;
            [self markSurfaceMultiTouchIgnored];
            return;
        }
        if (_surfaceTouchActive) {
            _panFallbackTracking = NO;
            return;
        }
        _panFallbackTracking = YES;
        CGPoint p = [recognizer locationInView:self.view];
        if ([self pointHitsView:_calendarPanel rootPoint:p] || [self pointHitsView:_weatherPanel rootPoint:p]) {
            _panFallbackTracking = NO;
            [self resetSurfaceTouchState];
            [self appendTouchDebug:@"panel-pan blocked from root fallback"];
            return;
        }
        _surfaceGestureIgnored = [self isControlPoint:p] || [self isSystemGestureEdgePoint:p];
        _surfaceStart = p;
        _surfaceIntent = @"";
        _pullReady = NO;
        [self selectClockOrDateEditTargetAtPoint:p];
        if (_editMode && _editTarget == IWEditTargetClock) {
            _editStartX = _clockOffsetX;
            _editStartY = _clockOffsetY;
        } else if (_editMode && _editTarget == IWEditTargetDate) {
            _editStartX = _dateOffsetX;
            _editStartY = _dateOffsetY;
        } else if (_editMode && _editTarget == IWEditTargetCalendar) {
            _editStartX = _calendarOffsetX;
            _editStartY = _calendarOffsetY;
        } else if (_editMode && _editTarget == IWEditTargetWeather) {
            _editStartX = _weatherOffsetX;
            _editStartY = _weatherOffsetY;
        } else {
            _editStartX = _backgroundX;
            _editStartY = _backgroundY;
        }
        [self appendTouchDebug:[NSString stringWithFormat:@"pan-begin ignored=%d edit=%d", _surfaceGestureIgnored, _editMode]];
    }
    if (_surfaceTouchActive) {
        _panFallbackTracking = NO;
        return;
    }
    if (!_panFallbackTracking) return;
    if (!_editMode && [recognizer numberOfTouches] >= 2) {
        _panFallbackTracking = NO;
        [self markSurfaceMultiTouchIgnored];
        return;
    }
    if (_surfaceGestureIgnored) {
        if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
            _panFallbackTracking = NO;
            _surfaceGestureIgnored = NO;
            _surfaceIntent = @"";
            _pullReady = NO;
        }
        return;
    }
    CGPoint t = [recognizer translationInView:self.view];
    if (_editMode) {
        if (_editTarget == IWEditTargetCalendar) {
            CGPoint editDelta = CGPointMake(t.x * IWEditDragGain(), t.y * IWEditDragGain());
            _calendarOffsetX = _editStartX + editDelta.x;
            _calendarOffsetY = _editStartY + editDelta.y;
            [self applyCalendarTransform];
            if (recognizer.state == UIGestureRecognizerStateEnded) {
                [self persistCurrentEditValues];
                [self writeDebugState:@"calendar-edit-pan-persist"];
            }
            if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
                _panFallbackTracking = NO;
                [self resetSurfaceTouchState];
            }
            return;
        }
        CGPoint editDelta = CGPointMake(t.x * IWEditDragGain(), t.y * IWEditDragGain());
        if (_editTarget == IWEditTargetClock) {
            _clockOffsetX = _editStartX + editDelta.x;
            _clockOffsetY = _editStartY + editDelta.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetDate) {
            _dateOffsetX = _editStartX + editDelta.x;
            _dateOffsetY = _editStartY + editDelta.y;
            [self applyClockTransforms];
        } else if (_editTarget == IWEditTargetWeather) {
            _weatherOffsetX = _editStartX + editDelta.x;
            _weatherOffsetY = _editStartY + editDelta.y;
            [self applyWeatherTransform];
        } else {
            _backgroundX = _editStartX + t.x;
            _backgroundY = _editStartY + t.y;
            [self applyBackgroundTransform];
        }
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            [self persistCurrentEditValues];
            [self writeDebugState:@"edit-pan-persist"];
            _panFallbackTracking = NO;
            [self resetSurfaceTouchState];
        } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
            [self writeDebugState:@"edit-pan-cancel"];
            _panFallbackTracking = NO;
            [self resetSurfaceTouchState];
        }
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        [self updateSurfacePull:t];
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self appendTouchDebug:[NSString stringWithFormat:@"pan-end dx=%.1f dy=%.1f intent=%@ pull=%d edit=%d", t.x, t.y, _surfaceIntent ?: @"", _pullReady, _editMode]];
        if (_editMode) {
            [self persistCurrentEditValues];
            [self writeDebugState:@"edit-pan-persist"];
        }
        if (![self recentSurfaceMultiTouch]) [self handleSurfaceSwipe:t];
        _panFallbackTracking = NO;
        [self resetSurfaceTouchState];
    }
}

- (void)handleBackgroundPinch:(UIPinchGestureRecognizer *)recognizer {
    CGPoint p = [recognizer locationInView:self.view];
    if ([self pointHitsView:_calendarPanel rootPoint:p] || [self pointHitsView:_weatherPanel rootPoint:p]) return;
    if (!_editMode) {
        [self markSurfaceMultiTouchIgnored];
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (_editTarget == IWEditTargetClock) _editStartZoom = _clockScale;
        else if (_editTarget == IWEditTargetDate) _editStartZoom = _dateScale;
        else if (_editTarget == IWEditTargetCalendar) _editStartZoom = _calendarScale;
        else if (_editTarget == IWEditTargetWeather) _editStartZoom = _weatherScale;
        else _editStartZoom = _backgroundZoom;
    }
    CGFloat nextScale = _editStartZoom * recognizer.scale;
    if (_editTarget == IWEditTargetClock) {
        _clockScale = MAX(IWClockScaleMin(), MIN(IWClockScaleMax(), nextScale));
        [self applyClockTransforms];
    } else if (_editTarget == IWEditTargetDate) {
        _dateScale = MAX(IWDateScaleMin(), MIN(IWDateScaleMax(), nextScale));
        [self applyClockTransforms];
    } else if (_editTarget == IWEditTargetCalendar) {
        _calendarScale = MAX(IWCalendarScaleMin(), MIN(IWCalendarScaleMax(), nextScale));
        [self applyCalendarTransform];
    } else if (_editTarget == IWEditTargetWeather) {
        _weatherScale = MAX(IWWeatherScaleMin(), MIN(IWWeatherScaleMax(), nextScale));
        [self applyWeatherTransform];
    } else {
        _backgroundZoom = MAX(1.0, MIN(3.0, nextScale));
        [self applyBackgroundTransform];
    }
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self persistCurrentEditValues];
        [self writeDebugState:@"edit-pinch-persist"];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        [self writeDebugState:@"edit-pinch-cancel"];
    }
}

- (void)handleSurfaceTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;
    if ([self surfaceActionWasJustHandled]) return;
    if (_editMode || _menuOpen || (_videoOverlay && !_videoOverlay.hidden)) return;
    CGPoint p = [recognizer locationInView:self.view];
    if ([self isControlPoint:p]) return;
    _controlsHidden = !_controlsHidden;
    _menuButton.hidden = _controlsHidden;
    [self markSurfaceActionHandled:@"gesture-tap"];
    [self writeDebugState:@"gesture-tap"];
}

- (BOOL)pointHitsView:(UIView *)view rootPoint:(CGPoint)p {
    if (!view || view.hidden || view.alpha < 0.01) return NO;
    CGPoint local = [self.view convertPoint:p toView:view];
    return CGRectContainsPoint(view.bounds, local);
}

- (BOOL)pointHitsVisibleClockDigit:(CGPoint)p {
    if (![self pointHitsView:_digitGroup rootPoint:p]) return NO;
    for (UIView *digit in _digitLabels) {
        if (!digit.hidden && [self pointHitsView:digit rootPoint:p]) return YES;
    }
    for (UIView *digit in _countdownDayLabels) {
        if (!digit.hidden && [self pointHitsView:digit rootPoint:p]) return YES;
    }
    for (UIView *colon in _colonViews) {
        if (!colon.hidden && [self pointHitsView:colon rootPoint:p]) return YES;
    }
    return NO;
}

- (void)handleBackgroundLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    if (_editMode || (_videoOverlay && !_videoOverlay.hidden)) return;
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]]) return;
    CGPoint p = [recognizer locationInView:self.view];
    [self appendTouchDebug:[NSString stringWithFormat:@"root-longpress x=%.1f y=%.1f calendar=%d", p.x, p.y, [self pointHitsView:_calendarPanel rootPoint:p]]];
    if ([self pointHitsView:_calendarPanel rootPoint:p]) {
        [self resetPullIndicator];
        [self enterCalendarEditMode];
        [self prepareCurrentEditDragBaselineAtPoint:p];
        [self markSurfaceActionHandled:@"longpress-calendar-edit"];
        [self writeDebugState:@"longpress-calendar-edit"];
        return;
    }
    if ([self pointHitsView:_weatherPanel rootPoint:p]) {
        [self resetPullIndicator];
        [self enterWeatherEditMode];
        [self prepareCurrentEditDragBaselineAtPoint:p];
        [self markSurfaceActionHandled:@"longpress-weather-edit"];
        [self writeDebugState:@"longpress-weather-edit"];
        return;
    }
    if (_menuOpen || [self isControlPoint:p]) return;
    [self resetPullIndicator];
    if ([self pointHitsView:_dateLabel rootPoint:p]) {
        [self enterDateEditMode];
        [self prepareCurrentEditDragBaselineAtPoint:p];
        [self markSurfaceActionHandled:@"longpress-date-edit"];
        [self writeDebugState:@"longpress-date-edit"];
    } else if ([self pointHitsVisibleClockDigit:p]) {
        [self enterClockEditMode];
        [self prepareCurrentEditDragBaselineAtPoint:p];
        [self markSurfaceActionHandled:@"longpress-clock-edit"];
        [self writeDebugState:@"longpress-clock-edit"];
    } else {
        [self enterEditMode];
        [self prepareCurrentEditDragBaselineAtPoint:p];
        [self markSurfaceActionHandled:@"longpress-edit"];
        [self writeDebugState:@"longpress-edit"];
    }
}

- (BOOL)isControlPoint:(CGPoint)p {
    if (_editToolbar && !_editToolbar.hidden && CGRectContainsPoint(_editToolbar.frame, p)) return YES;
    if (_opacityControl && !_opacityControl.hidden && CGRectContainsPoint(_opacityControl.frame, p)) return YES;
    if (_borderControl && !_borderControl.hidden && CGRectContainsPoint(_borderControl.frame, p)) return YES;
    if (_menuButton && !_menuButton.hidden && CGRectContainsPoint(_menuButton.frame, p)) return YES;
    if (_menu && !_menu.hidden && CGRectContainsPoint(_menu.frame, p)) return YES;
    if (_settingsMenu && !_settingsMenu.hidden && CGRectContainsPoint(_settingsMenu.frame, p)) return YES;
    if (_weatherPanel && !_weatherPanel.hidden && [self pointHitsView:_weatherPanel rootPoint:p]) return YES;
    if (!_editMode && _homePanel && !_homePanel.hidden && CGRectContainsPoint(_homePanel.frame, p)) return YES;
    return NO;
}

- (BOOL)isSystemGestureEdgePoint:(CGPoint)p {
    if (_editMode) return NO;
    CGFloat edge = IWSystemGestureEdgeInset();
    CGFloat height = self.view.bounds.size.height;
    return p.y <= edge || p.y >= height - edge;
}

- (BOOL)touchIsInsideCalendarPanel:(UITouch *)touch {
    UIView *view = touch.view;
    while (view) {
        if (view == _calendarPanel) return YES;
        view = view.superview;
    }
    return NO;
}

- (BOOL)touchIsInsideWeatherPanel:(UITouch *)touch {
    UIView *view = touch.view;
    while (view) {
        if (view == _weatherPanel) return YES;
        view = view.superview;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (![gestureRecognizer.view isDescendantOfView:self.view]) return YES;
    if (gestureRecognizer.view == _weatherPanel && [touch.view isDescendantOfView:_weatherProviderButton]) return NO;
    // Calendar editing owns every touch that begins inside the calendar panel.
    // Without this gate, the root background pan/pinch can win recognizer
    // arbitration and move the wallpaper instead of the calendar.
    if (gestureRecognizer.view == self.view && [self touchIsInsideCalendarPanel:touch]) {
        [self appendTouchDebug:@"calendar-touch routed away from root gesture"];
        return NO;
    }
    if (gestureRecognizer.view == self.view && [self touchIsInsideWeatherPanel:touch]) {
        [self appendTouchDebug:@"weather-touch routed away from root gesture"];
        return NO;
    }
    if (![gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] &&
        ![gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]]) return YES;
    CGPoint p = [touch locationInView:self.view];
    if ([self isSystemGestureEdgePoint:p]) {
        [self appendTouchDebug:[NSString stringWithFormat:@"system-edge ignored x=%.1f y=%.1f", p.x, p.y]];
        return NO;
    }
    return YES;
}

- (BOOL)canHandleApplicationSurfaceTouchAtPoint:(CGPoint)point {
    if (_editMode || (_videoOverlay && !_videoOverlay.hidden)) return NO;
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]]) return NO;
    if ([self isSystemGestureEdgePoint:point]) return NO;
    if ([self pointHitsView:_calendarPanel rootPoint:point]) return NO;
    if ([self pointHitsView:_weatherPanel rootPoint:point]) return NO;
    return ![self isControlPoint:point];
}

- (void)handleApplicationSurfaceSwipeFrom:(CGPoint)start to:(CGPoint)end {
    if ([self pointHitsView:_calendarPanel rootPoint:start] || [self pointHitsView:_calendarPanel rootPoint:end] ||
        [self pointHitsView:_weatherPanel rootPoint:start] || [self pointHitsView:_weatherPanel rootPoint:end]) return;
    if (![self canHandleApplicationSurfaceTouchAtPoint:start]) return;
    if ([self isControlPoint:end]) return;
    if ([self surfaceActionWasJustHandled]) return;
    if ([self recentSurfaceMultiTouch]) return;
    CGPoint delta = CGPointMake(end.x - start.x, end.y - start.y);
    [self appendTouchDebug:[NSString stringWithFormat:@"app-fallback dx=%.1f dy=%.1f", delta.x, delta.y]];
    [self handleSurfaceSwipe:delta];
}

- (void)setPullOffset:(CGFloat)value ready:(BOOL)ready {
    CGFloat top = 18.0 - 64.0 + value;
    _pullIndicator.hidden = value <= 0.0 && !ready;
    _pullIndicator.alpha = value <= 0.0 ? 0.0 : 1.0;
    _pullIndicator.frame = CGRectMake((self.view.bounds.size.width - IWControlSize()) / 2.0, top, IWControlSize(), IWControlSize());
    _pullIndicator.backgroundColor = IWThemePink(0.72);
    _pullIndicator.layer.borderWidth = IWControlBorderWidth();
    _pullIndicator.layer.borderColor = [[UIColor colorWithRed:1.0 green:249.0/255.0 blue:238.0/255.0 alpha:(ready ? 0.86 : 0.68)] CGColor];
}

- (void)startPullIndicatorSpin {
    [_pullIndicator.layer removeAnimationForKey:@"iw-refresh-spin"];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0.0;
    spin.toValue = @(M_PI * 2.0);
    spin.duration = 0.65;
    spin.repeatCount = HUGE_VALF;
    spin.removedOnCompletion = NO;
    [_pullIndicator.layer addAnimation:spin forKey:@"iw-refresh-spin"];
}

- (void)stopPullIndicatorSpin {
    [_pullIndicator.layer removeAnimationForKey:@"iw-refresh-spin"];
}

- (void)resetPullIndicator {
    _pullReady = NO;
    _pullRefreshing = NO;
    _surfaceIntent = @"";
    [UIView animateWithDuration:0.18 animations:^{
        [self setPullOffset:0.0 ready:NO];
    } completion:^(BOOL finished) {
        if (!_pullRefreshing) {
            [self stopPullIndicatorSpin];
            _pullIndicator.hidden = YES;
        }
    }];
}

- (void)finishPullRefresh {
    [self resetPullIndicator];
}

- (void)triggerPullRefresh {
    [self setPullOffset:64.0 ready:YES];
    _pullRefreshing = YES;
    [self startPullIndicatorSpin];
    [self refreshSurfaceData];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishPullRefresh) object:nil];
    [self performSelector:@selector(finishPullRefresh) withObject:nil afterDelay:2.00];
}

- (void)updateSurfacePull:(CGPoint)t {
    if ([self recentSurfaceMultiTouch]) {
        [self setPullOffset:0.0 ready:NO];
        return;
    }
    CGFloat dx = t.x;
    CGFloat dy = t.y;
    CGFloat absX = fabs(dx);
    CGFloat absY = fabs(dy);
    if ([_surfaceIntent length] == 0 && (absX > 8.0 || absY > 8.0)) {
        _surfaceIntent = absY > absX * 1.08 ? @"vertical" : @"horizontal";
    }
    if (![_surfaceIntent isEqualToString:@"vertical"]) {
        if ([_surfaceIntent length] > 0) [self setPullOffset:0.0 ready:NO];
        return;
    }
    if (dy > 0.0) {
        CGFloat pullAmount = MIN(64.0, round(dy * 0.48));
        _pullReady = pullAmount >= 46.0;
        [self setPullOffset:pullAmount ready:_pullReady];
    } else {
        _pullReady = NO;
        [self setPullOffset:0.0 ready:NO];
    }
}

- (NSArray *)activeWallpaperOrder {
    return [self displayItems];
}

- (void)stepWallpaper:(NSInteger)direction {
    NSArray *items = [self activeWallpaperOrder];
    if (![items count]) return;
    NSInteger position = 0;
    NSInteger i;
    for (i = 0; i < [items count]; i += 1) {
        NSInteger original = [[[items objectAtIndex:i] objectForKey:@"index"] integerValue];
        if (original == _wallpaperIndex) {
            position = i;
            break;
        }
    }
    NSInteger next = (position + direction + [items count]) % [items count];
    NSInteger originalIndex = [[[items objectAtIndex:next] objectForKey:@"index"] integerValue];
    [self selectWallpaper:originalIndex slideDirection:direction];
}

- (void)refreshSurfaceData {
    NSString *currentKey = [[self wallpaperKey] copy];
    [self loadWallpapers];
    if ([currentKey length]) {
        NSInteger i;
        for (i = 0; i < [_wallpapers count]; i += 1) {
            NSString *key = [[_wallpapers objectAtIndex:i] objectForKey:@"key"];
            if ([key isEqualToString:currentKey]) {
                _wallpaperIndex = i;
                break;
            }
        }
    }
    [self loadHomeStatus];
    [self loadCastStatus];
    [self applyWallpaper];
    [self saveState];
}

- (void)handleSurfaceSwipe:(CGPoint)t {
    if ([self recentSurfaceMultiTouch]) {
        [self setPullOffset:0.0 ready:NO];
        return;
    }
    if ([self surfaceActionWasJustHandled]) {
        if (!_pullRefreshing) [self resetPullIndicator];
        return;
    }
    CGFloat dx = t.x;
    CGFloat dy = t.y;
    CGFloat absX = fabs(dx);
    CGFloat absY = fabs(dy);
    if (_pullReady) {
        _controlsHidden = NO;
        _menuButton.hidden = NO;
        [self markSurfaceActionHandled:@"pull"];
        [self triggerPullRefresh];
        [self writeDebugState:@"surface-pull"];
        return;
    }
    [self resetPullIndicator];
    if (absX <= 12.0 && absY <= 12.0 && !_menuOpen && !_editMode) {
        _controlsHidden = !_controlsHidden;
        _menuButton.hidden = _controlsHidden;
        [self markSurfaceActionHandled:@"tap"];
        [self writeDebugState:@"surface-tap"];
        return;
    }
    if (absY > absX * 1.18 && dy < -72.0) {
        _controlsHidden = NO;
        _menuButton.hidden = NO;
        [self markSurfaceActionHandled:@"up"];
        [self openGallery];
        [self writeDebugState:@"surface-up"];
        return;
    }
    if (absY > absX * 1.18 && dy > 72.0) {
        _controlsHidden = NO;
        _menuButton.hidden = NO;
        [self markSurfaceActionHandled:@"down"];
        [self triggerPullRefresh];
        [self writeDebugState:@"surface-down"];
        return;
    }
    if (absX > absY * 1.35 && absX > 96.0) {
        _controlsHidden = NO;
        _menuButton.hidden = NO;
        [self markSurfaceActionHandled:(dx < 0 ? @"left" : @"right")];
        [self stepWallpaper:(dx < 0 ? 1 : -1)];
        [self writeDebugState:(dx < 0 ? @"surface-left" : @"surface-right")];
    }
}

- (void)handleSurfaceSwipeGesture:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;
    if ([self surfaceActionWasJustHandled]) return;
    if ([self recentSurfaceMultiTouch]) return;
    if (_editMode || (_videoOverlay && !_videoOverlay.hidden) || (self.presentedViewController && [self.presentedViewController isKindOfClass:[IWGalleryController class]])) return;
    CGPoint p = [recognizer locationInView:self.view];
    if ([self pointHitsView:_calendarPanel rootPoint:p]) return;
    if ([self isSystemGestureEdgePoint:p]) return;
    if ([self isControlPoint:p]) return;
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    [self resetPullIndicator];
    if (recognizer.direction == UISwipeGestureRecognizerDirectionUp) {
        [self markSurfaceActionHandled:@"swipe-up"];
        [self openGallery];
        [self writeDebugState:@"gesture-up"];
    } else if (recognizer.direction == UISwipeGestureRecognizerDirectionDown) {
        [self markSurfaceActionHandled:@"swipe-down"];
        [self triggerPullRefresh];
        [self writeDebugState:@"gesture-down"];
    } else if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) {
        [self markSurfaceActionHandled:@"swipe-left"];
        [self stepWallpaper:1];
        [self writeDebugState:@"gesture-left"];
    } else if (recognizer.direction == UISwipeGestureRecognizerDirectionRight) {
        [self markSurfaceActionHandled:@"swipe-right"];
        [self stepWallpaper:-1];
        [self writeDebugState:@"gesture-right"];
    }
}

- (void)writeDebugState:(NSString *)context {
    CGRect clipBounds = _backgroundClip ? _backgroundClip.bounds : CGRectZero;
    CGRect bgFrame = _background ? _background.frame : CGRectZero;
    CGRect viewBounds = self.view ? self.view.bounds : CGRectZero;
    UIWindow *window = self.view.window ?: [[UIApplication sharedApplication] keyWindow];
    CGRect windowBounds = window ? window.bounds : CGRectZero;
    UIInterfaceOrientation statusOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    UIViewController *presented = self.presentedViewController;
    BOOL galleryOpen = (presented && [presented isKindOfClass:[IWGalleryController class]]);
    BOOL photoPickerOpen = galleryOpen && (presented.presentedViewController != nil);
    NSDictionary *currentWallpaper = (_wallpaperIndex >= 0 && _wallpaperIndex < [_wallpapers count]) ? [_wallpapers objectAtIndex:_wallpaperIndex] : nil;
    BOOL backgroundCoverageOk = !CGRectIsEmpty(clipBounds) &&
        bgFrame.origin.x <= 0.0 &&
        bgFrame.origin.y <= 0.0 &&
        CGRectGetMaxX(bgFrame) >= clipBounds.size.width &&
        CGRectGetMaxY(bgFrame) >= clipBounds.size.height;
    CGSize remotePresentationSize = (_remoteVideoPlayer && _remoteVideoPlayer.currentItem) ? _remoteVideoPlayer.currentItem.presentationSize : CGSizeZero;
    NSTimeInterval videoCurrentTime = 0.0;
    NSTimeInterval videoDuration = 0.0;
    if (_usingRemoteVideoPlayer && _remoteVideoPlayer) {
        videoCurrentTime = IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime);
        videoDuration = IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentItem.duration);
    } else if (_moviePlayer) {
        videoCurrentTime = IWSecondsSafe(_moviePlayer.currentPlaybackTime);
        videoDuration = IWSecondsSafe(_moviePlayer.duration);
    }
    NSDictionary *state = @{
        @"context": context ?: @"",
        @"buildVersion": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
        @"buildNumber": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
        @"buildChannel": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WizardBuildChannel"] ?: @"",
        @"sourceFingerprint": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WizardSourceFingerprint"] ?: @"unbound",
        @"processID": @(getpid()),
        @"physicalMemoryBytes": @([NSProcessInfo processInfo].physicalMemory),
        @"applicationState": @([UIApplication sharedApplication].applicationState),
        @"windowHidden": @(window.hidden),
        @"videoOverlayAlpha": @(_videoOverlay.alpha),
        @"frameProbeError": _frameProbe.lastError.localizedDescription ?: @"",
        @"wallpaperIndex": [NSNumber numberWithInteger:_wallpaperIndex],
        @"wallpaperCount": [NSNumber numberWithInteger:[_wallpapers count]],
        @"wallpaperFileName": [currentWallpaper objectForKey:@"fileName"] ?: @"",
        @"wallpaperLabel": [currentWallpaper objectForKey:@"label"] ?: @"",
        @"menuOpen": [NSNumber numberWithBool:_menuOpen],
        @"cleanMode": [NSNumber numberWithBool:_cleanMode],
        @"showSeconds": [NSNumber numberWithBool:_showSeconds],
        @"gta6CountdownMode": [NSNumber numberWithBool:_gta6CountdownMode],
        @"hour24": [NSNumber numberWithBool:_hour24],
        @"dateLanguage": [NSNumber numberWithInteger:_dateLanguage],
        @"dateLanguageLabel": [self dateLanguageLabel],
        @"homeVisible": [NSNumber numberWithBool:_homeVisible],
        @"homePanelHidden": [NSNumber numberWithBool:(_homePanel == nil || _homePanel.hidden)],
        @"weatherVisible": [NSNumber numberWithBool:_weatherVisible],
        @"weatherPanelHidden": [NSNumber numberWithBool:(_weatherPanel == nil || _weatherPanel.hidden)],
        @"weatherLoading": [NSNumber numberWithBool:_weatherLoading],
        @"weatherError": [NSNumber numberWithBool:_weatherError],
        @"weatherCity": _weatherCity ?: @"",
        @"weatherTemperature": [_weatherSnapshot objectForKey:@"temperature"] ?: @0,
        @"weatherCode": [_weatherSnapshot objectForKey:@"code"] ?: @0,
        @"weatherProvider": [_weatherSnapshot objectForKey:@"provider"] ?: @"",
        @"weatherScale": [NSNumber numberWithFloat:_weatherScale],
        @"weatherOffsetX": [NSNumber numberWithFloat:_weatherOffsetX],
        @"weatherOffsetY": [NSNumber numberWithFloat:_weatherOffsetY],
        @"editMode": [NSNumber numberWithBool:_editMode],
        @"favoriteOnly": [NSNumber numberWithBool:_favoriteOnly],
        @"promoOnly": [NSNumber numberWithBool:_promoOnly],
        @"musicPlaying": [NSNumber numberWithBool:_player.playing],
        @"musicError": [NSNumber numberWithBool:_musicError],
        @"castReady": [NSNumber numberWithBool:([_castSrc length] > 0)],
        @"castServerRunning": [NSNumber numberWithBool:_dlnaCastServer.running],
        @"castServerPort": [NSNumber numberWithUnsignedInteger:_dlnaCastServer.httpPort],
        @"castError": [NSNumber numberWithBool:_castError],
        @"appPowerSleepActive": [NSNumber numberWithBool:_appPowerSleepActive],
        @"powerConnected": [NSNumber numberWithBool:_lastPowerConnected],
        @"powerConnectEnabled": [NSNumber numberWithBool:_powerConnectEnabled],
        @"powerDisconnectEnabled": [NSNumber numberWithBool:_powerDisconnectEnabled],
        @"depthMode": [NSNumber numberWithBool:_depthMode],
        @"editTarget": [NSNumber numberWithInteger:_editTarget],
        @"clockOffsetX": [NSNumber numberWithFloat:_clockOffsetX],
        @"clockOffsetY": [NSNumber numberWithFloat:_clockOffsetY],
        @"clockScale": [NSNumber numberWithFloat:_clockScale],
        @"dateOffsetX": [NSNumber numberWithFloat:_dateOffsetX],
        @"dateOffsetY": [NSNumber numberWithFloat:_dateOffsetY],
        @"dateScale": [NSNumber numberWithFloat:_dateScale],
        @"calendarVisible": [NSNumber numberWithBool:_calendarVisible],
        @"calendarPanelHidden": [NSNumber numberWithBool:(_calendarPanel == nil || _calendarPanel.hidden)],
        @"calendarScale": [NSNumber numberWithFloat:_calendarScale],
        @"calendarOffsetX": [NSNumber numberWithFloat:_calendarOffsetX],
        @"calendarOffsetY": [NSNumber numberWithFloat:_calendarOffsetY],
        @"calendarOpacity": [NSNumber numberWithFloat:_calendarOpacity],
        @"digitCardOpacity": [NSNumber numberWithFloat:_digitCardOpacity],
        @"videoOpen": [NSNumber numberWithBool:(_videoOverlay && !_videoOverlay.hidden)],
        @"videoMinimized": [NSNumber numberWithBool:_videoMinimized],
        @"videoVolumeVisible": [NSNumber numberWithBool:_videoVolumeVisible],
        @"videoCurrentPath": _videoCurrentPath ?: @"",
        @"videoUsesRemotePlayer": [NSNumber numberWithBool:_usingRemoteVideoPlayer],
        @"videoUserPaused": @(_videoUserPaused),
        @"lastLocalVideoFinish": _lastLocalVideoFinish ?: @{},
        @"remoteVideoRate": @(_remoteVideoPlayer.rate),
        @"remoteVideoWidth": [NSNumber numberWithFloat:IWFloatSafe(remotePresentationSize.width)],
        @"remoteVideoHeight": [NSNumber numberWithFloat:IWFloatSafe(remotePresentationSize.height)],
        @"videoCurrentTime": [NSNumber numberWithDouble:videoCurrentTime],
        @"videoDuration": [NSNumber numberWithDouble:videoDuration],
        @"videoPlaybackState": [NSNumber numberWithInteger:(_moviePlayer ? _moviePlayer.playbackState : 0)],
        @"videoLoadState": [NSNumber numberWithInteger:(_moviePlayer ? _moviePlayer.loadState : 0)],
        @"galleryOpen": [NSNumber numberWithBool:galleryOpen],
        @"galleryFilter": galleryOpen ? [(IWGalleryController *)presented categoryDebugState] : @{},
        @"photoPickerOpen": [NSNumber numberWithBool:photoPickerOpen],
        @"statusBarOrientation": [NSNumber numberWithInteger:statusOrientation],
        @"viewBounds": @{
            @"width": [NSNumber numberWithFloat:IWFloatSafe(viewBounds.size.width)],
            @"height": [NSNumber numberWithFloat:IWFloatSafe(viewBounds.size.height)]
        },
        @"windowBounds": @{
            @"width": [NSNumber numberWithFloat:IWFloatSafe(windowBounds.size.width)],
            @"height": [NSNumber numberWithFloat:IWFloatSafe(windowBounds.size.height)]
        },
        @"controlsHidden": [NSNumber numberWithBool:_controlsHidden],
        @"pullIndicatorVisible": [NSNumber numberWithBool:(_pullIndicator && !_pullIndicator.hidden)],
        @"pullRefreshing": [NSNumber numberWithBool:_pullRefreshing],
        @"backgroundX": [NSNumber numberWithFloat:_backgroundX],
        @"backgroundY": [NSNumber numberWithFloat:_backgroundY],
        @"backgroundZoom": [NSNumber numberWithFloat:_backgroundZoom],
        @"backgroundCoverageOk": [NSNumber numberWithBool:backgroundCoverageOk],
        @"backgroundFrame": @{
            @"x": [NSNumber numberWithFloat:bgFrame.origin.x],
            @"y": [NSNumber numberWithFloat:bgFrame.origin.y],
            @"width": [NSNumber numberWithFloat:IWFloatSafe(bgFrame.size.width)],
            @"height": [NSNumber numberWithFloat:IWFloatSafe(bgFrame.size.height)]
        },
        @"backgroundClip": @{
            @"width": [NSNumber numberWithFloat:IWFloatSafe(clipBounds.size.width)],
            @"height": [NSNumber numberWithFloat:IWFloatSafe(clipBounds.size.height)]
        }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (data) [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-state.json"] atomically:YES];
}

- (void)captureDebugScreenshotToPath:(NSString *)path afterDelay:(NSTimeInterval)delay {
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = self.view.window ?: [[UIApplication sharedApplication] keyWindow];
        UIView *target = window ?: self.view;
        CGSize size = target.bounds.size;
        if (size.width <= 0 || size.height <= 0) return;
        UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
        BOOL drawn = NO;
        if ([target respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
            drawn = [target drawViewHierarchyInRect:target.bounds afterScreenUpdates:YES];
        }
        if (!drawn) {
            CGContextRef context = UIGraphicsGetCurrentContext();
            if (context) [target.layer renderInContext:context];
        }
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *png = image ? UIImagePNGRepresentation(image) : nil;
        if (png) {
            [png writeToFile:path atomically:YES];
            [self appendTouchDebug:[NSString stringWithFormat:@"screenshot written %@", [path lastPathComponent]]];
        }
    });
}

- (void)captureDebugLayerScreenshotToPath:(NSString *)path afterDelay:(NSTimeInterval)delay {
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = self.view.window ?: [[UIApplication sharedApplication] keyWindow];
        UIView *target = window ?: self.view;
        CGSize size = target.bounds.size;
        if (size.width <= 0 || size.height <= 0) return;
        UIGraphicsBeginImageContextWithOptions(size, YES, 0.0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (context) [target.layer renderInContext:context];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSData *png = image ? UIImagePNGRepresentation(image) : nil;
        if (png) {
            [png writeToFile:path atomically:YES];
            [self appendTouchDebug:[NSString stringWithFormat:@"layer screenshot written %@", [path lastPathComponent]]];
        }
    });
}

- (void)captureDebugScreenshot {
    [self captureDebugScreenshotToPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-screenshot.png"] afterDelay:0.45];
}

- (void)handleDebugCommand:(NSString *)command {
    NSString *value = [command lowercaseString] ?: @"";
    BOOL shouldWriteCommandState = YES;
    [self appendTouchDebug:[NSString stringWithFormat:@"cmd %@", value]];
    if ([value isEqualToString:@"perf"] || [value isEqualToString:@"perfmenu"] || [value isEqualToString:@"perfgallery"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-performance-debug"] || [[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) {
            if (!_frameProbe) _frameProbe = [[IWFrameProbe alloc] init];
            if (!_frameProbe.running) {
                NSTimeInterval probeDuration = 30.0;
                if ([value isEqualToString:@"perfgallery"]) [self openGallery];
                else if ([value isEqualToString:@"perfmenu"] && !_menuOpen) [self toggleMenu];
                NSString *context = _videoOverlay && !_videoOverlay.hidden ? @"video" : ([self.presentedViewController isKindOfClass:[IWGalleryController class]] ? @"gallery" : (_menuOpen ? @"menu" : @"home"));
                if (![_frameProbe startWithContext:context duration:probeDuration]) {
                    [self writeDebugState:@"probe-start-failed"];
                    return;
                }
                // Capture only after measurement, without another URL activation
                // that would run the normal video lifecycle cleanup.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((probeDuration + 1.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self writeDebugState:[@"probe-" stringByAppendingString:context]];
                    [self captureDebugScreenshot];
                });
            }
        }
    } else if ([value isEqualToString:@"weathercreditstest"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-performance-debug"]) [self runWeatherCreditAudit];
    } else if ([value isEqualToString:@"videotestlocal"] || [value isEqualToString:@"videotestremote"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-performance-debug"]) {
            [self runVideoControlAuditWithLocalVideo:[value isEqualToString:@"videotestlocal"]];
        }
    } else if ([value isEqualToString:@"videopause"] || [value isEqualToString:@"videoresume"] || [value isEqualToString:@"videojump"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-performance-debug"] && (_videoMinimized || (_videoOverlay && !_videoOverlay.hidden))) {
            if ([value isEqualToString:@"videojump"]) {
                NSTimeInterval current = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime) : IWSecondsSafe(_moviePlayer.currentPlaybackTime);
                [self seekVideoToTime:current + 10.0];
            } else if (_videoUserPaused != [value isEqualToString:@"videopause"]) {
                [self videoPlayTapped];
            }
        }
    } else if ([value isEqualToString:@"halock"]) {
        IWPostWizardPowerNotification(IWWizardPowerLockRequestNotification);
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"gallery"] || [value isEqualToString:@"up"]) {
        [self openGallery];
    } else if ([value isEqualToString:@"gallerycategories"]) {
        if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            IWGalleryController *gallery = (IWGalleryController *)self.presentedViewController;
            [gallery categoryTapped];
        }
    } else if ([value hasPrefix:@"gallerycategory"]) {
        if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            [(IWGalleryController *)self.presentedViewController selectCategory:[value substringFromIndex:[@"gallerycategory" length]]];
        }
    } else if ([value isEqualToString:@"galleryadd"]) {
        if (![self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            [self openGallery];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(debugOpenPresentedGalleryPicker) object:nil];
            [self performSelector:@selector(debugOpenPresentedGalleryPicker) withObject:nil afterDelay:0.65];
        } else {
            [(IWGalleryController *)self.presentedViewController debugOpenPhotoPicker];
        }
    } else if ([value isEqualToString:@"pickercancel"]) {
        if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            [(IWGalleryController *)self.presentedViewController debugClosePhotoPicker];
        }
    } else if ([value isEqualToString:@"gallerylocate"]) {
        if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            [(IWGalleryController *)self.presentedViewController locateTapped];
        } else {
            [self openGallery];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locatePresentedGallery) object:nil];
            [self performSelector:@selector(locatePresentedGallery) withObject:nil afterDelay:0.65];
        }
    } else if ([value isEqualToString:@"gallerydelete"]) {
        if (![self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
            [self openGallery];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(debugEnterPresentedGalleryDeleteMode) object:nil];
            [self performSelector:@selector(debugEnterPresentedGalleryDeleteMode) withObject:nil afterDelay:0.65];
        } else {
            [(IWGalleryController *)self.presentedViewController debugEnterDeleteMode];
        }
    } else if ([value isEqualToString:@"swipeup"]) {
        [self handleSurfaceSwipe:CGPointMake(0.0, -120.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"swipedown"]) {
        [self handleSurfaceSwipe:CGPointMake(0.0, 120.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"swipeleft"]) {
        [self handleSurfaceSwipe:CGPointMake(-130.0, 0.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"swiperight"]) {
        [self handleSurfaceSwipe:CGPointMake(130.0, 0.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appfallbackup"]) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
        [self handleApplicationSurfaceSwipeFrom:center to:CGPointMake(center.x, center.y - 120.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appfallbackdown"]) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
        [self handleApplicationSurfaceSwipeFrom:center to:CGPointMake(center.x, center.y + 120.0)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appfallbackleft"]) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
        [self handleApplicationSurfaceSwipeFrom:center to:CGPointMake(center.x - 130.0, center.y)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appfallbackright"]) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
        [self handleApplicationSurfaceSwipeFrom:center to:CGPointMake(center.x + 130.0, center.y)];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"surfacetap"]) {
        [self handleSurfaceSwipe:CGPointZero];
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"wakeon"]) {
        _powerConnectEnabled = YES;
        [self savePowerAutomationPrefs];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"wakeoff"]) {
        _powerConnectEnabled = NO;
        [self savePowerAutomationPrefs];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"sleepon"]) {
        _powerDisconnectEnabled = YES;
        [self savePowerAutomationPrefs];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"sleepoff"]) {
        _powerDisconnectEnabled = NO;
        [self savePowerAutomationPrefs];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"powerconnect"]) {
        IWPostWizardPowerNotification(IWWizardPowerWakeRequestNotification);
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appwake"]) {
        IWPostWizardPowerNotification(IWWizardPowerWakeRequestNotification);
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"powerdisconnect"]) {
        IWPostWizardPowerNotification(IWWizardPowerLockRequestNotification);
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"appsleep"]) {
        IWPostWizardPowerNotification(IWWizardPowerLockRequestNotification);
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"castfault"]) {
        // Fault injection is intentionally unavailable during normal use.
        // Tests must opt in by creating this short-lived marker first.
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) {
            [_dlnaCastServer debugInvalidateSockets];
        }
        shouldWriteCommandState = NO;
    } else if ([value isEqualToString:@"screenshot"] || [value isEqualToString:@"shot"]) {
        [self captureDebugScreenshot];
    } else if ([value isEqualToString:@"fliptest"]) {
        [self runFlipDebugTest];
    } else if ([value isEqualToString:@"flipcapture"]) {
        [self runFlipCaptureTest];
    } else if ([value hasPrefix:@"flipframe"]) {
        NSInteger frame = [[value substringFromIndex:[@"flipframe" length]] integerValue];
        [self runFlipFrameCapture:frame];
    } else if ([value isEqualToString:@"importsample"]) {
        [self debugImportSample];
    } else if ([value isEqualToString:@"bgstress"]) {
        _backgroundZoom = 1.0;
        _backgroundX = 9999.0;
        _backgroundY = 9999.0;
        [self applyBackgroundTransform];
    } else if ([value isEqualToString:@"bgstressneg"]) {
        _backgroundZoom = 1.0;
        _backgroundX = -9999.0;
        _backgroundY = -9999.0;
        [self applyBackgroundTransform];
    } else if ([value isEqualToString:@"bgcenter"]) {
        _backgroundZoom = 1.0;
        _backgroundX = 0.0;
        _backgroundY = 0.0;
        [self applyBackgroundTransform];
    } else if ([value hasPrefix:@"wallpaper"]) {
        NSString *indexText = [value substringFromIndex:[@"wallpaper" length]];
        NSInteger index = [indexText integerValue];
        [self selectWallpaper:index];
    } else if ([value isEqualToString:@"refresh"] || [value isEqualToString:@"down"]) {
        [self triggerPullRefresh];
    } else if ([value isEqualToString:@"next"] || [value isEqualToString:@"left"]) {
        [self stepWallpaper:1];
    } else if ([value isEqualToString:@"prev"] || [value isEqualToString:@"right"]) {
        [self stepWallpaper:-1];
    } else if ([value isEqualToString:@"close"] || [value isEqualToString:@"main"] || [value isEqualToString:@"root"]) {
        [self returnToMainScreen];
    } else if ([value isEqualToString:@"menu"]) {
        [self toggleMenu];
    } else if ([value isEqualToString:@"home"]) {
        _homeVisible = !_homeVisible;
        if (_homeVisible) [self loadHomeStatus];
        _homePanel.hidden = _cleanMode || !_homeVisible;
        [self.view setNeedsLayout];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"weather"]) {
        _weatherVisible = !_weatherVisible;
        _weatherPanel.hidden = _cleanMode || !_weatherVisible;
        if (_weatherVisible) [self startWeatherUpdates];
        else [self stopWeatherUpdates];
        [self saveState];
        [self updateMenuButtons];
    } else if ([value isEqualToString:@"weatherdemo"]) {
        [self loadWeatherDemo];
    } else if ([value isEqualToString:@"weatheredit"]) {
        if (_weatherVisible && !_editMode) [self enterWeatherEditMode];
    } else if ([value isEqualToString:@"weathereditdemo"]) {
        if (!_weatherVisible) [self loadWeatherDemo];
        if (!_editMode) [self enterWeatherEditMode];
        if (_editTarget == IWEditTargetWeather) {
            _weatherScale = 1.25;
            _weatherOffsetX = -80.0;
            _weatherOffsetY = 40.0;
            [self applyWeatherTransform];
            [self saveState];
            [self captureDebugScreenshotToPath:IWWeatherDebugPath(@"wizard-weather-edit-screenshot.png") afterDelay:0.65];
        }
    } else if ([value isEqualToString:@"music"]) {
        [self toggleMusic];
    } else if ([value isEqualToString:@"video"] || [value isEqualToString:@"movie"]) {
        [self openLocalVideo];
    } else if ([value isEqualToString:@"video2"] || [value isEqualToString:@"movie2"]) {
        [self openLocalVideo2];
    } else if ([value isEqualToString:@"videominimize"] || [value isEqualToString:@"movieminimize"]) {
        [self minimizeVideo];
    } else if ([value isEqualToString:@"videovolume"] || [value isEqualToString:@"movievolume"]) {
        [self videoVolumeTapped];
    } else if ([value isEqualToString:@"cast"]) {
        [self toggleWizardCast];
    } else if ([value isEqualToString:@"theme"]) {
        [self cyclePromoWallpaper];
    } else if ([value isEqualToString:@"favorite"]) {
        [self toggleFavoriteGallery];
    } else if ([value isEqualToString:@"clock"] || [value isEqualToString:@"clean"]) {
        _cleanMode = !_cleanMode;
        [self applyCleanMode];
        [self saveState];
    } else if ([value isEqualToString:@"seconds"]) {
        _showSeconds = !_showSeconds;
        [self tick];
        [self saveState];
        [self.view setNeedsLayout];
    } else if ([value isEqualToString:@"hour"]) {
        _hour24 = !_hour24;
        [self tick];
        [self saveState];
    } else if ([value isEqualToString:@"language"] || [value isEqualToString:@"lang"]) {
        _dateLanguage = (_dateLanguage + 1) % 4;
        [self tick];
        [self refreshWeatherLanguagePresentation];
        [self saveState];
    } else if ([value isEqualToString:@"calendar"]) {
        if (!_dateVisible && !_calendarVisible) _dateVisible = YES;
        else if (_dateVisible && !_calendarVisible) { _dateVisible = NO; _calendarVisible = YES; }
        else { _dateVisible = NO; _calendarVisible = NO; _calendarHolidayToast.hidden = YES; }
        _calendarPanel.hidden = !_calendarVisible;
        [self tick];
        [self updateCalendarPanel];
        [self saveState];
    } else if ([value isEqualToString:@"calendaredit"]) {
        if (_calendarVisible) [self enterCalendarEditMode];
    } else if ([value isEqualToString:@"vi"] || [value isEqualToString:@"gta6"] || [value isEqualToString:@"countdown"]) {
        [self saveState];
        _gta6CountdownMode = !_gta6CountdownMode;
        [self loadClockLayoutForCurrentMode];
        [self tick];
        [self saveState];
        [self.view setNeedsLayout];
    } else if ([value isEqualToString:@"edit"]) {
        [self enterEditMode];
    } else if ([value isEqualToString:@"clockedit"]) {
        [self enterClockEditMode];
    } else if ([value isEqualToString:@"dateedit"]) {
        [self enterDateEditMode];
    } else if ([value isEqualToString:@"done"]) {
        if (_editMode) [self finishEditMode];
    } else if ([value isEqualToString:@"cancel"]) {
        if (_editMode) [self cancelEditMode];
    } else if ([value isEqualToString:@"reset"]) {
        if (_editMode) [self resetEditMode];
    }
    [self updateMenuButtons];
    if (shouldWriteCommandState) [self writeDebugState:value];
}

- (void)locatePresentedGallery {
    if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
        [(IWGalleryController *)self.presentedViewController locateTapped];
    }
}

- (void)debugOpenPresentedGalleryPicker {
    if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
        [(IWGalleryController *)self.presentedViewController debugOpenPhotoPicker];
    }
}

- (void)debugEnterPresentedGalleryDeleteMode {
    if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
        [(IWGalleryController *)self.presentedViewController debugEnterDeleteMode];
    }
}

- (void)setClockDigitsForDebug:(NSString *)value animated:(BOOL)animated {
    NSInteger i;
    for (i = 0; i < [_digitLabels count]; i += 1) {
        UILabel *digit = [_digitLabels objectAtIndex:i];
        NSString *text = i < [value length] ? [value substringWithRange:NSMakeRange(i, 1)] : @"0";
        if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
            [(IWFlipDigitLabel *)digit setDigitText:text animated:animated];
        } else {
            digit.text = text;
        }
    }
}

- (void)setClockDigitsForDebugFlipPhase:(CGFloat)phase {
    NSInteger i;
    for (i = 0; i < [_digitLabels count]; i += 1) {
        UILabel *digit = [_digitLabels objectAtIndex:i];
        if ([digit isKindOfClass:[IWFlipDigitLabel class]]) {
            [(IWFlipDigitLabel *)digit showDebugFlipFromText:@"1" toText:@"2" phase:phase];
        } else {
            digit.text = phase < 0.5 ? @"1" : @"2";
        }
    }
}

- (void)runFlipDebugTest {
    [_timer invalidate];
    _timer = nil;
    NSArray *values = @[@"111111", @"222222", @"333333", @"444444"];
    NSInteger i;
    for (i = 0; i < [values count]; i += 1) {
        NSString *value = [values objectAtIndex:i];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.82 * i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setClockDigitsForDebug:value animated:YES];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.82 * [values count] + 0.6) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self tick];
        if (!_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self writeDebugState:@"fliptest"];
    });
}

- (void)runFlipFrameCapture:(NSInteger)frame {
    [_timer invalidate];
    _timer = nil;
    CGFloat phase = 0.25;
    if (frame == 2) phase = 0.50;
    else if (frame == 3) phase = 0.75;
    else if (frame >= 4) phase = 1.0;
    if (phase >= 1.0) [self setClockDigitsForDebug:@"222222" animated:NO];
    else [self setClockDigitsForDebugFlipPhase:phase];
    [self captureDebugLayerScreenshotToPath:@"/tmp/wizardsystem-flipframe.png" afterDelay:0.30];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self tick];
        if (!_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self writeDebugState:@"flipframe"];
    });
}

- (void)runFlipCaptureTest {
    [_timer invalidate];
    _timer = nil;
    [self setClockDigitsForDebug:@"111111" animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self setClockDigitsForDebug:@"222222" animated:YES];
    });
    [self captureDebugLayerScreenshotToPath:@"/tmp/wizardsystem-flipcap-01.png" afterDelay:0.30];
    [self captureDebugLayerScreenshotToPath:@"/tmp/wizardsystem-flipcap-02.png" afterDelay:0.44];
    [self captureDebugLayerScreenshotToPath:@"/tmp/wizardsystem-flipcap-03.png" afterDelay:0.58];
    [self captureDebugLayerScreenshotToPath:@"/tmp/wizardsystem-flipcap-04.png" afterDelay:0.86];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self tick];
        if (!_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self writeDebugState:@"flipcapture"];
    });
}

- (void)debugImportSample {
    if (![_wallpapers count]) return;
    NSInteger sourceIndex = MAX(0, MIN(_wallpaperIndex, [_wallpapers count] - 1));
    NSString *path = [[_wallpapers objectAtIndex:sourceIndex] objectForKey:@"imagePath"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return;
    NSInteger index = [self importSystemImage:image];
    if (index < 0) return;
    [self selectWallpaper:index];
    if ([self.presentedViewController isKindOfClass:[IWGalleryController class]]) {
        [(IWGalleryController *)self.presentedViewController reloadAfterImportedIndex:index];
    }
    [self writeDebugState:@"importsample"];
}

- (NSDictionary *)jsonAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] > 65536) return nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (void)resetHomePlaceholders:(NSString *)updatedText {
    NSArray *labels = @[@"客厅", @"卧室", @"空气"];
    NSArray *metaValues = @[@"--%", @"--%", @"PM2.5"];
    _homeUpdatedLabel.text = [updatedText length] ? updatedText : @"等待接入 Home Assistant";
    NSInteger i;
    for (i = 0; i < [_homeCards count]; i += 1) {
        UIView *card = [_homeCards objectAtIndex:i];
        card.hidden = i >= [labels count];
        UILabel *name = [card viewWithTag:1];
        UILabel *value = [card viewWithTag:2];
        UILabel *meta = [card viewWithTag:3];
        name.text = i < [labels count] ? [labels objectAtIndex:i] : @"";
        value.text = @"--";
        meta.text = i < [metaValues count] ? [metaValues objectAtIndex:i] : @"--";
    }
}

- (void)loadHomeStatus {
    NSDictionary *json = [self jsonAtPath:[IWAppPath stringByAppendingPathComponent:@"home-status.json"]];
    id rawItems = [json objectForKey:@"items"];
    NSMutableArray *items = [NSMutableArray array];
    if ([rawItems isKindOfClass:[NSArray class]]) {
        for (id item in rawItems) if ([item isKindOfClass:[NSDictionary class]]) [items addObject:item];
    }
    id updatedValue = [json objectForKey:@"updatedAt"];
    NSString *updated = [updatedValue isKindOfClass:[NSString class]] ? updatedValue : @"";
    if (![items count]) {
        [self resetHomePlaceholders:[self formatHomeUpdated:updated]];
        [self.view setNeedsLayout];
        return;
    }
    _homeUpdatedLabel.text = [self formatHomeUpdated:updated];
    NSInteger i;
    NSInteger maxItems = MIN([items count], [_homeCards count]);
    for (i = 0; i < [_homeCards count]; i += 1) {
        UIView *card = [_homeCards objectAtIndex:i];
        card.hidden = i >= maxItems;
    }
    for (i = 0; i < maxItems; i += 1) {
        NSDictionary *item = [items objectAtIndex:i];
        UIView *card = [_homeCards objectAtIndex:i];
        UILabel *name = [card viewWithTag:1];
        UILabel *value = [card viewWithTag:2];
        UILabel *meta = [card viewWithTag:3];
        id label = [item objectForKey:@"label"];
        name.text = [label isKindOfClass:[NSString class]] ? label : @"--";
        id temp = [item objectForKey:@"temperature"];
        id humidity = [item objectForKey:@"humidity"];
        id rawValue = [item objectForKey:@"value"];
        if (temp && temp != [NSNull null]) {
            value.text = [self formatTemperature:temp];
            meta.text = [self formatHumidity:humidity];
        } else {
            value.text = ([rawValue isKindOfClass:[NSString class]] || [rawValue isKindOfClass:[NSNumber class]]) ? [NSString stringWithFormat:@"%@", rawValue] : @"--";
            id metaValue = [item objectForKey:@"meta"];
            meta.text = [metaValue isKindOfClass:[NSString class]] ? metaValue : @"--";
        }
    }
}

- (NSString *)formatTemperature:(id)value {
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return @"--";
    NSString *text = [NSString stringWithFormat:@"%@", value];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double n;
    if (![scanner scanDouble:&n] || ![scanner isAtEnd] || !isfinite(n)) return @"--";
    return [NSString stringWithFormat:@"%.1f°", n];
}

- (NSString *)formatHumidity:(id)value {
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return @"--%";
    NSString *text = [NSString stringWithFormat:@"%@", value];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double n;
    if (![scanner scanDouble:&n] || ![scanner isAtEnd] || !isfinite(n)) return @"--%";
    return [NSString stringWithFormat:@"%.0f%%", round(n)];
}

- (NSString *)formatHomeUpdated:(NSString *)value {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return @"等待数据";
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    [iso setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [iso setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    [iso setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDate *date = [iso dateFromString:value];
    if (!date) {
        [iso setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        date = [iso dateFromString:value];
    }
    if (!date) return value;
    NSDateFormatter *out = [[NSDateFormatter alloc] init];
    [out setDateFormat:@"HH:mm"];
    return [NSString stringWithFormat:@"更新 %@", [out stringFromDate:date]];
}

- (void)loadCastStatus {
    NSDictionary *json = [self jsonAtPath:[IWAppPath stringByAppendingPathComponent:@"cast-state.json"]];
    id idValue = [json objectForKey:@"id"];
    NSString *castId = [idValue isKindOfClass:[NSString class]] ? idValue : nil;
    id srcValue = [json objectForKey:@"src"];
    NSString *src = [srcValue isKindOfClass:[NSString class]] ? srcValue : nil;
    _castSrc = nil;
    _castTitle = nil;
    if ([src length]) {
        src = [[src componentsSeparatedByString:@"?"] objectAtIndex:0];
        _castSrc = [src hasPrefix:@"/"] ? src : [IWAppPath stringByAppendingPathComponent:src];
        id titleValue = [json objectForKey:@"title"];
        _castTitle = [titleValue isKindOfClass:[NSString class]] ? titleValue : @"投送视频";
        _castError = NO;
        if ([castId length]) _castLastId = castId;
    } else {
        _castLastId = nil;
    }
    [self updateMenuButtons];
}

- (void)startVideoTimer {
    [_videoTimer invalidate];
    _videoTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(updateVideoControls) userInfo:nil repeats:YES];
    [self updateVideoControls];
}

- (void)styleVideoVolumeViews {
    UIColor *pink = IWThemePink(1.0);
    _airPlayView.tintColor = [UIColor whiteColor];
    _volumeSlider.minimumTrackTintColor = pink;
    _volumeSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.28];
    if ([_volumeSlider respondsToSelector:@selector(setThumbTintColor:)]) {
        _volumeSlider.thumbTintColor = [UIColor whiteColor];
    }
    _systemVolumeSlider = nil;
    for (UIView *view in [_volumeView subviews]) {
        if ([view isKindOfClass:[UISlider class]]) {
            _systemVolumeSlider = (UISlider *)view;
            _volumeSlider.value = _systemVolumeSlider.value;
        } else if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            button.tintColor = pink;
            UIImage *image = [button imageForState:UIControlStateNormal];
            if (image && [image respondsToSelector:@selector(imageWithRenderingMode:)]) {
                [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
            }
            UIImage *selectedImage = [button imageForState:UIControlStateSelected];
            if (selectedImage && [selectedImage respondsToSelector:@selector(imageWithRenderingMode:)]) {
                [button setImage:[selectedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateSelected];
            }
        }
    }
    for (UIView *view in [_airPlayView subviews]) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            button.tintColor = [UIColor whiteColor];
            UIImage *image = [button imageForState:UIControlStateNormal];
            if (image && [image respondsToSelector:@selector(imageWithRenderingMode:)]) {
                [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
            }
            UIImage *selectedImage = [button imageForState:UIControlStateSelected];
            if (selectedImage && [selectedImage respondsToSelector:@selector(imageWithRenderingMode:)]) {
                [button setImage:[selectedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateSelected];
            }
        }
    }
}

- (NSString *)formatVideoTime:(NSTimeInterval)value {
    if (!isfinite(value) || value < 0) value = 0;
    NSInteger total = (NSInteger)round(value);
    NSInteger seconds = total % 60;
    NSInteger minutes = (total / 60) % 60;
    NSInteger hours = total / 3600;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (void)setVideoControlsVisible:(BOOL)visible animated:(BOOL)animated {
    _videoControlsVisible = visible;
    UIView *closeButton = [_videoOverlay viewWithTag:502];
    UIView *minimizeButton = [_videoOverlay viewWithTag:503];
    _videoTapShield.frame = _videoOverlay.bounds;
    [_videoOverlay bringSubviewToFront:_videoTapShield];
    [_videoOverlay bringSubviewToFront:closeButton];
    [_videoOverlay bringSubviewToFront:minimizeButton];
    [_videoOverlay bringSubviewToFront:_videoControls];
    [_videoOverlay bringSubviewToFront:_volumePanel];
    if (!visible) {
        _videoVolumeVisible = NO;
        _volumePanel.hidden = YES;
    }
    void (^changes)(void) = ^{
        _videoControls.alpha = visible ? 1.0 : 0.0;
        closeButton.alpha = visible ? 1.0 : 0.0;
        minimizeButton.alpha = visible ? 1.0 : 0.0;
        _volumePanel.alpha = (_videoVolumeVisible && visible) ? 1.0 : 0.0;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        _videoControls.hidden = !visible;
        closeButton.hidden = !visible;
        minimizeButton.hidden = !visible;
        _volumePanel.hidden = !(_videoVolumeVisible && visible);
    };
    if (visible) {
        _videoControls.hidden = NO;
        closeButton.hidden = NO;
        minimizeButton.hidden = NO;
        _volumePanel.hidden = !_videoVolumeVisible;
    }
    if (animated) [UIView animateWithDuration:0.18 animations:changes completion:done];
    else { changes(); done(YES); }
}

- (void)scheduleVideoControlsAutoHide {
    [_videoHideTimer invalidate];
    _videoHideTimer = nil;
    if (_videoUserPaused || _videoOverlay.hidden || UIAccessibilityIsVoiceOverRunning()) return;
    _videoHideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(hideVideoControlsTimerFired) userInfo:nil repeats:NO];
}

- (void)hideVideoControlsTimerFired {
    if (!_videoUserPaused && !_videoOverlay.hidden && !UIAccessibilityIsVoiceOverRunning()) [self setVideoControlsVisible:NO animated:YES];
}

- (void)videoAccessibilityStatusChanged:(NSNotification *)notification {
    if (!_videoOverlay || _videoOverlay.hidden) {
        [_videoHideTimer invalidate];
        _videoHideTimer = nil;
        return;
    }
    [self setVideoControlsVisible:YES animated:NO];
    [self scheduleVideoControlsAutoHide];
}

- (BOOL)isAirPlayActive {
    if (_usingRemoteVideoPlayer) return NO;
    if ([_moviePlayer respondsToSelector:@selector(isAirPlayVideoActive)] && _moviePlayer.airPlayVideoActive) {
        return YES;
    }
    if ([[UIScreen screens] count] > 1) return YES;
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *output in route.outputs) {
        NSString *type = output.portType ?: @"";
        NSString *name = output.portName ?: @"";
        if ([type rangeOfString:@"AirPlay" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([name rangeOfString:@"AirPlay" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    for (UIView *view in [_airPlayView subviews]) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)view;
            if (button.selected) return YES;
        }
    }
    return NO;
}

- (void)updateVideoControls {
    NSTimeInterval duration = 0.0;
    NSTimeInterval current = 0.0;
    if (_usingRemoteVideoPlayer && _remoteVideoPlayer) {
        CMTime d = _remoteVideoPlayer.currentItem.duration;
        CMTime c = _remoteVideoPlayer.currentTime;
        duration = IWSecondsFromCMTimeSafe(d);
        current = IWSecondsFromCMTimeSafe(c);
    } else {
        duration = IWSecondsSafe(_moviePlayer.duration);
        current = IWSecondsSafe(_moviePlayer.currentPlaybackTime);
    }
    if (duration > 0) {
        _videoSlider.maximumValue = duration;
        if (_videoSliderScrubbing) {
            current = _videoSlider.value;
        } else if (_remoteVideoSeeking) {
            _videoSlider.value = MAX(0.0, MIN(duration, _remoteVideoPendingSeekTime));
            current = _remoteVideoPendingSeekTime;
        } else if (!_videoSlider.tracking) {
            _videoSlider.value = MAX(0.0, MIN(duration, current));
        }
    }
    _videoCurrentLabel.text = [self formatVideoTime:current];
    _videoDurationLabel.text = [self formatVideoTime:duration];
    _videoPlayButton.kind = _videoUserPaused ? IWButtonKindPlay : IWButtonKindPause;
    [_videoPlayButton setNeedsDisplay];
    BOOL airPlayActive = [self isAirPlayActive];
    _airPlayView.backgroundColor = airPlayActive ? IWThemePink(0.72) : [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
}

- (void)videoPlayTapped {
    if (_videoUserPaused) {
        _videoUserPaused = NO;
        if (_usingRemoteVideoPlayer) [_remoteVideoPlayer play];
        else [_moviePlayer play];
        [self scheduleVideoControlsAutoHide];
    } else {
        _videoUserPaused = YES;
        [_videoHideTimer invalidate];
        if (_usingRemoteVideoPlayer) [_remoteVideoPlayer pause];
        else [_moviePlayer pause];
    }
    [self updateVideoControls];
}

- (void)videoRewindTapped {
    NSTimeInterval current = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime) : IWSecondsSafe(_moviePlayer.currentPlaybackTime);
    NSTimeInterval next = MAX(0.0, current - 10.0);
    if (_usingRemoteVideoPlayer) {
        [self seekVideoToTime:next];
    } else {
        _moviePlayer.currentPlaybackTime = next;
        if (!_videoUserPaused) [_moviePlayer play];
        [self scheduleVideoControlsAutoHide];
        [self updateVideoControls];
    }
}

- (void)videoForwardTapped {
    NSTimeInterval duration = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentItem.duration) : IWSecondsSafe(_moviePlayer.duration);
    NSTimeInterval current = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime) : IWSecondsSafe(_moviePlayer.currentPlaybackTime);
    NSTimeInterval next = current + 10.0;
    if (duration > 0) next = MIN(duration, next);
    if (_usingRemoteVideoPlayer) {
        [self seekVideoToTime:next];
    } else {
        _moviePlayer.currentPlaybackTime = next;
        if (!_videoUserPaused) [_moviePlayer play];
        [self scheduleVideoControlsAutoHide];
        [self updateVideoControls];
    }
}

- (void)videoSliderChanged:(UISlider *)slider {
    if (_usingRemoteVideoPlayer) {
        _videoSliderScrubbing = YES;
        _videoCurrentLabel.text = [self formatVideoTime:slider.value];
        return;
    }
    [self seekVideoToTime:slider.value];
}

- (void)videoSliderTouchBegan:(UISlider *)slider {
    [_videoHideTimer invalidate];
    _videoSliderScrubbing = _usingRemoteVideoPlayer;
    _videoControls.hidden = NO;
    _videoControls.alpha = 1.0;
}

- (void)videoSliderTouchEnded:(UISlider *)slider {
    _videoSliderScrubbing = NO;
    [self seekVideoToTime:slider.value];
}

- (void)seekVideoToTime:(NSTimeInterval)value {
    if (_usingRemoteVideoPlayer) {
        _remoteVideoSeeking = YES;
        _remoteVideoPendingSeekTime = MAX(0.0, value);
        _remoteVideoSeekGeneration += 1;
        NSInteger seekGeneration = _remoteVideoSeekGeneration;
        [_remoteVideoPlayer pause];
        _videoSlider.value = _remoteVideoPendingSeekTime;
        _videoCurrentLabel.text = [self formatVideoTime:_remoteVideoPendingSeekTime];
        IWCastLog(@"remote seek %.2f", _remoteVideoPendingSeekTime);
        __weak IWRootViewController *weakSelf = self;
        [_remoteVideoPlayer seekToTime:CMTimeMakeWithSeconds(_remoteVideoPendingSeekTime, 600)
                       toleranceBefore:CMTimeMakeWithSeconds(0.25, 600)
                        toleranceAfter:CMTimeMakeWithSeconds(0.25, 600)
                     completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                IWRootViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                if (seekGeneration != strongSelf->_remoteVideoSeekGeneration) return;
                void (^finishSeek)(void) = ^{
                    if (seekGeneration != strongSelf->_remoteVideoSeekGeneration) return;
                    strongSelf->_remoteVideoSeeking = NO;
                    if (finished && !strongSelf->_videoUserPaused && strongSelf->_usingRemoteVideoPlayer) [strongSelf->_remoteVideoPlayer play];
                    [strongSelf updateVideoControls];
                    [strongSelf scheduleVideoControlsAutoHide];
                };
                if (finished && !strongSelf->_videoUserPaused && strongSelf->_usingRemoteVideoPlayer && [strongSelf->_remoteVideoPlayer respondsToSelector:@selector(prerollAtRate:completionHandler:)]) {
                    [strongSelf->_remoteVideoPlayer prerollAtRate:1.0 completionHandler:^(__unused BOOL prerollFinished) {
                        dispatch_async(dispatch_get_main_queue(), finishSeek);
                    }];
                } else if (finished && !strongSelf->_videoUserPaused && strongSelf->_usingRemoteVideoPlayer) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), finishSeek);
                } else {
                    finishSeek();
                }
            });
        }];
    } else {
        _moviePlayer.currentPlaybackTime = value;
        if (!_videoUserPaused) [_moviePlayer play];
        [self scheduleVideoControlsAutoHide];
        [self updateVideoControls];
    }
}

- (void)volumeSliderChanged:(UISlider *)slider {
    if (!_systemVolumeSlider) [self styleVideoVolumeViews];
    [_systemVolumeSlider setValue:slider.value animated:NO];
    [_systemVolumeSlider sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)videoVolumeTapped {
    _videoVolumeVisible = !_videoVolumeVisible;
    [self styleVideoVolumeViews];
    _videoVolumeButton.backgroundColor = _videoVolumeVisible ? IWThemePink(0.72) : [UIColor colorWithRed:13.0/255.0 green:11.0/255.0 blue:34.0/255.0 alpha:0.46];
    _videoVolumeButton.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.62] CGColor];
    _volumePanel.hidden = !_videoVolumeVisible;
    _volumePanel.alpha = _videoVolumeVisible ? 1.0 : 0.0;
    [self setVideoControlsVisible:YES animated:YES];
    [self scheduleVideoControlsAutoHide];
}

- (void)runVideoControlAuditWithLocalVideo:(BOOL)localVideo {
    if (_videoAuditRunning) return;
    if (localVideo) {
        NSString *fixturePath = nil;
        NSString *markerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-local-video-fixture"];
        IWLocalVideoFixtureStatus fixtureStatus = IWResolveLocalVideoFixture(markerPath,
                                                                              @"/var/mobile/Media/iPadWizard",
                                                                              (uid_t)501,
                                                                              &fixturePath);
        if (fixtureStatus == IWLocalVideoFixtureStatusAbsent) [self openLocalVideo];
        else if (fixtureStatus == IWLocalVideoFixtureStatusValid) {
            [self openMoviePath:fixturePath];
            if (![_videoCurrentPath isEqualToString:fixturePath]) return;
        }
        else return;
    }
    if (!_videoCurrentURL || (!localVideo && !_usingRemoteVideoPlayer)) return;
    _videoAuditRunning = YES;
    NSUInteger generation = _videoCloseGeneration;
    CFTimeInterval started = CACurrentMediaTime();
    NSTimeInterval startedAtEpoch = [[NSDate date] timeIntervalSince1970];
    float audioOutputVolumeBefore = [AVAudioSession sharedInstance].outputVolume;
    NSMutableArray *trace = [NSMutableArray array];
    NSArray *steps = @[@[@4, @"pause"], @[@5, @"paused"], @[@7, @"paused-later"],
                      @[@8, @"seek"], @[@10, @"seeked"], @[@11, @"minimize"],
                      @[@12, @"minimized"], @[@13, @"restore"], @[@15, @"restored"],
                      @[@16, @"resume"], @[@18, @"resumed"], @[@19, @"minimize-playing"],
                      @[@21, @"minimized-playing-early"], @[@24, @"minimized-playing-later"],
                      @[@35, @"restore"], @[@37, @"restored-playing"], @[@38, @"pause"], @[@39, @"finish"]];
    for (NSArray *step in steps) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([step[0] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL current = generation == _videoCloseGeneration;
            NSString *action = step[1];
            if (current) {
                if ([action isEqualToString:@"pause"] && !_videoUserPaused) [self videoPlayTapped];
                else if ([action isEqualToString:@"resume"] && _videoUserPaused) [self videoPlayTapped];
                else if ([action isEqualToString:@"seek"]) {
                    NSTimeInterval at = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime) : IWSecondsSafe(_moviePlayer.currentPlaybackTime);
                    [self seekVideoToTime:at + 10.0];
                } else if ([action isEqualToString:@"minimize"] || [action isEqualToString:@"minimize-playing"]) [self minimizeVideo];
                else if ([action isEqualToString:@"restore"]) [self restoreMinimizedVideo];
                // Sample in memory: full-state serialization and file readback
                // can disturb the very intervals this audit needs to observe.
                CFTimeInterval sampleStarted = CACurrentMediaTime();
                NSTimeInterval position = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentTime) : IWSecondsSafe(_moviePlayer.currentPlaybackTime);
                NSTimeInterval duration = _usingRemoteVideoPlayer ? IWSecondsFromCMTimeSafe(_remoteVideoPlayer.currentItem.duration) : IWSecondsSafe(_moviePlayer.duration);
                CMTimebaseRef timebase = _usingRemoteVideoPlayer ? _remoteVideoPlayer.currentItem.timebase : NULL;
                id timebasePosition = timebase ? @(IWSecondsFromCMTimeSafe(CMTimebaseGetTime(timebase))) : (id)[NSNull null];
                id timebaseRate = timebase ? @(CMTimebaseGetRate(timebase)) : (id)[NSNull null];
                CFTimeInterval sampleEnded = CACurrentMediaTime();
                UIWindow *window = self.view.window;
                CGSize remoteSize = _usingRemoteVideoPlayer ? _remoteVideoPlayer.currentItem.presentationSize : CGSizeZero;
                [trace addObject:@{
                    @"context": action,
                    @"plannedElapsedSeconds": step[0],
                    @"sampleStartElapsedSeconds": @(sampleStarted - started),
                    @"sampleEndElapsedSeconds": @(sampleEnded - started),
                    @"sampleDurationSeconds": @(sampleEnded - sampleStarted),
                    @"applicationState": @([UIApplication sharedApplication].applicationState),
                    @"windowHidden": @(!window || window.hidden),
                    @"videoCurrentTime": @(position),
                    @"videoDuration": @(duration),
                    @"videoUserPaused": @(_videoUserPaused),
                    @"videoMinimized": @(_videoMinimized),
                    @"videoOpen": @(_videoOverlay && !_videoOverlay.hidden),
                    @"videoOverlayAlpha": @(_videoOverlay.alpha),
                    @"usingRemoteVideoPlayer": @(_usingRemoteVideoPlayer),
                    @"remoteVideoRate": @(_remoteVideoPlayer.rate),
                    @"remoteVideoTimebaseSeconds": timebasePosition,
                    @"remoteVideoTimebaseRate": timebaseRate,
                    @"remoteVideoWidth": @(remoteSize.width),
                    @"remoteVideoHeight": @(remoteSize.height),
                    @"videoPlaybackState": @(_moviePlayer.playbackState),
                    @"videoLoadState": @(_moviePlayer.loadState),
                }];
            }
            if ([action isEqualToString:@"finish"]) {
                _videoAuditRunning = NO;
                NSDictionary *report = @{@"schemaVersion": @2,
                                         @"sourceFingerprint": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WizardSourceFingerprint"] ?: @"",
                                         @"buildNumber": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
                                         @"processID": @(getpid()),
                                         @"startedAtEpoch": @(startedAtEpoch),
                                         @"completedAtEpoch": @([[NSDate date] timeIntervalSince1970]),
                                         @"elapsedSeconds": @(CACurrentMediaTime() - started),
                                         @"audioOutputVolumeBefore": @(audioOutputVolumeBefore),
                                         @"audioOutputVolumeAfter": @([AVAudioSession sharedInstance].outputVolume),
                                         @"expectedStepCount": @([steps count]),
                                         @"localVideo": @(localVideo), @"cancelled": @(!current), @"trace": trace};
                NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
                [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-video-audit.json"] options:NSDataWritingAtomic error:nil];
            }
        });
    }
}

- (void)restoreMinimizedVideo {
    if (!_videoMinimized) return;
    BOOL shouldPlay = !_videoUserPaused;
    _videoMinimized = NO;
    _closingVideo = NO;
    _videoOverlay.hidden = NO;
    _videoOverlay.alpha = 1.0;
    [self.view bringSubviewToFront:_videoOverlay];
    UIView *playerView = [_videoOverlay viewWithTag:501];
    [_moviePlayer.view removeFromSuperview];
    _moviePlayer.view.frame = playerView.bounds;
    [playerView addSubview:_moviePlayer.view];
    _remoteVideoLayer.frame = playerView.bounds;
    // Minimizing retains both players and their position; reloading here
    // restarts buffering and can autoplay a session the user paused.
    [self setVideoControlsVisible:YES animated:NO];
    [self startVideoTimer];
    if (shouldPlay) {
        if (_usingRemoteVideoPlayer) [_remoteVideoPlayer play];
        else [_moviePlayer play];
    } else {
        if (_usingRemoteVideoPlayer) [_remoteVideoPlayer pause];
        else [_moviePlayer pause];
    }
    [self scheduleVideoControlsAutoHide];
    [self updateVideoControls];
}

- (void)openMoviePath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if ([_castSrc length] && [path isEqualToString:_castSrc]) _castError = YES;
        [self updateMenuButtons];
        return;
    }
    [self openMovieURL:[NSURL fileURLWithPath:path] identity:path];
}

- (void)invalidatePendingVideoClose {
    _videoCloseGeneration += 1;
    _closingVideo = NO;
    [_videoOverlay.layer removeAllAnimations];
}

- (void)openMovieURL:(NSURL *)url identity:(NSString *)identity {
    NSString *path = identity ?: [url absoluteString];
    if (![path length] || !url) return;
    _pendingCastURL = nil;
    if (_videoMinimized && [_videoCurrentPath isEqualToString:path]) {
        [self restoreMinimizedVideo];
        return;
    }
    [self removeRemoteVideoObservers];
    if (_videoMinimized) {
        _videoMinimized = NO;
        _videoOverlay.hidden = YES;
        _videoOverlay.alpha = 1.0;
        [_videoTimer invalidate];
        _videoTimer = nil;
        [_videoHideTimer invalidate];
        _videoHideTimer = nil;
        [_moviePlayer stop];
        [_remoteVideoPlayer pause];
        _videoCurrentPath = nil;
        _videoCurrentURL = nil;
    }
    if (_player.playing) [_player pause];
    _menuOpen = NO;
    _menu.hidden = YES;
    _controlsHidden = NO;
    _menuButton.hidden = NO;
    [self updateMenuButtons];
    [self invalidatePendingVideoClose];
    _videoMinimized = NO;
    _videoVolumeVisible = NO;
    _videoUserPaused = NO;
    _videoSliderScrubbing = NO;
    _remoteVideoSeeking = NO;
    _remoteVideoPendingSeekTime = 0.0;
    _remoteVideoSeekGeneration += 1;
    _volumePanel.hidden = YES;
    _videoOverlay.alpha = 0.0;
    _videoOverlay.hidden = NO;
    _videoTapShield.frame = _videoOverlay.bounds;
    [_videoOverlay bringSubviewToFront:_videoTapShield];
    [_videoOverlay bringSubviewToFront:[_videoOverlay viewWithTag:502]];
    [_videoOverlay bringSubviewToFront:[_videoOverlay viewWithTag:503]];
    [_videoOverlay bringSubviewToFront:_videoControls];
    [_videoOverlay bringSubviewToFront:_volumePanel];
    [_moviePlayer stop];
    [_remoteVideoPlayer pause];
    _videoCurrentPath = [path copy];
    _videoCurrentURL = url;
    _usingRemoteVideoPlayer = !url.isFileURL;
    _moviePlayer.view.hidden = _usingRemoteVideoPlayer;
    _remoteVideoLayer.hidden = !_usingRemoteVideoPlayer;
    if (_usingRemoteVideoPlayer) {
        _remoteVideoPlayer = [AVPlayer playerWithURL:url];
        _remoteVideoLayer.player = _remoteVideoPlayer;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(remoteVideoFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:_remoteVideoPlayer.currentItem];
        [center addObserver:self selector:@selector(remoteVideoFinished:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_remoteVideoPlayer.currentItem];
        IWCastLog(@"remote AVPlayer open %@", [url absoluteString]);
    } else {
        _remoteVideoLayer.player = nil;
        _remoteVideoPlayer = nil;
        _moviePlayer.contentURL = url;
        if (!url.isFileURL) IWCastLog(@"remote MPMoviePlayer open %@", [url absoluteString]);
    }
    [self setVideoControlsVisible:YES animated:NO];
    if (_usingRemoteVideoPlayer) [_remoteVideoPlayer play];
    else {
        [_moviePlayer prepareToPlay];
        [_moviePlayer play];
    }
    [self startVideoTimer];
    [self scheduleVideoControlsAutoHide];
    [self writeDebugState:(_usingRemoteVideoPlayer ? @"remote-video-open" : @"local-video-open")];
    [UIView animateWithDuration:0.18 animations:^{
        _videoOverlay.alpha = 1.0;
    }];
}

- (void)openLocalVideo {
    [self openMoviePath:[IWAppPath stringByAppendingPathComponent:@"assets/video/gta6-trailer-1080p-ipad2-test.mp4"]];
}

- (void)openLocalVideo2 {
    [self openMoviePath:[IWAppPath stringByAppendingPathComponent:@"assets/video/gta6-trailer-2-1080p-ipad.mp4"]];
}

- (void)openCastVideo {
    [self loadCastStatus];
    if ([_castSrc length]) {
        _castError = NO;
        [self openMoviePath:_castSrc];
        return;
    }
    _castError = YES;
    [self updateMenuButtons];
}

- (void)openCastURL:(NSURL *)url {
    if (!url) return;
    _pendingCastURL = url;
    [self commitEditModeForLifecycle];
    if (_player.playing) [_player pause];
    if (_castDismissingModal) return;
    if (self.presentedViewController) {
        _castDismissingModal = YES;
        [self dismissViewControllerAnimated:NO completion:^{
            _castDismissingModal = NO;
            NSURL *latestURL = _pendingCastURL;
            _pendingCastURL = nil;
            if (latestURL) [self openCastURL:latestURL];
        }];
        return;
    }
    _pendingCastURL = nil;
    _castError = NO;
    _castSrc = [[url absoluteString] copy];
    _castTitle = @"投送视频";
    [self openMovieURL:url identity:[url absoluteString]];
    [self.view bringSubviewToFront:_videoOverlay];
    [self updateMenuButtons];
}

- (void)toggleWizardCast {
    if (!_dlnaCastServer) [self setupWizardCastServer];
    if (!_dlnaCastServer.running) {
        // A retry request is accepted before listener readiness is known.
        [_dlnaCastServer start];
    }
    [self updateMenuButtons];
}

- (void)closeVideo {
    if ((_videoOverlay.hidden && !_videoMinimized) || _closingVideo) return;
    NSUInteger closeGeneration = ++_videoCloseGeneration;
    [self removeRemoteVideoObservers];
    _closingVideo = YES;
    _videoMinimized = NO;
    _videoVolumeVisible = NO;
    [_videoTimer invalidate];
    _videoTimer = nil;
    [_videoHideTimer invalidate];
    _videoHideTimer = nil;
    [_moviePlayer stop];
    [_remoteVideoPlayer pause];
    _remoteVideoLayer.player = nil;
    _remoteVideoPlayer = nil;
    _remoteVideoLayer.hidden = YES;
    _moviePlayer.view.hidden = NO;
    _usingRemoteVideoPlayer = NO;
    _videoSliderScrubbing = NO;
    _remoteVideoSeeking = NO;
    _remoteVideoPendingSeekTime = 0.0;
    _remoteVideoSeekGeneration += 1;
    _videoCurrentPath = nil;
    _videoCurrentURL = nil;
    _volumePanel.hidden = YES;
    if (_videoOverlay.hidden) {
        _closingVideo = NO;
        return;
    }
    [UIView animateWithDuration:0.20 animations:^{
        _videoOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (closeGeneration != _videoCloseGeneration || !_closingVideo) return;
        _videoOverlay.hidden = YES;
        _videoOverlay.alpha = 1.0;
        _closingVideo = NO;
    }];
}

- (void)minimizeVideo {
    if (_videoOverlay.hidden || _closingVideo) return;
    _videoMinimized = YES;
    _videoVolumeVisible = NO;
    _volumePanel.hidden = YES;
    [_videoHideTimer invalidate];
    _videoHideTimer = nil;
    [UIView animateWithDuration:0.18 animations:^{
        _videoOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (!_videoMinimized) return;
        _videoOverlay.hidden = YES;
        _videoOverlay.alpha = 1.0;
    }];
}

- (void)videoOverlayTapped:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (_lastVideoTapAt > 0 && now - _lastVideoTapAt < 0.18) return;
    _lastVideoTapAt = now;
    CGPoint p = [recognizer locationInView:_videoOverlay];
    UIView *closeButton = [_videoOverlay viewWithTag:502];
    UIView *minimizeButton = [_videoOverlay viewWithTag:503];
    if (closeButton && CGRectContainsPoint(closeButton.frame, p)) return;
    if (minimizeButton && CGRectContainsPoint(minimizeButton.frame, p)) return;
    if (_videoVolumeVisible && CGRectContainsPoint(_volumePanel.frame, p)) return;
    if (!_videoControls.hidden && CGRectContainsPoint(_videoControls.frame, p)) return;
    [self setVideoControlsVisible:!_videoControlsVisible animated:YES];
    if (!_videoControlsVisible) [_videoHideTimer invalidate];
    else [self scheduleVideoControlsAutoHide];
}

- (void)videoTapShieldPressed:(UIControl *)sender {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (_lastVideoTapAt > 0 && now - _lastVideoTapAt < 0.18) return;
    _lastVideoTapAt = now;
    [self setVideoControlsVisible:!_videoControlsVisible animated:YES];
    if (!_videoControlsVisible) [_videoHideTimer invalidate];
    else [self scheduleVideoControlsAutoHide];
}

- (void)movieFinished:(NSNotification *)notification {
    NSNumber *reasonValue = [[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    _lastLocalVideoFinish = @{@"reason": reasonValue ?: @(-1), @"remoteActive": @(_usingRemoteVideoPlayer)};
    if (_usingRemoteVideoPlayer || notification.object != _moviePlayer) return;
    if (reasonValue && [reasonValue integerValue] == MPMovieFinishReasonUserExited) return;
    [self closeVideo];
}

- (void)removeRemoteVideoObservers {
    id item = _remoteVideoPlayer.currentItem;
    if (!item) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [center removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
}

- (void)remoteVideoFinished:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self remoteVideoFinished:notification]; });
        return;
    }
    // A queued notification from a replaced item must not close its successor.
    if (!_usingRemoteVideoPlayer || notification.object != _remoteVideoPlayer.currentItem) return;
    if ([notification.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification]) _castError = YES;
    [self closeVideo];
}

- (void)toggleMusic {
    if (_player.playing) {
        [_player pause];
        _musicError = NO;
        [self updateMenuButtons];
        return;
    }
    if (!_player) {
        NSString *path = [IWAppPath stringByAppendingPathComponent:@"assets/audio/love-is-a-long-road-preview.m4a"];
        NSError *error = nil;
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
        if (!_player || error) {
            _musicError = YES;
            [self updateMenuButtons];
            return;
        }
        _player.numberOfLoops = -1;
        _player.volume = 0.55;
        [_player prepareToPlay];
    }
    [_player play];
    _musicError = NO;
    [self updateMenuButtons];
}

@end

@interface IWApplication : UIApplication {
    CGPoint _applicationSurfaceStart;
    BOOL _applicationSurfaceTracking;
}
@end

@implementation IWApplication

- (void)appendApplicationTouchDebug:(NSString *)message {
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/tmp/wizardsystem-debug"]) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message ?: @""];
    NSString *path = @"/tmp/wizardsystem-touch.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (void)sendEvent:(UIEvent *)event {
    NSSet *touches = [event allTouches];
    UITouchPhase phase = UITouchPhaseStationary;
    CGPoint p = CGPointZero;
    IWRootViewController *root = nil;
    if ([touches count]) {
        UITouch *touch = [touches anyObject];
        phase = touch.phase;
        p = [touch locationInView:self.keyWindow];
        root = [self.keyWindow.rootViewController isKindOfClass:[IWRootViewController class]] ? (IWRootViewController *)self.keyWindow.rootViewController : nil;
        NSString *phaseName = @"other";
        if (touch.phase == UITouchPhaseBegan) phaseName = @"app-begin";
        else if (touch.phase == UITouchPhaseEnded) phaseName = @"app-end";
        else if (touch.phase == UITouchPhaseCancelled) phaseName = @"app-cancel";
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            [self appendApplicationTouchDebug:[NSString stringWithFormat:@"%@ x=%.1f y=%.1f view=%@", phaseName, p.x, p.y, NSStringFromClass([touch.view class])]];
        }
        if (touch.phase == UITouchPhaseBegan && root) {
            _applicationSurfaceStart = p;
            _applicationSurfaceTracking = [root canHandleApplicationSurfaceTouchAtPoint:p];
            if (_applicationSurfaceTracking) [self appendApplicationTouchDebug:@"app-track begin"];
        } else if (touch.phase == UITouchPhaseCancelled) {
            _applicationSurfaceTracking = NO;
        }
    }
    [super sendEvent:event];
    if (root && phase == UITouchPhaseEnded && _applicationSurfaceTracking) {
        _applicationSurfaceTracking = NO;
        [root handleApplicationSurfaceSwipeFrom:_applicationSurfaceStart to:p];
    } else if (phase == UITouchPhaseCancelled) {
        _applicationSurfaceTracking = NO;
    }
}

@end

@interface IWAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, assign) BOOL handledURLActivation;
@property (nonatomic, assign) BOOL pendingDisplayRestore;
@property (nonatomic, strong) CMMotionManager *startupMotionManager;
@property (nonatomic, strong) NSURL *pendingLaunchURL;
@property (nonatomic, assign) BOOL rootInstalled;
@end

@implementation IWAppDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    return YES;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)handleOpenURL:(NSURL *)url {
    if (!url) return NO;
    NSString *command = [url host];
    if (![command length]) command = [[url path] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    IWRootViewController *root = [self.window.rootViewController isKindOfClass:[IWRootViewController class]] ? (IWRootViewController *)self.window.rootViewController : nil;
    if (![command length]) return NO;
    if (!root) {
        self.pendingLaunchURL = url;
        return YES;
    }
    self.handledURLActivation = YES;
    NSString *normalized = [command lowercaseString];
    BOOL wakeCommand = [normalized isEqualToString:@"main"] ||
                       [normalized isEqualToString:@"appwake"] ||
                       [normalized isEqualToString:@"powerconnect"];
    if (wakeCommand) {
        self.pendingDisplayRestore = YES;
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            [root restoreDisplayAfterSystemLock];
            self.pendingDisplayRestore = NO;
        }
    }
    [root handleDebugCommand:command];
    return YES;
}

- (UIInterfaceOrientation)startupOrientationForGravity:(CMAcceleration)gravity {
    if (gravity.x >= 0.35) return UIInterfaceOrientationLandscapeLeft;
    if (gravity.x <= -0.35) return UIInterfaceOrientationLandscapeRight;
    return IWCurrentLandscapeOrientation();
}

- (void)installRootForStartupOrientation:(UIInterfaceOrientation)orientation gravity:(CMAcceleration)gravity sampled:(BOOL)sampled {
    if (self.rootInstalled) return;
    self.rootInstalled = YES;
    [self.startupMotionManager stopDeviceMotionUpdates];
    self.startupMotionManager = nil;

    [[NSUserDefaults standardUserDefaults] setInteger:orientation forKey:IWLastLandscapeOrientationKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[UIDevice currentDevice] setValue:@(orientation) forKey:@"orientation"];
    [[UIApplication sharedApplication] setStatusBarOrientation:orientation animated:NO];
    self.window.frame = [[UIScreen mainScreen] bounds];
    self.window.rootViewController = [[IWRootViewController alloc] init];

    NSString *line = [NSString stringWithFormat:@"%@ sampled=%d gravity=(%.4f,%.4f,%.4f) target=%ld device=%ld status=%ld\n",
                      [NSDate date], sampled, gravity.x, gravity.y, gravity.z, (long)orientation,
                      (long)[[UIDevice currentDevice] orientation],
                      (long)[[UIApplication sharedApplication] statusBarOrientation]];
    [line writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"wizard-orientation.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSURL *pendingURL = self.pendingLaunchURL;
    self.pendingLaunchURL = nil;
    if (pendingURL) [self handleOpenURL:pendingURL];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    application.statusBarHidden = YES;
    application.idleTimerDisabled = YES;
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];
    UIViewController *placeholder = [[UIViewController alloc] init];
    placeholder.view.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = placeholder;
    [self.window makeKeyAndVisible];
    NSURL *launchURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if (launchURL) self.pendingLaunchURL = launchURL;

    self.startupMotionManager = [[CMMotionManager alloc] init];
    if ([self.startupMotionManager isDeviceMotionAvailable]) {
        self.startupMotionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
        __weak IWAppDelegate *weakSelf = self;
        [self.startupMotionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue]
                                                        withHandler:^(CMDeviceMotion *motion, NSError *error) {
            IWAppDelegate *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.rootInstalled || error || !motion) return;
            CMAcceleration gravity = motion.gravity;
            if (fabs(gravity.x) < 0.35) return;
            [strongSelf installRootForStartupOrientation:[strongSelf startupOrientationForGravity:gravity]
                                                 gravity:gravity sampled:YES];
        }];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.rootInstalled) return;
        CMDeviceMotion *motion = self.startupMotionManager.deviceMotion;
        CMAcceleration gravity = motion ? motion.gravity : (CMAcceleration){0, 0, 0};
        [self installRootForStartupOrientation:[self startupOrientationForGravity:gravity]
                                       gravity:gravity sampled:(motion != nil)];
    });
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    application.statusBarHidden = YES;
    application.idleTimerDisabled = YES;
    IWRootViewController *root = [self.window.rootViewController isKindOfClass:[IWRootViewController class]] ? (IWRootViewController *)self.window.rootViewController : nil;
    if (self.pendingDisplayRestore) {
        [root restoreDisplayAfterSystemLock];
        self.pendingDisplayRestore = NO;
    }
    if (self.handledURLActivation) {
        self.handledURLActivation = NO;
        return;
    }
    [root returnToMainScreen];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    IWRootViewController *root = [self.window.rootViewController isKindOfClass:[IWRootViewController class]] ? (IWRootViewController *)self.window.rootViewController : nil;
    [root commitEditModeForLifecycle];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    IWRootViewController *root = [self.window.rootViewController isKindOfClass:[IWRootViewController class]] ? (IWRootViewController *)self.window.rootViewController : nil;
    [root commitEditModeForLifecycle];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self handleOpenURL:url];
}

// iOS 10 delivers custom URLs to an already-running application through this
// selector.  Keep the older callback above for the iOS 9 iPad 2 build.
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    return [self handleOpenURL:url];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, NSStringFromClass([IWApplication class]), NSStringFromClass([IWAppDelegate class]));
    }
}
