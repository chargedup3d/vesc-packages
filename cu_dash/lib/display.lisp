;! Display setup, framebuffer and page transitions.
; lib/display.lisp - JC3248W535C panel driver
; verified: AXS15231B QSPI, vendor init required, backlight GPIO1,
; orientation 3 = 480x320, panel swaps GREEN/BLUE, full-frame blit only.

@const-start
(def disp-w 480)
(def disp-h 320)

; The current AXS15231B driver needs no correction, so this is identity.
; Earlier builds read rgb565 buffers back with the opposite byte order to the
; one they wrote and also swapped red and blue; the compensating transforms
; are written out in the porting guide if you meet that. Worth knowing: a
; grey ramp cannot detect a channel swap, since greys have equal channels.
; Check a red, a green and a blue swatch instead.
(defun col (c) c)

(defun dc (r d) (if (> d 0) (sleep (/ d 1000.0))))

(defun display-init () {
        (disp-load-axs15231 21 48 40 39 47 45 -1 40)
        ; Backlight stays off through panel init. The panel holds whatever
        ; was in its RAM at power up, and lighting it before there is a
        ; frame to show is what put static on screen at boot. The boot splash
        ; and bl-apply own the backlight.
        (gpio-configure 1 'pin-mode-out)
        (gpio-write 1 0)
        (dc (trap (ext-disp-cmd 0xbb 0x00 0x00 0x00 0x00 0x00 0x00 0x5a 0xa5)) 0)
        (dc (trap (ext-disp-cmd 0xa0
                0x00 0x10 0x00 0x02 0x00 0x00 0x64 0x3f 0x20 0x05
                0x3f 0x3f 0x00 0x00 0x00 0x00 0x00
            )) 0)
        (dc (trap (ext-disp-cmd 0xa2
                0x30 0x04 0x0a 0x3c 0xec 0x54 0xc4 0x30 0xac 0x28
                0x7f 0x7f 0x7f 0x20 0xf8 0x10 0x02 0xff 0xff 0xf0
                0x90 0x01 0x32 0xa0 0x91 0xc0 0x20 0x7f 0xff 0x00
                0x54
            )) 0)
        (dc (trap (ext-disp-cmd 0xd0
                0x30 0xac 0x21 0x24 0x08 0x09 0x10 0x01 0xaa 0x14
                0xc2 0x00 0x22 0x22 0xaa 0x03 0x10 0x12 0x40 0x14
                0x1e 0x51 0x15 0x00 0x40 0x10 0x00 0x03 0x3d 0x12
            )) 0)
        (dc (trap (ext-disp-cmd 0xa3
                0xa0 0x06 0xaa 0x08 0x08 0x02 0x0a 0x04 0x04 0x04
                0x04 0x04 0x04 0x04 0x04 0x04 0x04 0x04 0x04 0x00
                0x55 0x55
            )) 0)
        (dc (trap (ext-disp-cmd 0xc1
                0x33 0x04 0x02 0x02 0x71 0x05 0x24 0x55 0x02 0x00
                0x41 0x00 0x53 0xff 0xff 0xff 0x4f 0x52 0x00 0x4f
                0x52 0x00 0x45 0x3b 0x0b 0x02 0x0d 0x00 0xff 0x40
            )) 0)
        (dc (trap (ext-disp-cmd 0xc3
                0x00 0x00 0x00 0x50 0x03 0x00 0x00 0x00 0x01 0x80
                0x01
            )) 0)
        (dc (trap (ext-disp-cmd 0xc4
                0x00 0x24 0x33 0x90 0x50 0xea 0x64 0x32 0xc8 0x64
                0xc8 0x32 0x90 0x90 0x11 0x06 0xdc 0xfa 0x04 0x03
                0x80 0xfe 0x10 0x10 0x00 0x0a 0x0a 0x44 0x50
            )) 0)
        (dc (trap (ext-disp-cmd 0xc5
                0x18 0x00 0x00 0x03 0xfe 0x78 0x33 0x20 0x30 0x10
                0x88 0xde 0x0d 0x08 0x0f 0x0f 0x01 0x78 0x33 0x20
                0x10 0x10 0x80
            )) 0)
        (dc (trap (ext-disp-cmd 0xc6
                0x05 0x0a 0x05 0x0a 0x00 0xe0 0x2e 0x0b 0x12 0x22
                0x12 0x22 0x01 0x00 0x00 0x3f 0x6a 0x18 0xc8 0x22
            )) 0)
        (dc (trap (ext-disp-cmd 0xc7
                0x50 0x32 0x28 0x00 0xa2 0x80 0x8f 0x00 0x80 0xff
                0x07 0x11 0x9f 0x6f 0xff 0x26 0x0c 0x0d 0x0e 0x0f
            )) 0)
        (dc (trap (ext-disp-cmd 0xc9 0x33 0x44 0x44 0x01)) 0)
        (dc (trap (ext-disp-cmd 0xcf
                0x34 0x1e 0x88 0x58 0x13 0x18 0x56 0x18 0x1e 0x68
                0xf7 0x00 0x65 0x0c 0x22 0xc4 0x0c 0x77 0x22 0x44
                0xaa 0x55 0x04 0x04 0x12 0xa0 0x08
            )) 0)
        (dc (trap (ext-disp-cmd 0xd5
                0x3e 0x3e 0x88 0x00 0x44 0x04 0x78 0x33 0x20 0x78
                0x33 0x20 0x04 0x28 0xd3 0x47 0x03 0x03 0x03 0x03
                0x86 0x00 0x00 0x00 0x30 0x52 0x3f 0x40 0x40 0x96
            )) 0)
        (dc (trap (ext-disp-cmd 0xd6
                0x10 0x32 0x54 0x76 0x98 0xba 0xdc 0xfe 0x95 0x00
                0x01 0x83 0x75 0x36 0x20 0x75 0x36 0x20 0x3f 0x03
                0x03 0x03 0x10 0x10 0x00 0x04 0x51 0x20 0x01 0x00
            )) 0)
        (dc (trap (ext-disp-cmd 0xd7
                0x0a 0x08 0x0e 0x0c 0x1e 0x18 0x19 0x1f 0x00 0x1f
                0x1a 0x1f 0x3e 0x3e 0x04 0x00 0x1f 0x1f 0x1f
            )) 0)
        (dc (trap (ext-disp-cmd 0xd8
                0x0b 0x09 0x0f 0x0d 0x1e 0x18 0x19 0x1f 0x01 0x1f
                0x1a 0x1f
            )) 0)
        (dc (trap (ext-disp-cmd 0xd9
                0x00 0x0d 0x0f 0x09 0x0b 0x1f 0x18 0x19 0x1f 0x01
                0x1e 0x1a 0x1f
            )) 0)
        (dc (trap (ext-disp-cmd 0xdd
                0x0c 0x0e 0x08 0x0a 0x1f 0x18 0x19 0x1f 0x00 0x1e
                0x1a 0x1f
            )) 0)
        (dc (trap (ext-disp-cmd 0xdf 0x44 0x73 0x4b 0x69 0x00 0x0a 0x02 0x90)) 0)
        (dc (trap (ext-disp-cmd 0xe0
                0x19 0x20 0x0a 0x13 0x0e 0x09 0x12 0x28 0xd4 0x24
                0x0c 0x35 0x13 0x31 0x36 0x2f 0x03
            )) 0)
        (dc (trap (ext-disp-cmd 0xe1
                0x38 0x20 0x09 0x12 0x0e 0x08 0x12 0x28 0xc5 0x24
                0x0c 0x34 0x12 0x31 0x36 0x2f 0x27
            )) 0)
        (dc (trap (ext-disp-cmd 0xe2
                0x19 0x20 0x0a 0x11 0x09 0x06 0x11 0x25 0xd4 0x22
                0x0b 0x33 0x12 0x2d 0x32 0x2f 0x03
            )) 0)
        (dc (trap (ext-disp-cmd 0xe3
                0x38 0x20 0x0a 0x11 0x09 0x06 0x11 0x25 0xc4 0x21
                0x0a 0x32 0x11 0x2c 0x32 0x2f 0x27
            )) 0)
        (dc (trap (ext-disp-cmd 0xe4
                0x19 0x20 0x0d 0x14 0x0d 0x08 0x12 0x2a 0xd4 0x26
                0x0e 0x35 0x13 0x34 0x39 0x2f 0x03
            )) 0)
        (dc (trap (ext-disp-cmd 0xe5
                0x38 0x20 0x0d 0x13 0x0d 0x07 0x12 0x29 0xc4 0x25
                0x0d 0x35 0x12 0x33 0x39 0x2f 0x27
            )) 0)
        (dc (trap (ext-disp-cmd 0xbb 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00)) 0)
        (dc (trap (ext-disp-cmd 0x13)) 0)
        (dc (trap (ext-disp-cmd 0x11)) 200)
        (dc (trap (ext-disp-cmd 0x29)) 200)
        (dc (trap (ext-disp-cmd 0x2c 0x00 0x00 0x00 0x00)) 0)
        (dc (trap (ext-disp-cmd 0x13)) 20)
        (dc (trap (ext-disp-cmd 0x29)) 50)
        (ext-disp-orientation 3)
})
@const-end

; Set while the draw thread is inside a frame, and while a buffer swap
; wants it to stay out of one. See fb-alloc.
(def fb-drawing false)
(def fb-hold false)

(def fb nil)
(def fb-pool nil)

; page slide state - see page-step
(def slide-req nil)
(def slide-dir 0)
(def slide-img nil)
(def slide-fw nil)
(def slide-from 0)
(def slide-drag nil)
; the finger, while a swipe is being dragged: see touch-thread
(def drag-on nil)
(def drag-off 0)
(def drag-commit nil)

@const-start
(def fb-w 480)
(def fb-h 320)

; Only one framebuffer fits in the arena (307200 bytes of about 470k), so
; switching orientation drops the old buffer, collects, and reallocates.
(defun fb-alloc (w h) {
        ; the old buffer has to go before the new one will fit, so there is a
        ; window where fb is nil. The draw thread checks for that. Retries a
        ; few times because the collector may need a moment.
        ;
        ; That check is at the top of the frame and the frame takes many
        ; milliseconds, so on its own it is a snapshot rather than a guard:
        ; the buffer can vanish, or change shape, half way down a frame that
        ; already passed the test. Rotating the display reliably produced a
        ; trapped type_error and a lost string that way. So ask the draw
        ; thread to stand off, and wait for it to say it is out of the frame
        ; before touching anything. Bounded, because a draw that threw will
        ; never lower the flag and a stuck rotation is worse than a torn one.
        (def fb-hold true)
        (var waited 0)
        (loopwhile (and fb-drawing (< waited 50)) {
                (sleep 0.01)
                (setq waited (+ waited 1))
        })
        (def fb nil)
        (def fb-pool nil)
        (trap (gc))
        (var got false)
        (looprange i 0 4 {
                (if (not got) {
                        (var r (trap (dm-create 330000)))
                        (if (eq (car r) 'exit-ok) {
                                (def fb-pool (car (cdr r)))
                                (def fb (img-buffer fb-pool 'rgb565 w h))
                                (def fb-w w)
                                (def fb-h h)
                                (img-clear fb)
                                (setq got true)
                        } { (trap (gc)) (sleep 0.15) })
                })
        })
        (if (not got) (print "framebuffer alloc failed"))
        ; whatever happened, let the draw thread back in
        (def fb-hold false)
        got
})

(defun fb-use (vertical)
    (if vertical (fb-alloc 320 480) (fb-alloc 480 320)))

(defun fb-flush () {
        ; trapped and cleared here rather than inside: a slide that threw
        ; would otherwise stay asked for and throw again every frame
        (if (!= slide-dir 0) {
                (trap (slide-run))
                (def slide-dir 0)
                (def slide-img nil)
        })
        (disp-render fb 0 0)
        (def fb-frames (+ fb-frames 1))
})

;; --- page slide ------------------------------------------------------------
;;
;; A swipe or a page button asks for a page rather than setting it. The draw
;; thread takes the request at the top of a frame, where fb still holds
;; exactly what the glass shows, copies it aside, paints the new page into fb
;; the way any page change does, and the flush slides the old page out and
;; the new one in. The two are composed by the driver while it stages the
;; frame for DMA (ext-disp-slide), so a slide frame costs one plain flush,
;; about 17ms, where composing it in lisp cost 76 to 93ms.
;;
;; The copy borrows the repair pool: nothing is repaired on the frame a page
;; is entered, and the collect afterwards hands the space straight back.
;; Firmware without the extension, or no room for the copy, switches page the
;; way it always did.
;;
;; A drag asks as soon as the finger has clearly gone sideways, so the new
;; page is painted while the finger is still moving; the slide then follows
;; the finger, and letting go either finishes it or puts the old page back.
(def slide-secs 0.16)
(def slide-reveal-fw nil)

(defun page-step-d (d drag) (if (and (= page (pg-setup)) (> setup-view 0))
    ; A child swipe goes back on release. Never dismiss an active check.
    (if (not drag) (setup-back)) {
        (var n (page-count))
        (var base (if slide-req (ix slide-req 0) page))
        (var np (mod (+ base n d) n))
        ; Opposite queued swipes cancel; do not leave the earlier request
        ; waiting when the combined destination is the current page.
        (def slide-req (if (!= np page) (list np d drag) nil))
}))

(defun page-step (d) (page-step-d d nil))

; whether this firmware can slide at all
(defun slide-can () {
        (if (eq slide-fw nil)
            (def slide-fw (if (eq (car (trap ext-disp-slide)) 'exit-ok) 1 0)))
        (= slide-fw 1)
})

(defun slide-grab () (if (slide-can) {
        (if (eq tc-pool nil) {
                (var p (trap (dm-create 330000)))
                (if (eq (car p) 'exit-ok) (def tc-pool (car (cdr p))))
        })
        (var r (if tc-pool (trap (img-buffer tc-pool 'rgb565 fb-w fb-h)) nil))
        (if (and tc-pool (not-eq (car r) 'exit-ok)) {
                (trap (gc))
                (setq r (trap (img-buffer tc-pool 'rgb565 fb-w fb-h)))
        })
        (if (eq (car r) 'exit-ok) {
                (def slide-img (car (cdr r)))
                (bufcpy slide-img 0 fb 0 (buflen fb))
                true
        } nil)
} nil))

; called by the draw thread before it draws anything
(defun slide-take () {
        (var r slide-req)
        (def slide-req nil)
        (def slide-from page)
        (def slide-drag (ix r 2))
        (if (and (not ble-pick) (not quick-open) (slide-grab))
            (def slide-dir (ix r 1)))
        (def page (ix r 0))
})

; Native layered reveal when supported. Older firmware keeps the original
; slide. A rejected reveal falls back in the same frame and is not retried.
(defun slide-show (fwd a b pos) {
    (if (eq slide-reveal-fw nil)
        (def slide-reveal-fw (if (eq (car (trap ext-disp-reveal)) 'exit-ok) 1 0)))
    (var r nil)
    (if (= slide-reveal-fw 1) {
        (setq r (trap (ext-disp-reveal (if fwd a b) (if fwd b a)
            (to-i pos) (if fwd 1 -1))))
        (if (not (and (eq (car r) 'exit-ok) (car (cdr r)))) (def slide-reveal-fw 0))
    })
    (if (= slide-reveal-fw 0)
        (setq r (trap (ext-disp-slide a b (if fwd (to-i pos) (- fb-w (to-i pos)))))))
    (and (eq (car r) 'exit-ok) (car (cdr r)))
})

(defun slide-run () {
        (var fwd (> slide-dir 0))
        (var a (if fwd slide-img fb))
        (var b (if fwd fb slide-img))
        (var w (to-float fb-w))
        (var pos 0.0)
        (var ok true)
        (var t0 (systime))
        ; with the finger: eased toward it, since the page is usually ready
        ; only after the finger has already gone some way. Bounded, so a
        ; touch thread that died mid drag cannot hold the screen.
        (loopwhile (and ok drag-on slide-drag (< (secs-since t0) 5.0)) {
                (var tg (if (> drag-off fb-w) w (to-float drag-off)))
                (var np (+ pos (* 0.5 (- tg pos))))
                (if (> (abs (- np pos)) 0.5)
                    { (setq pos np) (setq ok (slide-show fwd a b pos)) }
                    (sleep 0.01))
        })
        (var back (and slide-drag (not drag-commit)))
        (var from pos)
        (var span (- (if back 0.0 w) from))
        (var secs (* slide-secs (/ (abs span) w)))
        (if (< secs 0.08) (setq secs 0.08))
        (setq t0 (systime))
        ; A later swipe should not wait for this page to finish settling.
        (loopwhile (and ok (not slide-req) (< (secs-since t0) secs)) {
                (var q (- 1.0 (/ (secs-since t0) secs)))
                (setq ok (slide-show fwd a b (+ from (* span (- 1.0 (* q q q))))))
        })
        ; let go early: the old page goes back as it was, and is repainted
        ; next frame since the page it is on changes back
        (if back {
                (bufcpy fb 0 slide-img 0 (buflen fb))
                (def page slide-from)
        })
        (def slide-dir 0)
        (def slide-img nil)
        (trap (gc))
})

;; --- drawing only what changed, for every layout -------------------------
;;
;; A layout draws the same things in the same order every pass. So the pass
;; that paints the whole screen records each text and shape it draws, and the
;; passes after it run the same layout code in compare mode: a call that
;; matches its record is skipped, a text that changed has just its own old box
;; wiped and is drawn again. The panel takes no partial windows, so the frame
;; still goes out whole - but only when something changed, and the drawing
;; that fed it is a few texts instead of all of them.
;;
;; A shape that changed - a meter moving, a needle - cannot be undrawn in
;; place without knowing what was under it, so it makes the frame a full
;; repaint instead (tc-restart), done before the flush so the glass never
;; sees a half updated frame. Widgets that move often earn their own update
;; path later; correctness does not depend on it.
;;
;; tc-mode: 0 draw normally, 1 draw and record, 2 compare
(def tc-mode 0)
(def tc-i 0)
(def tc-n 0)
(def tc-rec nil)
; each record's box, computed once when it is recorded or changed
(def tc-bx nil)
(def tc-acc nil)
(def tc-restart false)
(def tc-bg 0)
; why the last compare pass fell back to a repaint - for tuning, costs nothing
(def tc-why nil)

(defun tc-get (i) (if (< i tc-n) (ix tc-rec i) nil))

; true when a shape with this signature should be drawn now
(defun tc-p (sig) (cond
        ((= tc-mode 0) true)
        ((= tc-mode 1) {
                (def tc-acc (cons sig tc-acc))
                (def tc-i (+ tc-i 1))
                true
        })
        (tc-restart false)
        (t {
                (var i tc-i)
                (var r (tc-get i))
                (def tc-i (+ i 1))
                (cond
                    ((eq r sig) false)
                    ; a text where a shape should be means the layout drew a
                    ; different set of things; any shape for any shape - a
                    ; bar that appeared, an arc that grew - is just a change
                    ((or (eq r nil) (eq (ix r 0) 't)) {
                            (def tc-restart true)
                            (def tc-why (list "shape out of step" sig))
                            false
                    })
                    ; A shape that moved or changed colour: wipe where it was
                    ; and where it will be, then draw again, in order,
                    ; everything recorded in that box - this shape included.
                    ; Returns false because the repair has drawn it.
                    (t {
                            ; An arc that only grew or shrank - same centre, radius,
                            ; width, start and colour - damages just the part of the
                            ; circle between its old and new ends, not its whole box.
                            ; On a gauge the whole box is most of the layout.
                            (if (and (eq (ix r 0) 'a) (eq (ix sig 0) 'a)
                                     (= (ix r 1) (ix sig 1)) (= (ix r 2) (ix sig 2))
                                     (= (ix r 3) (ix sig 3)) (= (ix r 4) (ix sig 4))
                                     (= (ix r 6) (ix sig 6)) (= (ix r 7) (ix sig 7))) {
                                    (setix tc-rec i sig)
                                    (setix tc-bx i (tc-box sig))
                                    (var sb (arc-sweep-box (ix sig 1) (ix sig 2) (ix sig 3) (ix sig 7)
                                                           (ix r 5) (ix sig 5)))
                                    (tc-damage (ix sb 0) (ix sb 1) (ix sb 2) (ix sb 3))
                            } {
                            ; a placeholder covers nothing, so the box is the other one
                            (var ob (tc-box (if (eq (ix r 0) 'n) sig r)))
                            (setix tc-rec i sig)
                            (setix tc-bx i (tc-box sig))
                            (var nb (tc-box (if (eq (ix sig 0) 'n) r sig)))
                            (tc-damage (min-i (ix ob 0) (ix nb 0)) (min-i (ix ob 1) (ix nb 1))
                                       (max-i (ix ob 2) (ix nb 2)) (max-i (ix ob 3) (ix nb 3)))
                            })
                            false
                    }))
        })))

;; Blocks. A helper that draws a stat, a meter or a gauge from one value is
;; wrapped in tc-block with that value, rounded finer than it is shown, as
;; its key. In compare mode a block whose key has not changed is skipped
;; whole - none of its strings built, none of its records compared - and the
;; record index jumps past what it drew. A block that did change runs as
;; normal, so its elements are still compared one by one and exactness never
;; rests on the key. Settings that change how a block draws are not in its
;; key; a settings change repaints the screen (disp-cfg in view_pages).
;;
;; Each block record is (key first-record record-count blocks-inside), kept
;; in the order blocks start, so a skipped block also skips the blocks nested
;; in it.
(def tb-rec nil)
(def tb-acc nil)
(def tb-i 0)
(def tb-n 0)
(def tb-seen 0)

; 15 is "off" in every slot, and not a source src-val knows
(defun qv (src) (if (= src 15) 0 (to-i (* 100.0 (src-val src)))))

(defun tc-block (key f) (cond
        ((= tc-mode 0) (f))
        ((= tc-mode 1) {
                (var rec (list key tc-i 0 0))
                (var b0 tb-seen)
                (def tb-seen (+ tb-seen 1))
                (def tb-acc (cons rec tb-acc))
                (f)
                (setix rec 2 (- tc-i (ix rec 1)))
                (setix rec 3 (- tb-seen b0 1))
        })
        (tc-restart nil)
        (t {
                (var i tb-i)
                (def tb-i (+ i 1))
                (var r (if (< i tb-n) (ix tb-rec i) nil))
                (if (and r (eq (ix r 0) key) (= (ix r 1) tc-i)) {
                        (def tc-i (+ tc-i (ix r 2)))
                        (def tb-i (+ tb-i (ix r 3)))
                } (if (and r (= (ix r 1) tc-i)) {
                        (setix r 0 key)
                        (f)
                } {
                        (def tc-restart true)
                        (def tc-why (list "block out of step" i))
                }))
        })))

;; Where a layout draws something only for some values - a fill that is not
;; there at zero - it records a placeholder the rest of the time, so the
;; sequence keeps its length and the fill appearing is an ordinary change.
(defun tc-skip () (tc-p (list 'n)))

(defun box (x y w h c)
    (if (tc-p (list 'b x y w h c)) (img-rectangle fb x y w h (col c) '(filled))))
(defun rbox (x y w h r c)
    (if (tc-p (list 'rb x y w h r c))
        (img-rectangle fb x y w h (col c) (list 'rounded r) '(filled))))
; The mode chip, smooth. img-rectangle's rounded corners are stepped and leave
; stray pixels where the curve meets the straight edge, and the label was
; smoothed against the screen's background rather than the chip, so its edge
; pixels came out in the wrong colour - the chip looked low resolution next to
; everything else (Jeremy, 2026-10-24). So the chip is built once into an image
; of its own: corners shaded by how much of each pixel the curve covers, the
; label smoothed from the chip's colour to its own. It is copied to the frame
; and only built again when something on it changes.
(defun chip-cov (px py r) {
        ; 4x4 samples of the pixel against a quarter circle centred at (r, r)
        (var n 0)
        (looprange sy 0 4 (looprange sx 0 4 {
                (var dx (- r (+ px (/ (+ sx 0.5) 4.0))))
                (var dy (- r (+ py (/ (+ sy 0.5) 4.0))))
                (if (<= (+ (* dx dx) (* dy dy)) (* r r)) (setq n (+ n 1)))
        }))
        (/ (to-float n) 16.0)
})

; Building a chip cost about half a second the first time on each layout and
; on every mode change, which changes its colour (bench, 2026-10-24): the
; corner coverage (16 samples a pixel) and the scan for the label's ink were
; done again each time, though neither depends on the colour. The coverage
; depends only on the radius and the ink only on the label, size and face,
; so both are kept; the ink is forgotten when the faces are rebuilt.
(def chip-cov-r -1) (def chip-cov-tab nil)
(def chip-ink nil)
(defun chip-covs (rad) {
        (if (!= rad chip-cov-r) {
                (var t2 nil)
                (looprange py 0 rad (looprange px 0 rad
                    (setq t2 (cons (chip-cov px py rad) t2))))
                (def chip-cov-tab (reverse t2))
                (def chip-cov-r rad)
        })
        chip-cov-tab
})

(defun chip-image (sz rad c tcol font label) {
        (var key (list sz rad c tcol label theme-bg cfg-aa))
        (if (not (eq key chip-key)) {
                (def chip-im nil)
                (var im (img-buffer 'rgb565 sz sz))
                (img-clear im (col theme-bg))
                (img-rectangle im rad 0 (- sz (* 2 rad)) sz (col c) '(filled))
                (img-rectangle im 0 rad sz (- sz (* 2 rad)) (col c) '(filled))
                (var covs (chip-covs rad))
                (looprange py 0 rad (looprange px 0 rad {
                        (var a (car covs)) (setq covs (cdr covs))
                        (if (> a 0.0) {
                                (var pc (col (mix-col theme-bg c a)))
                                (img-setpix im px py pc)
                                (img-setpix im (- sz 1 px) py pc)
                                (img-setpix im px (- sz 1 py) pc)
                                (img-setpix im (- sz 1 px) (- sz 1 py) pc)
                        })
                }))
                (var k (str-clean label))
                (var ik (list k sz (eq font font-sm)))
                (var pos (assoc chip-ink ik))
                (if (not pos) {
                        (var w (ix (tdim-k font k) 0))
                        (var tx (- (/ sz 2) (/ w 2)))
                        (var ty (- sz (/ sz 4)))
                        ; The advance width and a fixed baseline put the digit a few
                        ; pixels off centre (Jeremy, 2026-10-24). Draw it once on a
                        ; scratch image, find where its ink is, and move it by the
                        ; difference.
                        (var probe (img-buffer 'rgb565 sz sz))
                        (img-clear probe 0)
                        (trap (ttf-text probe tx ty (map (fn (i) (* i 0x111111)) (range 16)) font k))
                        (var x0 sz) (var x1 -1) (var y0 sz) (var y1 -1)
                        (looprange py 0 sz (looprange px 0 sz
                            (if (!= (img-getpix probe px py) 0) {
                                    (if (< px x0) (setq x0 px)) (if (> px x1) (setq x1 px))
                                    (if (< py y0) (setq y0 py)) (if (> py y1) (setq y1 py))
                            })))
                        (setq probe nil)
                        (if (>= x1 0) {
                                (setq tx (+ tx (/ (- (- sz 1 x1) x0) 2)))
                                (setq ty (+ ty (/ (- (- sz 1 y1) y0) 2)))
                        })
                        (setq pos (list tx ty))
                        ; a handful of labels (R N 1 2 3, or the mode names)
                        (def chip-ink (cons (cons ik pos) (if (> (length chip-ink) 12) nil chip-ink)))
                })
                (var tx (ix pos 0)) (var ty (ix pos 1))
                (var ramp (if cfg-aa
                    (map (fn (i) (col (mix-col c tcol (/ (to-float i) 15.0)))) (range 16))
                    (list (col c) (col tcol))))
                (trap (ttf-text im tx ty ramp font k))
                (def chip-im im)
                (def chip-key key)
        })
        chip-im
})

(defun chip (x y sz rad c tcol font label)
    (if (tc-p (list 'chip x y sz rad c tcol font label))
        (trap (img-blit fb (chip-image sz rad c tcol font label) x y -1))))
(def chip-im nil) (def chip-key nil)

(defun rframe (x y w h r c t2)
    (if (tc-p (list 'rf x y w h r c t2))
        (img-rectangle fb x y w h (col c) (list 'rounded r) (list 'thickness t2))))
(defun arc (cx cy r a0 a1 c t2)
    (if (tc-p (list 'a cx cy r a0 a1 c t2))
        (img-arc fb cx cy r a0 a1 (col c) (list 'thickness t2))))
; --- nothing drawn may ever take the frame down ---------------------------
; ttf-text throws if it meets a character the face was not subset with, and
; that throw kills the draw thread. It has happened three separate ways in
; one day: a D in the gear chip, a comma in a label, and an apostrophe in a
; BLE name advertised by somebody else's phone. The first two were mine and
; the third could never have been.
;
; So every string goes through the filter and every draw is trapped. The
; filter keeps it legible where it can; the trap means that even something
; unforeseen - a face that failed to prepare, a nil where a font should be -
; costs one missing string rather than the whole display.

; Which bytes the faces can draw: digits, letters, space and . / % -. A
; table rather than the chain of comparisons it replaces, because every string
; drawn or measured is checked a byte at a time and the chain cost a
; millisecond and a half for five characters - as long as drawing them. A row
; in the cart pill checked its value twice and its label twice per update.
; Every byte value has an entry, so nothing needs a bounds check.
(def glyph-tab [0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 1 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0])
(defun glyph-ok (c) (= (bufget-u8 glyph-tab c) 1))

(defun safe-str (str n) {
        (var out "")
        (var len (str-len str))
        (var lim (if (< len n) len n))
        (looprange i 0 lim {
                (var c (bufget-u8 str i))
                (setq out (str-merge out (if (glyph-ok c) (str-part str i 1) ".")))
        })
        out
})

; Scans without allocating and hands back the original when there is nothing
; to fix, which is every string this package writes itself - so the common
; case costs a few comparisons per character and makes no garbage.
(defun str-clean (str) {
        (var n (str-len str))
        (var i 0)
        (loopwhile (and (< i n) (= (bufget-u8 glyph-tab (bufget-u8 str i)) 1))
            (setq i (+ i 1)))
        (if (< i n) (safe-str str n) str)
})

(def txt-fails 0)

; The icon face is addressed by multi byte codepoints, which the filter would
; mangle, so it has a path of its own. Still trapped.
(defun txt-ico (x y c font str)
    (if (tc-p (list 'i x y c str (to-i (lh-of font))))
        (eq 'exit-ok (car (trap (ttf-text fb x y (col-ramp c) font str))))))

; A face prepared one bit (fonts-try drops font-xl to it above 170) reads
; only the first two colours it is given. The smooth ramp's second is 1/15 of
; the way from the ground to the text colour, so Scoobi's 244 digit came out
; nearly invisible; a one bit face gets the ground and the colour itself.
(defun txt-ramp (c font)
    (if (and cfg-aa (eq font font-xl) (> cfg-fs-xl 170))
        (list (col theme-bg) (col c))
        (col-ramp c)))

(defun txt-raw (x y c font k) {
        (var r (trap (ttf-text fb x y (txt-ramp c font) font k)))
        (if (eq (car r) 'exit-ok) true {
                (def txt-fails (+ txt-fails 1))
                false
        })
})

;; Every text goes through txt-a: the anchor x, the alignment (0 left,
;; 1 centred, 2 right, 3 centred but kept on screen) and the string as the
;; layout built it. In compare mode an unchanged text is recognised from
;; those alone, before the string is cleaned or measured - which is most of
;; what a text costs - so a pass where nothing changed is little more than
;; the layout building its strings.
(defun txt (x y c font str) (txt-a x y c font str 0))
(defun txt-k (x y c font k) (txt-a x y c font k 0))

(defun txt-x (ax w al) (cond
        ((= al 1) (- ax (/ w 2)))
        ((= al 2) (- ax w))
        ((= al 3) {
                ; 6 from the edge, as the layouts' own margins are: at 2 CHARGE
                ; still read as running into the glass's edge
                (var x (- ax (/ w 2)))
                (if (< x 6) (setq x 6))
                (if (> (+ x w) (- fb-w 6)) (setq x (- fb-w w 6)))
                x
        })
        (t ax)))

(defun txt-a (ax y c font s al)
    (if (= tc-mode 2) (txt-diff ax y c font s al) {
        (var k (str-clean s))
        (var w (if (or (> al 0) (= tc-mode 1)) (ix (tdim-k font k) 0) 0))
        (var x (txt-x ax w al))
        (if (= tc-mode 1) {
                (def tc-acc (cons (list 't s ax y c x w font k
                                        (- y (to-i (asc-of font)) 1)
                                        (+ y (to-i (- 0.0 (desc-of font))) 2))
                                  tc-acc))
                (def tc-i (+ tc-i 1))
        })
        (txt-raw x y c font k)
    }))

; Compare mode. Same string, anchor and colour: nothing to do. Changed: wipe
; the union of its old and new boxes, then draw again - in the order they
; were first drawn - everything recorded that the wipe touched, this text
; included. A value sitting on an underline or beside a label would otherwise
; take a bite out of it. A record that does not line up means the layout
; changed shape, and the frame becomes a repaint.
(defun txt-diff (ax y c font s al) (if tc-restart false {
        (var i tc-i)
        (def tc-i (+ i 1))
        (var r (tc-get i))
        (cond
            ((or (eq r nil) (not-eq (ix r 0) 't) (!= (ix r 3) y)) {
                    (def tc-restart true)
                    (def tc-why (list "text out of step" i s))
            })
            ((and (= (ix r 2) ax) (= (ix r 4) c) (eq (ix r 1) s)) true)
            (t {
                    (var k (str-clean s))
                    (var w (ix (tdim-k font k) 0))
                    (var x (txt-x ax w al))
                    (var rx (ix r 5)) (var rw (ix r 6))
                    (var x0 (- (if (< rx x) rx x) 2))
                    (var x1 (+ (if (> (+ rx rw) (+ x w)) (+ rx rw) (+ x w)) 2))
                    (var y0 (ix r 9)) (var y1 (ix r 10))
                    (var nr (list 't s ax y c x w font k y0 y1))
                    (setix tc-rec i nr)
                    (setix tc-bx i (tc-box nr))
                    (tc-damage x0 y0 x1 y1)
            }))
}))

; The box a record covers. Curved things get their bounding square, which is
; generous - it only costs redrawing a little more, never correctness.
(defun tc-box (r) {
        (var k (ix r 0))
        (cond
            ((eq k 'n) (list 0 0 0 0))
            ((eq k 't) (list (- (ix r 5) 2) (ix r 9) (+ (ix r 5) (ix r 6) 2) (ix r 10)))
            ((or (eq k 'b) (eq k 'rb) (eq k 'rf))
                (list (ix r 1) (ix r 2) (+ (ix r 1) (ix r 3)) (+ (ix r 2) (ix r 4))))
            ((eq k 'chip) (list (ix r 1) (ix r 2) (+ (ix r 1) (ix r 3)) (+ (ix r 2) (ix r 3))))
            ((eq k 'a) {
                    (var e (+ (ix r 3) (/ (ix r 7) 2) 3))
                    (list (- (ix r 1) e) (- (ix r 2) e) (+ (ix r 1) e 1) (+ (ix r 2) e 1))
            })
            ((eq k 'r) {
                    (var e (+ (ix r 3) (/ (ix r 5) 2) 3))
                    (list (- (ix r 1) e) (- (ix r 2) e) (+ (ix r 1) e 1) (+ (ix r 2) e 1))
            })
            ((eq k 'd) {
                    (var e (+ (ix r 3) 2))
                    (list (- (ix r 1) e) (- (ix r 2) e) (+ (ix r 1) e 1) (+ (ix r 2) e 1))
            })
            ((eq k 'l) {
                    (var e (+ (ix r 6) 2))
                    (list (- (min-i (ix r 1) (ix r 3)) e) (- (min-i (ix r 2) (ix r 4)) e)
                          (+ (max-i (ix r 1) (ix r 3)) e 1) (+ (max-i (ix r 2) (ix r 4)) e 1))
            })
            ((eq k 'dt) {
                    (var e (+ (ix r 5) (ix r 7) 2))
                    (list (- (ix r 1) e) (- (ix r 2) e) (+ (ix r 1) e 1) (+ (ix r 2) e 1))
            })
            ; the needle is a triangle from its tip to two points beside the hub,
            ; and the hub disc; its box is just those, not the dial
            ((eq k 'needle) {
                    (var cx (ix r 1)) (var cy (ix r 2)) (var a (ix r 4))
                    (var tx (pol-xf cx (- (ix r 3) 30) a)) (var ty (pol-yf cy (- (ix r 3) 30) a))
                    (list (- (min-i tx (- cx 10)) 3) (- (min-i ty (- cy 10)) 3)
                          (+ (max-i tx (+ cx 10)) 4) (+ (max-i ty (+ cy 10)) 4))
            })
            ; an icon is drawn up from its baseline, about as wide as tall
            ((eq k 'i) (list (- (ix r 1) 2) (- (ix r 2) (ix r 5) 2) (+ (ix r 1) (ix r 5) 4) (+ (ix r 2) 4)))
            (t (list 0 0 fb-w fb-h)))
})

(defun pol-xf (cx r a) (+ cx (to-i (* r (cos (* a 0.01745329))))))
(defun pol-yf (cy r a) (+ cy (to-i (* r (sin (* a 0.01745329))))))

; Replay a record onto a scratch image shifted by ox oy.


(defun tc-draw-to (g r ox oy) {
        (var k (ix r 0))
        (cond
            ((eq k 'n) nil)
            ; txt-ramp, as the first draw used: the repair of a one bit face with the
            ; smooth ramp left Scoobi's speed faint after every change (review 2026-10-24)
            ((eq k 't) (trap (ttf-text g (+ (ix r 5) ox) (+ (ix r 3) oy) (txt-ramp (ix r 4) (ix r 7)) (ix r 7) (ix r 8))))
            ((eq k 'b) (img-rectangle g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (ix r 4) (col (ix r 5)) '(filled)))
            ((eq k 'rb) (img-rectangle g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (ix r 4) (col (ix r 6))
                                       (list 'rounded (ix r 5)) '(filled)))
            ((eq k 'rf) (img-rectangle g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (ix r 4) (col (ix r 6))
                                       (list 'rounded (ix r 5)) (list 'thickness (ix r 7))))
            ((eq k 'a) (img-arc g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (ix r 4) (ix r 5) (col (ix r 6))
                                (list 'thickness (ix r 7))))
            ((eq k 'r) (img-circle g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (col (ix r 4)) (list 'thickness (ix r 5))))
            ((eq k 'd) (img-circle g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (col (ix r 4)) '(filled)))
            ((eq k 'l) (img-line g (+ (ix r 1) ox) (+ (ix r 2) oy) (+ (ix r 3) ox) (+ (ix r 4) oy)
                                 (col (ix r 5)) (list 'thickness (ix r 6))))
            ((eq k 'dt) {
                    (var cx (ix r 1)) (var cy (ix r 2)) (var a (ix r 3))
                    (img-line g (+ (pol-xf cx (ix r 4) a) ox) (+ (pol-yf cy (ix r 4) a) oy)
                                (+ (pol-xf cx (ix r 5) a) ox) (+ (pol-yf cy (ix r 5) a) oy)
                                (col (ix r 6)) (list 'thickness (ix r 7)))
            })
            ((eq k 'needle) (needle-draw-to g (+ (ix r 1) ox) (+ (ix r 2) oy) (ix r 3) (ix r 4) (ix r 5) (ix r 6)))
            ((eq k 'i) (trap (ttf-text g (+ (ix r 1) ox) (+ (ix r 2) oy) (col-ramp (ix r 3)) font-ico (ix r 4))))
            ((eq k 'chip) (trap (img-blit g (chip-image (ix r 3) (ix r 4) (ix r 5) (ix r 6) (ix r 7) (ix r 8))
                                          (+ (ix r 1) ox) (+ (ix r 2) oy) -1)))
            (t (def tc-restart true)))
})

;; The box of the part of a circle swept between two angles, at radius r and
;; width w: the two end points plus any quarter (0, 90, 180, 270 degrees) the
;; sweep passes, at the inner and outer edge, with a margin for antialiasing.
;; Angles as img-arc takes them; a sweep past 360 wraps.
(defun arc-sweep-box (cx cy r w a b) {
        (var lo (if (< a b) a b)) (var hi (if (< a b) b a))
        (var ro (+ r (/ w 2) 3)) (var ri (- r (/ w 2) 3))
        (var x0 cx) (var y0 cy) (var x1 cx) (var y1 cy)
        (var pts (list lo hi))
        (loop ((q 0.0)) (< q 721.0) {
                (if (and (> q lo) (< q hi)) (setq pts (cons q pts)))
                (setq q (+ q 90.0))
        })
        (loopforeach ang pts {
                (loopforeach rr (list ro ri) {
                        (var px (pol-xf cx rr ang)) (var py (pol-yf cy rr ang))
                        (setq x0 (min-i x0 px)) (setq y0 (min-i y0 py))
                        (setq x1 (max-i x1 px)) (setq y1 (max-i y1 py))
                })
        })
        ; the end points sit on the arc, not on the box's corner - pad by the width
        (list (- x0 3) (- y0 3) (+ x1 4) (+ y1 4))
})

(defun min-i (a b) (if (< a b) a b))
(defun max-i (a b) (if (> a b) a b))

; Damage is collected through the compare pass and repaired once at the end.
; Repairing each change as it was found meant a scan of every record per
; change, and with ten values moving in a frame that cost more than painting
; the whole screen - 1.4 seconds on the custom layout.
(def tc-dmg nil)
(defun tc-damage (x0 y0 x1 y1) {
        ; Text metrics are unsigned; damage origins must stay signed before
        ; negation. On the ESP32, -205u wraps to 268435251u; adding the
        ; EEPROM i32 chip position then places its repair offscreen.
        (def tc-dmg (cons (list (max-i (to-i x0) 0) (max-i (to-i y0) 0)
                               (min-i (to-i x1) fb-w) (min-i (to-i y1) fb-h)) tc-dmg))
        (def fb-changed true)
})



; Repair each damaged box through a scratch image of exactly its size: clear
; it to the background, draw into it - shifted so the box's corner is its
; origin - every record that touches the box, in their original order, and
; copy it onto the frame. Whatever a record paints outside the box falls off
; the edge of the scratch image, so nothing outside the damage is touched and
; nothing needs to grow. An earlier version grew the damage instead, until no
; redrawn record reached outside it; that was exact too, but the growing was a
; Lisp scan per step and cost 220ms on an instrument frame with three values
; moving.
;
; When the damage would redraw most of the records anyway, a repaint is
; cheaper, and the caller does that. If a scratch image cannot be had, same.
(def tc-pool nil)
(defun tc-repair-all () {
        (if (eq tc-pool nil) {
                (var p (trap (dm-create 330000)))
                (if (eq (car p) 'exit-ok) (def tc-pool (car (cdr p))))
        })
        (var hits 0)
        (loopforeach d tc-dmg
            (loop ((bs tc-bx)) bs {
                    (var b (car bs))
                    (if (and (< (ix b 0) (ix d 2)) (> (ix b 2) (ix d 0))
                             (< (ix b 1) (ix d 3)) (> (ix b 3) (ix d 1)))
                        (setq hits (+ hits 1)))
                    (setq bs (cdr bs))
            }))
        (if (or (eq tc-pool nil) (> (* hits 10) (* tc-n 7))) {
                (def tc-restart true)
                (def tc-why (list "repair would redraw" hits "of" tc-n))
        } (loopforeach d tc-dmg {
                (var x0 (ix d 0)) (var y0 (ix d 1))
                (var w (- (ix d 2) x0)) (var h (- (ix d 3) y0))
                (if (and (> w 0) (> h 0) (not tc-restart)) {
                        (var tr (trap (img-buffer tc-pool 'rgb565 w h)))
                        (if (not-eq (car tr) 'exit-ok) {
                                (def tc-restart true)
                                (def tc-why (list "no scratch image" w h))
                        } {
                                (var tile (car (cdr tr)))
                                (img-clear tile (col tc-bg))
                                (loop ((bs tc-bx) (rs tc-rec)) bs {
                                        (var b (car bs))
                                        (if (and (< (ix b 0) (ix d 2)) (> (ix b 2) x0)
                                                 (< (ix b 1) (ix d 3)) (> (ix b 3) y0))
                                            (tc-draw-to tile (car rs) (- 0 x0) (- 0 y0)))
                                        (setq bs (cdr bs))
                                        (setq rs (cdr rs))
                                })
                                (img-blit fb tile x0 y0 -1)
                                (setq tile nil)
                        })
                })
        }))
        (def tc-dmg nil)
})



; Measuring throws on the same strings drawing does, and every caller wants a
; number rather than an exception. A rough estimate when even that fails is
; better than a skipped element, because a skipped element is invisible and
; a slightly mis-centred one is not.
(defun tdim (f str) (tdim-k f (str-clean str)))

(defun tdim-k (f k) {
        (var r (trap (ttf-text-dims f k)))
        ; Font dimensions feed subtraction and centering, including offscreen
        ; text. Convert before arithmetic, not after unsigned underflow.
        (if (eq (car r) 'exit-ok) (map to-i (car (cdr r)))
            (list (* 9 (str-len k)) 16))
})

; four ramp slots, kept as plain variables because a list cannot be mutated
; Four ramp slots held as plain variables. A list cannot be mutated in place,
; and rebuilding a sixteen entry ramp for every string drawn was the single
; largest source of garbage in the draw loop.
(def rk0 -1) (def rk1 -1) (def rk2 -1) (def rk3 -1)
(def rv0 nil) (def rv1 nil) (def rv2 nil) (def rv3 nil)
(def rnext 0)

; Antialiased glyphs are blitted through a sixteen step ramp whose first
; entry has to be whatever the frame was cleared to, or every letter carries
; a fringe of the old background. theme-bg is that colour; layouts that want
; something other than black set it through theme-set, which also drops the
; cached ramps built against the previous one.
(def theme-bg 0x000000)

(defun ramp-build (c) (if cfg-aa
        (map (fn (i) (col (mix-col theme-bg c (/ (to-float i) 15.0)))) (range 16))
        (list (col theme-bg) (col c))))

(defun ramp-store (c v) {
        (cond ((= rnext 0) { (def rk0 c) (def rv0 v) })
              ((= rnext 1) { (def rk1 c) (def rv1 v) })
              ((= rnext 2) { (def rk2 c) (def rv2 v) })
              (t           { (def rk3 c) (def rv3 v) }))
        (def rnext (mod (+ rnext 1) 4))
        v
})

(defun col-ramp (c) (cond
        ((= c rk0) rv0)
        ((= c rk1) rv1)
        ((= c rk2) rv2)
        ((= c rk3) rv3)
        (t (ramp-store c (ramp-build c)))))

(defun ramp-flush () {
        (def rk0 -1) (def rk1 -1) (def rk2 -1) (def rk3 -1)
        (def rv0 nil) (def rv1 nil) (def rv2 nil) (def rv3 nil)
        (def rnext 0)
        true
})

(defun mix-col (a b f) {
        (var ar (bitwise-and (shr a 16) 0xff))
        (var ag (bitwise-and (shr a 8) 0xff))
        (var ab (bitwise-and a 0xff))
        (var br (bitwise-and (shr b 16) 0xff))
        (var bg (bitwise-and (shr b 8) 0xff))
        (var bb (bitwise-and b 0xff))
        (bitwise-or (shl (to-i (+ ar (* (- br ar) f))) 16)
        (bitwise-or (shl (to-i (+ ag (* (- bg ag) f))) 8)
                    (to-i (+ ab (* (- bb ab) f)))))
})
; ---- theme ---------------------------------------------------------------
; The colour model the Arduino cart dash uses, ported so the arc layout can
; look like the screen it replaces. Everything derives from two stored
; colours - a background and an accent - which is what keeps a user-picked
; hue readable without them having to choose eight colours by hand.

(defun col-r (c) (bitwise-and (shr c 16) 0xff))
(defun col-g (c) (bitwise-and (shr c 8) 0xff))
(defun col-b (c) (bitwise-and c 0xff))
(defun rgb (r g b) (bitwise-or (shl r 16) (bitwise-or (shl g 8) b)))
(defun clamp8 (v) (if (< v 0) 0 (if (> v 255) 255 v)))
(defun idist (a b) (if (> a b) (- a b) (- b a)))

; ITU-R BT.601 luma, the same weights the Arduino build uses. Every
; light/dark decision below is a threshold on this one number.
(defun col-bri (c)
    (/ (+ (* (col-r c) 299) (+ (* (col-g c) 587) (* (col-b c) 114))) 1000))

; Panels sit just off the background: lifted on a dark one, dropped on a
; light one, so a card reads as a card without needing a border.
(defun theme-panel (bg) {
        (var v (col-bri bg))
        (var d (if (> v 200) -30 (if (< v 30) 30 20)))
        (rgb (clamp8 (+ (col-r bg) d))
             (clamp8 (+ (col-g bg) d))
             (clamp8 (+ (col-b bg) d)))
})

(defun theme-txt (bg) {
        (var v (col-bri bg))
        (cond ((> v 200) 0x000000) ((> v 140) 0x111111)
              ((< v 30) 0xffffff) (t 0xeaeaea))
})

(defun theme-dim (bg) {
        (var v (col-bri bg))
        (cond ((> v 200) 0x333333) ((> v 140) 0x444444)
              ((< v 30) 0xbbbbbb) (t 0xcccccc))
})

; Text sitting on the accent rather than on the background.
(defun theme-on (acc) (if (> (col-bri acc) 200) 0x111111 0xffffff))
(defun theme-on2 (acc) (if (> (col-bri acc) 200) 0x444444 0xcccccc))

; Status colours come in a bright and a dark form; take whichever stands
; further from what it will be drawn against. Green on a light background is
; the case this exists for - 0x00ff00 nearly vanishes, 0x007a00 does not.
(defun pick-variant (bright dark against) {
        (var v (col-bri against))
        (if (>= (idist (col-bri bright) v) (idist (col-bri dark) v)) bright dark)
})

(def theme-acc  0x000000)
(def theme-pan  0x323d4f)
(def theme-fg   0xeaeaea)
(def theme-fg2  0xcccccc)
(def theme-ofg  0xffffff)
(def theme-ofg2 0xcccccc)
(def theme-good 0x00ff00)
(def theme-warn 0xffd800)
(def theme-bad  0xff3333)
; the same three picked against the accent instead, for status text that
; sits inside an accent filled pill rather than on the background
(def theme-good-a 0x00ff00)
(def theme-warn-a 0xffd800)
(def theme-bad-a  0xff3333)

; Everything below depends on the two colours and nothing else, and it is
; called at the top of every frame. Recomputing eleven contrast calculations
; sixty times a second for a theme that has not changed cost 4.6ms a frame,
; which at 24 frames a second is a tenth of the time available.
(def theme-set-bg -1)
(def theme-set-acc -1)

(defun theme-set (bg acc) {
        (if (and (= bg theme-set-bg) (= acc theme-set-acc)) true {
                (def theme-set-bg bg)
                (def theme-set-acc acc)
                (theme-apply bg acc)
        })
})

(defun theme-apply (bg acc) {
        ; the cached ramps were built against the old background
        (if (!= bg theme-bg) { (def theme-bg bg) (ramp-flush) })
        (def theme-acc acc)
        (def theme-pan (theme-panel bg))
        (def theme-fg (theme-txt bg))
        (def theme-fg2 (theme-dim bg))
        (def theme-ofg (theme-on acc))
        (def theme-ofg2 (theme-on2 acc))
        (def theme-good (pick-variant 0x00ff00 0x007a00 bg))
        (def theme-warn (pick-variant 0xffd800 0x806600 bg))
        (def theme-bad  (pick-variant 0xff3333 0x800000 bg))
        (def theme-good-a (pick-variant 0x00ff00 0x007a00 acc))
        (def theme-warn-a (pick-variant 0xffd800 0x806600 acc))
        (def theme-bad-a  (pick-variant 0xff3333 0x800000 acc))
        true
})





@const-end
