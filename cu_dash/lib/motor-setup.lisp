; On-screen native motor measurements and separate throttle / brake capture.
@const-start
(def setup-stop-request nil)
; View 0 hub, 1 start confirmation, 2 session, 3 Hall, 4 ADC save review.
(def setup-view 0) (def setup-choice 1) (def setup-amps 103)
(def setup-motors '("Mini outrunner ~75 g" "Small outrunner ~200 g"
    "Medium outrunner ~750 g" "Large outrunner ~2000 g" "Small inrunner ~200 g"
    "Medium inrunner ~750 g" "Large inrunner ~2000 g" "Direct-drive hub ~6 kg"
    "Small EDF inrunner ~200 g"))
(def setup-t 0) (def setup-session 0) (def setup-seq -1) (def setup-kind 0)
(def setup-stage 0) (def setup-flags 0) (def setup-error 0) (def setup-values '(0.0 0.0 0.0 0.0))
(def setup-adc '(0.0 0.0)) (def setup-elapsed 0) (def setup-current 0) (def setup-fault 0)
(def setup-owned nil) (def setup-pending -1) (def setup-want 0) (def setup-request 0)
(def setup-send-t 0) (def setup-beat-t 0) (def setup-note 0)
(def setup-via 0) (def setup-owner nil) (def setup-full nil) (def setup-query-t 0)
(defun setup-context () (cond
    ((and setup-owner (= (ix setup-owner 0) 2) cfg-vb-en vb-linked
          (> vb-last 0) (< (secs-since vb-last) 2.0)) (list 2 cfg-vb-mac vb-fwd))
    ((link-carries) (list 1 link-mac cfg-esc-id))
    ((and cfg-vb-en vb-linked (> vb-last 0) (< (secs-since vb-last) 2.0))
        (list 2 cfg-vb-mac vb-fwd))
    (t nil)))
(defun setup-transport () {
    (var ctx (setup-context))
    (if (and ctx (or (not setup-owner) (eq ctx setup-owner))) (ix ctx 0) 0)
})
(defun setup-live () (and (> setup-t 0) (< (secs-since setup-t) 1.5)
    (= setup-via (setup-transport)) (> setup-via 0)))
(defun setup-running () (!= (bitwise-and setup-flags 2) 0))
(defun setup-locked () (or setup-owned (>= setup-pending 0)
    (and (setup-live) (!= (bitwise-and setup-flags 1) 0))))
(defun setup-floats-valid (b base) {
    (var valid t) (loopforeach offset '(9 13 17 21 25 29 37) (if (= (bitwise-and (bufget-u32 b (+ base offset)) 0x7F800000) 0x7F800000) (setq valid nil))) valid
})
(defun setup-receive (b base via) (if (and (and (= via (setup-transport)) (>= (buflen b) (+ base 41))) (= (bufget-u8 b (+ base 0)) 0x53)
    (or (= (bufget-u8 b (+ base 1)) 1) (= (bufget-u8 b (+ base 1)) 2)) (<= (bufget-u8 b (+ base 5)) 5) (<= (bufget-u8 b (+ base 6)) 25) (<= (bufget-u8 b (+ base 7)) 3) (setup-floats-valid b base)) (atomic {
    (var session (bufget-u16 b (+ base 2))) (var seq (bufget-u8 b (+ base 4)))
    (if (or (!= via setup-via) (!= seq setup-seq) (!= session setup-session)) {
        (def setup-full (or (= via 1) (= (bufget-u8 b (+ base 1)) 2)))
        (def setup-via via) (def setup-t (systime)) (def setup-session session) (def setup-seq seq)
        (def setup-kind (bufget-u8 b (+ base 5))) (def setup-stage (bufget-u8 b (+ base 6)))
        (def setup-flags (bufget-u8 b (+ base 7))) (def setup-error (bufget-u8 b (+ base 8)))
        (def setup-values (list (bufget-f32 b (+ base 9)) (bufget-f32 b (+ base 13)) (bufget-f32 b (+ base 17)) (bufget-f32 b (+ base 21))))
        (def setup-adc (list (bufget-f32 b (+ base 25)) (bufget-f32 b (+ base 29))))
        (def setup-elapsed (bufget-u16 b (+ base 33))) (def setup-current (bufget-u8 b (+ base 35)))
        (def setup-fault (bufget-u8 b (+ base 36)))
        (if (!= (bitwise-and setup-flags 1) 0) {
            (if (not setup-owned) { (def setup-owner (setup-context)) (def setup-want session) })
            (def setup-owned t)
        })
        (if (= session setup-want) {
            (if (and (or (= setup-pending 8) (= setup-pending 10)) (= setup-elapsed imu-token)) {
                (def setup-pending -1) (def imu-edit nil) (def setup-view 5)
            })
            (if (and (= setup-pending 1) (!= setup-stage 0)) (def setup-pending -1))
            (if (and (= setup-pending 2) (!= setup-stage 6)) (def setup-pending -1))
            (if (and (= setup-pending 3) (!= setup-stage 7)) (def setup-pending -1))
            (if (and (= setup-pending 0) setup-stop-request (>= setup-stage 9) (<= setup-stage 11)) (def setup-pending -1))
            (if (and (= setup-pending 6) (or (= setup-stage 13) (= setup-stage 15) (> setup-error 0))) {
                (def setup-pending -1) (def setup-view 2)
            })
            (if (and (= setup-pending 4) (= setup-stage 0)) {
                (def setup-pending -1) (def setup-owned nil) (def setup-owner nil) (def setup-view 0) (def setup-note 0)
            })
        })
    })
})))
(defun setup-from-link (b) (setup-receive b 144 1))
(defun setup-from-ble (b) (if (= (buflen b) 42)
    (setup-receive b 1 2)))
(defun setup-command (action) {
    (var b (bufcreate 9)) (bufset-u8 b 0 0xC7) (bufset-u8 b 1 0x57) (bufset-u8 b 2 0x31)
    (bufset-u8 b 3 action) (bufset-u16 b 4 setup-want)
    (bufset-u8 b 6 (if (= action 9) 255 (if (= action 8) imu-f setup-choice)))
    (bufset-u8 b 7 (if (= action 8) imu-u setup-amps)) (bufset-u8 b 8 imu-token)
    (if (= action 13) {
        (bufset-u8 b 6 basic-token) (bufset-u16 b 7 basic-value-want)
    })
    (cond ((= (setup-transport) 1) (link-send b))
          ((= (setup-transport) 2) { (bufset-u8 b 0 36) (vb-send b) }))
    (free b)
})
(defun setup-start () (if (or (and (= setup-choice 1) (>= setup-amps 101) (< setup-current 100))
    (and (= (setup-transport) 2) (!= setup-choice 5)
    (not (and (setup-live) setup-full))))
    (def setup-note 3) (setup-start-inner)))
(defun setup-start-inner () (if (and (setup-live) (not (setup-locked)) (not (hall-locked))
    (< (abs d-speed) 0.5) (not (whl-armed))) {
    (send-mode 0) (def setup-owner (setup-context)) (def setup-owned t) (def setup-pending 1) (def setup-view 2) (def setup-note 0)
    (def setup-want (+ 1 (mod (+ setup-session (to-i (* (secs-since 0) 100.0))) 65534)))
    (if (= setup-want setup-session) (def setup-want (mod (+ setup-want 1) 65536)))
    (def setup-request (systime)) (def setup-send-t (systime))
    (spawn (fn () {
        (var session setup-want) (sleep 0.8)
        (if (and (= setup-pending 1) (= setup-want session) (setup-live)) (setup-command 1))
    }))
} (def setup-note 1)))
(defun setup-action (action) (if (setup-live) {
    (if (and (= action 0) (not (setup-running))) (setq action 4))
    (if (= action 0) (def setup-stop-request (setup-running)))
    (def setup-want setup-session) (def setup-pending action) (def setup-request (systime))
    (def setup-send-t (systime)) (setup-command action)
} (def setup-note 2)))
(defun setup-tick () {
    (if (and (help-active) (or (setup-locked) (hall-locked))) (setup-back))
    (imu-tick) (basic-tick) (pm-tick)
    (if (and (= page (pg-setup)) (<= setup-view 2) (= (setup-transport) 2)
        (not (setup-locked)) (not (hall-locked)) (> (secs-since setup-query-t) 0.5)) {
        (def setup-query-t (systime)) (setup-command 14)
    })
    (if (and (setup-locked) (> (secs-since setup-beat-t) 0.2) (> (setup-transport) 0)) {
        (def setup-beat-t (systime))
        (if (and (= (setup-transport) 2) (setup-live) (= setup-session setup-want)
                 (!= (bitwise-and setup-flags 1) 0)) (setup-command 9))
        (setup-command 5)
    })
    (if (and (>= setup-pending 0) (> (secs-since setup-send-t) 0.5)) {
        (def setup-send-t (systime))
        (if (> (secs-since setup-request) 8.0) { (def setup-pending -1) (def setup-note 2) }
            (if (and (!= setup-pending 1) (setup-live)) (setup-command setup-pending)))
    })
})
(defun setup-loop () (loopwhile t { (setup-tick) (sleep 0.2) }))
(defun setup-title (kind) (cond ((= kind 1) "MOTOR WIZARD") ((= kind 2) "ADC1 THROTTLE") (t "ADC2 BRAKE / REGEN")))
(defun setup-message () (cond
    ((= setup-note 3) "Update ESC package for setup")
    ((= setup-error 10) "Not supported by this package")
    ((= setup-pending 1) "Entering Neutral and service hold")
    ((not (setup-live)) "No fresh data - check connection")
    ((= setup-note 1) "End Hall check and disarm first")
    ((= setup-note 2) "Request unconfirmed - check link")
    ((and (setup-running) (>= setup-stage 9) (<= setup-stage 11)) "Stopping - finishing measurement")
    ((= setup-stage 1) "Waiting for service hold")
    ((and (= setup-kind 1) (= setup-stage 25)) "Detecting Hall sensors")
    ((= setup-stage 2) "Measuring resistance")
    ((= setup-stage 3) "Measuring inductance")
    ((= setup-stage 4) "Measuring flux - motor spins")
    ((= setup-stage 5) (if (>= setup-current 101) "Tune saved - readback verified" "Measurements ready for review"))
    ((= setup-stage 6) (if (= setup-error 2) "Hold steady / check wiring" "Release both controls and hold"))
    ((= setup-stage 7) (if (= setup-error 3) "Need stable travel of 0.30 V" (if (= setup-kind 2) "Hold throttle fully open" "Hold brake fully applied")))
    ((and (= setup-stage 8) (= setup-error 6)) "Release both controls to save")
    ((and (= setup-stage 8) (= setup-error 7)) "Need fresh link and Neutral")
    ((and (= setup-stage 8) (= setup-error 8)) "Save unavailable on this firmware")
    ((= setup-stage 8) "Range ready - release and review")
    ((= setup-stage 13) "Saved - controller readback OK")
    ((= setup-stage 14) "Saving / keep controls released")
    ((= setup-stage 15) "Save unverified - check values")
    ((= setup-stage 9) "Stopped - END to leave setup")
    ((= setup-stage 10) "Link lost - output held off")
    ((and (= setup-stage 11) (= setup-error 5)) "Restore failed - output held off")
    ((= setup-stage 11) (if (>= setup-current 101) "Detect failed - backup restored" "Measurement failed - tuning kept"))
    ((= setup-stage 12) "Requires Neutral / UART-only app")
    (t "Select motor or input setup")))
(defun setup-button (x y w label color) {
    (rbox x y w 36 8 color)
    (txt-c (+ x (/ w 2)) (base-c font-ui (+ y 18)) 0xFFFFFF font-ui label)
})
; Navigation never sends a controller command or clears a service hold.
(defun setup-inside (x y bx by bw bh)
    (and (>= x bx) (< x (+ bx bw)) (>= y by) (< y (+ by bh))))
(defun setup-back () (cond
    ((setup-locked) (def setup-view (if (or (= setup-kind 5) (= setup-choice 5)) 8 (if (or (= setup-kind 4) (= setup-choice 4)) 5 2))))
    ((hall-locked) { (def setup-view 3) (def hall-confirm nil) })
    ((= setup-view 10) (help-back))
    ((and (= setup-view 3) hall-confirm) (def hall-confirm nil))
    (t { (def setup-view 0) (def setup-note 0) })
))
(defun setup-open (choice) (cond
((or (setup-locked) (hall-locked)) (setup-back))
((= choice 6) { (def setup-choice 5) (def setup-view 8) (def setup-note 0) (def basic-dirty nil) (def basic-mask 0) (def basic-queue nil) })
((and cfg-simple (= choice 5)) nil)
((= choice 5) { (def setup-choice 4) (def setup-view 5) (def setup-note 0) (def imu-edit nil) (imu-sync) })
((= choice 4) { (def setup-view 3) (def hall-confirm nil) (def hall-note 0) })
(t { (def setup-choice choice) (def setup-view 1) (def setup-note 0) })
))

(defun setup-heading (title) {
    (var held (or (setup-locked) (hall-locked)))
    (rbox 12 6 76 40 8 (if held 0x14181E 0x303640))
    (txt-c 50 (base-c font-ui 26) (if held 0x667080 0xFFFFFF) font-ui "BACK")
    (txt 100 (base-c font-ui 26) 0xFFFFFF font-ui title)
})
(defun setup-tile-rect (i) {
    (var w (/ (- fb-w 36) 2))
    (list (+ 12 (* (mod i 2) (+ w 12))) (+ 82 (* (/ i 2) 80)) w 64)
})
(defun draw-setup-hub () {
(txt 12 (base-c font-ui 26) 0xFFFFFF font-ui "DETECTION AND SETUP")
(txt 12 (base-c font-ui 56) 0x9CA3AF font-ui "Choose a check")
(looprange i 0 4 {
(var r (setup-tile-rect i)) (var x (ix r 0)) (var y (ix r 1)) (var w (ix r 2))
(var names '("MOTOR WIZARD" "HALL CHECK" "THROTTLE" "BRAKE / REGEN"))
(var hints '("Detect and save tune" "Inputs and table" "ADC1" "ADC2"))
(rbox x y w (ix r 3) 8 0x20262E)
(txt-c (+ x (/ w 2)) (base-c font-ui (+ y 22)) 0xFFFFFF font-ui (ix names i))
(txt-c (+ x (/ w 2)) (base-c font-ui (+ y 46)) 0x9CA3AF font-ui (ix hints i))
})
(var bw (/ (- fb-w 36) 2))
(setup-button 12 240 bw "VALUES" 0x20262E)
(if (not cfg-simple) (setup-button (+ 24 bw) 240 bw "IMU SETUP" 0x20262E))
(txt 12 (base-c font-ui (- fb-h 27)) (if (or (setup-locked) (hall-locked)) 0xF59E0B 0x9CA3AF) font-ui
(cond ((or (setup-locked) (hall-locked)) "Check active")
((setup-live) "Connected") (t "No controller")))
(setup-button (- fb-w 96) (- fb-h 40) 84 "HELP" 0x006CA8)
})

(defun setup-voltage-x (voltage) (+ 12 (to-i (* (- fb-w 24) (/ (clampx voltage 0.0 3.3) 3.3)))))
(defun draw-setup-adc () {
    (var live (setup-live)) (var w (- fb-w 24))
    (looprange i 0 2 {
        (var y (+ 63 (* i 51))) (var v (ix setup-adc i))
        (var color (if live (if (= i 0) 0x38BDF8 0xF59E0B) 0x667080))
        (txt 12 (base-c font-ui y) 0x9CA3AF font-ui (if (= i 0) "ADC1 throttle" "ADC2 brake"))
        (txt-r (- fb-w 12) (base-c font-ui y) color font-ui
            (if live (str-merge (str-from-n v "%.3f") " V") "STALE"))
        ; Always erase the whole track before drawing a shorter fill.
        (rbox 12 (+ y 17) w 14 4 0x303640)
        (var fill (- (setup-voltage-x v) 12))
        (if (and live (> fill 0)) (rbox 12 (+ y 17) fill 14 (if (< fill 8) 0 4) color) (tc-skip))
        (if (and (!= setup-view 1) (= i (- setup-kind 2)) (>= setup-stage 7)) {
            (rbox (clampx (setup-voltage-x (ix setup-values 0)) 12 (- fb-w 15)) (+ y 15) 3 18 0 0xFFFFFF)
            (if (>= setup-stage 8)
                (rbox (clampx (setup-voltage-x (ix setup-values 1)) 12 (- fb-w 15)) (+ y 15) 3 18 0 0x22C55E))
        })
    })
    (if (!= setup-view 1) {
    (txt 12 (base-c font-ui 174) 0xFFFFFF font-ui (if (>= setup-stage 7)
        (str-merge "Rest " (str-from-n (ix setup-values 0) "%.3f") " V") "Rest --"))
    (txt-r (- fb-w 12) (base-c font-ui 174) 0x9CA3AF font-ui "0 - 3.3 V")
    (txt 12 (base-c font-ui 201) 0x22C55E font-ui (if (>= setup-stage 8)
        (str-merge "Full " (str-from-n (ix setup-values 1) "%.3f") " V") "Full --"))
    })
})
(defun draw-setup () (cond ((= setup-view 10) (draw-help)) ((>= setup-view 8) (draw-basic-setup)) ((>= setup-view 5) (draw-imu-setup)) ((= setup-view 3) (draw-hall)) (t (draw-setup-body))))
(defun draw-setup-body () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (if (!= setup-view 0) (setup-heading
        (setup-title (if (or (= setup-view 1) (= setup-pending 1)) setup-choice setup-kind))))
    (cond
        ((= setup-view 0) (draw-setup-hub))
        ((= setup-view 1) {
            (if (= setup-choice 1) {
                (txt 12 (base-c font-ui 74) 0xF59E0B font-ui "Motor will spin / clear shaft")
                (var bw (/ (- fb-w 32) 2))
                (setup-button 12 100 bw "PREVIOUS" 0x303640)
                (setup-button (+ 20 bw) 100 bw "NEXT MOTOR" 0x303640)
                (txt 12 (base-c font-ui 160) 0xFFFFFF font-ui (ix setup-motors (- setup-amps 101)))
                (txt 12 (base-c font-ui 192) 0x9CA3AF font-ui "Detects and SAVES motor + sensors")
                (txt 12 (base-c font-ui 217) 0x9CA3AF font-ui "Keeps battery and power-mode caps")
                (txt 12 (base-c font-ui 241) 0x9CA3AF font-ui (cond ((= setup-note 3) "Update ESC package for setup") ((= setup-note 1) "End Hall check and disarm first") (t "STOP waits for measurement to end")))
            } {
                (draw-setup-adc)
                (txt 12 (base-c font-ui 174) 0xFFFFFF font-ui "Capture rest then full travel")
                (txt 12 (base-c font-ui 205) 0x9CA3AF font-ui "Review before saving this input")
                (txt 12 (base-c font-ui 241) 0x9CA3AF font-ui (cond ((= setup-note 3) "Update ESC package for setup") ((= setup-note 1) "End Hall check and disarm first") (t "START holds motor output off")))
            })
            (var bw (/ (- fb-w 32) 2))
            (setup-button 12 (- fb-h 44) bw "BACK" 0x303640)
            (setup-button (+ 20 bw) (- fb-h 44) bw "START" 0x92400E)
        })
        ; START has selected a new setup, but the snapshot still describes the
        ; previous session until the controller replies. Do not render its ADC
        ; panel, readings or capture actions under the new Motor Wizard title.
        ((= setup-pending 1) {
            (txt 12 (base-c font-ui 100) 0xFFFFFF font-ui "Entering Neutral and service hold")
            (txt 12 (base-c font-ui 135) 0x9CA3AF font-ui "Waiting for controller")
            (var bw (/ (- fb-w 32) 2))
            (setup-button (+ 20 bw) (- fb-h 44) bw "CANCEL" 0x303640)
        })
        (t {
            (if (= setup-kind 1) {
                (looprange i 0 4 {
                    (var labels (if (>= setup-current 101)
                        '("R mOhm" "L uH" "Flux mWb" "Motor limit A")
                        '("R mOhm" "L uH" "Flux mWb" "L test A")))
                    (var y (+ 63 (* i 35)))
                    (txt 12 (base-c font-ui y) 0x9CA3AF font-ui (ix labels i))
                    (txt-r (- fb-w 12) (base-c font-ui y) 0xFFFFFF font-ui (str-from-n (ix setup-values i) "%.3f"))
                })
            } {
                (draw-setup-adc)
            })
            (txt 12 (base-c font-ui (- fb-h 94)) 0xFFFFFF font-ui (if (= setup-view 4) "Save this input calibration" (setup-message)))
            (txt 12 (base-c font-ui (- fb-h 64)) 0x9CA3AF font-ui
                (if (and (= setup-stage 11) (= setup-error 5)) "END retries restoring the tune" (if (= setup-stage 11) (str-merge "Stage error " (str-from-n setup-error "%d") " / fault " (str-from-n setup-fault "%d")) (if (> setup-kind 1) (if (= setup-view 4) "Motor tune kept / output off" "Output held / END leaves setup") (if (>= setup-current 101) "Output held / END returns Neutral" "Tuning unchanged / output held")))))
            (var bw (/ (- fb-w 32) 2))
            (if (= setup-view 4) {
                (setup-button 12 (- fb-h 44) bw "CANCEL" 0x303640)
                (setup-button (+ 20 bw) (- fb-h 44) bw "SAVE INPUT" (if (setup-live) 0x166534 0x303640))
            } {
                (if (or (= setup-stage 6) (= setup-stage 7) (= setup-stage 8))
                    (setup-button 12 (- fb-h 44) bw (cond ((= setup-stage 6) "CAPTURE REST") ((= setup-stage 7) "CAPTURE FULL") (t "REVIEW SAVE")) 0x303640))
                (setup-button (+ 20 bw) (- fb-h 44) bw (if (setup-running) "STOP" "END") (if (setup-running) 0x991B1B 0x303640))
            })
        })
    )
})
(defun setup-hit (x y) (cond
    ((= setup-view 10) (help-hit x y))
    ((and (= setup-view 0) (setup-inside x y (- fb-w 96) (- fb-h 40) 84 36)) (help-open-page))
    ((and (= setup-view 0) (setup-inside x y 12 240 (/ (- fb-w 36) 2) 36)) (setup-open 6))
    ((and (= setup-view 0) (setup-inside x y (+ 24 (/ (- fb-w 36) 2)) 240 (/ (- fb-w 36) 2) 36)) (setup-open 5))
    ((= setup-view 0) (looprange i 0 4 {
        (var r (setup-tile-rect i))
        (if (setup-inside x y (ix r 0) (ix r 1) (ix r 2) (ix r 3))
            (setup-open (ix '(1 4 2 3) i)))
    }))
    ((setup-inside x y 12 6 76 40) (setup-back))
    ((>= setup-view 8) (basic-hit x y))
    ((>= setup-view 5) (imu-hit x y))
    ((= setup-view 3) (hall-hit x y))
    ((and (= setup-view 1) (= setup-choice 1) (>= y 100) (< y 136)) {
        (var bw (/ (- fb-w 32) 2))
        (if (setup-inside x y 12 100 bw 36) (def setup-amps (+ 101 (mod (+ (- setup-amps 101) 8) 9))))
        (if (setup-inside x y (+ 20 bw) 100 bw 36) (def setup-amps (+ 101 (mod (+ (- setup-amps 101) 1) 9))))
    })
    (t {
        (var bw (/ (- fb-w 32) 2))
        (var left (setup-inside x y 12 (- fb-h 44) bw 36))
        (var right (setup-inside x y (+ 20 bw) (- fb-h 44) bw 36))
        (if (= setup-view 1)
            (cond (left (setup-back)) (right (setup-start)))
            (if (= setup-view 4)
                (cond (left (def setup-view 2))
                      ((and right (= setup-stage 8) (= setup-pending -1)) (setup-action 6)))
                (cond (right (setup-action 0))
                    ((and left (!= setup-pending 1)) (cond ((= setup-stage 6) (setup-action 2)) ((= setup-stage 7) (setup-action 3))
                        ((and (= setup-stage 8) (> setup-kind 1)) (def setup-view 4)))))))
    })
))
@const-end
