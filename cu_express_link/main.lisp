(import "version.lisp" 'cu-package-version-data)
(read-eval-program cu-package-version-data)
; CU Express Link v1. Stock VESC Express T 7.00, CAN connection.
(import "lib/cu_common/cu_gateway_wire.lisp" 'cu-gateway-wire)
(read-eval-program cu-gateway-wire)
(import "lib/cu_common/cu_gateway_can.lisp" 'cu-gateway-can)
(read-eval-program cu-gateway-can)
(import "lib/cu_common/cu_link_core.lisp" 'cu-link-core)
(read-eval-program cu-link-core)

@const-start
; Connection preferences have their own two-bank store. The live bridge keeps
; its current route until power-up. A screen's core-save cannot overwrite a
; pending change. Slots 220-235 are outside shared link settings (100-149).
(defun express-valid (v) {
    (var ok (= (length v) 5))
    (if ok (loopforeach n v
        (if (not (and (number? n) (= n (to-i n)))) (setq ok false))))
    (and ok (>= (ix v 0) 0) (<= (ix v 0) 1) (>= (ix v 1) 0) (<= (ix v 1) 253)
         (>= (ix v 2) 0) (<= (ix v 2) 1) (>= (ix v 3) 0) (<= (ix v 3) 253)
         (>= (ix v 4) 1) (<= (ix v 4) 13)
         (or (= (ix v 0) 1)
             (and (!= (ix v 1) cfg-my-id)
                  (or (= (ix v 2) 0)
                      (and (!= (ix v 1) (ix v 3)) (!= (ix v 3) cfg-my-id))))))
})
(defun express-checksum (gen v)
    (+ gen (* 3 (ix v 0)) (* 7 (ix v 1)) (* 11 (ix v 2))
       (* 17 (ix v 3)) (* 31 (ix v 4))))
(defun express-bank (slot) {
    (var marker (eeprom-read-i slot))
    (var gen (eeprom-read-i (+ slot 1)))
    (var v (map (fn (i) (eeprom-read-i (+ slot i))) '(2 3 4 5 6)))
    (var check (eeprom-read-i (+ slot 7)))
    (if (and (number? marker) (= marker 0x45584C31)
             (number? gen) (> gen 0) (< gen 16000000) (express-valid v)
             (number? check) (= check (express-checksum gen v)))
        (list slot gen v) nil)
})
(defun express-saved () {
    (var a (express-bank 220)) (var b (express-bank 228))
    (if (and a b) (if (> (ix b 1) (ix a 1)) b a) (if a a b))
})
(defun express-active ()
    (list (if cfg-esc-auto 1 0) cfg-esc-id (if cfg-esc2-en 1 0) cfg-esc2-id cfg-chan))
(defun express-store (slot word) {
    (var stored (eeprom-store-i slot word))
    (var got (eeprom-read-i slot))
    (if (not (and stored (number? got) (= got word)))
        (exit-error 'express-save-failed))
})
(defun express-config-write (v) {
    (if (not (express-valid v)) (exit-error 'express-invalid-settings))
    (var old (express-saved))
    (var slot (if (and old (= (ix old 0) 220)) 228 220))
    (var gen (if old (+ (ix old 1) 1) 1))
    (if (>= gen 16000000) (exit-error 'express-settings-counter-full))
    (express-store slot 0)
    (express-store (+ slot 1) gen)
    (looprange i 0 5 (express-store (+ slot 2 i) (ix v i)))
    (express-store (+ slot 7) (express-checksum gen v))
    (express-store slot 0x45584C31)
    true
})
(defun express-config-save (auto esc second esc2 channel) {
    (var r (trap (express-config-write (list auto esc second esc2 channel))))
    (if (eq (car r) 'exit-ok)
        (print "EXLINK-SAVE:ok") (print "EXLINK-SAVE:failed"))
    (express-status)
})
(defun express-config-load () {
    (var saved (express-saved))
    (if saved {
        (var v (ix saved 2))
        (def cfg-esc-auto (= (ix v 0) 1)) (def cfg-esc-id (to-i (ix v 1)))
        (def cfg-esc2-en (= (ix v 2) 1)) (def cfg-esc2-id (to-i (ix v 3)))
        (def cfg-chan (to-i (ix v 4)))
    })
    (def express-boot-settings (express-active))
})
(defun express-screen-live () (and (> rx-count 0) (rx-live)))
(defun express-controller-live ()
    (or (and x-ever (dash-esc-live)) (and (> sv-frames 0) (sv-live))))
(defun express-radio-channel () {
    (var r (trap (wifi-get-chan)))
    (var channel (ix r 1))
    (if (and (eq (car r) 'exit-ok) (number? channel)
             (>= channel 1) (<= channel 13)) channel 0)
})
(defun express-forget () {
    ; Do not break a live display's control route. Forget while it is off.
    (if (express-screen-live) (print "EXLINK-PAIR:busy") {
        (var r (trap {
            (express-store 122 0) (express-store 123 0)
            (def dash-mac nil) (def dash-nolearn false)
        }))
        (print (if (eq (car r) 'exit-ok) "EXLINK-PAIR:ok" "EXLINK-PAIR:failed"))
    })
    (express-status)
})
(defun express-status () {
    (var saved (express-saved)) (var v (if saved (ix saved 2) express-boot-settings))
    (var pending (not (eq (map to-i v) (map to-i express-boot-settings))))
    (var out "EXLINK:1")
    (loopforeach n v (setq out (str-merge out "," (str-from-n n "%d"))))
    (loopforeach n (list (if (express-controller-live) 1 0)
        (if (express-screen-live) 1 0) (if dash-mac 1 0) cfg-esc-id
        (if pending 1 0) cfg-my-id (express-radio-channel))
        (setq out (str-merge out "," (str-from-n n "%d"))))
    (print out)
})
(defun main () {
    (set-print-prefix "CUEXP-")
    (var own (car (cdr (trap (conf-get 'controller-id)))))
    (if (number? own) (def cfg-my-id (to-i own)))
    (core-load)
    ; This package never starts LED, GPIO, ANT or switch workers. Inherited
    ; optional output settings must not activate CAN IO or walk-assist either.
    (def cfg-io-en false) (def cfg-walk-en false)
    (express-config-load)
    (core-start)
    (print "CU Express Link v1 running")
})
@const-end
(def build-id "express-link-v1")
(def core-role 1) (def core-prio 25) (def core-inputs 0)
(def express-boot-settings '(1 6 0 0 1))
(main)
