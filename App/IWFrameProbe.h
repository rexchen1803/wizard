#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

// Opt-in diagnostic only. Display-link delivery measures main-run-loop
// scheduling; it is not a measurement of compositor-presented frames.
@interface IWFrameProbe : NSObject
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSError *lastError;
- (BOOL)startWithContext:(NSString *)context duration:(NSTimeInterval)duration;
@end

@implementation IWFrameProbe {
    CADisplayLink *_probeLink;
    NSMutableArray *_intervals;
    NSString *_probeContext;
    NSTimeInterval _probeStartedAt;
    NSTimeInterval _firstTimestamp;
    NSTimeInterval _lastTimestamp;
    NSTimeInterval _expectedInterval;
    NSError *_probeError;
}

- (BOOL)running { return _probeLink != nil; }
- (NSError *)lastError { return _probeError; }

- (BOOL)startWithContext:(NSString *)context duration:(NSTimeInterval)duration {
    if (self.running || ![NSThread isMainThread]) return NO;
    _probeError = nil;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-frame-probe.json"];
    NSError *removeError = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] &&
        ![[NSFileManager defaultManager] removeItemAtPath:path error:&removeError]) {
        _probeError = removeError;
        return NO;
    }
    _probeContext = [context copy] ?: @"unknown";
    _intervals = [NSMutableArray array];
    _probeStartedAt = [[NSDate date] timeIntervalSince1970];
    _firstTimestamp = _lastTimestamp = 0.0;
    _expectedInterval = 1.0 / 60.0;
    _probeLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(probeTick:)];
    _probeLink.frameInterval = 1;
    [_probeLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(1.0, MIN(300.0, duration)) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self finishProbe];
    });
    return YES;
}

- (void)probeTick:(CADisplayLink *)link {
    if (link.duration > 0.0) _expectedInterval = link.duration;
    NSTimeInterval timestamp = link.timestamp;
    if (_firstTimestamp <= 0.0) _firstTimestamp = timestamp;
    if (_lastTimestamp > 0.0 && timestamp > _lastTimestamp) [_intervals addObject:@(timestamp - _lastTimestamp)];
    _lastTimestamp = timestamp;
}

- (void)finishProbe {
    if (!self.running) return;
    [_probeLink invalidate];
    _probeLink = nil;
    NSArray *sorted = [_intervals sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger count = [sorted count], late = 0, over50ms = 0;
    for (NSNumber *interval in sorted) {
        if ([interval doubleValue] > _expectedInterval * 1.5) late += 1;
        if ([interval doubleValue] >= 0.05) over50ms += 1;
    }
    NSTimeInterval sampledDuration = MAX(0.0, _lastTimestamp - _firstTimestamp);
    NSDictionary *report = @{
        @"measurement": @"main_runloop_display_link_delivery",
        @"context": _probeContext,
        @"startedAtEpoch": @(_probeStartedAt),
        @"completedAtEpoch": @([[NSDate date] timeIntervalSince1970]),
        @"sourceFingerprint": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WizardSourceFingerprint"] ?: @"unbound",
        @"buildVersion": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
        @"buildNumber": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
        @"sampledDurationSeconds": @(sampledDuration),
        @"intervalCount": @(count),
        @"displayLinkHz": @(sampledDuration > 0.0 ? count / sampledDuration : 0.0),
        @"expectedIntervalMs": @(_expectedInterval * 1000.0),
        @"p95IntervalMs": @(count ? [sorted[(NSUInteger)ceil(count * 0.95) - 1] doubleValue] * 1000.0 : 0.0),
        @"worstIntervalMs": @(count ? [[sorted lastObject] doubleValue] * 1000.0 : 0.0),
        @"lateIntervals": @(late),
        @"intervalsOver50Ms": @(over50ms)
    };
    NSError *writeError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&writeError];
    if (json) [json writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"wizardsystem-frame-probe.json"] options:NSDataWritingAtomic error:&writeError];
    _probeError = writeError;
    _intervals = nil;
}

- (void)dealloc { [_probeLink invalidate]; }
@end
