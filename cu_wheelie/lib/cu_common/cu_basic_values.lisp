; One typed setting per setup command; only explicit overrides survive reboot.
; Slots 32..41: two commit-last banks, with an active-field mask in packed data.
@const-start
(def bs-magic 1129669170i32)
(def bs-bank -1) (def bs-generation 0) (def bs-saved nil) (def bs-mask 0)
(def bs-token -1) (def bs-value 0)
(def bs-keys '(si-battery-cells l-current-max l-in-current-max))
(def bs-caps '(0 0 0))
(defun bs-current () (map conf-get bs-keys))
(defun bs-pack (v mask) (+ (to-i (ix v 0)) (shl (to-i (ix v 1)) 8)
    (shl (to-i (ix v 2)) 16) (shl mask 24)))
(defun bs-unpack (n) (list (bitwise-and n 255) (bitwise-and (shr n 8) 255) (bitwise-and (shr n 16) 255)))
(defun bs-caps-read () (setvar 'bs-caps (list
    (clamp (to-i (/ (conf-get 'l-max-vin) 4.2)) 0 30)
    (clamp (to-i (conf-get 'l-current-max 2)) 0 250)
    (clamp (to-i (conf-get 'l-in-current-max 2)) 0 250))))
(defun bs-field-valid (field value) (and (>= field 0) (< field 3)
    (>= value (if (= field 0) 6 1)) (<= value (ix bs-caps field))
    (or (!= field 0) (= (ext-ms-battery-type) 0))))
(defun bs-valid (v mask) {
    (var ok (and (= (length v) 3) (> mask 0) (<= mask 7)))
    (looprange i 0 3 (if (!= (bitwise-and mask (shl 1 i)) 0)
        (if (not (bs-field-valid i (ix v i))) (setq ok nil)))) ok
})
(defun bs-read-bank (b) {
    (var at (+ 32 (* b 5))) (var row (map (fn (i) (eeprom-read-i (+ at i))) '(0 1 2 3 4)))
    (if (and (ix row 0) (ix row 1) (ix row 2) (ix row 3) (ix row 4)
        (= (ix row 0) bs-magic) (= (ix row 4) (bitwise-xor bs-magic 0xFFFFFF))
        (>= (ix row 1) 1) (<= (ix row 1) 65535)
        (>= (ix row 2) 0) (<= (ix row 2) 134217727i32)
        (= (ix row 3) (bitwise-xor bs-magic (bitwise-xor (ix row 1) (ix row 2))))
        (bs-valid (bs-unpack (ix row 2)) (shr (ix row 2) 24)))
        (list (ix row 1) (bs-unpack (ix row 2)) (shr (ix row 2) 24)) nil)
})
(defun bs-apply (v mask) {
    (var ok t)
    (looprange i 0 3 (if (!= (bitwise-and mask (shl 1 i)) 0) {
        (conf-set (ix bs-keys i) (ix v i))
        (if (>= (abs (- (conf-get (ix bs-keys i)) (ix v i))) 0.01) (setq ok nil))
    })) ok
})
(defun bs-load () {
    (bs-caps-read)
    (var a (bs-read-bank 0)) (var b (bs-read-bank 1))
    (var newer (and b (or (not a) (and (> (mod (+ 65536 (- (ix b 0) (ix a 0))) 65536) 0)
        (< (mod (+ 65536 (- (ix b 0) (ix a 0))) 65536) 32768)))))
    (var chosen (if newer b a))
    (if chosen {
        (setvar 'bs-bank (if newer 1 0)) (setvar 'bs-generation (ix chosen 0))
        (setvar 'bs-saved (ix chosen 1)) (setvar 'bs-mask (ix chosen 2))
        (bs-apply bs-saved bs-mask)
    })
})
(defun bs-preview () {
    (bs-caps-read)
    (setvar 'ms-values (append (bs-current) (list (to-float (ix bs-caps 1)))))
})
; Action 13: [token: field(2 bits) / serial(6 bits)] [value:u16].
; Session is checked by ms-command; echoed token plus actual value identifies ACK.
(defun bs-save (b) (if (and (= ms-kind 5) (or (= ms-stage 22) (= ms-stage 24)) (= ms-stop 0)) {
    (var token (bufget-u8 b 5)) (var field (shr token 6)) (var value (bufget-u16 b 6))
    (var delta (mod (+ 64 (- (bitwise-and token 63) (bitwise-and bs-token 63))) 64))
    (bs-caps-read)
    (cond
        ((not (and ms-lock (not ms-running) (ms-safe) (> ms-ack 0)
            (< (secs-since ms-ack) 0.6) (< (secs-since ms-beat) 0.6))) (setvar 'ms-error 2))
        ((not (bs-field-valid field value)) (setvar 'ms-error 3))
        ((= token bs-token) (if (= value bs-value) (setvar 'ms-error 0) (setvar 'ms-error 3)))
        ((or (< bs-token 0) (and (> delta 0) (< delta 32))) {
            (setvar 'bs-token token) (setvar 'bs-value value)
            (setvar 'ms-stage 23) (setvar 'ms-error 0) (ms-hold)
            (var v (map (fn (i) (if (= i field) value (if bs-saved (ix bs-saved i) 0))) '(0 1 2)))
            (var mask (bitwise-or bs-mask (shl 1 field)))
            (var target (if (= bs-bank 0) 1 0)) (var at (+ 32 (* target 5)))
            (var seq (+ 1 (mod bs-generation 65535))) (var packed (bs-pack v mask))
            (var result (trap {
                (if (not (and (eeprom-store-i at 0)
                    (eeprom-store-i (+ at 1) seq) (eeprom-store-i (+ at 2) packed)
                    (eeprom-store-i (+ at 3) (bitwise-xor bs-magic (bitwise-xor seq packed)))
                    (eeprom-store-i (+ at 4) (bitwise-xor bs-magic 0xFFFFFF))
                    (eeprom-store-i at bs-magic))) (exit-error 'basic-store-failed))
                (var back (bs-read-bank target))
                (if (not (and back (= (ix back 0) seq) (= (ix back 2) mask)
                    (= (bs-pack (ix back 1) (ix back 2)) packed))) (exit-error 'basic-readback-failed))
                (setvar 'bs-bank target) (setvar 'bs-generation seq)
                (setvar 'bs-saved v) (setvar 'bs-mask mask)
                ; Do not reapply any previously saved field during this command.
                (if (not (bs-apply v (shl 1 field))) (exit-error 'basic-apply-failed)) t
            }))
            (ms-hold) (bs-preview)
            (if (and (eq (car result) 'exit-ok) (ix result 1))
                (setvar 'ms-stage 24) { (setvar 'ms-stage 25) (setvar 'ms-error 4) })
        })
    )
}))
@const-end
