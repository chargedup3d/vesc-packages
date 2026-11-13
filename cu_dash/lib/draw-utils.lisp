;! Layout slots and shared drawing.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; slot placement, text helpers, the mode chip and the backlight

@const-start
(def k-foot   (list 9 10 4))
(def k-ride   (list 9 10 11 12 1 2 8 3 4 5))
(def k-diag   (list 0 3 4 5 1 2 8 6 7 9 10 12))
(def k-odo    (list 9 12 11))
(def k-thermal (list 10 9 6))
(def k-dualnm (list "MOTOR" "CTRL" "AMPS"))

; index 0 is Main, 1 to 4 are the original slots, 5 is the bottom meter and
; 6 to 8 are the extra positions the denser layouts need
(defun slots-rebuild () {
        (def sl-src (list cfg-arc-src cfg-tl-src cfg-tr-src cfg-bl-src
                          cfg-br-src cfg-bar-src
                          cfg-s6-src cfg-s7-src cfg-s8-src))
        (def sl-col (list cfg-acc-arc cfg-acc-tl cfg-acc-tr cfg-acc-bl
                          cfg-acc-br cfg-acc-batt
                          cfg-acc-s6 cfg-acc-s7 cfg-acc-s8))
        (def sl-min (list cfg-arc-min cfg-tl-min cfg-tr-min cfg-bl-min
                          cfg-br-min cfg-bar-min
                          cfg-s6-min cfg-s7-min cfg-s8-min))
        (def sl-max (list cfg-arc-max cfg-tl-max cfg-tr-max cfg-bl-max
                          cfg-br-max cfg-bar-max
                          cfg-s6-max cfg-s7-max cfg-s8-max))
        true
})
(defun slots-check () {
        (var sig (+ cfg-arc-src (* cfg-tl-src 17) (* cfg-tr-src 289)
                    (* cfg-bl-src 4913) (* cfg-br-src 83521)
                    (* cfg-bar-src 1419857) (* cfg-s6-src 11) (* cfg-s7-src 13)
                    (* cfg-s8-src 17) cfg-acc-s6 cfg-acc-s7 cfg-acc-s8
                    (to-i cfg-arc-max) (* (to-i cfg-tl-max) 3)
                    (* (to-i cfg-tr-max) 5) (* (to-i cfg-bl-max) 7)
                    (* (to-i cfg-br-max) 11) (* (to-i cfg-bar-max) 13)
                    ; and the rest of the ranges: a change to a minimum alone, or
                    ; to a lower slot's maximum, left the meters on the old scale
                    ; until something else moved (review 2026-10-24)
                    (* (to-i cfg-arc-min) 19) (* (to-i cfg-tl-min) 23)
                    (* (to-i cfg-tr-min) 29) (* (to-i cfg-bl-min) 31)
                    (* (to-i cfg-br-min) 37) (* (to-i cfg-bar-min) 41)
                    (* (to-i cfg-s6-min) 43) (* (to-i cfg-s7-min) 47)
                    (* (to-i cfg-s8-min) 53) (* (to-i cfg-s6-max) 59)
                    (* (to-i cfg-s7-max) 61) (* (to-i cfg-s8-max) 67)
                    cfg-acc-arc cfg-acc-tl cfg-acc-tr cfg-acc-bl
                    cfg-acc-br cfg-acc-batt
                    ; The strip owns a row of the screen and the chip is
                    ; placed relative to it, so turning it off changes the
                    ; geometry as much as any source does. Left out of
                    ; this sum, cart mode changed nothing until some other
                    ; setting happened to move and drag a rebuild with it,
                    ; which read as cart mode arriving late rather than
                    ; not arriving at all.
                    (if (strip-on) 1 0)))
        ; sig is a sum of eeprom values and so an i32, while slots-sig starts
        ; life as a plain 0. Same trap as everywhere else: compare numerically.
        (if (!= sig slots-sig) {
                (def slots-sig sig)
                (slots-rebuild)
        })
})
(defun chip-slot () {
        (if cfg-vertical
            (cond
                ; Tacho draws its own mode pill at 10,36 - the named one,
                ; ECO / POWER - so the shared chip would be a second answer
                ; to the same question. It also had nowhere to go: 236,2 sits
                ; on the twelve segment meter that spans x 10..310 at y 8.
                ((= cfg-vstyle 1) (list -1 -1))
                ((= cfg-vstyle 2) (list 14 420))  ; dual: bottom left
                ((= cfg-vstyle 3) (list 136 32))  ; flank: between the meters
                ; Moto draws its own 66 square chip beside the stats, sized
                ; and placed for that layout, so the overlay was a duplicate
                ; sitting in the corner above it.
                ((= cfg-vstyle 4) (list -1 -1))
                ((= cfg-vstyle 5) (list -1 -1))   ; scoobi has its own
                ; cart: the left margin beside the ring, which at this height
                ; is still more than fifty wide
                ; The corner, strip or no strip. This used to drop to y 60
                ; whenever the strip was shown, on the assumption that the
                ; strip owned the top row - it does not. The cart strip is a
                ; 140 wide block centred on the panel, so in portrait it sits
                ; at x 90..230 and a 48 chip at x 2..50 never comes near it.
                ; The result was a chip floating below an empty corner.
                ((= cfg-vstyle 6) (list 2 2))
                ((= cfg-vstyle 7) (list cfg-chip-x cfg-chip-y))
                (t (list 264 2)))
            (cond
                ; between the two rings, which leaves a 64 wide gap
                ((= cfg-style 1) (list 213 110)) ; twin: between the rings
                ((= cfg-style 2) (list -2 210))  ; dual: below the number
                ((= cfg-style 3) (list 12 80))   ; tacho: left, below the label
                ((= cfg-style 4) (list -2 210))  ; flank: below the number
                ((= cfg-style 5) (list 14 130))  ; header: against the left edge
                ; cart: the corner of the arc area the ring does not reach.
                ; At y 78 the ring's left edge is already past x 65, so a
                ; 48 wide chip here clears it and sits under the strip.
                ; Same in landscape: the strip is centred at x 90..230 of
                ; 480, so the corner is free whether it is shown or not.
                ((= cfg-style 6) (list 6 2))
                ((= cfg-style 7) (list cfg-chip-x cfg-chip-y))
                (t (list -2 196))))
})
; The strip's drawn content is 140 wide even though the slot is 152, so a
; centred position has to be worked out from the content or it sits left.
(defun strip-cx () (/ (- fb-w 140) 2))

