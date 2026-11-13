;! ANT BMS over Bluetooth, for link boards.
;; ============================================================================
; cu_link_ant - reads an ANT BMS over Bluetooth for a Charged Up link product
;
; Optional: it needs the board's Bluetooth and some memory, and a CUP-3.5 can
; read the same BMS itself, so a product includes this only when it wants the
; link to carry the pack to the controller (set-bms-val, so the controller and
; VESC Tool see it) and to the screen (the core's 0xCB frames).
;
; Needs cu_link_core and the Charged Up link firmware's BLE central. Settings
; in EEPROM slots 190-192.
; ============================================================================

@const-start
; The pack's address is kept too, as two halves of three bytes. Only the
; switch was, so after a power cycle the reader was on with no address and
; tried to connect to nothing every few seconds until a pack was picked again.
(defun ant-hex (s) (if (= (str-len s) 17)
        (str-merge (str-part s 0 2) (str-part s 3 2) (str-part s 6 2)
                   (str-part s 9 2) (str-part s 12 2) (str-part s 15 2))
        s))
(defun ant-save () {
        (eeprom-store-i 190 (if cfg-ant-en 1 0))
        (var h (ant-hex cfg-ant-mac))
        (if (= (str-len h) 12) {
                (eeprom-store-i 191 (+ 0x1000000 (str-to-i (str-part h 0 6) 16)))
                (eeprom-store-i 192 (+ 0x1000000 (str-to-i (str-part h 6 6) 16)))
        })
})
(defun ant-load () {
        (def cfg-ant-en (= (core-ri 190 0 1 0) 1))
        (var a (core-ri 191 0x1000000 0x1FFFFFF -1))
        (var b (core-ri 192 0x1000000 0x1FFFFFF -1))
        (if (and (>= a 0) (>= b 0))
            (def cfg-ant-mac (str-merge (str-from-n (- a 0x1000000) "%06X")
                                        (str-from-n (- b 0x1000000) "%06X"))))
})
; ===========================================================================
; ANT BMS over BLE
;
; Needs the vesc_express build with the BLE central patch (ble_cli). Without
; it these calls are simply undefined and the reader stays off, so the package
; still runs on stock firmware.
;
; Everything published here goes through set-bms-val, which means poll-bms,
; send-bms, VESC Tool and the CAN forward all pick it up with no extra wiring.
; ===========================================================================
(def ant-h 16)                 ; FFE1, notify and write share this handle

(def ant-poll (list 0x7E 0xA1 0x01 0x00 0x00 0xBE 0x18 0x55 0xAA 0x55))

(defun ant-le16 (b i)
    (+ (bufget-u8 b i) (* 256 (bufget-u8 b (+ i 1)))))

(defun ant-le16s (b i) {
        (var v (ant-le16 b i))
        (if (> v 32767) (- v 65536) v)
})

; telemetry, function 0x11. Payload from byte 6: sysAut, status, n_temp,
; n_cell, bitmaps, reserved, then cells, temps and the scalars.
(defun ant-parse (b) {
        (var n-temp (bufget-u8 b 8))
        (var n-cell (bufget-u8 b 9))
        (if (or (= n-cell 0) (> n-cell 32)) nil {
                ; the counts must be set before any indexed write: set-bms-val
                ; bounds checks the index against them, so with a count of 0
                ; every per cell write is silently rejected
                (set-bms-val 'bms-cell-num n-cell)
                (set-bms-val 'bms-temp-adc-num n-temp)

                (var e 34)
                (var vmin 10.0)
                (var vmax 0.0)
                (looprange i 0 n-cell {
                        (var cv (/ (to-float (ant-le16 b (+ e (* i 2)))) 1000.0))
                        (set-bms-val 'bms-v-cell i cv)
                        (if (< cv vmin) (setq vmin cv))
                        (if (> cv vmax) (setq vmax cv))
                })
                (setq e (+ e (* n-cell 2)))

                (var t-max -100.0)
                (looprange i 0 n-temp {
                        (var tc (to-float (ant-le16s b (+ e (* i 2)))))
                        (set-bms-val 'bms-temps-adc i tc)
                        (if (> tc t-max) (setq t-max tc))
                })
                (setq e (+ e (* n-temp 2)))

                (var t-mos (to-float (ant-le16s b e)))
                (setq e (+ e 4))
                (var v-tot (/ (to-float (ant-le16 b e)) 100.0))
                (var i-ant (/ (to-float (ant-le16s b (+ e 2))) 10.0))
                (var soc (ant-le16 b (+ e 4)))

                (set-bms-val 'bms-v-tot v-tot)
                (set-bms-val 'bms-v-charge v-tot)
                (set-bms-val 'bms-v-cell-min vmin)
                (set-bms-val 'bms-v-cell-max vmax)
                (set-bms-val 'bms-temp-cell-max t-max)
                (set-bms-val 'bms-temp-ic t-mos)
                ; ANT reports positive for charge, bms_values for discharge
                (set-bms-val 'bms-i-in-ic (- 0.0 i-ant))
                (set-bms-val 'bms-i-in (- 0.0 i-ant))
                (set-bms-val 'bms-soc (/ (to-float soc) 100.0))
                (trap (send-bms-can))

                (def ant-frames (+ ant-frames 1))
                (def ant-last (systime))
                true
        })
})

; Notifications arrive in MTU sized chunks, so a frame longer than that has to
; be reassembled before parsing.
(defun ant-feed (chunk) {
        (var cn (buflen chunk))
        (if (> (+ ant-len cn) 250) (def ant-len 0))
        (looprange i 0 cn
            (bufset-u8 ant-buf (+ ant-len i) (bufget-u8 chunk i)))
        (def ant-len (+ ant-len cn))
        (cond
            ((< ant-len 6) nil)
            ((not (= (bufget-u8 ant-buf 0) 0x7E)) { (def ant-len 0) nil })
            (t {
                (var total (+ 10 (bufget-u8 ant-buf 5)))
                (if (< ant-len total) nil {
                        (var fc (bufget-u8 ant-buf 2))
                        ; ends in AA 55, or chunks were lost on the way and
                        ; this is pieces of two frames
                        (var r (if (and (= fc 0x11) (= (bufget-u8 ant-buf (- total 2)) 0xAA)
                                        (= (bufget-u8 ant-buf (- total 1)) 0x55))
                                   (ant-parse ant-buf) nil))
                        (def ant-len 0)
                        r
                })
            }))
})

; register_for_notify puts the handle in the stack's table; the CCCD write
; tells the pack to actually send. Both are needed, and in that order.
(defun ant-link () {
        (def ant-state "connecting")
        (trap (ble-disconnect))
        (sleep 1.0)
        (trap (ble-connect cfg-ant-mac))
        (if (= (car (cdr (trap (ble-state)))) 4) {
                (sleep 1.0)
                (trap (ble-notify ant-h))
                (sleep 0.5)
                (trap (ble-cccd ant-h))
                (sleep 0.5)
                (def ant-len 0)
                (def ant-state "connected")
                true
        } { (def ant-state "no link") false })
})

(defun ant-start () {
        (if (not (eq (car (trap (ble-state))) 'exit-ok)) {
                (def ant-state "no ble central in firmware")
                false
        } {
                (def ant-buf (bufcreate 256))
                (loopwhile-thd ("Ant" 200) t {
                        (match (trap (loopwhile t {
                                    (if cfg-ant-en {
                                            (if (not (= (car (cdr (trap (ble-state)))) 4))
                                                (if (not (ant-link)) (sleep 3.0)))
                                            (if (= (car (cdr (trap (ble-state)))) 4) {
                                                    (trap (ble-write ant-h ant-poll))
                                                    (looprange i 0 12 {
                                                            (var f (car (cdr (trap (ble-rx)))))
                                                            (if f (ant-feed f))
                                                            (sleep 0.05)
                                                    })
                                            })
                                    } (sleep 1.0))
                                    (sleep 0.3)
                        }))
                            ((exit-ok (? a)) nil)
                            (_ (print "ant thread restarted")))
                        (sleep 1.0)
                })
                (def ant-running true)
                (def ant-state "running")
                true
        })
})

; Prints one line the settings page turns into a device picker, so the address
; never has to be typed in by hand.
(defun ant-list () {
        (trap (ble-disconnect))
        (sleep 0.5)
        (trap (ble-scan-start 5))
        (spawn (fn () {
                (sleep 5.5)
                (trap (ble-scan-stop))
                (var s "ANTLIST:")
                (loopforeach d (car (cdr (trap (ble-scan-list))))
                    (setq s (str-merge s (ix d 0) "," (ix d 1) ","
                                       (str-from-n (ix d 2) "%d") ";")))
                (print s)
        }))
        true
})

(defun ant-use (mac) {
        (def cfg-ant-mac mac)
        (def cfg-ant-en true)
        (ant-save)
        (trap (ble-disconnect))
        (sleep 0.5)
        (if ant-running (trap (ble-disconnect)) (ant-start))
        true
})

(defun ant-info () (print (list "ant" ant-state "frames" ant-frames
                                "ago" (secs-since ant-last)
                                "mac" cfg-ant-mac)))


@const-end

(def cfg-ant-en false)
(def cfg-ant-mac "")
(def ant-buf nil)
(def ant-len 0)
(def ant-frames 0)
(def ant-last 0)
(def ant-state "off")
(def ant-running false)
