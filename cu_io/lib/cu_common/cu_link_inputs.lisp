;! Switch inputs for link boards, mapped to actions.
; ============================================================================
; cu_link_inputs - switch inputs for a Charged Up link product
;
; Up to three inputs, each a switch to ground with the C3's pull-up (or, set to
; "open", one held to ground that acts when it opens: a normally closed brake
; switch, a kill loop). Read every 10 ms, taken once three reads agree. Each
; is a momentary button with a short and a long press, or an on/off switch
; whose action holds while it is on; or inputs 1 and 2 together are one
; three-position speed switch. What they do is set on the board, so they work
; with no display; the actions run through the core (sw-do), here or on the
; display.
;
; Needs cu_link_core. The product sets, before (inputs-start):
;   in-pins   list of GPIOs, one per input (its length is the count)
;   in-led    GPIO of a status LED, active low, or -1
; and routes custom app data through (inputs-app data) for the live test.
; Settings in EEPROM slots 150-169.
; ============================================================================

@const-start

(defun inputs-save () {
        (looprange i 0 3 {
                (eeprom-store-i (+ 150 (* i 4)) (sw-type i))
                (eeprom-store-i (+ 151 (* i 4)) (sw-pol i))
                (eeprom-store-i (+ 152 (* i 4)) (sw-short i))
                (eeprom-store-i (+ 153 (* i 4)) (sw-long i))
        })
        (eeprom-store-i 162 cfg-sw-pair)
        (eeprom-store-i 163 cfg-sw-pm0) (eeprom-store-i 164 cfg-sw-pm1) (eeprom-store-i 165 cfg-sw-pm2)
        true
})

(defun inputs-load () {
        (def cfg-sw1-type (core-ri 150 0 1 cfg-sw1-type)) (def cfg-sw1-pol (core-ri 151 0 1 cfg-sw1-pol))
        (def cfg-sw1-s (core-ri 152 0 31 cfg-sw1-s))       (def cfg-sw1-l (core-ri 153 0 31 cfg-sw1-l))
        (def cfg-sw2-type (core-ri 154 0 1 cfg-sw2-type)) (def cfg-sw2-pol (core-ri 155 0 1 cfg-sw2-pol))
        (def cfg-sw2-s (core-ri 156 0 31 cfg-sw2-s))       (def cfg-sw2-l (core-ri 157 0 31 cfg-sw2-l))
        (def cfg-sw3-type (core-ri 158 0 1 cfg-sw3-type)) (def cfg-sw3-pol (core-ri 159 0 1 cfg-sw3-pol))
        (def cfg-sw3-s (core-ri 160 0 31 cfg-sw3-s))       (def cfg-sw3-l (core-ri 161 0 31 cfg-sw3-l))
        (def cfg-sw-pair (core-ri 162 0 1 cfg-sw-pair))
        (def cfg-sw-pm0 (core-ri 163 0 3 cfg-sw-pm0)) (def cfg-sw-pm1 (core-ri 164 0 3 cfg-sw-pm1))
        (def cfg-sw-pm2 (core-ri 165 0 3 cfg-sw-pm2))
})

(defun sw-type (i) (cond ((= i 0) cfg-sw1-type) ((= i 1) cfg-sw2-type) (t cfg-sw3-type)))
(defun sw-pol (i) (cond ((= i 0) cfg-sw1-pol) ((= i 1) cfg-sw2-pol) (t cfg-sw3-pol)))
(defun sw-short (i) (cond ((= i 0) cfg-sw1-s) ((= i 1) cfg-sw2-s) (t cfg-sw3-s)))
(defun sw-long (i) (cond ((= i 0) cfg-sw1-l) ((= i 1) cfg-sw2-l) (t cfg-sw3-l)))

; one input, once a debounced state is known: on now, on before
(defun sw-tick (i on was) {
        (var s (sw-short i)) (var l (sw-long i))
        (cond
            ((= (sw-type i) 1)
                ; an on/off switch: a held action follows it, others fire on
                (if (not-eq on was)
                    (if (sw-state-act s) (sw-do s (if on 1 0)) (if on (sw-do s 2)))))
            ((sw-hold-act s) (if (not-eq on was) (sw-do s (if on 1 0))))
            (t {
                (if (and on (not was)) {
                        (setix sw-t i (systime))
                        (setix sw-fired i false)
                        ; nothing to tell apart, so act at once
                        (if (= l 0) { (sw-do s 2) (setix sw-fired i true) })
                })
                (if (and on (not (ix sw-fired i)) (> l 0) (> (secs-since (ix sw-t i)) 0.7)) {
                        (if (sw-hold-act l)
                            { (sw-do l 1) (setix sw-lheld i true) }
                            (sw-do l 2))
                        (setix sw-fired i true)
                })
                (if (and (not on) was) {
                        (if (and (not (ix sw-fired i)) (> l 0)) (sw-do s 2))
                        (if (ix sw-lheld i) { (sw-do l 0) (setix sw-lheld i false) })
                })
            }))
})

; the three position speed switch: off, input 1, input 2
(defun sw-pair-mode (p) (cond ((= p 1) cfg-sw-pm1) ((= p 2) cfg-sw-pm2) (t cfg-sw-pm0)))
(defun sw-pair-go (p) {
        (var m (sw-pair-mode p))
        (if (= m 0) (sw-do 27 1) (sw-do (+ 23 m) 2))
})

(defun sw-read () {
        (var r 0)
        (looprange i 0 core-inputs
            (if (= (gpio-read (ix in-pins i)) 0) (setq r (bitwise-or r (shl 1 i)))))
        r
})