; The other pages have titles of their own along the top, and the layout's
; slot landed on them: upright, the strip sat on RIDE DATA, ODOMETER,
; DIAGNOSTIC and on the wheelie page's title and ARMED chip; and a landscape
; layout that moves it (Tacho y 50, Header y 228, Custom anywhere) would have
; put it in the middle of those pages (page sweep, 2026-10-24).
(defun page-strip-slot () (cond
        ((= page (pg-setup)) (list -1 -1))
        ; no room beside the upright wheelie title and its ARMED chip, and
        ; the chip says what matters on that page
        ((= page (pg-whl)) (if cfg-vertical (list -1 -1) (list (strip-cx) 2)))
        ; upright cells has its title left and the cell count right
        ((= page (pg-cells)) (list (strip-cx) 2))
        ; the other upright pages have a title at the left only
        (cfg-vertical (list (- fb-w 156) 2))
        (t (list (strip-cx) 2))))

(defun strip-slot () {
        (if (!= page 0) (page-strip-slot)
        (if cfg-vertical
            (cond ((= cfg-vstyle 5) (list -1 -1))
                  ; dual fills the top with motor headings and the middle
                  ; with columns, so both go along the bottom
                  ((= cfg-vstyle 2) (list (strip-cx) 444))
                  ; tacho's power meter runs the full width of the top, and
                  ; the strip sat on it; under the last row is free
                  ((= cfg-vstyle 1) (list (strip-cx) 444))
                  (t (list (strip-cx) 2)))
            (cond
                ((= cfg-style 1) (list (strip-cx) 2))
                ; centred in the gap between the two motor columns.
                ; The drawn content is 140 wide, so it is centred on
                ; that rather than the 152 slot.
                ((= cfg-style 2) (list (strip-cx) 2))
                ; tacho fills the top with a full width meter
                ((= cfg-style 3) (list 300 50))
                ((= cfg-style 4) (list (strip-cx) 2))
                ; between the number and the battery meter
                ((= cfg-style 5) (list (strip-cx) 228))
                ; cart: centred over the arc area, not the panel, which is
                ; where the Arduino screen puts its connection line
                ((= cfg-style 6) (list 90 2))
                ((= cfg-style 7) (list cfg-status-x cfg-status-y))
                (t (list (strip-cx) 2)))))
})
; How far a layout moves down to clear the strip at the top. By orientation:
; this read the landscape layout even when an upright one asked, so upright
; Flank moved by whatever the landscape choice happened to want, and upright
; Instrument, which needs it most (the strip sat on its MPH), asked nothing.
(defun strip-drop ()
    (if (not (strip-on)) 0
      (if cfg-vertical
        (cond ((= cfg-vstyle 0) 22)
              ((= cfg-vstyle 3) 11)
              (t 0))
        (cond ((= cfg-style 1) 20)
              ((= cfg-style 3) 0)
              ((= cfg-style 4) 6)
              ((= cfg-style 5) 0)
              ; the cart ring is fixed geometry with the strip above it
              ((= cfg-style 6) 0)
              ((= cfg-style 7) 0)
              (t 11)))))

