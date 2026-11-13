@const-start
(def ms-lock nil) (def ms-running nil) (def ms-stage 0) (def ms-kind 0)
(def ms-session 0) (def ms-seq 0) (def ms-amps 5) (def ms-stop 0)
(def ms-beat 0) (def ms-ack 0) (def ms-start 0) (def ms-phase 0) (def ms-peer -1)
(def ms-error 0) (def ms-values '(0.0 0.0 0.0 0.0))
(def ms-adc '(0.0 0.0)) (def ms-rest 0.0) (def ms-full 0.0)
(def ms-n 0) (def ms-pos 0) (def ms-ring nil) (def ms-payload nil) (def ms-tx nil)
(def ms-send-t 0) (def ms-original nil) (def ms-other-rest 0.0)
(def ms-save-native-ok nil)
(def ms-limit-keys '(l-current-max-scale l-watt-max foc-current-kp foc-current-ki foc-motor-r))
(defun ms-safe () (and (= (conf-get 'app-to-use) 3) (= whl-armed 0)
(< (abs (get-rpm)) 50) (< (abs (get-current)) 0.2) (= (get-fault) 0)
(<= (conf-get 'l-current-max-scale) 0.00001) (<= (conf-get 'l-watt-max) 0.0)))
(defun ms-hold () {
(setvar 'whl-armed 0) (setvar 'whl-out 0.0) (app-disable-output -1)
(if (not ms-running) (set-current 0.0))
})
(defun ms-cancel (reason) {
(if (= ms-stop 0) (setvar 'ms-stop reason))
(if ms-running (set-kill-sw 1))
(setvar 'ms-stage ms-stop)
})
(defun ms-finite-positive (v ceiling) (and (number? v) (> v 0.0) (< v ceiling)))
(defun ms-guard () (if ms-lock {
(if ms-running {
(cond ((> ms-stop 0) (set-kill-sw 1))
((or (> (secs-since ms-beat) 1.2) (> (secs-since ms-ack) 1.2)) (ms-cancel 10))
((or (> (secs-since ms-start) 75.0) (> (abs (get-rpm)) 6000)
(> (abs (get-current)) (+ ms-amps 3.0)) (!= (get-fault) 0)
(!= (conf-get 'app-to-use) 3)) (ms-cancel 11)))
} (if (or (and (or (>= ms-kind 4) (= ms-stage 1) (= ms-stage 6) (= ms-stage 7))
(> (secs-since ms-beat) 2.0))
(and (= ms-stage 1) (> (secs-since ms-start) 10.0))) (ms-cancel 10)))
}))
(defun ms-native (call) (if (= ms-stop 0) {
(var r (trap (eval call)))
(if (and (= ms-stop 0) (eq (car r) 'exit-ok)) (ix r 1) nil)
} nil))
(defun ms-restore () (if ms-original {
(looprange i 0 (length ms-limit-keys) (conf-set (ix ms-limit-keys i) (ix ms-original i)))
(setvar 'ms-original nil)
}))
(defun ms-measure () {
(if (and (= ms-stop 0) (< (secs-since ms-ack) 0.6) (< (secs-since ms-beat) 0.6)) {
(conf-set 'l-current-max-scale (/ (to-float ms-amps) (conf-get 'l-current-max)))
(conf-set 'l-watt-max 500.0)
(conf-set 'foc-current-kp 0.001) (conf-set 'foc-current-ki 1.0)
} (ms-cancel 10))
(setvar 'ms-stage 2) (setvar 'ms-phase (systime))
(var r (ms-native (list 'conf-measure-res (to-float ms-amps) 200)))
(if (ms-finite-positive r 10.0) {
(setvar 'ms-values (list (* r 1000.0) 0.0 0.0 0.0))
(conf-set 'foc-motor-r (* r 1000.0))
(setvar 'ms-stage 3) (setvar 'ms-phase (systime))
(var ind (ms-native (list 'conf-measure-ind (to-float ms-amps) 200)))
(if (and (eq (type-of ind) 'type-list) (= (length ind) 3)
(ms-finite-positive (ix ind 0) 10000.0)
(ms-finite-positive (ix ind 2) (+ ms-amps 3.0))) {
(setvar 'ms-values (list (* r 1000.0) (ix ind 0) 0.0 (ix ind 2)))
(if (and (= ms-stop 0) (< (secs-since ms-ack) 0.6) (< (secs-since ms-beat) 0.6)) {
(setvar 'ms-stage 4) (setvar 'ms-phase (systime))
(var flux (ms-native (list 'conf-detect-lambda-enc (to-float ms-amps) 0.15 800.0 (* r 1000.0) (ix ind 0))))
(if (and (eq (type-of flux) 'type-list) (= (length flux) 6)
(ms-finite-positive (ix flux 1) 1.0) (>= (ix flux 2) 500)) {
(setvar 'ms-values (list (* r 1000.0) (ix ind 0) (* (ix flux 1) 1000.0) (ix ind 2)))
(setvar 'ms-stage 5)
} (if (= ms-stop 0) { (setvar 'ms-stage 11) (setvar 'ms-error 3) }))
} (ms-cancel 10))
} (if (= ms-stop 0) { (setvar 'ms-stage 11) (setvar 'ms-error 2) }))
} (if (= ms-stop 0) { (setvar 'ms-stage 11) (setvar 'ms-error 1) }))
})
(defun ms-worker () {
(var result (trap (ms-measure)))
(if (and (= ms-stop 0) (eq (car result) 'exit-error)) {
(setvar 'ms-stage 11) (setvar 'ms-error 4)
})
(var cleanup (trap (ms-restore)))
(if (eq (car cleanup) 'exit-error) { (setvar 'ms-error 5) (ms-cancel 11) })
(setvar 'ms-running nil)
(if (> ms-stop 0) (setvar 'ms-stage ms-stop))
(ms-hold)
})
(defun ms-stable-channel (channel) {
(var lo 10.0) (var hi -10.0) (var sum 0.0) (var valid t)
(looprange i 0 16 {
(var v (bufget-f32 ms-ring (+ (* channel 64) (* i 4))))
(if (not (and (> v 0.05) (< v 3.25))) (setq valid nil))
(if (< v lo) (setq lo v)) (if (> v hi) (setq hi v)) (setq sum (+ sum v))
})
(if (and valid (>= ms-n 16) (> lo 0.05) (< hi 3.25) (< (- hi lo) 0.04)) (/ sum 16.0) nil)
})
(defun ms-stable () (ms-stable-channel (- ms-kind 2)))
(defun ms-save-adc () {
(var v (ms-stable)) (var other (ms-stable-channel (- 3 ms-kind)))
(cond
((not (and ms-lock (not ms-running) (= ms-stop 0) (ms-safe)
(< (secs-since ms-beat) 0.6) (< (secs-since ms-ack) 0.6)))
(setvar 'ms-error 7))
((not (and v other (< (abs (- v ms-rest)) 0.08)
(< (abs (- other ms-other-rest)) 0.08))) (setvar 'ms-error 6))
((not ms-save-native-ok) (setvar 'ms-error 8))
(t {
(setvar 'ms-stage 14) (setvar 'ms-error 0) (ms-hold)
(var saved (trap (ext-ms-adc-save (- ms-kind 1) ms-rest ms-full)))
(if (and (eq (car saved) 'exit-ok) (= (ix saved 1) 1))
(setvar 'ms-stage 13)
{ (setvar 'ms-stage 15) (setvar 'ms-error 9) })
(ms-hold)
})
)
})
(defun ms-command (b) {
(var action (bufget-u8 b 2)) (var session (bufget-u16 b 3))
(cond
((and (= action 11) (not ms-lock) (not hc-lock)) {
(setvar 'ms-error 0) (setvar 'ms-kind 5) (setvar 'ms-stage 22) (setvar 'ms-stop 0) (bs-preview)
})
((and (= action 7) (not ms-lock) (not hc-lock)) {
(if (!= ms-kind 4) { (setvar 'ms-kind 4) (setvar 'ms-stage 21) (def im-request -1) })
(setvar 'ms-stop 0) (def im-view-t (systime))
})
((and (or (= action 8) (= action 10)) (= ms-kind 4)) (im-command b))
((and (= action 1) (not ms-lock) (not hc-lock) (!= session ms-session)) {
(var kind (bufget-u8 b 5)) (var amps (bufget-u8 b 6))
(setvar 'ms-session session)
(if (and (ms-safe) (>= kind 1) (<= kind 5)
(or (= kind 5) (and (or (= amps 5) (= amps 10))
(>= (conf-get 'l-current-max) amps)
(<= (conf-get 'l-current-min) (- amps))))) {
(if (= kind 4) (def im-local-error 0))
(if (= kind 5) (setvar 'bs-token -1))
(setvar 'ms-kind kind) (setvar 'ms-amps amps) (setvar 'ms-lock t)
(setvar 'ms-stop 0) (setvar 'ms-error 0) (setvar 'ms-stage 1)
(setvar 'ms-values '(0.0 0.0 0.0 0.0)) (setvar 'ms-n 0) (setvar 'ms-pos 0)
(setvar 'ms-beat (systime)) (setvar 'ms-start (systime)) (setvar 'ms-ack 0)
(setvar 'ms-peer -1) (ms-hold)
} { (setvar 'ms-stage 12) (setvar 'ms-error 1) })
})
((= session ms-session) (cond
((and (= action 5) ms-lock) (setvar 'ms-beat (systime)))
((and (= action 9) ms-lock (or (= ms-peer -1) (= ms-peer (bufget-u8 b 5)))) {
(setvar 'ms-peer (bufget-u8 b 5)) (setvar 'ms-ack (systime))
})
((and (= action 0) ms-lock) (ms-cancel 9))
((and (= action 4) (not ms-running) (or (!= ms-kind 4) (and (<= im-request 0) (or (!= im-status 2) (not (im-fresh)))))) {
(if (= ms-error 5) {
(var restored (trap (ms-restore)))
(if (and (eq (car restored) 'exit-ok) (not ms-original)) (setvar 'ms-error 0))
})
(if (or (not ms-lock) (and (ms-safe) (!= ms-error 5))) {
(if ms-lock { (set-current 0.0) (if (> ms-stop 0) (set-kill-sw 0)) (app-disable-output 0) })
(setvar 'ms-stage 0) (setvar 'ms-lock nil) (setvar 'ms-stop 0)
(if (= ms-kind 4) { (setvar 'ms-kind 0) (def im-local-error 0) (def im-request -1) })
})
})
((and (= action 13) (= ms-kind 5)) (bs-save b))
((and (= action 6) (= ms-stage 8) (>= ms-kind 2) (<= ms-kind 3)) (ms-save-adc))
((and (= action 2) (= ms-stage 6)) {
(var v (ms-stable)) (var other (ms-stable-channel (- 3 ms-kind)))
(if (and v other) { (setvar 'ms-other-rest other) (setvar 'ms-rest v) (setvar 'ms-stage 7) (setvar 'ms-error 0)
(setvar 'ms-n 0) (setvar 'ms-values (list v v 0.0 0.0)) }
(setvar 'ms-error 2))
})
((and (= action 3) (= ms-stage 7)) {
(var v (ms-stable))
(if (and v (>= (abs (- v ms-rest)) 0.3)) {
(setvar 'ms-full v) (setvar 'ms-stage 8) (setvar 'ms-error 0)
(setvar 'ms-values (list ms-rest v (abs (- v ms-rest)) (if (< v ms-rest) 1.0 0.0)))
} (setvar 'ms-error 3))
})
))
)
})
(defun ms-publish () {
(atomic {
(setvar 'ms-seq (mod (+ ms-seq 1) 256))
(bufset-u8 ms-payload 0 ms-kind) (bufset-u8 ms-payload 1 ms-stage)
(bufset-u8 ms-payload 2 (+ (if ms-lock 1 0) (if ms-running 2 0)))
(bufset-u8 ms-payload 3 ms-error)
(looprange i 0 4 (bufset-f32 ms-payload (+ 4 (* i 4)) (ix ms-values i)))
(bufset-f32 ms-payload 20 (if (= ms-kind 5) (to-float (ix bs-caps 2)) (ix ms-adc 0)))
(bufset-f32 ms-payload 24 (if (= ms-kind 5) (to-float (ix bs-caps 0)) (ix ms-adc 1)))
(bufset-u16 ms-payload 28 (cond ((= ms-kind 5) (if (< bs-token 0) 65535 bs-token)) ((= ms-kind 4) (if (< im-done 0) 65535 im-done)) (t (to-i (clamp (secs-since ms-start) 0 65535)))))
(bufset-u8 ms-payload 30 ms-amps) (bufset-u8 ms-payload 31 (get-fault))
(bufset-f32 ms-payload 32 (get-rpm))
(bufset-u8 ms-tx 0 0x57) (bufset-u8 ms-tx 2 ms-seq) (bufset-u16 ms-tx 3 ms-session)
})
(looprange i 0 12 {
(bufset-u8 ms-tx 1 (+ 0xA0 i)) (bufcpy ms-tx 5 ms-payload (* i 3) 3)
(can-send-sid (+ whl-sid-rsp whl-canid) ms-tx)
(sleep 0.010)
})
})
(defun ms-step () {
(im-step)
(setvar 'ms-adc (list (get-adc 0) (get-adc 1)))
(atomic (if (and ms-lock (= ms-stage 1) (> ms-ack 0) (< (secs-since ms-ack) 0.6)
(< (secs-since ms-beat) 0.6)) {
(if (= ms-kind 1) {
(setvar 'ms-original (map conf-get ms-limit-keys))
(setvar 'ms-running t) (setvar 'ms-stage 2) (spawn ms-worker)
} (if (= ms-kind 5) { (bs-preview) (setvar 'ms-stage 22) }
(setvar 'ms-stage (if (= ms-kind 4) 16 6))))
}))
(if (and ms-lock (or (= ms-stage 6) (= ms-stage 7) (= ms-stage 8))) {
(looprange channel 0 2 (bufset-f32 ms-ring (+ (* channel 64) (* ms-pos 4)) (ix ms-adc channel)))
(setvar 'ms-pos (mod (+ ms-pos 1) 16)) (setvar 'ms-n (if (< ms-n 16) (+ ms-n 1) 16))
})
(if (> (secs-since ms-send-t) (if ms-lock 0.2 1.0)) {
(setvar 'ms-send-t (systime)) (ms-publish)
})
})
(defun ms-loop () (loopwhile t { (ms-step) (sleep 0.02) }))
(defun ms-init () {
(setvar 'ms-ring (bufcreate 128)) (setvar 'ms-payload (bufcreate 36)) (setvar 'ms-tx (bufcreate 8))
})
@const-end
