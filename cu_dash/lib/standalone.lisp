;! Controller and BMS picker over Bluetooth.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; picking a controller or a battery on the screen, and the touch thread

@const-start
; --- picking a controller on the screen ----------------------------------
; A cart has no link board. Its owner has a display, a controller with
; Bluetooth, and no way to type a MAC address into anything - so the display
; has to do the finding. When nothing at all is talking to it, it says so and
; offers to look, and everything after that is tapping a name in a list.
;
; It is a modal state rather than a page, because a swipe is how pages are
; changed and swiping out of a half finished connection by accident is
; exactly the sort of thing that makes somebody give up.

(def ble-pick false)
; Which device the picker is picking. The two searches are the same search -
; scan, sort, tap a row - and the only things that differ are the word on the
; title, which saved address counts as "yours", and what a tap finally calls.
; One picker with a target beats two that drift apart.
(def ble-target 0)     ; 0 controller, 1 BMS
(def ble-items nil)
; First visible row. Five rows fit in landscape and a scan in a normal room
; finds ten or more, so without this the list is a lottery: the device you
; want is either in the first five or it does not exist as far as the screen
; is concerned. A BMS is the bad case - most packs advertise no name, so they
; sort below every named thing in range.
(def ble-top 0)
(def ble-busy false)
(def ble-msg "")

(defun ble-rows () (/ (- fb-h 124) 36))

; An advertiser with no name comes back as "?" rather than as an empty
; string, so anything longer than one character is a real name.
(defun ble-named (d) (> (str-len (ix d 1)) 1))

; Is the controller we already chose among what the scan just saw? A module
; someone else is connected to stops advertising, so "not here" is the
; signal that it is off or busy - and it is worth separating from "here but
; further down the list", because the advice is opposite.
(defun pick-mac () (if (= ble-target 1) cfg-ab-mac cfg-vb-mac))

(defun ble-saw-saved () {
        (var f nil)
        (loopforeach d ble-items (if (eq (ix d 0) (pick-mac)) (setq f t)))
        f
})

(defun ble-scan () {
        (def ble-busy true)
        (def ble-items nil)
        (def ble-top 0)
        (def ble-msg (if (= ble-target 1) "looking for a BMS"
                                          "looking for controllers"))
        (spawn (fn () {
                ; A connected peer stops advertising, so let go before
                ; looking - both links, because the pack is on link 1 and a
                ; scan run alongside a live link is what once dragged the
                ; dash from five frames a second down to two thirds of one.
                ; Both threads reconnect on their own afterwards.
                (trap (ble-disconnect))
                (trap (ble-disconnect 1))
                (sleep 0.4)
                (var ok (trap (ble-scan-start 5)))
                (sleep 5.2)
                (trap (ble-scan-stop))
                (var got (car (cdr (trap (ble-scan-list)))))
                (if (eq (car ok) 'exit-error) {
                        (def ble-msg "this display has no Bluetooth build")
                        (def ble-items nil)
                } {
                        ; Named first, then strongest. There is room for five
                        ; rows and a scan in a block of flats finds eight or
                        ; more, so what lands on screen decides whether the
                        ; list is useful or a lottery. A controller advertises
                        ; a name; most of what fills a scan does not - a real
                        ; scan here was one controller, one smart plug and six
                        ; anonymous ones - so sorting the nameless below the
                        ; named is worth more than signal strength alone.
                        (def ble-items
                            (car (cdr (trap (sort (fn (a b)
                                                      (if (eq (ble-named a) (ble-named b))
                                                          (> (ix a 2) (ix b 2))
                                                          (ble-named a)))
                                                  got)))))
                        (if (eq ble-items nil) (def ble-items got))
                        ; choosing a controller: other displays are not one,
                        ; and picking one is how a dash ends up paired to the
                        ; display beside it on a bench (see vb-is-display)
                        (if (= ble-target 0)
                            (def ble-items (filter (fn (d) (not (vb-is-display (ix d 1)))) ble-items)))
                        (var n (if ble-items (length ble-items) 0))
                        ; Saying "8 found - tap one" while showing five is a
                        ; lie the owner cannot act on. If the list does not
                        ; fit, say what is on screen and give them something
                        ; to do about the rest.
                        (def ble-msg (cond
                            ; An empty scan with a controller already chosen
                            ; is not the same as an empty scan on a new dash.
                            ; The commonest cause is that the controller is
                            ; connected to something else - a module with a
                            ; central attached stops advertising, so it is
                            ; invisible to this scan however close it is.
                            ; Without saying so, the rider is told to try
                            ; again at something that will never appear.
                            ((and (= n 0) (> (str-len (pick-mac)) 1))
                                (if (= ble-target 1)
                                    "nothing found - is the pack asleep"
                                    "nothing found - is it off or on a phone"))
                            ((= n 0) "nothing found - try again")
                            ; Found plenty, but not the one already chosen.
                            ; Telling them to move nearer is wrong here: a
                            ; controller that is off or held by a phone will
                            ; not appear at any distance. Checked before the
                            ; truncation message because the advice differs.
                            ((and (> (str-len (pick-mac)) 1) (not (ble-saw-saved)))
                                (if (= ble-target 1)
                                    "yours is not listed - asleep or on its app"
                                    "yours is not listed - off or on a phone"))
                            ((> n (ble-rows))
                                ; not "the closest": the list is named
                                ; first, then strongest, so the row order is
                                ; not distance order
                                (str-merge (str-from-n (ble-rows) "%d")
                                           " of "
                                           (str-from-n n "%d")
                                           " - swipe up for the rest"))
                            (t (str-merge (str-from-n n "%d")
                                          " found - tap one to use it"))))
                })
                (def ble-busy false)
        }))
        true
})

