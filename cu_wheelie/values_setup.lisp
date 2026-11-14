; Core adapter for shared motor, Hall, ADC, IMU and Values setup.
; Core owns profile arbitration and a temporary zero-watt service guard.
(def clamp base-clamp)
(def core-service-watts nil)
(def core-apply-drive-mode apply-drive-mode)
(def core-proc-sid proc-sid)
(def core-ms-command ms-command) (def core-hc-command hc-command)
; Keep aliases to existing flash closures; do not copy their bodies again.
@const-start
(defun setup-disarmed () (and (= drive-mode 1) (not profile-suspend)))
(defun setup-disarm () { (setq drive-mode 1) (setq cruise-on 0) })
; Default Charged Up CAN IMU address; absent sensors report unavailable.
(defun setup-imu-offset () 0)
(defun core-service-held () (or ms-lock hc-lock))
(defun core-service-enter () (atomic (if (and (not core-service-watts) (not (core-service-held))
    (setup-disarmed) (= (conf-get 'app-to-use) 3)
    (< (abs (get-rpm)) 50) (< (abs (get-current)) 0.2) (= (get-fault) 0)
    (<= (conf-get 'l-current-max-scale) 0.00001)) {
    (setq core-service-watts (conf-get 'l-watt-max))
    ; Reserve the profile writer before publishing the zero-watt hold.
    (conf-set 'l-watt-max 0.0)
})))
(defun core-service-leave () {
    (var released nil)
    (atomic (if (and (not (core-service-held)) core-service-watts) {
        (conf-set 'l-watt-max core-service-watts)
        (setq core-service-watts nil) (setq base-last nil) (setq released t)
    }))
    (if released (apply-drive-mode 1))
})
; Serialize profile selection/write with the setup reservation. A writer
; selected before START cannot finish by overwriting a native worker's limits.
(defun apply-drive-mode (m) {
    (atomic (if (not (or core-service-watts (core-service-held))) (core-apply-drive-mode m)))
    ; Hold helpers have their own atomic latch checks; do not nest them.
    (if ms-lock (ms-hold) (if hc-lock (hc-hold)))
})
(defun ms-command (b) {
    (if (= (bufget-u8 b 2) 1) (core-service-enter))
    (core-ms-command b) (core-service-leave)
})
(defun hc-command (b) {
    (if (or (= (bufget-u8 b 2) 1) (= (bufget-u8 b 2) 2)) (core-service-enter))
    (core-hc-command b) (core-service-leave)
})
(defun proc-sid (id data) {
    (im-rx id data)
    (if (and (= id (+ 0x500 (can-local-id))) (= (buflen data) 8)
             (= (bufget-u8 data 0) 0x57))
        (cond ((= (bufget-u8 data 1) 0x31) (ms-command data))
              ((= (bufget-u8 data 1) 0x30) (hc-command data)))
        (core-proc-sid id data))
})
(defun core-service-guard () {
    (hd-guard) (ms-guard)
    (if ms-lock (ms-hold) (if hc-lock (hc-hold)))
})
@const-end