; active inputs: raw, with "open" ones turned round
(defun sw-active (raw) {
        (var inv 0)
        (looprange i 0 core-inputs (if (= (sw-pol i) 1) (setq inv (bitwise-or inv (shl 1 i)))))
        (bitwise-xor raw inv)
})

; the settings page's live test: the inputs and what is on now
(defun sw-mon-send () (send-data (str-merge "IOSW "
        (str-from-n io-sw "%d") " "
        (if aux-left "1" "0") " " (if aux-right "1" "0") " "
        (if aux-hazard "1" "0") " " (if aux-beam "1" "0") " "
        (str-from-n cfg-mode "%d") " "
        (if (dash-sw-ok) "1" "0") " " (if (rx-live) "1" "0") " "
        (if lt-dark "1" "0") " " (if (or lt-brake-man lt-brake) "1" "0"))))

; "SWMON" from the settings page: keep the live test going for 3 s
(defun inputs-app (data)
    (if (and (>= (buflen data) 5) (= (bufget-u8 data 0) 83) (= (bufget-u8 data 1) 87)
             (= (bufget-u8 data 2) 77))
        (def sw-mon-t (systime))))

(defun inputs-start () {
        (def core-inputs (length in-pins))
        (looprange i 0 core-inputs (gpio-configure (ix in-pins i) 'pin-mode-in-pu))
        (if (>= in-led 0) { (gpio-configure in-led 'pin-mode-out) (gpio-write in-led 1) })
        (var last (sw-read))
        (var same 0)
        (var tick 0)
        (var pair-p -1)
        (var dash-was false)
        (loopwhile-thd ("Inputs" 160) t {
                (match (trap (loopwhile t {
                            (var raw (sw-read))
                            (if (= raw last) (setq same (+ same 1)) (setq same 0))
                            (setq last raw)
                            (if (>= same 2) {
                                    (var act (sw-active raw))
                                    (var was io-sw)
                                    (def io-sw act)
                                    ; hazards as they were before the first input
                                    ; of a press went down (see the both-inputs case)
                                    (if (and (= was 0) (!= act 0)) (def sw-haz0 aux-hazard))
                                    (if (= cfg-sw-pair 1) {
                                            ; a position is input 1, input 2 or neither
                                            (var p (cond ((= (bitwise-and act 1) 1) 1)
                                                         ((= (bitwise-and act 2) 2) 2) (t 0)))
                                            ; and the display, once it is there, is told
                                            ; where the switch already is
                                            (var dn (dash-sw-ok))
                                            (if (or (!= p pair-p) (and dn (not dash-was)))
                                                { (setq pair-p p) (sw-pair-go p) })
                                            (setq dash-was dn)
                                    } {
                                            (setq pair-p -1)
                                            (var b1 (= (bitwise-and act 1) 1))
                                            (var b2 (= (bitwise-and act 2) 2))
                                            ; two signal buttons together are hazards: undo
                                            ; the one that went first, and nothing more
                                            ; until both are let go
                                            (if (and b1 b2 (not sw-both)
                                                     (= cfg-sw1-type 0) (= cfg-sw2-type 0)
                                                     (or (and (= cfg-sw1-s 8) (= cfg-sw2-s 9))
                                                         (and (= cfg-sw1-s 9) (= cfg-sw2-s 8)))) {
                                                    (def sw-both true)
                                                    (setix sw-fired 0 true) (setix sw-fired 1 true)
                                                    ; the input that went first has toggled its
                                                    ; signal, which also cleared hazards: set
                                                    ; them from how they were before it
                                                    (sw-do 8 0) (sw-do 9 0)
                                                    (sw-do 10 (if sw-haz0 0 1))
                                            })
                                            (if sw-both {
                                                    (if (and (not b1) (not b2)) (def sw-both false))
                                            } {
                                                    (sw-tick 0 b1 (= (bitwise-and was 1) 1))
                                                    (sw-tick 1 b2 (= (bitwise-and was 2) 2))
                                            })
                                    })
                                    ; a third input stands alone
                                    (if (> core-inputs 2)
                                        (sw-tick 2 (= (bitwise-and act 4) 4) (= (bitwise-and was 4) 4)))
                            })
                            ; the settings page's live test, 20 times a second
                            ; while it is open
                            (if (and (< (secs-since sw-mon-t) 3.0) (= (mod tick 5) 0))
                                (sw-mon-send))
                            ; status LED: steady with the display talking to
                            ; us, a slow blink without one
                            (setq tick (mod (+ tick 1) 100))
                            (if (>= in-led 0) (gpio-write in-led (if (or (rx-live) (< tick 15)) 0 1)))
                            (sleep 0.01) }))
                    ((exit-ok (? a)) nil)
                    (_ (print "inputs thread restarted")))
                (sleep 0.5) })
})

@const-end

(def in-pins nil) (def in-led -1)
(def sw-mon-t 0)         ; when the settings page last asked for the live test
; what each input does - see the core's actions for the numbers
(def cfg-sw1-type 0) (def cfg-sw1-pol 0) (def cfg-sw1-s 8) (def cfg-sw1-l 0)
(def cfg-sw2-type 0) (def cfg-sw2-pol 0) (def cfg-sw2-s 9) (def cfg-sw2-l 0)
(def cfg-sw3-type 0) (def cfg-sw3-pol 0) (def cfg-sw3-s 0) (def cfg-sw3-l 0)
(def cfg-sw-pair 0)      ; 1: inputs 1 and 2 are one three position speed switch
(def cfg-sw-pm0 1) (def cfg-sw-pm1 2) (def cfg-sw-pm2 3)   ; its modes, 0 = N
(def sw-t (list 0 0 0)) (def sw-fired (list nil nil nil)) (def sw-lheld (list nil nil nil))
(def sw-both false) (def sw-haz0 false)
