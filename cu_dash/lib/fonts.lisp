;! Fonts.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; the glyph subset and the face loader

@const-start
(defun u8s (a b c) {
        (var q (bufcreate 4))
        (bufset-u8 q 0 a) (bufset-u8 q 1 b) (bufset-u8 q 2 c) (bufset-u8 q 3 0)
        q
})
(def glyphs " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./%-?")
; The numeric faces carry three letters beyond the digits. N and R are the
; gear chip; V is the portrait cart layout, which sets its voltage line in
; the ring face rather than the small one; D is road mode. One glyph across
; three faces is cheaper than a seventh face, and a face missing a character
; the chip wants does not degrade - ttf-text throws and takes the frame with
; it, which is how this one was found.
; The percent sign is here because the charge screen sets its number in
; this face and a subset that cannot draw one throws inside ttf-text - the
; same way a D, a comma and an apostrophe each did. Cheap to carry, and the
; alternative is a second draw in a different face just to place one glyph.
(def glyphs-num "0123456789.- NRVD%")

(defun fonts-try (aa) {
        ; Montserrat is here for the cart layout, which is a port of a screen
        ; set in it; on any other layout it is just a second face to pick.
        (def font-ttf (if (= cfg-font 1) font-montserrat font-rajdhani))
        (var f (if aa 'indexed16 'indexed2))
        (def font-sm (ttf-prepare font-ttf cfg-fs-sm f glyphs))
        ; Controls keep a readable, bounded size regardless of the ride layout.
        (def font-ui (ttf-prepare font-ttf 18 f glyphs))
        (def font-md (ttf-prepare font-ttf (+ cfg-fs-sm 10) f glyphs))
        (def font-lg (ttf-prepare font-ttf cfg-fs-lg f glyphs-num))
        ; Antialiased glyphs cost about 0.29 bytes per pixel against 0.07 for
        ; one bit, so a very large face has to drop to hard edges or it will
        ; not fit beside the framebuffer. On a digit this size the difference
        ; is barely visible, whereas the extra height is obvious.
        (def font-xl (ttf-prepare font-ttf cfg-fs-xl
                     (if (> cfg-fs-xl 170) 'indexed2 f) glyphs-num))
        (def font-ring (ttf-prepare font-ttf cfg-fs-ring f glyphs-num))
        (def font-ico (ttf-prepare font-icons-ttf cfg-icon-size f ico-all))
        ; last, so it means the faces are there rather than that we started
        (def fonts-ready true)
        true
})

(defun fonts-init () {
        (if fonts-ready (print "refonts"))
        (var r (trap (fonts-try cfg-aa)))
        (if (eq (car r) 'exit-ok) true {
                ; not enough room for antialiased faces - fall back
                ; ramp-build reads this to decide how many entries a colour
                ; ramp gets. It has to match the faces actually prepared below,
                ; or one bit glyphs index into a sixteen colour ramp and the
                ; text comes out corrupted rather than merely hard edged.
                (print "font memory tight, dropping to hard edged text")
                (def cfg-aa false)
                (trap (gc))
                (var r2 (trap (fonts-try false)))
                ; Both attempts gone means no faces at all, and the draw thread
                ; now stands down when that is the case - which would be a blank
                ; panel with no way back. Fall all the way to the default sizes,
                ; which are known to fit, rather than leave it there.
                (if (eq (car r2) 'exit-ok) true {
                        (print "falling back to default font sizes")
                        (def cfg-fs-sm 22) (def cfg-fs-lg 46)
                        (def cfg-fs-xl 124) (def cfg-fs-ring 88)
                        (def cfg-icon-size 26)
                        (trap (gc))
                        (car (trap (fonts-try false)))
                })
        })
})
; The old faces have to go before the new ones are built, or the peak is both
; sets at once and a size that fits on its own fails here.
(defun refonts () {
        (def fonts-ready false)
        ; draw-frame checks that flag on entry, so a frame already past the
        ; check is still holding the faces. Let it finish before they go, or
        ; it draws with nil and takes the thread down with it.
        (sleep 0.3)
        (trap (ramp-flush))
        (def font-sm nil) (def font-ui nil) (def font-md nil) (def font-lg nil)
        (def font-xl nil) (def font-ring nil) (def font-ico nil)
        ; The repaint records hold the face each text was drawn in, so with
        ; them kept the old faces could not be collected and the peak was
        ; both sets after all; and the mode chip's cached image is keyed on
        ; its label, not its face, so it kept the old lettering. Both go; the
        ; next frame is a full repaint that records afresh (review 2026-10-24).
        (def tc-rec nil) (def tc-bx nil) (def tc-n 0) (def tc-acc nil)
        (def tb-rec nil) (def tb-n 0) (def tb-acc nil)
        (def chip-im nil) (def chip-key nil) (def chip-ink nil)
        (def fb-dirty true)
        (trap (gc))
        ; Retry smooth every rebuild. The fallback below is about what fits at
        ; one particular set of sizes, so a size that dropped to hard edges must
        ; not hold every later rebuild down with it.
        (def cfg-aa true)
        (trap (fonts-init))
})


@const-end
