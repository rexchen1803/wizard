#!/usr/bin/env python3
"""Run extracted production gallery deletion and wallpaper-load guards on macOS."""
from pathlib import Path
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "App/main.m"
text = SOURCE.read_text()
if text.count("IWNextWallpaperLoadGeneration(&_wallpaperLoadGeneration)") != 2:
    raise RuntimeError("Expected production image-selection and apply paths to advance the load generation.")
if text.count("IWApplyWallpaperLoadIfCurrent(loadGeneration, _wallpaperLoadGeneration, _wallpapers, _wallpaperIndex, expectedKey, path,") != 4:
    raise RuntimeError("Expected production image and transition callbacks to use the guarded update helper.")


def method(selector_pattern: str) -> str:
    start = re.search(r"^- \([^\n)]+\)" + selector_pattern + r" \{", text, re.M)
    if not start:
        raise RuntimeError("Production method missing: " + selector_pattern)
    end = re.search(r"^[-+] \(", text[start.end():], re.M)
    return text[start.start():start.end() + end.start() if end else len(text)]


def c_function(name: str, return_type: str) -> str:
    start = re.search(r"^static " + re.escape(return_type) + r"\s*" + re.escape(name) + r"\([^\n]+\) \{", text, re.M)
    if not start:
        raise RuntimeError("Production function missing: " + name)
    opening = text.find("{", start.start())
    depth = 0
    for pos in range(opening, len(text)):
        if text[pos] == "{":
            depth += 1
        elif text[pos] == "}":
            depth -= 1
            if depth == 0:
                return text[start.start():pos + 1]
    raise RuntimeError("Unclosed production function: " + name)


HARNESS = r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSInteger checks = 0;
static NSInteger failures = 0;
static id gFileManager;
static NSString *IWGalleryCategoryForItem(NSDictionary *item);
static NSArray *IWGalleryCategoryDefinitions(void);
static NSArray *gOpenedGalleryItems;
static NSInteger gOpenedGallerySelection;

static void check(BOOL condition, NSString *message) {
    checks += 1;
    if (!condition) {
        failures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

@interface TestFileManager : NSObject
@property(nonatomic, strong) NSMutableSet *files;
@property(nonatomic, copy) NSString *failurePath;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
@end
@implementation TestFileManager
- (instancetype)init {
    self = [super init];
    if (self) _files = [NSMutableSet set];
    return self;
}
- (BOOL)fileExistsAtPath:(NSString *)path { return [_files containsObject:path]; }
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    if ([path isEqualToString:_failurePath]) {
        if (error) *error = [NSError errorWithDomain:@"GalleryTest" code:1 userInfo:nil];
        return NO;
    }
    if (![_files containsObject:path]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
        return NO;
    }
    [_files removeObject:path];
    return YES;
}
@end

static id galleryTestDefaultManager(id self, SEL selector) { return gFileManager; }

@interface GalleryViewStub : NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL selected;
@property(nonatomic, strong) id image;
- (void)setNeedsDisplay;
@end
@implementation GalleryViewStub
- (void)setNeedsDisplay {}
@end

@interface IWGalleryController : NSObject
@property(nonatomic, strong) id backdropImage;
- (instancetype)initWithOwner:(id)owner items:(NSArray *)items selected:(NSInteger)selected favorites:(id)favorites cache:(id)cache;
@end
@implementation IWGalleryController
- (instancetype)initWithOwner:(id)owner items:(NSArray *)items selected:(NSInteger)selected favorites:(id)favorites cache:(id)cache {
    self = [super init];
    if (self) { gOpenedGalleryItems = [items copy]; gOpenedGallerySelection = selected; }
    return self;
}
@end

@interface GalleryFilterOwner : NSObject
@property(nonatomic, copy) NSArray *galleryItems;
@property(nonatomic, copy) NSSet *favoriteIndexes;
- (NSArray *)allGalleryItems;
- (NSArray *)displayItems;
- (BOOL)isFavorite:(NSInteger)index;
@end
@implementation GalleryFilterOwner
- (NSArray *)allGalleryItems { return _galleryItems; }
- (NSArray *)displayItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in _galleryItems) if ([self isFavorite:[[item objectForKey:@"index"] integerValue]]) [items addObject:item];
    return items;
}
- (BOOL)isFavorite:(NSInteger)index { return [_favoriteIndexes containsObject:@(index)]; }
@end

