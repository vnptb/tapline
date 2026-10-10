# USB microphones with a mute or monitor button: what works with Tapline

Tapline turns the button on a USB microphone into a trigger on your Mac: dictation in Claude, a voice chat in ChatGPT, or any keyboard shortcut. This page lists popular microphones with a button, tap-to-mute sensor or push-in knob, and what we know about each one.

There's no list of supported models inside the app. Setup asks you to press the button three times and learns whatever signal changes, so the quickest way to check your mic is to try it. If it works, or doesn't, [open an issue](https://github.com/vnptb/tapline/issues/new) with the model name and we'll update this page.

## What the marks mean

- ✅ **Tested.** Someone ran Tapline with this mic and it works.
- 🟢 **Should work.** Public reports show that a press flips a USB Audio Class switch, the kind Tapline reads, or the mic is built the same way as one we tested. Tapline also tries to undo the press, so a mute button doesn't actually mute.
- 🟡 **Might work.** The mic has a button or a push-in knob, and nobody has tried it with Tapline yet. Try it: setup tells you within 20 seconds.
  "Mute stays" means the mic reports the press as a HID message after it has already muted itself. Tapline sees the press and runs your action, but has nothing to switch back, so the mic stays muted. That works for syncing mute with Zoom or Discord, not for dictation.
- ⛔ **Won't work.** There's no button, or the button talks only to the maker's own app.

Wireless clip-on receivers (DJI Mic, Hollyland Lark, RØDE Wireless GO) and USB headsets aren't covered yet.

### RØDE

| Microphone | Button | Tapline |
|---|---|---|
| **RØDE NT-USB Mini**<br><sub>NTUSB Mini · 19f7:0015</sub> | Press on the headphone knob (zero-latency monitoring) | ✅ Tested<br><sub>The press also keeps toggling monitoring: the mic doesn't let apps undo it.</sub> |
| **RØDE PodMic USB**<br><sub>19f7:004a</sub> | Press on the headphone knob (monitoring) | 🟢 Should work<br><sub>Same knob-press design as the NT-USB Mini.</sub> |
| **RØDE XCM-50** | Press on the headphone knob (monitoring) | 🟢 Should work<br><sub>Same knob-press design as the NT-USB Mini.</sub> |
| **RØDE XDM-100**<br><sub>19f7:0033</sub> | Press on the headphone knob (monitoring) | 🟢 Should work<br><sub>Same knob-press design as the NT-USB Mini.</sub> |
| **RØDE NT-USB+**<br><sub>NT-USB Plus</sub> | Two knobs, no button | ⛔ Won't work |
| **RØDE Wireless GO II / GO (Gen 3) / PRO / ME** | Mute on the transmitter or receiver | 🟡 Might work |
| **RØDE NT-USB** | Two knobs, no button | ⛔ Won't work |

### Shure

| Microphone | Button | Tapline |
|---|---|---|
| **Shure MV7+**<br><sub>MV7 Plus · 14ed:1019</sub> | Tap-to-mute touch panel | 🟢 Should work |
| **Shure MV6**<br><sub>14ed:1026</sub> | Tap-to-mute button | 🟢 Should work |
| **Shure MV7**<br><sub>MV7-K · 14ed:1012</sub> | Touch panel: mute, monitoring | 🟡 Might work<br><sub>Mute stays: the button still mutes the mic.</sub> |
| **Shure MV6 Gen 2** | Tap-to-mute button | 🟡 Might work |
| **Shure MV7i** | Touch-to-mute panel | 🟡 Might work |
| **Shure MV5 / MV5C** | Mute button | 🟡 Might work |
| **Shure MV51** | Touch panel with mute | 🟡 Might work |
| **Shure MVX2U** | No buttons | ⛔ Won't work |

### HyperX

| Microphone | Button | Tapline |
|---|---|---|
| **HyperX SoloCast**<br><sub>HMIS1X · 03f0:0592 · 0951:170f</sub> | Tap-to-mute sensor | 🟢 Should work |
| **HyperX QuadCast 2**<br><sub>QuadCast II · 03f0:07b4</sub> | Tap-to-mute sensor | 🟡 Might work<br><sub>Mute stays: the button still mutes the mic.</sub> |
| **HyperX QuadCast S**<br><sub>Quadcast-S · HMIQ1S · 0951:171f</sub> | Tap-to-mute sensor | 🟡 Might work<br><sub>Mute stays: the button still mutes the mic.</sub> |
| **HyperX QuadCast** | Tap-to-mute sensor | 🟡 Might work |
| **HyperX QuadCast 2 S** | Tap-to-mute sensor | 🟡 Might work |
| **HyperX SoloCast 2** | Tap-to-mute sensor | 🟡 Might work |
| **HyperX DuoCast** | Tap-to-mute sensor | 🟡 Might work |
| **HyperX FlipCast** | Tap-to-mute button | 🟡 Might work |

### Elgato

| Microphone | Button | Tapline |
|---|---|---|
| **Elgato Wave:3**<br><sub>Wave 3 · 0fd9:0070</sub> | Tap-to-mute on top | 🟢 Should work |
| **Elgato Wave:1**<br><sub>Wave 1</sub> | Press the dial to mute | 🟡 Might work |
| **Elgato Wave Neo** | Tap-to-mute | 🟡 Might work |
| **Elgato Wave XLR** | Tap-to-mute | 🟡 Might work |

### Logitech G / Blue

| Microphone | Button | Tapline |
|---|---|---|
| **Logitech G / Blue Yeti GX**<br><sub>Blue Yeti GX · 046d:0afc</sub> | Mute button | 🟡 Might work<br><sub>Mute stays: the button still mutes the mic.</sub> |
| **Logitech G / Blue Yeti**<br><sub>Blue Yeti</sub> | Mute button | 🟡 Might work |
| **Logitech G / Blue Yeti X**<br><sub>Blue Yeti X</sub> | Press the smart knob to mute | 🟡 Might work |
| **Logitech G / Blue Yeti Nano**<br><sub>Blue Yeti Nano</sub> | Press the headphone knob to mute | 🟡 Might work |
| **Logitech G / Blue Yeti Orb** | No buttons | ⛔ Won't work |
| **Logitech G / Blue Snowball / Snowball iCE** | No mute button | ⛔ Won't work |

### Razer

| Microphone | Button | Tapline |
|---|---|---|
| **Razer Seiren V3 Mini** | Tap-to-mute sensor | 🟡 Might work |
| **Razer Seiren V3 Chroma** | Tap-to-mute sensor | 🟡 Might work |
| **Razer Seiren V2 X** | Mute button | 🟡 Might work |
| **Razer Seiren V2 Pro** | Mute button | 🟡 Might work |
| **Razer Seiren X** | Mute button | 🟡 Might work |
| **Razer Seiren Elite** | Mute button | 🟡 Might work |
| **Razer Seiren Mini** | No buttons | ⛔ Won't work |

### Audio-Technica

| Microphone | Button | Tapline |
|---|---|---|
| **Audio-Technica AT2020USB-X** | Touch mute with LED ring | 🟡 Might work |
| **Audio-Technica AT2020USB-XP** | Touch mute | 🟡 Might work |
| **Audio-Technica AT2040USB** | Touch mute | 🟡 Might work |
| **Audio-Technica AT2020USB+** | Two knobs, no button | ⛔ Won't work |
| **Audio-Technica ATR2500x-USB** | Headphone volume only | ⛔ Won't work |

### Sennheiser

| Microphone | Button | Tapline |
|---|---|---|
| **Sennheiser Profile USB** | Mute button | 🟡 Might work |

### beyerdynamic

| Microphone | Button | Tapline |
|---|---|---|
| **beyerdynamic FOX** | Mute button | 🟡 Might work |

### AKG

| Microphone | Button | Tapline |
|---|---|---|
| **AKG Lyra** | Mute button | 🟡 Might work |
| **AKG Ara** | Press the knob to mute | 🟡 Might work |

### Apogee

| Microphone | Button | Tapline |
|---|---|---|
| **Apogee MiC Plus**<br><sub>MiC+</sub> | Press the gain knob to mute | 🟡 Might work |

### Samson

| Microphone | Button | Tapline |
|---|---|---|
| **Samson G-Track Pro** | Mute button | 🟡 Might work |
| **Samson Meteor Mic** | Mute button in the knob | 🟡 Might work |
| **Samson Satellite** | Touch mute | 🟡 Might work |
| **Samson Go Mic** | No mute button | ⛔ Won't work |

### Marantz Professional

| Microphone | Button | Tapline |
|---|---|---|
| **Marantz Professional MPM-4000U** | Mute button | 🟡 Might work |

### Movo

| Microphone | Button | Tapline |
|---|---|---|
| **Movo UM700 / UM300** | Mute button | 🟡 Might work |

### Deity

| Microphone | Button | Tapline |
|---|---|---|
| **Deity VO-7U** | Mute button | 🟡 Might work |

### PreSonus

| Microphone | Button | Tapline |
|---|---|---|
| **PreSonus Revelator** | Monitor and preset buttons | 🟡 Might work |

### SteelSeries

| Microphone | Button | Tapline |
|---|---|---|
| **SteelSeries Alias** | Touch mute | 🟡 Might work |

### JBL

| Microphone | Button | Tapline |
|---|---|---|
| **JBL Quantum Stream** | Tap-to-mute | 🟡 Might work |
| **JBL Quantum Stream Studio / Talk** | Tap-to-mute or press the knob | 🟡 Might work |

### NZXT

| Microphone | Button | Tapline |
|---|---|---|
| **NZXT Capsule / Capsule Mini** | Press the dial to mute | 🟡 Might work |

### Turtle Beach

| Microphone | Button | Tapline |
|---|---|---|
| **Turtle Beach Stream Mic** | Mute button | 🟡 Might work |

### ASUS ROG

| Microphone | Button | Tapline |
|---|---|---|
| **ASUS ROG Carnyx** | Touch mute | 🟡 Might work |

### MSI

| Microphone | Button | Tapline |
|---|---|---|
| **MSI Immerse GV60** | Mute button | 🟡 Might work |

### ROCCAT

| Microphone | Button | Tapline |
|---|---|---|
| **ROCCAT Torch** | Press the dial to mute | 🟡 Might work |

### EPOS

| Microphone | Button | Tapline |
|---|---|---|
| **EPOS B20** | Mute button | 🟡 Might work |

### Trust

| Microphone | Button | Tapline |
|---|---|---|
| **Trust GXT 258 Fyru / GXT 256 Exxo / GXT 232 Mantis** | Mute button | 🟡 Might work |
| **Trust GXT 252 Emita** | No mute button | ⛔ Won't work |

### FIFINE

| Microphone | Button | Tapline |
|---|---|---|
| **FIFINE AmpliTank K688**<br><sub>K688</sub> | Mute button | 🟡 Might work |
| **FIFINE AmpliGame AM8**<br><sub>AM8</sub> | Mute button | 🟡 Might work |
| **FIFINE AmpliGame A6V / A6T**<br><sub>A6V</sub> | Tap-to-mute | 🟡 Might work |
| **FIFINE AmpliGame A8**<br><sub>A8</sub> | Mute button | 🟡 Might work |
| **FIFINE K678 / K683A / K658 / K690** | Mute button | 🟡 Might work |
| **FIFINE K669 / K669B / K670** | Volume knob only | ⛔ Won't work |

### MAONO

| Microphone | Button | Tapline |
|---|---|---|
| **MAONO PD200X** | Mute button | 🟡 Might work |
| **MAONO DM30** | Press the knob to mute | 🟡 Might work |
| **MAONO PM422 / AU-PM421** | Touch mute | 🟡 Might work |
| **MAONO PD400X**<br><sub>352f:0100</sub> | Tap-to-mute | ⛔ Won't work<br><sub>The press arrives mixed with a constant level-meter stream. It needs dedicated support.</sub> |

### TONOR

| Microphone | Button | Tapline |
|---|---|---|
| **TONOR TC310** | Tap the top to mute | 🟡 Might work |
| **TONOR TC-777 / TC30** | No mute button | ⛔ Won't work |

### JLab

| Microphone | Button | Tapline |
|---|---|---|
| **JLab Talk / Talk Pro / Talk Go** | Quick-mute button | 🟡 Might work |

### NEEWER

| Microphone | Button | Tapline |
|---|---|---|
| **NEEWER CM25 / UM01 / DM03** | Mute button | 🟡 Might work |

### Thronmax

| Microphone | Button | Tapline |
|---|---|---|
| **Thronmax MDrill One Pro** | Mute button | 🟡 Might work |

### BOYA

| Microphone | Button | Tapline |
|---|---|---|
| **BOYA BY-PM500** | Knob with mute | 🟡 Might work |

### Zealsound

| Microphone | Button | Tapline |
|---|---|---|
| **Zealsound K66** | Mute button | 🟡 Might work |

### Defender

| Microphone | Button | Tapline |
|---|---|---|
| **Defender Glow GMC 400** | Mute button | 🟡 Might work |

### Oklick

| Microphone | Button | Tapline |
|---|---|---|
| **Oklick SM-700G** | No buttons | ⛔ Won't work |

### Focusrite

| Microphone | Button | Tapline |
|---|---|---|
| **Focusrite Scarlett Solo / 2i2 (3rd and 4th gen)** | Direct monitor button | ⛔ Won't work<br><sub>Interface buttons report through Focusrite's own protocol.</sub> |
| **Focusrite Vocaster One / Two** | Mute button | ⛔ Won't work<br><sub>Focusrite's own protocol.</sub> |

### Yamaha

| Microphone | Button | Tapline |
|---|---|---|
| **Yamaha AG03MK2 / AG06MK2** | Mute button | 🟡 Might work |

### MOTU

| Microphone | Button | Tapline |
|---|---|---|
| **MOTU M2 / M4** | MON buttons | 🟡 Might work |

### Behringer

| Microphone | Button | Tapline |
|---|---|---|
| **Behringer UMC202HD / UMC22** | Direct monitor switch | ⛔ Won't work<br><sub>An analog switch.</sub> |

### TC-Helicon

| Microphone | Button | Tapline |
|---|---|---|
| **TC-Helicon GoXLR / GoXLR Mini** | Mute buttons | ⛔ Won't work<br><sub>Needs the GoXLR app's protocol.</sub> |

## Your mic isn't here?

Run Tapline's setup and press the button three times. Then tell us what happened in an [issue](https://github.com/vnptb/tapline/issues/new): the model, the button, and whether setup recognized it.
