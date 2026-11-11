#import <Foundation/Foundation.h>

#include <arpa/inet.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#import "../IWHTTPTransport.h"

static NSUInteger IWTestCount = 0;
static NSUInteger IWFailureCount = 0;

static void IWCheck(BOOL condition, NSString *message) {
    IWTestCount += 1;
    if (!condition) {
        IWFailureCount += 1;
        fprintf(stderr, "FAIL: %s\n", [message UTF8String]);
    }
}

typedef struct {
    int socketFD;
    const unsigned char *bytes;
    NSUInteger length;
    NSUInteger chunkSize;
    useconds_t gapMicroseconds;
    useconds_t initialDelayMicroseconds;
    BOOL closeWhenDone;
} IWWritePlan;

static void *IWRunWriter(void *rawPlan) {
    IWWritePlan *plan = (IWWritePlan *)rawPlan;
    if (plan->initialDelayMicroseconds) usleep(plan->initialDelayMicroseconds);
    NSUInteger offset = 0;
    while (offset < plan->length) {
        NSUInteger amount = plan->chunkSize ? plan->chunkSize : plan->length - offset;
        if (amount > plan->length - offset) amount = plan->length - offset;
        ssize_t sent = send(plan->socketFD, plan->bytes + offset, amount, 0);
        if (sent <= 0) break;
        offset += (NSUInteger)sent;
        if (plan->gapMicroseconds && offset < plan->length) usleep(plan->gapMicroseconds);
    }
    if (plan->closeWhenDone) {
        shutdown(plan->socketFD, SHUT_RDWR);
        close(plan->socketFD);
    }
    return NULL;
}

static BOOL IWCreatePair(int sockets[2]) {
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) < 0) return NO;
    if (!IWHTTPPrepareAcceptedSocket(sockets[0], NULL) || !IWHTTPPrepareAcceptedSocket(sockets[1], NULL)) {
        close(sockets[0]);
        close(sockets[1]);
        return NO;
    }
    return YES;
}