@interface GalleryHarness : NSObject {
@public
    NSArray *_wallpapers;
    NSArray *_fixtureItems;
    GalleryFilterOwner *_owner;
    NSString *_categoryFilter;
    BOOL _favoriteFilterOnly;
    BOOL _editMode;
    BOOL _menuOpen;
    BOOL _controlsHidden;
    GalleryViewStub *_menu;
    GalleryViewStub *_menuButton;
    GalleryViewStub *_background;
    id _presentedViewController;
    NSInteger _wallpaperIndex;
    NSUInteger _wallpaperLoadGeneration;
    NSString *_userDir;
    NSString *_savedWallpaperKey;
    NSMutableDictionary *_favorites;
    NSMutableDictionary *_backgroundAdjustments;
    NSCache *_thumbCache;
    NSInteger _applyCount;
    NSInteger _saveCount;
}
- (NSString *)userWallpaperDirectory;
- (BOOL)canDeleteWallpaperAtIndex:(NSInteger)index;
- (NSInteger)deleteWallpapersAtIndexes:(NSArray *)indexes;
- (NSString *)wallpaperKey;
- (void)loadWallpapers;
- (void)applyWallpaper;
- (void)saveState;
- (NSArray *)itemsForFilter;
- (NSArray *)allGalleryItems;
- (NSArray *)displayItems;
- (void)openGallery;
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(id)completion;
@property(nonatomic, strong) id presentedViewController;
@end

@implementation GalleryHarness
- (NSString *)userWallpaperDirectory { return _userDir; }
- (void)loadWallpapers {
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *item in _fixtureItems) {
        BOOL userFile = [[item objectForKey:@"fileName"] hasPrefix:@"user-"];
        if (userFile && ![(id)gFileManager fileExistsAtPath:[item objectForKey:@"imagePath"]]) continue;
        NSMutableDictionary *indexed = [item mutableCopy];
        [indexed setObject:@([visible count]) forKey:@"index"];
        [visible addObject:indexed];
    }
    _wallpapers = [visible copy];
}
- (void)applyWallpaper { _applyCount += 1; }
- (void)saveState { _saveCount += 1; _savedWallpaperKey = [[self wallpaperKey] copy]; }
- (NSArray *)allGalleryItems { return [_owner allGalleryItems]; }
- (NSArray *)displayItems { return [_owner displayItems]; }
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(id)completion { _presentedViewController = controller; }
__PRODUCTION_METHODS__
@end

__PRODUCTION_FUNCTION__

static NSDictionary *wallpaper(NSString *key, NSString *fileName, NSString *path) {
    return @{@"key": key, @"fileName": fileName, @"imagePath": path, @"index": @0};
}

static NSDictionary *categorizedItem(NSInteger index, NSString *key, id category, NSString *type) {
    NSMutableDictionary *item = [@{@"index": @(index), @"key": key} mutableCopy];
    if (category) item[@"category"] = category;
    if (type) item[@"type"] = type;
    return [item copy];
}

static NSArray *indexes(NSArray *items) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *item in items) {
        id index = item[@"index"];
        if (index) [result addObject:index];
    }
    return result;
}

static NSArray *categoryFixtures(void) {
    return @[
        categorizedItem(0, @"art", @"artwork", nil),
        categorizedItem(1, @"person", @"people", nil),
        categorizedItem(2, @"place", @"places", nil),
        categorizedItem(3, @"ultimate", @"ultimate", nil),
        categorizedItem(4, @"vintage", @"vintage", nil),
        categorizedItem(5, @"video-category", @"video", nil),
        categorizedItem(6, @"legacy-missing", nil, nil),
        categorizedItem(7, @"user-photo.jpg", @"artwork", nil),
        categorizedItem(8, @"explicit-user", @"user", nil),
        categorizedItem(9, @"explicit-other", @"other", nil),
        categorizedItem(10, @"legacy-unknown", @"unrecognized", nil),
        categorizedItem(11, @"legacy-malformed", @42, nil),
        categorizedItem(12, @"video-priority", @"people", @"video"),
        categorizedItem(13, @"user-unknown.jpg", @"unrecognized", nil),
        categorizedItem(14, @"legacy-empty", @"", nil),
    ];
}

