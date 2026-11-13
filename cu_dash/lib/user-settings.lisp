;! Units, data sources and presets.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; unit conversion, the source table and the presets

@const-start
; --- unit conversion and the source table --------------------------------
(defun cv-temp (c) (if (= cfg-unit-temp 1) c (+ 32.0 (* c 1.8))))
(defun cv-speed (k) (if (= cfg-unit-speed 1) k (* k 0.621371)))
(defun cv-dist (k) (if (= cfg-unit-dist 1) k (* k 0.621371)))

(defun fmt (v d) {
        ; no tenth past a thousand: an odometer at 6213.1 mi and 99999.7 mi ran
        ; into its neighbours on the upright Instrument's footer, and the
        ; tenth of a mile says nothing at that size (sweep, 2026-10-24)
        (var s (if (and (= d 1) (< (abs v) 999.95)) (str-from-n v "%.1f") (str-from-n v "%.0f")))
        ; A current of -0.04 formats as "-0", which on a dash reads as a
        ; fault rather than as zero. Caught on a photograph of the screen
        ; sitting at rest with the motor stopped: "AMPS -0A".
        (if (or (eq s "-0") (eq s "-0.0")) (if (= d 1) "0.0" "0") s)
})

(defun src-val (s) (cond
        ; magnitude, not sign: a speedometer reads 4 going backwards, and
        ; the gear box beside it is what says which way. Found by driving the
        ; motor in reverse on the bench - the big number read "-4", and the
        ; arc fill went to empty, while every gear and mode check in here was
        ; already using (abs d-speed).
        ((= s 0) (cv-speed (abs d-speed)))
        ((= s 1) (cv-temp d-tmot))   ((= s 2) (cv-temp d-tesc))
        ((= s 3) d-amps)             ((= s 4) d-volt)
        ; From the pack when there is one. The controller estimates charge
        ; from voltage and a BMS counts coulombs, so two layouts reading the
        ; same "Charge %" would otherwise disagree with each other - which
        ; they did, 48 against 54, on the same battery.
        ((= s 5) (if (bms-live) bms-soc (* d-soc 100.0)))    ((= s 6) d-kw)
        ((= s 7) (* d-duty 100.0))   ((= s 8) (cv-temp d-tbat))
        ((= s 9) (cv-dist d-trip))   ((= s 10) (cv-dist d-odo))
        ((= s 11) (if (> d-trip 0.1) (/ (trip-wh) (cv-dist d-trip)) 0.0))
        ((= s 12) d-wh)              ((= s 13) bms-ah)
        ((= s 14) (to-float d-fault))
        ((= s 16) (cv-temp e2-tmot)) ((= s 17) (cv-temp e2-tesc))
        ((= s 18) e2-amps)           ((= s 19) (+ d-amps e2-amps))
        ((= s 20) (cv-temp (src-max-temp d-tmot e2-tmot)))
        ((= s 21) (cv-temp (src-max-temp d-tesc e2-tesc)))
        ((= s 22) x-amp-max)         ((= s 23) x-wh-chg)
        ((= s 24) x-pitch)           ((= s 25) d-iin)
        (t 0.0)))

(defun src-label (s) (cond
        ((= s 0) "SPEED")  ((= s 1) "MOTOR")  ((= s 2) "CTRL")
        ((= s 3) "AMPS")   ((= s 4) "BATTERY")((= s 5) "CHARGE")
        ((= s 6) "POWER")  ((= s 7) "DUTY")   ((= s 8) "PACK T")
        ((= s 9) "TRIP")   ((= s 10) "ODO")   ((= s 11) "EFF")
        ((= s 12) "ENERGY")((= s 13) "AMP HR")((= s 14) "FAULT")
        ((= s 16) "MOTOR 2")((= s 17) "CTRL 2")  ((= s 18) "AMPS 2")
        ((= s 19) "AMPS TOT")((= s 20) "MOTOR MAX")((= s 21) "CTRL MAX")
        ((= s 22) "PEAK AMPS")((= s 23) "CHARGED")((= s 24) "PITCH")
        ((= s 25) "BATT A")
        (t "")))

(defun src-unit (s) (cond
        ((= s 0) (if (= cfg-unit-speed 1) "KMH" "MPH"))
        ((or (= s 1) (= s 2) (= s 8) (= s 16) (= s 17) (= s 20) (= s 21))
            (if (= cfg-unit-temp 1) "C" "F"))
        ((or (= s 3) (= s 18) (= s 19) (= s 22) (= s 25)) "A")
        ((= s 4) "V")      ((= s 5) "%")     ((= s 6) "kW")
        ((= s 7) "%")
        ((or (= s 9) (= s 10)) (if (= cfg-unit-dist 1) "km" "mi"))
        ((= s 11) (if (= cfg-unit-dist 1) "Wh/km" "Wh/mi")) ((or (= s 12) (= s 23)) "Wh")
        ((= s 13) "Ah")    ((= s 24) "deg")
        (t "")))

