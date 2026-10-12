// Private macOS display APIs used by screenski.
//
// None of these are documented. The CGVirtualDisplay classes ship in CoreGraphics (DeskPad and
// BetterDisplay use the same API); CoreDisplay_DisplayCreateInfoDictionary ships in CoreDisplay.
// Signatures follow class dumps and open-source tools (DeskPad, m1ddc, MonitorControl).

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Virtual displays (CoreGraphics)

@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, copy, nullable) void (^terminationHandler)(id _Nullable, CGVirtualDisplay *_Nullable);
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

@interface CGVirtualDisplayMode : NSObject
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) CGFloat refreshRate;
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, strong) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property (nonatomic, readonly) CGDirectDisplayID displayID;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// MARK: - Display info (CoreDisplay)

/// Product name, IODisplayLocation, UUID, … for an online display. NULL for some virtual displays.
CFDictionaryRef _Nullable CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display) CF_RETURNS_RETAINED;

// MARK: - DDC/CI (implemented in DDC.m)

/// Whether `display` is an external display with an AV service we can send DDC commands through.
BOOL SKDDCIsAvailable(CGDirectDisplayID display);

/// Sets VCP feature `vcp` (0x10 = luminance) to `value`.
IOReturn SKDDCWrite(CGDirectDisplayID display, uint8_t vcp, uint16_t value);

/// Reads VCP feature `vcp`. `rawReply`, if given, receives the monitor's 12-byte reply for debugging.
IOReturn SKDDCRead(CGDirectDisplayID display, uint8_t vcp, uint16_t *current, uint16_t *maximum, uint8_t *_Nullable rawReply);

NS_ASSUME_NONNULL_END