static void testGalleryCategoryClassification(void) {
    NSArray *fixtures = categoryFixtures();
    NSArray *expected = @[@"artwork", @"people", @"places", @"ultimate", @"vintage", @"video",
                         @"other", @"user", @"user", @"other", @"other", @"other", @"video", @"user", @"other"];
    for (NSUInteger i = 0; i < fixtures.count; i += 1) {
        NSString *actual = IWGalleryCategoryForItem(fixtures[i]);
        check([actual isEqualToString:expected[i]], [NSString stringWithFormat:@"category classification for fixture %lu", (unsigned long)i]);
    }
}

static void testGalleryCategoryAndFavoriteFiltering(void) {
    NSArray *all = categoryFixtures();
    NSMutableArray *snapshots = [NSMutableArray arrayWithCapacity:all.count];
    for (NSDictionary *item in all) [snapshots addObject:[item copy]];
    GalleryFilterOwner *owner = [GalleryFilterOwner new];
    owner.galleryItems = all;
    owner.favoriteIndexes = [NSSet setWithArray:@[@1, @3, @7]];
    GalleryHarness *h = [GalleryHarness new];
    h->_owner = owner;

    NSArray *visible = [h itemsForFilter];
    check(visible.count == all.count, @"nil category and disabled favorites return the full gallery");
    check([indexes(visible) isEqualToArray:@[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12, @13, @14]], @"unfiltered gallery retains source order and original indexes");
    BOOL sameObjects = visible.count == all.count;
    for (NSUInteger i = 0; sameObjects && i < all.count; i += 1) sameObjects = visible[i] == all[i];
    check(sameObjects, @"filter returns original item dictionaries without mutation or copies");
    h->_categoryFilter = @"";
    check([h itemsForFilter].count == all.count, @"empty category selection behaves like all categories");

    h->_categoryFilter = @"other";
    visible = [h itemsForFilter];
    check([indexes(visible) isEqualToArray:@[@6, @9, @10, @11, @14]], @"other filter includes explicit other and missing, empty, unknown, and malformed legacy categories");
    h->_categoryFilter = @"user";
    visible = [h itemsForFilter];
    check([indexes(visible) isEqualToArray:@[@7, @8, @13]], @"user filter includes key-derived and explicit user categories in source order");
    h->_categoryFilter = @"video";
    visible = [h itemsForFilter];
    check([indexes(visible) isEqualToArray:@[@5, @12]], @"video filter includes explicit and type-derived videos");

    h->_categoryFilter = nil;
    h->_favoriteFilterOnly = YES;
    visible = [h itemsForFilter];
    check([indexes(visible) isEqualToArray:@[@1, @3, @7]], @"favorites-only filtering retains source order and original indexes");
    h->_categoryFilter = @"user";
    visible = [h itemsForFilter];
    check([indexes(visible) isEqualToArray:@[@7]], @"category and favorites filters intersect on original item indexes");
    h->_categoryFilter = @"vintage";
    visible = [h itemsForFilter];
    check(visible.count == 0, @"category and favorites filters can produce an empty intersection");
    BOOL unchanged = snapshots.count == all.count;
    for (NSUInteger i = 0; unchanged && i < all.count; i += 1) unchanged = [all[i] isEqual:snapshots[i]];
    check(unchanged, @"filtering leaves source item dictionaries unchanged");
}

static void testOpenGalleryUsesFullCatalogAndOriginalSelection(void) {
    GalleryFilterOwner *owner = [GalleryFilterOwner new];
    owner.galleryItems = @[
        categorizedItem(0, @"first", @"artwork", nil),
        categorizedItem(1, @"favorite", @"people", nil),
        categorizedItem(2, @"selected", @"places", nil)
    ];
    owner.favoriteIndexes = [NSSet setWithArray:@[@1]];
    GalleryHarness *h = [GalleryHarness new];
    h->_owner = owner;
    h->_wallpaperIndex = 2;
    h->_favorites = [@{@"favorite": @YES} mutableCopy];
    h->_thumbCache = [NSCache new];
    h->_menu = [GalleryViewStub new];
    h->_menuButton = [GalleryViewStub new];
    h->_background = [GalleryViewStub new];

    check([h displayItems].count == 1, @"fixture displayItems is a one-favorite subset");
    gOpenedGalleryItems = nil;
    gOpenedGallerySelection = -1;
    [h openGallery];
    check(gOpenedGalleryItems.count == 3, @"openGallery initializes with every catalog item");
    BOOL selectedItemIsOriginal = gOpenedGalleryItems.count > 2 && gOpenedGalleryItems[2] == owner.galleryItems[2];
    check(gOpenedGallerySelection == 2 && selectedItemIsOriginal, @"openGallery preserves the original selected index and its item");
}

