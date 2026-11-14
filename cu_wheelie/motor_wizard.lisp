; VESC Motor Wizard presets and native measurements, staged so cancellation
; never starts another measurement. Stock inductance measurement may finish
; its short internal pulse sequence before returning; keep the hold until then.
@const-start
(def mw-result -1)
(def mw-last-error 0) (def mw-last-transaction 0)
(defun mw-min (a b) (if (< a b) a b))
(defun mw-max (a b) (if (> a b) a b))
(def mw-profiles '((20.0 1400.0 4000.0) (50.0 1400.0 4000.0)
    (120.0 700.0 4000.0) (400.0 700.0 4000.0) (50.0 1400.0 4000.0)
    (140.0 1400.0 4000.0) (400.0 1000.0 4000.0) (150.0 300.0 2000.0)
    (110.0 1400.0 4000.0)))
(defun mw-idle () (and (< (abs (get-rpm)) 50) (< (abs (get-current)) 0.2)))
(defun mw-settle (check-link) {
    ; Hall detection releases PWM before its filtered current has settled.
    ; Keep the reservation until idle is observed, including on rollback.
    (set-current 0.0)
    (var polls 0)
    (loopwhile (and (< polls 60) (not (mw-idle))) {
        (sleep 0.05) (setq polls (+ polls 1))
        (if check-link (mw-check))
    })
    (mw-idle)
})
(defun mw-restore () {
    ; Never release the reservation while a native measurement can write.
    (if mw-active {
        (var restored (if (mw-settle nil) (ext-mw-transaction 3) -2))
        (setq mw-last-transaction restored)
        (if (= restored 1) (setq mw-active nil))
    })
    (if (not mw-active) {
        (if ms-original {
            (conf-set 'l-current-max-scale (ix ms-original 0))
            (conf-set 'l-watt-max (ix ms-original 1))
            (setq ms-original nil)
        })
        (setq base-last nil)
    })
})
(defun mw-require (valid error) (if (not valid) {
    (setq mw-last-error error)
    (if (= ms-stop 0) { (setq ms-error error) (ms-cancel 11) })
    (exit-error 'wizard-stopped)
}))
(defun mw-check () {
    (if (or (> (secs-since ms-ack) 0.6) (> (secs-since ms-beat) 0.6)) (ms-cancel 10))
    (mw-require (and (= ms-stop 0) (= (get-fault) 0) ms-lock) 11)
})
(defun mw-native (call) {
    (mw-check)
    (var result (ms-native call))
    (mw-check)
    result
})
(defun mw-run () {
    (mw-require (and base-ready ms-lock) 11) (mw-check)
    ; Capture the owner's limits, not the transient Neutral/kids profile.
    (conf-set 'l-current-min-scale (ix base-limits 0))
    (conf-set 'l-current-max-scale (ix base-limits 1))
    (conf-set 'l-min-erpm (* (base-speed-factor) (ix base-limits 2)))
    (conf-set 'l-max-erpm (* (base-speed-factor) (ix base-limits 3)))
    (conf-set 'l-watt-min (ix base-limits 4))
    (conf-set 'l-watt-max (ix base-limits 5))
    (mw-require (= (ext-mw-transaction 1) 1) 5)
    (setq mw-active t)
    (var p (ix mw-profiles (- ms-amps 101)))
    (var freq (ext-mw-transaction 4))
    (var min-i (/ (to-float (ext-mw-transaction 5)) 1000000.0))
    (mw-require (and (> freq 0) (> min-i 0)) 11)
    (var old-freq (conf-get 'foc-f-zv))
    (var old-sensor (conf-get 'foc-sensor-mode))
    (var old-port (conf-get 'm-sensor-port-mode))
    ; Encoder autoconfiguration needs a separate verified flow. Do not silently
    ; replace an existing encoder with a sensorless tune.
    (mw-require (and (!= old-sensor 1) (= old-port 0)) 13)
    (conf-set 'motor-type 2) (conf-set 'foc-sensor-mode 0)
    (conf-set 'l-current-max-scale 1.0) (conf-set 'l-current-min-scale 1.0)
    (conf-set 'foc-f-zv 10000.0)
    (conf-set 'foc-current-kp 0.0005) (conf-set 'foc-current-ki 1.0)
    (setq ms-stage 2)
    (var current (mw-max (/ mw-amp-cap 50.0) (* min-i 1.1)))
    (var last-i 0.0) (var r 0.0) (var enough nil)
    ; Same copper-loss target as measure_r_l_imax in the VESC Motor Wizard.
    ; Each public resistance primitive releases output, allowing cancellation
    ; between probes instead of running the monolithic detect-all command.
    (loopwhile (and (< current mw-amp-cap) (not enough)) {
        (setq r (mw-native (list 'conf-measure-res current 5)))
        (mw-require (ms-finite-positive r 10.0) 1)
        (setq last-i current)
        (setq enough (>= (* current current r 1.5) (/ (ix p 0) 5.0)))
        (setq current (* current 1.5))
    })
    (mw-require (> last-i 0) 1)
    (setq r (mw-native (list 'conf-measure-res last-i 100)))
    (mw-require (ms-finite-positive r 10.0) 1)
    (conf-set 'foc-motor-r (* r 1000.0))
    (setq ms-values (list (* r 1000.0) 0.0 0.0 0.0))
    (setq ms-stage 3)
    (var ind (mw-native (list 'conf-measure-ind last-i 100)))
    (mw-require (and (eq (type-of ind) 'type-list) (= (length ind) 3)
        (ms-finite-positive (ix ind 0) 10000.0)
        (number? (ix ind 1)) (< (abs (ix ind 1)) (* (ix ind 0) 2.0))
        (ms-finite-positive (ix ind 2) mw-amp-cap)) 2)
    (var limit (mw-min mw-amp-cap (sqrt (/ (ix p 0) (* r 1.5)))))
    (setq ms-values (list (* r 1000.0) (ix ind 0) 0.0 limit))
    (conf-set 'foc-f-zv (to-float freq))
    (setq ms-stage 4)
    (var flux (mw-native (list 'conf-detect-lambda-enc (/ limit 2.5) 0.3 1800.0 (* r 1000.0) (ix ind 0))))
    (mw-require (and (eq (type-of flux) 'type-list) (= (length flux) 6)) 3)
    (var linkage (if (> (ix flux 2) 60) (ix flux 1) (ix flux 0)))
    (mw-require (ms-finite-positive linkage 1.0) 3)
    ; Wait for coast-down before Hall measurement. The guard remains active.
    (var settle (systime))
    (loopwhile (and (< (secs-since settle) 15.0) (>= (abs (get-rpm)) 50)) {
        (sleep 0.05) (mw-check)
    })
    (mw-require (< (abs (get-rpm)) 50) 11)
    (conf-set 'foc-f-zv old-freq)
    (conf-set 'foc-motor-l (ix ind 0))
    (conf-set 'foc-motor-ld-lq-diff (ix ind 1))
    (conf-set 'foc-motor-flux-linkage (* linkage 1000.0))
    (conf-set 'foc-openloop-rpm (ix p 1)) (conf-set 'foc-sl-erpm (ix p 2))
    (setq ms-values (list (* r 1000.0) (ix ind 0) (* linkage 1000.0) limit))
    (setq ms-stage 25)
    (var hall (mw-native (list 'conf-detect-hall (/ limit 3.0))))
    (if hall {
        (mw-require (and (eq (type-of hall) 'type-array) (= (buflen hall) 8)) 14)
        (var hall-keys '(foc-hall-t0 foc-hall-t1 foc-hall-t2 foc-hall-t3 foc-hall-t4 foc-hall-t5 foc-hall-t6 foc-hall-t7))
        (looprange i 0 8 (conf-set (ix hall-keys i) (bufget-u8 hall i)))
        (conf-set 'foc-sensor-mode 2)
    } {
        ; An existing Hall setup must not silently turn sensorless on a failed
        ; Hall check. A new sensorless motor may legitimately have no table.
        (mw-require (!= old-sensor 2) 14)
        (conf-set 'foc-sensor-mode 0)
    })
    (mw-check)
    ; Upstream 1000 us current-loop gains. Lisp observer gain uses /1e6 units.
    (var motor-temp (get-temp-mot))
    (if (and (number? motor-temp) (> motor-temp -10.0) (< motor-temp 150.0))
        (conf-set 'foc-temp-comp-base-temp motor-temp))
    (conf-set 'foc-current-kp (* (ix ind 0) 0.001))
    (conf-set 'foc-current-ki (* r 1000.0))
    (conf-set 'foc-observer-gain (/ 0.001 (* linkage linkage)))
    (conf-set 'l-current-max limit)
    (conf-set 'l-current-min (- (mw-min (abs (conf-get 'l-current-min)) limit)))
    (mw-require (mw-settle t) 11) (mw-check)
    (setq mw-last-transaction (ext-mw-transaction 2))
    (mw-require (= mw-last-transaction 1) 12)
    ; Retain the backup through the asynchronous save so a late STOP or lost
    ; session restores the previous tune before releasing the reservation.
    (mw-check)
    (mw-require (= (ext-mw-transaction 6) 1) 12)
    (setq mw-active nil) (setq mw-result 1) (setq ms-stage 5)
})
(defun mw-worker () {
    (setq mw-result -1)
    (setq mw-last-error 0) (setq mw-last-transaction 0)
    (var result (trap (mw-run)))
    (if (and (= ms-stop 0) (eq (car result) 'exit-error)) {
        (setq ms-stage 11) (setq ms-error 4)
    })
    (var cleanup (trap (mw-restore)))
    (if (or (eq (car cleanup) 'exit-error) mw-active ms-original) {
        (setq ms-error 5) (ms-cancel 11)
    })
    (setq ms-running nil)
    (if (> ms-stop 0) (setq ms-stage ms-stop))
    (ms-hold)
})
@const-end
