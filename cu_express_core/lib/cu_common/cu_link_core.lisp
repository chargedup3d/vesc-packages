;! Charged Up link core: controller data to the CUP-3.5 over ESP-NOW,
;! the screen's commands back onto CAN. With several link boards on one bus
;! one is elected bridge (core-role / core-prio).
; ============================================================================
; cu_link_core - the link side of the Charged Up platform
;
; Included by every package for an Express based Charged Up product (CU IO
; Link, the IMU board, what comes next). It is everything that makes a board
; a link: the radio and pairing with the screen, finding the controller on
; CAN and bringing its data to the screen, the screen's commands (modes, kids
; mode, lights and horn outputs, walk assist, CU Wheelie), running the
; actions a product's inputs ask for, and moving off a CAN id another device
; has. Protocol: CHARGED_UP_PLATFORM.md. The product supplies its board name,
; its own features and settings page, and these hooks (variables, set after
; importing; nil means none):
;
;   core-app-hook   (fn (data))      custom app data (its settings page)
;   core-sid-hook   (fn (id data))   every standard CAN frame (read only)
;   core-op-hook    (fn (op on))     a display accessory op the core does not do
;   core-brake-hook (fn ())          true to light the brake (e.g. its own sensor)
;   core-inputs     n                how many inputs it reports (0 none)
;   core-role       n                its role on the bus: 2 IO link, 3 IMU board
;   core-prio       n                lower is preferred as the bridge
;
; Settings in EEPROM slots 100-149 (130-149 the learned mode limits); a
; product keeps clear of them. Packages built on this use 150 and up.
;
; Usage, in the product's main file:
;   (import "../cu_common/cu_link_core.lisp" 'cu-link-core)
;   (read-eval-program cu-link-core)
;   ... (core-load) at start, (core-save) in its save, (core-start) last.
; ============================================================================

@const-start

; Extras published by vedderb's dash_esc package on standard CAN ids.
; If that package is not running these simply stay at their defaults.
(defun dash-esc-live () (< (secs-since x-last) 2.0))
(def magic 0xCD)

(def bcast (list 255 255 255 255 255 255))

(defun core-save () {
        (eeprom-store-i 101 cfg-esc-id)
        (eeprom-store-i 102 (if cfg-esc2-en 1 0))
        (eeprom-store-i 103 cfg-esc2-id)
        (eeprom-store-i 104 cfg-chan)
        (eeprom-store-f 105 cfg-hz)
        (eeprom-store-i 106 cfg-io-id)
        (eeprom-store-i 107 (if cfg-io-en 1 0))
        (eeprom-store-i 108 cfg-soc-src)
        (eeprom-store-i 109 (if cfg-walk-en 1 0))
        (eeprom-store-f 110 cfg-walk-kph)
        (eeprom-store-f 111 cfg-walk-duty)
        (eeprom-store-i 112 cfg-ch-left)
        (eeprom-store-i 113 cfg-ch-right)
        (eeprom-store-i 114 cfg-ch-beam)
        (eeprom-store-i 115 cfg-ch-horn)
        (eeprom-store-i 116 (if cfg-kid-on 1 0))
        (eeprom-store-f 117 cfg-kid-mph)
        (eeprom-store-f 118 cfg-kid-w)
        (eeprom-store-i 119 (if cfg-setup-en 1 0))
        (eeprom-store-i 120 (if cfg-esc-auto 1 0))
        (eeprom-store-f 121 cfg-brake-a)
        (if cfg-kid-known (eeprom-store-i 124 1))
        (eeprom-store-i 100 core-magic)
        true
})

; one slot, kept only if it reads back in range: a slot never written (or
; written by something else) leaves the default
(defun core-ri (slot lo hi d) { (var v (eeprom-read-i slot)) (if (and v (>= v lo) (<= v hi)) (to-i v) d) })
(defun core-rf (slot lo hi d) { (var v (eeprom-read-f slot)) (if (and v (>= v lo) (<= v hi)) v d) })

(defun core-load () {
        (var m (eeprom-read-i 100))
        (if (and m (= m core-magic)) {
                (def cfg-esc-id (core-ri 101 0 253 cfg-esc-id))
                (def cfg-esc2-en (= (core-ri 102 0 1 0) 1))
                (def cfg-esc2-id (core-ri 103 0 253 cfg-esc2-id))
                (def cfg-chan (core-ri 104 1 13 cfg-chan))
                (def cfg-hz (core-rf 105 1.0 30.0 cfg-hz))
                (def cfg-io-id (core-ri 106 0 253 cfg-io-id))
                (def cfg-io-en (= (core-ri 107 0 1 0) 1))
                (def cfg-soc-src (core-ri 108 0 1 0))
                (def cfg-walk-en (= (core-ri 109 0 1 0) 1))
                (def cfg-walk-kph (core-rf 110 1.0 13.0 cfg-walk-kph))
                (def cfg-walk-duty (core-rf 111 0.03 0.41 cfg-walk-duty))
                (def cfg-ch-left (core-ri 112 0 16 cfg-ch-left))
                (def cfg-ch-right (core-ri 113 0 16 cfg-ch-right))
                (def cfg-ch-beam (core-ri 114 0 16 cfg-ch-beam))
                (def cfg-ch-horn (core-ri 115 0 16 cfg-ch-horn))
                (def cfg-kid-on (= (core-ri 116 0 1 0) 1))
                (def cfg-kid-known (or cfg-kid-on (= (core-ri 124 0 1 0) 1)))
                (def cfg-kid-mph (core-rf 117 1.0 99.0 cfg-kid-mph))
                (def cfg-kid-w (core-rf 118 1.0 30000.0 cfg-kid-w))
                (def cfg-setup-en (= (core-ri 119 0 1 1) 1))
                (def cfg-esc-auto (= (core-ri 120 0 1 1) 1))
                (def cfg-brake-a (core-rf 121 0.0 60.0 cfg-brake-a))
                true
        } false)
})

;; --- finding the controllers -----------------------------------------------
;;
;; Every VESC motor controller broadcasts status frames carrying its own CAN
;; id, and the firmware keeps the newest from each (can-list-devs, with
;; can-msg-age to tell a live one from a stale entry). Each id is pinged once
;; to confirm it is a motor controller (hw type 0) rather than a BMS, a
;; display or another Express. The lowest is the main ESC and the next the
;; second motor. A controller found stays chosen while it keeps reporting, so
;; the ids cannot change under a rider. Nothing broadcasting - status
;; messages switched off - falls back to a ping scan of the bus every 30 s.
;; With the setting off the stored ids are used, as before.
(defun esc-type (id) {
        (var hit nil)
        (loopforeach e esc-types (if (= (car e) id) (setq hit e)))
        (if hit (cdr hit) {
                (var ht (car (cdr (trap (can-ping id)))))
                ; only an answer is remembered; a miss is asked again later
                (if ht (def esc-types (cons (cons id ht) esc-types)))
                ht
        })
})

(defun esc-live (id) {
        (var a (car (cdr (trap (can-msg-age id 1)))))
        (and a (< a 2.0))
})

(defun esc-in (id ids) {
        (var f false)
        (loopforeach i ids (if (= i id) (setq f true)))
        f
})

(defun esc-find () {
        (var mine (car (cdr (trap (conf-get 'controller-id)))))
        (if (not (number? mine)) (setq mine -1))
        (var devs (car (cdr (trap (can-list-devs)))))
        (var ids (filter (fn (i) (and (!= i mine) (esc-live i) (eq (esc-type i) 0)))
                         (if (eq (type-of devs) type-list) devs nil)))
        ; No status broadcasts. If the controller already chosen still
        ; answers - the setup values it is asked for, or one ping - keep it:
        ; can-scan pings all 254 ids in one blocking call, which stops every
        ; thread here for seconds. Run every 30 s, it froze the mode heartbeat
        ; and the frames to the dash for up to 9 s at a time (bench, a VESC
        ; with status messages off).
        (if (and (eq ids nil) (>= cfg-esc-id 0) (!= cfg-esc-id mine)
                 (or (sv-live) (eq (car (cdr (trap (can-ping cfg-esc-id)))) 0)))
            (setq ids (list cfg-esc-id)))
        ; The scan stops every thread for 2-4 s with nobody answering, so
        ; three tries 30 s apart, then every five minutes.
        (if (and (eq ids nil) (or (not esc-scan-t)
                                  (> (secs-since esc-scan-t) (if (< esc-scan-n 3) 30.0 300.0)))) {
                (def esc-scan-t (systime))
                (def esc-scan-n (+ esc-scan-n 1))
                (var sc (car (cdr (trap (can-scan)))))
                (setq ids (filter (fn (i) (and (!= i mine) (eq (esc-type i) 0)))
                                  (if (eq (type-of sc) type-list) sc nil)))
        })
        (def esc-found ids)
        (if ids (def esc-scan-n 0))
        (if ids {
                (if (not (esc-in cfg-esc-id ids)) {
                        (def cfg-esc-id (car ids))
                        (print (list "controller found at id" cfg-esc-id))
                })
                (var others (filter (fn (i) (!= i cfg-esc-id)) ids))
                (if others {
                        (if (or (not cfg-esc2-en) (not (esc-in cfg-esc2-id others)))
                            (def cfg-esc2-id (car others)))
                        (def cfg-esc2-en true)
                } (def cfg-esc2-en false))
        })
})


; ---------------------------------------------------------------------------
; CAN in
; ---------------------------------------------------------------------------
; Reply fragments. The two fill packets differ in how the offset is carried:
;   5  FILL_RX_BUFFER       [index u8][7 data bytes]
;   6  FILL_RX_BUFFER_LONG  [index u16][6 data bytes]
;   7  PROCESS_RX_BUFFER    [sender][send mode][len u16][crc u16]
(defun sv-store (off data from) {
        (if (eq sv-buf nil) (def sv-buf (bufcreate 128)))
        (var n (- (buflen data) from))
        (if (and (>= off 0) (<= (+ off n) 128))
            (bufcpy sv-buf off data from n))
})

(defun sv-fill (data) {
        (def sv-fills (+ sv-fills 1))
        (if (>= (buflen data) 2) (sv-store (bufget-u8 data 0) data 1))
})

(defun sv-fill-long (data)
    (if (>= (buflen data) 3) (sv-store (bufget-u16 data 0) data 2)))

; [sender][send mode][length u16][crc16 u16]. The crc is what makes this
; safe: the controller sends its app data to whoever last asked it anything,
; so another package's stream (CU Wheelie's, 25 a second) can arrive as
; fragments into the same buffer. Checked only on the first byte, a reply
; half written over by one parsed - 996 km/h on a bike standing still
; (bench, 2026-10-23, CU Wheelie on the controller).
(defun sv-done (data) {
        (def sv-dones (+ sv-dones 1))
        (if (and sv-buf (>= (buflen data) 6)) {
                (var n (bufget-u16 data 2))
                (if (and (> n 0) (<= n 128) (= (bufget-u8 data 0) sv-req-id)
                         (= (bufget-u8 sv-buf 0) sv-req-cmd)
                         (= (crc16 sv-buf n) (bufget-u16 data 4)))
                    (cond
                        ((and (= sv-req-cmd 47) (>= n 60)) (sv-parse sv-buf))
                        ((and (= sv-req-cmd 91) (= n 50)) (mode-check sv-buf)))
                    (def sv-bad (+ sv-bad 1)))
        })
})

(defun proc-eid (id data) {
        (var v2 (bitwise-and id 0xFF))
        ; a reply to our own request is addressed to us, not to the controller;
        ; anything else addressed to us (another device's traffic) is dropped
        ; at once rather than reassembled
        (if (and (not (gw-can-eid id data)) (= v2 cfg-my-id) (< (secs-since sv-req-t) 0.3)) {
                (var mc (shr id 8))
                (if (= mc 5) (sv-fill data))
                (if (= mc 6) (sv-fill-long data))
                (if (= mc 7) (sv-done data))
        })
        (if (and cfg-esc2-en (= v2 cfg-esc2-id)) {
                (var c2 (shr id 8))
                (cond
                    ((= c2 9) { (def e2-amps (/ (bufget-i16 data 4) 10.0))
                                (def e2-duty (/ (bufget-i16 data 6) 1000.0)) })
                    ((= c2 16) { (def e2-tesc (/ (bufget-i16 data 0) 10.0))
                                 (def e2-tmot (/ (bufget-i16 data 2) 10.0)) }))
        })
        (if (= (bitwise-and id 0xFF) cfg-esc-id) {
                (def d-last (systime))
                (var cmd (shr id 8))
                (cond
                    ((= cmd 9) {
                            (def d-amps (/ (bufget-i16 data 4) 10.0))
                            (def d-duty (/ (bufget-i16 data 6) 1000.0))
                    })
                    ((= cmd 15) (def d-wh (/ (bufget-i32 data 0) 10000.0)))
                    ((= cmd 16) {
                            (def d-tesc (/ (bufget-i16 data 0) 10.0))
                            (def d-tmot (/ (bufget-i16 data 2) 10.0))
                            (def d-iin (/ (bufget-i16 data 4) 10.0))
                            (def d-kw (/ (* d-volt d-iin) 1000.0))
                    })
                    ((= cmd 27) (def d-volt (/ (bufget-i16 data 4) 10.0)))
                )
        })
        (free data)
})

; dash_esc frames, see vesc_pkg/dash_esc/main.lisp
(defun proc-dash-esc (id data) {
        ; only the controller's frames say dash_esc is there: a Dash 35B
        ; sends 202 as well, with its wheelie settings, and taking that made
        ; a bare controller look like dash_esc - no limits, no setup values
        (if (!= id 202) { (def x-last (systime)) (def x-ever true) })
        (cond
            ((= id 20) {
                    (def d-soc   (/ (bufget-i16 data 0) 1000.0))
                    (def d-duty  (/ (bufget-i16 data 2) 1000.0))
                    (def d-speed (/ (bufget-i16 data 4) 10.0))
                    (def d-kw    (/ (bufget-i16 data 6) 100.0))
            })
            ((= id 21) {
                    (def d-tbat (/ (bufget-i16 data 0) 10.0))
                    (def d-tesc (/ (bufget-i16 data 2) 10.0))
                    (def d-tmot (/ (bufget-i16 data 4) 10.0))
                    (def x-pitch (/ (bufget-i16 data 6) 100.0))
            })
            ((= id 22) {
                    (def d-wh     (/ (bufget-u16 data 0) 10.0))
                    (def x-wh-chg (/ (bufget-u16 data 2) 10.0))
                    (def d-trip   (/ (bufget-u16 data 4) 10.0))
                    (def d-fault  (bufget-u16 data 6))
            })
            ((= id 23) {
                    (def x-amp-avg (to-float (bufget-u16 data 0)))
                    (def x-amp-max (to-float (bufget-u16 data 2)))
                    (def d-amps    (to-float (bufget-i16 data 4)))
                    (def x-batt-ah (to-float (bufget-u16 data 6)))
            })
            ((= id 24) {
                    (def d-volt (/ (bufget-u16 data 0) 10.0))
                    (def d-odo  (/ (bufget-u32 data 2) 10.0))
                    (def x-cruise-kmh (/ (bufget-u16 data 6) 10.0))
            })
            ; A Dash 35B sends 202 too, byte 0 its wheelie state, and the two
            ; cannot be told apart. While another display is on the bus (its
            ; 201s, see proc-sid) cruise is reported off: the dash's "any
            ; press cancels cruise" sends a toggle, and a wheelie read as
            ; cruise on would have switched cruise ON.
            ((= id 202) (def x-cruise (if (< (secs-since x-disp-t) 5.0) 0 (bufget-u8 data 0))))
            ; dash_esc 2.4: the mode it is actually applying, which every
            ; display shows rather than its own idea of it, plus logging and
            ; the two servicing states. Its numbering: 0 reverse, 1 neutral,
            ; 2-4 modes 1-3.
            ((= id 25) {
                    (def x-ever true)
                    (def x-log  (bufget-u8 data 0))
                    (def x-mode (bufget-u8 data 1))
                    (def x-susp (bufget-u8 data 2))
                    (def x-mbad (bufget-u8 data 3))
                    (def x-mode-last (systime))
            }))
})

(defun proc-sid (id data) {
        (if (or (and (>= id 20) (<= id 25)) (= id 202))
            (proc-dash-esc id data))
        ; CU Wheelie's replies and telemetry, 0x540 + its CAN id
        (if (and (>= id 0x540) (< id 0x580)) (whl-proc id data))
        ; other Charged Up devices: presence, and switch presses for the bridge
        (if (and (>= id 0x5F0) (<= id 0x5FF)) (pr-recv data))
        (if (and (>= id 0x5E0) (<= id 0x5EF)) (pr-act-recv data))
        ; a mode frame heard means another display: only the bridge sends
        ; 201 here, and a board never hears its own frames
        (if (= id 201) (def x-disp-t (systime)))
        ; Only dash_esc's status frames say the controller is there. Taken
        ; from any standard frame, an Express IMU on the bus (0x5A0, 200 a
        ; second) kept a switched-off controller showing online.
        (if (and (>= id 20) (<= id 24)) (def d-last (systime)))
        (cond
            ((= id 20) {
                    (def d-soc (/ (bufget-i16 data 0) 1000.0))
                    (def d-duty (/ (bufget-i16 data 2) 1000.0))
                    (def d-speed (/ (bufget-i16 data 4) 10.0))
                    (def d-kw (/ (bufget-i16 data 6) 100.0))
            })
            ((= id 21) {
                    (def d-tbat (/ (bufget-i16 data 0) 10.0))
                    (def d-tesc (/ (bufget-i16 data 2) 10.0))
                    (def d-tmot (/ (bufget-i16 data 4) 10.0))
            })
            ((= id 22) {
                    (def d-wh (/ (bufget-u16 data 0) 10.0))
                    (def d-trip (/ (bufget-u16 data 4) 10.0))
                    (def d-fault (bufget-u16 data 6))
            })
            ((= id 23) (def d-amps (bufget-i16 data 4)))
            ((= id 24) {
                    (def d-volt (/ (bufget-u16 data 0) 10.0))
                    (def d-odo (/ (bufget-u32 data 2) 10.0))
            })
        )
        (free data)
})

; Accessory command from the dash: [0xCF][op][val][0]
;   1 left  2 right  3 hazard  4 beam  5 horn  6 cruise  7 trip reset
;   8 walk  9 logging  10 power going  11 lights off  12 brake light
;
; These map onto the frames vedderb's dash_esc already listens for, so a
; stock dash_esc responds correctly without any changes:
;
;   SID 201  [drive-mode][light]        set profile and headlight
;   SID 250  [0]                        toggle cruise control
;
; Turn signals are not part of that protocol - dash35b draws indicator
; icons but nothing in dash_esc drives them - so they go out on SID 211
; as an extension for a lighting board to pick up.
; cfg-mode here is the dash's numbering - -1 reverse, 0 neutral, 1-3 - and
; dash_esc's is one ahead: 0 reverse, 1 neutral, 2-4. Sent unconverted, as it
; was, neutral on the dash put the controller in REVERSE (dash_esc also holds
; the reverse input on for it), mode 1 gave neutral, 2 and 3 gave modes 1 and
; 2, and reverse (255) was ignored. The Bluetooth path from the dash always
; added the one.
; Before a dash has set the mode (mode-known) the link has no mode of its own
; to send: cfg-mode is only its default, 1. The beam op and switch and a kids
; frame reached here regardless, so with another display holding the bike in
; N or R a flick of the beam switch put it into mode 1. Until then the
; controller's own mode goes back to it (frame 25, fresh), so the light still
; works and nothing changes; with neither, nothing is sent.
(def cfg-kid-known false)
(def kid-can-t nil)
(defun send-kid-can () {
    (if (and (bridge) cfg-kid-known
             (or (not kid-can-t) (> (secs-since kid-can-t) 1.0))) {
        (var b (bufcreate 7))
        (bufset-u8 b 0 0x4B) (bufset-u8 b 1 1)
        (bufset-u8 b 2 (if cfg-kid-on 1 0))
        (bufset-u16 b 3 (to-i cfg-kid-mph)) (bufset-u16 b 5 (to-i cfg-kid-w))
        (trap (can-send-sid 212 b))
        (free b)
        (def kid-can-t (systime))
    })
})

(defun send-201 () (if (bridge) {
        (send-kid-can)
        (var m0 (cond (mode-known cfg-mode)
                      ((< (secs-since x-mode-last) 1.0) (- x-mode 1))
                      (t nil)))
        (if m0 {
                (var b (bufcreate 8))
                ; kids mode with dash_esc: never above mode 1, see apply-mode
                (var m (if (and cfg-kid-on (or x-ever (dash-esc-live)) (> m0 1)) 1 m0))
                (bufset-u8 b 0 (+ m 1))
                (bufset-u8 b 1 (if aux-beam 1 0))
                (trap (can-send-sid 201 b))
                (free b)
        })
}))

; CAN_PACKET_IO_BOARD_SET_OUTPUT_DIGITAL = 36, payload [channel][1][on],
; sent as an extended id of board-id | (36 << 8). This is the standard way
; to drive an output on another board, so any VESC IO board responds.
; Relay outputs go to a board on the CAN bus - an Rmcore, an IO board, or a
; VESC Express with outputs. Turned off, nothing is sent at all, which is the
; right default for anyone driving lights from the LED strip instead.
(defun io-out (ch on) {
        (if (and cfg-io-en (> ch 0)) {
                (var b (bufcreate 3))
                (bufset-u8 b 0 ch)
                (bufset-u8 b 1 1)
                (bufset-u8 b 2 (if on 1 0))
                (trap (can-send-eid (bitwise-or cfg-io-id (shl 36 8)) b))
                (free b)
        })
})

(defun send-signals () {
        (io-out cfg-ch-left  (or aux-left aux-hazard))
        (io-out cfg-ch-right (or aux-right aux-hazard))
        (io-out cfg-ch-beam  aux-beam)
})

; kid frame: [0xCA][on][mph u16][watts u16]
(defun apply-kid (data) {
        (if (and (>= (buflen data) 6) (= (bufget-u8 data 0) 0xCA)
                 (<= (bufget-u8 data 1) 1)
                 (>= (bufget-u16 data 2) 1) (<= (bufget-u16 data 2) 99)
                 (>= (bufget-u16 data 4) 1) (<= (bufget-u16 data 4) 30000)) {
                (var on (= (bufget-u8 data 1) 1))
                (var mph (to-float (bufget-u16 data 2)))
                (var w (to-float (bufget-u16 data 4)))
                ; saved on a change only: the dash sends this three times per
                ; setting and again on every reconnect, and each save is 22
                ; slots of flash
                (var changed (or (not-eq on cfg-kid-on) (!= mph cfg-kid-mph) (!= w cfg-kid-w)))
                (var first-kid (not cfg-kid-known))
                (def cfg-kid-known true)
                (def cfg-kid-on on)
                (def cfg-kid-mph mph)
                (def cfg-kid-w w)
                (if (or changed first-kid) (core-save))
                (def kid-can-t nil)
                ; reapply the current mode so the clamp takes effect at once -
                ; with its own limits: it was 200 A and 200 km/h, which with
                ; kids mode off lifted every limit until the next mode change
                (var b (mode-frame cfg-mode))
                (apply-mode b)
                (free b)
        })
})

(defun send-250 (ev) {
        (var b (bufcreate 8))
        (bufset-u8 b 0 ev)
        (trap (can-send-sid 250 b))
        (free b)
})

(defun apply-aux (data) {
        (var op (bufget-u8 data 1))
        (var v (= (bufget-u8 data 2) 1))
        (cond
            ((= op 1) { (def aux-left v) (if v (def aux-right false))
                        (send-signals) })
            ((= op 2) { (def aux-right v) (if v (def aux-left false))
                        (send-signals) })
            ((= op 3) { (def aux-hazard v) (send-signals) })
            ((= op 4) { (def aux-beam v) (send-201) (send-signals) })
            ((= op 5) {
                    ; horn: pulse the output for 400ms
                    (io-out cfg-ch-horn true)
                    (spawn (fn () {
                            (sleep 0.4)
                            (io-out cfg-ch-horn false)
                    })) })
            ((= op 6) {
                    ; cruise toggle, the dash_esc event frame
                    (var b (bufcreate 8))
                    (bufset-u8 b 0 0)
                    (trap (can-send-sid 250 b))
                    (free b) })
            ; walk assist: a hold, not a toggle. The dash repeats this
            ; while the button is down and the thread below gives up on it
            ; the moment they stop, so a lost release cannot leave the
            ; motor running.
            ((= op 8) (def walk-req (if v (systime) 0)))
            ; dash_esc events on SID 250: 2 toggles logging, 1 says power is
            ; about to go (it closes the log and puts the limits back first)
            ((= op 9) (send-250 2))
            ((= op 10) (send-250 1))
            ; a display button set to the link's lights off or brake light
            ((= op 11) (def lt-dark (not lt-dark)))
            ((= op 12) (def lt-brake-man (not lt-brake-man)))
            ; anything else is the product's: (core-op-hook op on)
            (t (if core-op-hook (core-op-hook op v))))
        (if (> op 0) (print (list "aux" op v)))
})

; mode frame from the dash:
;   [0xCE][mode+1][motor A u16][batt A u16][speed kph u16][brake A u16]
;   [change count][flags: bit 0 it takes the IO Link's switches]
; mode is sent offset by one so reverse (-1) fits in a byte.
;
; Kids mode clamps here rather than on the dash, so it holds even with no
; display connected, and only ever lowers a limit - never raises one.

; A COMM command to a controller over CAN: FILL_RX_BUFFER fragments, then
; PROCESS_RX_BUFFER with send mode 2, processed with no reply
(defun comm-can (id b) {
        (var n (buflen b))
        (var off 0)
        (loopwhile (< off n) {
                (var k (if (> (- n off) 7) 7 (- n off)))
                (var f (bufcreate (+ k 1)))
                (bufset-u8 f 0 off)
                (bufcpy f 1 b off k)
                (can-send-eid (bitwise-or id (shl 5 8)) f)
                (free f)
                (setq off (+ off k))
        })
        (var p (bufcreate 6))
        (bufset-u8 p 0 cfg-my-id) (bufset-u8 p 1 2)
        (bufset-u16 p 2 n) (bufset-u16 p 4 (crc16 b n))
        (can-send-eid (bitwise-or id (shl 7 8)) p)
        (free p)
})

; The limits for a controller with no dash_esc: COMM_SET_MCCONF_TEMP_SETUP,
; the command the screen sends over Bluetooth for the same case, so both
; paths leave the same settings behind whichever had the controller last.
; It was CONF_CURRENT_LIMITS in amps: neutral took regen away, a mode above
; the controller's own current raised it, speed and the kids speed were never
; applied, and a second controller got nothing. As on the screen: braking
; whole, drive whole or nothing, the mode's top speed, its battery amps as
; watts; RAM only, forwarded to the other controllers.
(defun mode-limits (m bat spd) (if (not su-held) {
        (var drive (>= m 1))
        (var volts (if (> d-volt 10.0) d-volt 50.0))
        (var w (if (and drive (> bat 0.0)) (* bat volts) 1500000.0))
        (if cfg-kid-on {
                (var k (* cfg-kid-mph 1.60934))
                (if (or (<= spd 0.0) (< k spd)) (setq spd k))
                (if (< cfg-kid-w w) (setq w cfg-kid-w))
        })
        (var b (bufcreate 37))
        (bufset-u8 b 0 49)
        (bufset-u8 b 1 0) (bufset-u8 b 2 1) (bufset-u8 b 3 0) (bufset-u8 b 4 0)
        (bufset-f32 b 5 1.0)
        (bufset-f32 b 9 (if drive 1.0 0.0))
        (bufset-f32 b 13 (if (and drive (> spd 0.0)) (- 0.0 (/ spd 3.6)) -100.0))
        (bufset-f32 b 17 (if (and drive (> spd 0.0)) (/ spd 3.6) 100.0))
        (bufset-f32 b 21 0.0)
        (bufset-f32 b 25 0.95)
        (bufset-f32 b 29 -1500000.0)
        (bufset-f32 b 33 (if drive w 0.0))
        (comm-can cfg-esc-id b)
        ; Keep the exact applied limits, including the voltage used for watts.
        ; Battery movement alone must never cause repeated configuration writes.
        (if mode-limit-buf (free mode-limit-buf))
        (def mode-limit-buf b)
        (def mode-limit-id cfg-esc-id)
        (def mode-limit-gen (+ mode-limit-gen 1))
}))

; Readback is authoritative; a remembered mode frame is not proof that RAM
; limits survived a controller-only reset. Poll without writing, and repair
; only a limit that became less restrictive. Never raise a stricter user/HW
; limit or compete with a controller package that owns the drive profiles.
(defun mode-check-active ()
    (and (not su-held) mode-limit-buf mode-known (bridge) (not x-ever) (not (dash-esc-live))
         (= mode-limit-id cfg-esc-id)))

(defun mode-lower (a b) (if (< a b) a b))
(defun mode-higher (a b) (if (> a b) a b))

(defun mode-check (b) {
        (if (and (mode-check-active) (= sv-req-gen mode-limit-gen)
                 (or (= sv-req-id cfg-esc-id)
                     (and cfg-esc2-en (= sv-req-id cfg-esc2-id)))) {
                (var poles (bufget-u8 b 41))
                (var gear (bufget-f32 b 42))
                (var wheel (bufget-f32 b 46))
                ; Reject non-finite configuration fields and invalid geometry.
                (var valid true)
                (looprange i 0 10 {
                        (if (= (bitwise-and (bufget-u32 b (+ 1 (* i 4))) 0x7F800000) 0x7F800000)
                            (setq valid false))
                })
                (if (and valid (>= (bufget-f32 b 1) 0.0) (>= (bufget-f32 b 5) 0.0)
                         (>= poles 2) (<= poles 250) (> gear 0.0) (< gear 10000.0)
                         (> wheel 0.001) (< wheel 100.0)) {
                        (var factor (/ (* poles 0.5 60.0 gear) (* 3.14159265 wheel)))
                        (var loose (or
                            (> (bufget-f32 b 5) (+ (bufget-f32 mode-limit-buf 9) 0.0001))
                            (> (bufget-f32 b 29) (+ (bufget-f32 mode-limit-buf 33) 0.01))
                            (> (bufget-f32 b 13) (+ (* factor (bufget-f32 mode-limit-buf 17)) 0.5))
                            (< (bufget-f32 b 9) (- (* factor (bufget-f32 mode-limit-buf 13)) 0.5))))
                        (def mode-checks (+ mode-checks 1))
                        (if loose {
                                ; A reset may loosen one cap while another
                                ; remains intentionally lower. Repair each cap
                                ; independently; never raise the other limits.
                                (var repair (bufcreate 37))
                                (bufcpy repair 0 mode-limit-buf 0 37)
                                (bufset-f32 repair 5 (bufget-f32 b 1))
                                (bufset-f32 repair 9 (mode-lower (bufget-f32 repair 9) (bufget-f32 b 5)))
                                (bufset-f32 repair 13 (mode-higher (bufget-f32 repair 13) (/ (bufget-f32 b 9) factor)))
                                (bufset-f32 repair 17 (mode-lower (bufget-f32 repair 17) (/ (bufget-f32 b 13) factor)))
                                (bufset-f32 repair 21 (bufget-f32 b 17))
                                (bufset-f32 repair 25 (bufget-f32 b 21))
                                (bufset-f32 repair 29 (bufget-f32 b 25))
                                (bufset-f32 repair 33 (mode-lower (bufget-f32 repair 33) (bufget-f32 b 29)))
                                ; Repair this controller only. Forwarding its
                                ; stricter limits could alter the other motor.
                                (bufset-u8 repair 2 0)
                                (comm-can sv-req-id repair)
                                (free repair)
                                (def mode-limit-gen (+ mode-limit-gen 1))
                                (def mode-repairs (+ mode-repairs 1))
                        })
                })
        })
})

; mode m as a mode frame: the dash's last values for it, else the ones kept
; from its frames (ml-learn), else none (no speed or watt limit)
(defun mode-frame (m) {
        (var b (bufcreate 10))
        (bufset-u8 b 0 0xCE) (bufset-u8 b 1 (+ m 1))
        (if (and mode-applied (= (ix mode-applied 0) (+ m 1)))
            (looprange i 0 4 (bufset-u16 b (+ 2 (* i 2)) (ix mode-applied (+ i 1))))
            (if (and (>= m -1) (<= m 3))
                (looprange i 0 4 (bufset-u16 b (+ 2 (* i 2)) (core-ri (+ (ml-slot m) i) 0 60000 0)))))
        b
})

(defun apply-mode (data) {
        ; byte 11 bit 0: this display runs the IO Link's switches itself
        (if (and (>= (buflen data) 12) (= (bitwise-and (bufget-u8 data 11) 1) 1))
            (def dash-sw-t (systime)))
        ; The dash repeats its mode once a second, so the same frame arrives
        ; again and again: act on a change only. Without dash_esc a change
        ; means writing limits, and those writes briefly interrupt the motor.
        (var key (list (bufget-u8 data 1) (bufget-u16 data 2) (bufget-u16 data 4)
                       (bufget-u16 data 6) (bufget-u16 data 8)
                       cfg-kid-on cfg-kid-mph cfg-kid-w))
        ; A dash new enough sends a change count in byte 10. A frame whose
        ; count is older than the last one acted on is a repeat that lost a
        ; race with a change, and acting on it put the controller back in the
        ; old mode. Three seconds without a mode frame (the dash restarted,
        ; or went out of range) and any count is accepted again.
        (var link-seq (if (>= (buflen data) 11) (bufget-u8 data 10) -1))
        (if (> (secs-since mode-rx-t) 3.0) (def mode-seq -1))
        (def mode-rx-t (systime))
        (var stale (and (>= link-seq 0) (>= mode-seq 0)
                        (>= (mod (+ (- link-seq mode-seq) 256) 256) 128)))
        (if (and (not stale) (>= link-seq 0)) (def mode-seq link-seq))
        ; Limits are written only for a controller with no dash_esc, and not
        ; in the first seconds, before dash_esc has had the chance to be
        ; heard: the screen waits the same five. Skipped, the frame is not
        ; taken as acted on, and the dash's next repeat is.
        (var lim (and (bridge) (not (or x-ever (dash-esc-live)))))
        (if (and (>= (buflen data) 10) (not stale)
                 (not (and lim (< (secs-since core-t0) 5.0)))
                 (not (and mode-known (eq key mode-applied)))) {
                (def mode-applied key)
                (def cfg-mode (- (bufget-u8 data 1) 1))
                (def mode-known true)
                ; Kids mode with dash_esc on the controller limits the way
                ; dash_esc does - through its drive profiles - by holding the
                ; mode at 1, whose speed and current are set in the package
                ; (send-201 does the holding).
                (var bat (to-float (bufget-u16 data 4)))
                (var spd (to-float (bufget-u16 data 6)))

                ; The limits are for a controller with no dash_esc.
                ; With it they are not ignored, whatever this said before:
                ; the firmware applies them under any Lisp, so they stacked
                ; on top of the drive profile and could be captured as its
                ; baseline - the setup corruption dash_esc guards against.
                ; Once dash_esc has been heard it owns the limits for good.
                ; Keyed on its frames being fresh, as this first was, a gap of
                ; two seconds in them - the link busy, a bus hiccup - made the
                ; next mode frame write the fallback limits straight into a
                ; dash_esc controller: on the bench its 60 A became 40 A.
                (if lim (mode-limits cfg-mode bat spd))

                (send-201)
                (print (list "mode" cfg-mode "bat" bat "spd" spd
                             "limits" lim "kid" cfg-kid-on))
        })
})

; Walk assist, the only place either package asks the motor to do something
; rather than tell it something.
;
; Three things keep it honest. It is off unless somebody turned it on. It
; only runs while hold frames keep arriving, so the watchdog below - not a
; release message - is what stops it, and losing the radio stops it too. And
; it is a slow closed loop on the speed the controller reports rather than an
; open duty: it creeps up while the bike is below walking pace and backs off
; faster than it climbs the moment it is over, so the failure is always
; towards stopping.
;
; The ceiling is a duty rather than a current because a duty that is too
; small simply fails to move a heavy bike, where a current that is too large
; moves it rather more than anyone standing beside it wants.
(defun walk-send (d) {
        (var b (bufcreate 4))
        (bufset-i32 b 0 (to-i (* d 100000.0)))
        (trap (can-send-eid (bitwise-or cfg-esc-id (shl 0 8)) b))
        (free b)
})

(defun walk-thread () (loopwhile t {
        (var live (and (not su-held) cfg-walk-en (> walk-req 0) (< (secs-since walk-req) 0.4)))
        ; The display starts it only below walking pace and lets go 4 km/h
        ; over; an input asks with no such check. Over the target the duty
        ; heads for zero, and zero duty is braking: a switch left on would
        ; have braked a ride. So the same two limits here, for every source.
        ; And only on a speed this board has: without dash_esc only the
        ; bridge asks for it, and a board that is not reads 0 for ever.
        (if (not (spd-known)) (setq live false))
        (if (and live (not walk-run) (>= (abs d-speed) cfg-walk-kph)) (setq live false))
        (if (> (abs d-speed) (+ cfg-walk-kph 4.0)) (setq live false))
        (setq walk-run live)
        (if live {
                (var kph d-speed)
                ; Up slowly, down five times faster, and aim a little under
                ; rather than at the limit. Simulated against bikes from a
                ; light scooter to a loaded cargo bike: this settles in one
                ; and a half to two seconds and peaks at 5.9 to 6.0 against a
                ; six limit, where backing off only at the limit itself
                ; overshot to 6.35 on the lively one. A walk assist that goes
                ; over the number it exists to respect is worth nothing.
                (if (< kph (- cfg-walk-kph 0.8))
                    (setq walk-duty (+ walk-duty 0.004))
                    (if (> kph (- cfg-walk-kph 0.2))
                        (setq walk-duty (- walk-duty 0.020))))
                (if (< walk-duty 0.0) (setq walk-duty 0.0))
                (if (> walk-duty cfg-walk-duty) (setq walk-duty cfg-walk-duty))
                (walk-send walk-duty)
        } {
                ; one zero on the way down, then nothing until asked again
                (if (> walk-duty 0.0) {
                        (setq walk-duty 0.0)
                        (walk-send 0.0)
                        (walk-send 0.0)
                        (print "walk released")
                })
        })
        (sleep 0.05)
}))

; One dash. Every display in range is heard - other riders' dashes, other
; links' telemetry - and this used to act on mode, kids mode and light frames
; from any of them. Now it keeps the dash that paired with it (slots 122/123)
; and obeys only that one. A dash only addresses a link directly once it has
; paired with it, so the first dash to do that is adopted; a different one is
; taken only after the kept one has been silent for 30 s - a replaced
; display, never a second one on the same ride.
(defun dash-ok (src des) (cond
        ((eq src dash-mac) { (def dash-t (systime)) true })
        ((or dash-nolearn (eq des bcast)
             (and dash-mac (< (secs-since dash-t) 30.0))) false)
        (t { (dash-pair src) true })))

(defun dash-pair (m) {
        (def dash-mac m)
        (def dash-t (systime))
        (eeprom-store-i 122 (+ 0x1000000 (* (ix m 0) 65536) (* (ix m 1) 256) (ix m 2)))
        (eeprom-store-i 123 (+ 0x1000000 (* (ix m 3) 65536) (* (ix m 4) 256) (ix m 5)))
        (print (list "paired with dash" m))
})

(defun dash-load () {
        (var a (eeprom-read-i 122))
        (var b (eeprom-read-i 123))
        (if (and a b (>= a 0x1000000) (< a 0x2000000) (>= b 0x1000000) (< b 0x2000000))
            ; plain integers: eeprom-read-i hands back i32s, the address an
            ; event carries is plain, and eq tells 168 from 168i32 - so a
            ; reloaded pairing matched nothing and the partner was refused
            ; after every power up (found on the bench, 2026-10-06)
            (def dash-mac (map to-i (list (bitwise-and (shr a 16) 255) (bitwise-and (shr a 8) 255)
                                (bitwise-and a 255) (bitwise-and (shr b 16) 255)
                                (bitwise-and (shr b 8) 255) (bitwise-and b 255)))))
})

(defun dash-forget () {
        (def dash-mac nil)
        (eeprom-store-i 122 0)
        (eeprom-store-i 123 0)
        true
})

; for the flasher's last step: not the bench dash, until the next power up
(defun dash-forget-hold () { (def dash-nolearn true) (dash-forget) })

; a frame that failed is counted and left to the GC (it may already be freed)
(defun ev-trap (r) (if (eq (car r) 'exit-error) (def ev-err (+ ev-err 1))))

(defun event-handler ()
    (progn
    ; A maximum-size gateway reply needs 81 CAN events before application
    ; traffic. 64 silently dropped the tail of full motor configurations.
    ; Bound the queue at 128: room for one complete reply and concurrent
    ; telemetry, without the former 256-message backlog on the Express heap.
    (set-mailbox-size 128)
    (loopwhile t
        (recv
            ;! Each message is trapped: one bad frame (a short one on an id we
            ;! read) costs that frame, not the receive thread.
            ((event-can-sid . ((? id) . (? data))) {
                    ; the product sees the frame first; proc-sid frees it
                    (if core-sid-hook (trap (core-sid-hook id data)))
                    (ev-trap (trap (proc-sid id data)))
            })
            ((event-can-eid . ((? id) . (? data))) (ev-trap (trap (proc-eid id data))))
            ; custom app data is the product's: its settings page, its tools
            ((event-data-rx . (? data)) {
                    (if core-app-hook (trap (core-app-hook data)))
                    (free data)
            })
            ((event-esp-now-rx (? src) (? des) (? data) (? rssi)) {
                    ; counted only from our own dash: other links' telemetry
                    ; kept the lights and the mode heartbeat thinking a dash
                    ; was there
                    (ev-trap (trap (if (= (bufget-u8 data 0) 0xD7) (gw-can-radio src data) (if (dash-ok src des) {
                            (def rx-last (systime))
                            (def rx-count (+ rx-count 1))
                            (def rx-last-len (buflen data))
                            (def rx-last-m0 (bufget-u8 data 0))
                            (var m0 (bufget-u8 data 0))
                            (if (and (= m0 0xCE) (>= (buflen data) 10)) {
                                    ; kept so a switch can change mode with no display
                                    (trap (ml-learn (- (bufget-u8 data 1) 1) (bufget-u16 data 2)
                                                    (bufget-u16 data 4) (bufget-u16 data 6)
                                                    (bufget-u16 data 8)))
                                    (def mode-local false)
                                    (apply-mode data)
                            })
                            (if (and (= m0 0xCA) (>= (buflen data) 6)) (apply-kid data))
                            ; the display's limits for modes 1-3, kept for the switches
                            (if (and (= m0 0xC9) (>= (buflen data) 25))
                                (looprange i 0 3 {
                                        (var o (+ 1 (* i 8)))
                                        (trap (ml-learn (+ i 1) (bufget-u16 data o) (bufget-u16 data (+ o 2))
                                                        (bufget-u16 data (+ o 4)) (bufget-u16 data (+ o 6))))
                                }))
                            (if (and (= m0 0xCF) (>= (buflen data) 4)) (apply-aux data))
                            (if (= m0 0xC7) (whl-from-dash data))
                    }))))
                    (free data)
            })
            ((? other) { (def ev-count (+ ev-count 1)) nil })))))

; ---------------------------------------------------------------------------
; CU Wheelie on the controller (3ShulMotors' Wheelie Assist display
; protocol, WHEELIE_CAN_PROTOCOL.md): telemetry on standard id 0x540 + its CAN
; id at 25 Hz, commands to 0x500 + id. The link carries its frames to the
; display inside the telemetry frame (bytes 65-97) and puts the display's
; commands on the bus, so a display reached only by radio still sees and sets
; it. Its id is taken from the frames it sends.
; ---------------------------------------------------------------------------
(defun whl-live () (< (secs-since whl-t) 1.0))
(defun whl-to () (if (>= whl-id 0) whl-id cfg-esc-id))

(defun whl-proc (id data)
    (if (and (>= (buflen data) 8) (= (bufget-u8 data 0) 0x57)) {
            (var r (bufget-u8 data 1))
            ; An attitude extension cannot select a different controller.
            (if (or (= r 0x81) (= r 0x82) (= r 0x83)) (def whl-id (- id 0x540)))
            (cond
                ((= r 0xB0) (if (= (- id 0x540) cfg-esc-id) {
    (bufcpy pm-link-data 0 data 0 8) (def pm-link-id cfg-esc-id) (def pm-link-t (systime))
}))
                ((and (>= r 0xA0) (<= r 0xAB)) (setup-link-rx id data))
                ((and (>= r 0x90) (<= r 0x97)) (hall-link-rx id data))
                ((= r 0x81) {
                        (bufcpy whl-tel 0 data 0 8)
                        (def whl-t (systime))
                        ; first sight of it: ask for its settings
                        (if (not whl-asked) { (def whl-asked true) (whl-cmd 1 0) })
                })
                ((and (= r 0x84) (= (bufget-u8 data 7) 1) (<= (bufget-u8 data 6) 2)) {
                        (bufcpy whl-att 0 data 0 8)
                        (def whl-att-id (- id 0x540))
                        (def whl-att-t (systime))
                })
                ((and (= r 0x82) (< (bufget-u8 data 2) 6)) {
                        (bufcpy whl-regs (* (bufget-u8 data 2) 4) data 4 4)
                        (def whl-regmask (bitwise-or whl-regmask (shl 1 (bufget-u8 data 2))))
                })
                (t nil))
    }))

; Hall snapshots: eight strictly ordered CAN fragments, same source/session/sequence.
; Never refresh freshness from a partial snapshot or replayed radio frame.
(defun hall-link-rx (id data) (if (= (- id 0x540) cfg-esc-id) {
    (var part (- (bufget-u8 data 1) 0x90))
    (var seq (bufget-u8 data 2)) (var session (bufget-u16 data 3))
    (if (= part 0) {
        (def hl-next 0) (def hl-seq seq) (def hl-session session) (def hl-begin (systime))
    })
    (if (and (= part hl-next) (= seq hl-seq) (= session hl-session)
             (< (secs-since hl-begin) 0.2)) {
        (bufcpy hl-work (* part 3) data 5 3)
        (def hl-next (+ part 1))
        (if (= hl-next 8) (atomic {
            (bufset-u8 hl-data 0 0x48) (bufset-u8 hl-data 1 2)
            (bufset-u16 hl-data 2 session) (bufset-u8 hl-data 4 seq)
            (bufcpy hl-data 5 hl-work 0 24)
            (def hl-id (- id 0x540)) (def hl-t (systime))
        }))
    } (def hl-next -1))
}))
 ; Setup snapshots also carry the service hold used by every link mode writer.
(defun setup-link-rx (id data) (if (and (= (- id 0x540) cfg-esc-id) (= (buflen data) 8)) {
    (var part (- (bufget-u8 data 1) 0xA0))
    (var seq (bufget-u8 data 2)) (var session (bufget-u16 data 3))
    (var have (= su-id cfg-esc-id))
    (var last-seq (bufget-u8 su-data 4)) (var last-session (bufget-u16 su-data 2))
    (var delta (mod (+ 256 (- seq last-seq)) 256))
    ; Assemble a complete matching snapshot even when CAN mailboxes reorder it.
    ; Replays of the last complete snapshot never refresh its timestamp or ACK.
    (if (and (>= part 0) (< part 12)
             (not (and have (= seq last-seq) (= session last-session)))
             (or (not have) (!= session last-session) (and (> delta 0) (< delta 128))
                 (> (secs-since su-t) 1.5))) {
        (if (or (!= seq su-seq) (!= session su-session)) {
            (def su-next 0) (def su-mask 0) (def su-seq seq)
            (def su-session session) (def su-begin (systime))
        })
        (if (< (secs-since su-begin) 0.2) {
            (var bit (shl 1 part))
            (if (= (bitwise-and su-mask bit) 0) {
                (bufcpy su-work (* part 3) data 5 3)
                (def su-mask (bitwise-or su-mask bit)) (def su-next (+ su-next 1))
            })
            (if (= su-mask 4095) {
                (atomic {
                    (bufset-u8 su-data 0 0x53) (bufset-u8 su-data 1 1)
                    (bufset-u16 su-data 2 session) (bufset-u8 su-data 4 seq)
                    (bufcpy su-data 5 su-work 0 36) (def su-t (systime)) (def su-id (- id 0x540))
                    (def su-held (!= (bitwise-and (bufget-u8 su-work 2) 1) 0))
                })
                (if su-held {
                    (var ack (bufcreate 8))
                    (bufset-u8 ack 0 0x57) (bufset-u8 ack 1 0x31) (bufset-u8 ack 2 9)
                    (bufset-u16 ack 3 session) (bufset-u8 ack 5 cfg-my-id)
                    (can-send-sid (+ 0x500 cfg-esc-id) ack) (free ack)
                })
            })
        })
    })
}))
(defun setup-link-pack (frame) (atomic
    (if (and (= su-id cfg-esc-id) (> su-t 0) (< (secs-since su-t) 1.5))
        (bufcpy frame 144 su-data 0 41) (bufset-u8 frame 144 0))))

(defun hall-link-pack (frame) (atomic
    (if (and (= hl-id cfg-esc-id) (> hl-t 0) (< (secs-since hl-t) 0.5))
        (bufcpy frame 115 hl-data 0 29) (bufset-u8 frame 115 0))))

(defun whl-att-pack (frame)
    (if (and (whl-live) (= whl-att-id whl-id) (> whl-att-t 0)
             (< (secs-since whl-att-t) 1.0))
        (bufcpy frame 105 whl-att 0 8)
        (bufset-u8 frame 105 0)))

; [0x57][cmd][arg] and zeros: 1 read all, 4 save, 5 arm (0 off 1 on 2 toggle)
(defun whl-cmd (cmd arg) {
        (var b (bufcreate 8))
        (bufset-u8 b 0 0x57) (bufset-u8 b 1 cmd) (bufset-u8 b 2 arg)
        (trap (can-send-sid (+ 0x500 (whl-to)) b))
        (free b)
})

; a command from the display: [0xC7] then the eight bytes to put on the bus
(defun whl-from-dash (data)
    (if (>= (buflen data) 9) {
            (var b (bufcreate 8))
            (bufcpy b 0 data 1 8)
            (if (= (bufget-u8 b 1) 1) (def whl-regmask 0))
            ; Hall / setup (including VALUES) belong to the selected ESC,
            ; matching their response and service-hold filters above. A
            ; separate Wheelie broadcaster must not redirect these requests.
            (var setup-cmd (and (= (bufget-u8 b 0) 0x57)
                (or (= (bufget-u8 b 1) 0x32) (= (bufget-u8 b 1) 0x30) (= (bufget-u8 b 1) 0x31))))
            (trap (can-send-sid (+ 0x500 (if setup-cmd cfg-esc-id (whl-to))) b))
            (free b)
    }))

; ---------------------------------------------------------------------------
; Actions. A product with inputs (cu_link_inputs) turns presses into these;
; the core runs them, here or on the display. Actions use the display's
; numbering:
;
;   0 nothing        1 mode up       2 mode down     3 mode cycle
;   4 next page      5 prev page     6 home page     7 mode chip
;   8 left signal    9 right signal 10 hazards      11 high beam
;  12 horn          13 cruise       14 reset trip   15 night mode
;  16 reverse       17 brighter     18 dimmer       19 walk assist
;  20 hold reverse  21 controller   22 release      23 BMS on/off
;  24 mode 1        25 mode 2       26 mode 3       27 neutral
;  28 lights off    29 brake light  30 logging      31 wheelie arm
;
; Horn, cruise, walk assist, lights off, brake light and logging belong to
; this board and always run here. The rest go to a paired display that says
; it takes them (bit 0 of byte 11 of its mode frames), so it stays in charge
; of the mode and signals it shows. With none, the link runs what it can -
; signals, beam and modes - and the display-only ones do nothing.
; ---------------------------------------------------------------------------
(defun dash-sw-ok () (< (secs-since dash-sw-t) 3.0))

; actions an on/off switch holds rather than fires once
(defun sw-state-act (a) (or (and (>= a 8) (<= a 12)) (= a 16) (= a 19) (= a 20)
                            (and (>= a 24) (<= a 29)) (= a 31)))
; on a momentary button these act while it is held
(defun sw-hold-act (a) (or (= a 12) (= a 19) (= a 20) (= a 29)))
(defun sw-own-act (a) (or (= a 12) (= a 13) (= a 19) (= a 28) (= a 29) (= a 30) (= a 31)))

; Events for the display, [code][val] with val 2 fire, 1 on, 0 off. A ring
; the switch thread alone writes (ev-w) and the frame sender alone reads
; (ev-r), so neither can undo the other's write.
(defun sw-queue (a v) {
        (var n (mod (+ ev-w 1) 16))
        (if (!= n ev-r) {
                (bufset-u8 ev-buf (* ev-w 2) a)
                (bufset-u8 ev-buf (+ (* ev-w 2) 1) v)
                (def ev-w n)
        })
})

; --- modes run by the link, with no display -------------------------------
; The display's limits for each mode, kept from its mode frames (apply-mode),
; so a switch can change mode on a controller without Dash ESC. With Dash
; ESC the mode number is all it takes.
(defun ml-slot (m) (+ 130 (* (+ m 1) 4)))
(defun eqi (s v) { (var r (eeprom-read-i s)) (and r (= r v)) })
(defun ml-learn (m mot bat spd brk)
    (if (and (>= m -1) (<= m 3) (not (and (eqi (ml-slot m) mot) (eqi (+ (ml-slot m) 1) bat)
                                          (eqi (+ (ml-slot m) 2) spd) (eqi (+ (ml-slot m) 3) brk)))) {
            (var s (ml-slot m))
            (eeprom-store-i s mot) (eeprom-store-i (+ s 1) bat)
            (eeprom-store-i (+ s 2) spd) (eeprom-store-i (+ s 3) brk)
    }))

(defun link-mode (m) {
        ; reverse and neutral only at a standstill, as on the display
        (if (and (< m 1) (> (abs d-speed) 1.6)) false {
                (def mode-local true)
                ; with dash_esc the number is all it takes; without, the
                ; display's limits for it, or none learned yet: neutral and
                ; reverse still take the drive away
                (var b (mode-frame m))
                (apply-mode b)
                (free b)
                (print (list "switch mode" m))
                true
        })
})

(defun sw-mode-step (d) {
        (var m (+ (if (< cfg-mode 1) 1 cfg-mode) d))
        (if (> m 3) (setq m 3))
        (if (< m 1) (setq m 1))
        (if (!= m cfg-mode) (link-mode m))
})

; into mode m and back out of it to wherever it came from
(defun sw-mode-in (m) {
        (if (>= cfg-mode 1) (def sw-prev cfg-mode))
        (link-mode m)
})
(defun sw-mode-toggle (m) (if (= cfg-mode m) (link-mode sw-prev) (sw-mode-in m)))

(defun sw-sig (a v) {
        (var on (fn (x) (if (= v 2) (not x) (= v 1))))
        (cond
            ((= a 8) { (def aux-left (on aux-left))
                       (if aux-left { (def aux-right false) (def aux-hazard false) }) })
            ((= a 9) { (def aux-right (on aux-right))
                       (if aux-right { (def aux-left false) (def aux-hazard false) }) })
            ((= a 10) { (def aux-hazard (on aux-hazard))
                        (if aux-hazard { (def aux-left false) (def aux-right false) }) })
            ((= a 11) { (def aux-beam (on aux-beam)) (send-201) }))
        (send-signals)
})

; this board's own: horn, cruise, walk assist, lights off, brake, logging
(defun sw-own (a v) (cond
        ((= a 12) (io-out cfg-ch-horn (!= v 0)))
        ((= a 13) (if (!= v 0) (send-250 0)))
        ((= a 19) (def sw-walk (!= v 0)))
        ((= a 28) (def lt-dark (if (= v 2) (not lt-dark) (= v 1))))
        ((= a 29) (def lt-brake-man (if (= v 2) (not lt-brake-man) (= v 1))))
        ((= a 30) (if (!= v 0) (send-250 2)))
        ; CU Wheelie: straight onto the bus, display or not
        ((= a 31) (whl-cmd 5 v))))

(defun sw-do (a v) (cond
        ((= a 0) nil)
        ; with another device bridging, it runs modes, signals and the rest,
        ; so they reach its display and the controller once
        ((and (not (pr-keep-act a)) (pr-peer) (not (bridge))) (pr-act-send a v))
        ((sw-own-act a) (sw-own a v))
        ; hold reverse: with a display it is a hold it watches (byte 61),
        ; without, the gear comes back once stopped and off the throttle
        ((= a 20) (if (dash-sw-ok) (def sw-rev-held (!= v 0))
                      (if (!= v 0)
                          (if (< (abs d-speed) 1.6) (sw-mode-in -1))
                          (if (= cfg-mode -1) (def sw-rev-wait true)))))
        ((dash-sw-ok) (sw-queue a v))
        ((and (>= a 8) (<= a 11)) (sw-sig a v))
        ((= a 1) (if (!= v 0) (sw-mode-step 1)))
        ((= a 2) (if (!= v 0) (sw-mode-step -1)))
        ((= a 3) (if (!= v 0) (link-mode (if (>= cfg-mode 3) 1 (+ (if (< cfg-mode 1) 0 cfg-mode) 1)))))
        ((or (= a 16) (= a 27) (and (>= a 24) (<= a 26))) {
                (var m (cond ((= a 16) -1) ((= a 27) 0) (t (- a 23))))
                (cond ((= v 2) (if (< m 1) (sw-mode-toggle m) (link-mode m)))
                      ((= v 1) (sw-mode-in m))
                      (t (if (= cfg-mode m) (link-mode sw-prev))))
        })
        (t nil)))

; regen beyond the threshold means the rider is braking
(defun brake-check ()
    (def lt-brake (or lt-brake-man
                      (and core-brake-hook (core-brake-hook))
                      (and pr-brake (pr-peer) (not (bridge)))
                      ; CU Wheelie decides brake from deceleration too
                      (and (whl-live) (= (bitwise-and (bufget-u8 whl-tel 6) 16) 16))
                      (and (> cfg-brake-a 0.0)
                           (< d-amps (- 0.0 cfg-brake-a))))))

; ---------------------------------------------------------------------------
; COMM_GET_VALUES_SETUP over CAN
;
; The standard status frames carry voltage, current, duty, rpm, tacho and
; temperatures, but not state of charge, speed in real units or distance -
; which is why dash_esc broadcasts its own. Asking the controller for
; GET_VALUES_SETUP instead gets all of it computed with the controller's own
; gearing, wheel size and battery configuration, so nothing has to be entered
; twice and nothing has to be estimated.
;
; The request goes out as CAN_PACKET_PROCESS_SHORT_BUFFER; the reply comes
; back as a run of CAN_PACKET_FILL_RX_BUFFER fragments followed by
; CAN_PACKET_PROCESS_RX_BUFFER, which is where it gets parsed.
; ---------------------------------------------------------------------------
; our own CAN id, so the controller knows where to send the answer

; A BMS is there when it has said something lately. Asked with none on the
; bus, get-bms-val answers 0.0 (and a message age of hours), and 0.0 is not
; nil, so this said yes with no BMS at all: poll-bms then put the BMS's 0 into
; the charge whenever the setup reply was a moment late, and the screen's
; battery bar emptied and came back (bench, 2026-10-24). The age key is
; trapped so a firmware without it reads as no BMS rather than an error.
(defun bms-live () {
        (var a (trap (get-bms-val 'bms-msg-age)))
        (and (eq (car a) 'exit-ok) (< (car (cdr a)) 10.0)
             (> (get-bms-val 'bms-cell-num) 0))
})

(defun sv-live () (< (secs-since sv-last) 3.0))

(defun sv-info () (print (list "setup frames" sv-frames
                              "ago" (secs-since sv-last)
                              "esc" cfg-esc-id "me" cfg-my-id
                              "fills" sv-fills "done" sv-dones)))

; A controller sends a package's app data (send-data) to whichever interface
; talked to it last, and this request makes that the link: CU Wheelie's
; 25 Hz text then crossed the bus to the link as some 2,000 CAN fragments a
; second (bench, 2026-10-23), loading the bus and starving an IMU board's own
; loop. So straight after asking, a second request with send mode 2 - process,
; no reply - leaves the controller with no app data destination at all. The
; answer to the first has gone by then. A Bluetooth display or VESC Tool takes
; it back with its next command, a tenth of a second later.
(defun sv-request () (core-request cfg-esc-id 47))

(defun core-request (id cmd) {
        (var b (bufcreate 3))
        (bufset-u8 b 0 cfg-my-id)     ; who to reply to
        (bufset-u8 b 1 0)             ; send mode 0: process and answer
        (bufset-u8 b 2 cmd)           ; setup telemetry or temporary limit readback
        (def sv-req-id id) (def sv-req-cmd cmd) (def sv-req-gen mode-limit-gen)
        (if sv-buf (bufclear sv-buf))
        (def sv-req-t (systime))
        (can-send-eid (bitwise-or id (shl 8 8)) b)
        (bufset-u8 b 1 2)             ; send mode 2: process, no reply
        (bufset-u8 b 2 0)             ; COMM_FW_VERSION, harmless
        (can-send-eid (bitwise-or id (shl 8 8)) b)
        (free b)
})

 ; One request window at a time: never interleave 47 and 91 fragments.
; At most one limit read per second (alternate controllers if there are two).
; Continue this check even if optional setup telemetry has been disabled.
(defun core-poll () {
        (if (and mode-limit-buf (!= mode-limit-id cfg-esc-id)) {
                (free mode-limit-buf) (def mode-limit-buf nil)
                (def mode-applied nil) (def mode-limit-gen (+ mode-limit-gen 1))
        })
        (if (and (not gw-can-job) (bridge) (> (secs-since sv-req-t) 0.33)
                 (or (> (secs-since gw-can-last) 0.20) (> (secs-since sv-last) 1.0)))
            (if (and (mode-check-active) (> (secs-since mode-check-t) 1.0)) {
                    (def mode-check-t (systime))
                    (def mode-check-second (not mode-check-second))
                    (core-request (if (and cfg-esc2-en mode-check-second) cfg-esc2-id cfg-esc-id) 91)
            } (if (and cfg-setup-en (not (dash-esc-live))) (sv-request))))
})

(defun sv-i16 (b i) (bufget-i16 b i))
(defun sv-i32 (b i) (bufget-i32 b i))

(defun sv-parse (b) {
        (if (< (buflen b) 60) nil {
                (def d-tesc (/ (to-float (sv-i16 b 1)) 10.0))
                (def d-tmot (/ (to-float (sv-i16 b 3)) 10.0))
                (def d-amps (/ (to-float (sv-i32 b 5)) 100.0))
                (var i-in (/ (to-float (sv-i32 b 9)) 100.0))
                (def d-duty (/ (to-float (sv-i16 b 13)) 1000.0))
                ; speed arrives in metres per second
                (def d-speed (* (/ (to-float (sv-i32 b 19)) 1000.0) 3.6))
                (def d-volt (/ (to-float (bufget-u16 b 23)) 10.0))
                ; the controller works this out from its own battery settings
                ; the controller's own figure, unless the rider prefers the BMS
                (if (or (= cfg-soc-src 0) (not (bms-live)))
                    (def d-soc (/ (to-float (bufget-u16 b 25)) 1000.0)))
                (def d-wh (/ (to-float (sv-i32 b 35)) 10000.0))
                ; distance is metres scaled by a thousand
                (var tk (/ (to-float (sv-i32 b 43)) 1000000.0))
                (def d-trip (if (< tk 0.0) 0.0 tk))
                (def d-fault (bufget-u8 b 55))
                (if (>= (buflen b) 66)
                    (def d-odo (/ (to-float (bufget-u32 b 62)) 1000.0)))
                (def d-iin i-in)
                (def d-kw (* d-volt i-in 0.001))
                (def sv-frames (+ sv-frames 1))
                (def sv-last (systime))
                true
        })
})

; Two things can report state of charge: the controller, which works it out
; from its own cell count and battery type, and a BMS, which measures the pack
; directly. Rather than let whichever updated last win, the rider picks - and
; if the preferred one goes quiet the other is used instead.
;   0 controller   1 BMS
(defun poll-bms () {
        (var soc (get-bms-val 'bms-soc))
        (if (bms-live) {
                (def d-tbat (get-bms-val 'bms-temp-cell-max))
                ; take it when it is preferred, or when the controller is not
                ; answering the setup request
                (if (or (= cfg-soc-src 1) (not (sv-live))) (def d-soc soc))
        })
})

; ---------------------------------------------------------------------------
; BMS frame 0xCB - cells and pack detail, sent slower than telemetry
;  0 magic  1 ncells  2 i16 packI x10  4 i16 tmax x10  6 i16 tmin x10
;  8 u16 soc x1000  10 u16 ah-cnt x10  12 u16 ah-full x10  14 u8 flags
; 16.. u16 cell mV
; ---------------------------------------------------------------------------
(defun send-bms () {
        (var n (get-bms-val 'bms-cell-num))
        (if (and cfg-bms-en n (> n 0)) {
                (var nc (if (> n 24) 24 n))
                (var len (+ 16 (* nc 2)))
                (var b (bufcreate len))
                (var cur (get-bms-val 'bms-i-in-ic))
                (bufset-u8  b 0 0xCB)
                (bufset-u8  b 1 nc)
                (bufset-i16 b 2 (to-i (* cur 10.0)))
                (bufset-i16 b 4 (to-i (* (get-bms-val 'bms-temp-cell-max) 10.0)))
                (bufset-i16 b 6 (to-i (* (get-bms-val 'bms-temp-ic) 10.0)))
                (bufset-u16 b 8 (to-i (* (get-bms-val 'bms-soc) 1000.0)))
                (bufset-u16 b 10 (to-i (* (get-bms-val 'bms-ah-cnt) 10.0)))
                (bufset-u16 b 12 (to-i (* (get-bms-val 'bms-ah-cnt-chg-total) 10.0)))
                (bufset-u8  b 14 (if (> cur 0.5) 1 0))
                (looprange i 0 nc
                    (bufset-u16 b (+ 16 (* i 2))
                        (to-i (* (get-bms-val 'bms-v-cell i) 1000.0))))
                (esp-now-send bcast b)
                (free b)
        })
})

; ---------------------------------------------------------------------------
; Frame, big endian - the first 32 bytes; the rest are set out below
;  0 u8  magic      1 u8  flags     2 i16 speed x10   4 i16 amps x10
;  6 u16 volts x10  8 i16 tmot x10 10 i16 tesc x10   12 i16 tbat x10
; 14 u16 soc x1000 16 i16 kw x100  18 i16 duty x1000 20 u16 trip x10
; 22 u32 odo x10   26 u16 wh x10   28 u16 fault      30 u16 link-seq
; ---------------------------------------------------------------------------

(defun clampi (v lo hi) (cond ((< v lo) lo) ((> v hi) hi) (t v)))

; A link that cannot send is no link, and after a day and a half up an Express
; IMU on the bench refused every esp-now-send, broadcast or not, re-adding the
; peer and restarting wifi changed nothing, while it still heard the display
; and ran happily otherwise - the screen sat offline for two hours (2026-10-25).
; Only a restart cleared it. So when nothing has gone out for 5 s the board
; restarts itself: a few seconds of "offline" instead of offline until someone
; switches the cart off and on. Not in the first 30 s, so it cannot loop.
;
; Its own thread, not the Link loop: on stock Express firmware esp-now-send
; blocks its caller until the radio reports, with no timeout, and a report
; that never comes leaves the caller blocked for good. The same IMU board was
; found with its Link thread blocked in a send for 43 hours (2026-10-27) - the
; check, sitting in that loop, never ran. And only stopped: on an IMU board
; the restart takes CU Wheelie's pitch away for a few seconds, so with
; the bike moving the screen waits rather than the rider.
(def tx-ok-t (systime))
(defun spd-known () (or (dash-esc-live) (sv-live)))
(defun tx-watch ()
    (if (and (> (secs-since tx-ok-t) 5.0) (> (secs-since 0) 30.0)
             (spd-known) (< (abs d-speed) 1.0)) {
            (print "esp-now sends failing for 5 s - restarting")
            (sleep 0.2)
            (reboot)
    }))

(defun send-frame () {
        (bufset-u8  tx 0 magic)
        (bufset-i16 tx 2 (to-i (* d-speed 10.0)))
        (bufset-i16 tx 4 (to-i (* d-amps 10.0)))
        (bufset-u16 tx 6 (to-i (clampi (* d-volt 10.0) 0 65535)))
        (bufset-i16 tx 8 (to-i (* d-tmot 10.0)))
        (bufset-i16 tx 10 (to-i (* d-tesc 10.0)))
        (bufset-i16 tx 12 (to-i (* d-tbat 10.0)))
        (bufset-u16 tx 14 (to-i (clampi (* d-soc 1000.0) 0 65535)))
        (bufset-i16 tx 16 (to-i (* d-kw 100.0)))
        (bufset-i16 tx 18 (to-i (* d-duty 1000.0)))
        (bufset-u16 tx 20 (to-i (clampi (* d-trip 10.0) 0 65535)))
        ; 4294967295 does not fit in a 32 bit integer: it wraps to -1, so the
        ; clamp forced every reading to -1 and the frame carried 0xFFFFFFFF.
        ; Clamp in kilometres, before the scale, well inside the range.
        (bufset-u32 tx 22 (to-i (* (clampi d-odo 0.0 200000.0) 10.0)))
        (bufset-u16 tx 26 (to-i (clampi (* d-wh 10.0) 0 65535)))
        (bufset-u16 tx 28 d-fault)
        (bufset-u16 tx 30 link-seq)
        (bufset-i16 tx 32 (to-i (* e2-tmot 10.0)))
        (bufset-i16 tx 34 (to-i (* e2-tesc 10.0)))
        (bufset-i16 tx 36 (to-i (* e2-amps 10.0)))
        (bufset-i16 tx 38 (to-i (* e2-duty 1000.0)))
        ; dash_esc extras
        (bufset-u8  tx 40 x-cruise)
        (bufset-u8  tx 41 (if (dash-esc-live) 1 0))
        (bufset-i16 tx 42 (to-i (* x-pitch 100.0)))
        (bufset-u16 tx 44 (to-i (* x-amp-max 10.0)))
        (bufset-u16 tx 46 (to-i (* x-wh-chg 10.0)))
        ; our mac, so the dash can address us directly. Broadcast is not
        ; always received, a directed send is.
        (if my-mac (looprange i 0 6 (bufset-u8 tx (+ 48 i) (ix my-mac i))))
        (bufset-i16 tx 54 (to-i (* d-iin 10.0)))
        ; dash_esc's SID 25, appended: 56 valid, 57 mode (its numbering),
        ; 58 suspended, 59 motor config bad, 60 logging
        (var xm (< (secs-since x-mode-last) 2.0))
        (bufset-u8 tx 56 (if xm 1 0))
        (bufset-u8 tx 57 (if xm x-mode 0))
        (bufset-u8 tx 58 (if xm x-susp 0))
        (bufset-u8 tx 59 (if xm x-mbad 0))
        (bufset-u8 tx 60 (if xm x-log 0))
        ; 61-64: a CU IO Link's switches. 61: bit 7 there are some, bit 0
        ; hold reverse held, bits 1 and 2 SW1 and SW2 active (for show).
        ; 62 event number, 63 action, 64 value (2 fire, 1 on, 0 off): each
        ; event goes out in four frames running, so a short burst of lost
        ; frames loses nothing (the display runs each number once).
        (bufset-u8 tx 61 (if (or (> core-inputs 0) pr-fwd-seen) (bitwise-or 0x80 (bitwise-or (if sw-rev-held 1 0) (* io-sw 2))) 0))
        ; 65-72 CU Wheelie's last telemetry frame as it came off the bus
        ; (zeros when it is not there), 73 which settings are known, 74-97
        ; its six settings, f32 each, in its register order
        (if (whl-live) (bufcpy tx 65 whl-tel 0 8) (bufset-u8 tx 65 0))
        (bufset-u8 tx 73 whl-regmask)
        (bufcpy tx 74 whl-regs 0 24)
        (if (!= ev-r ev-w) {
                (bufset-u8 tx 62 ev-r)
                (bufset-u8 tx 63 (bufget-u8 ev-buf (* ev-r 2)))
                (bufset-u8 tx 64 (bufget-u8 ev-buf (+ (* ev-r 2) 1)))
                (def ev-sent (+ ev-sent 1))
                (if (>= ev-sent 4) { (def ev-sent 0) (def ev-r (mod (+ ev-r 1) 16)) })
        } {
                (bufset-u8 tx 63 0)
        })
        (setq link-seq (mod (+ link-seq 1) 65536))
        ; bit 1 of flags marks a long frame carrying the second controller
        (var ext (dash-esc-live))
        ; online: status frames, or the setup values the link asks for -
        ; a controller with status messages switched off still answers those
        (bufset-u8 tx 1 (bitwise-or
                (if (or (< (secs-since d-last) 2.0) (sv-live)) 1 0)
                (bitwise-or (if cfg-esc2-en 2 0)
                (bitwise-or (if ext 4 0)
                (bitwise-or (if (or aux-left aux-hazard) 8 0)
                (bitwise-or (if (or aux-right aux-hazard) 16 0)
                (bitwise-or (if aux-beam 32 0)
                (bitwise-or (if (bridge) 64 0)
                            (if (pr-peer) 128 0)))))))))
        (bufset-u8 tx 98 core-role)
        ; 99-104 the dash this link obeys, zeros for none: a dash looking for
        ; its link passes over one that is another dash's
        (looprange i 0 6 (bufset-u8 tx (+ 99 i) (if dash-mac (ix dash-mac i) 0)))
        ; 105-112: optional Wheelie attitude extension. Older screens ignore it;
        ; older controllers leave marker zero. Never forward another ESC's roll.
        (whl-att-pack tx)
        (bufset-u8 tx 113 0xD7) (bufset-u8 tx 114 cfg-esc-id)
        (hall-link-pack tx)
        (setup-link-pack tx)
(if (and (= pm-link-id cfg-esc-id) (< (secs-since pm-link-t) 2.0))
    (bufcpy tx 185 pm-link-data 0 8) (bufset-u8 tx 185 0))
        ; One length for every case. Three variable lengths saved a few bytes
        ; per frame and cost a bug: the mac only reached the dash when
        ; dash_esc happened to be running, so the dash could never learn where
        ; to send commands.
        (if (eq (esp-now-send bcast tx) t) (def tx-ok-t (systime)))
})

; ---------------------------------------------------------------------------


; ---------------------------------------------------------------------------
; Several Charged Up devices on one bus (CHARGED_UP_PLATFORM.md section 4).
; Only one of them - the bridge - talks to the controller: the mode and its
; heartbeat, limits, setup value requests. Two doing it fought over the
; limits and doubled the requests, whose replies take over the controller's
; app data. Each says once a second, and at once when its lights or mode
; change, who it is:
;
;   SID 0x5F0 + (mac 5 & 15): [0x43][role][priority][mac 3-5][flags][mode+1]
;   flags: 0 a paired display talks to it, 1 bridge, 2 left, 3 right,
;          4 hazard, 5 beam, 6 lights off, 7 brake
;
; The bridge is the one with a display before one without, then the lowest
; priority, then the lowest mac. Each works it out from what it hears, so
; nothing is negotiated, and a bridge that goes quiet is replaced within
; three seconds. The others follow its lights and mode and send it their
; switch presses, which it runs as its own:
;
;   SID 0x5E0 + (mac 5 & 15): [0x41][action][value][mac 3-5]
;
; Keys are five bytes, compared in order: [no display][priority][mac 3-5].
; ---------------------------------------------------------------------------
(defun pr-less (a b) {
        (var r 0)
        (looprange i 0 5 (if (= r 0) {
                (var x (bufget-u8 a i)) (var y (bufget-u8 b i))
                (if (< x y) (setq r 1) (if (> x y) (setq r 2)))
        }))
        (= r 1)
})
(defun pr-peer () (and pr-any (< (secs-since pr-t) 3.0)))
(defun bridge () {
        (bufset-u8 pr-me 0 (if (rx-live) 0 1))
        (bufset-u8 pr-me 1 core-prio)
        (or (not (pr-peer)) (pr-less pr-me pr-best))
})
; kept on the device itself: its outputs, and frames anyone may send
(defun pr-keep-act (a) (or (= a 12) (= a 13) (= a 19) (= a 30) (= a 31)))

(defun pr-flags () (+ (if (rx-live) 1 0) (if (bridge) 2 0)
                      (if aux-left 4 0) (if aux-right 8 0) (if aux-hazard 16 0)
                      (if aux-beam 32 0) (if lt-dark 64 0) (if lt-brake 128 0)))

(defun pr-sid (base) (+ base (bitwise-and (ix my-mac 5) 15)))

(defun pr-tick () (if my-mac {
        (var f (pr-flags))
        (var m (+ cfg-mode 1))
        (if (or (!= f pr-sent-f) (!= m pr-sent-m) (> (secs-since pr-sent-t) 1.0)) {
                (def pr-sent-f f) (def pr-sent-m m) (def pr-sent-t (systime))
                (var b (bufcreate 8))
                (bufset-u8 b 0 0x43) (bufset-u8 b 1 core-role) (bufset-u8 b 2 core-prio)
                (looprange i 0 3 (bufset-u8 b (+ i 3) (ix my-mac (+ i 3))))
                (bufset-u8 b 6 f) (bufset-u8 b 7 m)
                (trap (can-send-sid (pr-sid 0x5F0) b))
                (free b)
        })
}))

(defun pr-recv (data) (if (and (= (buflen data) 8) (= (bufget-u8 data 0) 0x43)) {
        (var fl (bufget-u8 data 6))
        (var k (bufcreate 5))
        (bufset-u8 k 0 (if (= (bitwise-and fl 1) 1) 0 1))
        (bufset-u8 k 1 (bufget-u8 data 2))
        (bufcpy k 2 data 3 3)
        ; the best so far again (it may have got worse), or a better one
        (if (or (not (pr-peer)) (pr-less k pr-best)
                (and (= (bufget-u16 k 2) (bufget-u16 pr-best 2))
                     (= (bufget-u8 k 4) (bufget-u8 pr-best 4)))) {
                (bufcpy pr-best 0 k 0 5)
                (def pr-any true)
                (def pr-t (systime))
        })
        (free k)
        ; an IO Link on the bus: its presses come through the bridge, so the
        ; display is told to expect events from the first frame (byte 61)
        (if (= (bufget-u8 data 1) 2) (def pr-fwd-seen true))
        ; the bridge's lights and mode, when it is not us
        (if (and (= (bitwise-and fl 2) 2) (not (bridge))) {
                (var was (list aux-left aux-right aux-hazard aux-beam))
                (def aux-left (= (bitwise-and fl 4) 4))
                (def aux-right (= (bitwise-and fl 8) 8))
                (def aux-hazard (= (bitwise-and fl 16) 16))
                (def aux-beam (= (bitwise-and fl 32) 32))
                (def lt-dark (= (bitwise-and fl 64) 64))
                (def pr-brake (= (bitwise-and fl 128) 128))
                (def cfg-mode (- (bufget-u8 data 7) 1))
                ; so a mode frame from our own display, the same as the one
                ; acted on before, is acted on again once we bridge
                (def mode-applied nil)
                ; and its relay outputs follow too, if this board drives some
                (if (not (eq was (list aux-left aux-right aux-hazard aux-beam)))
                    (send-signals))
        })
}))

(defun pr-act-send (a v) {
        (var b (bufcreate 6))
        (bufset-u8 b 0 0x41) (bufset-u8 b 1 a) (bufset-u8 b 2 v)
        (looprange i 0 3 (bufset-u8 b (+ i 3) (ix my-mac (+ i 3))))
        (trap (can-send-sid (pr-sid 0x5E0) b))
        (free b)
})

(defun pr-act-recv (data)
    (if (and (= (buflen data) 6) (= (bufget-u8 data 0) 0x41) (bridge)) {
            (def pr-fwd-seen true)
            (sw-do (bufget-u8 data 1) (bufget-u8 data 2))
    }))

; ---------------------------------------------------------------------------
; Starting the link. The product calls this last, after its own setup.
; ---------------------------------------------------------------------------
(defun core-start () {
        (def core-t0 (systime))
        (trap (dash-load))
        ; a kept dash gets 30 s from power up before another can take over
        (def dash-t (systime))
        (var mid (car (cdr (trap (conf-get 'controller-id)))))
        (if (and mid (> mid 0)) (def cfg-my-id mid))
        ; Every VESC Express ships on CAN id 2, so a link beside an Express IMU
        ; (or any other Express) shares its id and the two answer each other's
        ; traffic - VESC Tool, setup values, package installs. A few seconds
        ; after start, ask the bus for this id; an answer can only be another
        ; device, so move to the first free id from 20 and keep it.
        (spawn (fn () {
                ; staggered by the MAC, so two links that start together
                ; and share an id do not both move to the same new one
                (sleep (+ 4.0 (* 0.02 (ix (get-mac-addr) 5))))
                (if (car (cdr (trap (can-ping cfg-my-id)))) {
                        (var new -1)
                        (looprange i 20 60
                            (if (and (< new 0) (!= i cfg-esc-id)
                                     (not (car (cdr (trap (can-ping i))))))
                                (setq new i)))
                        (if (>= new 0) {
                                (print (list "CAN id" cfg-my-id "is taken, moving to" new))
                                (trap (conf-set 'controller-id new))
                                (trap (conf-store))
                                (def cfg-my-id new)
                        })
                })
        }))
        ; Safe to run again: a package installed over a running one restarts
        ; the program, not the radio, and these must not stop it there.
        (trap (wifi-start))
        (trap (esp-now-start))
        (trap (wifi-set-chan cfg-chan))
        (trap (esp-now-add-peer bcast))
        (def my-mac (get-mac-addr))
        (looprange i 0 3 (bufset-u8 pr-me (+ i 2) (ix my-mac (+ i 3))))
        (print (list "mac:" my-mac "chan:" (trap (wifi-get-chan))))

        ; a stored kid limit is reapplied after boot, so power cycling does
        ; not lift it - unless a display has sent its mode by then, which
        ; carried it. Once only - config writes stall the motor. After the
        ; five seconds apply-mode waits for dash_esc.
        (if cfg-kid-on
            (spawn (fn () {
                    (sleep 6.0)
                    (if (not mode-known) {
                            (var b (mode-frame cfg-mode))
                            (apply-mode b)
                            (free b)
                            (print "kid limit applied")
                    })
            })))

        ; its own thread, so a stall anywhere else cannot leave a duty
        ; command standing
        (spawn walk-thread)

        ; finding the controllers: its own thread, because a ping scan of the
        ; bus blocks for as long as it takes
        (loopwhile-thd ("EscFind" 150) t {
                (if cfg-esc-auto (trap (esc-find)))
                (sleep 2.0)
        })

        ; The mode is a heartbeat, not a one-off: dash_esc puts the
        ; configured limits back after five seconds without a display, so a
        ; mode sent only on change lapsed five seconds after it was picked.
        ; Ten a second while the dash is talking - the rate a CAN display
        ; sends at - and only once the dash has said which mode it wants, so
        ; a link with no dash never chooses one on its own.
        (loopwhile-thd ("Mode" 120) t {
                ; Kids mode keeps it going with no dash too: it lives here so
                ; that pulling the display does not lift the limit, and with
                ; dash_esc the limit is the mode, which lapses without this.
                (if (and mode-known (or (rx-live) cfg-kid-on mode-local)) (trap (send-201)))
                (sleep 0.1)
        })

        (event-register-handler (spawn "CanRx" 256 event-handler))
        (event-enable 'event-can-sid)
        (event-enable 'event-can-eid)
        (trap (event-enable 'event-esp-now-rx))
        (trap (event-enable 'event-data-rx))

        (loopwhile-thd ("TxWatch" 100) t {
                (tx-watch)
                (sleep 1.0)
        })

        (loopwhile-thd ("Link" 200) t {
                (match (trap (loopwhile t {
                            (poll-bms)
                            ; ask the controller for the setup values a few
                            ; times a second; everything else on CAN arrives
                            ; unprompted. Wrapped tightly: a failure here must
                            ; not take down the thread that sends telemetry.
                            ; dash_esc broadcasts speed, charge and distance
                            ; itself, so asking is only for controllers without
                            (trap (gw-can-tick))
                            (trap (core-poll))
                            (brake-check)
                            ; walk assist from an input: the link's own dead
                            ; man, renewed while it is held
                            (if sw-walk (def walk-req (systime)))
                            ; hold reverse let go with no display: the gear
                            ; comes back once stopped and off the throttle
                            (if (and sw-rev-wait (< (abs d-speed) 1.6) (< (abs d-duty) 0.03)) {
                                    (def sw-rev-wait false)
                                    (if (= cfg-mode -1) (link-mode sw-prev))
                            })
                            (send-frame)
                            (pr-tick)
                            (setq bms-tick (+ bms-tick 1))
                            (if (>= bms-tick (to-i (/ cfg-hz cfg-bms-hz))) {
                                    (setq bms-tick 0)
                                    (trap (send-bms))
                            })
                            (sleep (/ 1.0 cfg-hz))
                }))
                    ((exit-ok (? a)) nil)
                    (_ (print "link crashed")))
                (sleep 1.0)
        })

        ; These reset on an erase and none of the failures are visible from
        ; the dash, so report them here.
        (var cb (car (cdr (trap (conf-get 'can-baud-rate)))))
        (print (list "can baud" cb "(2 = 500k)" "id" cfg-my-id
                     "wifi" (car (cdr (trap (conf-get 'wifi-mode))))
                     "chan" (car (cdr (trap (wifi-get-chan))))))
})

(defun rx-live () (< (secs-since rx-last) 5.0))

; shows the whole receive path in one line
(defun rxinfo () (print (list "rx" rx-count "len" rx-last-len
                              "magic" rx-last-m0
                              "ago" (secs-since rx-last)
                              "other" ev-count "err" ev-err
                              "chan" (trap (wifi-get-chan))
                              "mac" (get-mac-addr))))

@const-end

; ---------------------------------------------------------------------------
; Written at runtime, so outside the const block: const moves data to flash,
; where every write is silently ignored.
; ---------------------------------------------------------------------------
(def core-magic 0x43554C31)   ; "CUL1"
; hooks, see the top
(def core-app-hook nil) (def core-sid-hook nil) (def core-op-hook nil)
(def core-brake-hook nil) (def core-inputs 0)
(def core-role 4) (def core-prio 50)
; the election, see pr-recv
(def pr-me (bufcreate 5)) (def pr-best (bufcreate 5)) (def pr-any false) (def pr-t 0)
(def pr-brake false) (def pr-fwd-seen false)
(def pr-sent-f -1) (def pr-sent-m -1) (def pr-sent-t 0)

(def cfg-soc-src 0)   ; 0 controller, 1 BMS
(def cfg-setup-en true)        ; ask the controller rather than wait for dash_esc
(def cfg-my-id 20)
(def sv-buf nil) (def sv-bad 0) (def sv-req-t 0) (def sv-last 0) (def sv-frames 0) (def sv-fills 0) (def sv-dones 0) (def sv-tick 0)
(def cfg-esc-id 6)
(def cfg-esc2-en false)
(def cfg-esc2-id 0)
; find the controllers rather than be told: on unless switched off
(def cfg-esc-auto true)
(def esc-types nil)   ; (id . hw type) for ids already pinged
(def esc-found nil)   ; motor controllers last seen, lowest id first
(def esc-scan-t nil)  ; never scanned
(def esc-scan-n 0)    ; scans since a controller was last found
(def core-t0 0)       ; when core-start ran
(def cfg-io-en false)
(def cfg-io-id 4)
(def cfg-ch-left 1) (def cfg-ch-right 2) (def cfg-ch-beam 3) (def cfg-ch-horn 4)
(def cfg-bms-en true)
(def cfg-bms-hz 2.0)
(def cfg-chan 1)        ; wifi channel - MUST match the screen
(def cfg-hz 15.0)
(def cfg-brake-a 3.0)   ; regen amps that count as braking, 0 off
; Kids mode, stored here rather than on the dash so pulling the display does
; not lift the limit.
(def cfg-kid-on false) (def cfg-kid-mph 26.0) (def cfg-kid-w 2000.0)
; Walk assist. Off until somebody turns it on: the only thing here that
; drives the motor rather than reporting on it.
(def cfg-walk-en false)
(def cfg-walk-kph 6.0)   ; hold at walking pace
(def cfg-walk-duty 0.18) ; and never ask for more than this
(def walk-req 0) (def walk-duty 0.0) (def walk-run false)

(def d-speed 0.0) (def d-tmot 0.0) (def d-tesc 0.0) (def d-amps 0.0) (def d-iin 0.0)
(def d-volt 0.0)  (def d-soc 0.0)  (def d-kw 0.0)   (def d-duty 0.0)
(def d-tbat 0.0)  (def d-trip 0.0) (def d-odo 0.0)  (def d-wh 0.0)
(def d-fault 0)   (def link-seq 0)      (def d-last 0)
(def e2-tmot 0.0) (def e2-tesc 0.0) (def e2-amps 0.0) (def e2-duty 0.0)

(def cfg-mode 1)
(def aux-left false) (def aux-right false) (def aux-hazard false) (def aux-beam false)
(def lt-brake false) (def lt-dark false) (def lt-brake-man false)
(def x-cruise 0) (def x-cruise-kmh 0.0) (def x-pitch 0.0) (def x-amp-avg 0.0)
(def x-amp-max 0.0) (def x-wh-chg 0.0) (def x-batt-ah 0.0) (def x-last 0)
(def x-mode 0) (def x-log 0) (def x-susp 0) (def x-mbad 0) (def x-mode-last 0)
(def x-disp-t 0)
(def mode-known false)
(def mode-applied nil)   ; the last mode frame acted on, see apply-mode
(def mode-seq -1)        ; its change count, -1 none
(def mode-rx-t 0)        ; when a mode frame last arrived
(def x-ever false)       ; dash_esc heard at least once since boot
(def bms-tick 0)
(def dash-mac nil)       ; the dash this link obeys, see dash-ok
(def dash-t 0)           ; when it was last heard
(def dash-nolearn false) ; set by the flasher until the next power up
(def rx-last 0) (def rx-count 0) (def rx-last-len 0) (def rx-last-m0 0) (def ev-count 0) (def ev-err 0)
(def my-mac nil)

; 105 bytes: the frame proper, dash_esc's SID 25, inputs, CU Wheelie,
; role, the dash it obeys
(def tx (bufcreate 193))
(def pm-link-data (bufcreate 8)) (def pm-link-id -1) (def pm-link-t 0)

; inputs and the actions they run
(def io-sw 0)            ; inputs active, bit n input n
(def dash-sw-t 0)        ; when the display last said it takes input events
(def sw-walk false) (def sw-prev 1) (def sw-rev-held false) (def sw-rev-wait false)
(def mode-local false)   ; an input has set the mode, so keep sending it
(def ev-buf (bufcreate 32)) (def ev-w 0) (def ev-r 0) (def ev-sent 0)
; CU Wheelie, see whl-proc
(def hl-next -1) (def hl-seq -1) (def hl-session -1) (def hl-begin 0)
(def hl-id -1) (def hl-t 0) (def hl-work (bufcreate 24)) (def hl-data (bufcreate 29))
(def whl-t 0) (def whl-id -1) (def whl-asked false) (def whl-regmask 0)
(def whl-tel (bufcreate 8)) (def whl-regs (bufcreate 24))
(def whl-att (bufcreate 8)) (def whl-att-id -1) (def whl-att-t 0)

; Fallback RAM-limit verification state (no EEPROM writes).
(def mode-limit-buf nil) (def mode-limit-id -1) (def mode-limit-gen 0)
(def mode-check-t 0) (def mode-check-second false)
(def mode-checks 0) (def mode-repairs 0)
(def sv-req-id -1) (def sv-req-cmd 47) (def sv-req-gen -1)

(def su-held false) (def su-mask 0) (def su-next -1) (def su-session -1) (def su-seq -1)
(def su-begin 0) (def su-t 0) (def su-id -1)
(def su-work (bufcreate 36)) (def su-data (bufcreate 41))