static void testDeleteFailureKeepsCurrentStableKey(TestFileManager *fm, NSString *base) {
    GalleryHarness *h = [GalleryHarness new];
    h->_userDir = [base stringByAppendingPathComponent:@"assets/user"];
    NSString *a = [h->_userDir stringByAppendingPathComponent:@"user-a.jpg"];
    NSString *b = [h->_userDir stringByAppendingPathComponent:@"user-b.jpg"];
    NSString *c = [h->_userDir stringByAppendingPathComponent:@"user-c.jpg"];
    h->_fixtureItems = @[
        wallpaper(@"catalog", @"bundled.jpg", @"/app/assets/bundled.jpg"),
        wallpaper(@"user-a", @"user-a.jpg", a),
        wallpaper(@"user-b", @"user-b.jpg", b),
        wallpaper(@"user-c", @"user-c.jpg", c)
    ];
    h->_wallpapers = h->_fixtureItems;
    h->_wallpaperIndex = 2;
    h->_favorites = [@{@"user-a": @YES, @"user-b": @YES} mutableCopy];
    h->_backgroundAdjustments = [@{@"user-a": @{}, @"user-b": @{}} mutableCopy];
    h->_thumbCache = [NSCache new];
    [fm.files addObjectsFromArray:@[a, b, c]];
    fm.failurePath = b;

    NSInteger selected = [h deleteWallpapersAtIndexes:@[@1, @2]];
    check([fm fileExistsAtPath:b], @"failed current-photo removal leaves the source photo present");
    check(![fm fileExistsAtPath:a], @"the other selected imported photo is deleted");
    check(selected == 1 && [h->_wallpapers[selected][@"key"] isEqual:@"user-b"], @"current stable key is restored after an earlier index shifts");
    check([h->_favorites objectForKey:@"user-b"] != nil && [h->_favorites objectForKey:@"user-a"] == nil, @"favorite state is removed only for a successfully deleted photo");
    check([h->_backgroundAdjustments objectForKey:@"user-b"] != nil && [h->_backgroundAdjustments objectForKey:@"user-a"] == nil, @"background adjustment follows successful deletion only");
    check(h->_savedWallpaperKey != nil && [h->_savedWallpaperKey isEqual:@"user-b"], @"stable current key is persisted after failed deletion");
    check(h->_applyCount == 1 && h->_saveCount == 1, @"delete flow reapplies and saves exactly once");
}

static void testWallpaperLoadGenerationRejectsStaleCallbacks(void) {
    NSArray *items = @[wallpaper(@"photo-a", @"user-a.jpg", @"/user/a.jpg")];
    NSUInteger activeGeneration = 1;
    NSInteger currentIndex = 0;
    __block NSInteger updates = 0;
    BOOL current = IWApplyWallpaperLoadIfCurrent(1, activeGeneration, items, currentIndex, @"photo-a", @"/user/a.jpg", ^{ updates += 1; });
    check(current && updates == 1, @"current async image callback is accepted");

    NSArray *reloadedSameIndex = @[wallpaper(@"photo-b", @"user-b.jpg", @"/user/b.jpg")];
    NSUInteger replacementGeneration = IWNextWallpaperLoadGeneration(&activeGeneration);
    current = IWApplyWallpaperLoadIfCurrent(1, activeGeneration, reloadedSameIndex, currentIndex, @"photo-a", @"/user/a.jpg", ^{ updates += 1; });
    check(!current && updates == 1, @"same-index replacement rejects old image callback without mutating the view");

    current = IWApplyWallpaperLoadIfCurrent(replacementGeneration, activeGeneration, reloadedSameIndex, currentIndex, @"photo-b", @"/user/b.jpg", ^{ updates += 1; });
    check(current && updates == 2, @"replacement image callback is accepted");

    // A new selection of the same item still invalidates the old transition completion.
    NSUInteger repeatedSelectionGeneration = IWNextWallpaperLoadGeneration(&activeGeneration);
    check(repeatedSelectionGeneration == replacementGeneration + 1, @"each same-item selection receives a fresh generation");
    current = IWApplyWallpaperLoadIfCurrent(replacementGeneration, activeGeneration, reloadedSameIndex, currentIndex, @"photo-b", @"/user/b.jpg", ^{ updates += 1; });
    check(!current && updates == 2, @"stale transition completion for same key and path cannot reset newer animation state");
}

