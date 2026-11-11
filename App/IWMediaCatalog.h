#import <Foundation/Foundation.h>

// Catalogs and user media are optional. Reject malformed entries without
// changing the positional indexes used by selection, favorites and deletion.
static NSString *IWCatalogString(id value, NSString *fallback) {
    return [value isKindOfClass:[NSString class]] ? value : fallback;
}

static NSString *IWCatalogMediaPath(id value, NSString *root) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    NSString *relative = [[value componentsSeparatedByString:@"?"] firstObject];
    if ([relative isAbsolutePath] || [relative rangeOfString:@":"].location != NSNotFound) return nil;
    NSString *base = [root stringByStandardizingPath];
    NSString *path = [[base stringByAppendingPathComponent:relative] stringByStandardizingPath];
    return [path hasPrefix:[base stringByAppendingString:@"/"]] ? path : nil;
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
