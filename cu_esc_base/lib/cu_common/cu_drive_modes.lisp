;! Charged Up drive profiles. RAM-only motor limits, persistent mode table
;! and kids caps. A display disconnect never raises an applied limit.
@const-start
; Packages without Hall service keep this false.
(def hc-lock nil)
(def lib-cmd-proc [
    0x00 0x00 0x00 0x00 0x08 0xb5 0x07 0x4b 0x07 0x49 0x08 0x48 0x7b 0x44 0x79 0x44 0x1b 0x68 0x03 0x4b
    0x78 0x44 0x1b 0x68 0x98 0x47 0x01 0x20 0x08 0xbd 0x00 0xbf 0x00 0xf8 0x00 0x10 0xf0 0xff 0xff 0xff
    0x2f 0x00 0x00 0x00 0x18 0x00 0x00 0x00 0x65 0x78 0x74 0x2d 0x63 0x6d 0x64 0x2d 0x70 0x72 0x6f 0x63
    0x00 0x00 0x00 0x00 0x01 0x29 0x38 0xb5 0x05 0x46 0x0b 0x4c 0x02 0xd0 0xd4 0xf8 0x90 0x00 0x38 0xbd
    0x63 0x6f 0x00 0x68 0x98 0x47 0x00 0x28 0xf7 0xd0 0xa3 0x6a 0x28 0x68 0x98 0x47 0xd4 0xf8 0x4c 0x32
    0xd0 0xe9 0x00 0x10 0x00 0x22 0x98 0x47 0xd4 0xf8 0x8c 0x00 0xed 0xe7 0x00 0xbf 0x00 0xf8 0x00 0x10
])