(defun ble-open () {
        (def ble-target 0)
        (def ble-pick true)
        (ble-scan)
})

; The same picker, aimed at the pack. Turning the BMS on without one of
; these is a setting that appears to do nothing: the link thread needs an
; address and there is no keyboard on this display to type one into.
(defun ab-open () {
        (def ble-target 1)
        (def ble-pick true)
        (ble-scan)
})

(defun ble-close () { (def ble-pick false) (def ble-items nil) (def ble-top 0) })

; A vertical swipe moves the window. The picker is modal so a swipe is not
; already spoken for here, and a scroll bar on a panel this size would cost
; a row to save a gesture nobody has to be taught.
; The clamped offset, in one place.
;
; draw-ble used to clamp into a local while ble-hit indexed with the raw
; ble-top. A scan that came back shorter than the one before it left the
; offset past the end: the screen drew the last page, the tap was counted
; from further down, and tapping a BMS connected to whatever was three rows
; below it. Both now ask this, and it writes the clamp back so the two can
; never drift apart again.
(defun ble-topc () {
        (var total (if ble-items (length ble-items) 0))
        (var hi (- total (ble-rows)))
        (if (< hi 0) (setq hi 0))
        (var v ble-top)
        (if (< v 0) (setq v 0))
        (if (> v hi) (setq v hi))
        (if (!= v ble-top) (def ble-top v))
        v
})

(defun ble-scroll (d) {
        (def ble-top (+ (ble-topc) d))
        (ble-topc)
})

(defun ble-choose (i) {
        (var d (ix ble-items i))
        (if d {
                (def ble-msg (str-merge "connecting to " (safe-str (ix d 1) 18)))
                (def ble-busy true)
                ; read once, here: the spawned body must not depend on a
                ; global that the next tap could move under it
                (var tgt ble-target)
                (spawn (fn () {
                        (if (= tgt 1) (trap (ab-use (ix d 0)))
                                      (trap (vb-use (ix d 0))))
                        (sleep 2.0)
                        (def ble-busy false)
                        (def ble-pick false)
                }))
        })
})

; Offline UI follows the saved route, not just the direct BLE address.
; An Express link may be saved while controller BLE is disabled. Its normal
; startup wait must not invite a scan which cannot find that CAN controller.
(def ui-connect-t0 0)
(defun vb-settling ()
    (or (vb-grace)
        (and (> vb-try 0) (< (secs-since vb-try) 12.0))
        (and vb-linked (> vb-up 0) (< (secs-since vb-up) 10.0))))

(defun ble-remembered () (or link-saved (> (str-len cfg-vb-mac) 1)))
(defun ble-waiting ()
    (and (ble-remembered)
         (or (< (secs-since ui-connect-t0) 15.0)
             (and (> d-last 0) (< (secs-since d-last) 15.0))
             (and cfg-vb-en (vb-settling)))))
