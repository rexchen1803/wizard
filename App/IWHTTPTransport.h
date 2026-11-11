#import <Foundation/Foundation.h>

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const NSUInteger IWHTTPMaximumHeaderBytes = 32u * 1024u;
static const NSUInteger IWHTTPMaximumBodyBytes = 256u * 1024u;

static NSString * const IWHTTPTransportErrorDomain = @"IWHTTPTransportErrorDomain";

typedef NS_ENUM(NSInteger, IWHTTPTransportErrorCode) {
    IWHTTPTransportErrorInvalidArgument = 1,
    IWHTTPTransportErrorSocket,
    IWHTTPTransportErrorTimeout,
    IWHTTPTransportErrorHeaderTooLarge,
    IWHTTPTransportErrorBodyTooLarge,
    IWHTTPTransportErrorMalformedHeader,
    IWHTTPTransportErrorMalformedContentLength,
    IWHTTPTransportErrorDuplicateContentLength,
    IWHTTPTransportErrorUnsupportedTransferEncoding,
    IWHTTPTransportErrorTruncatedRequest
};

static inline void IWHTTPSetTransportError(NSError **error, IWHTTPTransportErrorCode code, NSString *description) {
    if (!error) return;
    NSDictionary *info = description ? @{NSLocalizedDescriptionKey: description} : @{};
    *error = [NSError errorWithDomain:IWHTTPTransportErrorDomain code:code userInfo:info];
}

static inline NSTimeInterval IWHTTPMonotonicNow(void) {
    return [[NSProcessInfo processInfo] systemUptime];
}

static inline BOOL IWHTTPWaitForSocket(int socketFD, BOOL writable, NSTimeInterval deadline, NSError **error) {
    if (socketFD < 0 || socketFD >= FD_SETSIZE) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorInvalidArgument, @"Invalid socket descriptor");
        return NO;
    }

    for (;;) {
        NSTimeInterval remaining = deadline - IWHTTPMonotonicNow();
        if (remaining <= 0.0) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorTimeout, @"Socket operation exceeded its deadline");
            return NO;
        }

        struct timeval timeout;
        timeout.tv_sec = (time_t)remaining;
        timeout.tv_usec = (suseconds_t)((remaining - (NSTimeInterval)timeout.tv_sec) * 1000000.0);
        if (timeout.tv_usec < 0) timeout.tv_usec = 0;
        if (timeout.tv_usec >= 1000000) {
            timeout.tv_sec += 1;
            timeout.tv_usec -= 1000000;
        }

        fd_set ready;
        FD_ZERO(&ready);
        FD_SET(socketFD, &ready);
        int result = writable ? select(socketFD + 1, NULL, &ready, NULL, &timeout)
                              : select(socketFD + 1, &ready, NULL, NULL, &timeout);
        if (result > 0) {
            if (IWHTTPMonotonicNow() >= deadline) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorTimeout, @"Socket operation exceeded its deadline");
                return NO;
            }
            return YES;
        }
        if (result == 0) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorTimeout, @"Socket operation exceeded its deadline");
            return NO;
        }
        if (errno == EINTR) continue;
        IWHTTPSetTransportError(error, IWHTTPTransportErrorSocket,
                                [NSString stringWithFormat:@"select failed: %d", errno]);
        return NO;
    }
}

/* Call immediately after accept(); Apple requires SO_NOSIGPIPE on each client socket. */
static inline BOOL IWHTTPPrepareAcceptedSocket(int socketFD, NSError **error) {
    if (socketFD < 0) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorInvalidArgument, @"Invalid accepted socket");
        return NO;
    }
#if defined(SO_NOSIGPIPE)
    int enabled = 1;
    if (setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) < 0) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorSocket,
                                [NSString stringWithFormat:@"SO_NOSIGPIPE failed: %d", errno]);
        return NO;
    }
#endif
    return YES;
}

static inline NSUInteger IWHTTPHeaderTerminatorOffset(const unsigned char *bytes, NSUInteger length) {
    if (!bytes || length < 4) return NSNotFound;
    for (NSUInteger i = 0; i + 3 < length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' && bytes[i + 2] == '\r' && bytes[i + 3] == '\n') return i;
    }
    return NSNotFound;
}

static inline BOOL IWHTTPHeaderNameCharacter(unichar c) {
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) return YES;
    return [@"!#$%&'*+-.^_`|~" rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound;
}

