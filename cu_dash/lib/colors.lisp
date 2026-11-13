;! Palettes, themes and layout import.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; the palette, theme codes and the layout code import and export

@const-start
; --- theme codes ---------------------------------------------------------
; Eleven accent colours, a ground, a pill and a typeface is more than anyone
; wants to set one dropdown at a time, and none of it is guessable from the
; names - the only way to know what a theme looks like is to look at it. So
; it gets built somewhere that can show you, and arrives here as a code.
;
;   CUP1-1E293B-000000-1-05214360521-A7
;   ^    ^      ^      ^ ^           ^
;   |    ground pill   | eleven      checksum
;   prefix        typeface palette indices
;
; Everything that is not a hex digit is ignored after the prefix, so the
; dashes are free and a code can be grouped however it is easiest to read
; out loud. The checksum is there because these do get read out loud.

(def pal-cols (list 0xffffff 0x00ff00 0x00ffff 0x0000ff
                    0xff0000 0xffff00 0xff00ff 0xff8000))

(defun pal (i) (ix pal-cols (bitwise-and i 7)))

(defun pal-ix (c) {
        (var r 0)
        (looprange i 0 8 (if (= (ix pal-cols i) c) (setq r i)))
        r
})

(defun hexv (c) (cond
        ((and (>= c 48) (<= c 57))  (- c 48))
        ((and (>= c 65) (<= c 70))  (- c 55))
        ((and (>= c 97) (<= c 102)) (- c 87))
        (t -1)))

(defun code-digits (s from) {
        (var out nil)
        (looprange i from (str-len s) {
                (var v (hexv (bufget-u8 s i)))
                (if (>= v 0) (setq out (cons v out)))
        })
        (reverse out)
})

(defun dig-n (d from cnt) {
        (var v 0)
        (looprange i 0 cnt (setq v (+ (* v 16) (ix d (+ from i)))))
        v
})

; Rolling rather than a plain sum: a plain sum cannot tell two transposed
; digits apart, and transposing two digits is exactly the mistake someone
; copying this by hand makes.
(defun code-sum (d cnt) {
        (var c 0)
        (looprange i 0 cnt (setq c (mod (+ (* c 31) (ix d i)) 256)))
        c
})

(defun theme-import (code) {
        (var ok (and (>= (str-len code) 4)
                     (= 0 (str-cmp (str-to-upper (str-part code 0 4)) "CUP1"))))
        (var d (if ok (code-digits code 4) nil))
        (var n (if d (length d) 0))
        (var bad (cond
            ((not ok)                                  "not a theme code")
            ((!= n 26)                                 "wrong length")
            ((!= (dig-n d 24 2) (code-sum d 24))       "checksum")
            ((> (ix d 12) 1)                           "unknown typeface")
            (t nil)))
        (if bad { (print (str-merge "THEME:" bad)) false } {
                (var was cfg-font)
                (def cfg-bg-col  (dig-n d 0 6))
                (def cfg-acc-col (dig-n d 6 6))
                (def cfg-font    (ix d 12))
                (def cfg-c-value  (pal (ix d 13)))
                (def cfg-c-unit   (pal (ix d 14)))
                (def cfg-acc-arc  (pal (ix d 15)))
                (def cfg-acc-tl   (pal (ix d 16)))
                (def cfg-acc-tr   (pal (ix d 17)))
                (def cfg-acc-bl   (pal (ix d 18)))
                (def cfg-acc-br   (pal (ix d 19)))
                (def cfg-acc-batt (pal (ix d 20)))
                (def cfg-acc-s6   (pal (ix d 21)))
                (def cfg-acc-s7   (pal (ix d 22)))
                (def cfg-acc-s8   (pal (ix d 23)))
                ; only when it actually changed: a refonts drops every face
                ; and builds them again, which is not something to do to
                ; someone who only picked a different green
                (if (!= was cfg-font) (trap (refonts)))
                (cfg-save)
                (cfg-dump)
                (print "THEME:ok")
                true
        })
})

; A layout is a hundred and sixty nine digits rather than twenty six, because
; it carries where everything sits as well as what colour it is. Same rules:
; a prefix, fixed width fields, non-hex ignored, a rolling checksum last.
;
;   CUPL1 o ssssss mainXY slot1-7XY gaugeXYR barXYW chipXY stripXY
;         sources colours sizes bg acc f cc
;
; Coordinates are three digits each, which covers a 480 wide panel with room
; to spare, and are unsigned - the editor always writes a real position, so
; the -1 that means "let the layout decide" never travels in one of these.