(defun ble-offer () (and (not d-online) (not ble-pick)))
(defun ble-offer-action ()
    ; A known link keeps reconnecting automatically. Waiting messages are
    ; informational; tapping them must not disconnect the BMS for a scan.
    (and (ble-offer) (not link-saved)
         (or vb-paused vb-wrong vb-nocon (not (ble-waiting)))))
(defun ble-offer-message () (cond
    (link-saved (if (ble-waiting) "CONNECTING TO CONTROLLER"
                       "WAITING FOR CONTROLLER - CHECK LINK"))
    (vb-paused "RELEASED FOR VESC TOOL - TAP")
    (vb-wrong "THAT IS NOT A CONTROLLER - TAP")
    (vb-nocon "COULD NOT CONNECT - TAP TO RETRY")
    ((ble-waiting) "CONNECTING TO CONTROLLER")
    ((ble-remembered) "CONTROLLER NOT RESPONDING - TAP TO RETRY")
    (t "TAP TO FIND A CONTROLLER")))

; Centred, and covering whatever is behind it. It only appears when nothing
; is talking to the display, so everything behind it is stale or zero and
; worth less than the instruction. Sat above the bottom edge it landed on the
; cart layout's charge line and clipped its battery bar - and with a free
; layout there is no safe corner to move it to, because the rider chooses
; where everything goes.
(defun draw-ble-offer () {
        (var msg (ble-offer-message))
        ; Sized to its message: the box was a fixed 268 wide and three of the
        ; four messages are wider at the default face, so they ran out past
        ; both its edges (page sweep, 2026-10-24). Too wide for the glass
        ; (upright), it goes on two lines, split at its " - ".
        (var mw (ix (tdim-k font-sm (str-clean msg)) 0))
        (var two (and (> (+ mw 32) fb-w) (>= (str-find msg " - ") 0)))
        (var l1 (if two (str-part msg 0 (str-find msg " - ")) msg))
        (var l2 (if two (str-part msg (+ (str-find msg " - ") 3)) ""))
        (var w1 (ix (tdim-k font-sm (str-clean l1)) 0))
        (var w2 (if two (ix (tdim-k font-sm (str-clean l2)) 0) 0))
        (var w (+ (if (> w1 w2) w1 w2) 28))
        (if (< w 268) (setq w 268))
        (if (> w (- fb-w 12)) (setq w (- fb-w 12)))
        (var h (if two 76 52))
        (var x (/ (- fb-w w) 2)) (var y (/ (- fb-h h) 2))
        (rbox x y w h 8 0x0A1822)
        (rframe x y w h 8 0x00A0FF 2)
        (if two {
                (txt-c (/ fb-w 2) (base-c font-sm (+ y 24)) 0xFFFFFF font-sm l1)
                (txt-c (/ fb-w 2) (base-c font-sm (+ y 52)) 0xFFFFFF font-sm l2)
        } (txt-c (/ fb-w 2) (base-c font-sm (+ y (/ h 2))) 0xFFFFFF font-sm msg))
})

