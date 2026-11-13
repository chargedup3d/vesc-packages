@const-start
; Typed on-screen setup. Standard CAN 5C0+offset request / 5D0+offset reply.
; Request: 49 action controller session:u16 token forward up. Network endian.
; Reply: 49 80/81 token status [forward up flags version] / [pitch:i16 roll:i16].
; Mutation requires this board's fresh, assembled controller service hold.
(def is-start 0) (def is-status 0) (def is-owner nil) (def is-last nil)
(defun is-held () (and su-held (= su-id cfg-esc-id) (> su-t 0)
    (< (secs-since su-t) 0.8) (= (bufget-u8 su-data 5) 4)
    (= (bitwise-and (bufget-u8 su-data 7) 3) 1)))
(defun is-stored () (and (= (eeprom-read-i 5) fwd-axis) (= (eeprom-read-i 6) up-axis)
    (= (eeprom-read-i 9) cal-valid)
    (< (abs (- (eeprom-read-f 12) pitch-off)) 0.0001)
    (< (abs (- (eeprom-read-f 13) roll-off)) 0.0001)
    (< (abs (- (eeprom-read-f 14) bias-x)) 0.0001)
    (< (abs (- (eeprom-read-f 15) bias-y)) 0.0001)
    (< (abs (- (eeprom-read-f 16) bias-z)) 0.0001)))
(defun is-reply (token) {
    (var b (bufcreate 8)) (bufset-u8 b 0 0x49) (bufset-u8 b 1 0x80)
    (bufset-u8 b 2 token) (bufset-u8 b 3 is-status)
    (bufset-u8 b 4 fwd-axis) (bufset-u8 b 5 up-axis)
    (bufset-u8 b 6 (frame-flags)) (bufset-u8 b 7 1)
    (can-send-sid (+ 0x5D0 can-off) b)
    (bufset-u8 b 1 0x81)
    (bufset-i16 b 4 (to-i (* 100.0 (clamp pitch -180.0 180.0))))
    (bufset-i16 b 6 (to-i (* 100.0 (clamp roll -180.0 180.0))))
    (can-send-sid (+ 0x5D0 can-off) b) (free b)
})
(defun is-can (id b) (if (and (= id (+ 0x5C0 can-off)) (= (buflen b) 8)
    (= (bufget-u8 b 0) 0x49) (= (bufget-u8 b 2) cfg-esc-id)) {
    (var action (bufget-u8 b 1)) (var session (bufget-u16 b 3))
    (var token (bufget-u8 b 5)) (var f (bufget-u8 b 6)) (var u (bufget-u8 b 7))
    (var key (list session token action))
    (if (and (> action 0) (<= action 2) (not-eq key is-last)) {
        (def is-last key)
        (cond
            ((not (and (is-held) (= session (bufget-u16 su-data 2)) (= cal-state 0))) (def is-status 5))
            ((= action 1) (if (and (<= f 5) (<= u 5) (!= (/ f 2) (/ u 2))) {
                (if (or (!= f fwd-axis) (!= u up-axis)) {
                    (setvar 'fwd-axis f) (setvar 'up-axis u) (apply-mount)
                    (setvar 'cal-valid 0) (setvar 'pitch-off 0.0) (setvar 'roll-off 0.0)
                    (setvar 'fused-init 0) (save-settings)
                })
                (def is-status (if (and (= (eeprom-read-i 5) fwd-axis) (= (eeprom-read-i 6) up-axis) (= (eeprom-read-i 9) cal-valid)) 1 6))
            } (def is-status 4)))
            ((= action 2) (if (and (= imu-ok 1) (= mount-ok 1)) {
                (def is-owner t) (def is-start (systime)) (def is-status 2) (cal-start)
            } (def is-status 4)))
        )
    })
    (is-cal-guard)
    (if (<= action 2) (is-reply token))
}))
(defun is-cal-guard () (if (and is-owner (or (not (is-held)) (> (secs-since is-start) 3.0))) {
    (setvar 'cal-state 0) (def is-owner nil) (def is-status 5)
    (set-msg "Zero Level cancelled: setup link lost")
}))

@const-end