; tl tr bl br gauge bar, the mode chip, the status strip, the four inverted
; bits for the dominant number and slots six to eight, and the dial
(def lay-mask 130028607)

(defun lay-put (d i) (dig-n d i 3))

(defun layout-import (code) {
        (var ok (and (>= (str-len code) 5)
                     (= 0 (str-cmp (str-to-upper (str-part code 0 5)) "CUPL1"))))
        (var d (if ok (code-digits code 5) nil))
        (var n (if d (length d) 0))
        (var bad (cond
            ((not ok)                            "not a layout code")
            ((!= n 169)                          "wrong length")
            ((!= (dig-n d 167 2) (code-sum d 167)) "checksum")
            ((> (ix d 137) 1)                    "unknown typeface")
            (t nil)))
        (if bad { (print (str-merge "THEME:" bad)) false } {
                (var was-f cfg-font)   (var was-sm cfg-fs-sm)
                (var was-lg cfg-fs-lg) (var was-xl cfg-fs-xl)
                (var was-rg cfg-fs-ring)
                (var vert (= (ix d 0) 1))

                ; Only the bits a layout editor owns travel in a code. The
                ; rest - buttons, splash, the reverse flag, everything under
                ; Hardware - stay as they are, because a code built somewhere
                ; that has never seen this display must not switch them off.
                (set-show (bitwise-or
                        (bitwise-and (show-bits) (bitwise-xor lay-mask 134217727))
                        (bitwise-and (dig-n d 1 7) lay-mask)))
                (def cfg-main-x (lay-put d 8))   (def cfg-main-y (lay-put d 11))
                (def cfg-tl-x (lay-put d 14))    (def cfg-tl-y (lay-put d 17))
                (def cfg-tr-x (lay-put d 20))    (def cfg-tr-y (lay-put d 23))
                (def cfg-bl-x (lay-put d 26))    (def cfg-bl-y (lay-put d 29))
                (def cfg-br-x (lay-put d 32))    (def cfg-br-y (lay-put d 35))
                (def cfg-s6-x (lay-put d 38))    (def cfg-s6-y (lay-put d 41))
                (def cfg-s7-x (lay-put d 44))    (def cfg-s7-y (lay-put d 47))
                (def cfg-s8-x (lay-put d 50))    (def cfg-s8-y (lay-put d 53))
                (def cfg-g-x (lay-put d 56))     (def cfg-g-y (lay-put d 59))
                (def cfg-g-r (lay-put d 62))
                (def cfg-bar-x (lay-put d 65))   (def cfg-bar-y (lay-put d 68))
                (def cfg-bar-w (lay-put d 71))
                (def cfg-chip-x (lay-put d 74))  (def cfg-chip-y (lay-put d 77))
                (def cfg-status-x (lay-put d 80)) (def cfg-status-y (lay-put d 83))

                (def cfg-arc-src (dig-n d 86 2))  (def cfg-tl-src (dig-n d 88 2))
                (def cfg-tr-src (dig-n d 90 2))   (def cfg-bl-src (dig-n d 92 2))
                (def cfg-br-src (dig-n d 94 2))   (def cfg-s6-src (dig-n d 96 2))
                (def cfg-s7-src (dig-n d 98 2))   (def cfg-s8-src (dig-n d 100 2))
                (def cfg-bar-fill (dig-n d 102 2))

                (def cfg-acc-arc (pal (ix d 104)))  (def cfg-acc-tl (pal (ix d 105)))
                (def cfg-acc-tr (pal (ix d 106)))   (def cfg-acc-bl (pal (ix d 107)))
                (def cfg-acc-br (pal (ix d 108)))   (def cfg-acc-s6 (pal (ix d 109)))
                (def cfg-acc-s7 (pal (ix d 110)))   (def cfg-acc-s8 (pal (ix d 111)))
                (def cfg-acc-batt (pal (ix d 112)))

                (def cfg-fs-sm (lay-put d 113))   (def cfg-fs-lg (lay-put d 116))
                (def cfg-fs-xl (lay-put d 119))   (def cfg-fs-ring (lay-put d 122))
                (def cfg-bg-col (dig-n d 125 6))
                (def cfg-acc-col (dig-n d 131 6))
                (def cfg-font (ix d 137))
                (def cfg-lbl-main (ix d 138))
                (def cfg-lbl-slot (ix d 139))
                (def cfg-mode-size (dig-n d 140 2))
                (def cfg-dial-x (lay-put d 142)) (def cfg-dial-y (lay-put d 145))
                (def cfg-dial-r (lay-put d 148))
                ; ranges are signed - regen puts amps below zero - so they
                ; travel with a half range offset rather than as raw digits
                (def cfg-arc-min (to-float (- (dig-n d 151 4) 32768)))
                (def cfg-arc-max (to-float (- (dig-n d 155 4) 32768)))
                (def cfg-bar-min (to-float (- (dig-n d 159 4) 32768)))
                (def cfg-bar-max (to-float (- (dig-n d 163 4) 32768)))

                ; the same guards cfg-load applies, because a code can carry a
                ; size or a source this build does not have
                (if (or (< cfg-fs-sm 10) (> cfg-fs-sm 50)) (def cfg-fs-sm 22))
                (if (or (< cfg-fs-lg 20) (> cfg-fs-lg 90)) (def cfg-fs-lg 46))
                (if (or (< cfg-fs-xl 40) (> cfg-fs-xl 260)) (def cfg-fs-xl 124))
                (if (or (< cfg-fs-ring 16) (> cfg-fs-ring 110)) (def cfg-fs-ring 88))
                (if (> cfg-arc-src 25) (def cfg-arc-src 15))
                (if (> cfg-tl-src 25) (def cfg-tl-src 15))
                (if (> cfg-tr-src 25) (def cfg-tr-src 15))
                (if (> cfg-bl-src 25) (def cfg-bl-src 15))
                (if (> cfg-br-src 25) (def cfg-br-src 15))
                (if (> cfg-s6-src 25) (def cfg-s6-src 15))
                (if (> cfg-s7-src 25) (def cfg-s7-src 15))
                (if (> cfg-s8-src 25) (def cfg-s8-src 15))
                (if (> cfg-bar-fill 25) (def cfg-bar-fill 5))
                (if (> cfg-lbl-main 3) (def cfg-lbl-main 1))
                (if (> cfg-lbl-slot 3) (def cfg-lbl-slot 3))
                (if (or (< cfg-mode-size 20) (> cfg-mode-size 90))
                    (def cfg-mode-size 48))
                (if (< cfg-dial-r 24) (def cfg-dial-r 24))
                ; a zero span makes frac divide by nothing, and every gauge
                ; on the screen would sit at its minimum for ever
                (if (< (abs (- cfg-arc-max cfg-arc-min)) 0.001)
                    (def cfg-arc-max (+ cfg-arc-min 1.0)))
                (if (< (abs (- cfg-bar-max cfg-bar-min)) 0.001)
                    (def cfg-bar-max (+ cfg-bar-min 1.0)))
                ; the chip is placed by the layout's own slot in this mode,
                ; so its corner override has to be out of the way
                (def cfg-mode-pos -1) (def cfg-mode-dx 0) (def cfg-mode-dy 0)

                ; Orientation reallocates the frame buffer, so it never goes
                ; through set-show - and it has to happen before the faces are
                ; rebuilt, or they are built against the wrong size.
                (if (not (eq vert cfg-vertical)) (trap (set-vertical vert)))
                (if vert (def cfg-vstyle 7) (def cfg-style 7))
                (if (or (!= was-f cfg-font) (!= was-sm cfg-fs-sm)
                        (!= was-lg cfg-fs-lg) (!= was-xl cfg-fs-xl)
                        (!= was-rg cfg-fs-ring))
                    (trap (refonts)))
                (slots-check)
                (cfg-save)
                (cfg-dump)
                ; positions are not among what the draw loop compares, so a
                ; code that only moves things showed only as each value changed
                (fb-redraw)
                (print "THEME:ok")
                true
        })
})