static inline BOOL IWHTTPParseHeader(NSData *headerData, NSUInteger *contentLengthOut, NSError **error) {
    if ([headerData length] > IWHTTPMaximumHeaderBytes) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorHeaderTooLarge, @"HTTP header exceeds 32 KiB");
        return NO;
    }
    NSString *header = [[NSString alloc] initWithData:headerData encoding:NSASCIIStringEncoding];
    if (!header) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"HTTP header is not ASCII");
        return NO;
    }

    NSArray *lines = [header componentsSeparatedByString:@"\r\n"];
    if ([lines count] < 3 || ![[lines objectAtIndex:0] length]) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Missing HTTP request line");
        return NO;
    }
    NSString *requestLine = [lines objectAtIndex:0];
    for (NSUInteger i = 0; i < [requestLine length]; i++) {
        unichar c = [requestLine characterAtIndex:i];
        if (c < 0x20 || c == 0x7f) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Control character in HTTP request line");
            return NO;
        }
    }

    BOOL sawContentLength = NO;
    BOOL sawTransferEncoding = NO;
    NSUInteger parsedLength = 0;
    for (NSUInteger lineIndex = 1; lineIndex + 2 < [lines count]; lineIndex++) {
        NSString *line = [lines objectAtIndex:lineIndex];
        if (![line length]) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Unexpected empty HTTP header line");
            return NO;
        }
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound || colon.location == 0) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Malformed HTTP header field");
            return NO;
        }
        NSString *name = [line substringToIndex:colon.location];
        for (NSUInteger i = 0; i < [name length]; i++) {
            if (!IWHTTPHeaderNameCharacter([name characterAtIndex:i])) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Invalid HTTP header field name");
                return NO;
            }
        }
        NSString *value = [line substringFromIndex:NSMaxRange(colon)];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t"]];
        for (NSUInteger i = 0; i < [value length]; i++) {
            unichar c = [value characterAtIndex:i];
            if ((c < 0x20 && c != '\t') || c == 0x7f) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedHeader, @"Control character in HTTP header value");
                return NO;
            }
        }

        if ([name caseInsensitiveCompare:@"Transfer-Encoding"] == NSOrderedSame) {
            sawTransferEncoding = YES;
        } else if ([name caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
            if (sawContentLength) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorDuplicateContentLength, @"Duplicate Content-Length fields are ambiguous");
                return NO;
            }
            sawContentLength = YES;
            if (![value length]) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedContentLength, @"Empty Content-Length");
                return NO;
            }
            NSUInteger number = 0;
            for (NSUInteger i = 0; i < [value length]; i++) {
                unichar c = [value characterAtIndex:i];
                if (c < '0' || c > '9') {
                    IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedContentLength, @"Content-Length must be an unsigned decimal integer");
                    return NO;
                }
                NSUInteger digit = (NSUInteger)(c - '0');
                if (number > (NSUIntegerMax - digit) / 10u) {
                    IWHTTPSetTransportError(error, IWHTTPTransportErrorMalformedContentLength, @"Content-Length overflows the platform integer size");
                    return NO;
                }
                number = number * 10u + digit;
                if (number > IWHTTPMaximumBodyBytes) {
                    IWHTTPSetTransportError(error, IWHTTPTransportErrorBodyTooLarge, @"HTTP body exceeds 256 KiB");
                    return NO;
                }
            }
            parsedLength = number;
        }
    }

    if (sawTransferEncoding) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorUnsupportedTransferEncoding, @"Transfer-Encoding is unsupported");
        return NO;
    }
    if (contentLengthOut) *contentLengthOut = parsedLength;
    return YES;
}

/*
 * Reads one complete request under one monotonic deadline. The returned bytes contain
 * the complete header and exactly Content-Length body bytes; the caller owns socket
 * closure. Missing Content-Length means a zero-length body. Transfer-Encoding is
 * rejected because chunked request decoding is not implemented here.
 */
