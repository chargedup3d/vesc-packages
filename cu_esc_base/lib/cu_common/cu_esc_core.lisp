;! Charged Up ESC core: the display side of a controller package.
;! Vedder's dash_esc CAN protocol, plus the same frames over Bluetooth app data.
;! The package defines apply-drive-mode, display-event and display-stop.
; ============================================================================
; cu_esc_core - the controller side of the Charged Up platform
;
; Included by a motor controller package so that every display works with it:
; VESC Labs CAN screens (Dash 35B, Dash 16) and anything else built for
; vedderb's dash_esc, the CUP-3.5 over Bluetooth, and the Charged Up links on
; CAN. It speaks dash_esc's display protocol exactly - it is dash_esc's
; display half, lifted out - plus one addition of ours: a display reached
; over Bluetooth sends and receives the same frames as custom app data,
; shaped [sid][payload]. It never changes the meaning of a dash_esc frame, so
; a VESC Labs screen and a CUP-3.5 can sit on one controller at once.
; Protocol: CHARGED_UP_PLATFORM.md, section 3.
;
; What it does:
;   in   201 [mode][light]  the display's mode (0 R, 1 N, 2-4 modes 1-3) and
;                           headlight, ten a second; a new mode is held 0.3 s
;                           against a second display that has not caught up
;        203 [brk][volts]   the display's brake lever, onto ADC2
;        250 [ev]           0 cruise toggle, 1 about to power off, 2 logging
;        35  [..][chg][time][ah]  a BMS display's charging state
;   out  20-24, 202, 25     the status frames, ten a second
;   and  reverse on the ADC reverse input in mode 0, cruise control, the
;        light on AUX 1 and 2 - all as dash_esc does them
;
; What the package defines - functions, by these names:
;   (apply-drive-mode m)   every mode frame, after the hold, m 0-4: apply the
;                          limits for it (ten a second - write on a change)
;   (display-event ev)     events 1 and 2 (cruise, 0, is the core's)
;   (display-stop)         the firmware is shutting down
; and keeps these, which frame 25 reports: log-running, profile-suspend,
; motor-config-bad.
;
; Usage, in the package's main file:
;   (import "../cu_common/cu_esc_core.lisp" 'cu-esc-core)
;   (read-eval-program cu-esc-core)
;   ... (esc-core-start) in main.
;
; Kept low on symbols - it uses dash_esc's own names, and the package's
; three are called by name rather than through hook variables: the cart's
; 75100 (firmware 7.00) could not take one new symbol with v12.9 loaded
; (bench gotcha 17). It adds four.
; ============================================================================

@const-start

(defmacro run-m2 (code) `(atomic {
            (var res nil)
            (select-motor 2)
            (setq res ,code)
            (select-motor 1)
            res
}))

(defun has-dual-motors () {
        (atomic
            (var motor-before (get-selected-motor))
            (select-motor 2)
            (var res (= (get-selected-motor) 2))
            (select-motor motor-before)
            res
        )
})

(defun proc-sid (id data) {
        (cond
            ((= id 35) {
                    (setq battery-a-charging (= (bufget-u8 data 2) 1))
                    (setq battery-a-chg-time (bufget-u16 data 3))
                    (setq stats-battery-ah (/ (bufget-u16 data 5) 10.0))
            })

            ((= id 201) {
                    (setq display-ts (systime))
                    (var drive-mode-new (bufget-u8 data 0))
                    (setq light-on (bufget-u8 data 1))

                    ; A mode with no profile here (a CUP-3.5's road mode is 5)
                    ; is not taken: the mode stays, and frame 25 goes on
                    ; reporting it, so the display sees they differ. Except
                    ; reverse, which becomes neutral - ignored, from R it kept
                    ; the reverse input held and the bike drove backwards.
                    (if (> drive-mode-new 4)
                        (setq drive-mode-new (if (= drive-mode 0) 1 drive-mode)))

                    ; A second display that has not caught up yet keeps sending
                    ; the previous mode for a frame or two. Hold a new mode
                    ; briefly so the limits cannot flick between two modes while
                    ; the others catch up.
                    (if (and (!= drive-mode-new drive-mode)
                             (< (secs-since mode-ts) 0.3))
                        (setq drive-mode-new drive-mode))

                    (if (!= drive-mode drive-mode-new) {
                            (setq cruise-on 0)
                            (setq mode-ts (systime))
                    })

                    (setq drive-mode drive-mode-new)

                    ; the limits are the package's; a mode outside 0-4 is
                    ; ignored, as dash_esc ignores it
                    (if (and (>= drive-mode 0) (<= drive-mode 4)) {
                            (apply-drive-mode drive-mode)
                            ; reverse is the ADC app's reverse input
                            (app-adc-override 2 (if (= drive-mode 0) 1 0))
                            (app-adc-detach adc-detach-mode 3)
                    })

                    (if (= light-on 1)
                        {
                            (set-aux 1 1)
                            (set-aux 2 1)
                        }
                        {
                            (set-aux 1 0)
                            (set-aux 2 0)
                        }
                    )
            })

            ((= id 212) {
                (if (and esc-kid-handler (>= (buflen data) 7)
                         (= (bufget-u8 data 0) 0x4B) (= (bufget-u8 data 1) 1))
                    (esc-kid-handler data))
            })

            ((= id 203) {
                    (setq val-brk (/ (bufget-i16 data 0) 1000.0))
                    (setq volts-brk (/ (bufget-i16 data 2) 1000.0))
                    (if (> val-brk 0.05) (setq cruise-on 0))

                    (setq adc-detach-mode 3)
                    (app-adc-override 1 volts-brk)
                    (app-adc-detach adc-detach-mode 3) ; Detach ADC2
            })

            ; Event
            ((= id 250) {
                    (if (= (bufget-u8 data 0) 0) { ; Toggle cruise control
                            ; Start the grace timer before publishing the on
                            ; flag to the concurrent cruise worker.
                            (if (= cruise-on 0) {
                                    (setq cruise-ts (systime))
                                    (setq cruise-on 1)
                                } (setq cruise-on 0))
                        }
                        (display-event (bufget-u8 data 0)))
            })
        )
})

; Custom app data carries two kinds of traffic.
;
; The code server and the settings UI send LispBM as text, which is what this
; channel has always been for. A display that reaches the controller over
; Bluetooth rather than CAN has no bus of its own, so it sends the frames a
; CAN display would send, as [sid][payload...] - up to eight payload bytes,
; the same as a CAN frame carries. Both end up in proc-sid, so the drive
; mode arbitration, the hold that stops two displays flicking the limits, the
; profile writing and the display timeout are shared rather than written once
; per transport.
;
; The two are told apart by the first byte: LispBM always opens a list, so a
; frame beginning with an opening paren is text. A sid of 40 is therefore not
; addressable this way, which is free - nothing uses it.
;
; The other direction. A display on the bus hears the status frames; one on a
; data link does not, so mirror them there in the same shape the inbound
; frames take - [sid][payload...] - and a display needs one parser for both
; directions rather than two. Only 25 (the mode applied) and 202 (cruise):
; a display on a data link reads its telemetry by polling, so 20-24 would be
; ten frames a second it never uses.
;
; Only while such a display is actually present. A controller with nothing on
; the link should not be writing to it ten times a second, and five seconds
; is the same silence dash_esc already uses to decide a display has gone.
;
; out is the sender's own nine bytes, made once: allocating here, twice every
; tenth of a second in a thread nothing restarts, put every status frame at
; the mercy of one failed allocation.
(defun send-frame (sid buf out) {
        (can-send-sid sid buf)
        (if (< (secs-since data-link-ts) 5.0) {
                (bufset-u8 out 0 sid)
                (looprange i 0 8 (bufset-u8 out (+ i 1) (bufget-u8 buf i)))
                (send-data out)
        })
})

(defun proc-data-rx (data) {
        (if (= (bufget-u8 data 0) 40)
            (eval (read data))
            {
                (setq data-link-ts (systime))
                ; exactly as long as the frame, as a CAN frame is: padded to
                ; eight with zeros, a bare [201] read as mode 0 (reverse), a
                ; bare [203] as brake 0 with ADC2 detached, and a bare [250] as
                ; a cruise toggle. Short now errors out under the handler's
                ; trap, the same as a short CAN frame always has.
                (var n (- (buflen data) 1))
                (if (> n 8) (setq n 8))
                (var f (bufcreate n))
                (looprange i 0 n (bufset-u8 f i (bufget-u8 data (+ i 1))))
                (proc-sid (bufget-u8 data 0) f)
                (free f)
            })
})

(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data)) (trap (proc-data-rx data)))
            (event-shutdown (display-stop))
            ((event-can-sid . ((? id) . (? data))) (trap (proc-sid id data)))
            (_ nil)
)))

(defun cruise-step () {
        ; Brake release must not re-engage a latched cruise request. ADC2 is
        ; a brake only in these two current-control app modes; leave unused
        ; or differently assigned ADC2 pins out of the cancellation decision.
        (var adc-type (conf-get 'adc-ctrl-type))
        (if (or
                (< drive-mode 2)
                (> val-brk 0.05)
                (and (or (= adc-type 4) (= adc-type 8))
                     (> (get-adc-decoded 1) 0.05))
                (and (> (secs-since cruise-ts) 1)
                     (< (* (abs (get-speed-set)) 3.6) 5.0))
                (and (> (secs-since cruise-ts) 2)
                     (> (abs (get-adc-decoded 0)) 0.05)))
            (setq cruise-on 0))
        (app-adc-override 3 cruise-on)
})

(defun esc-core-start () {
        (event-register-handler (spawn event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-shutdown)
        (event-enable 'event-data-rx)

        ; the status frames, as dash_esc sends them
        (var buf-can (array-create 8))
        (var buf-out (array-create 9))   ; send-frame's mirror
        (loopwhile-thd ("Send CAN" 150) t {
                (bufclear buf-can)
                (bufset-i16 buf-can 0 (* (get-batt) 1000))
                (bufset-i16 buf-can 2 (* (abs (get-duty)) 1000))
                (bufset-i16 buf-can 4 (* (abs (get-speed)) 3.6 10))
                (bufset-i16 buf-can 6 (* (setup-current-in) (get-vin) 0.1))
                (can-send-sid 20 buf-can)

                (bufclear buf-can)
                (if (> (get-bms-val 'bms-temp-adc-num) 2)
                    (bufset-i16 buf-can 0 (* (get-bms-val 'bms-temps-adc 2) 10))
                    (bufset-i16 buf-can 0 0)
                )
                (bufset-i16 buf-can 2 (* (get-temp-fet) 10))
                (bufset-i16 buf-can 4 (* (get-temp-mot) 10))
                (bufset-i16 buf-can 6 (* (ix (get-imu-rpy) 1) 100))
                (can-send-sid 21 buf-can)

                (bufclear buf-can)
                (bufset-u16 buf-can 0 (* (setup-wh) 10.0))
                (bufset-u16 buf-can 2 (* (setup-wh-chg) 10.0))
                (bufset-u16 buf-can 4 (* (/ (get-dist-abs) 1000.0) 10))
                (bufset-u16 buf-can 6 (get-fault))
                (can-send-sid 22 buf-can)

                (bufclear buf-can)
                (if dual-motors
                    {
                        (bufset-u16 buf-can 0 (to-i (+ (stats 'stat-current-avg) (run-m2 (stats 'stat-current-avg)))))
                        (bufset-u16 buf-can 2 (to-i (+ (stats 'stat-current-max) (run-m2 (stats 'stat-current-max)))))
                        (bufset-i16 buf-can 4 (to-i (+ (get-current) (run-m2 (get-current)))))
                    }
                    {
                        (bufset-u16 buf-can 0 (to-i (stats 'stat-current-avg)))
                        (bufset-u16 buf-can 2 (to-i (stats 'stat-current-max)))
                        (bufset-i16 buf-can 4 (to-i (get-current)))
                    }
                )
                (bufset-u16 buf-can 6 (to-i (conf-get 'si-battery-ah)))
                (can-send-sid 23 buf-can)

                (bufclear buf-can)
                (bufset-u16 buf-can 0 (* (get-vin) 10))
                (bufset-u32 buf-can 2 (* (/ (sysinfo 'odometer) 1000.0) 10))
                (bufset-u16 buf-can 6 (* (abs (get-speed-set)) 3.6 10)) ; Cruise control speed
                ; Reserved space
                (can-send-sid 24 buf-can)

                (bufclear buf-can)
                (bufset-u8 buf-can 0 cruise-on)
                ; mirrored as well: a display on Bluetooth needs to know
                ; cruise is on before a press may cancel it (a cancel is a
                ; toggle, so one sent while it is off turns it on)
                (send-frame 202 buf-can buf-out)

                ; Logging state on an id of its own. 202 also carries the
                ; wheelie settings the other way, and a display cannot tell a
                ; controller's frame from another display's.
                (bufclear buf-can)
                (bufset-u8 buf-can 0 (if log-running 1 0))
                ; The mode this controller is actually applying, so every
                ; display shows the same thing rather than its own idea of it
                (bufset-u8 buf-can 1 drive-mode)
                (bufset-u8 buf-can 2 (if profile-suspend 1 0))
                (bufset-u8 buf-can 3 (if motor-config-bad 1 0))
                (bufset-u8 buf-can 4 esc-capabilities)
                ; mirrored to a data link display too: this is the frame
                ; that tells every display which mode is actually applied
                (send-frame 25 buf-can buf-out)

                (sleep 0.1)
        })

        (loopwhile-thd ("Cruise" 150) t {
                (cruise-step)
                (sleep 0.05)
        })
})

@const-end

(def light-on 0)
(def drive-mode 1)
(def val-brk 0.0)
(def volts-brk 0.0)

; 2 is buttons only, 3 is buttons and ADC. Initially only
; the buttons are detached, but once throttle is received
; ADC2 is detached and replaced by the dash16 throttle
(def adc-detach-mode 2)

(def cruise-on 0)
(def cruise-ts 0)

(def battery-a-charging false)
(def battery-a-chg-time 0.0)
(def stats-battery-ah 0.0)

; systime of the last drive-mode frame from a display
(def display-ts 0)

; systime of the last drive mode change, used to hold a new mode briefly
(def mode-ts 0)

; systime of the last frame from a display on the data link
(def data-link-ts 0)

(def dual-motors (has-dual-motors))

; reported in frame 25; the package keeps them
(def log-running false)
(def profile-suspend false)
(def motor-config-bad false)

; Optional customer mode/kids support. Old packages advertise no capability.
(def esc-kid-handler nil)
(def esc-capabilities 0)
