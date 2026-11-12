#!/usr/bin/env python3
"""Exercise production URL and Cast-consent logic with host UIKit doubles."""
from pathlib import Path
import plistlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/main.m"
source = SOURCE.read_text()
INFO_PLIST = ROOT / "App/Info.plist"
info = plistlib.loads(INFO_PLIST.read_bytes())


def extract_function(name):
    match = re.search(r"^static BOOL " + re.escape(name) + r"\([^\n]*\) \{", source, re.M)
    if not match:
        raise RuntimeError("Production helper missing: " + name)
    opening = source.find("{", match.start())
    depth = 0
    for position in range(opening, len(source)):
        if source[position] == "{":
            depth += 1
        elif source[position] == "}":
            depth -= 1
            if depth == 0:
                return source[match.start():position + 1]
    raise RuntimeError("Unclosed production helper: " + name)


def extract_method(selector, return_type="void"):
    match = re.search(r"^- \(" + re.escape(return_type) + r"\)" + selector + r" \{", source, re.M)
    if not match:
        raise RuntimeError("Production method missing: " + selector)
    end = re.search(r"^[-+] \(", source[match.end():], re.M)
    stop = match.end() + end.start() if end else len(source)
    return source[match.start():stop]


PREAMBLE = r'''
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#define TARGET_OS_SIMULATOR 0

typedef NS_ENUM(NSInteger, UIApplicationState) {
    UIApplicationStateActive,
    UIApplicationStateInactive,
    UIApplicationStateBackground
};
typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleAlert };
typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel };

@class UIAlertController, UIAlertAction;

@interface UIViewController : NSObject
@property(nonatomic, strong) UIViewController *presentedViewController;
@property(nonatomic, weak) UIViewController *presentingViewController;
@property(nonatomic, assign) BOOL isBeingDismissed;
@property(nonatomic, assign) NSUInteger presentationCount;
- (void)presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface UIAlertAction : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, assign) UIAlertActionStyle style;
@property(nonatomic, copy) void (^handler)(UIAlertAction *action);
@property(nonatomic, weak) UIAlertController *alert;
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *action))handler;
- (void)trigger;
@end

@interface UIAlertController : UIViewController
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, assign) UIAlertControllerStyle preferredStyle;
@property(nonatomic, strong) NSMutableArray *actions;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
- (UIAlertAction *)actionWithTitle:(NSString *)title;
@end

@interface UIApplication : NSObject
@property(nonatomic, assign) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end

@interface UIWindow : NSObject
@property(nonatomic, strong) UIViewController *rootViewController;
@end

@interface IWDLNACastServer : NSObject
@property(nonatomic, copy) void (^playURLHandler)(NSURL *url);
@property(nonatomic, copy) void (^stateChangedHandler)(BOOL ready, NSError *error);
@property(nonatomic, assign) BOOL running;
@property(nonatomic, assign) BOOL startResult;
@property(nonatomic, assign) NSUInteger startCalls;
@property(nonatomic, assign) NSUInteger stopCalls;
- (BOOL)start;
- (void)stop;
@end

@interface IWRootViewController : UIViewController {
@public
    IWDLNACastServer *_dlnaCastServer;
    BOOL _castEnabled;
    BOOL _castError;
    UIAlertController *_castConsentAlert;
    NSUInteger _castConsentGeneration;
    NSURL *_pendingCastURL;
    NSUInteger _openCastCalls;
    NSURL *_openedURL;
    NSUInteger _menuUpdateCalls;
    NSUInteger _editCommitCalls;
    NSUInteger _debugCommandCalls;
    NSUInteger _displayRestoreCalls;
    NSString *_lastDebugCommand;
}
- (void)setupWizardCastServer;
- (void)toggleWizardCast;
- (void)requestCastURL:(NSURL *)url;
- (void)stopWizardCast;
- (void)openCastURL:(NSURL *)url;
- (void)updateMenuButtons;
- (void)commitEditModeForLifecycle;
- (void)writeDebugState:(NSString *)context;
- (void)handleDebugCommand:(NSString *)command;
- (void)restoreDisplayAfterSystemLock;
@end

@interface IWAppDelegate : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSURL *pendingLaunchURL;
@property(nonatomic, assign) BOOL handledURLActivation;
@property(nonatomic, assign) BOOL pendingDisplayRestore;
- (BOOL)handleOpenURL:(NSURL *)url;
- (void)applicationDidEnterBackground:(UIApplication *)application;
@end

@implementation UIViewController
- (void)presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion {
    (void)animated;
    self.presentationCount += 1;
    self.presentedViewController = viewController;
    viewController.presentingViewController = self;
    if (completion) completion();
}
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    (void)animated;
    UIViewController *presenter = self.presentingViewController;
    if (presenter.presentedViewController == self) presenter.presentedViewController = nil;
    self.presentingViewController = nil;
    if (completion) completion();
}
@end

@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    UIAlertAction *action = [self new];
    action.title = title;
    action.style = style;
    action.handler = handler;
    return action;
}
- (void)trigger {
    UIAlertController *alert = self.alert;
    [alert dismissViewControllerAnimated:NO completion:nil];
    if (self.handler) self.handler(self);
}
@end

@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    UIAlertController *alert = [self new];
    alert.title = title;
    alert.message = message;
    alert.preferredStyle = style;
    alert.actions = [NSMutableArray array];
    return alert;
}
- (void)addAction:(UIAlertAction *)action {
    action.alert = self;
    [self.actions addObject:action];
}
- (UIAlertAction *)actionWithTitle:(NSString *)title {
    for (UIAlertAction *action in self.actions) if ([action.title isEqualToString:title]) return action;
    return nil;
}
@end

@implementation UIApplication
+ (instancetype)sharedApplication {
    static UIApplication *application;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ application = [self new]; application.applicationState = UIApplicationStateActive; });
    return application;
}
@end

@implementation UIWindow
@end

@implementation IWDLNACastServer
- (instancetype)init {
    self = [super init];
    if (self) _startResult = YES;
    return self;
}
- (BOOL)start {
    self.startCalls += 1;
    if (self.startResult) self.running = YES;
    return self.startResult;
}
- (void)stop {
    self.stopCalls += 1;
    self.running = NO;
}
@end

static void IWStyleNativeAlert(UIAlertController *alert) { (void)alert; }
'''