(defun src-dec (s) (cond
        ((or (= s 4) (= s 6) (= s 9) (= s 10) (= s 13) (= s 24)) 1)
        (t 0)))

; Disconnected thermistors can report about -75 C. Keep that sentinel out
; of rider-facing temperatures while leaving numeric telemetry untouched.
(defun src-temp-ok (v) (and (>= v -40.0) (<= v 250.0)))
(defun src-max-temp (primary second)
    (if (and (e2-live) (or (not d-online) (> second primary))) second primary))
(defun src-ready (s) (cond
    ((or (= s 1) (= s 2)) d-online)
    ((= s 8) (bms-live))
    ((or (= s 16) (= s 17) (= s 18)) (e2-live))
    ((or (= s 20) (= s 21)) (or d-online (e2-live)))
    (t true)))
(defun src-fmt (s d) {
        (var temp (cond ((= s 1) d-tmot) ((= s 2) d-tesc) ((= s 8) d-tbat)
            ((= s 16) e2-tmot) ((= s 17) e2-tesc)
            ((= s 20) (src-max-temp d-tmot e2-tmot))
            ((= s 21) (src-max-temp d-tesc e2-tesc)) (t nil)))
        (if (or (not (src-ready s)) (and temp (not (src-temp-ok temp)))) "--"
            (fmt (src-val s) d))
})

(defun preset-base () {
        (def cfg-show-tl true) (def cfg-show-tr true)
        (def cfg-show-bl true) (def cfg-show-br true)
        (def cfg-show-gauge true) (def cfg-show-batt true)
        (def cfg-show-bars true) (def cfg-show-modes true)
        (def cfg-tl-x 8) (def cfg-tl-y 8) (def cfg-tr-x 320) (def cfg-tr-y 8)
        (def cfg-bl-x 8) (def cfg-bl-y 116) (def cfg-br-x 320) (def cfg-br-y 116)
        (def cfg-g-x 240) (def cfg-g-y 116) (def cfg-g-r 88)
        (def cfg-bar-x 8) (def cfg-bar-y 228)
        (def cfg-bar-icon true) (def cfg-bar-segs 28)
        (def cfg-bar-src 5) (def cfg-bar-fill 5)
        (def cfg-bar-min 0.0) (def cfg-bar-max 100.0)
        ; the ring numbers' size has no control of its own: Cart sets 18 and
        ; without this every layout picked after it kept ring numbers at 18
        (def cfg-fs-ring 88)
        ; and the status strip back to the layout's own place: Custom and the
        ; upright Cart set one, and every layout picked after them kept it -
        ; on the upright layouts right over their top labels (MPH, MOTOR 2,
        ; CHARGE), seen in the frames recorded for the web preview 2026-10-24
        (def cfg-status-x -1) (def cfg-status-y -1)
        (def cfg-tl-min 0.0) (def cfg-tr-min 0.0)
        (def cfg-bl-min 0.0) (def cfg-br-min 0.0) (def cfg-arc-min 0.0)
        ; The four slots need a baseline here, because not every preset sets
        ; all of them: 2 sets none and 3 and 4 leave the bottom right alone.
        ; Without this they keep whatever the previously selected layout put
        ; there, so the screen you get depends on the screen you had before -
        ; picking Tacho after Dual showed the motor amps twice, both labelled
        ; AMPS, and looked like a duplicated reading rather than a stale one.
        (def cfg-tl-src 1) (def cfg-tr-src 2)
        (def cfg-bl-src 3) (def cfg-br-src 4)
})

(defun cart-theme-defaults () {
        (def cfg-font 1)
        (def cfg-fs-sm 14) (def cfg-fs-lg 48) (def cfg-fs-ring 18)
        (def cfg-bg-col 0x1e293b) (def cfg-acc-col 0x000000)
        (def cfg-theme-all true)
        (def cfg-tl-src 25) (def cfg-tr-src 3)
        (def cfg-bl-src 2) (def cfg-br-src 1)
})