(defun draw-ble () {
        (img-clear fb 0x000000)
        (txt-c (/ fb-w 2) (base-c font-md 30) 0xFFFFFF font-md
               (if (= ble-target 1) "SELECT BMS" "SELECT CONTROLLER"))
        (txt-c (/ fb-w 2) (base-c font-sm 58) 0x9AA0AA font-sm ble-msg)

        ; Snapshot it. The scan thread and ble-close both set ble-items to
        ; nil, and reading it twice lets one land between the count and the
        ; row, where (ix nil i) throws and takes the whole frame with it.
        ; Trapped, so it never crashed - it just showed up as an occasional
        ; type_error with nothing obviously wrong, twice, hours apart.
        (var items ble-items)
        (var total (if items (length items) 0))
        (var rows (ble-rows))
        ; clamped here as well as where it is changed, because a scan that
        ; comes back shorter than the last one would otherwise leave the
        ; offset pointing past the end and draw nothing at all
        (var top (ble-topc))
        (var n (- total top))
        (if (> n rows) (setq n rows))
        (looprange i 0 n {
                (var d (ix items (+ top i)))
                (var y (+ 72 (* i 36)))
                (rbox 20 y (- fb-w 40) 32 6 0x14181E)
                ; an unnamed advertiser comes back as "?" rather than as an
                ; empty string, and a row showing one full stop helps nobody
                (var nm (if (> (str-len (ix d 1)) 1) (ix d 1) (ix d 0)))
                (txt 32 (base-c font-sm (+ y 16)) 0xFFFFFF font-sm
                     (safe-str nm 22))
                (txt-r (- fb-w 32) (base-c font-sm (+ y 16)) 0x9AA0AA font-sm
                       (str-merge (str-from-n (ix d 2) "%d") "dB"))
        })

        ; Footer: look again, hand the controller over, or give up.
        ;
        ; Measured off the width rather than fixed. The old two-button footer
        ; was written for 480 and put SCAN AGAIN at 20..170 and BACK at
        ; fb-w-170: in portrait that is 150, so the two overlapped and a tap
        ; in the overlap scanned instead of going back. Three fixed buttons
        ; would have had the middle one at a negative width.
        (var by (- fb-h 52))
        (var bw (/ (- fb-w 40) 3))
        (var bx0 12)
        (var bx1 (+ bx0 bw 8))
        (var bx2 (+ bx1 bw 8))
        (rbox bx0 by bw 40 8 0x1A3A1A)
        (txt-c (+ bx0 (/ bw 2)) (base-c font-sm (+ by 20)) 0xFFFFFF font-sm
               (if ble-busy "WORKING" "SCAN"))
        ; the middle button is the only way to let VESC Tool at the
        ; controller without switching the screen off
        ; The middle button. For a controller it hands the module back to
        ; VESC Tool. For a pack it forgets the one that is saved - turning
        ; the BMS link off from quick settings already hands the pack to its
        ; own app and keeps it for next time, so releasing it here would be
        ; a second way to do the same thing, while forgetting had no way at
        ; all.
        (if (= ble-target 1) {
                (rbox bx1 by bw 40 8 (if (> (str-len cfg-ab-mac) 1)
                                         0x3A2A12 0x22242A))
                (txt-c (+ bx1 (/ bw 2)) (base-c font-sm (+ by 20))
                       0xFFFFFF font-sm "FORGET")
        } {
                (rbox bx1 by bw 40 8 (if vb-paused 0x1A3A1A 0x2A2A12))
                (txt-c (+ bx1 (/ bw 2)) (base-c font-sm (+ by 20))
                       0xFFFFFF font-sm (if vb-paused "RECONNECT" "RELEASE"))
        })
        (rbox bx2 by bw 40 8 0x3A1A1A)
        (txt-c (+ bx2 (/ bw 2)) (base-c font-sm (+ by 20)) 0xFFFFFF font-sm "BACK")
})

(defun ble-hit (x y) {
        (var by (- fb-h 52))
        (cond
            ; same geometry the footer is drawn with, so what is tapped is
            ; what is lit
            ((and (> y by) (< x (+ 12 (/ (- fb-w 40) 3))))
                (if (not ble-busy) (ble-scan)))
            ((and (> y by) (> x (- fb-w 12 (/ (- fb-w 40) 3)))) (ble-close))
            ((> y by)
                (if (= ble-target 1)
                    (if (> (str-len cfg-ab-mac) 1)
                        { (trap (ab-forget))
                          (def ble-msg "pack forgotten - tap one to choose another") }
                        (def ble-msg "no pack saved to forget"))
                    { (def vb-paused (not vb-paused))
                      (if vb-paused (def ble-msg "released - VESC Tool can connect now")
                                    (def ble-msg "reconnecting")) }))
            ; only rows that are drawn: below the last one, above the footer,
            ; is a strip that indexed the next device off the screen
            ((and (>= y 72) (< y (- by 8)) (not ble-busy)
                  (< (/ (- y 72) 36) (ble-rows)))
                (ble-choose (+ (ble-topc) (/ (- y 72) 36))))
            (t nil))
})