TESTS = r'''
static NSUInteger checks = 0;
static NSUInteger failures = 0;
static void check(BOOL condition, NSString *message) {
    checks += 1;
    if (!condition) {
        failures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

__PRODUCTION_HELPERS__

static void testInfoPlistContract(void) {
__PLIST_ASSERTIONS__
}

@implementation IWRootViewController
__PRODUCTION_ROOT_METHODS__
- (void)openCastURL:(NSURL *)url { _openCastCalls += 1; _openedURL = url; }
- (void)updateMenuButtons { _menuUpdateCalls += 1; }
- (void)commitEditModeForLifecycle { _editCommitCalls += 1; }
- (void)writeDebugState:(NSString *)context { (void)context; }
- (void)handleDebugCommand:(NSString *)command { _debugCommandCalls += 1; _lastDebugCommand = command; }
- (void)restoreDisplayAfterSystemLock { _displayRestoreCalls += 1; }
@end

@implementation IWAppDelegate
__OPEN_URL_METHOD__
__BACKGROUND_METHOD__
@end

static NSURL *url(NSString *text) { return [NSURL URLWithString:text]; }
static IWAppDelegate *delegateWithRoot(IWRootViewController *root) {
    UIWindow *window = [UIWindow new];
    window.rootViewController = root;
    IWAppDelegate *delegate = [IWAppDelegate new];
    delegate.window = window;
    return delegate;
}

static void testOpenURLCallsite(void) {
    NSArray *deniedURLs = @[
        @"wizardsystem://powerdisconnect", @"wizardsystem://wakeon", @"wizardsystem://sleepoff",
        @"wizardsystem://weather", @"wizardsystem://main?debug=1", @"wizardsystem://main/path",
        @"wizardsystem://main#fragment"
    ];
    IWAppDelegate *launchingDelegate = delegateWithRoot(nil);
    for (NSString *text in deniedURLs) {
        check(![launchingDelegate handleOpenURL:url(text)] && launchingDelegate.pendingLaunchURL == nil &&
              !launchingDelegate.handledURLActivation && !launchingDelegate.pendingDisplayRestore,
              [@"rejected URL cannot queue launch work: " stringByAppendingString:text]);
    }

    NSURL *mainURL = url(@"wizardsystem://main");
    check([launchingDelegate handleOpenURL:mainURL] && [launchingDelegate.pendingLaunchURL isEqual:mainURL] &&
          !launchingDelegate.handledURLActivation,
          @"only the valid main URL is queued before the root controller exists");

    IWRootViewController *root = [IWRootViewController new];
    IWAppDelegate *activeDelegate = delegateWithRoot(root);
    NSURL *priorPendingURL = url(@"wizardsystem://main");
    activeDelegate.pendingLaunchURL = priorPendingURL;
    for (NSString *text in deniedURLs) {
        NSUInteger debugCalls = root->_debugCommandCalls;
        NSUInteger restoreCalls = root->_displayRestoreCalls;
        check(![activeDelegate handleOpenURL:url(text)] && root->_debugCommandCalls == debugCalls &&
              root->_displayRestoreCalls == restoreCalls && [activeDelegate.pendingLaunchURL isEqual:priorPendingURL] &&
              !activeDelegate.handledURLActivation,
              [@"rejected URL leaves root and pending launch state unchanged: " stringByAppendingString:text]);
    }

    activeDelegate.pendingLaunchURL = nil;
    check([activeDelegate handleOpenURL:mainURL] && root->_debugCommandCalls == 1 &&
          [root->_lastDebugCommand isEqualToString:@"main"] && root->_displayRestoreCalls == 1 &&
          activeDelegate.handledURLActivation && !activeDelegate.pendingDisplayRestore &&
          activeDelegate.pendingLaunchURL == nil,
          @"valid main URL reaches the normal root command and display restore");
}

static void testControlURLPolicy(void) {
    check(IWAllowsControlURL(url(@"wizardsystem://main"), NO), @"device allows the exact main control URL");
    check(IWAllowsControlURL(url(@"WizardSystem://MAIN"), NO), @"scheme and command host comparison is case insensitive");
    check(IWAllowsControlURL(url(@"wizardsystem://debug-gallery"), YES), @"simulator allows debug command hosts");
    for (NSString *bad in @[
        @"https://main", @"wizardsystem://other", @"wizardsystem://main/path",
        @"wizardsystem://main/", @"wizardsystem://main?x=1", @"wizardsystem://main#part",
        @"wizardsystem://user@main", @"wizardsystem://user:pass@main", @"wizardsystem://main:80",
        @"wizardsystem://@main", @"wizardsystem://main?", @"wizardsystem://main#",
        @"wizardsystem:main", @"wizardsystem:///main"
    ]) {
        check(!IWAllowsControlURL(url(bad), NO), [@"device rejects control URL: " stringByAppendingString:bad]);
    }
    check(!IWAllowsControlURL(nil, NO), @"nil control URL is rejected");
}

static void testCastURLPolicy(void) {
    NSURL *https = url(@"https://media.example/video.mp4");
    NSURL *http = url([NSString stringWithFormat:@"http://%u.%u.%u.%u:8080/video.mp4?token=sample", 192, 0, 2, 4]);
    check(IWShouldRequestCastConsent(https, YES, YES, YES), @"active enabled Cast accepts HTTPS for consent");
    check(IWShouldRequestCastConsent(http, YES, YES, YES), @"active enabled Cast accepts HTTP for consent");
    check(!IWShouldRequestCastConsent(https, NO, YES, YES), @"disabled Cast rejects playback request");
    check(!IWShouldRequestCastConsent(https, YES, NO, YES), @"stopped Cast rejects playback request");
    check(!IWShouldRequestCastConsent(https, YES, YES, NO), @"inactive app rejects playback request");
    check(!IWShouldRequestCastConsent(url(@"file:///tmp/video.mp4"), YES, YES, YES), @"file URL is rejected");
    check(!IWShouldRequestCastConsent(url(@"ftp://media.example/video.mp4"), YES, YES, YES), @"non-HTTP URL is rejected");
    check(!IWShouldRequestCastConsent(url(@"https:///video.mp4"), YES, YES, YES), @"URL without a host is rejected");
    check(!IWShouldRequestCastConsent(url([@"https://user@" stringByAppendingString:@"media.example/video.mp4"]), YES, YES, YES), @"URL with userinfo is rejected");
    check(!IWShouldRequestCastConsent(url([@"https://user:pass@" stringByAppendingString:@"media.example/video.mp4"]), YES, YES, YES), @"URL with username and password is rejected");
    check(!IWShouldRequestCastConsent(url(@"http://@media.example/video.mp4"), YES, YES, YES), @"URL with empty userinfo is rejected");
    NSString *longURL = [@"https://media.example/" stringByPaddingToLength:4100 withString:@"x" startingAtIndex:0];
    check(!IWShouldRequestCastConsent(url(longURL), YES, YES, YES), @"URL above the 4096 character limit is rejected");
    check(!IWShouldRequestCastConsent(nil, YES, YES, YES), @"nil playback URL is rejected");
}

static void triggerAction(UIAlertController *alert, NSString *title) {
    UIAlertAction *action = [alert actionWithTitle:title];
    check(action != nil, [@"expected alert action exists: " stringByAppendingString:title]);
    [action trigger];
}

static IWRootViewController *rootWithCastEnabled(void) {
    IWRootViewController *root = [IWRootViewController new];
    [root setupWizardCastServer];
    check(root->_dlnaCastServer != nil && !root->_dlnaCastServer.running && root->_dlnaCastServer.startCalls == 0,
          @"server setup installs callbacks without starting listeners");
    [root toggleWizardCast];
    UIAlertController *enableAlert = root->_castConsentAlert;
    check(enableAlert != nil && root->_dlnaCastServer.startCalls == 0,
          @"Cast stays stopped until the user accepts the enable alert");
    triggerAction(enableAlert, @"开启");
    check(root->_castEnabled && root->_dlnaCastServer.running && root->_dlnaCastServer.startCalls == 1,
          @"explicit enable starts Cast");
    return root;
}

static void testEnableCancelAndStop(void) {
    IWRootViewController *root = [IWRootViewController new];
    [root setupWizardCastServer];
    check(!root->_dlnaCastServer.running && root->_dlnaCastServer.startCalls == 0,
          @"app setup does not auto-start Cast");

    [root toggleWizardCast];
    UIAlertController *cancelAlert = root->_castConsentAlert;
    check(cancelAlert != nil && [cancelAlert.title isEqualToString:@"开启局域网投屏？"],
          @"toggle asks before opening the Cast listener");
    triggerAction(cancelAlert, @"取消");
    check(!root->_castEnabled && !root->_dlnaCastServer.running && root->_dlnaCastServer.startCalls == 0,
          @"cancelling enable keeps Cast stopped");

    [root toggleWizardCast];
    UIAlertController *enableAlert = root->_castConsentAlert;
    triggerAction(enableAlert, @"开启");
    check(root->_castEnabled && root->_dlnaCastServer.running, @"accepting enable opens Cast");
    [root toggleWizardCast];
    check(!root->_castEnabled && !root->_dlnaCastServer.running && root->_dlnaCastServer.stopCalls == 1,
          @"second toggle stops an enabled Cast listener");
}

static void testPlaybackRequiresConfirmationAndDeduplicates(void) {
    IWRootViewController *root = rootWithCastEnabled();
    NSURL *firstURL = url(@"https://first.example/path/video.mp4?token=one");
    root->_dlnaCastServer.playURLHandler(firstURL);
    UIAlertController *alert = root->_castConsentAlert;
    check(alert != nil && [alert.message isEqualToString:@"first.example"],
          @"play request prompts with host only");
    check(root->_openCastCalls == 0, @"received URL is not played before user approval");

    NSUInteger prompts = root.presentationCount;
    root->_dlnaCastServer.playURLHandler(url(@"https://second.example/video.mp4"));
    check(root.presentationCount == prompts && root->_castConsentAlert == alert,
          @"duplicate play requests do not stack consent prompts");
    triggerAction(alert, @"关闭投屏");
    check(root->_openCastCalls == 0 && root->_castConsentAlert == nil && !root->_castEnabled && !root->_dlnaCastServer.running,
          @"declining playback closes the receiver without opening the URL");

    root = rootWithCastEnabled();
    root->_dlnaCastServer.playURLHandler(firstURL);
    alert = root->_castConsentAlert;
    triggerAction(alert, @"播放");
    check(root->_openCastCalls == 1 && [root->_openedURL isEqual:firstURL],
          @"only the approved playback URL is opened");
}

static void testStopInvalidatesConsentAndCallbacks(void) {
    IWRootViewController *root = rootWithCastEnabled();
    root->_dlnaCastServer.playURLHandler(url(@"https://stale.example/video.mp4"));
    UIAlertController *playAlert = root->_castConsentAlert;
    UIAlertAction *oldPlayAction = [playAlert actionWithTitle:@"播放"];
    NSUInteger generation = root->_castConsentGeneration;
    [root stopWizardCast];
    check(!root->_castEnabled && !root->_dlnaCastServer.running && root->_pendingCastURL == nil,
          @"stop closes Cast and clears pending URL");
    check(root->_castConsentAlert == nil && root->_castConsentGeneration > generation,
          @"stop dismisses the consent alert and advances its generation");
    [oldPlayAction trigger];
    root->_dlnaCastServer.playURLHandler(url(@"https://late.example/video.mp4"));
    check(root->_openCastCalls == 0 && root->_castConsentAlert == nil,
          @"stale approval and late server callbacks cannot play or prompt after stop");

    IWRootViewController *enablingRoot = [IWRootViewController new];
    [enablingRoot setupWizardCastServer];
    [enablingRoot toggleWizardCast];
    UIAlertController *enableAlert = enablingRoot->_castConsentAlert;
    UIAlertAction *oldEnableAction = [enableAlert actionWithTitle:@"开启"];
    [enablingRoot stopWizardCast];
    [oldEnableAction trigger];
    check(!enablingRoot->_castEnabled && !enablingRoot->_dlnaCastServer.running &&
          enablingRoot->_dlnaCastServer.startCalls == 0,
          @"stale enable approval cannot start a listener after stop");
}

static void testBackgroundStopsCastAndInvalidatesCallbacks(void) {
    IWRootViewController *root = rootWithCastEnabled();
    root->_dlnaCastServer.playURLHandler(url(@"https://background.example/video.mp4"));
    UIAlertController *playAlert = root->_castConsentAlert;
    UIAlertAction *oldPlayAction = [playAlert actionWithTitle:@"播放"];

    UIWindow *window = [UIWindow new];
    window.rootViewController = root;
    IWAppDelegate *delegate = [IWAppDelegate new];
    delegate.window = window;
    UIApplication *application = [UIApplication sharedApplication];
    application.applicationState = UIApplicationStateBackground;
    [delegate applicationDidEnterBackground:application];

    [oldPlayAction trigger];
    root->_dlnaCastServer.playURLHandler(url(@"https://after-background.example/video.mp4"));
    check(!root->_castEnabled && !root->_dlnaCastServer.running && root->_dlnaCastServer.stopCalls == 1,
          @"background callback stops the active Cast listener");
    check(root->_editCommitCalls == 1 && root->_openCastCalls == 0 && root->_castConsentAlert == nil,
          @"background commits edit state and stale consent cannot play or prompt");

    IWRootViewController *enablingRoot = [IWRootViewController new];
    [enablingRoot setupWizardCastServer];
    [enablingRoot toggleWizardCast];
    UIAlertController *enableAlert = enablingRoot->_castConsentAlert;
    UIAlertAction *oldEnableAction = [enableAlert actionWithTitle:@"开启"];
    UIWindow *enableWindow = [UIWindow new];
    enableWindow.rootViewController = enablingRoot;
    IWAppDelegate *enableDelegate = [IWAppDelegate new];
    enableDelegate.window = enableWindow;
    [enableDelegate applicationDidEnterBackground:application];
    [oldEnableAction trigger];
    check(!enablingRoot->_castEnabled && !enablingRoot->_dlnaCastServer.running &&
          enablingRoot->_dlnaCastServer.startCalls == 0,
          @"background invalidates an open enable approval before it can start Cast");
    application.applicationState = UIApplicationStateActive;
}

int main(void) {
    @autoreleasepool {
        testInfoPlistContract();
        testControlURLPolicy();
        testCastURLPolicy();
        testOpenURLCallsite();
        testEnableCancelAndStop();
        testPlaybackRequiresConfirmationAndDeduplicates();
        testStopInvalidatesConsentAndCallbacks();
        testBackgroundStopsCastAndInvalidatesCallbacks();
        fprintf(stdout, "{\"checks\":%lu,\"failures\":%lu}\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
'''