static inline NSData *IWHTTPReadRequest(int socketFD, NSTimeInterval timeoutSeconds, NSError **error) {
    if (socketFD < 0 || !isfinite(timeoutSeconds) || timeoutSeconds <= 0.0) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorInvalidArgument, @"A valid socket and positive timeout are required");
        return nil;
    }
    NSTimeInterval deadline = IWHTTPMonotonicNow() + timeoutSeconds;
    NSMutableData *request = [NSMutableData dataWithCapacity:4096];
    NSUInteger requiredLength = 0;
    BOOL parsedHeader = NO;
    unsigned char bytes[4096];

    for (;;) {
        NSUInteger currentLength = [request length];
        if (parsedHeader && currentLength >= requiredLength) {
            return [request subdataWithRange:NSMakeRange(0, requiredLength)];
        }

        if (!parsedHeader && currentLength >= IWHTTPMaximumHeaderBytes) {
            NSUInteger terminator = IWHTTPHeaderTerminatorOffset([request bytes], currentLength);
            if (terminator == NSNotFound || terminator + 4u > IWHTTPMaximumHeaderBytes) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorHeaderTooLarge, @"HTTP header exceeds 32 KiB");
                return nil;
            }
        }

        NSUInteger readCapacity = sizeof(bytes);
        if (parsedHeader) {
            NSUInteger remaining = requiredLength - currentLength;
            if (readCapacity > remaining) readCapacity = remaining;
        } else {
            NSUInteger maximumBuffered = IWHTTPMaximumHeaderBytes + IWHTTPMaximumBodyBytes;
            if (currentLength >= maximumBuffered) {
                IWHTTPSetTransportError(error, IWHTTPTransportErrorHeaderTooLarge, @"HTTP request exceeds transport bounds");
                return nil;
            }
            if (readCapacity > maximumBuffered - currentLength) readCapacity = maximumBuffered - currentLength;
        }

        if (!IWHTTPWaitForSocket(socketFD, NO, deadline, error)) return nil;
        ssize_t received = recv(socketFD, bytes, readCapacity, 0);
        if (received == 0) {
            IWHTTPSetTransportError(error, IWHTTPTransportErrorTruncatedRequest, @"Peer closed before the HTTP request was complete");
            return nil;
        }
        if (received < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            IWHTTPSetTransportError(error, IWHTTPTransportErrorSocket,
                                    [NSString stringWithFormat:@"recv failed: %d", errno]);
            return nil;
        }
        [request appendBytes:bytes length:(NSUInteger)received];

        if (!parsedHeader) {
            NSUInteger terminator = IWHTTPHeaderTerminatorOffset([request bytes], [request length]);
            if (terminator != NSNotFound) {
                NSUInteger headerLength = terminator + 4u;
                if (headerLength > IWHTTPMaximumHeaderBytes) {
                    IWHTTPSetTransportError(error, IWHTTPTransportErrorHeaderTooLarge, @"HTTP header exceeds 32 KiB");
                    return nil;
                }
                NSData *headerData = [request subdataWithRange:NSMakeRange(0, headerLength)];
                NSUInteger contentLength = 0;
                if (!IWHTTPParseHeader(headerData, &contentLength, error)) return nil;
                requiredLength = headerLength + contentLength;
                parsedHeader = YES;
            }
        }
    }
}

/* Sends all bytes with partial-write handling and one monotonic deadline. */
static inline BOOL IWHTTPSendData(int socketFD, NSData *data, NSTimeInterval timeoutSeconds, NSError **error) {
    if (socketFD < 0 || !data || !isfinite(timeoutSeconds) || timeoutSeconds <= 0.0) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorInvalidArgument, @"A valid socket, data, and positive timeout are required");
        return NO;
    }
    if (!IWHTTPPrepareAcceptedSocket(socketFD, error)) return NO;

    int oldFlags = fcntl(socketFD, F_GETFL, 0);
    if (oldFlags < 0 || fcntl(socketFD, F_SETFL, oldFlags | O_NONBLOCK) < 0) {
        IWHTTPSetTransportError(error, IWHTTPTransportErrorSocket,
                                [NSString stringWithFormat:@"Could not enable nonblocking send: %d", errno]);
        return NO;
    }

    NSTimeInterval deadline = IWHTTPMonotonicNow() + timeoutSeconds;
    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger length = [data length];
    NSUInteger sentTotal = 0;
    BOOL success = YES;
    NSError *sendError = nil;

    while (sentTotal < length) {
        if (!IWHTTPWaitForSocket(socketFD, YES, deadline, &sendError)) {
            success = NO;
            break;
        }
        NSUInteger amount = length - sentTotal;
        if (amount > 65536u) amount = 65536u;
        int flags = 0;
#if defined(MSG_NOSIGNAL)
        flags |= MSG_NOSIGNAL;
#endif
        ssize_t sent = send(socketFD, bytes + sentTotal, amount, flags);
        if (sent > 0) {
            sentTotal += (NSUInteger)sent;
            continue;
        }
        if (sent < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        IWHTTPSetTransportError(&sendError, IWHTTPTransportErrorSocket,
                                [NSString stringWithFormat:@"send failed: %d", errno]);
        success = NO;
        break;
    }

    if (fcntl(socketFD, F_SETFL, oldFlags) < 0 && success) {
        IWHTTPSetTransportError(&sendError, IWHTTPTransportErrorSocket,
                                [NSString stringWithFormat:@"Could not restore socket flags: %d", errno]);
        success = NO;
    }
    if (!success && error) *error = sendError;
    return success;
}
