# Winry315 macropad

The 15-key + 3-encoder pad that drives DMC. Also known as `YD3xn15mx`; sold by dztech.
`atmega32u4`, `atmel-dfu` bootloader, VID `0xF1F1` / PID `0x0315`.

Everything here exists because the stock dztech firmware could not do two things: run reactive
RGB effects, and let VIA remap encoder rotation. Both needed a rebuild.

## Layout

|        | col 1 | col 2 | col 3 | col 4 | col 5 |
|--------|-------|-------|-------|-------|-------|
| row 1  | `F13` | `F14` | `F15` | `F16` | `F` |
| row 2  | `⇧F13` | `⇧F14` | `⇧F15` | `⇧F16` | `R` |
| row 3  | `⌃F13` | `⌃F14` | `⌃F15` | `⌃F16` | `X` |

| Encoder | Rotate | Press |
|---------|--------|-------|
| left    | DMC master volume | pause / resume |
| centre  | mousewheel | middle click |
| right   | RGB brightness | RGB mode next |

The left knob deliberately does **not** send `KC_VOLU`/`KC_VOLD`. macOS routes system volume to
Bluetooth headphones over AVRCP absolute volume, where each keypress is a round trip on a coarse
scale; rapid encoder taps get coalesced into jumps straight to 0 or ~50% instead of progressive
steps. Over the laptop speakers the identical keycodes behave perfectly, which makes the fault
look intermittent and sends you chasing the encoder, the tap timing and `ENCODER_MAP` in turn.
None of those are the cause.

It sends bare `KC_F17` / `KC_F18` / `KC_F19` instead, which DMC reads as hotkey slots 4-6 and
maps to master volume up, down and pause/resume. That bypasses macOS and Bluetooth entirely, and
only rides the ambience — a Discord ping stays where you set it. The trade-off is that it does
nothing while DMC is closed.

`F17`-`F20` specifically, and without a modifier. `F14`/`F15` are brightness on Apple keyboards
and macOS claims them whatever modifier you add: `LALT(KC_F14)` opened Displays settings *as well
as* reaching DMC. `F17`-`F20` carry no default binding at all.

DMC reads these as hotkey slots: bare `F13`–`F16` are slots 0–3, shifted 8–11, control 16–19.
See `HotkeyManager.padLayout`.

## Rebuilding the firmware

Needs `avr-gcc` and `dfu-programmer`:

```sh
brew tap osx-cross/avr
brew trust --formula osx-cross/avr/avr-binutils osx-cross/avr/avr-gcc@12
brew install osx-cross/avr/avr-gcc@12 dfu-programmer
```

QMK itself, shallow and AVR-only (the ARM submodules are ~2 GB of nothing useful here):

```sh
git clone --depth 1 https://github.com/qmk/qmk_firmware.git
cd qmk_firmware
git submodule update --init --depth 1 lib/lufa lib/printf
python3 -m venv .venv && .venv/bin/pip install qmk       # build needs the qmk CLI
```

Then apply this directory:

1. Copy `firmware/{keymap.c,config.h,rules.mk}` to `keyboards/winry/winry315/keymaps/via/`.
   Upstream QMK no longer ships VIA keymaps — they live in `qmk/qmk_userspace_via` — and that
   copy still uses the old `RGB_*` keycodes, which current QMK removed in favour of `RM_*`.
   The `keymap.c` here is the fixed version.
2. Merge `firmware/rgb_matrix.override.json` into `keyboards/winry/winry315/keyboard.json`,
   replacing its `animations` block. Trimming 39 effects to 3 is what keeps the build inside
   the atmega32u4's 28,672-byte ceiling.
3. Regenerate keycodes at spec 0.0.8: `qmk generate-keycodes --version 0.0.8 -o quantum/keycodes.h`.
   QMK master emits 0.0.9, which VIA rejects as unsupported. The only difference between the
   two specs is the steno range, so nothing is lost here.
4. `make winry/winry315:via`

Last build: 20,872 / 28,672 bytes (72%).

## Flashing

Enter DFU by holding the **top-left key of the 5x3 grid** (matrix `[0,0]`) while plugging USB in.
Or assign `QK_BOOT` to a key in VIA and press it.

```sh
dfu-programmer atmega32u4 erase --force
dfu-programmer atmega32u4 flash winry315_via_splash.hex
dfu-programmer atmega32u4 launch
```

The atmega32u4's DFU bootloader lives in a write-protected section, so a failed flash is
recoverable — re-enter DFU and try again.

## Restoring the keymap after a flash

Flashing erases EEPROM, taking the keymap with it. `setmap.swift` writes it back over VIA's raw
HID channel and verifies every value, which is faster and more reliable than re-importing
`winry315.layout.json` by hand:

```sh
swiftc -O -parse-as-library -o /tmp/setmap setmap.swift \
  -target arm64-apple-macos15 -framework IOKit
/tmp/setmap
```

`winry315.layout.json` is a dump of the live board for reference.
