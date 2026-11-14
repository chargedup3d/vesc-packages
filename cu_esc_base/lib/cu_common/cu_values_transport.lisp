; CAN and direct VESC custom-app/BLE share the same setup workers.
; A held session belongs to its original route until explicit END.
; These handlers already live in flash. Preserve their references.
(def ms-handle ms-command) (def hc-handle hc-command)
@const-start
(def ms-route 0) (def ms-ble-t 0) (def hc-route 0)
(defun ms-ble-active () (and (> ms-ble-t 0) (< (secs-since ms-ble-t) 2.0)))
(defun ms-wire-valid (b) (and (= (buflen b) 8)
    (= (bufget-u8 b 0) 0x57) (= (bufget-u8 b 1) 0x31)))
(defun hc-wire-valid (b) (and (= (buflen b) 8)
    (= (bufget-u8 b 0) 0x57) (= (bufget-u8 b 1) 0x30)))
(defun ms-route-command (b route) (if (and (ms-wire-valid b)
    (or (not ms-lock) (= ms-route route))
    (or (not hc-lock) (= hc-route route))) {
    (setvar 'ms-route route) (ms-handle b)
    (if (not ms-lock) (setvar 'ms-route 0)) t
} nil))
(defun hc-route-command (b route) (if (and (hc-wire-valid b)
    (or (not hc-lock) (= hc-route route))
    (or (not ms-lock) (= ms-route route))) {
    (setvar 'hc-route route) (hc-handle b)
    (if (not hc-lock) (setvar 'hc-route 0)) t
} nil))
(defun ms-command (b) (ms-route-command b 1))
(defun hc-command (b) (hc-route-command b 1))
; Version 2 advertises full setup, with the same 41-byte layout. Reuse the
; CAN snapshot so running, ADC channels, elapsed and IMU tokens cannot differ.
; Reply to requests only, never stream to whichever host last polled.
(defun ms-ble-reply () (atomic {
    (ms-snapshot)
    (var b (bufcreate 41))
    (bufset-u8 b 0 0x53) (bufset-u8 b 1 2) (bufset-u16 b 2 ms-session)
    (bufset-u8 b 4 ms-seq) (bufcpy b 5 ms-payload 0 36)
    (send-data b) (free b)
}))
(defun hc-ble-reply () (atomic {
    (hc-snapshot)
    (var b (bufcreate 29))
    (bufset-u8 b 0 0x48) (bufset-u8 b 1 2) (bufset-u16 b 2 hc-session)
    (bufset-u8 b 4 hc-seq) (bufcpy b 5 hc-payload 0 24)
    (send-data b) (free b)
}))
(defun ms-ble-rx (b) (cond
    ((ms-wire-valid b) {
        (var action (bufget-u8 b 2))
        ; Action 14 is a read-only poll; old bulk save 12 stays unsupported.
        (if (and (or (<= action 11) (= action 13) (= action 14))
                 (ms-route-command b 2)) {
            (setvar 'ms-ble-t (systime))
            (if (!= action 9) (ms-ble-reply))
        }) t
    })
    ((hc-wire-valid b) {
        (if (and (<= (bufget-u8 b 2) 4) (hc-route-command b 2)) {
            (setvar 'ms-ble-t (systime)) (hc-ble-reply)
        }) t
    })
    (t nil)))
@const-end
