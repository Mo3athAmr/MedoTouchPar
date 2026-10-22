#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// System-modal Touch Bar (the same private AppKit/DFRFoundation entry points
// BetterTouchTool's BTTTouchBarCenter calls). Every function is a no-op when
// the selector or symbol is missing, so the app degrades instead of crashing.

/// Shows `touchBar` above every app. hideControlStrip=YES uses the full width.
void TBPresentSystemModal(NSTouchBar *touchBar, BOOL hideControlStrip, NSTouchBarItemIdentifier trayIdentifier);
void TBMinimizeSystemModal(NSTouchBar *touchBar);
void TBDismissSystemModal(NSTouchBar *touchBar);

/// Puts an item in the Control Strip (the right-hand system area).
void TBAddSystemTrayItem(NSTouchBarItem *item);
void TBRemoveSystemTrayItem(NSTouchBarItem *item);
void TBSetControlStripPresence(NSTouchBarItemIdentifier identifier, BOOL present);

/// Controls the "X" close box AppKit draws on the left of system-modal bars.
void TBSetShowsCloseBox(BOOL shows);

/// YES when the private presentation API exists on this macOS build.
BOOL TBSystemModalAvailable(void);

/// Dock badge text of a running app ("3", "•", …) from LaunchServices'
/// StatusLabel (what `lsappinfo info -only StatusLabel` prints); nil when none.
NSString *_Nullable TBBadgeLabelForPID(pid_t pid);

/// Built-in display brightness 0...1 via DisplayServices; -1 when unavailable.
float TBGetBrightness(void);
void TBSetBrightness(float value);

NS_ASSUME_NONNULL_END
