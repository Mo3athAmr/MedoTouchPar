#import "TBPrivate.h"
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

@interface NSTouchBar (TBPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalFunctionBar:(NSTouchBar *)touchBar;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)dismissSystemModalFunctionBar:(NSTouchBar *)touchBar;
@end

@interface NSTouchBarItem (TBPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

static void *TBOpen(const char *path) {
    return dlopen(path, RTLD_LAZY);
}

static void *TBDFRSymbol(const char *name) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = TBOpen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation");
    });
    return handle ? dlsym(handle, name) : NULL;
}

static void *TBDisplayServicesSymbol(const char *name) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = TBOpen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices");
    });
    return handle ? dlsym(handle, name) : NULL;
}

void TBPresentSystemModal(NSTouchBar *touchBar, BOOL hideControlStrip, NSTouchBarItemIdentifier trayIdentifier) {
    long long placement = hideControlStrip ? 1 : 0;
    if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:touchBar placement:placement systemTrayItemIdentifier:trayIdentifier];
    } else if ([NSTouchBar respondsToSelector:@selector(presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalFunctionBar:touchBar placement:placement systemTrayItemIdentifier:trayIdentifier];
    }
}

void TBMinimizeSystemModal(NSTouchBar *touchBar) {
    if ([NSTouchBar respondsToSelector:@selector(minimizeSystemModalTouchBar:)]) {
        [NSTouchBar minimizeSystemModalTouchBar:touchBar];
    } else if ([NSTouchBar respondsToSelector:@selector(minimizeSystemModalFunctionBar:)]) {
        [NSTouchBar minimizeSystemModalFunctionBar:touchBar];
    }
}

void TBDismissSystemModal(NSTouchBar *touchBar) {
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:touchBar];
    } else if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalFunctionBar:)]) {
        [NSTouchBar dismissSystemModalFunctionBar:touchBar];
    }
}

void TBAddSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]) {
        [NSTouchBarItem addSystemTrayItem:item];
    }
}

void TBRemoveSystemTrayItem(NSTouchBarItem *item) {
    if ([NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]) {
        [NSTouchBarItem removeSystemTrayItem:item];
    }
}

void TBSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present) {
    typedef void (*Fn)(NSString *, BOOL);
    Fn fn = (Fn)TBDFRSymbol("DFRElementSetControlStripPresenceForIdentifier");
    if (fn) fn(identifier, present);
}

void TBSetShowsCloseBox(BOOL shows) {
    typedef void (*Fn)(BOOL);
    Fn fn = (Fn)TBDFRSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (fn) fn(shows);
}

BOOL TBSystemModalAvailable(void) {
    return [NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]
        || [NSTouchBar respondsToSelector:@selector(presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:)];
}

NSString *TBBadgeLabelForPID(pid_t pid) {
    typedef CFTypeRef (*ASNFn)(CFAllocatorRef, pid_t);
    typedef CFTypeRef (*InfoFn)(int, CFTypeRef, CFStringRef);
    static ASNFn asnForPid;
    static InfoFn copyInfoItem;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        asnForPid = (ASNFn)dlsym(RTLD_DEFAULT, "_LSASNCreateWithPid");
        copyInfoItem = (InfoFn)dlsym(RTLD_DEFAULT, "_LSCopyApplicationInformationItem");
    });
    if (!asnForPid || !copyInfoItem) return nil;

    CFTypeRef asn = asnForPid(kCFAllocatorDefault, pid);
    if (!asn) return nil;
    const int kLSDefaultSessionID = -2;
    id value = CFBridgingRelease(copyInfoItem(kLSDefaultSessionID, asn, CFSTR("StatusLabel")));
    CFRelease(asn);

    if (![value isKindOfClass:[NSDictionary class]]) return nil;
    id label = ((NSDictionary *)value)[@"label"];
    if (![label isKindOfClass:[NSString class]] || [label length] == 0) return nil;
    return label;
}

static CGDirectDisplayID TBBuiltinDisplay(void) {
    CGDirectDisplayID displays[16];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(16, displays, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayIsBuiltin(displays[i])) return displays[i];
        }
    }
    return CGMainDisplayID();
}

float TBGetBrightness(void) {
    typedef int (*Fn)(CGDirectDisplayID, float *);
    Fn fn = (Fn)TBDisplayServicesSymbol("DisplayServicesGetBrightness");
    if (!fn) return -1;
    float value = -1;
    if (fn(TBBuiltinDisplay(), &value) != 0) return -1;
    return value;
}

void TBSetBrightness(float value) {
    typedef int (*Fn)(CGDirectDisplayID, float);
    Fn fn = (Fn)TBDisplayServicesSymbol("DisplayServicesSetBrightness");
    if (fn) fn(TBBuiltinDisplay(), fmaxf(0, fminf(1, value)));
}