url_schemes = [scheme for url_type in info.get("CFBundleURLTypes", [])
               for scheme in url_type.get("CFBundleURLSchemes", [])]
location_usage = info.get("NSLocationWhenInUseUsageDescription", "")
usage_description_keys = {key for key in info if key.endswith("UsageDescription")}
expected_usage_description_keys = {"NSPhotoLibraryUsageDescription", "NSLocationWhenInUseUsageDescription"}
known_sdk_or_user_data_registration_keys = {
    "NSUserTrackingUsageDescription", "SKAdNetworkItems", "GADApplicationIdentifier",
    "GoogleAppID", "FacebookAppID", "FIRAnalyticsConfiguration",
    "FirebaseAppDelegateProxyEnabled", "NSPrivacyTracking", "NSPrivacyTrackingDomains",
    "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"
}
plist_contract = [
    (url_schemes == ["wizardsystem"], "Info.plist registers only the Wizard control URL scheme"),
    ("Open-Meteo" in location_usage and "Apple" in location_usage,
     "location consent names Open-Meteo and Apple city parsing"),
    (usage_description_keys == expected_usage_description_keys,
     "Info.plist requests only photo-library and when-in-use location access"),
    (not (known_sdk_or_user_data_registration_keys & set(info)),
     "Info.plist has no known ad, analytics, tracking, or privacy-data registrations")
]
plist_assertions = "\n".join(
    "    check(%s, @%s);" % ("YES" if passed else "NO", json.dumps(message))
    for passed, message in plist_contract
)
helpers = "\n".join([extract_function("IWAllowsControlURL"), extract_function("IWShouldRequestCastConsent")])
root_methods = "\n".join([
    extract_method("setupWizardCastServer"),
    extract_method("toggleWizardCast"),
    extract_method(r"requestCastURL:\(NSURL \*\)url"),
    extract_method("stopWizardCast"),
])
open_url_method = extract_method(r"handleOpenURL:\(NSURL \*\)url", "BOOL")
background_method = extract_method(r"applicationDidEnterBackground:\(UIApplication \*\)application")
harness_text = (PREAMBLE + TESTS.replace("__PRODUCTION_HELPERS__", helpers)
                .replace("__PLIST_ASSERTIONS__", plist_assertions)
                .replace("__PRODUCTION_ROOT_METHODS__", root_methods)
                .replace("__OPEN_URL_METHOD__", open_url_method)
                .replace("__BACKGROUND_METHOD__", background_method))

with tempfile.TemporaryDirectory(prefix="wizard-security-regressions-") as directory:
    temp = Path(directory)
    harness = temp / "security-regressions.m"
    binary = temp / "security-regressions"
    harness.write_text(harness_text)
    compile_result = subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-fblocks", "-Werror", "-framework", "Foundation",
        str(harness), "-o", str(binary)
    ], capture_output=True, text=True)
    if compile_result.returncode:
        print(compile_result.stdout, end="")
        print(compile_result.stderr, end="")
        raise SystemExit(compile_result.returncode)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)
