;! Addressable LED strips for link boards: tail, brake, signals, AUX.
;; ============================================================================
; cu_link_lights - addressable LED strips for a Charged Up link product
;
; A tail strip (running light, brake, sweeping indicators, hazards) and an
; optional AUX strip with a role (tail copy, headlight, one signal). They follow
; the core's state: aux-left/right/hazard/beam from the display or inputs,
; lt-brake from regen or CU Wheelie, lt-dark for lights off.
;
; Needs cu_link_core. The product sets, before (lights-start):
;   lt-fixed-pin    tail strip GPIO, or -1 to use the cfg-lt-pin setting
;   ax-pin          AUX strip GPIO, or -1 for none
;   lt-idle-rainbow true to show a rainbow until a display is heard
; Settings in EEPROM slots 170-189.
; ============================================================================

@const-start
(defun lights-save () {
        (eeprom-store-i 170 (if cfg-lt-en 1 0))
        (eeprom-store-i 171 cfg-lt-pin)
        (eeprom-store-i 172 cfg-lt-count)
        (eeprom-store-i 173 cfg-lt-type)
        (eeprom-store-i 174 (if cfg-lt-sweep 1 0))
        (eeprom-store-i 175 cfg-ax-count)
        (eeprom-store-i 176 cfg-ax-type)
        (eeprom-store-i 177 cfg-ax-role)
        (eeprom-store-f 178 cfg-b-run)
        (eeprom-store-f 179 cfg-b-brake)
        (eeprom-store-i 180 lights-magic)
        true
})

; false for a board that has never stored them, so the product can choose
; its own first-time defaults. The magic is compared as read: through
; core-ri, whose range stopped short of it, it never matched, and every
; setting here was back to its default after each power up.
(defun lights-load () (if (and (eeprom-read-i 180) (= (eeprom-read-i 180) lights-magic)) {
        (def cfg-lt-en (= (core-ri 170 0 1 0) 1))
        (def cfg-lt-pin (core-ri 171 0 21 cfg-lt-pin))
        (def cfg-lt-count (core-ri 172 1 120 cfg-lt-count))
        (def cfg-lt-type (core-ri 173 0 4 cfg-lt-type))
        (def cfg-lt-sweep (= (core-ri 174 0 1 1) 1))
        (def cfg-ax-count (core-ri 175 0 120 cfg-ax-count))
        (def cfg-ax-type (core-ri 176 0 4 cfg-ax-type))
        (def cfg-ax-role (core-ri 177 0 3 cfg-ax-role))
        (def cfg-b-run (core-rf 178 0.0 1.0 cfg-b-run))
        (def cfg-b-brake (core-rf 179 0.0 1.0 cfg-b-brake))
        true
} false))
@const-end

(def lights-magic 0x4C543031)   ; "LT01"
(def lt-fixed-pin -1) (def ax-pin -1) (def lt-idle-rainbow true)
(def cfg-lt-en false)
(def cfg-lt-pin 20)
(def cfg-lt-count 15)
(def cfg-lt-type 2)      ; 2 = GRBW SK6812, 0 = GRB WS2812
(def cfg-lt-timing 3)
(def cfg-lt-sweep true)  ; sweeping indicators rather than a hard blink
(def cfg-b-run 0.12)
(def cfg-b-brake 1.0)
(def cfg-b-ind 0.85)
(def lt-buf nil) (def lt-n 0) (def lt-t 0) (def lt-frame 0)
; what the painters below work on: the tail, or the AUX strip lent it
(def pb nil) (def pn 0)
(def cfg-ax-count 0)     ; AUX off until someone sets it up
(def cfg-ax-type 2)
(def cfg-ax-role 0)
(def ax-buf nil) (def ax-n 0) (def ax-ready false)

; ===========================================================================
; LIGHTING
;
; Drives an addressable strip directly from this board. Layers are painted
; in priority order so brake beats running light and indicators beat both.
; The render thread reads the input flags on its own 20ms tick, so nothing
; else ever has to call into it.
;
; Brake comes from motor current with no extra wiring: regen means braking.
; ===========================================================================
(def c-off 0x000000)
(def c-red 0xFF0000)
(def c-amber 0xFF3800)
(def c-white 0xFF000000)

@const-start
(defun lt-span (from to col bri)
    (looprange i from to (rgbled-color pb i col bri)))

; The TAIL plug on a CU IO Link is IO10 whatever the setting says: the pin
; setting is for the Express T, where the strip goes on whichever header pin
; it was wired to.
(defun lt-pin () (if (>= lt-fixed-pin 0) lt-fixed-pin cfg-lt-pin))

(defun lt-blink () (< (mod lt-frame 44) 22))

