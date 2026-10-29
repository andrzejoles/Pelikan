// Przebieg zrzutów w tle (D113, D196) — tylko kompilacja Debug i tylko z PELIKAN_UI_SCRIPT: okna aplikacji są
// niewidoczne od pierwszej klatki (przezroczystość 0, bez cienia, animacji i obsługi myszy), a aplikacja nigdy się nie
// aktywuje. Zrzuty robi sama aplikacja, rysując widoki okien do PNG (UIScriptSnapshots.swift), więc na monitorach
// właściciela nic się nie pojawia i nic nie zabiera fokusu (D30). PELIKAN_UI_SCRIPT_VISIBLE=1 — okna widoczne jak dawniej
// (zrzuty `screencapture`, scripts/screenshots.sh --screen).
//
// Haki w Objective-C, bo inicjalizator NSWindow (rodzina init: zużywa self i zwraca obiekt zachowany) da się bezpiecznie
// podmienić tylko z jawnym objc_method_family; z inicjalizatora i z każdej drogi wystawienia okna na ekran.
#if DEBUG
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void PKConceal(NSWindow *window) {
    window.alphaValue = 0;  // podmieniony setter i tak ustawia 0
    window.ignoresMouseEvents = YES;
    window.hasShadow = NO;
    window.animationBehavior = NSWindowAnimationBehaviorNone;
}

static void PKSwap(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, replacement);
    if (m1 == NULL || m2 == NULL) return;
    if (class_addMethod(cls, original, method_getImplementation(m2), method_getTypeEncoding(m2))) {
        class_replaceMethod(cls, replacement, method_getImplementation(m1), method_getTypeEncoding(m1));
    } else {
        method_exchangeImplementations(m1, m2);
    }
}

@interface NSWindow (PelikanUIScript)
- (instancetype)pk_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                                 defer:(BOOL)flag __attribute__((objc_method_family(init)));
- (instancetype)pk_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                                 defer:(BOOL)flag screen:(NSScreen *)screen __attribute__((objc_method_family(init)));
@end

@implementation NSWindow (PelikanUIScript)
- (instancetype)pk_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                                 defer:(BOOL)flag {
    self = [self pk_initWithContentRect:rect styleMask:style backing:backing defer:flag];
    if (self) PKConceal(self);
    return self;
}

- (instancetype)pk_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                                 defer:(BOOL)flag screen:(NSScreen *)screen {
    self = [self pk_initWithContentRect:rect styleMask:style backing:backing defer:flag screen:screen];
    if (self) PKConceal(self);
    return self;
}

- (void)pk_orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other {
    if (place != NSWindowOut) PKConceal(self);
    [self pk_orderWindow:place relativeTo:other];
}

- (void)pk_orderFront:(id)sender {
    PKConceal(self);
    [self pk_orderFront:sender];
}

- (void)pk_makeKeyAndOrderFront:(id)sender {
    PKConceal(self);
    [self pk_makeKeyAndOrderFront:sender];
}

- (void)pk_orderFrontRegardless {
    PKConceal(self);
    [self pk_orderFrontRegardless];
}

- (void)pk_setIsVisible:(BOOL)visible {
    if (visible) PKConceal(self);
    [self pk_setIsVisible:visible];
}

- (void)pk_setAlphaValue:(CGFloat)value {
    (void)value;
    [self pk_setAlphaValue:0];
}

- (void)pk_setIgnoresMouseEvents:(BOOL)value {
    (void)value;
    [self pk_setIgnoresMouseEvents:YES];
}

- (void)pk_addChildWindow:(NSWindow *)child ordered:(NSWindowOrderingMode)place {
    PKConceal(child);
    [self pk_addChildWindow:child ordered:place];
}

- (void)pk_beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler {
    PKConceal(sheet);
    [self pk_beginSheet:sheet completionHandler:handler];
}

- (void)pk_beginCriticalSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler {
    PKConceal(sheet);
    [self pk_beginCriticalSheet:sheet completionHandler:handler];
}
@end

@interface NSApplication (PelikanUIScript)
@end

@implementation NSApplication (PelikanUIScript)
// Aktywacja zabrałaby fokus oknu, w którym pracuje właściciel — w trybie skryptu nigdy.
- (void)pk_activateIgnoringOtherApps:(BOOL)flag {
    (void)flag;
}

- (void)pk_activate {
}

- (NSInteger)pk_requestUserAttention:(NSRequestUserAttentionType)type {
    (void)type;
    return 0;
}
@end

@interface PKUIScriptWindows : NSObject
@end

@implementation PKUIScriptWindows
+ (void)load {
    if (getenv("PELIKAN_UI_SCRIPT") == NULL || getenv("PELIKAN_UI_SCRIPT_VISIBLE") != NULL) return;
    Class w = [NSWindow class];
    PKSwap(w, @selector(initWithContentRect:styleMask:backing:defer:), @selector(pk_initWithContentRect:styleMask:backing:defer:));
    PKSwap(w, @selector(initWithContentRect:styleMask:backing:defer:screen:),
           @selector(pk_initWithContentRect:styleMask:backing:defer:screen:));
    PKSwap(w, @selector(orderWindow:relativeTo:), @selector(pk_orderWindow:relativeTo:));
    PKSwap(w, @selector(orderFront:), @selector(pk_orderFront:));
    PKSwap(w, @selector(makeKeyAndOrderFront:), @selector(pk_makeKeyAndOrderFront:));
    PKSwap(w, @selector(orderFrontRegardless), @selector(pk_orderFrontRegardless));
    PKSwap(w, @selector(setIsVisible:), @selector(pk_setIsVisible:));
    PKSwap(w, @selector(setAlphaValue:), @selector(pk_setAlphaValue:));
    PKSwap(w, @selector(setIgnoresMouseEvents:), @selector(pk_setIgnoresMouseEvents:));
    PKSwap(w, @selector(addChildWindow:ordered:), @selector(pk_addChildWindow:ordered:));
    PKSwap(w, @selector(beginSheet:completionHandler:), @selector(pk_beginSheet:completionHandler:));
    PKSwap(w, @selector(beginCriticalSheet:completionHandler:), @selector(pk_beginCriticalSheet:completionHandler:));
    Class a = [NSApplication class];
    PKSwap(a, @selector(activateIgnoringOtherApps:), @selector(pk_activateIgnoringOtherApps:));
    PKSwap(a, NSSelectorFromString(@"activate"), @selector(pk_activate));
    PKSwap(a, @selector(requestUserAttention:), @selector(pk_requestUserAttention:));
}
@end
#endif
