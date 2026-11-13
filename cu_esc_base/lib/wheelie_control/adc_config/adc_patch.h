// SPDX-License-Identifier: GPL-3.0-or-later
// Deliberately limited to the verified stock 7.00 APP schema. Never MC config.
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#define ADC_APP_LEN 285
static bool adc_schema(const uint8_t *p, unsigned n) {
    return n == ADC_APP_LEN && p[0] == 17 && p[1] == 0x8e &&
        p[2] == 0x19 && p[3] == 0x5e && p[4] == 0x93;
}
static void adc_mv(uint8_t *p, unsigned pos, float v) {
    unsigned mv = (unsigned)(v * 1000.0f + 0.5f);
    p[pos] = mv >> 8; p[pos + 1] = mv;
}
static bool adc_patch(uint8_t *p, unsigned n, int channel, float rest, float full) {
    if (!adc_schema(p,n) || (channel != 1 && channel != 2) ||
        !isfinite(rest) || !isfinite(full) || rest <= 0.05f || rest >= 3.25f ||
        full <= 0.05f || full >= 3.25f || fabsf(full-rest) < 0.30f) return false;
    float lo = fminf(rest, full), hi = fmaxf(rest, full);
    adc_mv(p, channel == 1 ? 96 : 106, lo);
    adc_mv(p, channel == 1 ? 98 : 108, hi);
    p[channel == 1 ? 113 : 114] = rest > full;
    if (channel == 1) {
        adc_mv(p,100,fmaxf(0.05f,lo-0.20f));
        adc_mv(p,102,fminf(3.25f,hi+0.20f));
    }
    return true;
}