(defun h3 (v) (str-from-n (clampx (to-i v) 0 4095) "%03X"))
(defun h2 (v) (str-from-n (clampx (to-i v) 0 255) "%02X"))
(defun h4o (v) (str-from-n (clampx (+ (to-i v) 32768) 0 65535) "%04X"))

(defun layout-export () {
        (var b (str-merge
                (if cfg-vertical "1" "0")
                ; seven, not six: the mask reaches bit twenty five, and a
                ; %06X that overflows prints an eighth character and shifts
                ; every field after it
                (str-from-n (bitwise-and (show-bits) lay-mask) "%07X")
                (h3 cfg-main-x) (h3 cfg-main-y)
                (h3 cfg-tl-x) (h3 cfg-tl-y) (h3 cfg-tr-x) (h3 cfg-tr-y)
                (h3 cfg-bl-x) (h3 cfg-bl-y) (h3 cfg-br-x) (h3 cfg-br-y)
                (h3 cfg-s6-x) (h3 cfg-s6-y) (h3 cfg-s7-x) (h3 cfg-s7-y)
                (h3 cfg-s8-x) (h3 cfg-s8-y)
                (h3 cfg-g-x) (h3 cfg-g-y) (h3 cfg-g-r)
                (h3 cfg-bar-x) (h3 cfg-bar-y) (h3 cfg-bar-w)
                (h3 cfg-chip-x) (h3 cfg-chip-y)
                (h3 cfg-status-x) (h3 cfg-status-y)))
        (setq b (str-merge b
                (h2 cfg-arc-src) (h2 cfg-tl-src) (h2 cfg-tr-src) (h2 cfg-bl-src)
                (h2 cfg-br-src) (h2 cfg-s6-src) (h2 cfg-s7-src) (h2 cfg-s8-src)
                (h2 cfg-bar-fill)
                (str-from-n (pal-ix cfg-acc-arc) "%01X")
                (str-from-n (pal-ix cfg-acc-tl) "%01X")
                (str-from-n (pal-ix cfg-acc-tr) "%01X")
                (str-from-n (pal-ix cfg-acc-bl) "%01X")
                (str-from-n (pal-ix cfg-acc-br) "%01X")
                (str-from-n (pal-ix cfg-acc-s6) "%01X")
                (str-from-n (pal-ix cfg-acc-s7) "%01X")
                (str-from-n (pal-ix cfg-acc-s8) "%01X")
                (str-from-n (pal-ix cfg-acc-batt) "%01X")))
        (setq b (str-merge b
                (h3 cfg-fs-sm) (h3 cfg-fs-lg) (h3 cfg-fs-xl) (h3 cfg-fs-ring)
                (str-from-n cfg-bg-col "%06X") (str-from-n cfg-acc-col "%06X")
                (str-from-n cfg-font "%01X")
                (str-from-n cfg-lbl-main "%01X") (str-from-n cfg-lbl-slot "%01X")
                (h2 cfg-mode-size)
                (h3 cfg-dial-x) (h3 cfg-dial-y) (h3 cfg-dial-r)
                (h4o cfg-arc-min) (h4o cfg-arc-max)
                (h4o cfg-bar-min) (h4o cfg-bar-max)))
        (var c (str-merge b (str-from-n (code-sum (code-digits b 0) 167) "%02X")))
        (print (str-merge "THEMEOUT:CUPL1" c))
        c
})

