// Copyright 2022 Sergey Vlasov (@sigprof)
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#define DYNAMIC_KEYMAP_LAYER_COUNT 8

// Consumer/media keycodes (volume, media transport) need a real press duration to register on
// the host; at the default 0ms they get dropped or coalesced, so a volume knob drifts instead
// of tracking. The stock keymap hit this too and used tap_code_delay(..., 10) explicitly —
// ENCODER_MAP taps via TAP_CODE_DELAY instead, so it has to be set here.
#define TAP_CODE_DELAY 10