; Indicator on one half, sweeping outward from the centre split.
; Sweeps outward from the centre split. The right half is sized from the
; total rather than assumed equal to the left, or an odd LED count leaves the
; last one dark.
(defun lt-ind (left) {
        (var h (/ pn 2))
        (var nleft h)
        (var nright (- pn h))
        (var span (if left nleft nright))
        (if cfg-lt-sweep {
                (var step (mod lt-frame 44))
                (if (< step 22) {
                        (var lit (/ (* step span) 18))
                        (if (> lit span) (setq lit span))
                        (looprange i 0 lit
                            (if left
                                (rgbled-color pb (- h 1 i) c-amber cfg-b-ind)
                                (rgbled-color pb (+ h i) c-amber cfg-b-ind)))
                })
        } {
                (if (lt-blink)
                    (if left
                        (lt-span 0 h c-amber cfg-b-ind)
                        (lt-span h pn c-amber cfg-b-ind)))
        })
})

(defun rgbpack (r g b)
    (bitwise-or (shl r 16) (bitwise-or (shl g 8) b)))

; hue to colour, v is 0..1
(defun wheel (h v) {
        (var hh (mod h 360))
        (var sect (/ hh 60))
        (var f (mod hh 60))
        (var mx (to-i (* 255.0 v)))
        (var up (to-i (* 255.0 v (/ (to-float f) 60.0))))
        (var dn (- mx up))
        (cond ((= sect 0) (rgbpack mx up 0)) ((= sect 1) (rgbpack dn mx 0))
              ((= sect 2) (rgbpack 0 mx up)) ((= sect 3) (rgbpack 0 dn mx))
              ((= sect 4) (rgbpack up 0 mx)) (t (rgbpack mx 0 dn)))
})

(defun lt-rainbow ()
    (looprange i 0 pn
        (rgbled-color pb i (wheel (+ (* lt-frame 3) (* i 24)) 0.4))))

(defun lt-render () {
        (def pb lt-buf) (def pn lt-n)
        (looprange i 0 pn (rgbled-color pb i c-off))
        ; An IO Link is often the only box on the vehicle, so it lights up
        ; properly with no display; the rainbow is for a link waiting on one.
        (if (and (not (rx-live)) lt-idle-rainbow)
            ; nothing from the dash yet, so show a rainbow rather than
            ; sitting dark and looking broken
            (lt-rainbow)
            {
                ; lights off keeps the brake and the signals
                (if (not lt-dark) (lt-span 0 pn c-red cfg-b-run))
                (if lt-brake (lt-span 0 pn c-red cfg-b-brake))
                (if aux-hazard
                    (if (lt-blink) (lt-span 0 pn c-amber cfg-b-ind))
                    {
                        (if aux-left (lt-ind true))
                        (if aux-right (lt-ind false))
                    })
            })
        (rgbled-update lt-buf (lt-pin))
})

; The thread runs whether or not the strip is enabled, and checks each pass.
; Starting it only at boot meant the setting could not be changed without a
; restart: unticking left the thread running with the LEDs lit, and ticking
; did nothing at all until the next power cycle.
@const-end
(def lt-ready false)
(def lt-was-en false)

@const-start
(defun lights-init () {
        ; a new count or type from the settings page needs a new buffer, as
        ; on the AUX plug; it used to wait for a power up
        (if (and lt-ready (or (!= lt-n cfg-lt-count) (!= lt-t cfg-lt-type))) {
                (lights-off)
                (def lt-ready false)
        })
        (if lt-ready true {
                (var r (trap (rgbled-init (lt-pin) cfg-lt-timing)))
                (if (eq (car r) 'exit-ok) {
                        (def lt-buf (rgbled-buffer cfg-lt-count cfg-lt-type))
                        (def lt-n cfg-lt-count) (def lt-t cfg-lt-type)
                        (def lt-ready true)
                        (print (list "lights on pin" (lt-pin)
                                     "count" cfg-lt-count))
                        true
                } { (print "rgbled init failed") false })
        })
})

(defun lights-off () {
        (if lt-ready {
                (looprange i 0 lt-n (rgbled-color lt-buf i 0))
                (rgbled-update lt-buf (lt-pin))
        })
})

; Called when the setting changes, so the strip follows the tick box at once.
(defun lights-apply () {
        (if cfg-lt-en (lights-init) (lights-off))
        (def lt-was-en cfg-lt-en)
        true
})

; cycles every state so wiring can be checked without a dash attached
(defun lights-test () {
        (if (not (lights-init)) false {
                (print "running light")
                (def aux-left false) (def aux-right false) (def aux-hazard false)
                (sleep 1.5)
                ; the manual brake: the Link thread works lt-brake out again
                ; every tick, so setting that only flickered
                (print "brake") (def lt-brake-man true) (sleep 1.5)
                (def lt-brake-man false)
                (print "left") (def aux-left true) (sleep 2.5)
                (def aux-left false)
                (print "right") (def aux-right true) (sleep 2.5)
                (def aux-right false)
                (print "hazard") (def aux-hazard true) (sleep 2.5)
                (def aux-hazard false)
                (print "test done")
                true
        })
})

