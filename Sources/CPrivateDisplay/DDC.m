// DDC/CI over IOAVService on Apple Silicon.
// The service lookup and packet layout follow m1ddc (github.com/waydabber/m1ddc),
// Copyright (c) 2021 waydabber, MIT License.

#import "CPrivateDisplay.h"

typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef _Nullable IOAVServiceCreateWithService(CFAllocatorRef _Nullable allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

static const uint32_t kChipAddressDefault = 0x37;
// Some Macs route their built-in HDMI port through an MCDP29xx DP-to-HDMI converter, which answers on 0xB7.
static const uint32_t kChipAddressMCDP29XX = 0xB7;
static const uint8_t kHostAddress = 0x51;
static const useconds_t kWriteWait = 10000;
static const useconds_t kReplyWait = 40000;
static const useconds_t kReplyWaitMCDP29XX = 50000;
static const int kWriteRepeats = 2;  // Many monitors miss the first write.
static const int kReadAttempts = 4;

static BOOL stringPropertyEquals(io_registry_entry_t entry, CFStringRef key, CFStringRef expected, IOOptionBits options) {
    CFTypeRef value = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key, kCFAllocatorDefault, options);
    BOOL equal = value != NULL && CFGetTypeID(value) == CFStringGetTypeID() &&
                 CFStringCompare((CFStringRef)value, expected, 0) == kCFCompareEqualTo;
    if (value != NULL) CFRelease(value);
    return equal;
}

static BOOL isMCDP29XX(io_service_t proxy) {
    io_registry_entry_t parent;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) return NO;
    BOOL result = stringPropertyEquals(parent, CFSTR("EPICProviderClass"), CFSTR("AppleDCPMCDP29XX"), 0);
    IOObjectRelease(parent);
    return result;
}

static BOOL framebufferEntryID(CGDirectDisplayID display, uint64_t *entryID) {
    CFDictionaryRef info = CoreDisplay_DisplayCreateInfoDictionary(display);
    if (info == NULL) return NO;
    CFTypeRef location = CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
    io_registry_entry_t framebuffer = MACH_PORT_NULL;
    if (location != NULL && CFGetTypeID(location) == CFStringGetTypeID()) {
        framebuffer = IORegistryEntryCopyFromPath(kIOMainPortDefault, (CFStringRef)location);
    }
    CFRelease(info);
    if (framebuffer == MACH_PORT_NULL) return NO;
    BOOL found = IORegistryEntryGetRegistryEntryID(framebuffer, entryID) == KERN_SUCCESS;
    IOObjectRelease(framebuffer);
    return found;
}

/// Finds the external DCPAVServiceProxy that drives `display`. The caller releases the result.
static IOAVServiceRef _Nullable copyAVService(CGDirectDisplayID display, uint32_t *chipAddress) {
    uint64_t targetID;
    if (!framebufferEntryID(display, &targetID)) return NULL;

    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    io_iterator_t iter;
    kern_return_t kr = IORegistryEntryCreateIterator(root, kIOServicePlane, kIORegistryIterateRecursively, &iter);
    IOObjectRelease(root);
    if (kr != KERN_SUCCESS) return NULL;

    // The registry walk visits each IOMobileFramebuffer before the AV service proxy that belongs to it.
    BOOL inTargetFramebuffer = NO;
    IOAVServiceRef result = NULL;
    io_service_t service;
    while (result == NULL && (service = IOIteratorNext(iter)) != MACH_PORT_NULL) {
        if (IOObjectConformsTo(service, "IOMobileFramebuffer")) {
            uint64_t entryID;
            inTargetFramebuffer = IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS && entryID == targetID;
        } else if (inTargetFramebuffer) {
            io_name_t name;
            if (IORegistryEntryGetName(service, name) == KERN_SUCCESS && strcmp(name, "DCPAVServiceProxy") == 0 &&
                stringPropertyEquals(service, CFSTR("Location"), CFSTR("External"), kIORegistryIterateRecursively)) {
                result = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
                if (result != NULL) *chipAddress = isMCDP29XX(service) ? kChipAddressMCDP29XX : kChipAddressDefault;
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return result;
}

BOOL SKDDCIsAvailable(CGDirectDisplayID display) {
    uint32_t chipAddress;
    IOAVServiceRef service = copyAVService(display, &chipAddress);
    if (service == NULL) return NO;
    CFRelease(service);
    return YES;
}

IOReturn SKDDCWrite(CGDirectDisplayID display, uint8_t vcp, uint16_t value) {
    uint32_t chipAddress;
    IOAVServiceRef service = copyAVService(display, &chipAddress);
    if (service == NULL) return kIOReturnNotFound;

    // Set VCP Feature: length, opcode, VCP code, value (big-endian), checksum.
    uint8_t packet[6] = {0x84, 0x03, vcp, value >> 8, value & 0xFF, 0};
    packet[5] = 0x6E ^ kHostAddress ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];

    IOReturn result = kIOReturnSuccess;
    for (int i = 0; i < kWriteRepeats && result == kIOReturnSuccess; i++) {
        usleep(kWriteWait);
        result = IOAVServiceWriteI2C(service, chipAddress, kHostAddress, packet, sizeof packet);
    }
    CFRelease(service);
    return result;
}

IOReturn SKDDCRead(CGDirectDisplayID display, uint8_t vcp, uint16_t *current, uint16_t *maximum, uint8_t *rawReply) {
    uint32_t chipAddress;
    IOAVServiceRef service = copyAVService(display, &chipAddress);
    if (service == NULL) return kIOReturnNotFound;

    // Get VCP Feature request. Like m1ddc and MonitorControl, the checksum leaves out the host address.
    uint8_t request[4] = {0x82, 0x01, vcp, 0};
    request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2];

    IOReturn result = kIOReturnError;
    for (int attempt = 0; attempt < kReadAttempts; attempt++) {
        usleep(kWriteWait);
        result = IOAVServiceWriteI2C(service, chipAddress, kHostAddress, request, sizeof request);
        if (result != kIOReturnSuccess) continue;

        usleep(chipAddress == kChipAddressMCDP29XX ? kReplyWaitMCDP29XX : kReplyWait);
        uint8_t reply[12] = {0};
        result = IOAVServiceReadI2C(service, chipAddress, kHostAddress, reply, sizeof reply);
        if (rawReply != NULL) memcpy(rawReply, reply, sizeof reply);
        if (result != kIOReturnSuccess) continue;

        // Reply: source, length, opcode 0x02, result code, VCP code, type, max (2 bytes), current (2 bytes), checksum.
        uint8_t checksum = 0x50;
        for (int i = 0; i < 10; i++) checksum ^= reply[i];
        if (reply[2] != 0x02 || reply[3] != 0x00 || reply[4] != vcp || reply[10] != checksum) {
            result = kIOReturnIOError;  // Got bytes, but not a valid reply.
            continue;
        }
        *maximum = (uint16_t)(reply[6] << 8 | reply[7]);
        *current = (uint16_t)(reply[8] << 8 | reply[9]);
        break;
    }
    CFRelease(service);
    return result;
}
