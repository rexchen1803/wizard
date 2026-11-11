#!/usr/bin/env python3
"""Compile and exercise the production remote-seek and video-close methods."""
from pathlib import Path
import subprocess
import tempfile
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/main.m"


def extract_method(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"production method not found: {signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"method body not found: {signature}")

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
    raise SystemExit(f"unterminated method body: {signature}")


source = SOURCE.read_text()
audit_method = extract_method(source, "- (void)runVideoControlAuditWithLocalVideo:(BOOL)localVideo {")
audit_compact = re.sub(r"\s+", " ", audit_method)
absent_guard = audit_compact.find("IWLocalVideoFixtureStatusAbsent")
valid_guard = audit_compact.find("IWLocalVideoFixtureStatusValid")
local_fallback = audit_compact.find("[self openLocalVideo]")
guarded_fixture_open = audit_compact.find("[self openMoviePath:fixturePath]")
invalid_return = audit_compact.find("else return;", valid_guard)
if not (0 <= absent_guard < local_fallback and 0 <= valid_guard < guarded_fixture_open and
        local_fallback < valid_guard and guarded_fixture_open < invalid_return and
        audit_compact.count("[self openLocalVideo]") == 1):
    raise SystemExit("local audit still lacks absent-only fallback and invalid-fixture fail-closed routing")

fixture_enum_start = source.find("typedef NS_ENUM(NSInteger, IWLocalVideoFixtureStatus)")
if fixture_enum_start < 0:
    raise SystemExit("production fixture status enum not found")
fixture_enum_end = source.find("};", fixture_enum_start)
if fixture_enum_end < 0:
    raise SystemExit("production fixture status enum body not found")
fixture_types = source[fixture_enum_start:fixture_enum_end + 2]
fixture_helper = extract_method(source, "static IWLocalVideoFixtureStatus IWResolveLocalVideoFixture(")
fixture_helper_compact = re.sub(r"\s+", " ", fixture_helper)
for required in ("O_NOFOLLOW", "markerInfo.st_uid != expectedUID", "rootInfo.st_uid != expectedUID",
                 "fixtureInfo.st_uid != expectedUID", "rootInfo.st_dev != parentInfo.st_dev",
                 "fixtureInfo.st_dev != rootInfo.st_dev"):
    if required not in fixture_helper_compact:
        raise SystemExit(f"production fixture helper lost required filesystem guard: {required}")
for required in ("wizardsystem-local-video-fixture", "/var/mobile/Media/iPadWizard", "(uid_t)501"):
    if required not in audit_compact:
        raise SystemExit(f"production local-audit route lost its fixed fixture contract: {required}")

methods = [
    extract_method(source, "- (void)seekVideoToTime:(NSTimeInterval)value {"),
    extract_method(source, "- (void)invalidatePendingVideoClose {"),
    extract_method(source, "- (void)closeVideo {"),
    extract_method(source, "- (void)restoreMinimizedVideo {"),
    extract_method(source, "- (void)commitEditModeForLifecycle {"),
    extract_method(source, "- (void)openMovieURL:(NSURL *)url identity:(NSString *)identity {"),
    extract_method(source, "- (void)openMoviePath:(NSString *)path {"),
    extract_method(source, "- (void)openCastURL:(NSURL *)url {"),
    extract_method(source, "- (void)returnToMainScreen {"),
    extract_method(source, "- (void)movieFinished:(NSNotification *)notification {"),
    extract_method(source, "- (void)scheduleVideoControlsAutoHide {"),
    extract_method(source, "- (void)hideVideoControlsTimerFired {"),
]
accessibility_handler = "- (void)videoAccessibilityStatusChanged:(NSNotification *)notification {"
methods.append(extract_method(source, accessibility_handler) if accessibility_handler in source
               else accessibility_handler + " (void)notification; }")
video_setup = extract_method(source, "- (void)buildVideoOverlay {")
production_movie_autoplay_disabled = "_moviePlayer.shouldAutoplay = NO;" in video_setup

generated = r'''
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static dispatch_queue_t IWTestMainQueue;
#define dispatch_get_main_queue() IWTestMainQueue

static NSUInteger IWChecks = 0;
static NSUInteger IWFailures = 0;
static NSMutableArray *IWAnimationCompletions;
static NSMutableArray *IWCurrentEventSink;
static BOOL IWTestVoiceOverRunning = NO;
static BOOL UIAccessibilityIsVoiceOverRunning(void) { return IWTestVoiceOverRunning; }
static NSString * const AVPlayerItemDidPlayToEndTimeNotification = @"AVPlayerItemDidPlayToEndTimeNotification";
static NSString * const AVPlayerItemFailedToPlayToEndTimeNotification = @"AVPlayerItemFailedToPlayToEndTimeNotification";
static NSString * const AVLayerVideoGravityResizeAspect = @"AVLayerVideoGravityResizeAspect";
static NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey = @"MPMoviePlayerPlaybackDidFinishReasonUserInfoKey";
static const NSInteger MPMovieFinishReasonUserExited = 1;

static NSTimeInterval IWSecondsFromCMTimeSafe(CMTime time) { return CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : 0.0; }

static void IWCheck(BOOL condition, NSString *message) {
    IWChecks += 1;
    if (!condition) {
        IWFailures += 1;
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
    }
}

static void IWDrainMainQueue(void) {
    dispatch_sync(IWTestMainQueue, ^{});
}

@interface IWTestLayer : NSObject
@property (nonatomic, assign) NSUInteger removeAnimationCount;
- (void)removeAllAnimations;
@end
@implementation IWTestLayer
- (void)removeAllAnimations { self.removeAnimationCount += 1; }
@end

@interface UIView : NSObject
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) NSInteger tag;
@property (nonatomic, strong) IWTestLayer *layer;
@property (nonatomic, strong) NSMutableArray *events;
@property (nonatomic, strong) NSMutableArray *subviews;
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, assign) NSUInteger frontCount;
- (CGRect)bounds;
- (void)setNeedsDisplay;
- (void)setNeedsLayout;
- (UIView *)viewWithTag:(NSInteger)tag;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (void)bringSubviewToFront:(UIView *)view;
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations;
+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion;
@end
@implementation UIView
- (instancetype)init {
    self = [super init];
    if (self) { _alpha = 1.0; _layer = [[IWTestLayer alloc] init]; _events = [NSMutableArray array]; _subviews = [NSMutableArray array]; }
    return self;
}
- (CGRect)bounds { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (void)setNeedsDisplay {}
- (void)setNeedsLayout {}
- (UIView *)viewWithTag:(NSInteger)tag {
    for (UIView *view in self.subviews) {
        if (view.tag == tag) return view;
        UIView *nested = [view viewWithTag:tag];
        if (nested) return nested;
    }
    return nil;
}
- (void)addSubview:(UIView *)view {
    [view removeFromSuperview];
    view.superview = self;
    [self.subviews addObject:view];
}
- (void)removeFromSuperview {
    [self.superview.subviews removeObjectIdenticalTo:self];
    self.superview = nil;
}
- (void)bringSubviewToFront:(UIView *)view { (void)view; self.frontCount += 1; [self.events addObject:@"front-child"]; }
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations {
    (void)duration;
    if (animations) animations();
}
+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    (void)duration;
    if (animations) animations();
    if (completion) [IWAnimationCompletions addObject:[completion copy]];
}
@end

@interface UIViewController : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, strong) UIViewController *presentedViewController;
@property (nonatomic, strong) NSMutableArray *dismissCompletions;
@property (nonatomic, assign) NSUInteger dismissCount;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)completeDismissalAtIndex:(NSUInteger)index;
@end
@implementation UIViewController
- (instancetype)init {
    self = [super init];
    if (self) { _view = [[UIView alloc] init]; _dismissCompletions = [NSMutableArray array]; }
    return self;
}
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    (void)animated;
    self.dismissCount += 1;
    self.presentedViewController = nil;
    if (completion) [self.dismissCompletions addObject:[completion copy]];
}
- (void)completeDismissalAtIndex:(NSUInteger)index {
    void (^completion)(void) = [self.dismissCompletions objectAtIndex:index];
    [self.dismissCompletions replaceObjectAtIndex:index withObject:[NSNull null]];
    completion();
}
@end

@interface IWTestAudioPlayer : NSObject
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign) NSUInteger pauseCount;
@property (nonatomic, strong) NSMutableArray *events;
- (void)pause;
@end
@implementation IWTestAudioPlayer
- (void)pause { self.playing = NO; self.pauseCount += 1; [self.events addObject:@"music-pause"]; }
@end

@interface UILabel : NSObject
@property (nonatomic, copy) NSString *text;
@end
@implementation UILabel @end

@interface UISlider : NSObject
@property (nonatomic, assign) float value;
@property (nonatomic, assign) BOOL tracking;
@end
@implementation UISlider @end

@interface AVPlayer : NSObject
@property (nonatomic, strong) NSMutableArray *seekCompletions;
@property (nonatomic, strong) NSMutableArray *prerollCompletions;
@property (nonatomic, strong) id currentItem;
@property (nonatomic, assign) NSUInteger pauseCount;
@property (nonatomic, assign) NSUInteger playCount;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign) CMTime currentTime;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSMutableArray *events;
@end
@implementation AVPlayer
+ (instancetype)playerWithURL:(NSURL *)url {
    AVPlayer *player = [[self alloc] init];
    player.url = url;
    player.events = IWCurrentEventSink;
    return player;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _seekCompletions = [NSMutableArray array];
        _prerollCompletions = [NSMutableArray array];
        _currentItem = [[NSObject alloc] init];
    }
    return self;
}
- (void)pause { self.pauseCount += 1; self.playing = NO; }
- (void)play { self.playCount += 1; self.playing = YES; [self.events addObject:@"video-play"]; }
- (void)seekToTime:(CMTime)time
   toleranceBefore:(CMTime)before
    toleranceAfter:(CMTime)after
 completionHandler:(void (^)(BOOL finished))completion {
    (void)time; (void)before; (void)after;
    [self.seekCompletions addObject:[completion copy]];
}
- (void)prerollAtRate:(float)rate completionHandler:(void (^)(BOOL finished))completion {
    (void)rate;
    [self.prerollCompletions addObject:[completion copy]];
}
- (void)completeSeekAtIndex:(NSUInteger)index finished:(BOOL)finished {
    void (^completion)(BOOL) = [self.seekCompletions objectAtIndex:index];
    [self.seekCompletions replaceObjectAtIndex:index withObject:[NSNull null]];
    completion(finished);
}
- (void)completePrerollAtIndex:(NSUInteger)index finished:(BOOL)finished {
    void (^completion)(BOOL) = [self.prerollCompletions objectAtIndex:index];
    [self.prerollCompletions replaceObjectAtIndex:index withObject:[NSNull null]];
    completion(finished);
}
@end

@interface AVPlayerLayer : NSObject
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, copy) NSString *videoGravity;
@end
@implementation AVPlayerLayer @end

@interface MPMoviePlayerController : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) NSTimeInterval currentPlaybackTime;
@property (nonatomic, strong) NSURL *contentURL;
@property (nonatomic, assign) BOOL shouldAutoplay;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign) NSUInteger currentPlaybackTimeWriteCount;
@property (nonatomic, assign) NSUInteger contentURLWriteCount;
@property (nonatomic, assign) NSUInteger prepareCount;
@property (nonatomic, assign) NSUInteger playCount;
@property (nonatomic, assign) NSUInteger pauseCount;
@property (nonatomic, assign) NSUInteger seekCount;
- (void)play;
- (void)pause;
- (void)stop;
- (void)prepareToPlay;
@end
@implementation MPMoviePlayerController
- (instancetype)init {
    self = [super init];
    if (self) _view = [[UIView alloc] init];
    return self;
}
- (void)setCurrentPlaybackTime:(NSTimeInterval)time { _currentPlaybackTime = time; self.currentPlaybackTimeWriteCount += 1; }
- (void)setContentURL:(NSURL *)url { _contentURL = url; self.contentURLWriteCount += 1; }
- (void)play { self.playCount += 1; self.playing = YES; }
- (void)pause { self.pauseCount += 1; self.playing = NO; }
- (void)stop { self.playing = NO; }
- (void)prepareToPlay { self.prepareCount += 1; if (self.shouldAutoplay) self.playing = YES; }
@end

static void IWCastLog(NSString *format, ...) { (void)format; }

@interface IWRootViewController : UIViewController {
@public
    BOOL _usingRemoteVideoPlayer;
    BOOL _videoUserPaused;
    BOOL _videoControlsVisible;
    BOOL _remoteVideoSeeking;
    NSTimeInterval _remoteVideoPendingSeekTime;
    NSInteger _remoteVideoSeekGeneration;
    NSUInteger _videoCloseGeneration;
    BOOL _closingVideo;
    BOOL _videoMinimized;
    BOOL _videoVolumeVisible;
    BOOL _videoSliderScrubbing;
    BOOL _editMode;
    BOOL _panFallbackTracking;
    BOOL _castDismissingModal;
    BOOL _castError;
    BOOL _homeVisible;
    BOOL _menuOpen;
    BOOL _controlsHidden;
    BOOL _depthMode;
    BOOL _settingsOpen;
    NSInteger _secondaryMenuMode;
    BOOL _appPowerSleepActive;
    AVPlayer *_remoteVideoPlayer;
    AVPlayerLayer *_remoteVideoLayer;
    MPMoviePlayerController *_moviePlayer;
    UIView *_videoOverlay;
    UIView *_volumePanel;
    UISlider *_videoSlider;
    UILabel *_videoCurrentLabel;
    NSString *_videoCurrentPath;
    NSString *_castSrc;
    NSString *_castTitle;
    NSURL *_pendingCastURL;
    UIView *_videoTapShield;
    UIView *_videoControls;
    UIView *_menu;
    UIView *_menuButton;
    UIView *_homePanel;
    UIView *_settingsMenu;
    UIView *_powerSleepOverlay;
    IWTestAudioPlayer *_player;
    NSUInteger _editCommitCount;
    NSMutableArray *_events;
    NSMutableArray *_openedURLs;
    NSDictionary *_lastLocalVideoFinish;
    NSURL *_videoCurrentURL;
    NSTimer *_videoTimer;
    NSTimer *_videoHideTimer;
}
- (NSString *)formatVideoTime:(NSTimeInterval)seconds;
- (void)updateVideoControls;
- (void)scheduleVideoControlsAutoHide;
- (void)hideVideoControlsTimerFired;
- (void)videoAccessibilityStatusChanged:(NSNotification *)notification;
- (void)removeRemoteVideoObservers;
- (void)seekVideoToTime:(NSTimeInterval)value;
- (void)invalidatePendingVideoClose;
- (void)closeVideo;
- (void)commitEditModeForLifecycle;
- (void)finishEditMode;
- (void)resetSurfaceTouchState;
- (void)writeDebugState:(NSString *)context;
- (void)setDepthDemoEnabled:(BOOL)enabled;
- (void)updateMenuButtons;
- (void)setVideoControlsVisible:(BOOL)visible animated:(BOOL)animated;
- (void)startVideoTimer;
- (void)openMovieURL:(NSURL *)url identity:(NSString *)identity;
- (void)restoreMinimizedVideo;
- (void)openMoviePath:(NSString *)path;
- (void)openCastURL:(NSURL *)url;
- (void)returnToMainScreen;
@end

@implementation IWRootViewController
- (instancetype)init {
    self = [super init];
    if (self) {
        _events = [NSMutableArray array];
        IWCurrentEventSink = _events;
        _openedURLs = [NSMutableArray array];
        self.view.events = _events;
        _remoteVideoPlayer = [[AVPlayer alloc] init];
        _remoteVideoLayer = [[AVPlayerLayer alloc] init];
        _moviePlayer = [[MPMoviePlayerController alloc] init];
        _videoOverlay = [[UIView alloc] init];
        _videoOverlay.hidden = YES;
        UIView *playerContainer = [[UIView alloc] init];
        playerContainer.tag = 501;
        [_videoOverlay addSubview:playerContainer];
        [playerContainer addSubview:_moviePlayer.view];
        _videoTapShield = [[UIView alloc] init];
        _videoControls = [[UIView alloc] init];
        _volumePanel = [[UIView alloc] init];
        _videoSlider = [[UISlider alloc] init];
        _videoCurrentLabel = [[UILabel alloc] init];
        _menu = [[UIView alloc] init];
        _menuButton = [[UIView alloc] init];
        _homePanel = [[UIView alloc] init];
        _settingsMenu = [[UIView alloc] init];
        _powerSleepOverlay = [[UIView alloc] init];
        _player = [[IWTestAudioPlayer alloc] init];
        _player.events = _events;
    }
    return self;
}
- (NSString *)formatVideoTime:(NSTimeInterval)seconds { return [NSString stringWithFormat:@"%.0f", seconds]; }
- (void)updateVideoControls {}
- (void)removeRemoteVideoObservers {}
- (void)finishEditMode { _editMode = NO; _editCommitCount += 1; [_events addObject:@"edit-commit"]; }
- (void)resetSurfaceTouchState {}
- (void)writeDebugState:(NSString *)context { (void)context; }
- (void)setDepthDemoEnabled:(BOOL)enabled { (void)enabled; _depthMode = NO; }
- (void)updateMenuButtons {}
- (void)setVideoControlsVisible:(BOOL)visible animated:(BOOL)animated { _videoControlsVisible = visible; (void)animated; }
- (void)startVideoTimer {}
'''

generated += "\nstatic const BOOL IWProductionMovieAutoplayDisabled = "
generated += "YES;\n" if production_movie_autoplay_disabled else "NO;\n"
generated += fixture_types + "\n" + fixture_helper + "\n"
generated += "\n".join(methods)
generated += r'''

@end

static void IWResetAnimationCompletions(void) {
    [IWAnimationCompletions removeAllObjects];
}

static void IWCompleteAnimationAtIndex(NSUInteger index) {
    void (^completion)(BOOL) = [IWAnimationCompletions objectAtIndex:index];
    [IWAnimationCompletions replaceObjectAtIndex:index withObject:[NSNull null]];
    completion(YES);
}

static IWRootViewController *IWNewPlayingController(void) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    controller->_usingRemoteVideoPlayer = YES;
    controller->_videoUserPaused = NO;
    return controller;
}

static void IWCompleteSeekAndDrain(AVPlayer *player, NSUInteger index) {
    [player completeSeekAtIndex:index finished:YES];
    IWDrainMainQueue();
}

static void IWCompletePrerollAndDrain(AVPlayer *player, NSUInteger index) {
    [player completePrerollAtIndex:index finished:YES];
    IWDrainMainQueue();
}

static void IWTestPauseDuringSeek(void) {
    IWRootViewController *controller = IWNewPlayingController();
    AVPlayer *player = controller->_remoteVideoPlayer;
    [controller seekVideoToTime:42.0];
    controller->_videoUserPaused = YES;
    IWCompleteSeekAndDrain(player, 0);
    if ([player.prerollCompletions count] > 0) IWCompletePrerollAndDrain(player, 0);
    IWCheck(player.playCount == 0, @"pause during seek remains paused after completion");
    IWCheck(controller->_videoUserPaused && !controller->_remoteVideoSeeking,
            @"pause during seek leaves paused UI and clears pending state");
}

static void IWTestPauseDuringPreroll(void) {
    IWRootViewController *controller = IWNewPlayingController();
    AVPlayer *player = controller->_remoteVideoPlayer;
    [controller seekVideoToTime:84.0];
    IWCompleteSeekAndDrain(player, 0);
    IWCheck([player.prerollCompletions count] == 1, @"successful seek queues preroll");
    controller->_videoUserPaused = YES;
    IWCompletePrerollAndDrain(player, 0);
    IWCheck(player.playCount == 0, @"pause during preroll remains paused after completion");
    IWCheck(controller->_videoUserPaused && !controller->_remoteVideoSeeking,
            @"pause during preroll leaves paused UI and clears pending state");
}

static void IWTestNormalResumeAndSupersededSeek(void) {
    IWRootViewController *controller = IWNewPlayingController();
    AVPlayer *player = controller->_remoteVideoPlayer;
    [controller seekVideoToTime:10.0];
    IWCompleteSeekAndDrain(player, 0);
    IWCompletePrerollAndDrain(player, 0);
    IWCheck(player.playCount == 1 && !controller->_remoteVideoSeeking,
            @"successful seek resumes playback after preroll");

    controller = IWNewPlayingController();
    player = controller->_remoteVideoPlayer;
    [controller seekVideoToTime:20.0];
    [controller seekVideoToTime:30.0];
    IWCompleteSeekAndDrain(player, 0);
    IWCheck([player.prerollCompletions count] == 0 && player.playCount == 0,
            @"superseded seek completion cannot preroll or play");
    IWCompleteSeekAndDrain(player, 1);
    IWCompletePrerollAndDrain(player, 0);
    IWCheck(player.playCount == 1 && !controller->_remoteVideoSeeking,
            @"latest seek completes and resumes normally");
}

static void IWTestCloseThenInvalidateSuccessor(void) {
    IWResetAnimationCompletions();
    IWRootViewController *controller = IWNewPlayingController();
    controller->_videoOverlay.hidden = NO;
    [controller closeVideo];
    IWCheck([IWAnimationCompletions count] == 1, @"close stores its fade completion");
    [controller invalidatePendingVideoClose];
    controller->_videoOverlay.hidden = NO; // successor open makes the overlay visible
    IWCompleteAnimationAtIndex(0);
    IWCheck(!controller->_videoOverlay.hidden,
            @"stale close completion cannot hide the successor overlay");
    IWCheck(!controller->_closingVideo,
            @"stale close completion cannot overwrite successor closing state");
}

static IWRootViewController *IWNewMinimizedVideo(BOOL remote, BOOL paused, NSTimeInterval position) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    controller->_videoMinimized = YES;
    controller->_videoOverlay.hidden = YES;
    controller->_videoUserPaused = paused;
    controller->_usingRemoteVideoPlayer = remote;
    controller->_moviePlayer.shouldAutoplay = YES; // prepareToPlay would restart playback in this fake.
    controller->_moviePlayer.currentPlaybackTime = position;
    controller->_moviePlayer.currentPlaybackTimeWriteCount = 0;
    controller->_moviePlayer.playing = paused;
    controller->_remoteVideoPlayer.currentTime = CMTimeMakeWithSeconds(position, 600);
    controller->_remoteVideoPlayer.playing = paused;
    return controller;
}

static void IWCheckMinimizedPlayerRetained(IWRootViewController *controller,
                                            BOOL remote,
                                            BOOL paused,
                                            NSTimeInterval position,
                                            NSUInteger moviePlayBefore,
                                            NSUInteger moviePauseBefore,
                                            NSUInteger remotePlayBefore,
                                            NSUInteger remotePauseBefore) {
    MPMoviePlayerController *movie = controller->_moviePlayer;
    AVPlayer *remotePlayer = controller->_remoteVideoPlayer;
    NSUInteger prepareBefore = movie.prepareCount;
    NSUInteger contentURLBefore = movie.contentURLWriteCount;
    NSURL *contentURL = movie.contentURL;
    [controller restoreMinimizedVideo];

    IWCheck(!controller->_videoMinimized && !controller->_videoOverlay.hidden,
            @"restoring a minimized player reveals the existing overlay");
    UIView *container = [controller->_videoOverlay viewWithTag:501];
    IWCheck(movie.view.superview == container && [container.subviews containsObject:movie.view],
            @"restore reparents the retained local player view into its original container");
    IWCheck(movie.currentPlaybackTime == position &&
            IWSecondsFromCMTimeSafe(remotePlayer.currentTime) == position &&
            movie.currentPlaybackTimeWriteCount == 0,
            @"restore retains local and remote playback positions without seeking");
    IWCheck(movie.prepareCount == prepareBefore && movie.contentURLWriteCount == contentURLBefore &&
            movie.contentURL == contentURL,
            @"restore neither prepares nor reloads the local player");

    if (paused) {
        IWCheck(remote ? (!remotePlayer.isPlaying && remotePlayer.pauseCount == remotePauseBefore + 1 &&
                          remotePlayer.playCount == remotePlayBefore) :
                         (!movie.isPlaying && movie.pauseCount == moviePauseBefore + 1 &&
                          movie.playCount == moviePlayBefore),
                @"paused restore explicitly pauses the active player without resuming it");
    } else {
        IWCheck(remote ? (remotePlayer.isPlaying && remotePlayer.playCount == remotePlayBefore + 1 &&
                          remotePlayer.pauseCount == remotePauseBefore) :
                         (movie.isPlaying && movie.playCount == moviePlayBefore + 1 &&
                          movie.pauseCount == moviePauseBefore),
                @"playing restore resumes only the active player");
    }
    IWCheck(movie.shouldAutoplay && movie.prepareCount == 0,
            @"autoplay-sensitive fake confirms restore never calls prepareToPlay");
}

static void IWTestMinimizedPlaybackRestore(void) {
    IWCheck(IWProductionMovieAutoplayDisabled,
            @"production MPMoviePlayer setup disables implicit autoplay");
    IWRootViewController *controller = IWNewMinimizedVideo(NO, YES, 123.5);
    controller->_moviePlayer.playing = YES; // Catch a restore path that leaves autoplay running.
    IWCheckMinimizedPlayerRetained(controller, NO, YES, 123.5,
                                   controller->_moviePlayer.playCount, controller->_moviePlayer.pauseCount,
                                   controller->_remoteVideoPlayer.playCount, controller->_remoteVideoPlayer.pauseCount);

    controller = IWNewMinimizedVideo(YES, YES, 45.25);
    controller->_remoteVideoPlayer.playing = YES;
    IWCheckMinimizedPlayerRetained(controller, YES, YES, 45.25,
                                   controller->_moviePlayer.playCount, controller->_moviePlayer.pauseCount,
                                   controller->_remoteVideoPlayer.playCount, controller->_remoteVideoPlayer.pauseCount);

    controller = IWNewMinimizedVideo(NO, NO, 67.0);
    IWCheckMinimizedPlayerRetained(controller, NO, NO, 67.0,
                                   controller->_moviePlayer.playCount, controller->_moviePlayer.pauseCount,
                                   controller->_remoteVideoPlayer.playCount, controller->_remoteVideoPlayer.pauseCount);

    controller = IWNewMinimizedVideo(YES, NO, 89.75);
    IWCheckMinimizedPlayerRetained(controller, YES, NO, 89.75,
                                   controller->_moviePlayer.playCount, controller->_moviePlayer.pauseCount,
                                   controller->_remoteVideoPlayer.playCount, controller->_remoteVideoPlayer.pauseCount);
}

static void IWTestMovieFinishedIgnoresStaleAndRemoteNotifications(void) {
    IWResetAnimationCompletions();
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    controller->_videoOverlay.hidden = NO;
    controller->_usingRemoteVideoPlayer = YES;
    controller->_videoCurrentURL = [NSURL URLWithString:@"https://media.test/remote-successor.mp4"];
    NSNotification *remoteOverlap = [NSNotification notificationWithName:@"movie-finished"
                                                                  object:controller->_moviePlayer];
    [controller movieFinished:remoteOverlap];
    IWCheck(IWAnimationCompletions.count == 0 && !controller->_closingVideo &&
            controller->_videoCurrentURL != nil && !controller->_videoOverlay.hidden,
            @"a local-player completion arriving during remote playback cannot close the remote successor");

    controller = [[IWRootViewController alloc] init];
    controller->_videoOverlay.hidden = NO;
    controller->_videoCurrentURL = [NSURL URLWithString:@"file:///tmp/new-local-successor.mp4"];
    MPMoviePlayerController *staleMovie = [[MPMoviePlayerController alloc] init];
    NSNotification *stale = [NSNotification notificationWithName:@"movie-finished" object:staleMovie];
    [controller movieFinished:stale];
    IWCheck(IWAnimationCompletions.count == 0 && !controller->_closingVideo &&
            controller->_videoCurrentURL != nil && !controller->_videoOverlay.hidden,
            @"a completion from a replaced local player cannot close the current successor");

    NSNotification *userExit = [NSNotification notificationWithName:@"movie-finished"
                                                              object:controller->_moviePlayer
                                                            userInfo:@{MPMoviePlayerPlaybackDidFinishReasonUserInfoKey: @(MPMovieFinishReasonUserExited)}];
    [controller movieFinished:userExit];
    IWCheck(IWAnimationCompletions.count == 0 && !controller->_closingVideo,
            @"user-exit completion remains distinct from natural local playback completion");

    NSNotification *natural = [NSNotification notificationWithName:@"movie-finished"
                                                             object:controller->_moviePlayer];
    [controller movieFinished:natural];
    IWCheck(IWAnimationCompletions.count == 1 && controller->_closingVideo &&
            controller->_videoCurrentURL == nil,
            @"the current local player's natural completion still closes its video");
}

static NSUInteger IWEventIndex(NSArray *events, NSString *event) {
    return [events indexOfObject:event];
}

static NSUInteger IWEventCount(NSArray *events, NSString *event) {
    NSUInteger count = 0;
    for (NSString *candidate in events) if ([candidate isEqualToString:event]) count += 1;
    return count;
}

static NSURL *IWCastURL(NSString *path) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://cast.test/%@.mp4", path]];
}

static void IWTestCastFromHomeAndEdit(void) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    NSURL *url = IWCastURL(@"home");
    [controller openCastURL:url];
    IWCheck([controller->_videoCurrentURL isEqual:url] && controller->_remoteVideoPlayer.playCount == 1,
            @"home Cast request opens and plays the requested URL");
    IWCheck(controller.view.frontCount == 1 && !controller->_videoOverlay.hidden,
            @"home Cast request presents the video overlay");

    controller = [[IWRootViewController alloc] init];
    controller->_editMode = YES;
    controller->_player.playing = YES;
    [controller openCastURL:IWCastURL(@"edit")];
    IWCheck(!controller->_editMode && controller->_editCommitCount == 1,
            @"Cast transition commits an active edit");
    IWCheck(!controller->_player.playing,
            @"Cast transition pauses regular music before opening video");
    NSUInteger commit = IWEventIndex(controller->_events, @"edit-commit");
    NSUInteger musicPause = IWEventIndex(controller->_events, @"music-pause");
    NSUInteger videoPlay = IWEventIndex(controller->_events, @"video-play");
    NSUInteger videoFront = IWEventIndex(controller->_events, @"front-child");
    IWCheck(commit < musicPause && musicPause < videoPlay && videoPlay < videoFront,
            @"edit and music cleanup precede video playback and fronting");
}

static void IWTestGalleryDismissDefersAndKeepsLatestCast(void) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    UIViewController *gallery = [[UIViewController alloc] init];
    controller.presentedViewController = gallery;
    NSURL *first = IWCastURL(@"first");
    NSURL *latest = IWCastURL(@"latest");

    [controller openCastURL:first];
    IWCheck(controller.dismissCount == 1 && controller->_remoteVideoPlayer.playCount == 0,
            @"Cast waits for the presented gallery to dismiss");
    [controller openCastURL:latest];
    IWCheck(controller.dismissCount == 1 && [controller->_pendingCastURL isEqual:latest],
            @"rapid Cast replacement updates the pending URL without a second dismissal");

    [controller completeDismissalAtIndex:0];
    IWCheck([controller->_videoCurrentURL isEqual:latest] && [controller->_remoteVideoPlayer.url isEqual:latest],
            @"gallery dismissal opens only the latest Cast URL");
    IWCheck(controller->_remoteVideoPlayer.playCount == 1 && controller->_pendingCastURL == nil &&
            !controller->_castDismissingModal && controller.view.frontCount == 1 &&
            IWEventCount(controller->_events, @"video-play") == 1,
            @"latest Cast starts once after dismissal and is brought forward");
}

static void IWTestHomeCancelsPendingCast(void) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    controller.presentedViewController = [[UIViewController alloc] init];
    [controller openCastURL:IWCastURL(@"cancelled")];
    IWCheck(controller->_pendingCastURL != nil && controller->_remoteVideoPlayer.playCount == 0,
            @"Cast request is pending while a modal is presented");
    [controller returnToMainScreen];
    [controller completeDismissalAtIndex:0];
    IWCheck(controller->_pendingCastURL == nil && controller->_remoteVideoPlayer.playCount == 0 &&
            !controller->_castDismissingModal && IWEventCount(controller->_events, @"video-play") == 0,
            @"returning home cancels the pending Cast before dismissal completion");
}

static void IWTestLocalVideoPathSkipsCastPreflight(void) {
    IWRootViewController *controller = [[IWRootViewController alloc] init];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"wizard-local-video-%@.mp4", [[NSUUID UUID] UUIDString]]];
    NSData *fixture = [@"local" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wrote = [fixture writeToFile:path atomically:YES];
    IWCheck(wrote, @"local video fixture is created");
    [controller openMoviePath:path];
    IWCheck([controller->_videoCurrentURL isFileURL] && [controller->_videoCurrentPath isEqualToString:path],
            @"ordinary local video still follows openMoviePath directly");
    IWCheck(controller.dismissCount == 0 && controller->_editCommitCount == 0,
            @"local video path does not run the incoming-Cast edit cleanup preflight");
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

static void IWTestVideoControlsRemainAvailableToVoiceOver(void) {
    IWRootViewController *controller = IWNewPlayingController();
    controller->_videoOverlay.hidden = NO;
    controller->_videoControlsVisible = YES;
    IWTestVoiceOverRunning = NO;
    [controller scheduleVideoControlsAutoHide];
    NSTimer *oldTimer = controller->_videoHideTimer;
    IWCheck(oldTimer.valid, @"normal playing video schedules its existing auto-hide timer");
    IWTestVoiceOverRunning = YES;
    [controller scheduleVideoControlsAutoHide];
    IWCheck(!oldTimer.valid && controller->_videoHideTimer == nil, @"VoiceOver cancels the old timer without starting another");
    [controller hideVideoControlsTimerFired];
    IWCheck(controller->_videoControlsVisible, @"a racing timer cannot hide VoiceOver controls");
    IWTestVoiceOverRunning = NO;
    [controller hideVideoControlsTimerFired];
    IWCheck(!controller->_videoControlsVisible, @"normal playing video still auto-hides controls");
    controller->_videoControlsVisible = YES;
    controller->_videoUserPaused = YES;
    [controller scheduleVideoControlsAutoHide];
    [controller hideVideoControlsTimerFired];
    IWCheck(controller->_videoControlsVisible && controller->_videoHideTimer == nil, @"paused video keeps controls and no timer");
    controller->_videoUserPaused = NO;
    IWTestVoiceOverRunning = YES;
    controller->_videoControlsVisible = NO;
    [controller videoAccessibilityStatusChanged:nil];
    IWCheck(controller->_videoControlsVisible && controller->_videoHideTimer == nil, @"enabling VoiceOver reveals existing video controls");
    IWTestVoiceOverRunning = NO;
    [controller videoAccessibilityStatusChanged:nil];
    IWCheck(controller->_videoControlsVisible && controller->_videoHideTimer.valid, @"disabling VoiceOver restores normal auto-hide scheduling");
    controller->_videoOverlay.hidden = YES;
    controller->_videoControlsVisible = NO;
    [controller videoAccessibilityStatusChanged:nil];
    IWCheck(!controller->_videoControlsVisible && controller->_videoHideTimer == nil, @"status change leaves a closed or minimized overlay hidden");
    [controller->_videoHideTimer invalidate];
    IWTestVoiceOverRunning = NO;
}

static NSString *IWCreateFixtureParent(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"wizard-fixture-guard-%@", [[NSUUID UUID] UUIDString]]];
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
    IWCheck(created, @"fixture test parent is created");
    return path;
}

static NSString *IWFixtureRoot(NSString *parent, NSString *nonce) {
    return [parent stringByAppendingPathComponent:
            [@".wizard-local-video-audit-" stringByAppendingString:nonce]];
}

static NSString *IWFixtureMarker(NSString *parent) {
    return [parent stringByAppendingPathComponent:@"marker"];
}

static BOOL IWWriteFixtureFile(NSString *path, NSData *data, mode_t mode) {
    if (![data writeToFile:path atomically:NO]) return NO;
    return chmod([path fileSystemRepresentation], mode) == 0;
}

static BOOL IWCreateValidFixture(NSString *parent, NSString *nonce) {
    NSString *root = IWFixtureRoot(parent, nonce);
    NSString *marker = IWFixtureMarker(parent);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:root
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:&error]) return NO;
    if (chmod([root fileSystemRepresentation], 0700) != 0) return NO;
    NSData *nonceData = [nonce dataUsingEncoding:NSASCIIStringEncoding];
    NSData *fixtureData = [@"x" dataUsingEncoding:NSASCIIStringEncoding];
    return IWWriteFixtureFile(marker, nonceData, 0600) &&
           IWWriteFixtureFile([root stringByAppendingPathComponent:@"fixture.mp4"], fixtureData, 0600);
}

static void IWExpectFixtureStatus(NSString *marker, NSString *parent, uid_t expectedUID,
                                  IWLocalVideoFixtureStatus expectedStatus, NSString *expectedPath,
                                  NSString *message) {
    NSString *resolved = @"must be cleared";
    IWLocalVideoFixtureStatus status = IWResolveLocalVideoFixture(marker, parent, expectedUID, &resolved);
    IWCheck(status == expectedStatus, message);
    if (expectedStatus == IWLocalVideoFixtureStatusValid) {
        IWCheck([resolved isEqualToString:expectedPath], [message stringByAppendingString:@" (canonical fixture path)"]);
    } else {
        IWCheck(resolved == nil, [message stringByAppendingString:@" (no path on rejection)"]);
    }
}

static void IWTestLocalVideoFixtureGuard(void) {
    NSString *parent = IWCreateFixtureParent();
    NSString *nonce = @"0123456789abcdefabcd";
    NSString *marker = IWFixtureMarker(parent);
    NSString *root = IWFixtureRoot(parent, nonce);
    char canonicalParentBytes[PATH_MAX];
    IWCheck(realpath([parent fileSystemRepresentation], canonicalParentBytes) != NULL,
            @"fixture parent canonical path resolves");
    NSString *canonicalParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:canonicalParentBytes
                                                                                              length:strlen(canonicalParentBytes)];
    NSString *fixture = [[IWFixtureRoot(canonicalParent, nonce) stringByAppendingPathComponent:@"fixture.mp4"] copy];
    uid_t uid = getuid();

    IWExpectFixtureStatus([parent stringByAppendingPathComponent:@"absent"], parent, uid,
                          IWLocalVideoFixtureStatusAbsent, nil, @"truly absent marker keeps fallback eligible");
    IWCheck(symlink("missing-target", [[parent stringByAppendingPathComponent:@"broken-marker"] fileSystemRepresentation]) == 0,
            @"broken marker symlink is created");
    IWExpectFixtureStatus([parent stringByAppendingPathComponent:@"broken-marker"], parent, uid,
                          IWLocalVideoFixtureStatusInvalid, nil, @"broken marker symlink fails closed instead of looking absent");

    IWCheck(IWCreateValidFixture(parent, nonce), @"valid marker, private root, and fixture are created");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusValid, fixture,
                          @"valid fixture resolves to the exact direct child");

    NSString *parentAlias = [parent stringByAppendingPathComponent:@"parent-alias"];
    IWCheck(symlink([parent fileSystemRepresentation], [parentAlias fileSystemRepresentation]) == 0,
            @"canonical parent alias is created");
    IWExpectFixtureStatus(marker, parentAlias, uid, IWLocalVideoFixtureStatusValid, fixture,
                          @"symlinked parent root canonicalizes to the same fixture");

    IWCheck(chmod([marker fileSystemRepresentation], 0644) == 0, @"marker mode is made permissive");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"marker mode must be exactly 0600");
    chmod([marker fileSystemRepresentation], 0600);

    IWCheck(chmod([marker fileSystemRepresentation], 0600) == 0, @"marker mode is restored");
    NSData *malformedNonce = [@"../etc/passwd......." dataUsingEncoding:NSASCIIStringEncoding];
    IWCheck(IWWriteFixtureFile(marker, malformedNonce, 0600), @"malformed nonce is written");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"malformed or traversal nonce is rejected");
    IWCheck(IWWriteFixtureFile(marker, [[nonce substringToIndex:19] dataUsingEncoding:NSASCIIStringEncoding], 0600),
            @"short nonce marker is written");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"marker length other than twenty bytes is rejected");
    IWCheck(IWWriteFixtureFile(marker, [nonce dataUsingEncoding:NSASCIIStringEncoding], 0600),
            @"valid nonce is restored");

    NSString *markerLink = [parent stringByAppendingPathComponent:@"marker-link"];
    IWCheck(symlink([marker fileSystemRepresentation], [markerLink fileSystemRepresentation]) == 0,
            @"marker symlink to a valid target is created");
    IWExpectFixtureStatus(markerLink, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"marker symlink is rejected even when its target is valid");

    IWExpectFixtureStatus(marker, parent, (uid_t)(uid + 1), IWLocalVideoFixtureStatusInvalid, nil,
                          @"wrong expected owner is rejected");

    IWCheck(chmod([root fileSystemRepresentation], 0755) == 0, @"fixture root mode is made permissive");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"root mode must be exactly 0700");
    chmod([root fileSystemRepresentation], 0700);

    NSString *fixtureLinkTarget = [parent stringByAppendingPathComponent:@"outside.mp4"];
    IWCheck(IWWriteFixtureFile(fixtureLinkTarget, [@"outside" dataUsingEncoding:NSASCIIStringEncoding], 0600),
            @"outside fixture target is created");
    [[NSFileManager defaultManager] removeItemAtPath:fixture error:nil];
    IWCheck(symlink([fixtureLinkTarget fileSystemRepresentation], [fixture fileSystemRepresentation]) == 0,
            @"fixture symlink is created");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"fixture symlink outside the guarded root is rejected");
    [[NSFileManager defaultManager] removeItemAtPath:fixture error:nil];

    IWCheck(IWWriteFixtureFile(fixture, [NSData data], 0600), @"empty fixture is created");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"empty fixture is rejected");
    NSMutableData *oversized = [NSMutableData dataWithLength:2 * 1024 * 1024 + 1];
    IWCheck(IWWriteFixtureFile(fixture, oversized, 0600), @"oversized fixture is created");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"fixture larger than 2 MiB is rejected");
    [[NSFileManager defaultManager] removeItemAtPath:fixture error:nil];
    IWCheck([[NSFileManager defaultManager] createDirectoryAtPath:fixture
                                    withIntermediateDirectories:NO
                                                     attributes:nil
                                                          error:nil],
            @"directory fixture is created");
    IWExpectFixtureStatus(marker, parent, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"non-regular fixture is rejected");

    NSString *symlinkRootBase = IWCreateFixtureParent();
    NSString *symlinkMarker = IWFixtureMarker(symlinkRootBase);
    NSString *symlinkRoot = IWFixtureRoot(symlinkRootBase, nonce);
    NSString *targetRoot = [symlinkRootBase stringByAppendingPathComponent:@"root-target"];
    IWCheck(IWCreateValidFixture(symlinkRootBase, nonce), @"root-symlink fixture is initially valid");
    IWCheck(rename([symlinkRoot fileSystemRepresentation], [targetRoot fileSystemRepresentation]) == 0,
            @"root directory is moved to a target name");
    IWCheck(symlink([targetRoot fileSystemRepresentation], [symlinkRoot fileSystemRepresentation]) == 0,
            @"root symlink is created");
    IWExpectFixtureStatus(symlinkMarker, symlinkRootBase, uid, IWLocalVideoFixtureStatusInvalid, nil,
                          @"fixture root symlink is rejected");

    [[NSFileManager defaultManager] removeItemAtPath:parent error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:symlinkRootBase error:nil];
}

int main(void) {
    @autoreleasepool {
        IWTestMainQueue = dispatch_queue_create("wizard.media.lifecycle.tests", DISPATCH_QUEUE_SERIAL);
        IWAnimationCompletions = [NSMutableArray array];
        IWTestPauseDuringSeek();
        IWTestPauseDuringPreroll();
        IWTestNormalResumeAndSupersededSeek();
        IWTestCloseThenInvalidateSuccessor();
        IWTestMinimizedPlaybackRestore();
        IWTestMovieFinishedIgnoresStaleAndRemoteNotifications();
        IWTestCastFromHomeAndEdit();
        IWTestGalleryDismissDefersAndKeepsLatestCast();
        IWTestHomeCancelsPendingCast();
        IWTestLocalVideoPathSkipsCastPreflight();
        IWTestLocalVideoFixtureGuard();
        IWTestVideoControlsRemainAvailableToVoiceOver();
        printf("media lifecycle regressions: %lu checks, %lu failures\n",
               (unsigned long)IWChecks, (unsigned long)IWFailures);
        return IWFailures ? 1 : 0;
    }
}
'''

with tempfile.TemporaryDirectory(prefix="wizard-media-lifecycle-") as temporary:
    generated_path = Path(temporary) / "media-lifecycle-harness.m"
    binary_path = Path(temporary) / "media-lifecycle-harness"
    generated_path.write_text(generated)
    subprocess.run(
        [
            "/usr/bin/clang",
            "-fobjc-arc",
            "-fblocks",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
            "-Werror=return-type",
            "-framework",
            "Foundation",
            "-framework",
            "CoreMedia",
            str(generated_path),
            "-o",
            str(binary_path),
        ],
        check=True,
    )
    subprocess.run([str(binary_path)], check=True)
