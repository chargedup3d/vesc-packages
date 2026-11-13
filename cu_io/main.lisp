(import "version.lisp" 'cu-package-version-data)
(read-eval-program cu-package-version-data)
;! CU IO Link: switches, tail light and AUX strips on the Charged Up CAN hat,
;! and a link to the screen.
; ============================================================================
; cu_io - the CU IO Link
;
; An ESP32-C3 SuperMini on the Charged Up CAN hat, firmware hardware name
; "CU IO Link": a link to the CUP-3.5 (cu_link_core), two switch plugs
; (cu_link_inputs), a TAIL and an AUX LED strip (cu_link_lights), and
; optionally an ANT BMS over Bluetooth (cu_link_ant).
;
;   IO10 TAIL strip   IO4 AUX strip   IO20 SW1   IO21 SW2   IO8 blue LED
; ============================================================================

(import "lib/cu_common/cu_gateway_wire.lisp" 'cu-gateway-wire)
(read-eval-program cu-gateway-wire)
(import "lib/cu_common/cu_gateway_can.lisp" 'cu-gateway-can)
(read-eval-program cu-gateway-can)

(import "lib/cu_common/cu_link_core.lisp" 'cu-link-core)
(import "lib/cu_common/cu_link_inputs.lisp" 'cu-link-inputs)
(import "lib/cu_common/cu_link_lights.lisp" 'cu-link-lights)
(import "lib/cu_common/cu_link_ant.lisp" 'cu-link-ant)
(read-eval-program cu-link-core)
(read-eval-program cu-link-inputs)
(read-eval-program cu-link-lights)
(read-eval-program cu-link-ant)

@const-start

(defun cfg-save () {
        (core-save) (inputs-save) (lights-save) (ant-save)
        (print "saved")
        true
})

; Every setting, so the page shows what is stored rather than its own
; defaults. The order is the settings page's.
(defun cfg-dump () (print (str-merge "LINK:"
        (str-from-n cfg-esc-id "%d") "," (str-from-n (if cfg-esc2-en 1 0) "%d") ","
        (str-from-n cfg-esc2-id "%d") "," (str-from-n cfg-chan "%d") ","
        (str-from-n cfg-hz "%.0f") "," (str-from-n cfg-io-id "%d") ","
        (str-from-n (if cfg-io-en 1 0) "%d") "," (str-from-n cfg-ch-left "%d") ","
        (str-from-n cfg-ch-right "%d") "," (str-from-n cfg-ch-beam "%d") ","
        (str-from-n cfg-ch-horn "%d") "," (str-from-n (if cfg-lt-en 1 0) "%d") ","
        (str-from-n (lt-pin) "%d") "," (str-from-n cfg-lt-count "%d") ","
        (str-from-n cfg-lt-type "%d") "," (str-from-n cfg-brake-a "%.1f") ","
        (str-from-n (if cfg-lt-sweep 1 0) "%d") "," (str-from-n (if cfg-bms-en 1 0) "%d") ","
        (str-from-n (if cfg-ant-en 1 0) "%d") "," (str-from-n (if cfg-setup-en 1 0) "%d") ","
        (str-from-n cfg-soc-src "%d") "," (str-from-n (if cfg-walk-en 1 0) "%d") ","
        (str-from-n cfg-walk-kph "%.0f") "," (str-from-n (* cfg-walk-duty 100.0) "%.0f") ","
        (str-from-n (if cfg-esc-auto 1 0) "%d") "," (str-from-n cfg-ax-count "%d") ","
        (str-from-n cfg-ax-type "%d") "," (str-from-n cfg-ax-role "%d") ",1,"
        (str-from-n cfg-sw1-type "%d") "," (str-from-n cfg-sw1-pol "%d") ","
        (str-from-n cfg-sw1-s "%d") "," (str-from-n cfg-sw1-l "%d") ","
        (str-from-n cfg-sw2-type "%d") "," (str-from-n cfg-sw2-pol "%d") ","
        (str-from-n cfg-sw2-s "%d") "," (str-from-n cfg-sw2-l "%d") ","
        (str-from-n cfg-sw-pair "%d") "," (str-from-n cfg-sw-pm0 "%d") ","
        (str-from-n cfg-sw-pm1 "%d") "," (str-from-n cfg-sw-pm2 "%d"))))

(defun main () {
        (set-print-prefix "CUIO-")
        (core-load)
        (inputs-load)
        (ant-load)
        ; a fresh board lights its TAIL plug: that is what the plug is for
        (if (not (lights-load)) {
                (def cfg-lt-en true) (def cfg-lt-count 8) (def cfg-lt-type 2)
        })
        (def core-app-hook inputs-app)
        (trap (lights-start))
        (trap (inputs-start))
        (if cfg-ant-en (trap (ant-start)))
        (core-start)
        (print (str-merge "cu io running, build " build-id))
})

@const-end

(def build-id "io-1.1.0-rc3")
(def core-role 2) (def core-prio 20)   ; bridges before an IMU board
(def in-pins (list 20 21)) (def in-led 8)
(def lt-fixed-pin 10) (def ax-pin 4) (def lt-idle-rainbow false)

(main)