(defun clampx (v lo hi) (cond ((< v lo) lo) ((> v hi) hi) (t v)))

(defun mode-name (m) (cond ((and cfg-simple (not (cart-package-live))) "DATA") ((= m -1) "R") ((= m 0) "N")
                           ((= m 1) cfg-m1-name) ((= m 2) cfg-m2-name)
                           ((= m 3) cfg-m3-name) ((= m 4) "ROAD") (t "?")))

(defun mode-label (m) (cond ((and cfg-simple (not (cart-package-live))) "--") ((= m -1) "R") ((= m 0) "N") ((= m 4) "D")
                            (t (str-from-n m "%d"))))

(defun mode-colour (m) (cond ((and cfg-simple (not (cart-package-live))) 0x808080) ((= m -1) 0xFF0000) ((= m 0) 0xFFFF00)
                             ((= m 1) 0x00FF00) ((= m 2) 0x00FFFF)
                             ((= m 4) 0x0090FF)
                             (t 0xFF8000)))
(defun mode-mot (m) (cond ((= m 1) cfg-m1-mot) ((= m 2) cfg-m2-mot)
                          ((= m 3) cfg-m3-mot) ((= m 4) cfg-d-mot) (t 0)))
(defun mode-spd (m) (cond ((= m 1) cfg-m1-spd) ((= m 2) cfg-m2-spd)
                          ((= m 3) cfg-m3-spd) ((= m 4) cfg-d-spd) (t 5)))
(defun mode-brk (m) (cond ((= m 1) cfg-m1-brk) ((= m 2) cfg-m2-brk)
                          ((= m 3) cfg-m3-brk) ((= m 4) cfg-d-brk) (t 20)))
(defun mode-bat (m) (cond ((= m 1) cfg-m1-bat) ((= m 2) cfg-m2-bat)
                          ((= m 3) cfg-m3-bat) ((= m 4) cfg-d-bat) (t 0)))



(defun clamp01 (x) (cond ((< x 0.0) 0.0) ((> x 1.0) 1.0) (t x)))

(defun txt-c (cx y c f s) (txt-a cx y c f s 1))
(defun txt-r (rx y c f s) (txt-a rx y c f s 2))

; Centred, but never off the edge. A label is centred on the thing it
; labels, and a long one on a narrow panel then hangs over the side: the
; portrait flank layout centres its right hand label at 286 of 320, which
; is fine for AMPS and cuts the E off CHARGE. The label moves rather than
; the meter, because the meter is what the eye is lining it up with.
(defun txt-cs (cx y c f s) (txt-a cx y c f s 3))


