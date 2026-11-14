// SPDX-License-Identifier: GPL-3.0-or-later
// Only Motor Wizard tuning may enter the saved owner configuration.
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
typedef struct { unsigned offset, length; } mw_span;
typedef struct {
    uint32_t mc_sig, app_sig;
    unsigned mc_len, app_len, app_type, abs_max, r, l, flux, sensor, hall, cal_mode, offsets;
    unsigned tune_count;
} mw_schema;
#include "schema.h"
// Flat native libraries are relocated without a dynamic linker. An address
// stored inside a static initializer remains a zero-based link address, even
// with -fpic. Resolve these arrays through PC-relative code instead.
static const mw_span *mw_tune(const mw_schema *s) {
    return s==&schema_7 ? tune_7 : tune_6;
}
static uint32_t mw_u32(const uint8_t *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static float mw_float(const uint8_t *p) {
    union { uint32_t u; float f; } v; v.u=mw_u32(p); return v.f;
}
static void mw_copy(uint8_t *d,const uint8_t *s,unsigned n) {
    for (unsigned i=0;i<n;i++) d[i]=s[i];
}
static bool mw_equal(const uint8_t *a,const uint8_t *b,unsigned n) {
    for (unsigned i=0;i<n;i++) if (a[i]!=b[i]) return false;
    return true;
}
static const mw_schema *mw_schema_for(const uint8_t *p,unsigned n) {
    if (n<5 || p[0]!=14) return 0;
    if (n==schema_6.mc_len && mw_u32(p+1)==schema_6.mc_sig) return &schema_6;
    if (n==schema_7.mc_len && mw_u32(p+1)==schema_7.mc_sig) return &schema_7;
    return 0;
}
static bool mw_app_valid(const mw_schema *s,const uint8_t *p,unsigned n) {
    return s && n==s->app_len && p[0]==17 && mw_u32(p+1)==s->app_sig && p[s->app_type]==3;
}
static bool mw_positive(const uint8_t *p,float max) {
    float v=mw_float(p);return isfinite(v) && v>0 && v<max;
}
static void mw_keep_live_offsets(const mw_schema *s,uint8_t *desired,const uint8_t *live) {
    // VESC 7 SET_MCCONF deliberately ignores supplied offsets unless bit 1
    // enables writing them. Native detection recalibrates these ADC offsets.
    // Match that exact firmware behavior, then verify every returned byte.
    // VESC 6 has no such flag and accepts the original offset values.
    if (s->cal_mode && !(desired[s->cal_mode]&2))
        mw_copy(desired+s->offsets,live+s->offsets,24);
}
static bool mw_merge(const mw_schema *s,uint8_t *dst,const uint8_t *old,const uint8_t *det,unsigned n) {
    if (mw_schema_for(det,n)!=s || det[7]!=2 || det[s->sensor]>2 ||
        !mw_positive(det+s->r,10) || !mw_positive(det+s->l,.1f) ||
        !mw_positive(det+s->flux,1) ||
        !mw_positive(det+s->sensor-25,1e6f) || // current kp, both schemas
        !mw_positive(det+s->sensor-21,1e6f) || // current ki
        !mw_positive(det+s->flux+4,1e20f)) return false; // observer gain
    // A Hall result must contain six usable states; native success alone is
    // insufficient (some vendor builds return success with invalid flux).
    if (det[s->sensor]==2) {
        unsigned usable=0;
        for (unsigned i=0;i<8;i++) {
            uint8_t v=det[s->hall+i];
            if (v<200) usable++; else if (v!=255) return false;
        }
        if (usable!=6) return false;
    }
    mw_copy(dst,old,n);
    for (unsigned i=0;i<s->tune_count;i++) {
        mw_span span=mw_tune(s)[i];mw_copy(dst+span.offset,det+span.offset,span.length);
    }
    // Detection may reduce current, never silently increase the owner's caps.
    unsigned limits[]={9,13,s->abs_max};
    for (unsigned i=0;i<3;i++) {
        unsigned off=limits[i];float a=mw_float(old+off),b=mw_float(det+off);
        if (!isfinite(a) || !isfinite(b) || a*b<=0) return false;
        if (fabsf(b)<fabsf(a)) mw_copy(dst+off,det+off,4);
    }
    return true;
}