(defun base-min (a b) (if (< a b) a b))
(defun base-max (a b) (if (> a b) a b))
(defun base-clamp (v lo hi) (if (< v lo) lo (if (> v hi) hi v)))
; EEPROM integers are i32, while unqualified literals use the VM's native
; integer width. Compare numeric values and spell large markers as i32.
(defun base-marker (slot value) {
    (var saved (eeprom-read-i slot))
    (and saved (= saved value))
})
(defun base-save-f (slot v) (if (not-eq (eeprom-read-f slot) v) (eeprom-store-f slot v)))
(defun base-mode-value (i) (ix base-modes i))
(defun base-speed-factor ()
    (if (and (> (conf-get 'si-motor-poles) 0) (> (conf-get 'si-gear-ratio) 0.0)
             (> (conf-get 'si-wheel-diameter) 0.0))
        (/ (* (conf-get 'si-motor-poles) 0.5 60.0 (conf-get 'si-gear-ratio))
           (* (conf-get 'si-wheel-diameter) 3.14159265)) 0.0))

; Preserve the established 13-value Dash ESC mode-table order and slots 8-20.
(defun base-load () {
    (if (or (base-marker 0 240) (base-marker 0 1129661773i32))
        (looprange i 0 13 {
            (var v (eeprom-read-f (+ 8 i)))
            (var speed (or (= i 0) (= i 4) (= i 7) (= i 10)))
            (if (and v (>= v (if speed 1.0 0.0)) (<= v (if speed 250.0 1.0)))
                (setix base-modes i v))
        }))
    ; Separate marker: old packages never owned these slots. Store the on
    ; flag last, so a new cap is complete before it can become active.
    (if (base-marker 203 1129661771i32) {
        (var mph (eeprom-read-i 201)) (var watts (eeprom-read-i 202))
        (if (and mph watts (>= mph 1) (<= mph 99) (>= watts 1) (<= watts 30000)) {
            (setq base-kid-mph mph) (setq base-kid-w watts)
            (setq base-kid-on (base-marker 200 1))
        })
    })
})

; All clients share the same edit gate; full-table app/QML saves must not
; change a held setup session or running drive profile.
(defun base-mode-editable () (and (= drive-mode 1) (not ms-lock) (not hc-lock)
    (not profile-suspend) (< (abs (get-rpm)) 50) (< (abs (get-current)) 0.2)
    (= (get-fault) 0)))
(defun base-save-modes () (if (not (base-mode-editable))
    (send-data "msg Stop, select Neutral and end setup before saving modes") {
    (if (= (length (rest-args)) 13) {
        ; Validate every value before saving any of them.
        (var good true)
        (looprange i 0 13 {
            (var v (rest-args i))
            (var speed (or (= i 0) (= i 4) (= i 7) (= i 10)))
            (if (not (and (number? v) (>= v (if speed 1.0 0.0))
                          (<= v (if speed 250.0 1.0)))) (setq good false))
        })
        (if good {
            (looprange i 0 13 {
                (setix base-modes i (to-float (rest-args i)))
                (base-save-f (+ 8 i) (base-mode-value i))
            })
            (eeprom-store-i 0 1129661773i32)
            ; Apply on the profile loop after this custom-app reply, just as
            ; field saves do. Native apply changes the command reply callback.
            (setq base-last nil)
            (send-data "msg Modes saved")
        } (send-data "msg Invalid mode limits; nothing saved"))
    } (send-data "msg Expected 13 mode values; nothing saved"))
}))

(defun save-modes () (atomic (apply base-save-modes (rest-args))))

; QML edits a complete table; compare its baseline atomically with the save.
(defun save-modes-checked (expected requested) (atomic {
    (var same (= (length expected) 13))
    (if same (looprange i 0 13 {
        (var v (ix expected i))
        (if (not (and (number? v) (< (abs (- v (base-mode-value i))) 0.00001))) (setq same nil))
    }))
    (if same (apply base-save-modes requested) (send-data "msg Modes changed elsewhere; reload before saving"))
}))

(defun send-modes () {
    (var text "modes ")
    (looprange i 0 13 (setq text (str-merge text (str-from-n (base-mode-value i) "%.6f "))))
    (send-data text)
})
(defun base-modes-status () (print (cons "base-modes" base-modes)))
(defun send-status () (send-data (str-merge "status " (str-from-n drive-mode "%d ")
    (if profile-suspend "1 " "0 ") (str-from-n (secs-since display-ts) "%.1f"))))

; Snapshot at boot only: a live reinstall can still have the old temporary
; profile applied. Until a power cycle gives a trustworthy baseline, stay N.
(defun base-capture () {
    (setq base-ready (and (< (secs-since 0) 30.0)
        (> (conf-get 'l-current-max-scale) 0.0)
        (> (base-speed-factor) 0.0)))
    (if base-ready {
        (var factor (base-speed-factor))
        (setq base-limits (list (conf-get 'l-current-min-scale) (conf-get 'l-current-max-scale)
            (/ (conf-get 'l-min-erpm) factor) (/ (conf-get 'l-max-erpm) factor)
            (conf-get 'l-watt-min) (conf-get 'l-watt-max)))
    })
})

(defun apply-drive-mode (m) {
    (var factor (base-speed-factor))
    (if (<= factor 0.0) (setq base-ready false))
    (if (not base-ready) {
        (setq drive-mode 1)
        (if (!= (conf-get 'l-current-max-scale) 0.0) (conf-set 'l-current-max-scale 0.0))
    } (if (not profile-suspend) {
        (var idx (cond ((= m 0) 0) ((= m 3) 7) ((= m 4) 10) (t 4)))
        (var speed (/ (base-mode-value idx) 3.6))
        (var power (if (= m 1) 0.0 (base-mode-value (+ idx 1))))
        (var brake (if (= m 1) (base-mode-value 3) (base-mode-value (+ idx 2))))
        (var watts (ix base-limits 5))
        (if base-kid-on {
            (setq speed (base-min speed (* base-kid-mph 0.44704)))
            (setq watts (base-min watts base-kid-w))
        })
        ; Never increase the owner's original scale, speed or watt limits.
        ; Neutral leaves braking available and disables positive drive.
        (var wanted (list (base-min brake (ix base-limits 0)) (base-min power (ix base-limits 1))
            (base-max (- speed) (ix base-limits 2)) (base-min speed (ix base-limits 3)) watts))
        (if (or (not-eq wanted base-last)
                (!= (conf-get 'l-current-max-scale) (ix wanted 1))
                (!= (conf-get 'l-current-min-scale) (ix wanted 0))
                ; Firmware converts m/s to ERPM. Allow one ERPM for float
                ; rounding, but repair overwritten limits even in the same mode.
                (> (abs (- (conf-get 'l-min-erpm) (* factor (ix wanted 2)))) 1.0)
                (> (abs (- (conf-get 'l-max-erpm) (* factor (ix wanted 3)))) 1.0)
                (!= (conf-get 'l-watt-min) (ix base-limits 4))
                (!= (conf-get 'l-watt-max) watts)) {
            (var b (bufcreate 37))
            (bufset-u8 b 0 49) (bufset-u8 b 1 0) (bufset-u8 b 2 1)
            (bufset-u8 b 3 0) (bufset-u8 b 4 0)
            (looprange i 0 4 (bufset-f32 b (+ 5 (* i 4)) (ix wanted i)))
            (bufset-f32 b 21 (conf-get 'l-min-duty)) (bufset-f32 b 25 (conf-get 'l-max-duty))
            (bufset-f32 b 29 (ix base-limits 4)) (bufset-f32 b 33 watts)
            (ext-cmd-proc b)
            (free b)
            (setq base-last wanted)
        })
    }))
})

; SID 212: [0x4B][1][on][mph u16][watts u16]. Shared by CAN and BLE.
(defun base-kid-frame (data) {
    (var on (= (bufget-u8 data 2) 1))
    (var mph (bufget-u16 data 3)) (var watts (bufget-u16 data 5))
    (if (and (<= (bufget-u8 data 2) 1) (>= mph 1) (<= mph 99) (>= watts 1) (<= watts 30000)) {
        (var changed (or (not-eq on base-kid-on) (!= mph base-kid-mph) (!= watts base-kid-w)))
        (setq base-kid-on on) (setq base-kid-mph mph) (setq base-kid-w watts)
        (if changed {
            (eeprom-store-i 201 mph) (eeprom-store-i 202 watts)
            (eeprom-store-i 203 1129661771i32) (eeprom-store-i 200 (if on 1 0))
            (setq cruise-on 0)
            (setq base-last nil)
            (apply-drive-mode drive-mode)
        })
    })
})

; Mode-field protocol v1 with additive speed selector 04. One field per save.
; Request 57 32 token mode|field(04 speed)|write(80) value(u16) expected(u16).
; Reply   57 B0 token mode|field|error(10/20/30) actual(u16) version(1) reserved(0).
; Power uses basis points; speed uses hundredths of km/h. Other fields stay intact.
; CAN and custom app data call the same handler and canonical EEPROM table.
(defun base-mode-field-index (m f) (+ (if (= f 4) 4 5) (* m 3)))
(defun base-mode-field-units (m f) (to-i (+ 0.5 (* (if (= f 4) 100.0 10000.0)
    (base-mode-value (base-mode-field-index m f))))))
(defun base-power-units (m) (base-mode-field-units m 0))
(defun base-power-rx (b via) (if (and (= (buflen b) 8)
    (= (bufget-u8 b 0) 0x57) (= (bufget-u8 b 1) 0x32)) (atomic {
    (var flags (bufget-u8 b 3)) (var m (bitwise-and flags 3))
    (var f (bitwise-and flags 4)) (var key (+ m f))
    (if (and (< m 3) (or (= flags key) (= flags (+ key 128)))) {
        (var status 0) (var want (bufget-u16 b 4))
        (if (>= flags 128) {
            (cond
                ((or (< want (if (= f 4) 100 0)) (> want (if (= f 4) 25000 10000))
                     (< (bufget-u16 b 6) (if (= f 4) 100 0))
                     (> (bufget-u16 b 6) (if (= f 4) 25000 10000))) (setq status 48))
                ((not (base-mode-editable)) (setq status 32))
                ((!= (bufget-u16 b 6) (base-mode-field-units m f)) (setq status 16))
                (t {
                    (var idx (base-mode-field-index m f))
                    (var v (/ (to-float want) (if (= f 4) 100.0 10000.0)))
                    (base-save-f (+ 8 idx) v)
                    ; A storage failure must not be presented as a saved value.
                    (var stored (eeprom-read-f (+ 8 idx)))
                    (if (and stored (< (abs (- stored v)) (if (= f 4) 0.0001 0.00001))) {
                        (setix base-modes idx stored)
                        (eeprom-store-i 0 1129661773i32)
                        ; Let the periodic drive loop reapply after this reply. The native
                        ; config command replaces the custom-app reply callback.
                        (setq base-last nil)
                    } (setq status 48))
                }))
        })
        (var reply (bufcreate 8))
        (bufset-u8 reply 0 0x57) (bufset-u8 reply 1 0xB0)
        (bufset-u8 reply 2 (bufget-u8 b 2)) (bufset-u8 reply 3 (+ key status))
        (bufset-u16 reply 4 (base-mode-field-units m f)) (bufset-u8 reply 6 1) (bufset-u8 reply 7 0)
        (if (= via 1) (can-send-sid (+ 0x540 (can-local-id)) reply) (send-data reply))
        (free reply)
    })
    t
}) nil))

@const-end
(def base-modes (list 15.0 0.5 1.0 1.0 20.0 0.5 1.0 25.0 0.6 1.0 250.0 1.0 1.0))
(def base-limits nil) (def base-last nil) (def base-ready false)
(def base-kid-on false) (def base-kid-mph 26) (def base-kid-w 1500)
