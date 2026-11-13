// SPDX-License-Identifier: GPL-3.0-or-later
// Typed input-only persistence helper. Uses VESC's normal APP serializer/store;
// no conf-store, MC write, arbitrary packet interface, or motor command.
#include "vesc_c_if.h"
#include "adc_patch.h"
HEADER
typedef struct {
    uint8_t reply[ADC_APP_LEN];
    uint8_t desired[ADC_APP_LEN];
    unsigned length;
    uint8_t expected;
    bool busy;
} adc_data;
static adc_data *context(void) {
    void **slot=VESC_IF->get_arg(PROG_ADDR);
    return slot ? *slot : 0;
}
static void reply(uint8_t *p, unsigned n) {
    adc_data *d = context();
    if (!d || !d->busy || !n || p[0] != d->expected || n > ADC_APP_LEN) return;
    for (unsigned i=0;i<n;i++) d->reply[i]=p[i];
    d->length=n;
}
static void request(adc_data *d, uint8_t *p, unsigned n) {
    d->length=0; d->expected=p[0];
    VESC_IF->commands_process_packet(p,n,reply);
    VESC_IF->commands_unregister_reply_func(reply);
}
static bool idle(void) {
    return VESC_IF->app_is_output_disabled() &&
        fabsf(VESC_IF->mc_get_rpm()) < 50.0f &&
        fabsf(VESC_IF->mc_get_tot_current_filtered()) < 0.2f &&
        VESC_IF->mc_get_fault() == FAULT_CODE_NONE;
}
// channel 0 is a read-only compatibility probe. Writes require the Lisp
// service/session/released-input guards AND the independent native idle guard.
static lbm_value save(lbm_value *args, lbm_uint count) {
    if (count != 3 || !VESC_IF->lbm_is_number(args[0]) ||
        !VESC_IF->lbm_is_number(args[1]) || !VESC_IF->lbm_is_number(args[2]))
        return VESC_IF->lbm_enc_i(-3);
    adc_data *d=context();
    int channel=VESC_IF->lbm_dec_as_i32(args[0]), result=-1;
    float rest=VESC_IF->lbm_dec_as_float(args[1]), full=VESC_IF->lbm_dec_as_float(args[2]);
    if (!d || d->busy) return VESC_IF->lbm_enc_i(-2);
    if (channel != 0 && !idle()) return VESC_IF->lbm_enc_i(-2);
    d->busy=true;
    uint8_t get=17;
    request(d,&get,1);
    if (!adc_schema(d->reply,d->length)) goto done;
    if (channel == 0) { result=1; goto done; }
    // UART-only calibration: never change the running application or enable
    // ADC drive as a side effect of saving one input.
    if (d->reply[34] != 3) { result=-2; goto done; }
    for (unsigned i=0;i<ADC_APP_LEN;i++) d->desired[i]=d->reply[i];
    if (!adc_patch(d->desired,ADC_APP_LEN,channel,rest,full)) { result=-3; goto done; }
    if (!idle()) { result=-2; goto done; }
    d->desired[0]=16;
    request(d,d->desired,ADC_APP_LEN);
    d->desired[0]=17;
    if (d->length!=1 || d->reply[0]!=16) { result=-4; goto done; }
    request(d,&get,1);
    result=-5;
    if (d->length!=ADC_APP_LEN) goto done;
    for (unsigned i=0;i<ADC_APP_LEN;i++) if (d->desired[i]!=d->reply[i]) goto done;
    result=1;
done:
    VESC_IF->commands_unregister_reply_func(reply);
    d->busy=false;
    return VESC_IF->lbm_enc_i(result);
}
static void stop(void *arg) {
    VESC_IF->commands_unregister_reply_func(reply);
    VESC_IF->free(arg);
}
// Read-only chemistry check; stock Lisp exposes cell count but not type.
static lbm_value battery_type(lbm_value *args, lbm_uint count) {
    (void)args;
    return VESC_IF->lbm_enc_i(!count && VESC_IF->get_cfg_int ?
        VESC_IF->get_cfg_int(CFG_PARAM_si_battery_type) : -1);
}
INIT_FUN(lib_info *info) {
    INIT_START
    if (!VESC_IF->commands_process_packet || !VESC_IF->commands_unregister_reply_func ||
        !VESC_IF->app_is_output_disabled) return false;
    adc_data *d=VESC_IF->malloc(sizeof(adc_data));
    if (!d) return false;
    d->length=0; d->expected=0; d->busy=false;
    info->arg=d; info->stop_fun=stop;
    if (VESC_IF->lbm_add_extension("ext-ms-adc-save",save) &&
        VESC_IF->lbm_add_extension("ext-ms-battery-type",battery_type)) return true;
    VESC_IF->free(d); info->arg=0; info->stop_fun=0;
    return false;
}
