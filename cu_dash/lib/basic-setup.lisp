; Basic Setup: local edits never command the motor or write configuration.
; The package owns persistence, shown explicitly on the review screen.
@const-start
(def basic-edit '(12 20 10)) (def basic-dirty nil) (def basic-query-t 0)
(def basic-drag-row -1) (def basic-mask 0) (def basic-queue nil)
(def basic-serial 0) (def basic-token 0) (def basic-field 0) (def basic-value-want 0)
(defun basic-live () (and (setup-live) (= setup-kind 5) (>= setup-stage 22)))
(defun basic-ready () (and (basic-live) (setup-locked) (or (= setup-stage 22) (= setup-stage 24))
    (= setup-pending -1) (= setup-error 0)))
(defun basic-max (i) (to-i (cond ((= i 0) (ix setup-adc 1))
    ((= i 1) (if cfg-simple (clampx (* 3 (ix basic-edit 2)) 0 (ix setup-values 3)) (ix setup-values 3)))
    (t (ix setup-adc 0)))))
(defun basic-min (i) (if (= i 0) 6 1))
; Match the cart package editor. Reducing battery amps can only lower motor
; amps, never raise battery amps. Both selected changes remain on the review.
(defun basic-cart-limit () (if (and cfg-simple (> (ix basic-edit 1) (basic-max 1))) {
    (def basic-edit (list (ix basic-edit 0) (basic-max 1) (ix basic-edit 2)))
    (def basic-mask (bitwise-or basic-mask 2)) (def basic-dirty t) t
} nil))
(defun basic-next () {
    (def basic-field (car basic-queue)) (def basic-value-want (ix basic-edit basic-field))
    (def basic-serial (mod (+ basic-serial 1) 64))
    (def basic-token (+ (shl basic-field 6) basic-serial))
    (setup-action 13)
})
(defun basic-save () (if (and (basic-ready) basic-dirty) {
    ; A mode change after REVIEW must return the new capped value for review.
    (if (basic-cart-limit) (def setup-note 4) {
    (def basic-queue nil)
    ; Raise battery first when raising both, lower motor first when lowering
    ; both. Every acknowledged intermediate pair respects the cart ratio.
    (loopforeach i (if (> (ix basic-edit 2) (ix setup-values 2)) '(0 2 1) '(0 1 2))
        (if (!= (bitwise-and basic-mask (shl 1 i)) 0)
        (def basic-queue (append basic-queue (list i)))))
    (def setup-note 0)
    (if basic-queue (basic-next))
    })
}))
(defun basic-tick () {
    (if (and (= setup-pending 13) (basic-live) (= setup-session setup-want)
        (= setup-elapsed basic-token)) {
        (if (or (= setup-stage 25) (> setup-error 0)) {
            (def basic-queue nil) (def setup-pending -1) (def setup-note 2)
        } (if (and (= setup-stage 24) (< (abs (- (ix setup-values basic-field) basic-value-want)) 0.01)) {
            (def basic-queue (cdr basic-queue))
            (if basic-queue (basic-next) {
                (def setup-pending -1) (def basic-mask 0) (def basic-dirty nil)
            })
        }))
    })
    ; An expired/unconfirmed request never starts the rest of the queue later.
    (if (and basic-queue (!= setup-pending 13)) (def basic-queue nil))
    (if (and (>= setup-view 8) (<= setup-view 9) (= page (pg-setup)) (> (setup-transport) 0)
        (not (setup-locked)) (> (secs-since basic-query-t) 0.5)) {
        (def basic-query-t (systime)) (setup-command 11)
    })
    (if (and (basic-live) (not basic-dirty))
        (def basic-edit (list (to-i (ix setup-values 0)) (to-i (ix setup-values 1)) (to-i (ix setup-values 2)))))
    ; Existing settings above the cart cap become a visible, unsaved edit.
    (if (and (= setup-view 8) (basic-ready)) (basic-cart-limit))
})
(defun basic-message () (cond
    ((= setup-note 2) "Unconfirmed / check connection")
    ((= setup-pending 1) "Entering service hold")
    ((= setup-pending 13) "Saving selected setting")
    ((= setup-note 4) "Cart cap changed / review again")
    ((and (= setup-kind 5) (= setup-stage 10)) "Link lost / output held")
    ((not (basic-live)) "Waiting for controller")
    ((and (= setup-stage 24) basic-dirty) "Review changes before saving")
    ((= setup-stage 24) "Saved in package / readback OK")
    ((= setup-stage 25) "Save unverified / output held")
    ((= setup-stage 23) "Saving / output held")
    ((= setup-error 1) "Requires Li-ion controller setup")
    ((= setup-error 2) "Need fresh link and Neutral")
    ((= setup-error 3) "Outside controller limits")
    ((= setup-stage 10) "Link lost / output held")
    ((and cfg-simple (setup-locked)) "Cart motor limit is 3x battery amps")
    ((setup-locked) "Choose ratings for your hardware")
    (t "START holds motor output off")))
(defun basic-draw-sig () (list 'basic setup-view basic-edit basic-dirty (basic-live)
    (basic-ready) (basic-message) setup-pending (setup-locked) setup-values setup-adc cfg-simple))
(defun basic-set (i v) (if (basic-ready) {
    (def basic-edit (map (fn (j) (if (= j i) (clampx (to-i v) (basic-min i) (basic-max i)) (ix basic-edit j))) '(0 1 2)))
    (def basic-dirty t) (def basic-mask (bitwise-or basic-mask (shl 1 i)))
    (basic-cart-limit)
}))
(defun basic-slider-row (x y) (if (and (= page (pg-setup)) (= setup-view 8) (basic-ready)
    (>= x 62) (< x (- fb-w 62)) (>= y 80) (< y 234)) {
    (var row (/ (- y 80) 62))
    (if (and (< row 3) (< (- y (+ 80 (* row 62))) 30)) row -1)
} -1))
(defun basic-drag (i x) (if (and (>= i 0) (< i 3))
    (basic-set i (+ (basic-min i) (to-i (+ 0.5 (* (- (basic-max i) (basic-min i))
        (/ (to-float (clampx (- x 72) 0 (- fb-w 144))) (- fb-w 144)))))))))
(defun basic-value (i) (str-merge (str-from-n (ix basic-edit i) "%d") (if (= i 0) "S Li-ion" " A")))
(defun draw-basic-setup () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (var bw (/ (- fb-w 32) 2))
    (if (= setup-view 8) {
        (looprange i 0 3 {
            (var y (+ 62 (* i 62)))
            (txt 12 (base-c font-ui y) 0x9CA3AF font-ui
                (if (and cfg-simple (= i 1) (basic-live))
                    (str-merge "Motor current / max " (str-from-n (basic-max 1) "%d") " A")
                    (ix '("Battery series" "Motor current" "Battery current") i)))
            (txt-r (- fb-w 12) (base-c font-ui y) (if (basic-live) 0x38BDF8 0x667080) font-ui
                (if (basic-live) (basic-value i) "--"))
            (rbox 12 (+ y 18) 42 30 8 0x303640)
            (txt-c 33 (base-c font-ui (+ y 33)) 0xFFFFFF font-ui "-")
            (rbox (- fb-w 54) (+ y 18) 42 30 8 0x303640)
            (rbox (- fb-w 39) (+ y 32) 12 2 0 0xFFFFFF)
            (rbox (- fb-w 34) (+ y 27) 2 12 0 0xFFFFFF)
            (rbox 72 (+ y 30) (- fb-w 144) 8 4 0x303640)
            (var f (if (and (basic-live) (> (basic-max i) (basic-min i)))
                (/ (to-float (- (ix basic-edit i) (basic-min i))) (- (basic-max i) (basic-min i))) 0.0))
            (rbox (+ 66 (to-i (* (- fb-w 144) (clampx f 0.0 1.0)))) (+ y 23) 12 22 5
                (if (basic-ready) 0x38BDF8 0x667080))
        })
        (txt 12 (base-c font-sm (- fb-h 64)) 0x9CA3AF font-sm (basic-message))
        (if (setup-locked) {
            (setup-button 12 (- fb-h 44) bw "END" 0x303640)
            (setup-button (+ 20 bw) (- fb-h 44) bw "REVIEW" (if (and (basic-ready) basic-dirty) 0x166534 0x20262E))
        } (setup-button 12 (- fb-h 44) (- fb-w 24) "START SETUP" 0x92400E))
    } {
        (looprange i 0 3 {
            (var y (+ 69 (* i 30)))
            (txt 12 (base-c font-ui y) 0x9CA3AF font-ui (ix '("Battery series" "Motor current" "Battery current") i))
            (txt-r (- fb-w 12) (base-c font-ui y) 0xFFFFFF font-ui (basic-value i))
        })
        (txt 12 (base-c font-ui 166) 0x38BDF8 font-ui (str-merge "Full charge " (str-from-n (* 4.2 (ix basic-edit 0)) "%.1f") " V"))
        (txt 12 (base-c font-sm 197) 0xF59E0B font-sm
            (if cfg-simple "Cart motor limit is 3x battery amps" "Only changed settings are saved"))
        (txt 12 (base-c font-sm 225) 0x9CA3AF font-sm "Saved with controller package")
        (txt 12 (base-c font-sm 253) 0x9CA3AF font-sm "Cutoffs and motor tune kept")
        (setup-button 12 (- fb-h 44) bw "CANCEL" 0x303640)
        (setup-button (+ 20 bw) (- fb-h 44) bw "SAVE" (if (basic-ready) 0x166534 0x20262E))
    })
    ; Paint the fixed header after the changing body so a body redraw cannot erase it.
    (rbox 0 0 fb-w 50 0 theme-bg)
    (setup-heading "VALUES")
})
(defun basic-hit (x y) {
    (var old-view setup-view)
    (var bw (/ (- fb-w 32) 2))
    (if (= setup-view 9) {
        (if (setup-inside x y 12 (- fb-h 44) bw 36) (def setup-view 8))
        (if (and (basic-ready) (setup-inside x y (+ 20 bw) (- fb-h 44) bw 36)) {
            (basic-save) (def setup-view 8)
        })
    } {
        (looprange i 0 3 {
            (var yy (+ 80 (* i 62)))
            (if (setup-inside x y 12 yy 42 30) (basic-set i (- (ix basic-edit i) 1)))
            (if (setup-inside x y (- fb-w 54) yy 42 30) (basic-set i (+ (ix basic-edit i) 1)))
        })
        (var row (basic-slider-row x y)) (if (>= row 0) (basic-drag row x))
        (if (setup-inside x y 12 (- fb-h 44) (- fb-w 24) 36) {
            (if (setup-locked) {
                (if (and (= setup-pending -1) (setup-inside x y 12 (- fb-h 44) bw 36)) (setup-action 0))
                (if (and (basic-ready) basic-dirty (setup-inside x y (+ 20 bw) (- fb-h 44) bw 36)) (def setup-view 9))
            } { (def setup-choice 5) (def basic-dirty nil) (def basic-mask 0) (def basic-queue nil) (setup-start) (def setup-view 8) })
        })
    })
    (if (!= old-view setup-view) (def fb-dirty true))
})
@const-end
