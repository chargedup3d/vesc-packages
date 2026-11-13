; VESC Tool virtual CAN 253. Firmware owns host request callbacks; this worker
; owns one downstream transaction. No automatic replay or transport failover
; of an in-flight request. This first build deliberately exposes reads only.
@const-start
(defun gw-esp-send (dest b) { (var r (esp-send dest b)) (and (eq (car r) 'exit-ok) (eq (ix r 1) t)) })
(defun gw-context () (cond
    ((and (link-carries) link-saved (>= gw-link-target 0)) (list 1 link-mac gw-link-target))
    ((and cfg-vb-en vb-linked (not vb-stale) (< (secs-since vb-last) 2.0))
        (list 2 cfg-vb-mac vb-fwd))
    (t nil)))
(defun gw-target () (if (and gw-route-context (= (ix gw-route-context 0) 1)) (ix gw-route-context 2) cfg-esc-id))
(defun gw-finish () (atomic {
    (if gw-job {
        (if (not gw-probe) (gateway-cancel (ix gw-job 0)))
        (free (ix gw-job 1))
    })
    (def gw-job nil) (def gw-ble-busy false)
}))
(defun gw-motor-identity (b) {
    (var n (buflen b)) (var i 3)
    (loopwhile (and (< i n) (!= (bufget-u8 b i) 0)) (setq i (+ i 1)))
    (and (< (+ i 15) n) (= (bufget-u8 b (+ i 15)) 0))
})
(defun gw-receive (ticket target b) {
    (if (and gw-job (= ticket (ix gw-job 0)) (= target (gw-target))
             (> (buflen b) 0) (= (bufget-u8 b 0) (bufget-u8 (ix gw-job 1) 0))
             (eq gw-route-context (gw-context)) (< (secs-since gw-start) 3.0)) {
        (if gw-probe {
            ; Genuine controller firmware identity, not the screen/Express.
            ; FW_VERSION: bytes 1/2 version, then zero-terminated HW name.
            (if (gw-motor-identity b) { (def gw-online true) (def gw-good-t (systime)) })
        } {
            (gateway-reply ticket b)
            (def gw-good-t (systime))
        })
        (free (ix gw-job 1))
        (def gw-job nil) (def gw-ble-busy false)
    })
})
(defun gw-radio (src b) {
    (if (and gw-job link-saved (eq src link-mac) gw-route-context (= (ix gw-route-context 0) 1)) {
        (var r (gw-wire-feed b 2))
        (if r { (gw-receive (ix r 0) (ix r 1) (ix r 2)) (free (ix r 2)) })
    })
})
(defun gw-ble-reply (b) {
    (var used (and gw-ble-busy gw-job
        (= (bufget-u8 b 0) (bufget-u8 (ix gw-job 1) 0))))
    (if used (gw-receive (ix gw-job 0) (gw-target) b))
    used
})
(defun gw-send-job () {
    (def gw-start (systime))
    (gw-wire-reset)
    (if (= (ix gw-route-context 0) 1)
        (gw-wire-send gw-esp-send link-mac 1 (gw-target) (ix gw-job 0) (ix gw-job 1))
        { (def gw-ble-busy true) (def gw-ble-sent false) true })
})
; Called by the BLE reader, so polling cannot race a new gateway request.
; Drain old packets for one request period first; timeouts drop the BLE link
; to prevent an untagged late response being assigned to a different client.
(defun gw-ble-poll () {
    (if (and gw-ble-busy (not gw-ble-sent) (> (secs-since gw-start) 0.18)) {
        (def gw-ble-sent true) (vb-send (ix gw-job 1))
    })
})
(defun gw-tick () {
    (var ctx (gw-context))
    (if (not (eq ctx gw-route-context)) {
        (gw-finish) (gw-wire-reset)
        (def gw-online false) (def gw-route-context ctx)
        (def gw-route-key (+ gw-route-key 1u32))
        (def gw-probe-t 0)
    })
    (if (and gw-job (> (secs-since gw-start) 3.0)) {
        (if gw-ble-busy { (vb-drop) (def vb-stale true) })
        (gw-finish) (def gw-online false)
    })
    (gateway-route gw-route-key (if (and ctx gw-online (< (secs-since gw-good-t) 5.0)) 1 0) 0)
    (if (and ctx (not gw-job)) {
        (def gw-probe false)
        (def gw-job (gateway-next))
        (if (and (not gw-job) (> (secs-since gw-probe-t) 2.0)) {
            (def gw-probe-t (systime)) (def gw-probe true)
            (def gw-probe-seq (bitwise-and (+ gw-probe-seq 1u32) 0x7fffffffu32))
            (def gw-job (list gw-probe-seq (bufcreate 1)))
        })
        (if gw-job (if (not (gw-send-job)) { (gw-finish) (def gw-online false) }))
    })
})
(defun gw-start-worker () {
    (if (eq (car (trap (gateway-route 0 0 0))) 'exit-ok) {
        (def gw-probe-seq (to-u (rand (systime))))
        (def gw-running true)
        (loopwhile-thd ("Gateway" 300) t {
            (var r (trap (gw-tick)))
            (if (eq (car r) 'exit-error) {
                (def gw-errors (+ gw-errors 1)) (def gw-error r)
                (trap (gw-finish)) (trap (gateway-route 0 0 0))
                (def gw-online false)
            })
            (sleep 0.01)
        })
    })
})
(defun gw-info () (print (list "gateway read-only" gw-online "route" gw-route-context
    "busy" (not (eq gw-job nil)) "errors" gw-errors gw-error)))
@const-end
(def gw-route-context nil) (def gw-route-key 0u32)
(def gw-online false) (def gw-good-t 0) (def gw-start 0)
(def gw-job nil) (def gw-probe false) (def gw-probe-seq 0u32) (def gw-probe-t 0)
(def gw-ble-busy false) (def gw-ble-sent false)
(def gw-running false) (def gw-errors 0) (def gw-error nil)

(def gw-link-target -1)
