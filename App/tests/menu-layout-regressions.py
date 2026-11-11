#!/usr/bin/env python3
"""Execute production menu geometry and surface guards with host UIKit doubles.

This checks layout and control membership, not native rendering or physical input.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT / 'App/main.m')
source = parser.parse_args().source.read_text()


def method(name):
    start = re.search(r'^- \([^\n)]+\)' + re.escape(name) + r' \{', source, re.M)
    if not start:
        raise RuntimeError('Missing production method: ' + name)
    end = re.search(r'^[-+] \(', source[start.end():], re.M)
    return source[start.start():start.end() + end.start()]


menu = method('buildMenu')
menu_loop = menu[menu.index('    CGFloat leftX'):menu.index('    _settingsMenu =')]
enum = re.search(r'typedef NS_ENUM\(NSInteger, IWButtonKind\) \{.*?\};', source, re.S).group()
constants = '\n'.join(re.findall(r'^static NSInteger const (?:IWPowerConnectTag|IWPowerDisconnectTag|IWWallpaperTransitionTag|IWGTA6CountdownTag)[^\n]+', source, re.M))
controls = '\n'.join(re.findall(r'^static CGFloat (?:IWControlSize|IWControlRightMargin)\(void\) \{[^\n]+', source, re.M))
layout = '\n'.join(line for line in source.splitlines() if any(line.strip().startswith(s) for s in (
    'CGFloat menuRightColumnX =', '_menu.frame =', 'CGFloat secondaryMenuHeight =', '_settingsMenu.frame =')))
program = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
__ENUM__
__CONSTANTS__
__CONTROLS__
static NSInteger checks, failures;
static void check(BOOL value, NSString *message) { checks++; if (!value) { failures++; fprintf(stderr,"FAIL: %s\n",message.UTF8String); } }
enum { UIControlEventTouchUpInside = 1 };
static id IWGTATextFont(CGFloat size) { return nil; }
@interface UIView : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic, readonly) CGRect bounds;
@property(nonatomic) BOOL hidden;
@property(nonatomic, strong) NSMutableArray *subviews;
- (void)addSubview:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) _subviews=[NSMutableArray array]; return self; }
- (CGRect)bounds { return (CGRect){CGPointZero,self.frame.size}; }
- (void)addSubview:(UIView *)view { [_subviews addObject:view]; }
@end
@interface UILabel : NSObject
@property(nonatomic,strong) id font;
@end
@implementation UILabel @end
@interface UIButton : UIView
@property(nonatomic) NSInteger tag, actions;
@property(nonatomic,strong) UILabel *titleLabel;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSInteger)events;
@end
@implementation UIButton
- (instancetype)init { if ((self=[super init])) _titleLabel=[UILabel new]; return self; }
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSInteger)events { _actions++; }
@end
@interface IWIconButton : UIButton @end
@implementation IWIconButton @end
@interface IWGalleryController : NSObject @end
@implementation IWGalleryController @end
@interface MenuHarness : NSObject {
@public
    UIView *_menu, *_settingsMenu, *_videoOverlay, *_calendarPanel, *_weatherPanel;
    UIButton *_musicButton, *_settingsButton, *_wallpaperTransitionButton, *_secondsButton, *_hourButton, *_languageButton;
    IWIconButton *_castButton;
    UIButton *_powerConnectButton, *_powerDisconnectButton;
    NSInteger _secondaryMenuMode;
    BOOL _editMode;
}
@property(nonatomic,strong) UIView *view;
@property(nonatomic,strong) id presentedViewController;
- (void)buildMenu;
- (void)buildLabSecondaryMenu;
- (void)buildThemeSecondaryMenu;
- (BOOL)canHandleApplicationSurfaceTouchAtPoint:(CGPoint)point;
@end
@implementation MenuHarness
- (NSString *)wallpaperTransitionLabel { return @"Slide"; }
- (NSString *)dateLanguageLabel { return @"繁體"; }
- (IWIconButton *)actionButton:(NSInteger)kind { IWIconButton *b=[IWIconButton new];b.tag=kind;return b; }
- (UIButton *)textButton:(NSString *)title tag:(NSInteger)tag { UIButton *b=[UIButton new];b.tag=tag;b.actions=1;return b; }
- (void)addBetaWarningBadgeToButton:(UIButton *)button {}
- (void)clearSecondaryMenu { [_settingsMenu.subviews removeAllObjects]; }
- (void)menuAction:(UIButton *)button {}
- (void)themeCycleTapped:(UIButton *)button {}
- (BOOL)isSystemGestureEdgePoint:(CGPoint)point { return NO; }
- (BOOL)pointHitsView:(UIView *)view rootPoint:(CGPoint)point { return NO; }
- (BOOL)isControlPoint:(CGPoint)point { return NO; }
- (void)layoutMenus { __LAYOUT__ }
- (void)buildMenu { __MENU_LOOP__ }
__LAB__
__THEME__
__SURFACE__
@end
static void checkMenu(UIView *menu, NSInteger expected, NSString *name) {
    check(menu.subviews.count==expected,[name stringByAppendingString:@" retains every expected action"]);
    for (NSUInteger i=0;i<menu.subviews.count;i++) {
        UIButton *b=menu.subviews[i];
        check(CGRectContainsRect(menu.bounds,b.frame),[name stringByAppendingString:@" keeps controls inside panel"]);
        check(b.frame.size.width>=44 && b.frame.size.height>=44,[name stringByAppendingString:@" keeps touch targets usable"]);
        check(b.actions==1,[name stringByAppendingString:@" connects each control once"]);
        for (NSUInteger j=0;j<i;j++) check(!CGRectIntersectsRect(b.frame,((UIButton *)menu.subviews[j]).frame),[name stringByAppendingString:@" has no overlapping controls"]);
    }
}
int main(void) { @autoreleasepool {
    MenuHarness *h=[MenuHarness new];h.view=[UIView new];h.view.frame=CGRectMake(0,0,1024,768);
    h->_menu=[UIView new];h->_settingsMenu=[UIView new];[h buildMenu];[h layoutMenus];
    checkMenu(h->_menu,13,@"Main menu");
    NSArray *expected=@[@(IWButtonKindThemeMenu),@(IWWallpaperTransitionTag),@(IWButtonKindClock),@2001,@2002,@2003,@(IWButtonKindCalendar),@(IWButtonKindWeather),@(IWButtonKindHeart),@(IWButtonKindVideo),@(IWButtonKindMusic),@(IWButtonKindLock),@(IWButtonKindLab)];
    NSMutableArray *actual=[NSMutableArray array];for (UIButton *b in h->_menu.subviews) [actual addObject:@(b.tag)];
    check([actual isEqual:expected],@"All retained actions preserve their original order, including favorites");
    check(CGRectEqualToRect(h->_settingsButton.frame,CGRectMake(10,334,104,46)),@"Settings fills the final row without an orphan slot");
    h->_secondaryMenuMode=1;[h buildLabSecondaryMenu];[h layoutMenus];checkMenu(h->_settingsMenu,4,@"Settings submenu");
    h->_secondaryMenuMode=2;[h buildThemeSecondaryMenu];[h layoutMenus];checkMenu(h->_settingsMenu,2,@"Theme submenu");
    for (NSInteger width=1024;width<=1366;width+=342) {
        h.view.frame=CGRectMake(0,0,width,768);
        for (NSInteger mode=1;mode<=2;mode++) { h->_secondaryMenuMode=mode;[h layoutMenus];
            check(CGRectContainsRect(h.view.bounds,h->_menu.frame),@"Main panel fits the landscape canvas");
            check(CGRectContainsRect(h.view.bounds,h->_settingsMenu.frame),@"Submenu fits the landscape canvas");
            check(!CGRectIntersectsRect(h->_menu.frame,h->_settingsMenu.frame),@"Panels do not overlap");
        }
    }
    check([h canHandleApplicationSurfaceTouchAtPoint:CGPointZero],@"Idle background accepts surface navigation");
    h->_editMode=YES;check(![h canHandleApplicationSurfaceTouchAtPoint:CGPointZero],@"Editing suppresses application surface navigation");h->_editMode=NO;
    h->_videoOverlay=[UIView new];check(![h canHandleApplicationSurfaceTouchAtPoint:CGPointZero],@"Visible video suppresses application surface navigation");
    h->_videoOverlay.hidden=YES;check([h canHandleApplicationSurfaceTouchAtPoint:CGPointZero],@"Closed video restores surface navigation");
    h.presentedViewController=[IWGalleryController new];check(![h canHandleApplicationSurfaceTouchAtPoint:CGPointZero],@"Gallery owns its surface input");
    printf("{\"checks\":%ld,\"failures\":%ld}\n",(long)checks,(long)failures);return failures?1:0;
} }
'''
for key,value in {'ENUM':enum,'CONSTANTS':constants,'CONTROLS':controls,'LAYOUT':layout,'MENU_LOOP':menu_loop,
                  'LAB':method('buildLabSecondaryMenu'),'THEME':method('buildThemeSecondaryMenu'),
                  'SURFACE':method('canHandleApplicationSurfaceTouchAtPoint:(CGPoint)point')}.items():
    program=program.replace('__'+key+'__',value)
with tempfile.TemporaryDirectory(prefix='wizard-menu-layout-') as directory:
    directory=Path(directory);test=directory/'menus.m';binary=directory/'menus';test.write_text(program)
    subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-Werror','-framework','Foundation','-framework','CoreGraphics',str(test),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
