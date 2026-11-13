@const-start
(def ms-route 0) (def ms-ble-seq 0) (def ms-ble-t 0)
(defun ms-ble-active () (and (> ms-ble-t 0) (< (secs-since ms-ble-t) 2.0)))
(def ms-handle ms-command)
(defun ms-wire-valid (b) (and (= (buflen b) 8)
(= (bufget-u8 b 0) 0x57) (= (bufget-u8 b 1) 0x31)))
(defun ms-route-command (b route) (if (and (ms-wire-valid b)
(or (not ms-lock) (= ms-route route))) {
(setvar 'ms-route route)
(ms-handle b)
(if (not ms-lock) (setvar 'ms-route 0))
t
} nil))
(defun ms-command (b) (ms-route-command b 1))
(defun ms-ble-reply () (atomic {
(var b (bufcreate 41))
(setvar 'ms-ble-seq (mod (+ ms-ble-seq 1) 256))
(bufset-u8 b 0 0x53) (bufset-u8 b 1 1) (bufset-u16 b 2 ms-session)
(bufset-u8 b 4 ms-ble-seq) (bufset-u8 b 5 ms-kind)
(bufset-u8 b 6 ms-stage) (bufset-u8 b 7 (if ms-lock 1 0)) (bufset-u8 b 8 ms-error)
(looprange i 0 4 (bufset-f32 b (+ 9 (* i 4)) (ix ms-values i)))
(bufset-f32 b 25 (to-float (ix bs-caps 2)))
(bufset-f32 b 29 (to-float (ix bs-caps 0)))
(bufset-u16 b 33 (if (< bs-token 0) 65535 bs-token))
(bufset-u8 b 35 0) (bufset-u8 b 36 (get-fault)) (bufset-f32 b 37 (get-rpm))
(send-data b) (free b)
}))
(defun ms-ble-rx (b) (if (ms-wire-valid b) {
(var action (bufget-u8 b 2))
(if (and (or (= action 0) (= action 4) (= action 5) (= action 9)
(= action 11) (= action 13)
(and (= action 1) (= (bufget-u8 b 5) 5)))
(or (not ms-lock) (= ms-kind 5))
(ms-route-command b 2))
{ (setvar 'ms-ble-t (systime)) (if (!= action 9) (ms-ble-reply)) })
t
} nil))
@const-end