int main(void) {
    @autoreleasepool {
        TestFileManager *fm = [TestFileManager new];
        gFileManager = fm;
        Method method = class_getClassMethod([NSFileManager class], @selector(defaultManager));
        IMP original = method_setImplementation(method, (IMP)galleryTestDefaultManager);
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        testDeleteFailureKeepsCurrentStableKey(fm, base);
        [fm.files removeAllObjects]; fm.failurePath = nil;
        testGalleryCategoryClassification();
        testGalleryCategoryAndFavoriteFiltering();
        testOpenGalleryUsesFullCatalogAndOriginalSelection();
        testWallpaperLoadGenerationRejectsStaleCallbacks();
        method_setImplementation(method, original);
        printf("{\"checks\":%ld,\"failures\":%ld}\n", (long)checks, (long)failures);
    }
    return failures ? 1 : 0;
}
'''

IMPORT_HARNESS = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

static NSInteger checks = 0, failures = 0;
static void check(BOOL condition, NSString *message) {
    checks += 1;
    if (!condition) { failures += 1; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}

// Only image encoding is a test double. Production import/enumeration methods
// write to and reload a real, isolated temporary filesystem directory.
@interface UIImage : NSObject
@property(nonatomic, copy) NSString *marker;
@property(nonatomic, assign) CGSize size;
+ (instancetype)imageWithContentsOfFile:(NSString *)path;
@end
@implementation UIImage
+ (instancetype)imageWithContentsOfFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    UIImage *image = [UIImage new];
    image.marker = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    image.size = CGSizeMake(16, 16);
    return image;
}
@end
static NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat quality) {
    return [image.marker dataUsingEncoding:NSUTF8StringEncoding];
}
static NSDate *fixedImportDate(id self, SEL selector) {
    return [NSDate dateWithTimeIntervalSince1970:1000];
}

@interface ImportHarness : NSObject {
@public
    NSArray *_wallpapers;
    NSInteger _wallpaperIndex;
    BOOL _promoOnly, _favoriteOnly;
    NSString *_userDir, *_savedWallpaperKey;
    NSInteger _saveCount;
}
- (NSString *)userWallpaperDirectory;
- (UIImage *)imageConstrainedToMaxLongEdge:(UIImage *)image maxLongEdge:(CGFloat)edge;
- (UIImage *)thumbnailForImage:(UIImage *)image size:(CGSize)size;
- (void)appendUserWallpapersToItems:(NSMutableArray *)items;
- (NSInteger)importSystemImage:(UIImage *)image;
- (NSString *)wallpaperKey;
- (void)loadWallpapers;
- (void)saveState;
@end
@implementation ImportHarness
- (NSString *)userWallpaperDirectory { return _userDir; }
- (UIImage *)imageConstrainedToMaxLongEdge:(UIImage *)image maxLongEdge:(CGFloat)edge { return image; }
- (UIImage *)thumbnailForImage:(UIImage *)image size:(CGSize)size { return image; }
- (void)loadWallpapers {
    NSMutableArray *items = [NSMutableArray array];
    [self appendUserWallpapersToItems:items];
    _wallpapers = [items copy];
}
- (void)saveState { _saveCount += 1; _savedWallpaperKey = [[self wallpaperKey] copy]; }
__IMPORT_METHODS__
@end

static NSString *selectedPath(ImportHarness *h, NSInteger index) {
    return index >= 0 && index < (NSInteger)h->_wallpapers.count ? h->_wallpapers[index][@"imagePath"] : nil;
}
static NSData *bytes(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *base = [NSString stringWithUTF8String:argv[1]];
        ImportHarness *h = [ImportHarness new]; h->_userDir = [base stringByAppendingPathComponent:@"imports"];
        [[NSFileManager defaultManager] createDirectoryAtPath:h->_userDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *old = [h->_userDir stringByAppendingPathComponent:@"user-1000000.jpg"];
        NSString *oldThumb = [h->_userDir stringByAppendingPathComponent:@"user-1000000-thumb.jpg"];
        NSString *future = [h->_userDir stringByAppendingPathComponent:@"user-9999999999999.jpg"];
        [bytes(@"ORIGINAL_PHOTO") writeToFile:old atomically:YES];
        [bytes(@"ORIGINAL_THUMB") writeToFile:oldThumb atomically:YES];
        [bytes(@"FUTURE_NAMED_PHOTO") writeToFile:future atomically:YES];
        [h loadWallpapers];
        Method dateMethod = class_getClassMethod([NSDate class], @selector(date));
        IMP originalDate = method_setImplementation(dateMethod, (IMP)fixedImportDate);
        UIImage *first = [UIImage new]; first.marker = @"NEW_PHOTO_A"; first.size = CGSizeMake(16, 16);
        NSInteger a = [h importSystemImage:first]; NSString *aPath = [selectedPath(h, a) copy];
        check(a >= 0 && [[NSData dataWithContentsOfFile:aPath] isEqual:bytes(@"NEW_PHOTO_A")], @"new import is selected even when an older filename sorts later");
        check([[NSData dataWithContentsOfFile:old] isEqual:bytes(@"ORIGINAL_PHOTO")], @"import cannot overwrite a pre-existing same-millisecond source");
        check([[NSData dataWithContentsOfFile:oldThumb] isEqual:bytes(@"ORIGINAL_THUMB")], @"import cannot overwrite a pre-existing same-millisecond thumbnail");
        check(h->_wallpapers.count == 3, @"first import adds one distinct source");
        check(a >= 0 && a < (NSInteger)h->_wallpapers.count && [h->_savedWallpaperKey isEqual:h->_wallpapers[a][@"key"]], @"new import stable key is saved");
        UIImage *second = [UIImage new]; second.marker = @"NEW_PHOTO_B"; second.size = CGSizeMake(16, 16);
        NSInteger b = [h importSystemImage:second]; NSString *bPath = selectedPath(h, b);
        check(b >= 0 && [[NSData dataWithContentsOfFile:bPath] isEqual:bytes(@"NEW_PHOTO_B")], @"second frozen-time import selects its own image");
        check(aPath && bPath && ![aPath isEqual:bPath], @"two imports at the same clock instant use distinct paths");
        check([[NSData dataWithContentsOfFile:aPath] isEqual:bytes(@"NEW_PHOTO_A")], @"second frozen-time import preserves the first imported image");
        check(h->_wallpapers.count == 4, @"two imports add two sources without replacing existing photos");
        NSInteger saved = h->_saveCount;
        check([h importSystemImage:nil] == -1 && h->_saveCount == saved, @"nil image does not save or import");
        ImportHarness *blocked = [ImportHarness new]; blocked->_userDir = [base stringByAppendingPathComponent:@"blocked"];
        [bytes(@"NOT_A_DIRECTORY") writeToFile:blocked->_userDir atomically:YES];
        check([blocked importSystemImage:first] == -1 && blocked->_saveCount == 0, @"failed primary write does not persist a selected photo");
        check([[NSData dataWithContentsOfFile:future] isEqual:bytes(@"FUTURE_NAMED_PHOTO")], @"future-named existing photo remains untouched");
        method_setImplementation(dateMethod, originalDate);
        printf("{\"checks\":%ld,\"failures\":%ld}\n", (long)checks, (long)failures);
    }
    return failures ? 1 : 0;
}
'''

