#include "usbaudio.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <string.h>

typedef IOUSBDeviceInterface245 **Dev;

#define UAC_CS_INTERFACE 0x24
#define UAC_FEATURE_UNIT 0x06
#define UAC_MUTE_CONTROL 0x01
#define UAC1_GET_CUR 0x81
#define UAC1_SET_CUR 0x01
#define UAC2_CUR 0x01
#define UAC2_PROTOCOL 0x20

static Dev open_service(io_service_t svc) {
    IOCFPlugInInterface **plug = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                          &plug, &score) != KERN_SUCCESS || !plug)
        return NULL;
    Dev dev = NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID245), (LPVOID *)&dev);
    (*plug)->Release(plug);
    return dev;
}

static uint32_t number_property(io_service_t svc, CFStringRef key) {
    uint32_t value = 0;
    CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
    if (ref) {
        if (CFGetTypeID(ref) == CFNumberGetTypeID()) CFNumberGetValue(ref, kCFNumberSInt32Type, &value);
        CFRelease(ref);
    }
    return value;
}

static void string_property(io_service_t svc, CFStringRef key, char *out, size_t size) {
    out[0] = 0;
    CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
    if (ref) {
        if (CFGetTypeID(ref) == CFStringGetTypeID()) CFStringGetCString(ref, out, (CFIndex)size, kCFStringEncodingUTF8);
        CFRelease(ref);
    }
}

static IOUSBConfigurationDescriptorPtr active_config(Dev dev) {
    UInt8 value = 0, count = 0;
    if ((*dev)->GetConfiguration(dev, &value) != kIOReturnSuccess || value == 0) return NULL;
    if ((*dev)->GetNumberOfConfigurations(dev, &count) != kIOReturnSuccess) return NULL;
    for (UInt8 i = 0; i < count; i++) {
        IOUSBConfigurationDescriptorPtr cfg = NULL;
        if ((*dev)->GetConfigurationDescriptorPtr(dev, i, &cfg) == kIOReturnSuccess && cfg &&
            cfg->bConfigurationValue == value)
            return cfg;
    }
    return NULL;
}

// Calls `visit` for every descriptor in the active configuration.
// `iface` carries the class/subclass/protocol/number of the interface the descriptor belongs to.
typedef struct { int number, cls, sub, proto; } iface_ctx;
typedef void (*visit_fn)(const uint8_t *d, int len, const iface_ctx *iface, void *user);

static int walk_config(Dev dev, visit_fn visit, void *user) {
    IOUSBConfigurationDescriptorPtr cfg = active_config(dev);
    if (!cfg) return -1;
    const uint8_t *d = (const uint8_t *)cfg;
    int total = USBToHostWord(cfg->wTotalLength);
    iface_ctx iface = {-1, -1, -1, -1};
    for (int i = 0; i + 2 <= total;) {
        int len = d[i];
        if (len < 2 || i + len > total) break;
        if (d[i + 1] == kUSBInterfaceDesc && len >= 9) {
            iface.number = d[i + 2];
            iface.cls = d[i + 5];
            iface.sub = d[i + 6];
            iface.proto = d[i + 7];
        }
        visit(d + i, len, &iface, user);
        i += len;
    }
    return 0;
}

static void find_audio_control(const uint8_t *d, int len, const iface_ctx *iface, void *user) {
    (void)len;
    if (d[1] == kUSBInterfaceDesc && iface->cls == kUSBAudioInterfaceClass && iface->sub == kUSBAudioControlSubClass)
        *(int *)user = 1;
}

