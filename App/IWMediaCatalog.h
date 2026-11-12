#import <Foundation/Foundation.h>

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// Catalogs and user media are optional. Reject malformed entries without
// changing the positional indexes used by selection, favorites and deletion.
static NSString *IWCatalogString(id value, NSString *fallback) {
    return [value isKindOfClass:[NSString class]] ? value : fallback;
}

static BOOL IWCatalogPathIsWithinRoot(NSString *path, NSString *root) {
    if ([path isEqualToString:root]) return YES;
    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    return [path hasPrefix:prefix];
}

/*
 * The returned catalog path remains lexical for existing index and identity
 * behavior. Canonical checks accept aliases in the supplied root itself (for
 * example /var -> /private/var), while rejecting symlink components below it.
 * This is a load-time check, not a race-proof guarantee against privileged
 * concurrent replacement between validation and the caller opening the file.
 */
static BOOL IWCatalogMediaPathIsSafe(NSString *path, NSString *base) {
    const char *baseName = [base fileSystemRepresentation];
    if (!baseName) return NO;

    char canonicalRoot[PATH_MAX];
    if (!realpath(baseName, canonicalRoot)) return NO;
    struct stat rootInfo;
    if (stat(canonicalRoot, &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode)) return NO;
    NSString *canonicalRootPath = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:canonicalRoot length:strlen(canonicalRoot)];
    if (![canonicalRootPath length]) return NO;

    NSUInteger relativeStart = [base hasSuffix:@"/"] ? [base length] : [base length] + 1;
    if ([path length] <= relativeStart) return NO;
    NSString *relativePath = [path substringFromIndex:relativeStart];
    NSArray *components = [relativePath pathComponents];
    NSString *cursor = base;
    for (NSUInteger index = 0; index < [components count]; index += 1) {
        NSString *component = [components objectAtIndex:index];
        if (![component length] || [component isEqualToString:@"/"] || [component isEqualToString:@"."]) continue;
        cursor = [cursor stringByAppendingPathComponent:component];
        const char *cursorName = [cursor fileSystemRepresentation];
        if (!cursorName) return NO;

        struct stat itemInfo;
        if (lstat(cursorName, &itemInfo) != 0) {
            // A missing optional catalog asset is still a valid catalog path.
            // Its existing ancestors have already been checked above.
            return errno == ENOENT;
        }
        if (S_ISLNK(itemInfo.st_mode)) return NO;
        BOOL isLastComponent = index + 1 == [components count];
        if ((!isLastComponent && !S_ISDIR(itemInfo.st_mode)) ||
            (isLastComponent && !S_ISREG(itemInfo.st_mode))) return NO;

        char canonicalItem[PATH_MAX];
        if (!realpath(cursorName, canonicalItem)) return NO;
        NSString *canonicalItemPath = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:canonicalItem length:strlen(canonicalItem)];
        if (![canonicalItemPath length] || !IWCatalogPathIsWithinRoot(canonicalItemPath, canonicalRootPath)) return NO;
    }
    return YES;
}

static NSString *IWCatalogMediaPath(id value, NSString *root) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    NSString *relative = [[value componentsSeparatedByString:@"?"] firstObject];
    if ([relative isAbsolutePath] || [relative rangeOfString:@":"].location != NSNotFound) return nil;
    NSString *base = [root stringByStandardizingPath];
    NSString *path = [[base stringByAppendingPathComponent:relative] stringByStandardizingPath];
    return IWCatalogPathIsWithinRoot(path, base) && [path length] > [base length] &&
           IWCatalogMediaPathIsSafe(path, base) ? path : nil;
}

static NSArray *IWMediaCatalogItems(NSString *text, NSString *root, NSInteger *sourceCount) {
    if (sourceCount) *sourceCount = 0;
    if (![text isKindOfClass:[NSString class]]) return @[];
    NSRange start = [text rangeOfString:@"["];
    NSRange end = [text rangeOfString:@"]" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) return @[];
    NSString *json = [text substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
    id raw = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    if (sourceCount) *sourceCount = [raw count];
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *keys = [NSMutableSet set];
    NSInteger sourceIndex = 0;
    for (id entry in raw) {
        NSInteger original = sourceIndex++;
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *w = entry;
        NSString *image = IWCatalogMediaPath([w objectForKey:@"src"], root);
        NSString *video = IWCatalogMediaPath([w objectForKey:@"video"], root);
        NSString *type = IWCatalogString([w objectForKey:@"type"], @"image");
        if (![type isEqualToString:@"image"] && ![type isEqualToString:@"video"]) continue;
        if (![image length] || ([type isEqualToString:@"video"] && ![video length])) continue;
        NSString *key = IWCatalogString([w objectForKey:@"key"], nil);
        if (![key length]) key = [NSString stringWithFormat:@"%ld", (long)original];
        if ([keys containsObject:key]) continue;
        [keys addObject:key];
        id width = [w objectForKey:@"width"];
        id height = [w objectForKey:@"height"];
        [items addObject:@{
            @"index": @([items count]), @"legacyIndex": @(original), @"type": type, @"key": key,
            @"fileName": IWCatalogString([w objectForKey:@"fileName"], @""),
            @"label": IWCatalogString([w objectForKey:@"label"], @""),
            @"category": IWCatalogString([w objectForKey:@"category"], @""),
            @"imagePath": image,
            @"thumbPath": IWCatalogMediaPath([w objectForKey:@"thumb"], root) ?: image,
            @"videoPath": video ?: @"",
            @"width": [width isKindOfClass:[NSNumber class]] ? width : @0,
            @"height": [height isKindOfClass:[NSNumber class]] ? height : @0,
            @"themeClass": IWCatalogString([w objectForKey:@"themeClass"], @"theme-sunset"),
            @"themeName": IWCatalogString([w objectForKey:@"themeName"], @"")
        }];
    }
    return items;
}