methods = [
    method(r"canDeleteWallpaperAtIndex:\(NSInteger\)index"),
    method(r"deleteWallpapersAtIndexes:\(NSArray \*\)indexes"),
    method("wallpaperKey"),
    method("itemsForFilter"),
    method("openGallery"),
]

# UIKit presentation is replaced with small host doubles. The production
# confirmation method is executed verbatim; filesystem deletion is covered above.
CONFIRM_HARNESS = r'''
#import <Foundation/Foundation.h>
// UIKit appearance is checked in native captures; this harness tests deletion semantics.
static void IWStyleNativeAlert(id alert) { (void)alert; }
static NSInteger checks, failures;
static void check(BOOL value, NSString *message) {
    checks++;
    if (!value) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
enum { UIAlertControllerStyleAlert, UIAlertActionStyleCancel, UIAlertActionStyleDestructive };
@interface UIAlertAction : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic) NSInteger style;
@property(nonatomic, copy) void (^handler)(UIAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *))handler;
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *))handler {
    UIAlertAction *action = [self new]; action.title = title; action.style = style; action.handler = handler; return action;
}
@end
@interface UIAlertController : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) NSMutableArray *actions;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style;
- (void)addAction:(UIAlertAction *)action;
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style {
    UIAlertController *alert = [self new]; alert.title = title; alert.actions = [NSMutableArray array]; return alert;
}
- (void)addAction:(UIAlertAction *)action { [_actions addObject:action]; }
@end
@interface ConfirmOwner : NSObject
@property(nonatomic) NSInteger deletes;
@property(nonatomic, copy) NSArray *lastIndexes;
- (NSInteger)deleteWallpapersAtIndexes:(NSArray *)indexes;
@end
@implementation ConfirmOwner
- (NSInteger)deleteWallpapersAtIndexes:(NSArray *)indexes { _deletes++; _lastIndexes = indexes; return 0; }
@end
@interface CollectionStub : NSObject
@property(nonatomic, readonly) CollectionStub *collectionViewLayout;
- (void)invalidateLayout;
- (void)reloadData;
- (void)layoutIfNeeded;
@end
@implementation CollectionStub
- (CollectionStub *)collectionViewLayout { return self; }
- (void)invalidateLayout {}
- (void)reloadData {}
- (void)layoutIfNeeded {}
@end
@interface GalleryConfirmHarness : NSObject {
@public
    NSMutableSet *_deleteSelection;
    NSArray *_items;
    ConfirmOwner *_owner;
    CollectionStub *_collection;
    BOOL _deleteMode;
    NSInteger _selected, _pendingLocateIndex, _presentations;
}
@property(nonatomic, strong) UIAlertController *presentedViewController;
- (NSInteger)selectedDeletableCount;
- (void)confirmDeleteTapped;
- (void)deleteConfirmedWallpapersAtIndexes:(NSArray *)indexes;
- (NSArray *)itemsForFilter;
- (void)updateFavoriteFilterUI;
- (void)updateDeleteModeUI;
- (void)updateEmptyState;
- (void)preloadReset:(BOOL)reset;
- (void)presentViewController:(UIAlertController *)controller animated:(BOOL)animated completion:(id)completion;
@end
#define IWGalleryController GalleryConfirmHarness
@implementation GalleryConfirmHarness
- (NSInteger)selectedDeletableCount { return [_deleteSelection containsObject:@1] ? 1 : 0; }
- (void)deleteConfirmedWallpapersAtIndexes:(NSArray *)indexes { [_owner deleteWallpapersAtIndexes:indexes]; }
- (NSArray *)itemsForFilter { return _items; }
- (void)updateFavoriteFilterUI {}
- (void)updateDeleteModeUI {}
- (void)updateEmptyState {}
- (void)preloadReset:(BOOL)reset {}
- (void)presentViewController:(UIAlertController *)controller animated:(BOOL)animated completion:(id)completion {
    _presentations++; self.presentedViewController = controller;
}
__CONFIRM_METHOD__
@end
static GalleryConfirmHarness *fixture(void) {
    GalleryConfirmHarness *h = [GalleryConfirmHarness new];
    h->_owner = [ConfirmOwner new]; h->_deleteMode = YES;
    h->_deleteSelection = [NSMutableSet setWithArray:@[@0, @1]];
    h->_items = @[@{@"index": @0}, @{@"index": @1}]; return h;
}
static UIAlertAction *destructive(GalleryConfirmHarness *h) {
    for (UIAlertAction *action in h.presentedViewController.actions)
        if (action.style == UIAlertActionStyleDestructive) return action;
    return nil;
}
int main(void) { @autoreleasepool {
    GalleryConfirmHarness *h = fixture(); [h->_deleteSelection removeAllObjects]; [h confirmDeleteTapped];
    check(!h.presentedViewController && !h->_owner.deletes, @"empty selection cannot delete");
    h = fixture(); [h->_deleteSelection removeObject:@1]; [h confirmDeleteTapped];
    check(!h.presentedViewController && !h->_owner.deletes, @"built-in-only selection cannot delete");
    h = fixture(); [h confirmDeleteTapped];
    check(h->_owner.deletes == 0, @"trash tap defers every deletion until confirmation");
    check(h.presentedViewController.actions.count == 2, @"confirmation has cancel and destructive actions");
    check(h.presentedViewController && [h.presentedViewController.title rangeOfString:@"1"].location != NSNotFound,
          @"mixed selection confirms only the deletable photo count");
    UIAlertAction *action = destructive(h);
    check(action.handler != nil, @"destructive action owns the deferred operation");
    if (action.handler) {
        for (UIAlertAction *cancel in h.presentedViewController.actions) if (cancel.style == UIAlertActionStyleCancel) {
            if (cancel.handler) cancel.handler(cancel);
            check(h->_owner.deletes == 0 && h->_deleteMode && h->_deleteSelection.count == 2,
                  @"cancel retains photos and mixed favorite selection");
        }
        [h confirmDeleteTapped]; check(h->_presentations == 1, @"repeated trash taps cannot stack confirmations");
        action.handler(action); check(h->_owner.deletes == 1, @"explicit destructive confirmation deletes once");
        h = fixture(); [h confirmDeleteTapped]; action = destructive(h); [h->_deleteSelection removeObject:@1];
        action.handler(action); check(!h->_owner.deletes, @"changed selection invalidates a stale confirmation");
        h = fixture(); [h confirmDeleteTapped]; action = destructive(h); h->_items = @[];
        action.handler(action); check(!h->_owner.deletes, @"reloaded gallery invalidates a stale confirmation");
        h = fixture(); [h confirmDeleteTapped]; action = destructive(h); h->_deleteMode = NO;
        action.handler(action); check(!h->_owner.deletes, @"leaving selection mode invalidates a stale confirmation");
    }
    printf("{\"checks\":%ld,\"failures\":%ld}\n", (long)checks, (long)failures);
    return failures ? 1 : 0;
} }
'''