; One box in the settings page for both, since nobody wants to think about
; which kind of code they were handed.
(defun cu-import (code) {
        (if (and (>= (str-len code) 5)
                 (= 0 (str-cmp (str-to-upper (str-part code 0 5)) "CUPL1")))
            (layout-import code)
            (theme-import code))
})

; The reverse, so a display that is already set up can hand its theme to the
; builder page or to somebody else.
(defun theme-export () {
        (var b (str-merge
                (str-from-n cfg-bg-col "%06X")
                (str-from-n cfg-acc-col "%06X")
                (str-from-n cfg-font "%01X")
                (str-from-n (pal-ix cfg-c-value) "%01X")
                (str-from-n (pal-ix cfg-c-unit) "%01X")
                (str-from-n (pal-ix cfg-acc-arc) "%01X")
                (str-from-n (pal-ix cfg-acc-tl) "%01X")
                (str-from-n (pal-ix cfg-acc-tr) "%01X")
                (str-from-n (pal-ix cfg-acc-bl) "%01X")
                (str-from-n (pal-ix cfg-acc-br) "%01X")
                (str-from-n (pal-ix cfg-acc-batt) "%01X")
                (str-from-n (pal-ix cfg-acc-s6) "%01X")
                (str-from-n (pal-ix cfg-acc-s7) "%01X")
                (str-from-n (pal-ix cfg-acc-s8) "%01X")))
        (var c (str-merge b (str-from-n (code-sum (code-digits b 0) 24) "%02X")))
        (print (str-merge "THEMEOUT:CUP1" c))
        c
})


@const-end