; Pure settings: safe before fonts/framebuffer initialization on a fresh cart.
; Applied once at first boot, or when the owner enables Cart mode. Saved
; appearance choices remain intact on subsequent starts and ordinary imports.
(defun cart-defaults () {
        (preset-base)
        (def cfg-style 6) (def cfg-vstyle 6)
        (def cfg-arc-src 0) (def cfg-arc-max 60.0)
        (cart-theme-defaults)
})

(defun set-cart-mode (enabled) {
        (var entering (and enabled (not cfg-simple)))
        (def cfg-simple enabled)
        (if entering {
                (cart-defaults)
                (if fonts-ready (trap (refonts)))
        })
        (def fb-dirty true)
        (def mode-state nil)
        (cfg-dump)
        true
})

(defun preset (n) {
        ; the faces are rebuilt at the end if this changed any of them - a
        ; preset that brings its own (5, Cart) or one picked after them
        ; (by value: what came out of the store is i32, a preset's own numbers are not)
        (var fonts0 (map to-i (list cfg-font cfg-fs-sm cfg-fs-lg cfg-fs-xl cfg-fs-ring)))
        (preset-base)
        (def cfg-arc-src 0) (def cfg-arc-max 60.0)
        (cond
            ; 0 INSTRUMENT - number, side columns, footer row
            ((= n 0) {
                    (def cfg-style 0)
                    (def cfg-tl-src 1) (def cfg-tl-max 120.0)
                    (def cfg-tr-src 2) (def cfg-tr-max 120.0)
                    (def cfg-bl-src 3) (def cfg-bl-max 150.0)
                    (def cfg-br-src 4) (def cfg-bar-src 5) })
            ; 1 TWIN RING - speed and charge as arcs, three stats below
            ((= n 1) {
                    (def cfg-style 1)
                    (def cfg-tl-src 5) (def cfg-tl-max 100.0)
                    (def cfg-tr-src 1) (def cfg-bl-src 2) (def cfg-br-src 3) })
            ; 2 DUAL MOTOR - a column per controller
            ((= n 2) {
                    (def cfg-style 2)
                    (def cfg-esc2-en true) (def cfg-bar-src 5) })
            ; 3 TACHO - shift lights over a dominant number
            ((= n 3) {
                    (def cfg-style 3)
                    (def cfg-tl-src 6) (def cfg-tl-max 15.0)
                    (def cfg-tr-src 1) (def cfg-bl-src 3) })
            ; 4 FLANK - upright meters at both edges
            ((= n 4) {
                    (def cfg-style 4)
                    (def cfg-tl-src 3) (def cfg-tl-max 200.0)
                    (def cfg-tr-src 5) (def cfg-tr-max 100.0)
                    (def cfg-bl-src 4)
                    ; The baseline leaves this on battery volts, which is
                    ; what the bottom left is set to just above - so the
                    ; layout came up showing 49.0 V twice side by side and
                    ; read as a bug in the reading rather than in the preset.
                    ; Exactly the trap the baseline comment describes.
                    (def cfg-br-src 1) })
            ; 5 HEADER - four small values over the number
            ((= n 5) {
                    (def cfg-style 5)
                    (def cfg-tl-src 1) (def cfg-tr-src 2)
                    (def cfg-bl-src 3) (def cfg-br-src 4)
                    (def cfg-bar-fill 5) (def cfg-bar-max 100.0) })
            ; 7 CUSTOM - a starting arrangement to drag from rather than a
            ; design. Four readings along the bottom, the number above them,
            ; no ring, everything clear of everything else.
            ((= n 7) {
                    (def cfg-style 7)
                    (def cfg-show-gauge false)
                    (def cfg-show-main true)
                    (def cfg-show-s6 false) (def cfg-show-s7 false)
                    (def cfg-show-s8 false)
                    ; Four columns across 480, each carrying a label that
                    ; includes its unit. At 22 the widest of those - BATTERY V
                    ; - is 125 wide against a 120 column, so the right hand one
                    ; ran 21 pixels off the panel and lost its V. Four cannot
                    ; fit at that size whatever the spacing, and the unit
                    ; cannot just be dropped: the value underneath carries no
                    ; unit of its own. Measured at 18 the label is 102 and the
                    ; value 99, so 116 apart from 12 ends the last one at 462.
                    ; 20 is the most that fits (label ~114 in the 116, ending at
                    ; 474): at 18 the labels and the MPH over the number read as
                    ; small print beside every other layout (2026-10-24).
                    (def cfg-fs-sm 20) (def cfg-fs-lg 46) (def cfg-fs-xl 110)
                    (def cfg-main-x 140) (def cfg-main-y 40)
                    (def cfg-tl-x 12)  (def cfg-tl-y 190)
                    (def cfg-tr-x 128) (def cfg-tr-y 190)
                    (def cfg-bl-x 244) (def cfg-bl-y 190)
                    (def cfg-br-x 360) (def cfg-br-y 190)
                    (def cfg-bar-x 16) (def cfg-bar-y 282) (def cfg-bar-w 448)
                    (def cfg-chip-x 416) (def cfg-chip-y 16)
                    (def cfg-status-x 164) (def cfg-status-y 6)   ; clear of the MPH under it
                    (def cfg-tl-src 1) (def cfg-tr-src 2)
                    (def cfg-bl-src 3) (def cfg-br-src 4)
                    (def cfg-bar-fill 5) (def cfg-bar-max 100.0) })
            ; 6 CART - the Arduino screen: ring left, stats pill right
            ((= n 6) {
                    (def cfg-style 6)
                    ; the face and sizes are part of the look, not a
                    ; preference - this screen is set in Montserrat at
                    ; fourteen, twenty four and forty eight
                    ; battery amps, motor amps, then the two temperatures,
                    ; which is the Arduino's order exactly
                    (cart-theme-defaults) })
            (t nil))
        (if (not-eq fonts0 (map to-i (list cfg-font cfg-fs-sm cfg-fs-lg cfg-fs-xl cfg-fs-ring)))
            (trap (refonts)))
        (cfg-dump)
        true
})

(defun vpreset (n) {
        (preset-base)
        (def cfg-vertical true)
        (def cfg-arc-src 0) (def cfg-arc-max 60.0)
        (def cfg-bar-fill 5) (def cfg-bar-min 0.0) (def cfg-bar-max 100.0)
        (def cfg-fs-xl 124)
        (cond
            ; 0 INSTRUMENT
            ((= n 0) { (def cfg-vstyle 0)
                    (def cfg-tl-src 1) (def cfg-tr-src 2)
                    (def cfg-bl-src 3) (def cfg-br-src 4) })
            ; 1 TACHO
            ((= n 1) { (def cfg-vstyle 1)
                    (def cfg-tl-src 6) (def cfg-tl-max 15.0)
                    (def cfg-tr-src 1) (def cfg-bl-src 3) })
            ; 2 DUAL
            ((= n 2) { (def cfg-vstyle 2) (def cfg-esc2-en true) })
            ; 3 FLANK
            ((= n 3) { (def cfg-vstyle 3)
                    (def cfg-tl-src 3) (def cfg-tl-max 200.0)
                    (def cfg-tr-src 5) (def cfg-tr-max 100.0)
                    (def cfg-bl-src 4) })
            ; 4 MOTO
            ((= n 4) { (def cfg-vstyle 4)
                    (def cfg-tl-src 10) (def cfg-tr-src 4) })
            ; 5 SCOOBI - matches the reference cluster, including a speed
            ; digit tall enough that the face drops to one bit glyphs
            ((= n 5) { (def cfg-vstyle 5)
                    (def cfg-arc-src 0) (def cfg-arc-max 60.0)
                    (def cfg-bar-max 100.0)
                    (def cfg-fs-xl 244) })
            ; 7 CUSTOM - the same starting arrangement, turned upright
            ((= n 7) { (def cfg-vstyle 7)
                    (def cfg-show-gauge false)
                    (def cfg-show-main true)
                    (def cfg-show-s6 false) (def cfg-show-s7 false)
                    (def cfg-show-s8 false)
                    (def cfg-fs-sm 22) (def cfg-fs-lg 46) (def cfg-fs-xl 110)
                    (def cfg-main-x 60) (def cfg-main-y 60)
                    (def cfg-tl-x 16)  (def cfg-tl-y 230)
                    (def cfg-tr-x 176) (def cfg-tr-y 230)
                    (def cfg-bl-x 16)  (def cfg-bl-y 320)
                    (def cfg-br-x 176) (def cfg-br-y 320)
                    (def cfg-bar-x 16) (def cfg-bar-y 430) (def cfg-bar-w 288)
                    (def cfg-chip-x 256) (def cfg-chip-y 16)
                    (def cfg-status-x 84) (def cfg-status-y 16)
                    (def cfg-tl-src 1) (def cfg-tr-src 2)
                    (def cfg-bl-src 3) (def cfg-br-src 4) })
            ; 6 CART - the portrait half of the Arduino screen
            ((= n 6) { (def cfg-vstyle 6)
                    (cart-theme-defaults) }))
        (apply-orient)
        (trap (refonts))
        (cfg-dump)
        true
})

@const-end