(defun p2-rows () {
        (txt 20 32 cfg-acc-arc font-sm "RIDE DATA")
        (rule-h 20 40 440 cfg-acc-arc)
        (var ss (list 9 1 10 2 11 8 12 3 4 5))
        (var cs sl-col)
        (looprange i 0 10 {
                (var sc (ix ss i))
                (var x (+ 20 (* (mod i 2) 236)))
                (var y (+ 78 (* (/ i 2) 47)))
                (txt x y (ix cs (mod i 5)) font-sm (src-label sc))
                (txt-r (+ x 212) y cfg-c-value font-md
                    (str-merge (src-fmt sc (src-dec sc)) " " (src-unit sc)))
        })
})

(defun p2-odo () {
        (txt 16 34 cfg-acc-arc font-sm "ODOMETER")
        (txt 16 132 cfg-c-value font-xl (src-fmt 10 1))
        (txt-r 464 132 cfg-c-unit font-sm (src-unit 10))
        (rule-h 16 162 448 (c-rule))
        (stat-block 16 190 200 9 cfg-acc-tl)
        (stat-block 264 190 200 12 cfg-acc-tr)
        (stat-block 16 264 200 11 cfg-acc-bl)
        (stat-block 264 264 200 4 cfg-acc-br)
})

(defun vp-ride () {
        (txt 16 34 cfg-acc-arc font-sm "RIDE DATA")
        (rule-h 16 42 288 cfg-acc-arc)
        (var ss k-ride)
        (var cs sl-col)
        (looprange i 0 10 {
                (var sc (ix ss i))
                (var y (+ 80 (* i 40)))
                (txt 16 y (ix cs (mod i 5)) font-sm (src-label sc))
                (txt-r 304 y cfg-c-value font-md
                    (str-merge (src-fmt sc (src-dec sc)) " " (src-unit sc)))
        })
})

(defun vp-odo () {
        (txt 16 34 cfg-acc-arc font-sm "ODOMETER")
        ; the ring face, the big one here - except under Cart, which sets it to
        ; 18 for its own use, and the odometer came out the size of a label
        (txt-c 160 124 cfg-c-value (if (> cfg-fs-ring cfg-fs-lg) font-ring font-lg) (src-fmt 10 1))
        (txt-c 160 168 cfg-c-unit font-sm (src-unit 10))
        (rule-h 16 182 288 (c-rule))
        (var ss k-odo)
        (var cs (cdr sl-col))
        (looprange i 0 3 {
                (var sc (ix ss i))
                (var y (+ 216 (* i 80)))
                (txt 16 y (ix cs i) font-sm (src-label sc))
                (txt 16 (+ y 44) cfg-c-value font-lg
                    (src-fmt sc (src-dec sc)))
                (txt-r 304 (+ y 44) cfg-c-unit font-sm (src-unit sc))
                (box 16 (+ y 58) 288 2 (ix cs i))
        })
})

(defun vp-diag () {
        (txt 12 28 cfg-acc-arc font-sm "DIAGNOSTIC")
        (rule-h 12 34 296 cfg-acc-arc)
        (var ss k-diag)
        (looprange i 0 12 {
                (var sc (ix ss i))
                (var x (+ 12 (* (mod i 2) 152)))
                (var y (+ 68 (* (/ i 2) 66)))
                (txt x y cfg-acc-tr font-sm (src-label sc))
                (txt x (+ y 30) cfg-c-value font-sm
                    (str-merge (src-fmt sc (src-dec sc)) " " (src-unit sc)))
        })
        (if (> d-fault 0)
            (txt 12 466 0xFF0000 font-sm (fault-name d-fault))
            (txt 12 466 0x00FF00 font-sm "OK"))
})

(defun draw-vpage2 () (cond
        ((= cfg-p2-style 1) (vp-odo))
        ((= cfg-p2-style 2) (vp-diag))
        (t (vp-ride))))

(defun draw-page2 () (cond
        ((= cfg-p2-style 1) (p2-odo))
        ((= cfg-p2-style 2) (draw-diag))
        (t (p2-rows))))
