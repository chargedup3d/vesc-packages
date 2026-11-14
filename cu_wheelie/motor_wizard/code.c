// SPDX-License-Identifier: GPL-3.0-or-later
// Motor Wizard backup/commit/rollback. No arbitrary commands or motor drive.
#include "vesc_c_if.h"
#include "transaction.h"
HEADER
#define MW_MAX 512
typedef struct {
    uint8_t reply[MW_MAX], mc[MW_MAX], app[MW_MAX], desired[MW_MAX];
    unsigned length;
    uint8_t expected;
    volatile bool busy, pending;
    bool active, committed;
    int action, motor;
    lbm_cid cid;
    lib_thread thread;
    const mw_schema *schema;
} mw_data;
static mw_data *context(void) {
    void **slot=VESC_IF->get_arg(PROG_ADDR);return slot ? *slot : 0;
}
static void reply(uint8_t *p,unsigned n) {
    mw_data *d=context();
    if (!d || !d->busy || !n || p[0]!=d->expected || n>MW_MAX) return;
    mw_copy(d->reply,p,n);d->length=n;
}
static void request(mw_data *d,uint8_t *p,unsigned n) {
    d->length=0;d->expected=p[0];
    VESC_IF->commands_process_packet(p,n,reply);
    VESC_IF->commands_unregister_reply_func(reply);
}
static bool idle(void) {
    return VESC_IF->app_is_output_disabled() && fabsf(VESC_IF->mc_get_rpm())<50 &&
        fabsf(VESC_IF->mc_get_tot_current_filtered())<.2f;
}
static bool write_verify(mw_data *d,uint8_t *p,unsigned n,bool force_store) {
    uint8_t get=p[0];request(d,&get,1);
    if (!force_store && d->length==n && mw_equal(d->reply,p,n)) return true;
    if (!idle()) return false;
    p[0]=get-1;request(d,p,n);p[0]=get;
    if (d->length!=1 || d->reply[0]!=get-1) return false;
    request(d,&get,1);
    return d->length==n && mw_equal(d->reply,p,n);
}
// 0 probe, 1 backup, 2 commit verified tuning, 3 restore backup;
// 4 wizard flux frequency, 5 minimum current in microamps (7.00 schema),
// 6 accept a verified commit after the Lisp cancellation/session recheck.
// Backup is
// retained after any failure so END can retry while motor output stays held.
static int perform(mw_data *d,int action) {
    int result=-1;
    if (action && !idle()) { result=-2;goto done; }
    if (action==6) {
        if (d->committed) { d->active=false;d->committed=false;result=1; }
        else result=-2;
        goto done;
    }
    uint8_t get=14;request(d,&get,1);
    const mw_schema *s=mw_schema_for(d->reply,d->length);
    if (!s || (d->active && d->schema!=s)) goto done;
    if (action>=4) {
        if (s!=&schema_7) goto done;
        if (action==4) result=d->reply[237]==1 ? 25000 : 40000;
        else {
            float min=mw_float(d->reply+385);
            if (isfinite(min) && min>0 && min<100) result=(int)(min*1000000.0f);
        }
        goto done;
    }
    if (action<=1) {
        if (action==1) mw_copy(d->mc,d->reply,s->mc_len);
        get=17;request(d,&get,1);
        if (!mw_app_valid(s,d->reply,d->length)) goto done;
        if (action==1) { mw_copy(d->app,d->reply,s->app_len);d->schema=s;d->active=true;d->committed=false; }
        result=1;goto done;
    }
    if (action==2) {
        if (VESC_IF->mc_get_fault()!=FAULT_CODE_NONE ||
            !mw_merge(s,d->desired,d->mc,d->reply,d->length)) { result=-6;goto done; }
    } else mw_copy(d->desired,d->mc,s->mc_len);
    mw_keep_live_offsets(s,d->desired,d->reply);
    // Staged measurements only change RAM. Even matching live bytes still
    // require SET_MCCONF to persist the tune (or restore a failed commit).
    if (!write_verify(d,d->desired,s->mc_len,true)) { result=-4;goto done; }
    // Native detect also changes CAN status settings. Preserve the APP backup,
    // including throttle/brake calibration, UART selection, and timeout.
    if (!write_verify(d,d->app,s->app_len,false)) { result=-5;goto done; }
    if (action==2) d->committed=true;
    else { d->active=false;d->committed=false; }
    result=1;
done:
    VESC_IF->commands_unregister_reply_func(reply);d->busy=false;
    return result;
}
static void worker_once(mw_data *d) {
    if (!d->pending) return;
    d->pending=false;
    lbm_cid cid=d->cid;
    VESC_IF->mc_select_motor_thread(d->motor);
    int result=perform(d,d->action);
    VESC_IF->lbm_unblock_ctx_unboxed(cid,VESC_IF->lbm_enc_i(result));
}
static void worker(void *arg) {
    mw_data *d=arg;
    while (!VESC_IF->should_terminate()) {
        worker_once(d);VESC_IF->sleep_ms(2);
    }
}
static lbm_value transaction(lbm_value *args,lbm_uint count) {
    if (count!=1 || !VESC_IF->lbm_is_number(args[0])) return VESC_IF->lbm_enc_i(-3);
    mw_data *d=context();int action=VESC_IF->lbm_dec_as_i32(args[0]);
    if (!d || d->busy || action<0 || action>6) return VESC_IF->lbm_enc_i(-2);
    if (action && !idle()) return VESC_IF->lbm_enc_i(-2);
    if ((action==1 && d->active) || (action>=2 && !d->active)) return VESC_IF->lbm_enc_i(-2);
    d->busy=true;
    if (action==2 || action==3) {
        // SET_MCCONF takes the firmware's full flash/configuration call chain.
        // Keep it off the 2 KiB Lisp evaluator stack and let heartbeats run.
        d->action=action;d->motor=VESC_IF->mc_get_motor_thread();
        d->cid=VESC_IF->lbm_get_current_cid();
        VESC_IF->lbm_block_ctx_from_extension();d->pending=true;
        return VESC_IF->lbm_enc_sym_true;
    }
    return VESC_IF->lbm_enc_i(perform(d,action));
}
static void stop(void *arg) {
    mw_data *d=arg;
    if (d->thread) VESC_IF->request_terminate(d->thread);
    VESC_IF->commands_unregister_reply_func(reply);VESC_IF->free(d);
}
INIT_FUN(lib_info *info) {
    INIT_START
    if (!VESC_IF->commands_process_packet || !VESC_IF->commands_unregister_reply_func ||
        !VESC_IF->app_is_output_disabled || !VESC_IF->spawn ||
        !VESC_IF->lbm_unblock_ctx_unboxed) return false;
    mw_data *d=VESC_IF->malloc(sizeof(mw_data));if (!d) return false;
    d->length=0;d->busy=false;d->pending=false;d->active=false;d->committed=false;d->schema=0;
    d->thread=0;
    info->arg=d;info->stop_fun=stop;
    d->thread=VESC_IF->spawn(worker,4096,"mw_save",d);
    if (d->thread && VESC_IF->lbm_add_extension("ext-mw-transaction",transaction)) return true;
    if (d->thread) VESC_IF->request_terminate(d->thread);
    VESC_IF->free(d);info->arg=0;info->stop_fun=0;return false;
}
