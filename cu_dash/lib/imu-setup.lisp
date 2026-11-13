; IMU child of Detection and Setup. Preview is read-only; edits require hold.
@const-start
(def imu-f 0) (def imu-u 4) (def imu-edit nil) (def imu-token 0) (def imu-query-t 0)
(defun imu-live () (and (setup-live) (= setup-kind 4) (>= setup-stage 16) (< setup-stage 21)))
(defun imu-ready () (and (imu-live) (setup-locked) (= setup-pending -1)
    (!= setup-stage 18) (!= setup-stage 21)))
(defun imu-axis (v) (ix '("X" "-X" "Y" "-Y" "Z" "-Z") (clampx (to-i v) 0 5)))
(defun imu-sync () (if (and (imu-live) (not imu-edit)) {
    (def imu-f (to-i (ix setup-values 2))) (def imu-u (to-i (ix setup-values 3)))
}))
(defun imu-message () (cond
    ((or (= setup-pending 8) (= setup-pending 10)) "Waiting for IMU readback")
    ((= setup-note 2) "Unconfirmed / check connection")
    ((not (setup-live)) "No setup data / check package")
    ((and (= setup-kind 4) (= setup-stage 21)) "Waiting for CAN IMU")
    ((< setup-stage 16) (setup-message))
    ((= setup-stage 18) "Hold still / measuring zero")
    ((= setup-stage 20) (cond ((= setup-error 4) "Check axes / hold IMU still")
        ((= setup-error 6) "Save unverified / check IMU") (t "Setup hold lost / try again")))
    ((= setup-stage 19) "Zero saved / readback OK")
    ((and (= setup-stage 17) (= (bitwise-and setup-error 1) 0)) "Mount saved / Zero Level next")
    ((= (bitwise-and setup-error 2) 0) "Sensor fault / check IMU")
    ((= (bitwise-and setup-error 1) 0) "Zero Level needed")
    (t "IMU healthy / level saved")))
; Keep complete repainting when pixels change, but do not spend a whole frame
; redrawing identical text. Use the displayed angle strings, including sign
; and rounding, so neither small sensor noise nor stale data gets mis-cached.
(defun imu-draw-sig () (list 'imu setup-view imu-f imu-u imu-edit
    (setup-locked) (hall-locked)
    (if (= setup-view 5) (list (imu-live) (imu-ready) (imu-message)
        (if (imu-live) (list (str-from-n (ix setup-values 0) "%.1f")
                            (str-from-n (ix setup-values 1) "%.1f")) nil)) nil)))
(defun imu-submit (action) (if (imu-ready) {
    (def imu-token (mod (+ imu-token 1) 256)) (def setup-note 0)
    (setup-action action) (def setup-view 5)
}))
(defun imu-tick () {
(if (and (not cfg-simple) (and (>= setup-view 5) (<= setup-view 7)) (= page (pg-setup)) (> (setup-transport) 0)
(not (setup-locked)) (> (secs-since imu-query-t) 0.5)) {
(def imu-query-t (systime)) (setup-command 7)
})
(imu-sync)
})

(defun draw-imu-setup () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (setup-heading "IMU SETUP")
    (var bw (/ (- fb-w 32) 2))
    (if (= setup-view 5) {
        (looprange i 0 2 {
            (var x (if (= i 0) 12 (+ 20 bw)))
            (txt x (base-c font-ui 69) 0x9CA3AF font-ui (if (= i 0) "PITCH" "ROLL"))
            (txt x (base-c font-ui 98) (if (imu-live) 0x38BDF8 0x667080) font-ui
                (if (imu-live) (str-merge (str-from-n (ix setup-values i) "%.1f") " deg") "--"))
        })
        (setup-button 12 123 bw (str-merge "FWD " (imu-axis imu-f)) (if (imu-ready) 0x303640 0x20262E))
        (setup-button (+ 20 bw) 123 bw (str-merge "UP " (imu-axis imu-u)) (if (imu-ready) 0x303640 0x20262E))
        (txt 12 (base-c font-ui 178) 0x9CA3AF font-ui
            (if (setup-locked) "Match board axis markings" "START holds output for setup"))
        (setup-button 12 198 bw "SAVE MOUNT" (if (and (imu-ready) imu-edit (!= (/ imu-f 2) (/ imu-u 2))) 0x166534 0x20262E))
        (setup-button (+ 20 bw) 198 bw "ZERO LEVEL" (if (and (imu-ready) (not imu-edit)) 0x92400E 0x20262E))
        (txt 12 (base-c font-ui 253) 0xFFFFFF font-ui (if (and imu-edit (= (/ imu-f 2) (/ imu-u 2))) "Forward and up must differ" (imu-message)))
        (setup-button 12 (- fb-h 44) (- fb-w 24) (if (setup-locked) "END SETUP" "START SETUP")
            (if (setup-locked) 0x303640 0x92400E))
    } {
        (txt 12 (base-c font-ui 84) 0xFFFFFF font-ui (if (= setup-view 6) "Set bike upright and level" "Save this mounting direction"))
        (txt 12 (base-c font-ui 126) 0xF59E0B font-ui (if (= setup-view 6) "Hold still for 1 second" "New mount clears level zero"))
        (txt 12 (base-c font-ui 168) 0x9CA3AF font-ui (if (= setup-view 6) "Saves level and gyro bias" (str-merge "Forward " (imu-axis imu-f) " / Up " (imu-axis imu-u))))
        (txt 12 (base-c font-ui 210) 0x9CA3AF font-ui (if (= setup-view 6) "Tilt only / no compass sensor" "Run Zero Level after saving"))
        (txt 12 (base-c font-ui 250) 0x9CA3AF font-ui "Motor output held off")
        (setup-button 12 (- fb-h 44) bw "CANCEL" 0x303640)
        (setup-button (+ 20 bw) (- fb-h 44) bw (if (= setup-view 6) "ZERO AND SAVE" "SAVE MOUNT") 0x166534)
    })
})
(defun imu-hit (x y) {
    (var bw (/ (- fb-w 32) 2))
    (if (= setup-view 5) {
        (if (and (imu-ready) (>= y 123) (< y 159)) {
            (cond ((setup-inside x y 12 123 bw 36) { (def imu-f (mod (+ imu-f 1) 6)) (def imu-edit t) })
                ((setup-inside x y (+ 20 bw) 123 bw 36) { (def imu-u (mod (+ imu-u 1) 6)) (def imu-edit t) }))
        })
        (if (imu-ready) {
            (if (and imu-edit (!= (/ imu-f 2) (/ imu-u 2)) (setup-inside x y 12 198 bw 36)) (def setup-view 7))
            (if (and (not imu-edit) (setup-inside x y (+ 20 bw) 198 bw 36)) (def setup-view 6))
        })
        (if (setup-inside x y 12 (- fb-h 44) (- fb-w 24) 36)
            (if (setup-locked) (if (and (!= setup-stage 18) (!= setup-pending 8) (!= setup-pending 10)) (setup-action 0))
                { (def setup-choice 4) (setup-start) (def setup-view 5) }))
    } {
        (if (setup-inside x y 12 (- fb-h 44) bw 36) (def setup-view 5))
        (if (setup-inside x y (+ 20 bw) (- fb-h 44) bw 36)
            (imu-submit (if (= setup-view 6) 10 8)))
    })
})
@const-end
