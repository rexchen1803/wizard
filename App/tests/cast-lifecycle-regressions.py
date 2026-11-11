#!/usr/bin/env python3
"""Extract the production IWDLNACastServer block and exercise its lifecycle on loopback."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/main.m"
text = SOURCE.read_text()
start = text.index("@interface IWDLNACastRunContext : NSObject")
end = text.index("@interface IWImagePickerController", start)
production = text[start:end]

preamble = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#import "IWHTTPTransport.h"

static volatile int IWAcceptFaultsRemaining = 0;
static volatile int IWInjectedAcceptFaults = 0;
static int IWTestAccept(int socketFD, struct sockaddr *address, socklen_t *length) {
    int remaining = __sync_add_and_fetch(&IWAcceptFaultsRemaining, 0);
    while (remaining > 0) {
        int observed = __sync_val_compare_and_swap(&IWAcceptFaultsRemaining, remaining, remaining - 1);
        if (observed == remaining) {
            __sync_add_and_fetch(&IWInjectedAcceptFaults, 1);
            errno = EAGAIN;
            return -1;
        }
        remaining = observed;
    }
    return accept(socketFD, address, length);
}
#define accept IWTestAccept

@interface UIDevice : NSObject
+ (instancetype)currentDevice;
@property (nonatomic, readonly) NSUUID *identifierForVendor;
@end
@implementation UIDevice
+ (instancetype)currentDevice { return [[self alloc] init]; }
- (NSUUID *)identifierForVendor { return [NSUUID UUID]; }
@end

static void IWCastLog(NSString *format, ...) { (void)format; }
static NSString *IWCastDeviceModelName(void) { return @"Lifecycle Test"; }
static NSString *IWLocalWiFiAddress(void) { return @"127.0.0.1"; }
static NSString *IWXMLValue(NSString *body, NSString *name) { (void)body; (void)name; return @""; }
static NSString *IWXMLFirstElementValue(NSString *body, NSString *name) { (void)body; (void)name; return @""; }
static NSString *IWHeaderValue(NSString *request, NSString *name) { (void)request; (void)name; return @""; }
static CGSize IWMetadataResolution(NSString *body) { (void)body; return CGSizeZero; }
static BOOL IWRemoteResolutionSupported(CGSize size) { (void)size; return YES; }

'''

tests = r'''
#undef accept

static NSUInteger IWChecks = 0;
static NSUInteger IWFailures = 0;

static void IWCheck(BOOL condition, NSString *message) {
    IWChecks += 1;
    if (!condition) {
        IWFailures += 1;
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
    }
}

@interface IWTestCastServer : IWDLNACastServer
@property (nonatomic, strong) NSMutableArray *events;
@property (nonatomic, assign) NSUInteger aliveNotificationCount;
@property (atomic, assign) BOOL injectHTTPException;
@property (atomic, assign) NSUInteger workerExitCount;
- (instancetype)initWithHTTPPort:(NSUInteger)httpPort ssdpPort:(NSUInteger)ssdpPort;
@end

@implementation IWTestCastServer
- (instancetype)initWithHTTPPort:(NSUInteger)httpPort ssdpPort:(NSUInteger)ssdpPort {
    self = [super initWithHTTPPort:httpPort
                          ssdpPort:ssdpPort
                       bindAddress:htonl(INADDR_LOOPBACK)
                     joinMulticast:NO];
    if (self) {
        _events = [NSMutableArray array];
        __weak IWTestCastServer *weakSelf = self;
        self.stateChangedHandler = ^(BOOL ready, NSError *error) {
            IWTestCastServer *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.events addObject:@{
                @"ready": @(ready),
                @"errorCode": @(error.code),
                @"errorText": error.localizedDescription ?: @""
            }];
        };
    }
    return self;
}
- (void)emitAliveNotificationsForContext:(IWDLNACastRunContext *)context {
    (void)context;
    self.aliveNotificationCount += 1;
}
- (void)handleHTTPClient:(int)client context:(IWDLNACastRunContext *)context {
    if (self.injectHTTPException) {
        self.injectHTTPException = NO;
        @throw [NSException exceptionWithName:@"InjectedHTTPFailure" reason:@"test" userInfo:nil];
    }
    [super handleHTTPClient:client context:context];
}
- (void)workerFinishedForContext:(IWDLNACastRunContext *)context {
    [super workerFinishedForContext:context];
    @synchronized (self) { self.workerExitCount += 1; }
}
@end

static NSUInteger IWUnusedLoopbackPort(int socketType) {
    int fd = socket(AF_INET, socketType, 0);
    if (fd < 0) return 0;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return 0;
    }
    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) < 0) {
        close(fd);
        return 0;
    }
    NSUInteger port = ntohs(address.sin_port);
    close(fd);
    return port;
}

static BOOL IWRunLoopUntilReady(IWTestCastServer *server, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        if (server.running) return YES;
    }
    return server.running;
}

static BOOL IWPollUntilReadyWithoutRunLoop(IWTestCastServer *server, NSTimeInterval timeout) {
    NSTimeInterval start = [NSProcessInfo processInfo].systemUptime;
    while ([NSProcessInfo processInfo].systemUptime - start < timeout) {
        if (server.running) return YES;
        usleep(10000);
    }
    return server.running;
}

static BOOL IWSendGETAndReadResponse(NSUInteger port) {
    int client = socket(AF_INET, SOCK_STREAM, 0);
    if (client < 0) return NO;
    struct timeval timeout = {2, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)port);
    BOOL ok = connect(client, (struct sockaddr *)&address, sizeof(address)) == 0;
    const char *request = "GET /description.xml HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    if (ok) ok = send(client, request, strlen(request), 0) == (ssize_t)strlen(request);
    NSMutableData *response = [NSMutableData data];
    if (ok) {
        unsigned char bytes[2048];
        for (;;) {
            ssize_t count = recv(client, bytes, sizeof(bytes), 0);
            if (count == 0) break;
            if (count < 0) { ok = NO; break; }
            [response appendBytes:bytes length:(NSUInteger)count];
        }
    }
    close(client);
    NSString *text = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    return ok && [text hasPrefix:@"HTTP/1.1 200 OK"] &&
           [text rangeOfString:@"WizardCast"].location != NSNotFound;
}

static int IWHoldLoopbackSocket(int socketType, NSUInteger *portOut) {
    int fd = socket(AF_INET, socketType, 0);
    if (fd < 0) return -1;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return -1;
    }
    if (socketType == SOCK_STREAM && listen(fd, 1) < 0) {
        close(fd);
        return -1;
    }
    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) < 0) {
        close(fd);
        return -1;
    }
    *portOut = ntohs(address.sin_port);
    return fd;
}

static BOOL IWWaitForEventMatching(IWTestCastServer *server, BOOL (^predicate)(NSDictionary *), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        for (NSDictionary *event in server.events) if (predicate(event)) return YES;
    }
    for (NSDictionary *event in server.events) if (predicate(event)) return YES;
    return NO;
}

static void IWTestLoopbackHTTPAndRapidRestart(void) {
    NSUInteger httpPort = IWUnusedLoopbackPort(SOCK_STREAM);
    NSUInteger ssdpPort = IWUnusedLoopbackPort(SOCK_DGRAM);
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    IWCheck(httpPort > 0 && ssdpPort > 0, @"loopback test ports allocated");
    IWCheck([server start], @"start accepts a run request");
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"HTTP and SSDP listeners become ready");
    IWCheck(IWSendGETAndReadResponse(server.httpPort), @"production HTTP loop serves a GET response");

    for (NSUInteger cycle = 0; cycle < 8; cycle++) {
        [server stop];
        IWCheck(!server.running, @"stop immediately clears composite readiness");
        IWCheck([server start], @"restart request is accepted while old workers unwind");
        IWCheck(IWRunLoopUntilReady(server, 3.0), @"deferred generation reaches readiness");
        IWCheck(IWSendGETAndReadResponse(server.httpPort), @"only the current generation serves HTTP");
    }
    [server stop];
    usleep(300000);
}

static void IWTestStalledClientStopDeadline(void) {
    NSUInteger httpPort = IWUnusedLoopbackPort(SOCK_STREAM);
    NSUInteger ssdpPort = IWUnusedLoopbackPort(SOCK_DGRAM);
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    [server start];
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"stalled-client server starts");

    int client = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)httpPort);
    BOOL connected = connect(client, (struct sockaddr *)&address, sizeof(address)) == 0;
    const char *partial = "POST /control HTTP/1.1\r\nContent-Length: 40\r\n\r\npartial";
    if (connected) send(client, partial, strlen(partial), 0);
    usleep(50000);

    NSTimeInterval start = [NSProcessInfo processInfo].systemUptime;
    [server stop];
    NSTimeInterval stopDuration = [NSProcessInfo processInfo].systemUptime - start;
    IWCheck(stopDuration < 0.25, @"stop invalidates state without waiting on stalled HTTP client");
    IWCheck([server start], @"start during bounded client read is queued");
    IWCheck(!server.running, @"old worker cannot report ready while draining stalled client");
    IWCheck(IWRunLoopUntilReady(server, 7.0), @"new generation starts after the five-second request deadline");
    if (client >= 0) close(client);
    [server stop];
    usleep(300000);
}

static void IWTestBindConflictAndPartialRecovery(void) {
    NSUInteger httpPort = 0;
    NSUInteger ssdpPort = 0;
    int httpHolder = IWHoldLoopbackSocket(SOCK_STREAM, &httpPort);
    int ssdpHolder = IWHoldLoopbackSocket(SOCK_DGRAM, &ssdpPort);
    IWCheck(httpHolder >= 0 && ssdpHolder >= 0, @"conflict sockets bound on loopback");
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    [server start];
    BOOL sawInitialError = IWWaitForEventMatching(server, ^BOOL(NSDictionary *event) {
        return [event[@"errorCode"] integerValue] == EADDRINUSE;
    }, 2.0);
    IWCheck(sawInitialError, @"bind conflict reaches the readiness handler");
    IWCheck(!server.running, @"bind conflict does not report running");
    if (httpHolder >= 0) close(httpHolder);
    BOOL sawRemainingSSDPError = IWWaitForEventMatching(server, ^BOOL(NSDictionary *event) {
        return ![event[@"ready"] boolValue] &&
               [event[@"errorText"] containsString:@"SSDP socket operation failed"];
    }, 2.5);
    IWCheck(sawRemainingSSDPError, @"HTTP recovery preserves the still-active SSDP error");
    IWCheck(!server.running, @"one recovered listener is not composite readiness");
    if (ssdpHolder >= 0) close(ssdpHolder);
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"server recovers after both ports are released");
    BOOL finalReadyWithoutError = NO;
    for (NSDictionary *event in [server.events reverseObjectEnumerator]) {
        if ([event[@"ready"] boolValue]) {
            finalReadyWithoutError = [event[@"errorCode"] integerValue] == 0;
            break;
        }
    }
    IWCheck(finalReadyWithoutError, @"final readiness clears transport errors");
    [server stop];
    usleep(300000);
}

static void IWTestTransientAcceptFailureRetiresListener(void) {
    NSUInteger httpPort = IWUnusedLoopbackPort(SOCK_STREAM);
    NSUInteger ssdpPort = IWUnusedLoopbackPort(SOCK_DGRAM);
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    [server start];
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"transient-accept test server starts");
    [server.events removeAllObjects];

    int queuedClient = socket(AF_INET, SOCK_STREAM, 0);
    int noSIGPIPE = 1;
    setsockopt(queuedClient, SOL_SOCKET, SO_NOSIGPIPE, &noSIGPIPE, sizeof(noSIGPIPE));
    struct timeval timeout = {2, 0};
    setsockopt(queuedClient, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)httpPort);

    IWInjectedAcceptFaults = 0;
    IWAcceptFaultsRemaining = 3;
    BOOL connected = queuedClient >= 0 &&
                     connect(queuedClient, (struct sockaddr *)&address, sizeof(address)) == 0;
    IWCheck(connected, @"a real loopback client queues on the ready listener");
    BOOL sawRetirement = IWWaitForEventMatching(server, ^BOOL(NSDictionary *event) {
        return ![event[@"ready"] boolValue] &&
               [event[@"errorCode"] integerValue] == EAGAIN;
    }, 2.0);
    IWCheck(IWInjectedAcceptFaults == 3, @"accept wrapper injected three transient EAGAIN results");
    IWCheck(sawRetirement, @"three consecutive accept EAGAIN results clear readiness and publish the error");
    IWCheck(IWRunLoopUntilReady(server, 4.0), @"listener recovers after transient accept failures");

    const char *request = "GET /description.xml HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    errno = 0;
    ssize_t sendLength = connected ? send(queuedClient, request, strlen(request), 0) : -1;
    int sendError = errno;
    char response[256];
    errno = 0;
    ssize_t responseLength = connected ? recv(queuedClient, response, sizeof(response), 0) : -1;
    int receiveError = errno;
    BOOL timedOut = responseLength < 0 && (receiveError == EAGAIN || receiveError == EWOULDBLOCK || receiveError == EINTR);
    BOOL queuedClientClosed = responseLength == 0 ||
                              (responseLength < 0 && !timedOut) ||
                              (sendLength < 0 && sendError != EAGAIN && sendError != EWOULDBLOCK && sendError != EINTR);
    IWCheck(queuedClientClosed, @"the client queued on the retired listener is closed, not served by the replacement");
    if (queuedClient >= 0) close(queuedClient);
    IWCheck(IWSendGETAndReadResponse(httpPort), @"replacement listener serves a fresh client");
    [server stop];
    usleep(300000);
}

static void IWTestStaleReadyAndAliveSuppression(void) {
    NSUInteger httpPort = IWUnusedLoopbackPort(SOCK_STREAM);
    NSUInteger ssdpPort = IWUnusedLoopbackPort(SOCK_DGRAM);
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    [server start];
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"fault-injection server starts");
    [server.events removeAllObjects];
    server.aliveNotificationCount = 0;

    [server debugInvalidateSockets];
    IWCheck(!server.running, @"debug invalidation clears readiness synchronously");
    IWCheck(IWPollUntilReadyWithoutRunLoop(server, 3.0), @"invalidated generation is replaced after its workers exit");
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    IWCheck(server.events.count == 1 && [server.events[0][@"ready"] boolValue],
            @"queued stale readiness events are suppressed in favor of the current generation");
    NSDate *aliveDeadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
    while (server.aliveNotificationCount == 0 && [aliveDeadline timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    IWCheck(server.aliveNotificationCount == 1, @"current ready generation emits one initial alive notification");
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    IWCheck(server.aliveNotificationCount == 1, @"cancelled generations do not emit duplicate alive notifications");
    [server stop];
    usleep(300000);
}

static void IWTestUnexpectedExitAndMalformedDatagram(void) {
    NSUInteger httpPort = IWUnusedLoopbackPort(SOCK_STREAM);
    NSUInteger ssdpPort = IWUnusedLoopbackPort(SOCK_DGRAM);
    IWTestCastServer *server = [[IWTestCastServer alloc] initWithHTTPPort:httpPort ssdpPort:ssdpPort];
    [server start];
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"exception-test server starts");
    server.injectHTTPException = YES;
    IWCheck(!IWSendGETAndReadResponse(httpPort), @"injected worker exception closes its accepted client");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while (server.workerExitCount == 0 && [deadline timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    IWCheck(server.workerExitCount > 0, @"failed worker completes its cleanup");
    IWCheck(IWRunLoopUntilReady(server, 3.0), @"peer retires and a new generation recovers after an exception");
    IWCheck(IWSendGETAndReadResponse(httpPort), @"recovered generation serves HTTP without leaked listener ownership");

    int client = socket(AF_INET, SOCK_DGRAM, 0);
    struct timeval timeout = {0, 300000};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address); address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons((uint16_t)ssdpPort);
    const unsigned char invalid[] = {0xff, 'M', '-', 'S', 'E', 'A', 'R', 'C', 'H'};
    sendto(client, invalid, sizeof(invalid), 0, (struct sockaddr *)&address, sizeof(address));
    char bytes[4096];
    IWCheck(recv(client, bytes, sizeof(bytes), 0) < 0, @"invalid UTF8 discovery packet is ignored");
    const char *valid = "M-SEARCH * HTTP/1.1\r\nST: ssdp:all\r\n\r\n";
    sendto(client, valid, strlen(valid), 0, (struct sockaddr *)&address, sizeof(address));
    ssize_t length = recv(client, bytes, sizeof(bytes), 0);
    IWCheck(length > 0 && !memcmp(bytes, "HTTP/1.1 200 OK", 15), @"valid discovery still works after a malformed packet");
    close(client); [server stop]; usleep(300000);
}

int main(void) {
    IWTestLoopbackHTTPAndRapidRestart();
    IWTestStalledClientStopDeadline();
    IWTestBindConflictAndPartialRecovery();
    IWTestTransientAcceptFailureRetiresListener();
    IWTestStaleReadyAndAliveSuppression();
    IWTestUnexpectedExitAndMalformedDatagram();
    printf("%lu checks, %lu failures\n", (unsigned long)IWChecks, (unsigned long)IWFailures);
    return IWFailures ? 1 : 0;
}
'''

with tempfile.TemporaryDirectory(prefix="iw-cast-lifecycle-") as temp:
    tempdir = Path(temp)
    generated = tempdir / "cast-lifecycle-regressions.m"
    binary = tempdir / "cast-lifecycle-regressions"
    generated.write_text(preamble + production + tests)
    compile_result = subprocess.run(
        [
            "/usr/bin/clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra",
            "-framework", "Foundation", "-framework", "CoreGraphics",
            "-I", str(ROOT / "App"), str(generated), "-o", str(binary),
        ],
        text=True, capture_output=True,
    )
    if compile_result.returncode:
        print(compile_result.stdout, end="")
        print(compile_result.stderr, end="")
        raise SystemExit(compile_result.returncode)
    if compile_result.stderr.strip():
        print(compile_result.stderr, end="")
    run_result = subprocess.run([str(binary)], text=True, capture_output=True)
    print(run_result.stdout, end="")
    print(run_result.stderr, end="")
    raise SystemExit(run_result.returncode)