(defun src-glyph (s) (cond
        ((= s 0) ico-speed)
        ((or (= s 1) (= s 2) (= s 8) (= s 16) (= s 17) (= s 20) (= s 21)) ico-temp)
        ((or (= s 3) (= s 18) (= s 19)) ico-bolt)
        ((= s 6) ico-power)
        ((or (= s 4) (= s 13)) ico-batt)
        ((= s 5) ico-charge)
        ((or (= s 9) (= s 10)) ico-route)
        ((or (= s 11) (= s 12)) ico-eco)
        ((= s 7) ico-pct)
        ((= s 14) ico-warn)
        (t nil)))

(defun draw-icon (src x y sz c) {
        (if (and (> cfg-icons 0) (!= src 15)) {
                (var g (src-glyph src))
                (if g (txt-ico x (+ y (- sz 3)) c font-ico g))
        })
})
(defun clamp01f (x) (cond ((< x 0.05) 0.05) ((> x 1.0) 1.0) (t x)))


(defun bl-init () {
        ; channel 2, backlight pin, 2kHz. Started once; set-duty alone after.
        ; Starts at zero: display-init leaves the panel dark on purpose, and
        ; coming up at full here would put the static back for the moment
        ; before the splash pulls it down again.
        (var r (trap (pwm-start 2000 0.0 2 1 10)))
        (def bl-started (eq (car r) 'exit-ok))
        ; With no pwm there is no way to fade, and leaving the pin where
        ; display-init put it would look like a dead unit, so drive it on.
        (if (not bl-started) {
                (print "backlight pwm unavailable, staying on")
                (trap (gpio-write 1 1))
        })
        bl-started
})

(defun bl-apply () {
        (if bl-started
            (trap (pwm-set-duty
                      (clamp01f (if bl-night-on cfg-bl-night cfg-bl-day)) 2))
            false)
})

(defun bl-toggle () { (def bl-night-on (not bl-night-on)) (bl-apply) })
(defun bl-step (d) {
        (var st (/ (to-float cfg-bl-step) 100.0))
        (var previous (if bl-night-on cfg-bl-night cfg-bl-day))
        (if bl-night-on
            (def cfg-bl-night (clamp01f (+ cfg-bl-night (* d st))))
            (def cfg-bl-day (clamp01f (+ cfg-bl-day (* d st)))))
        (bl-apply)
        ; Persist only the changed brightness slot, not the whole UI config.
        ; Repeated presses at the clamp must not keep writing flash.
        (var level (if bl-night-on cfg-bl-night cfg-bl-day))
        (if (!= previous level) (eeprom-store-f (if bl-night-on 97 96) level))
})
(defun fault-name (f) (cond
        ((= f 0) "")
        ((= f 1) "OVER VOLT")   ((= f 2) "UNDER VOLT")
        ((= f 3) "DRV")         ((= f 4) "ABS OVERCURRENT")
        ((= f 5) "FET TEMP")    ((= f 6) "MOTOR TEMP")
        ((= f 7) "GATE DRV OV") ((= f 8) "GATE DRV UV")
        ((= f 9) "MCU UNDER V") ((= f 10) "BOOT FAULT")
        ((= f 11) "ENCODER SPI")((= f 12) "ENCODER MAG LOW")
        ((= f 13) "ENCODER MAG HIGH")
        ((= f 14) "FLASH CORRUPT")
        ((= f 25) "HIGH OFFSET")((= f 26) "UNBALANCED")
        ((= f 29) "BRK")
        (t (str-from-n f "FAULT %d"))))


(defun mode-toggle-rev () {
        (if (and (< (abs d-speed) 1.6) (!= cfg-mode 4))
            (send-mode (if (= cfg-mode -1) 1 -1)))
})

; In or out, and it says which out loud, because a mode with no control of
; its own is otherwise indistinguishable from the bike having gone wrong.
(defun mode-toggle-d () {
        (if (= cfg-mode 4)
            { (print "road mode off") (send-mode 1) }
            { (print "road mode on") (send-mode 4) })
        ; saved both ways, so a restart keeps road mode (main) and does not
        ; bring back one already left; nothing else writes slot 64 but cfg-save
        (eeprom-store-i 64 cfg-mode)
})
(defun mode-chip-x () {
        (var sz cfg-mode-size)
        (if (< cfg-mode-pos 0)
            {
                ; auto: the layout's slot. -2 means centre, so the chip stays
                ; centred if its size is changed.
                (var sx (ix (chip-slot) 0))
                (if (= sx -2) (setq sx (/ (- fb-w sz) 2)))
                (clampx (+ sx cfg-mode-dx) 0 (- fb-w sz))
            }
            {
                (var c (mod cfg-mode-pos 3))
                (var b (cond ((= c 0) 6)
                             ((= c 1) (/ (- fb-w sz) 2))
                             (t (- fb-w sz 6))))
                (clampx (+ b cfg-mode-dx) 0 (- fb-w sz))
            })
})

(defun mode-chip-y () {
        (var sz cfg-mode-size)
        (if (< cfg-mode-pos 0)
            (clampx (+ (ix (chip-slot) 1) cfg-mode-dy) 0 (- fb-h sz))
            {
                (var r (/ cfg-mode-pos 3))
                (var b (cond ((= r 0) 6)
                             ((= r 1) (/ (- fb-h sz) 2))
                             (t (- fb-h sz 6))))
                (clampx (+ b cfg-mode-dy) 0 (- fb-h sz))
            })
})

(defun draw-modestrip () {
        (var sz cfg-mode-size)
        (var x (mode-chip-x))
        (var y (mode-chip-y))
        (var c (mode-colour cfg-mode))
        (if (gear-locked (- cfg-mode 1)) (setq c 0x808080))
        (chip x y sz 8 c 0x000000 (if (< sz 40) font-sm font-lg) (mode-label cfg-mode))
        (if (< (secs-since mode-blocked) 1.5)
            (txt-c (+ x (/ sz 2)) (+ y sz 20) 0xFF0000 font-sm "STOP"))
})

(defun modestrip-hit (tx ty) {
        (var sz cfg-mode-size)
        (var x (mode-chip-x))
        (var y (mode-chip-y))
        ; the same conditions draw-overlays draws it under: a hidden chip
        ; kept its hit area (top left with no slot) and changed the mode
        (if (and cfg-show-modestrip (not (bms-chg))
                 (>= (ix (chip-slot) 1) 0)
                 (> tx x) (< tx (+ x sz))
                 (> ty y) (< ty (+ y sz)))
            ; mode-cycle, not mode-step: a step clamps at the top, so
            ; tapping the chip took you 1, 2, 3 and then did nothing at all.
            ; The chip is one control with no second direction, so it has to
            ; wrap - which is what mode-cycle is for, and it already knows
            ; that a cart wraps 3 -> 1 while everything else wraps 3 -> N.
            { (mode-cycle) true }
            false)
})
; NOTE: img-rectangle misdraws a rectangle that is one pixel wide or tall on
; this panel - the row lands at the wrong offset and appears as a stray line
; beside the shape. Keep every dimension at two or more.
;
; Drawn in two pixel bands rather than single pixel rows. Every other element
; on screen is two or more pixels in both directions, and the arrows were the
; only thing using one - which is exactly where the stray displaced line came
; from. Two pixel steps also halve the number of draw calls.
(defun st-arrow (x y s c left) {
        (var hw (/ (* s 3) 5))          ; head length
        (var th (/ s 4))                ; tail thickness
        (var half (/ s 2))

        ; tail first, running under the head so there is no seam
        (var tw (+ (- s hw) 4))
        (box (if left (- (+ x s) tw) x) (+ y (/ (- s th) 2)) tw th c)

        (looprange k 0 (/ s 2) {
                (var r (* k 2))
                (var d (if (< r half) (- half r) (- r half)))
                (var reach (- hw (/ (* d hw) half)))
                (if (> reach 1)
                    (box (if left (+ x (- hw reach)) (+ x (- s hw)))
                         (+ y r) reach 2 c))
        })
})

(defun st-beam-icon (x y s c) {
        (ring (+ x (/ s 3)) (+ y (/ s 2)) (/ s 3) c 2)
        (looprange i 0 3
            (box (+ x (/ (* s 2) 3)) (+ y (/ s 4) (* i (/ s 4))) (/ s 3) 2 c))
})


@const-end
