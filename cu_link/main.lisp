(import "version.lisp" 'cu-package-version-data)
(read-eval-program cu-package-version-data)
;! CU Express Link: the CUP-3.5 / CAN link for an Express T.
; Existing CU Link firmware; no IO-hat pins or onboard IMU are assumed.
(import "lib/cu_common/cu_gateway_wire.lisp" 'cu-gateway-wire)
(read-eval-program cu-gateway-wire)
(import "lib/cu_common/cu_gateway_can.lisp" 'cu-gateway-can)
(read-eval-program cu-gateway-can)
(import "lib/cu_common/cu_link_core.lisp" 'cu-link-core)
(read-eval-program cu-link-core)
(import "lib/cu_common/cu_link_lights.lisp" 'cu-link-lights)
(read-eval-program cu-link-lights)
(import "lib/cu_common/cu_link_ant.lisp" 'cu-link-ant)
(read-eval-program cu-link-ant)
(import "legacy_settings.lisp" 'legacy-settings)
(read-eval-program legacy-settings)

@const-start
(defun cfg-save () {
    (lights-save) (ant-save) (core-save)
    (print "link saved") true
})
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
        (str-from-n cfg-ax-type "%d") "," (str-from-n cfg-ax-role "%d") ",0")))

(defun main () {
    (set-print-prefix "CULINK-")
    ; Stop before radio/output startup if an old settings copy cannot verify.
    (express-migrate)
    (core-load) (lights-load) (ant-load)
    (trap (lights-start))
    (if cfg-ant-en (trap (ant-start)))
    (core-start)
    (print (str-merge "Express Link running, build " build-id))
})
@const-end
(def build-id "link-1.2.0-rc1")
; IO Link has priority 20; Express T 25; IMU 30. One bridge at a time.
(def core-role 1) (def core-prio 25) (def core-inputs 0)
(def lt-fixed-pin -1) (def ax-pin -1) (def lt-idle-rainbow true)
(main)
