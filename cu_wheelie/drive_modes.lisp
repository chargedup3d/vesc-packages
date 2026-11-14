; CU Core modes, with Wheelie's existing IMU, brake and crash arbitration.
(def wheelie-core-sid core-proc-sid)
(def wheelie-core-editable base-mode-editable)
(def wheelie-core-apply apply-drive-mode)
; Aliases retain the original flash closures without duplicating them.
@const-start
(defun whl-drive-ready () (and base-ready (>= drive-mode 2) (<= drive-mode 4)
    (not core-service-watts) (not ms-lock) (not hc-lock)))
(defun setup-disarmed () (and (= whl-armed 0) (= drive-mode 1) (not profile-suspend)))
(defun setup-disarm () {
    (setq whl-armed 0) (setq whl-out 0.0) (setq whl-rider 0.0)
    (setq drive-mode 1) (setq cruise-on 0)
})
(defun setup-imu-offset () ex-offset)
(defun base-mode-editable () (and (= whl-armed 0) (not core-service-watts)
    (wheelie-core-editable)))
(defun apply-drive-mode (m) {
    ; The shared writer and wheelie-step serialize their output decisions.
    (wheelie-core-apply m)
    (if (< drive-mode 2) (setq whl-armed 0))
})
(defun proc-sid (id data) {
    (cond
        ((= id (+ 0x5A0 ex-offset)) {
            (ex-handle data) (if ctrl-pid (send ctrl-pid 'frame))
        })
        ((= id (+ 0x500 (can-local-id))) (whl-can-handle id data))
        ((= id 201) {
            ; Reverse requires released inputs and a stopped motor. Neutral
            ; remains available immediately, including while assistance is on.
            (if (and (>= (buflen data) 2)
                (or (!= (bufget-u8 data 0) 0)
                    (and (= whl-armed 0) (< (abs (get-rpm)) 50)
                         (< (abs (get-adc-decoded 0)) thr-db)
                         (< (abs (get-adc-decoded 1)) thr-db))))
                {
                    (if (= (bufget-u8 data 0) 1) (setq mode-ts 0))
                    (wheelie-core-sid id data)
                })
        })
        ; Wheelie already owns current while armed. Do not latch ADC cruise
        ; behind it and unexpectedly resume cruise after disarm or IMU loss.
        ((= id 250) nil)
        (t { (im-rx id data) (wheelie-core-sid id data) })
    )
})
(defun cruise-step () { (setq cruise-on 0) (app-adc-override 3 0) })
(defun display-event (ev) nil)
(defun display-stop () nil)
(defun base-status () (print (list "base" whl-version drive-mode light-on 0
    (if (> display-ts 0) (secs-since display-ts) -1.0)
    (if (> data-link-ts 0) (secs-since data-link-ts) -1.0)
    (if base-ready 1 0) (if base-kid-on 1 0) base-kid-mph base-kid-w)))
(defun whl-select-mode (mode) {
    (if (and (>= mode 0) (<= mode 4) (= whl-armed 0)
        (not ms-lock) (not hc-lock) (< (abs (get-rpm)) 50)
        (< (abs (get-current)) 0.2) (< (abs (get-adc-decoded 0)) thr-db)
        (< (abs (get-adc-decoded 1)) thr-db)) {
        (var b (bufcreate 8)) (bufset-u8 b 0 mode) (bufset-u8 b 1 light-on)
        (proc-sid 201 b) (free b)
    })
})
; 3Shul SUB units are 100 ms, independent of the faster BLE live stream.
(defun whl-can-telem-step () (if (and (> whl-can-telem-rate 0)
    (>= (secs-since whl-can-telem-t) (* 0.1 whl-can-telem-rate))) {
    (setq whl-can-telem-t (systime)) (whl-can-send-telem) (whl-can-send-attitude)
}))
@const-end
