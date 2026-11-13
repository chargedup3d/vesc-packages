@const-start
(def hd-running nil) (def hd-stop 0) (def hd-beat 0) (def hd-start 0)
(def hd-fault 0) (def hd-table nil) (def hd-amps 2)
(def hc-lock nil) (def hc-status 0) (def hc-session 0) (def hc-seq 0)
(def hc-raw 0) (def hc-seen 0) (def hc-states 0) (def hc-gaps 0)
(def hc-jumps 0) (def hc-n 0) (def hc-prev -1) (def hc-last 0) (def hc-start 0)
(def hc-send-t 0) (def hc-guard-t 0) (def hc-count nil) (def hc-payload nil) (def hc-tx nil)
(defun hc-neutral () (and (= (conf-get 'app-to-use) 3)
(<= (conf-get 'l-current-max-scale) 0.00001)
(<= (conf-get 'l-watt-max) 0.0)))
(defun hc-safe-start () (and (hc-neutral) (= whl-armed 0)
(< (abs (get-rpm)) 50) (< (abs (get-current)) 0.2)))
(defun hc-hold () {
(setvar 'whl-armed 0) (setvar 'whl-out 0.0)
(app-disable-output -1) (if (not hd-running) (set-current 0.0))
})
(defun hc-command (data) {
(var action (bufget-u8 data 2)) (var session (bufget-u16 data 3))
(cond
((and (= action 1) (not hd-running) (not ms-lock) (!= session hc-session)) {
(if (hc-safe-start) {
(setvar 'hc-lock t) (hc-hold)
(atomic {
(setvar 'hc-session session) (setvar 'hc-status 1)
(setvar 'hc-raw 0) (setvar 'hc-seen 0) (setvar 'hc-states 0)
(setvar 'hc-gaps 0) (setvar 'hc-jumps 0) (setvar 'hc-prev -1)
(setvar 'hc-n 0) (setvar 'hc-start (systime)) (setvar 'hc-last (systime))
(looprange i 0 3 (bufset-u16 hc-count (* i 2) 0))
(if (!= (conf-get 'm-sensor-port-mode) 0) (setvar 'hc-status 3))
})
} (if (not hc-lock) {
(setvar 'hc-session session) (setvar 'hc-status 4)
}))
})
((and (= action 2) (not hd-running) (not ms-lock) (!= session hc-session)) (hd-begin session (bufget-u8 data 5)))
((and (= action 3) (= session hc-session) hd-running) (setvar 'hd-beat (systime)))
((and (= action 0) (= session hc-session) hd-running) (hd-cancel 9))
((and (= action 0) (= session hc-session)) {
(if (not hc-lock) (setvar 'hc-status 0)
(if (hc-neutral) {
(setvar 'whl-armed 0) (setvar 'whl-out 0.0)
(set-current 0.0) (if (> hd-stop 0) (set-kill-sw 0))
(setvar 'hd-stop 0) (app-disable-output 0)
(setvar 'hc-lock nil) (setvar 'hc-status 0)
} (setvar 'hc-status 5)))
})
)
})
(defun hd-cancel (reason) {
(if (= hd-stop 0) (setvar 'hd-stop reason))
(set-kill-sw 1) (setvar 'hc-status hd-stop)
})
(defun hd-guard () (if hd-running {
(cond
((> hd-stop 0) (set-kill-sw 1))
((> (secs-since hd-start) 16.0) (hd-cancel 11))
((> (secs-since hd-beat) 1.2) (hd-cancel 10))
((not (hc-neutral)) (hd-cancel 11))
((!= (get-fault) 0) (hd-cancel 11))
)
}))
(defun hd-worker () {
(var result (trap (conf-detect-hall (to-float hd-amps))))
(atomic {
(setvar 'hd-running nil)
(if (> hd-stop 0) (setvar 'hc-status hd-stop)
(if (and (eq (car result) 'exit-ok) (eq (type-of (ix result 1)) 'type-array)
(= (buflen (ix result 1)) 8)) {
(bufcpy hd-table 0 (ix result 1) 0 8) (setvar 'hc-status 7)
} {
(setvar 'hc-status 8)
(if (and (eq (car result) 'exit-ok) (number? (ix result 1)))
(setvar 'hd-fault (ix result 1)))
}))
})
(hc-hold)
})
(defun hd-begin (session requested) {
(var current (if (= requested 0) 2 requested))
(if (and (or (= current 2) (= current 5)) (hc-safe-start) (= (conf-get 'm-sensor-port-mode) 0)
(= (conf-get 'motor-type) 2) (>= (conf-get 'l-current-max) current)
(<= (conf-get 'l-current-min) (- current)) (= (get-fault) 0) (= hd-stop 0)) {
(setvar 'hc-lock t) (hc-hold)
(atomic {
(setvar 'hd-amps current)
(setvar 'hc-session session) (setvar 'hc-status 6)
(setvar 'hc-raw 0) (setvar 'hc-seen 0) (setvar 'hc-states 0)
(setvar 'hc-gaps 0) (setvar 'hc-jumps 0) (setvar 'hc-prev -1) (setvar 'hc-n 0)
(setvar 'hc-start (systime)) (setvar 'hc-last (systime))
(looprange i 0 3 (bufset-u16 hc-count (* i 2) 0))
(looprange i 0 8 (bufset-u8 hd-table i 255))
(setvar 'hd-fault 0) (setvar 'hd-beat (systime)) (setvar 'hd-start (systime))
(setvar 'hd-running t)
})
(spawn hd-worker)
} (if (not hc-lock) { (setvar 'hc-session session) (setvar 'hc-status 4) }))
})
(defun hc-observe (raw gap) {
(if gap (setvar 'hc-gaps (if (< hc-gaps 127) (+ hc-gaps 1) 127)))
(setvar 'hc-raw raw)
(setvar 'hc-states (bitwise-or hc-states (shl 1 raw)))
(looprange i 0 3 {
(var high (!= (bitwise-and raw (shl 1 i)) 0))
(setvar 'hc-seen (bitwise-or hc-seen (shl 1 (+ (* i 2) (if high 1 0)))))
(if (and (>= hc-prev 0) (!= (bitwise-and raw (shl 1 i)) (bitwise-and hc-prev (shl 1 i)))) {
(var n (bufget-u16 hc-count (* i 2)))
(if (< n 65535) (bufset-u16 hc-count (* i 2) (+ n 1)) (setvar 'hc-gaps 127))
})
})
(if (>= hc-prev 0) {
(var changed (bitwise-xor raw hc-prev))
(if (and (!= changed 0) (!= changed 1) (!= changed 2) (!= changed 4))
(setvar 'hc-jumps (if (< hc-jumps 255) (+ hc-jumps 1) 255)))
})
(setvar 'hc-prev raw) (setvar 'hc-n (+ hc-n 1))
})
(defun hc-snapshot () (atomic {
(setvar 'hc-seq (mod (+ hc-seq 1) 256))
(bufset-u8 hc-payload 0 hc-status) (bufset-u8 hc-payload 1 hc-raw)
(bufset-u8 hc-payload 2 hc-seen)
(bufset-u16 hc-payload 3 (bufget-u16 hc-count 0)) (bufset-u8 hc-payload 5 hc-gaps)
(bufset-u16 hc-payload 6 (bufget-u16 hc-count 2)) (bufset-u8 hc-payload 8 hc-states)
(bufset-u16 hc-payload 9 (bufget-u16 hc-count 4)) (bufset-u8 hc-payload 11 hc-jumps)
(bufcpy hc-payload 12 hd-table 0 8)
(bufset-u16 hc-payload 20 (if (> hd-start 0) (to-i (clamp (* (secs-since hd-start) 1000.0) 0 65535)) 0))
(bufset-u8 hc-payload 22 hd-fault) (bufset-u8 hc-payload 23 (if hd-running 1 0))
(bufset-u8 hc-tx 0 0x57) (bufset-u8 hc-tx 2 hc-seq) (bufset-u16 hc-tx 3 hc-session)
}))
(defun hc-publish () {
(hc-snapshot)
(looprange i 0 8 {
(bufset-u8 hc-tx 1 (+ 0x90 i)) (bufcpy hc-tx 5 hc-payload (* i 3) 3)
(can-send-sid (+ whl-sid-rsp whl-canid) hc-tx)
})
})
(defun hc-step () {
(if hc-lock {
(if (> (secs-since hc-guard-t) 0.1) {
(setvar 'hc-guard-t (systime))
(if (and (not hd-running) (not (hc-neutral))) (setvar 'hc-status 5))
(if (!= (conf-get 'm-sensor-port-mode) 0) (setvar 'hc-status 3))
})
(if (and (= hc-status 1) (> (secs-since hc-start) 300.0)) (setvar 'hc-status 2))
(if (or (= hc-status 1) (= hc-status 6)) {
(var h (raw-hall 1 0))
(var raw (+ (ix h 0) (* 2 (ix h 1)) (* 4 (ix h 2))))
(atomic (hc-observe raw (> (secs-since hc-last) 0.02)))
(setvar 'hc-last (systime))
})
})
(if (> (secs-since hc-send-t) (if hc-lock 0.1 1.0)) {
(setvar 'hc-send-t (systime)) (hc-publish)
})
})
(defun hc-loop () (loopwhile t { (hc-step) (sleep (if (or (= hc-status 1) (= hc-status 6)) 0.002 0.02)) }))
(defun hc-init () {
(setvar 'hc-count (bufcreate 6)) (setvar 'hc-payload (bufcreate 24)) (setvar 'hc-tx (bufcreate 8))
(setvar 'hd-table (bufcreate 8))
(looprange i 0 8 (bufset-u8 hd-table i 255))
})
@const-end
