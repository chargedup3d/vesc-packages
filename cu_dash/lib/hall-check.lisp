; Manual and powered Hall Check over CAN link or direct VESC Bluetooth. Results never saved.
@const-start
(def hall-stop-request nil) (def hall-amps 2) (def hall-run-amps 0) (def hall-run-session -1)
(def hall-confirm nil) (def hall-running nil) (def hall-ms 0) (def hall-fault 0)
(def hall-table '(255 255 255 255 255 255 255 255)) (def hall-beat-t 0)
(def hall-via 0) (def hall-query-t 0) (def hall-t 0) (def hall-seq -1) (def hall-session 0) (def hall-status 0)
(def hall-raw 0) (def hall-seen 0) (def hall-counts '(0 0 0))
(def hall-gaps 0) (def hall-states 0) (def hall-jumps 0)
(def hall-owned nil) (def hall-pending -1) (def hall-want 0)
(def hall-request-t 0) (def hall-send-t 0) (def hall-note 0)
; Idle snapshots are sent once per second. Allow transport/scheduling margin,
; retaining the existing one-second freshness rule during an active check.
(defun hall-live () (and (> hall-t 0)
    (< (secs-since hall-t) (if (or hall-owned hall-running (>= hall-pending 0)) 1.0 1.5)) (> hall-via 0) (= hall-via (setup-transport))))
(defun hall-locked () (or hall-owned (>= hall-pending 0)
    (and (hall-live) (or (= hall-status 1) (= hall-status 2) (= hall-status 3) (= hall-status 5) (>= hall-status 6)))))
(defun hall-receive (data base via) (if (and (= via (setup-transport)) (>= (buflen data) (+ base 29))
    (= (bufget-u8 data (+ base 0)) 0x48) (= (bufget-u8 data (+ base 1)) 2)
    (<= (bufget-u8 data (+ base 5)) 11) (< (bufget-u8 data (+ base 6)) 8)
    (<= (bufget-u8 data (+ base 28)) 1)) (atomic {
        (var session (bufget-u16 data (+ base 2))) (var seq (bufget-u8 data (+ base 4)))
        (if (or (!= via hall-via) (!= seq hall-seq) (!= session hall-session)) {
            (def hall-via via) (def hall-t (systime)) (def hall-seq seq) (def hall-session session)
            (def hall-status (bufget-u8 data (+ base 5))) (def hall-raw (bufget-u8 data (+ base 6)))
            (def hall-seen (bufget-u8 data (+ base 7)))
            (def hall-counts (list (bufget-u16 data (+ base 8)) (bufget-u16 data (+ base 11)) (bufget-u16 data (+ base 14))))
            (def hall-gaps (bufget-u8 data (+ base 10))) (def hall-states (bufget-u8 data (+ base 13)))
            (def hall-jumps (bufget-u8 data (+ base 16)))
            (def hall-table (list (bufget-u8 data (+ base 17)) (bufget-u8 data (+ base 18)) (bufget-u8 data (+ base 19)) (bufget-u8 data (+ base 20))
                                 (bufget-u8 data (+ base 21)) (bufget-u8 data (+ base 22)) (bufget-u8 data (+ base 23)) (bufget-u8 data (+ base 24))))
            (def hall-ms (bufget-u16 data (+ base 25))) (def hall-fault (bufget-u8 data (+ base 27)))
            (def hall-running (= (bufget-u8 data (+ base 28)) 1))
            (if (or (= hall-status 1) (= hall-status 2) (= hall-status 3) (= hall-status 5) (>= hall-status 6)) {
                (if (not hall-owned) { (def setup-owner (setup-context)) (def hall-want session) })
                (def hall-owned t)
            })
            (if (= hall-want session) {
                (if (and (> hall-pending 0) (!= hall-status 0)) (def hall-pending -1))
                (if (and (= hall-pending 0) hall-stop-request (>= hall-status 9)) (def hall-pending -1))
                (if (and (= hall-pending 0) (= hall-status 0)) {
                    (def hall-pending -1) (def hall-owned nil) (def setup-owner nil) (def hall-note 0)
                    (if (= setup-view 3) (def setup-view 0))
                })
            })
        })
})))
(defun hall-from-link (b) (hall-receive b 115 1))
(defun hall-from-ble (b) (if (= (buflen b) 30) (hall-receive b 1 2)))
(defun hall-command (action session) {
    (var b (bufcreate 9))
    (bufset-u8 b 0 0xC7) (bufset-u8 b 1 0x57) (bufset-u8 b 2 0x30)
    (bufset-u8 b 3 action) (bufset-u16 b 4 session)
    (if (= action 2) (bufset-u8 b 6 hall-run-amps))
    (cond ((= (setup-transport) 1) (link-send b))
          ((= (setup-transport) 2) { (bufset-u8 b 0 36) (vb-send b) }))
    (free b)
})
(defun hall-start () (if (and (not (setup-locked)) (not hall-running) (hall-live) (< (abs d-speed) 0.5) (not (whl-armed))) {
    (send-mode 0)
    (def setup-owner (setup-context)) (def hall-owned t) (def hall-pending 1) (def hall-note 0)
    (def hall-want (+ 1 (mod (+ hall-session (to-i (* (secs-since 0) 100.0))) 65534)))
    (if (= hall-want hall-session) (def hall-want (mod (+ hall-want 1) 65536)))
    (def hall-request-t (systime)) (def hall-send-t (systime))
} (def hall-note 1)))
(defun hall-end () (if (hall-live) {
    (def hall-stop-request hall-running)
    (send-mode 0) (def hall-want hall-session) (def hall-pending 0)
    (def hall-request-t (systime)) (def hall-send-t 0) (def hall-note 0)
    (hall-command 0 hall-want)
} (def hall-note 2)))
(defun hall-power () (if (and (not (setup-locked)) (hall-live) (not hall-running)
    (< (abs d-speed) 0.5) (not (whl-armed)) (not (and (>= hall-status 9) (hall-locked)))) {
    (send-mode 0) (def hall-confirm nil) (def setup-owner (setup-context)) (def hall-owned t) (def hall-note 0)
    (def hall-want (+ 1 (mod (+ hall-session (to-i (* (secs-since 0) 100.0))) 65534)))
    (if (= hall-want hall-session) (def hall-want (mod (+ hall-want 1) 65536)))
    (def hall-run-amps hall-amps) (def hall-run-session hall-want)
    (def hall-pending 2) (def hall-request-t (systime)) (def hall-send-t (systime))
    ; Deferred once to allow Neutral to arrive. Retries cannot start a motor.
    (spawn (fn () {
        (var session hall-want) (sleep 0.8)
        (if (and (= hall-pending 2) (= hall-want session) (hall-live)) (hall-command 2 session))
    }))
} { (def hall-confirm nil) (def hall-note 1) }))
(defun hall-tick () {
    ; Discover a controller hold left across a screen restart from the hub too.
    ; This only reads status; it never starts or ends a Hall routine.
    (if (and (= (setup-transport) 2) (or hall-owned (= page (pg-setup)))
        (not (setup-locked)) (> (secs-since hall-query-t) (if hall-owned 0.2 0.5))) {
        (def hall-query-t (systime)) (hall-command 4 hall-want)
    })
    (if (and (or (and hall-running (hall-live)) (= hall-pending 2)) (> (secs-since hall-beat-t) 0.2) (> (setup-transport) 0)) {
        (def hall-beat-t (systime))
        (hall-command 3 (if (= hall-pending 2) hall-want hall-session))
    })
    (if (and (>= hall-pending 0) (> (secs-since hall-request-t) 0.8)
             (> (secs-since hall-send-t) 0.4) (> (setup-transport) 0)) {
        (def hall-send-t (systime))
        (if (< (secs-since hall-request-t) 8.0)
            (if (!= hall-pending 2) (hall-command hall-pending hall-want))
            { (def hall-pending -1) (def hall-note 2) })
    })
})
(defun hall-loop () (loopwhile t { (hall-tick) (sleep 0.2) }))
(defun hall-both (i) (= (bitwise-and (shr hall-seen (* i 2)) 3) 3))
(defun hall-state-n () {
    (var n 0) (looprange i 0 8 (if (!= 0 (bitwise-and hall-states (shl 1 i))) (setq n (+ n 1)))) n
})
(defun hall-message (live) (cond
    ((>= hall-pending 0) (if (> hall-pending 0) "Entering Neutral..." "Stopping / ending check..."))
    ((not live) "No Hall data - check ESC package")
    ((= hall-note 1) "Stop motor and disarm Wheelie first")
    ((= hall-note 2) "Request unconfirmed - check link")
    (hall-running (if (= hall-status 6) "Hall detect - motor rotates slowly" "Stopping - please wait"))
    ((= hall-status 7) "Hall table found - tuning unchanged")
    ((= hall-status 8) "No valid Hall table - compare inputs")
    ((= hall-status 9) "Stopped - END before another detect")
    ((= hall-status 10) "Link lost - stopped / END to clear")
    ((= hall-status 11) "Detect stopped - check controller fault")
    ((= hall-status 0) "Choose MANUAL or powered DETECT")
    ((= hall-status 2) "5 min complete - RESET or END")
    ((= hall-status 3) "Sensor port is not set to Halls")
    ((= hall-status 4) "Requires Neutral / UART-only app")
    ((= hall-status 5) "Setup changed - output remains held")
    ((> hall-gaps 0) "Capture gap - RESET and turn slowly")
    ((> hall-jumps 0) "Skipped states - turn slower")
    ((= hall-states (shl 1 hall-raw)) "Turn the MOTOR SHAFT slowly")
    ((and (hall-both 0) (hall-both 1) (hall-both 2)) "All 3 inputs changed - keep turning")
    (t "Keep turning - compare H1 / H2 / H3")))
(defun hall-table-text (start end) {
    (var s "") (looprange i start end {
        (setq s (str-merge s (if (= i start) "" " ")
            (if (= (ix hall-table i) 255) "--" (str-from-n (ix hall-table i) "%d"))))
    }) s
})
(defun draw-hall-confirm () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (setup-heading "HALL DETECT")
    (txt 12 (base-c font-ui 82) 0xF59E0B font-ui "Motor will rotate slowly")
    (var aw (/ (- fb-w 32) 2))
    (looprange i 0 2 {
        (var a (if (= i 0) 2 5)) (var x (+ 12 (* i (+ aw 8))))
        (rbox x 100 aw 36 8 (if (= hall-amps a) 0x92400E 0x303640))
        (txt-c (+ x (/ aw 2)) (base-c font-ui 118) 0xFFFFFF font-ui
            (str-merge (str-from-n a "%d") " A"))
    })
    (txt 12 (base-c font-ui 154) 0xFFFFFF font-ui "Secure motor and clear shaft")
    (txt 12 (base-c font-ui 190) 0x9CA3AF font-ui "Results only / tuning unchanged")
    (txt 12 (base-c font-ui 226) 0x9CA3AF font-ui "About 12 seconds / STOP available")
    (var w (/ (- fb-w 32) 2))
    (rbox 12 (- fb-h 44) w 36 8 0x303640)
    (txt-c (+ 12 (/ w 2)) (base-c font-ui (- fb-h 26)) 0xFFFFFF font-ui "CANCEL")
    (rbox (+ 20 w) (- fb-h 44) w 36 8 0x92400E)
    (txt-c (+ 20 w (/ w 2)) (base-c font-ui (- fb-h 26)) 0xFFFFFF font-ui "START SPIN")
})
(defun draw-hall () (if hall-confirm (draw-hall-confirm) (draw-hall-live)))
(defun draw-hall-live () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (var f (w-label-font)) (var nf (w-number-font))
    (var live (hall-live)) (var capture (and live (or (= hall-status 1) (>= hall-status 6))))
    (setup-heading "HALL CHECK")
    (txt-r (- fb-w 12) (base-c f 26) (if capture 0x38BDF8 0x9CA3AF) f
        (if (and live hall-running) (if (= hall-status 6) "SPINNING" "STOPPING") (if capture "LIVE" (if live "READY" "STALE"))))
    (var cw (/ (- fb-w 40) 3))
    (var cy 56) (var ch (if cfg-vertical 168 134))
    (looprange i 0 3 {
        (var x (+ 12 (* i (+ cw 8)))) (var cx (+ x (/ cw 2)))
        (var high (!= 0 (bitwise-and hall-raw (shl 1 i))))
        (rbox x cy cw ch 10 0x14181E)
        (txt-c cx (base-c f (+ cy 20)) 0x9CA3AF f (str-merge "H" (str-from-n (+ i 1) "%d")))
        (txt-c cx (base-c nf (+ cy 52)) (if capture (if high 0x38BDF8 0xFFFFFF) 0x667080) nf
            (if capture (if high "HIGH" "LOW") "--"))
        (txt-c cx (base-c f (+ cy 86)) 0xFFFFFF f
            (if live (str-from-n (ix hall-counts i) "%d") "--"))
        (txt-c cx (base-c font-ui (+ cy 108)) 0x9CA3AF font-ui "CHANGES")
        (if cfg-vertical (txt-c cx (base-c font-ui (+ cy 143)) 0x38BDF8 font-ui
            (if (and live (hall-both i)) "BOTH" "WAIT")))
    })
    (var y (+ cy ch 18))
    (txt 12 (base-c font-ui y) 0x9CA3AF font-ui
        (if live (str-merge "States " (str-from-n (hall-state-n) "%d")
            "/8   Gaps " (str-from-n hall-gaps "%d") "   Skips " (str-from-n hall-jumps "%d")) "Waiting for controller snapshot"))
    (if cfg-vertical {
        (txt 12 (base-c font-ui (+ y 28)) 0x9CA3AF font-ui "H1-H3 are controller input pins")
        (txt 12 (base-c font-ui (+ y 52)) 0x9CA3AF font-ui "Turn shaft one full revolution.")
        (txt 12 (base-c font-ui (+ y 76)) 0x9CA3AF font-ui "A fixed input is not a proven fault.")
    })
    (txt 12 (base-c font-ui (- fb-h 83)) 0xFFFFFF font-ui (hall-message live))
    (txt 12 (base-c font-ui (- fb-h 62)) 0x9CA3AF font-ui
        (cond
            ((and live hall-running) (str-merge (if (= hall-session hall-run-session) (str-merge (str-from-n hall-run-amps "%d") " A / ") "Sweep / ") (str-from-n (/ hall-ms 1000) "%d") " seconds / STOP to cancel"))
            ((and live (= hall-status 7)) (str-merge "Table " (hall-table-text 0 (if cfg-vertical 4 8))))
            ((hall-locked) "Motor output held off until END")
            (t "Manual rotation or a slow Hall sweep")))
    (if (and cfg-vertical live (= hall-status 7))
        (txt 12 (base-c font-ui (- fb-h 108)) 0x9CA3AF font-ui (str-merge "Table 4-7  " (hall-table-text 4 8))))
    (var bw (/ (- fb-w 40) 3))
    (looprange i 0 3 {
        (var x (+ 12 (* i (+ bw 8))))
        (rbox x (- fb-h 44) bw 36 8 (cond ((and (= i 2) hall-running) 0x991B1B)
            ((and (= i 1) (not hall-running)) 0x92400E) (t 0x303640)))
        (txt-c (+ x (/ bw 2)) (base-c f (- fb-h 26)) 0xFFFFFF f
            (cond ((= i 0) (if (= hall-status 1) "RESET" "MANUAL")) ((= i 1) "DETECT")
                (hall-running "STOP") (t "END")))
    })
})
(defun hall-hit (x y) (if (and hall-confirm (>= y 100) (< y 136))
    (def hall-amps (if (< x (/ fb-w 2)) 2 5))
    (if (and (>= y (- fb-h 44)) (< y (- fb-h 8)))
    (if hall-confirm
        (if (< x (/ fb-w 2)) (def hall-confirm nil) (hall-power))
        (cond
            ((>= x (* fb-w (/ 2.0 3.0))) (hall-end))
            ((and (not hall-running) (< hall-pending 0) (< x (/ fb-w 3))) (hall-start))
            ((and (not hall-running) (< hall-pending 0) (hall-live)) (def hall-confirm t))
        )))))
@const-end
