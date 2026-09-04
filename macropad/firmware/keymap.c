// Based on the upstream VIA keymap by Sergey Vlasov (@sigprof)
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Updated for current QMK: the RGB_* keycodes were renamed to RM_* when RGB Matrix and
// RGBLIGHT keycodes were split apart, and the old names no longer exist.

#include QMK_KEYBOARD_H

// clang-format off

#define U_LTESC LT(1, KC_ESC)

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT_top(
            KC_HOME,           KC_MUTE,           KC_MPLY,
             KC_1,    KC_2,    KC_3,    KC_4,    KC_5,
             KC_6,    KC_7,    KC_8,    KC_9,    KC_0,
             U_LTESC, KC_TAB,  KC_SPC,  KC_BSPC, KC_ENT
    ),
    [1] = LAYOUT_top(
            RM_TOGG,           RM_NEXT,           RM_PREV,
             RM_NEXT, RM_HUEU, RM_SATU, RM_VALU, RM_SPDU,
             RM_PREV, RM_HUED, RM_SATD, RM_VALD, RM_SPDD,
             KC_TRNS, RM_TOGG, RM_ON,   RM_OFF,  RM_NEXT
    ),
    [2 ... 7] = LAYOUT_top(
            KC_TRNS,           KC_TRNS,           KC_TRNS,
             KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
             KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS,
             KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),
};

// clang-format on

#ifdef ENCODER_MAP_ENABLE
// Encoder 3 drives RGB brightness on the base layer — the thing the old firmware could never
// do, because rotation was hardcoded in C and VIA had no way to reach it. With
// ENCODER_MAP_ENABLE all three are remappable from VIA anyway.
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][NUM_DIRECTIONS] = {
    [0] =        { ENCODER_CCW_CW(KC_PGUP, KC_PGDN), ENCODER_CCW_CW(KC_VOLD, KC_VOLU), ENCODER_CCW_CW(RM_VALD, RM_VALU) },
    [1] =        { ENCODER_CCW_CW(RM_HUED, RM_HUEU), ENCODER_CCW_CW(RM_SATD, RM_SATU), ENCODER_CCW_CW(KC_MPRV, KC_MNXT) },
    [2 ... 7] =  { ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______), ENCODER_CCW_CW(_______, _______) }
};
#endif