(defun touch-thread () {
        (var was nil)
        (var sx 0) (var sy 0) (var lx 0) (var ly 0) (var t0 0) (var dd 1)
        (loopwhile t {
                ; the driver loads alongside the dash, so this runs before
                ; it exists; trapped as well as gated, because a touch panel
                ; that fails to load must not take the thread with it
                (var tp (if touch-ok
                            (car (cdr (trap (touch-read))))
                            nil))
                (if tp {
                        (var m (map-touch tp))
                        (setq lx (ix m 0))
                        (setq ly (ix m 1))
                        (if (eq was nil) {
                                (setq sx lx) (setq sy ly) (setq t0 (systime))
                                (def basic-drag-row (basic-slider-row lx ly))
                                (def drag-commit nil)
                        })
                        (if (>= basic-drag-row 0) (basic-drag basic-drag-row lx))
                        ; clearly sideways: ask for the page now, so it is
                        ; painted while the finger is still moving
                        (var dx (- lx sx))
                        (var dy (- ly sy))
                        (if (and (< basic-drag-row 0) was (not drag-on) (not ble-pick) (not quick-open)
                                 (not slide-req) (= slide-dir 0)
                                 (> (abs dx) 24) (> (abs dx) (* 2 (abs dy)))
                                 (slide-can)) {
                                (setq dd (if (> dx 0) -1 1))
                                (page-step-d dd true)
                                (if slide-req (def drag-on true))
                        })
                        (if drag-on {
                                (var o (* (- 0 dd) dx))
                                (def drag-off (if (< o 0) 0 o))
                        })
                })
                (if (and (eq tp nil) was) {
                        (var dx (- lx sx))
                        (var dy (- ly sy))
                        ; a drag already asked for its page; letting go only
                        ; decides whether it goes through. Far enough, or a
                        ; quick flick, and it does. Settled before drag-on
                        ; drops, which is what the draw thread waits on.
                        (if drag-on {
                                (def drag-commit (or (> drag-off 60)
                                                     (and (> drag-off 30) (< (secs-since t0) 0.3))))
                                (if (and (not drag-commit) slide-req) (def slide-req nil))
                                (def drag-on nil)
                        }
                        (if ble-pick
                            (if (and (< (abs dx) 40) (< (abs dy) 40))
                                (ble-hit sx sy)
                                ; up the screen means further down the list,
                                ; the way every list on a phone behaves
                                (if (> (abs dy) 50)
                                    (ble-scroll (if (> dy 0) 1 -1))))
                        (if quick-open
                            (if (and (< (abs dx) 40) (< (abs dy) 40))
                                (quick-hit sx sy))
                        (if (help-active)
                            (if (and (< (abs dx) 40) (< (abs dy) 40) (< (secs-since t0) 0.6))
                                (help-hit sx sy) (help-gesture dx dy))
                        (if (>= basic-drag-row 0) (def basic-drag-row -1)
                        (if (> (abs dx) 60)
                            (page-step (if (> dx 0) -1 1))
                            {
                                ; a tap: the banner first, because on a cart
                                ; it is the only thing on the screen worth
                                ; touching, and it sits in the middle
                                (if (and (< (abs dy) 40) (< (secs-since t0) 0.6)
                                         (= page 0))
                                    (if (and (ble-offer)
                                             (> sy (- (/ fb-h 2) 40))
                                             (< sy (+ (/ fb-h 2) 40)))
                                        (if (ble-offer-action) (ble-open))
                                        (modestrip-hit sx sy)))
                                ; the same panel, reached by swiping to the
                                ; end instead of by holding. Swipes still
                                ; change page here - it is a page, not a
                                ; modal - so only taps are claimed.
                                (if (and (= page (pg-set))
                                         (< (abs dy) 40)
                                         (< (secs-since t0) 0.6))
                                    (quick-hit sx sy))
                                (if (and (= page (pg-whl))
                                         (< (abs dx) 40) (< (abs dy) 40)
                                         (< (secs-since t0) 0.6))
                                    (whl-hit sx sy))
                                (if (and (= page (pg-setup)) (< (abs dx) 40) (< (abs dy) 40)
                                         (< (secs-since t0) 0.6)) (setup-hit sx sy))
                                ; held still and held on: the one gesture a
                                ; swipe and a tap do not already claim
                                (if (and (< (abs dx) 40) (< (abs dy) 40)
                                         (!= page (pg-set))
                                         (not (and (= page (pg-setup)) (> setup-view 0)))
                                         (>= (secs-since t0) 0.8))
                                    (def quick-open true))
                            }))))))
                })
                (setq was tp)
                (sleep 0.03) })
})

@const-end
