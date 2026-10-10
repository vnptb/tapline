#include "system.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>
#include <stdbool.h>

int mb_toggle_caps_lock(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!svc) return -1;
    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), kIOHIDParamConnectType, &conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) return -1;
    bool state = false;
    int result = -1;
    if (IOHIDGetModifierLockState(conn, kIOHIDCapsLockState, &state) == KERN_SUCCESS &&
        IOHIDSetModifierLockState(conn, kIOHIDCapsLockState, !state) == KERN_SUCCESS)
        result = state ? 0 : 1;
    IOServiceClose(conn);
    return result;
}
