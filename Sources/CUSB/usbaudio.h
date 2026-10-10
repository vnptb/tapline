#ifndef MB_USBAUDIO_H
#define MB_USBAUDIO_H

#include <stdint.h>

// Access to the controls of USB Audio Class (UAC1/UAC2) devices through control requests on
// endpoint 0. Works next to macOS's own audio driver: no interface is claimed or opened.

typedef struct {
    uint64_t registryID;      // this connection of the device; changes on every re-enumeration
    uint32_t locationID;      // the USB port
    uint16_t vendorID;
    uint16_t productID;
    char name[128];
    char serial[64];
} mb_device_info;

typedef struct {
    uint8_t interfaceNumber;  // AudioControl interface
    uint8_t unitID;           // Feature Unit
    uint8_t channel;          // 0 = master
    uint8_t uacVersion;       // 1 or 2
} mb_mute_control;

// Lists connected USB devices that have an AudioControl interface.
// Writes at most `max` entries and returns the total number found.
int mb_list_audio_devices(mb_device_info *out, int max);

// Opens a device by its registry entry ID (from mb_list_audio_devices). NULL if it is gone.
void *mb_open(uint64_t registryID);
void mb_close(void *handle);

// Lists every Feature Unit channel that has a Mute control. Returns the count written.
int mb_list_mute_controls(void *handle, mb_mute_control *out, int max);

int mb_get_mute(void *handle, mb_mute_control control);           // 1 muted, 0 not muted, -1 error
int mb_set_mute(void *handle, mb_mute_control control, int mute); // 0 ok, -1 error

#endif