static NSData *IWRequest(NSString *requestLine, NSString *headers, NSString *body) {
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *request = [NSString stringWithFormat:@"%@\r\n%@%@\r\n%@", requestLine, headers ?: @"",
                         [headers length] ? @"" : @"", body ?: @""];
    if ([bodyData length] && ![headers.lowercaseString containsString:@"content-length:"]) {
        request = [NSString stringWithFormat:@"%@\r\nContent-Length: %lu\r\n\r\n%@", requestLine,
                   (unsigned long)[bodyData length], body ?: @""];
    } else if (![headers length]) {
        request = [NSString stringWithFormat:@"%@\r\n\r\n%@", requestLine, body ?: @""];
    }
    return [request dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *IWReadWithPlan(NSData *input, NSUInteger chunkSize, useconds_t gapMicroseconds,
                              NSTimeInterval timeout, NSError **readError, NSTimeInterval *elapsed) {
    int sockets[2];
    if (!IWCreatePair(sockets)) return nil;
    IWWritePlan plan = {sockets[1], [input bytes], [input length], chunkSize, gapMicroseconds, 0, YES};
    pthread_t writer;
    if (pthread_create(&writer, NULL, IWRunWriter, &plan) != 0) {
        close(sockets[0]);
        close(sockets[1]);
        return nil;
    }
    NSTimeInterval start = IWHTTPMonotonicNow();
    NSData *result = IWHTTPReadRequest(sockets[0], timeout, readError);
    if (elapsed) *elapsed = IWHTTPMonotonicNow() - start;
    shutdown(sockets[0], SHUT_RDWR);
    close(sockets[0]);
    pthread_join(writer, NULL);
    return result;
}

static void IWTestValidGETAndSOAP(void) {
    NSError *error = nil;
    NSData *get = [@"GET /description.xml HTTP/1.1\r\nHost: localhost\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *readGET = IWReadWithPlan(get, 0, 0, 1.0, &error, NULL);
    IWCheck([readGET isEqualToData:get], @"Valid GET is returned exactly");
    IWCheck(error == nil, @"Valid GET has no transport error");

    NSString *soapBody = @"<s:Envelope><s:Body><u:SetAVTransportURI><CurrentURI>https://example.test/clip.mp4</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>";
    NSData *soap = IWRequest(@"POST /AVTransport/control HTTP/1.1",
                             [NSString stringWithFormat:@"Content-Length: %lu\r\nSOAPAction: \"SetAVTransportURI\"\r\n",
                              (unsigned long)[[soapBody dataUsingEncoding:NSUTF8StringEncoding] length]], soapBody);
    error = nil;
    NSData *readSOAP = IWReadWithPlan(soap, 0, 0, 1.0, &error, NULL);
    IWCheck([readSOAP isEqualToData:soap], @"Valid SOAP body is read to its declared Content-Length");
    IWCheck(error == nil, @"Valid SOAP has no transport error");

    error = nil;
    NSData *fragmented = IWReadWithPlan(soap, 3, 1000, 2.0, &error, NULL);
    IWCheck([fragmented isEqualToData:soap], @"Fragmented headers and body are reassembled exactly");
    IWCheck(error == nil, @"Fragmented valid SOAP has no transport error");
}

static void IWTestRejectedRequests(void) {
    NSError *error = nil;
    NSData *truncated = [@"POST /control HTTP/1.1\r\nContent-Length: 5\r\n\r\nab" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *result = IWReadWithPlan(truncated, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorTruncatedRequest,
            @"Connection close before Content-Length bytes is reported as truncation");

    NSData *malformed = [@"POST /control HTTP/1.1\r\nContent-Length: 2x\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    result = IWReadWithPlan(malformed, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorMalformedContentLength,
            @"Non-decimal Content-Length is rejected");

    NSData *duplicate = [@"POST /control HTTP/1.1\r\nContent-Length: 1\r\ncontent-length: 1\r\n\r\nx" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    result = IWReadWithPlan(duplicate, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorDuplicateContentLength,
            @"Duplicate Content-Length fields are rejected even when equal");

    NSData *transferEncoding = [@"POST /control HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\nx" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    result = IWReadWithPlan(transferEncoding, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorUnsupportedTransferEncoding,
            @"Transfer-Encoding is rejected");

    NSData *oversizedBody = [@"POST /control HTTP/1.1\r\nContent-Length: 262145\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    result = IWReadWithPlan(oversizedBody, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorBodyTooLarge,
            @"Body above 256 KiB is rejected before reading it");

    NSMutableData *oversizedHeader = [NSMutableData dataWithData:[@"GET / HTTP/1.1\r\nX-Fill: " dataUsingEncoding:NSASCIIStringEncoding]];
    unsigned char fill[4096];
    memset(fill, 'a', sizeof(fill));
    while ([oversizedHeader length] <= IWHTTPMaximumHeaderBytes) [oversizedHeader appendBytes:fill length:sizeof(fill)];
    error = nil;
    result = IWReadWithPlan(oversizedHeader, 0, 0, 1.0, &error, NULL);
    IWCheck(result == nil && error.code == IWHTTPTransportErrorHeaderTooLarge,
            @"Header above 32 KiB is rejected");
}

static void IWTestAbsoluteReadDeadline(void) {
    int sockets[2];
    if (!IWCreatePair(sockets)) {
        IWCheck(NO, @"Socketpair available for deadline test");
        return;
    }
    NSData *partial = [@"GET /deliberately-incomplete" dataUsingEncoding:NSUTF8StringEncoding];
    IWWritePlan plan = {sockets[1], [partial bytes], [partial length], 1, 30000, 0, YES};
    pthread_t writer;
    pthread_create(&writer, NULL, IWRunWriter, &plan);
    NSError *error = nil;
    NSTimeInterval elapsed = 0.0;
    NSTimeInterval start = IWHTTPMonotonicNow();
    NSData *result = IWHTTPReadRequest(sockets[0], 0.10, &error);
    elapsed = IWHTTPMonotonicNow() - start;
    IWCheck(result == nil && error.code == IWHTTPTransportErrorTimeout,
            @"Incomplete request times out against one absolute deadline");
    IWCheck(elapsed < 0.28, @"Read deadline is bounded rather than waiting for peer close");
    shutdown(sockets[0], SHUT_RDWR);
    close(sockets[0]);
    pthread_join(writer, NULL);
}

typedef struct {
    int socketFD;
    NSUInteger expectedLength;
    NSUInteger receivedLength;
    BOOL bytesValid;
} IWDrainPlan;

static void *IWRunDrainer(void *rawPlan) {
    IWDrainPlan *plan = (IWDrainPlan *)rawPlan;
    unsigned char bytes[8192];
    plan->bytesValid = YES;
    for (;;) {
        ssize_t received = recv(plan->socketFD, bytes, sizeof(bytes), 0);
        if (received == 0) break;
        if (received < 0) {
            if (errno == EINTR) continue;
            plan->bytesValid = NO;
            break;
        }
        for (ssize_t i = 0; i < received; i++) if (bytes[i] != 0x5a) plan->bytesValid = NO;
        plan->receivedLength += (NSUInteger)received;
        usleep(100);
    }
    return NULL;
}

static void IWTestSendPartialWritesAndDeadline(void) {
    int sockets[2];
    if (!IWCreatePair(sockets)) {
        IWCheck(NO, @"Socketpair available for partial-send test");
        return;
    }
    int smallBuffer = 4096;
    setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &smallBuffer, sizeof(smallBuffer));
    NSUInteger payloadLength = 1024u * 1024u;
    NSMutableData *payload = [NSMutableData dataWithLength:payloadLength];
    memset([payload mutableBytes], 0x5a, payloadLength);
    IWDrainPlan drainPlan = {sockets[1], payloadLength, 0, NO};
    pthread_t drainer;
    pthread_create(&drainer, NULL, IWRunDrainer, &drainPlan);
    NSError *error = nil;
    BOOL sent = IWHTTPSendData(sockets[0], payload, 4.0, &error);
    shutdown(sockets[0], SHUT_WR);
    pthread_join(drainer, NULL);
    IWCheck(sent && error == nil, @"Large response is sent across partial writes");
    IWCheck(drainPlan.receivedLength == payloadLength && drainPlan.bytesValid,
            @"Partial-send loop preserves every response byte");
    close(sockets[0]);
    close(sockets[1]);

    if (!IWCreatePair(sockets)) {
        IWCheck(NO, @"Socketpair available for send-deadline test");
        return;
    }
    setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &smallBuffer, sizeof(smallBuffer));
    NSMutableData *blockedPayload = [NSMutableData dataWithLength:4u * 1024u * 1024u];
    memset([blockedPayload mutableBytes], 0x5a, [blockedPayload length]);
    error = nil;
    NSTimeInterval start = IWHTTPMonotonicNow();
    sent = IWHTTPSendData(sockets[0], blockedPayload, 0.12, &error);
    NSTimeInterval elapsed = IWHTTPMonotonicNow() - start;
    IWCheck(!sent && error.code == IWHTTPTransportErrorTimeout,
            @"Send stops when its absolute deadline expires");
    IWCheck(elapsed < 0.35, @"Send deadline bounds a non-reading peer");
    close(sockets[0]);
    close(sockets[1]);
}

static void IWTestDisconnectDoesNotRaiseSIGPIPE(void) {
    pid_t child = fork();
    if (child == 0) {
        @autoreleasepool {
            int sockets[2];
            if (!IWCreatePair(sockets)) _exit(2);
            close(sockets[1]);
            NSError *error = nil;
            BOOL sent = IWHTTPSendData(sockets[0], [@"response" dataUsingEncoding:NSUTF8StringEncoding], 0.5, &error);
            close(sockets[0]);
            if (sent || error.code != IWHTTPTransportErrorSocket) _exit(3);
            _exit(0);
        }
    }
    if (child < 0) {
        IWCheck(NO, @"fork available for SIGPIPE isolation test");
        return;
    }
    int status = 0;
    waitpid(child, &status, 0);
    IWCheck(WIFEXITED(status) && WEXITSTATUS(status) == 0,
            @"Disconnected peer returns a send error without terminating the process");
}

static void IWTestLoopbackTCPRoundTrip(void) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) {
        IWCheck(NO, @"Loopback listener socket created");
        return;
    }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    BOOL setup = bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(listener, 1) == 0;
    socklen_t addressLength = sizeof(address);
    if (setup) setup = getsockname(listener, (struct sockaddr *)&address, &addressLength) == 0;
    int client = setup ? socket(AF_INET, SOCK_STREAM, 0) : -1;
    if (client >= 0) setup = connect(client, (struct sockaddr *)&address, sizeof(address)) == 0;
    int accepted = setup ? accept(listener, NULL, NULL) : -1;
    close(listener);
    if (client < 0 || accepted < 0 || !setup) {
        if (client >= 0) close(client);
        if (accepted >= 0) close(accepted);
        IWCheck(NO, @"Loopback TCP connection accepted");
        return;
    }

    NSData *request = [@"GET /description.xml HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL requestSent = IWHTTPSendData(client, request, 1.0, &error);
    shutdown(client, SHUT_WR);
    NSData *receivedRequest = IWHTTPReadRequest(accepted, 1.0, &error);
    NSData *response = [@"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL responseSent = IWHTTPSendData(accepted, response, 1.0, &error);
    close(accepted);
    NSMutableData *receivedResponse = [NSMutableData data];
    unsigned char buffer[128];
    ssize_t count;
    while ((count = recv(client, buffer, sizeof(buffer), 0)) > 0) [receivedResponse appendBytes:buffer length:(NSUInteger)count];
    close(client);
    IWCheck(requestSent && [receivedRequest isEqualToData:request], @"Loopback TCP request is read correctly");
    IWCheck(responseSent && [receivedResponse isEqualToData:response], @"Loopback TCP response is sent completely");
}

int main(void) {
    @autoreleasepool {
        IWTestValidGETAndSOAP();
        IWTestRejectedRequests();
        IWTestAbsoluteReadDeadline();
        IWTestSendPartialWritesAndDeadline();
        IWTestDisconnectDoesNotRaiseSIGPIPE();
        IWTestLoopbackTCPRoundTrip();
        fprintf(stdout, "%lu checks, %lu failures\n", (unsigned long)IWTestCount, (unsigned long)IWFailureCount);
        return IWFailureCount ? EXIT_FAILURE : EXIT_SUCCESS;
    }
}