; ---------------------------------------------------------------------------
; The AUX plug (a product that has one sets ax-pin): a second strip with a role of its own.
;   0 a copy of the tail strip    1 headlight - white, full on high beam,
;   2 left signal only            3 right signal only
; Signals show on the headlight too, amber on the turning half. No LEDs set
; means the plug is off and nothing is sent to it at all.
; ---------------------------------------------------------------------------
(defun ax-on () (and (>= ax-pin 0) (> cfg-ax-count 0)))

(defun ax-white () (if (>= cfg-ax-type 2) c-white 0xFFFFFF))

(defun ax-init () {
        (if ax-ready true {
                (var r (trap (rgbled-init ax-pin cfg-lt-timing)))
                (if (eq (car r) 'exit-ok) {
                        (def ax-buf (rgbled-buffer cfg-ax-count cfg-ax-type))
                        (def ax-n cfg-ax-count)
                        (def ax-ready true)
                        (print (list "aux strip" cfg-ax-count "role" cfg-ax-role))
                        true
                } { (print "aux rgbled init failed") false })
        })
})

; clear what is there and start again: a new count needs a new buffer
(defun ax-apply () {
        (if ax-ready {
                (looprange i 0 ax-n (rgbled-color ax-buf i 0))
                (rgbled-update ax-buf ax-pin)
        })
        (def ax-ready false)
        true
})

(defun ax-span (from to col bri)
    (looprange i from to (rgbled-color ax-buf i col bri)))

; a signal on a strip of its own: the same sweep as the tail, across all of it
(defun ax-sig () {
        (if cfg-lt-sweep {
                (var step (mod lt-frame 44))
                (if (< step 22) {
                        (var lit (/ (* step ax-n) 18))
                        (if (> lit ax-n) (setq lit ax-n))
                        (ax-span 0 lit c-amber cfg-b-ind)
                })
        } (if (lt-blink) (ax-span 0 ax-n c-amber cfg-b-ind)))
})

(defun ax-render () {
        (ax-span 0 ax-n c-off 0.0)
        (var left (or aux-left aux-hazard))
        (var right (or aux-right aux-hazard))
        (var half (/ ax-n 2))
        (cond
            ((= cfg-ax-role 0) {
                    ; borrow the tail painter. It used to borrow the tail's own
                    ; settings for it, and a save landing then stored the AUX
                    ; count as the tail's.
                    (def pb ax-buf) (def pn ax-n)
                    (trap {
                        (if (not lt-dark) (lt-span 0 ax-n c-red cfg-b-run))
                        (if lt-brake (lt-span 0 ax-n c-red cfg-b-brake))
                        (if aux-hazard
                            (if (lt-blink) (lt-span 0 ax-n c-amber cfg-b-ind))
                            { (if aux-left (lt-ind true)) (if aux-right (lt-ind false)) })
                    })
            })
            ((= cfg-ax-role 1) {
                    (if (not lt-dark) (ax-span 0 ax-n (ax-white) (if aux-beam 1.0 0.45)))
                    (if (lt-blink) {
                            (if left (ax-span 0 half c-amber cfg-b-ind))
                            (if right (ax-span half ax-n c-amber cfg-b-ind))
                    })
            })
            ((= cfg-ax-role 2) (if left (ax-sig)))
            ((= cfg-ax-role 3) (if right (ax-sig))))
        (rgbled-update ax-buf ax-pin)
})

(defun ax-tick () {
        (if (ax-on) {
                (if (and ax-ready (!= ax-n cfg-ax-count)) (ax-apply))
                (if (ax-init) (ax-render))
        } (if ax-ready (ax-apply)))
})

(defun lights-start () {
        (loopwhile-thd ("Lights" 150) t {
                (match (trap (loopwhile t {
                            (if cfg-lt-en {
                                    (if (not lt-was-en) (lights-apply))
                                    (if (lights-init) (lt-render))
                            } {
                                    ; clear once on the way down, then idle
                                    (if lt-was-en (lights-apply))
                            })
                            (ax-tick)
                            ; wrapped on a whole number of every pattern's period,
                            ; or after a month the count overflowed
                            (def lt-frame (mod (+ lt-frame 1) 1320))
                            (sleep 0.02) }))
                    ((exit-ok (? a)) nil)
                    (_ nil))
                (sleep 1.0) })
})

; ---------------------------------------------------------------------------
@const-end
