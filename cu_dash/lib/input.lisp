;! Touch, buttons, actions and drive modes.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; orientation, the power modes, the buttons and walk mode

@const-start
(def c-tile  0x101014)
(def c-edge  0x2A2A32)
(def c-track 0x26262C)
(def c-text  0xFFFFFF)
(def c-dim   0x8A8A93)
(def tl-x 8)   (def tl-y 8)
(def tr-x 320) (def tr-y 8)
(def bl-x 8)   (def bl-y 116)
(def br-x 320) (def br-y 116)
(def g-cx 240) (def g-cy 116) (def g-r 88)
(def bar-x 8) (def bar-y 228) (def bar-w 464) (def bar-h 80)
(def d-ah 0.0)    (def d-whkm 0.0) (def d-fault 0)
(def link-peer false)
; when a link frame last said its controller answers; see link-carries
(def link-on-t 0)
; and when it last started answering after a gap, see vb-standby
(def link-on-t0 0)
; The link carries the mode only while its own controller answers it. Present
; but cut off from the controller, it would take the mode and deliver it
; nowhere, while Bluetooth to the same controller was working.
; and whether the link says it is this dash's: a link kept by another dash
; is not carrying this one's controller, whatever it reports
(def link-mine true)
(defun link-carries () (and link-peer link-mine (< (secs-since link-on-t) 2.0)))
(def st-hazard false) (def st-aux false)
(def fault-1 "") (def fault-2 "")

(defun set-vertical (v) {
        (print (list "set-vertical" v))
        (def cfg-vertical v)
        (apply-orient)
})

;; One ESP-NOW send at a time. The firmware's esp-now-send blocks the calling
;; thread until the radio reports the send, and it keeps a single record of who
;; to wake: a second send from another thread before the first is reported
;; overwrites it, and the first thread is never woken - blocked for good. The
;; touch, button, hello and mode threads all send, so this could freeze the
;; touchscreen; on the bench a mode thread hung after a burst of sends
;; (2026-10-05). A lock taken in an atomic block (a send itself may not be
;; done inside one), held only for the send, and given up on after half a
;; second rather than waited on for ever.
(def esp-tx-busy false)
(def esp-tx-t 0)

