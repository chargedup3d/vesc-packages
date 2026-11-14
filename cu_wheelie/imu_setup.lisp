; Forward typed IMU setup over CAN, independently of which board carries radio.
; ms-kind 4 reuses the existing service hold. It never raises drive limits.
@const-start
(def im-local-error 0) (def im-done -1) (def im-view-t 0) (def im-t 0) (def im-send-t 0) (def im-request -1)
(def im-token 0) (def im-begin 0) (def im-mask 0) (def im-status 0)
(def im-flags 0) (def im-f 0) (def im-u 4) (def im-pitch 0.0) (def im-roll 0.0)
(def im-want-f 0) (def im-want-u 4) (def im-last nil) (def im-wire nil)
(defun im-fresh () (and (> im-t 0) (< (secs-since im-t) 0.8)))
(defun im-safe () (and ms-lock (= ms-kind 4) (= ms-stop 0) (ms-safe)
    (> ms-ack 0) (< (secs-since ms-ack) 0.6) (< (secs-since ms-beat) 0.6)))
(defun im-begin-request (cmd) {
    (def im-request cmd) (def im-token (mod (+ im-token 1) 256))
    (def im-mask 0) (def im-begin (systime)) (def im-send-t 0)
    (bufset-u8 im-wire 0 0x49) (bufset-u8 im-wire 1 cmd) (bufset-u8 im-wire 2 (can-local-id))
    (bufset-u16 im-wire 3 ms-session) (bufset-u8 im-wire 5 im-token)
    (bufset-u8 im-wire 6 im-want-f) (bufset-u8 im-wire 7 im-want-u)
})
(defun im-command (b) {
    (var action (bufget-u8 b 2)) (var key (list ms-session (bufget-u8 b 7) action))
    (if (and (= (bufget-u16 b 3) ms-session) (not-eq key im-last)) {
        (def im-last key)
        (if (and (im-safe) (im-fresh) (!= im-status 2)
                 (or (= action 10) (and (<= (bufget-u8 b 5) 5) (<= (bufget-u8 b 6) 5)
                     (!= (/ (bufget-u8 b 5) 2) (/ (bufget-u8 b 6) 2))))) {
            (def im-local-error 0) (def im-want-f (bufget-u8 b 5)) (def im-want-u (bufget-u8 b 6))
            (im-begin-request (if (= action 8) 1 2))
        } { (def im-local-error 5) (def im-status 5) (def im-done (bufget-u8 b 7)) (setvar 'ms-stage 20) (setvar 'ms-error 5) })
    })
})
(defun im-rx (id b) (if (and (= id (+ 0x5D0 (setup-imu-offset))) (= (buflen b) 8)
    (= (bufget-u8 b 0) 0x49) (>= im-request 0) (= (bufget-u8 b 2) im-token)
    (< (secs-since im-begin) 1.2) (<= (bufget-u8 b 3) 6)) {
    (var part (bufget-u8 b 1))
    (if (and (= part 0x80) (= (bufget-u8 b 7) 1)
        (<= (bufget-u8 b 4) 5) (<= (bufget-u8 b 5) 5)) {
        (def im-f (bufget-u8 b 4)) (def im-u (bufget-u8 b 5))
        (def im-flags (bufget-u8 b 6)) (def im-status (bufget-u8 b 3))
        (def im-mask (bitwise-or im-mask 1))
    })
    (if (and (= part 0x81) (<= (abs (bufget-i16 b 4)) 18000) (<= (abs (bufget-i16 b 6)) 18000)) {
        (def im-pitch (/ (to-float (bufget-i16 b 4)) 100.0))
        (def im-roll (/ (to-float (bufget-i16 b 6)) 100.0))
        (def im-mask (bitwise-or im-mask 2))
    })
    (if (= im-mask 3) { (if (> im-request 0) (def im-done (ix im-last 1))) (def im-t (systime)) (def im-request -1) })
}))
(defun im-step () (if (= ms-kind 4) {
    (if (or ms-lock (< (secs-since im-view-t) 2.0)) {
        (if (and (< im-request 0) (> (secs-since im-send-t) 0.25)) (im-begin-request 0))
        (if (and (>= im-request 0) (> (secs-since im-send-t) 0.25)) {
            (if (or (> (secs-since im-begin) 1.2) (and (> im-request 0) (not (im-safe))))
                { (def im-request -1) (def im-t 0) }
                { (def im-send-t (systime)) (can-send-sid (+ 0x5C0 (setup-imu-offset)) im-wire) })
        })
    })
    (if (and (>= ms-stage 16) (= ms-stop 0)) {
        (setvar 'ms-values (list im-pitch im-roll (to-float im-f) (to-float im-u)))
        (if (im-fresh) {
            (setvar 'ms-stage (cond ((> im-local-error 0) 20) ((= im-status 1) 17) ((= im-status 2) 18) ((= im-status 3) 19) ((>= im-status 4) 20) (t 16)))
            (setvar 'ms-error (if (> im-local-error 0) im-local-error (if (>= im-status 4) im-status im-flags)))
        } { (setvar 'ms-stage 21) (setvar 'ms-error 0) })
    })
}))
(defun im-init () {
(def im-wire (bufcreate 8))
})
@const-end