int mb_list_audio_devices(mb_device_info *out, int max) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) != KERN_SUCCESS)
        return 0;
    int total = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
        Dev dev = open_service(svc);
        if (dev) {
            int audio = 0;
            walk_config(dev, find_audio_control, &audio);
            if (audio && total < max) {
                mb_device_info *info = &out[total];
                memset(info, 0, sizeof *info);
                IORegistryEntryGetRegistryEntryID(svc, &info->registryID);
                info->locationID = number_property(svc, CFSTR("locationID"));
                info->vendorID = (uint16_t)number_property(svc, CFSTR("idVendor"));
                info->productID = (uint16_t)number_property(svc, CFSTR("idProduct"));
                io_name_t name;
                if (IORegistryEntryGetName(svc, name) == KERN_SUCCESS) strlcpy(info->name, name, sizeof info->name);
                string_property(svc, CFSTR("kUSBSerialNumberString"), info->serial, sizeof info->serial);
            }
            if (audio) total++;
            (*dev)->Release(dev);
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return total;
}

void *mb_open(uint64_t registryID) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID));
    if (!svc) return NULL;
    Dev dev = open_service(svc);
    IOObjectRelease(svc);
    return dev;
}

void mb_close(void *handle) {
    Dev dev = handle;
    if (dev) (*dev)->Release(dev);
}

typedef struct { mb_mute_control *out; int max, count; } collect_ctx;

static void add_control(collect_ctx *c, int iface, int unit, int channel, int version) {
    if (c->count >= c->max) return;
    c->out[c->count++] = (mb_mute_control){(uint8_t)iface, (uint8_t)unit, (uint8_t)channel, (uint8_t)version};
}

static void collect_mute(const uint8_t *d, int len, const iface_ctx *iface, void *user) {
    if (d[1] != UAC_CS_INTERFACE || len < 6 || d[2] != UAC_FEATURE_UNIT) return;
    if (iface->cls != kUSBAudioInterfaceClass || iface->sub != kUSBAudioControlSubClass) return;
    collect_ctx *c = user;
    int unit = d[3];
    if (iface->proto == UAC2_PROTOCOL) {
        // bmaControls: 4 bytes per channel, mute = bits D1..D0
        for (int ch = 0; 5 + ch * 4 + 4 <= len - 1; ch++)
            if (d[5 + ch * 4] & 0x03) add_control(c, iface->number, unit, ch, 2);
    } else if (iface->proto == 0 && len >= 7) {
        // bControlSize bytes per channel, mute = bit D0
        int size = d[5];
        if (size == 0) return;
        for (int ch = 0; 6 + ch * size + size <= len - 1; ch++)
            if (d[6 + ch * size] & 0x01) add_control(c, iface->number, unit, ch, 1);
    }
}

int mb_list_mute_controls(void *handle, mb_mute_control *out, int max) {
    collect_ctx c = {out, max, 0};
    if (!handle || walk_config(handle, collect_mute, &c) != 0) return 0;
    return c.count;
}

static int mute_request(Dev dev, mb_mute_control m, int set, uint8_t *value) {
    IOUSBDevRequestTO r = {
        .bmRequestType = set ? 0x21 : 0xA1,
        .bRequest = m.uacVersion == 2 ? UAC2_CUR : (set ? UAC1_SET_CUR : UAC1_GET_CUR),
        .wValue = (uint16_t)((UAC_MUTE_CONTROL << 8) | m.channel),
        .wIndex = (uint16_t)((m.unitID << 8) | m.interfaceNumber),
        .wLength = 1,
        .pData = value,
        .noDataTimeout = 100,
        .completionTimeout = 200,
    };
    if ((*dev)->DeviceRequestTO(dev, &r) != kIOReturnSuccess || r.wLenDone != 1) return -1;
    return 0;
}

int mb_get_mute(void *handle, mb_mute_control control) {
    uint8_t value = 0;
    if (!handle || mute_request(handle, control, 0, &value) != 0) return -1;
    return value ? 1 : 0;
}

int mb_set_mute(void *handle, mb_mute_control control, int mute) {
    uint8_t value = mute ? 1 : 0;
    if (!handle) return -1;
    return mute_request(handle, control, 1, &value);
}