(defun esp-send (dest b) {
        (var got false)
        (var t0 (systime))
        (loopwhile (and (not got) (< (secs-since t0) 0.5)) {
                (atomic
                    ; a holder older than a second is a send that never came
                    ; back (older firmware); take the lock from it
                    (if (or (not esp-tx-busy) (> (secs-since esp-tx-t) 1.0)) {
                            (def esp-tx-busy true)
                            (def esp-tx-t (systime))
                            (setq got true)
                    }))
                (if (not got) (sleep 0.003))
        })
        (if got {
                (var r (trap (esp-now-send dest b)))
                (def esp-tx-busy false)
                r
        } '(exit-error esp-busy))
})

(defun set-flip (v) { (def cfg-orient (if v 1 3)) (apply-orient) })
(defun send-aux (op val) {
        (var b (bufcreate 4))
        (bufset-u8 b 0 0xCF)
        (bufset-u8 b 1 op)
        (bufset-u8 b 2 (if val 1 0))
        (bufset-u8 b 3 0)
        ; If telemetry has stopped, forget the learned address and go back to
        ; broadcast. Otherwise a link that reboots, or one that starts after
        ; the dash, would keep being addressed directly with nothing there to
        ; hear it - and boot order would matter, which it should not.
        (if (and link-peer (> (secs-since d-last) 5.0)) (def link-peer false))
        (def tx-count (+ tx-count 1))
        (def tx-last (systime))
        (var r (link-send b))
        ; with no link paired there is nobody to tell, and saying so for
        ; every press (seven a second with walk held) is only noise
        (if (and link-saved (not-eq (car r) 'exit-ok)) (print (list "aux send failed" r)))
        (free b)
})
; Once a second. With a link paired it carries the mode rather than nothing:
; the mode used to go out once, when it changed, so a single lost ESP-NOW
; frame lost the change - on the bench 2 of 6 mode changes never reached the
; controller (2026-10-05). The link acts only on a change, so repeating it
; costs nothing, and it also tells a link that restarted which mode is wanted.
; The repeat could read the old mode, be switched out while a change was
; made and sent, and then send the old mode after it - the link took the last
; frame as the change, and the controller went back (1 in 15 on the bench).
; So the mode travels with a count that goes up on every change, both kept in
; one value so they are always read together, and the link drops a frame
; whose count is older than the last it acted on. (An atomic block would have
; been simpler, but sending is not allowed inside one.)
(def mode-state nil)  ; (mode . count)

; The limits of modes 1-3, every fifth hello: a CU IO Link keeps them, so its
; switches can change mode with no display there and no Dash ESC on the
; controller. [0xC9] then motor A, battery A, speed, brake A per mode, u16.
(def hello-n 0)
(defun send-mode-table () {
        (var b (bufcreate 25))
        (bufset-u8 b 0 0xC9)
        (looprange i 0 3 {
                (var m (+ i 1))
                (var o (+ 1 (* i 8)))
                (bufset-u16 b o (mode-mot m))
                (bufset-u16 b (+ o 2) (mode-bat m))
                (bufset-u16 b (+ o 4) (mode-spd m))
                (bufset-u16 b (+ o 6) (mode-brk m))
        })
        (link-send b)
        (free b)
})

(defun send-hello () (if link-peer {
        (if (eq mode-state nil) (def mode-state (cons cfg-mode 0)))
        (link-mode-frame mode-state)
        (def hello-n (+ hello-n 1))
        (if (= (mod hello-n 5) 1) (send-mode-table))
    } {
        (var b (bufcreate 4))
        (bufset-u8 b 0 0xCF)
        (bufset-u8 b 1 0)        ; op 0, no action
        (bufset-u8 b 2 0)
        (bufset-u8 b 3 0)
        (esp-send '(255 255 255 255 255 255) b)
        (free b)
}))

(defun link-mode-frame (st) {
        (var m (car st))
        (var b (bufcreate 12))
        (bufset-u8 b 0 0xCE)
        (bufset-u8 b 1 (+ m 1))
        (bufset-u16 b 2 (mode-mot m))
        (bufset-u16 b 4 (mode-bat m))
        (bufset-u16 b 6 (mode-spd m))
        (bufset-u16 b 8 (mode-brk m))
        (bufset-u8 b 10 (cdr st))
        ; 11 bit 0: this display runs a CU IO Link's switches, so the link
        ; leaves them to it instead of working the signals itself
        (bufset-u8 b 11 1)
        (link-send b)
        (free b)
})


; The settings page has always called this, but it was never defined, so the
; Hardware buttons box threw on the device and the flag never moved. Turning
; buttons on has to configure the pins as well; the button thread checks the
; flag every loop, so turning them off needs nothing more.
(defun set-btn-en (v) {
        (def cfg-btn-en v)
        (if v (btn-init))
        v
})

; A button's level: 0 pressed, 1 released. A pin that is not the buttons' to
; use (pin-free) reads released, or the backlight's PWM or the panel's bus
; would come through as presses until the next start put the setting back.
(defun btn-read (pin)
    (if (pin-free pin) (car (cdr (trap (gpio-read pin)))) 1))

(defun btn-init () {
        (if cfg-btn-en {
                ; the common pin is driven low so it acts as a local ground
                ; and only on a pin a button may use (pin-free): a pin typed into
                ; the settings page goes live before any load check sees it
                (if (pin-free cfg-btn-gnd) {
                        (trap (gpio-configure cfg-btn-gnd 'pin-mode-out))
                        (trap (gpio-write cfg-btn-gnd 0))
                })
                (var ru (if (pin-free cfg-btn-up) (trap (gpio-configure cfg-btn-up 'pin-mode-in-pu)) '(reserved)))
                (var rd (if (pin-free cfg-btn-dn) (trap (gpio-configure cfg-btn-dn 'pin-mode-in-pu)) '(reserved)))
                (if (pin-free cfg-btn-3)
                    (trap (gpio-configure cfg-btn-3 'pin-mode-in-pu)))
                (print (list "btn-init up" cfg-btn-up (car ru)
                             "dn" cfg-btn-dn (car rd)
                             "3rd" cfg-btn-3 "gnd" cfg-btn-gnd))
        } (print "buttons disabled"))
})
(defun btn-mon () {
        (btn-init)
        (print "watching - press each button. 30s")
        (var pu 1) (var pd 1) (var p3 1)
        (var t0 (systime))
        (loopwhile (< (secs-since t0) 30.0) {
                (var u (btn-read cfg-btn-up))
                (var d (btn-read cfg-btn-dn))
                (var v3 (if (>= cfg-btn-3 0)
                            (btn-read cfg-btn-3) 1))
                (if (not-eq u pu) {
                        (print (list (if (= u 0) "UP pressed" "UP released")
                                     cfg-btn-up))
                        (setq pu u) })
                (if (not-eq d pd) {
                        (print (list (if (= d 0) "DOWN pressed" "DOWN released")
                                     cfg-btn-dn))
                        (setq pd d) })
                (if (not-eq v3 p3) {
                        (print (list (if (= v3 0) "THIRD pressed" "THIRD released")
                                     cfg-btn-3))
                        (setq p3 v3) })
                (sleep 0.02)
        })
        (print "monitor done")
})

(defun kid-send () {
        (var b (bufcreate 8))
        (bufset-u8 b 0 0xCA)          ; kid frame, distinct from the
        ;                                telemetry magic the link sends back
        (bufset-u8 b 1 (if kid-on 1 0))
        (bufset-u16 b 2 (to-i cfg-kid-mph))
        (bufset-u16 b 4 (to-i cfg-kid-w))
        (link-send b)
        (free b)
})

; Kept here as well as on the link (slot 167), so a restarted dash still
; knows, and sent again whenever the link comes back. And on Bluetooth too:
; with no link the limiter was a gesture that did nothing.
(defun kid-set (on) {
        (def kid-on on)
        (def kid-known true)
        (eeprom-store-i 167 (if on 1 0))
        (def vb-kid-t nil)
        (spawn (fn () (looprange k 0 3 { (kid-send) (sleep 0.1) })))
        (if (not (link-carries)) {
                (vb-mode-apply cfg-mode)
                ; at once rather than on the next heartbeat
                (vb-mode-frame cfg-mode)
        })
})
; Both buttons at once carries two gestures, told apart by how long they
; are held rather than by which buttons: past five seconds sets the speed
; limiter, and a release between one and three toggles road mode. The
; limiter sets kid-done so that letting go afterwards cannot also land in
; the road mode window on the way back up.
(defun kid-check-enter (u d) {
        (if (and (= u 0) (= d 0)) {
                (if (= kid-hold 0) { (def kid-hold (systime)) (def kid-done false) })
                (if (and (not kid-on) (not kid-done) (> (secs-since kid-hold) 5.0)) {
                        (kid-set true)
                        (def kid-done true)
                })
        } {
                (if (and cfg-d-en (> kid-hold 0) (not kid-done)) {
                        (var held (secs-since kid-hold))
                        (if (and (> held 1.0) (< held 3.0)) (mode-toggle-d))
                })
                (def kid-hold 0)
                (def kid-done false)
        })
})
(defun kid-tap () {
        (if (> (secs-since kid-first) 4.0) { (def kid-taps 0) })
        (if (= kid-taps 0) (def kid-first (systime)))
        (def kid-taps (+ kid-taps 1))
})

(defun kid-check-exit (held) {
        (if (and kid-on (>= kid-taps 5) (> held 5.0)) {
                (kid-set false)
                (def kid-taps 0)
                true
        } false)
})

; --- orientation, modes and button actions -------------------------------
(defun apply-orient () {
        ; Never change what the rider asked for. If the buffer for the wanted
        ; shape will not allocate, keep the current one and say so.
        (var want cfg-vertical)
        (if (fb-use want) {
                (ext-disp-orientation
                    (if want (if (= cfg-orient 1) 2 0)
                             (if (= cfg-orient 1) 1 3)))
                true
        } {
                (print "orientation failed, keeping current")
                (fb-use (not want))
                (ext-disp-orientation
                    (if (not want) (if (= cfg-orient 1) 2 0)
                                   (if (= cfg-orient 1) 1 3)))
                false
        })
})


; Only reverse and neutral are blocked while moving. Shifting between the
; forward modes is something a rider does mid ride.
;
; A cart is not a bike. Its modes are the whole throttle map, and the
; driver picks one by tapping a chip rather than by thumbing a bar button
; they are already holding - so a change at speed is a lurch rather than a
; decision. Cart mode locks every mode change above the same threshold,
; not only the ones below drive. The chip already says STOP when a change
; is refused, so this needs no new screen furniture.
(defun gear-locked (m)
    (and (or (< m 1) cfg-simple) (> (abs d-speed) cfg-mode-lock)))

; Modes over a BLE link.
;
; send-mode sends the mode to a paired cu_link board to apply over CAN. A
; cart may have no link board, and then the mode has to reach the controller
; over the Bluetooth link instead.
;
; With dash_esc on the controller that is just the mode number (vb-mode-
; frame); dash_esc owns what each mode means. Only a controller with no
; package gets limits from here (vb-mode-apply), as
; COMM_SET_MCCONF_TEMP_SETUP with store off, so a power cycle hands it back
; its flashed config. The current fields of that command are scales of the
; controller's own limits, not amps (see vb-mode-apply); there is no battery
; current field, so the mode's battery amps become a watt limit.
; How the drive mode reaches the controller.
;
; dash35b sends its mode as CAN frame 201, ten times a second, and the
; dash_esc package on the controller owns what that mode means: it holds the
; per-mode current, speed and brake settings and applies them with
; set-profile. The display asks, the controller decides. Everything that
; comes with that is shared rather than reimplemented here - arbitration when
; two displays disagree, the brief hold that stops the limits flicking while
; they catch up, restoring the owner's own limits when a display goes away,
; and suspending the profile during motor detection, which is what made
; detection fail while this dash was writing the configuration itself.
;
; This display has no CAN of its own, so it sends the same frame over its
; Bluetooth link as custom app data - [201][mode][lights] - and dash_esc
; routes it into the same handler a CAN frame lands in.
;
; Vedder numbers modes 0 reverse, 1 neutral, 2 3 4 for the drive modes. This
; dash numbers them -1, 0, 1 2 3. The same order, offset by one.
; Built once and refilled, not created and freed ten times a second. The
; array pool this comes out of is the same one the framebuffer and the faces
; live in, and it is tight enough that the largest free block after boot was
; measured at 28k: churning it at 10Hz fragments it, and the damage shows up
; later and more often, as a Bluetooth link that drops at an increasing rate
; on a board doing nothing at all.
(def vb-mode-buf nil)

; Cruise is a toggle at the controller, so a cancel sent when it is already
; off turns it on. Cancel only on a report that it is on, fresh (under a
; second old) and made at least half a second after the last cancel: two
; presses inside the report's lag sent two toggles, off and on again. A
; Bluetooth-only bike hears the state only from a controller package that
; mirrors frame 202 (cu_esc_base 1.0.2 and later); until then this never fires there.
(def cruise-cancel-t 0)
(defun cruise-cancel-ok ()
    (and (= x-cruise 1) (< (secs-since x-cruise-t) 1.0)
         (< (secs-since x-cruise-t) (- (secs-since cruise-cancel-t) 0.5))))

(defun cruise-toggle () (if (not cfg-simple) (if (and (not (link-carries)) cfg-vb-en vb-linked)
(vb-cruise) (send-aux 6 true))))

; Cruise, with the controller on Bluetooth and no link carrying: dash_esc's
; own event frame, 250 with 0 for "toggle cruise", in the same [sid][payload]
; shape as the mode. It went to the link only, so on a Bluetooth-only bike
; the cruise button did nothing (bench, 2026-10-27, Charged Up ESC).
(defun vb-cruise () (if (not cfg-simple) {
(var b (bufcreate 3))
(bufset-u8 b 0 36) (bufset-u8 b 1 250) (bufset-u8 b 2 0)
(trap (vb-send b))
(free b)
}))

(def vb-kid-buf nil)
(def vb-kid-t nil)
(defun vb-kid-frame () {
    (if (and kid-known cfg-vb-en vb-linked (not (link-carries))
             (or (not vb-kid-t) (> (secs-since vb-kid-t) 1.0))) {
        (if (not vb-kid-buf) (def vb-kid-buf (bufcreate 9)))
        (bufset-u8 vb-kid-buf 0 36) (bufset-u8 vb-kid-buf 1 212)
        (bufset-u8 vb-kid-buf 2 0x4B) (bufset-u8 vb-kid-buf 3 1)
        (bufset-u8 vb-kid-buf 4 (if kid-on 1 0))
        (bufset-u16 vb-kid-buf 5 (to-i cfg-kid-mph))
        (bufset-u16 vb-kid-buf 7 (to-i cfg-kid-w))
        (vb-send vb-kid-buf)
        (def vb-kid-t (systime))
    })
})

(defun vb-mode-frame (m) {
        (vb-kid-frame)
        ; Kids mode with dash_esc: never above mode 1, the link's rule
        ; (cu_link_core send-201). dash_esc owns the limits, so vb-mode-apply
        ; stays out, and the limiter is its mode 1; without this the gesture
        ; did nothing on a Bluetooth-only bike.
        (var mm (if (and kid-on (esc-present) (> m 1)) 1 m))
        (if (not (and cfg-vb-en vb-linked)) false {
                (if (eq vb-mode-buf nil) (def vb-mode-buf (bufcreate 4)))
                (bufset-u8 vb-mode-buf 0 36)    ; COMM_CUSTOM_APP_DATA
                (bufset-u8 vb-mode-buf 1 201)   ; the frame a CAN display sends
                (bufset-u8 vb-mode-buf 2 (+ mm 1))
                (bufset-u8 vb-mode-buf 3 (if sig-beam 1 0))
                (eq (car (trap (vb-send vb-mode-buf))) 'exit-ok)
        })
})

(defun vb-mode-apply (m) {
        ; never into a controller whose limits dash_esc owns
        (if (or cfg-simple (not (and cfg-vb-en vb-linked)) (esc-present)) nil {
                (var bat (to-float (mode-bat m)))
                (var spd (to-float (mode-spd m)))
                (var volts (if (> d-volt 5.0) d-volt 50.0))
                ; the limiter, as the link applies it: its speed, its watts
                (var kspd (* cfg-kid-mph 1.60934))
                (if (and kid-on (or (<= spd 0.0) (< kspd spd))) (setq spd kspd))
                ; The two current fields are SCALES of the controller's own
                ; limits, 0 to 1 - not amps, whatever was believed here
                ; before. 7.00 clamps them, so -100 for braking became 0 (no
                ; regen at all) and 100 for drive became 1; 6.x takes them as
                ; they come, so -100 was a negative scale and 100 a hundred
                ; times the motor limit (bldc commands.c, 6.02 to 7.00). This
                ; dash does not know the controller's amps, so a mode cannot
                ; be a current fraction here: braking stays whole, drive is
                ; whole or nothing, and the mode limits through what is known
                ; absolutely - its top speed, and its battery amps as watts.
                ;
                ; Neutral and reverse drive nothing; braking is left alone in
                ; every mode, rolling in neutral included.
                (var drive (>= m 1))
                (var w (if (and drive (> bat 0.0)) (* bat volts) 1500000.0))
                (if (and kid-on (< cfg-kid-w w)) (setq w cfg-kid-w))
                (var b (bufcreate 37))
                (bufset-u8 b 0 49)
                (bufset-u8 b 1 0)   ; store off - RAM only
                (bufset-u8 b 2 1)   ; forward over CAN to any slaves
                (bufset-u8 b 3 0)   ; no ack
                (bufset-u8 b 4 0)   ; do not divide between controllers
                (bufset-f32 b 5  1.0)                       ; braking scale
                (bufset-f32 b 9  (if drive 1.0 0.0))        ; drive scale
                (bufset-f32 b 13 (if (and drive (> spd 0.0)) (- 0.0 (/ spd 3.6)) -100.0))
                (bufset-f32 b 17 (if (and drive (> spd 0.0)) (/ spd 3.6) 100.0))
                (bufset-f32 b 21 0.0)
                (bufset-f32 b 25 0.95)
                (bufset-f32 b 29 -1500000.0)
                (bufset-f32 b 33 (if drive w 0.0))
                (var r (trap (vb-send b)))
                (free b)
                (eq (car r) 'exit-ok)
        })
})

; Out of reverse into drive only at a standstill as well. mode-step always
; kept R while moving, but the cycle, the straight-to-a-mode buttons and an IO
; reverse switch turned off all sent a forward mode at once, so drive came on
; while the bike was still rolling backwards.
(defun rev-locked (m)
    (and (= cfg-mode -1) (>= m 1) (> (abs d-speed) cfg-mode-lock)))

; Cart controls require a fresh controller package status. Stock firmware
; remains available for native telemetry without temporary limit writes.
(defun cart-package-live () (and esc-ever (< (secs-since esc-seen) 2.0)))

(defun send-mode (m) {
        (if (or (and cfg-simple (!= m 0) (not (cart-package-live))) (and (!= m 0) (or (hall-locked) (setup-locked))) (gear-locked m) (rev-locked m) (and (= m 4) (= cfg-mode -1))) {
                (def mode-blocked (if (and cfg-simple (not (cart-package-live))) 0 (systime)))
                ; and road mode not straight from reverse: a controller
                ; package with no road mode leaves the mode as it was, and
                ; from R that kept the bike reversing under a D
                (print (cond ((and cfg-simple (not (cart-package-live))) "Charged Up package required for cart modes")
                             ((= m 4) "leave reverse before road mode")
                             (cfg-simple "stop before changing mode")
                             ((rev-locked m) "stop before leaving reverse")
                             (t "stop before selecting neutral or reverse")))
                false
        } {
                ; Marked as the rider's own change before anything changes.
                ; Stamped after, as it was, a frame from the controller still
                ; reporting the old mode could land in between, find no recent
                ; change, and have the dash adopt the old mode back - which it
                ; then sent to the link at the same count, and the link took
                ; it (bench: Mode 1, then Neutral in the same second).
                (def esc-mode-ts (systime))
                ; a later choice, from anywhere, replaces a switch's refused one
                (def io-want nil)
                (def cfg-mode m)
                (def mode-state (cons m (mod (+ (if mode-state (cdr mode-state) 0) 1) 256)))
                (link-mode-frame mode-state)
                ; and twice more within a tenth of a second each, so a lost
                ; ESP-NOW frame costs 0.1 s rather than the second until the
                ; next repeat
                (if (link-carries)
                    (spawn (fn () (looprange k 0 3 { (sleep 0.1) (link-mode-frame mode-state) }))))
                ; and to the controller directly, for anyone without a link
                ; board in between. With the dash_esc package on the far end
                ; the mode is a request and the limits are its business; the
                ; old path writes the limits from here and stays for a
                ; controller that has no package on it.
                (def esc-mode-ts (systime))
                ; The frame costs four bytes and a controller with no package
                ; on it ignores it, so it always goes out - that is also what
                ; makes the package announce itself. The old path, which
                ; writes the limits from here, runs only while nothing has
                ; answered, so a bare controller behaves as it always did and
                ; one running dash_esc is left to own its own configuration.
                ; One source of the mode at a time. With a link present it
                ; carries it, and the Bluetooth link to the controller only
                ; reads. Both at once, dash_esc took the mode from two
                ; senders that briefly disagreed after every change - the
                ; link still on the old one until its frame arrived - and 3
                ; changes in 94 settled on the old mode (bench, 2026-10-05).
                ; The limit fallback is the link's job then as well.
                (if (not (link-carries)) {
                        (vb-mode-frame m)
                        ; and not in the first seconds of a link, before
                        ; dash_esc has had the chance to answer: then it
                        ; waits, see the vb-mode-pending check in vescble
                        (if (not (esc-present))
                            (if (and (>= vb-first vb-up) (> (secs-since vb-first) 5.0))
                                (vb-mode-apply m)
                                (def vb-mode-pending true)))
                })
                true
        })
})

; Up clamps at 3 and never wraps. Down stops at 1 while moving; stopped, it
; continues into neutral and reverse.
; Cycle wraps: 1, 2, 3, then neutral, then back to 1. Reverse is never in the
; cycle - it is destructive to hit by accident, so it lives on its own action
; that a rider can assign to a hold if they want it.
; D is deliberately a dead end for the ordinary controls. Somebody who has
; put the bike into its road mode has usually done so because a rule says
; to, and a mode you can leave by leaning on a handlebar button is not a
; mode, it is a suggestion.
(defun mode-cycle () {
        (if (= cfg-mode 4) nil {
        (var m (cond ((= cfg-mode 3) 0)
                     ((= cfg-mode 0) 1)
                     ((= cfg-mode -1) 1)
                     (t (+ cfg-mode 1))))
        ; Neutral is only reachable at a standstill - and on a cart, not at
        ; all. Cart mode means no reverse and no neutral, but the wrap from
        ; the top mode still went through it, so one press off mode 3 parked
        ; a cart in N: the chip reads N, the cart will not drive, and it
        ; looks like the mode button has stopped working rather than like a
        ; gear it never had. Cart mode wraps 1, 2, 3, 1.
        (if (and (= m 0) (or cfg-simple (> (abs d-speed) cfg-mode-lock)))
            (setq m 1))
        (if (!= m cfg-mode) (send-mode m))
        })
})

(defun mode-step (d) {
        (if (= cfg-mode 4) nil {
        (var stopped (< (abs d-speed) 1.6))
        (var lo (if (and cfg-rev-en (not cfg-simple) stopped) -1 1))
        (var m (+ cfg-mode d))
        (if (> m 3) (setq m 3))
        (if (< m lo) (setq m lo))
        (if (and (= cfg-mode -1) (not stopped)) (setq m -1))
        (if (!= m cfg-mode) (send-mode m))
        })
})

; Walk assist. The button is a dead man rather than a toggle: while it is
; down the dash repeats the frame, and the link cuts the motor as soon as
; they stop arriving. A toggle would mean a dropped release packet leaves a
; bike walking away from whoever let go of it.
;
; It will not start above walking pace, and it stops itself if the bike gets
; away - somebody has stopped pushing and started riding, and the assist is
; not what should be driving that.
(defun walk-stop () {
        (if walk-on {
                (def walk-on false)
                ; three times, because this is the message that matters and
                ; esp-now does not retry a broadcast
                (send-aux 8 false) (send-aux 8 false) (send-aux 8 false)
                (print "walk off")
        })
})

(defun walk-tick (down) {
        (if (and down (not walk-on) (not cfg-simple)
                 (< (abs d-speed) (to-float cfg-walk-kph)))
            { (def walk-on true) (def walk-tx 0) (print "walk on") })
        (if (and walk-on (not down)) (walk-stop))
        (if (and walk-on (> (abs d-speed) (+ (to-float cfg-walk-kph) 4.0)))
            (walk-stop))
        ; repeated rather than sent once, so the link can time it out
        (if (and walk-on (> (secs-since walk-tx) 0.15))
            { (def walk-tx (systime)) (send-aux 8 true) })
})

; Hold for reverse. The rider holds the button, twists, and the bike backs
; up; let go and it is in a forward gear again. Same dead man shape as walk
; assist, and for the same reason - a reverse you have to remember to switch
; off is a reverse you will forget to switch off.
;
; Two things decide when it lets go, and both are about not lurching. It will
; not hand back a forward gear while the bike is still rolling, which is the
; rule the ordinary reverse toggle already follows. And it will not hand one
; back while the throttle is still open: letting go of the button with a
; twist still on would otherwise turn a reverse into a jump forwards, which
; is exactly the moment somebody is standing in front of it.
(defun rev-tick (down) {
        (var stopped (< (abs d-speed) 1.6))
        (var idle (< (abs d-duty) 0.03))
        (if (and down (not rev-hold) cfg-rev-en (not cfg-simple)
                 (!= cfg-mode 4) (!= cfg-mode -1) stopped idle) {
                (def rev-prev (if (< cfg-mode 1) 1 cfg-mode))
                (def rev-hold true)
                (def rev-wait false)
                (send-mode -1)
                (print "reverse held")
        })
        (if (and rev-hold (not down)) {
                (def rev-hold false)
                (def rev-wait true)
        })
        (if (and rev-wait stopped idle) {
                (def rev-wait false)
                ; only if it is still ours to give back - the rider may have
                ; changed gear by hand in the meantime
                (if (= cfg-mode -1) (send-mode rev-prev))
                (print "reverse released")
        })
})

(defun btn-action (a0) (btn-run a0))

; A CU IO Link switch event: v 2 is a press, 1 and 0 an on/off switch going
; on and off. Set up on the link for exactly this, so cart mode does not
; swap it for something else the way it does the display's own buttons.
(defun io-run (a v) (cond
((and cfg-simple (bike-action a))
(if (or (= v 1) (= v 2)) (btn-run a)))
((= v 2) (btn-run a))
((= a 8) { (def sig-left (= v 1)) (if sig-left (def sig-right false))
(def st-turn-l sig-left) (def st-turn-r sig-right)
(send-aux 1 sig-left) })
((= a 9) { (def sig-right (= v 1)) (if sig-right (def sig-left false))
(def st-turn-l sig-left) (def st-turn-r sig-right)
(send-aux 2 sig-right) })
((= a 10) { (def sig-hazard (= v 1))
(def st-turn-l sig-hazard) (def st-turn-r sig-hazard)
(send-aux 3 sig-hazard) })
((= a 11) { (def sig-beam (= v 1)) (def st-beam sig-beam) (send-aux 4 sig-beam) })
((and (= cfg-mode 4) (or (= a 16) (= a 27) (and (>= a 24) (<= a 26)))) nil)
((or (= a 16) (= a 27) (and (>= a 24) (<= a 26))) {
(var m (cond ((= a 16) -1) ((= a 27) 0) (t (- a 23))))
(var to (if (= v 1) m (if (= cfg-mode m) io-prev nil)))
(if (= v 1) (if (>= cfg-mode 1) (def io-prev cfg-mode)))
(if (and to (not (send-mode to))) (def io-want to))
})
(t nil)))


(def io-want nil) (def io-try-t 0)
(defun io-retry ()
    (if (and io-want (> (secs-since io-try-t) 0.5)) {
            (def io-try-t (systime))
            (send-mode io-want)
    }))

(defun btn-run (a) {
(if (and cfg-simple (bike-action a)) (setq a (cart-sub a)))
(if (and (not cfg-simple) cfg-cruise-cancel (!= a 13) (cruise-cancel-ok)) {
(def cruise-cancel-t (systime))
(cruise-toggle)
})
(cond
((= a 1) (mode-step 1))
((= a 2) (mode-step -1))
((= a 3) (mode-cycle))
((= a 4) (page-step 1))
((= a 5) (page-step -1))
((= a 6) (def page 0))
((= a 7) (def cfg-show-modestrip (not cfg-show-modestrip)))
((= a 8) {
(def sig-left (not sig-left))
(if sig-left (def sig-right false))
(def st-turn-l sig-left) (def st-turn-r sig-right)
(send-aux 1 sig-left) })
((= a 9) {
(def sig-right (not sig-right))
(if sig-right (def sig-left false))
(def st-turn-l sig-left) (def st-turn-r sig-right)
(send-aux 2 sig-right) })
((= a 10) {
(def sig-hazard (not sig-hazard))
(def st-turn-l sig-hazard) (def st-turn-r sig-hazard)
(send-aux 3 sig-hazard) })
((= a 11) {
(def sig-beam (not sig-beam))
(def st-beam sig-beam)
(send-aux 4 sig-beam) })
((= a 12) (send-aux 5 true))
((= a 13) (cruise-toggle))
((= a 14) { (trip-reset) (send-aux 7 true) })
((= a 15) (bl-toggle))
((= a 16) (mode-toggle-rev))
((= a 17) (bl-step 1))
((= a 18) (bl-step -1))
((= a 21) (if (< (abs d-speed) cfg-mode-lock) (ble-open)))
((= a 22) (if (< (abs d-speed) cfg-mode-lock)
(def vb-paused (not vb-paused))))
((= a 23) {
(def cfg-ab-en (not cfg-ab-en))
(eeprom-store-i 149 (if cfg-ab-en 1 0))
(if cfg-ab-en (trap (ab-start))
{ (trap (ble-disconnect 1)) (def ab-linked false) })
})
((and (= cfg-mode 4) (>= a 24) (<= a 27)) nil)
((= a 24) (send-mode 1))
((= a 25) (send-mode 2))
((= a 26) (send-mode 3))
((= a 27) (if (= cfg-mode 0) (send-mode btn-prev)
{ (if (>= cfg-mode 1) (def btn-prev cfg-mode)) (send-mode 0) }))
((= a 28) (send-aux 11 true))
((= a 29) (send-aux 12 true))
((= a 30) (send-aux 9 true))
((= a 31) (whl-arm-toggle))
(t nil))
})


(defun btn-edge (pin prev tdown fired short long)
    (btn-edge-v (btn-read pin) prev tdown fired short long))

(defun btn-edge-v (now prev tdown fired short long) {
        (var t2 tdown)
        (var f2 fired)
        (if (and (= now 0) (= prev 1)) {
                (setq t2 (systime))
                (setq f2 false)
                ; nothing to disambiguate, so act at once
                (if (= long 0) { (btn-action short) (setq f2 true) })
        })
        (if (and (= now 0) (not f2) (> long 0) (> (secs-since t2) 0.7))
            { (btn-action long)
              ; brightness repeats while held, everything else fires once
              (if (or (= long 17) (= long 18))
                  ; ticks are milliseconds: 0.55 here was half a tick,
                  ; so each repeat waited the full 0.7 s
                  (setq t2 (- (systime) 550))
                  (setq f2 true)) })
        (if (and (= now 1) (= prev 0) (not f2) (> long 0))
            (btn-action short))
        (list now t2 f2)
})

(defun btn-thread () {
        (var pu 1) (var pd 1) (var p3 1)
        (var tu 0) (var td 0) (var t3 0)
        (var fu false) (var fd false) (var f3 false)
        (loopwhile t {
                (io-retry)
                (if cfg-btn-en {
                        ; raw states first, the kid gestures watch these
                        (var ru0 (btn-read cfg-btn-up))
                        (var rd0 (btn-read cfg-btn-dn))
                        (kid-check-enter ru0 rd0)

                        ; while both are held the normal actions are suppressed
                        (var both (and (= ru0 0) (= rd0 0)))

                        (if (not both) {
                                (var ru (btn-edge cfg-btn-up pu tu fu
                                                  cfg-btn-up-s cfg-btn-up-l))
                                (setq pu (ix ru 0)) (setq tu (ix ru 1))
                                (setq fu (ix ru 2))
                                (var rd (btn-edge cfg-btn-dn pd td fd
                                                  cfg-btn-dn-s cfg-btn-dn-l))
                                (setq pd (ix rd 0)) (setq td (ix rd 1))
                                (setq fd (ix rd 2))
                        } {
                                (setq pu ru0) (setq pd rd0)
                                ; marked fired: let go one at a time, the
                                ; other's long action (its press time is from
                                ; before both) and the released one's short
                                ; action both went off after the gesture
                                (setq fu true) (setq fd true)
                        })

                        (if (>= cfg-btn-3 0) {
                                (var v3 (btn-read cfg-btn-3))
                                (if (and (= v3 0) (= p3 1)) {
                                        (setq t3 (systime))
                                        (setq f3 false)
                                        (kid-tap)
                                        (if (= cfg-btn-3-l 0)
                                            { (btn-action cfg-btn-3-s)
                                              (setq f3 true) })
                                })
                                ; The exit gesture is checked even after the
                                ; short action has fired, otherwise clearing
                                ; the long action would lock kids mode on.
                                (if (and (= v3 0) kid-on
                                         (kid-check-exit (secs-since t3)))
                                    (setq f3 true))
                                (if (and (= v3 0) (not f3) (> cfg-btn-3-l 0)
                                         (> (secs-since t3) 0.7))
                                    { (btn-action cfg-btn-3-l) (setq f3 true) })
                                (if (and (= v3 1) (= p3 0) (not f3)
                                         (> cfg-btn-3-l 0))
                                    (btn-action cfg-btn-3-s))
                                (setq p3 v3)
                        })

                        (if (and btn-debug (or (= pu 0) (= pd 0) (= p3 0)))
                            (print (list "btn" pu pd p3)))
                })

                ; the holds, from a display button or a link switch alike
                (var wd (hold-state 19))
                (if (>= wd 0) (walk-tick (= wd 0)) (if walk-on (walk-stop)))
                (var rd (hold-state 20))
                (if (>= rd 0)
                    (rev-tick (= rd 0))
                    ; unassigned while it was still held down: give
                    ; the gear back rather than leaving it in reverse
                    (if (or rev-hold rev-wait) (rev-tick false)))
                (sleep 0.02) })
})

; A CU IO Link's hold reverse. It drives the motor, so a link that has gone
; quiet for half a second has let go. (Its walk assist runs on the link.)
(defun io-live () (and io-seen (< (secs-since io-sw-t) 0.5)))

; Hold action a (19 walk, 20 reverse): -1 nothing is assigned it, 0 held,
; 1 assigned and up.
(defun hold-state (a) {
        (var pin (if cfg-btn-en (cond
                ((= cfg-btn-up-s a) cfg-btn-up)
                ((= cfg-btn-dn-s a) cfg-btn-dn)
                ((and (>= cfg-btn-3 0) (= cfg-btn-3-s a)) cfg-btn-3)
                (t -1)) -1))
        (var pdown (and (>= pin 0) (= 0 (btn-read pin))))
        (var idown (and (= a 20) io-rev (io-live)))
        (cond ((or pdown idown) 0) ((>= pin 0) 1) (t -1))
})

@const-end