with tempfile.TemporaryDirectory(prefix="wizard-gallery-media-regressions-") as directory:
    output = Path(directory)
    harness = output / "gallery-regressions.m"
    production_functions = "\n".join([
        c_function("IWApplyWallpaperLoadIfCurrent", "BOOL"),
        c_function("IWNextWallpaperLoadGeneration", "NSUInteger"),
        c_function("IWGalleryCategoryDefinitions", "NSArray *"),
        c_function("IWGalleryCategoryForItem", "NSString *"),
    ])
    harness.write_text(HARNESS.replace("__PRODUCTION_METHODS__", "\n".join(methods)).replace("__PRODUCTION_FUNCTION__", production_functions))
    binary = output / "gallery-regressions"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Werror", "-framework", "Foundation", str(harness), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    gallery_summary = json.loads(result.stdout)
    print(result.stderr, end="")
    import_harness = output / "import-regressions.m"
    import_methods = [method("appendUserWallpapersToItems:\\(NSMutableArray \\*\\)items"),
                      method("importSystemImage:\\(UIImage \\*\\)image"), method("wallpaperKey")]
    import_harness.write_text(IMPORT_HARNESS.replace("__IMPORT_METHODS__", "\n".join(import_methods)))
    import_binary = output / "import-regressions"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Werror", "-Wno-unused-parameter", "-framework", "Foundation", "-framework", "CoreGraphics", str(import_harness), "-o", str(import_binary)], check=True)
    imported = subprocess.run([str(import_binary), str(output)], capture_output=True, text=True)
    import_summary = json.loads(imported.stdout)
    print(imported.stderr, end="")
    confirm_harness = output / "confirmation-regressions.m"
    confirm_harness.write_text(CONFIRM_HARNESS.replace("__CONFIRM_METHOD__", method("confirmDeleteTapped")))
    confirm_binary = output / "confirmation-regressions"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Werror", "-framework", "Foundation",
                    str(confirm_harness), "-o", str(confirm_binary)], check=True)
    confirmed = subprocess.run([str(confirm_binary)], capture_output=True, text=True)
    confirm_summary = json.loads(confirmed.stdout)
    print(confirmed.stderr, end="")
    print(json.dumps({"checks": gallery_summary["checks"] + import_summary["checks"] + confirm_summary["checks"],
                      "failures": gallery_summary["failures"] + import_summary["failures"] + confirm_summary["failures"]}))
    raise SystemExit(result.returncode or imported.returncode or confirmed.returncode)
