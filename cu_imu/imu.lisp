(import "version.lisp" 'cu-package-version-data)
(read-eval-program cu-package-version-data)
;! CU IMU: pitch and roll for CU Wheelie (CAN 0x5A0 + offset),
;! the tail light, and a Charged Up link to the screen.
; cu_imu - CU IMU over CAN
; --------------------------------------------------------------------------
; Reads a 6-axis IMU over I2C at 200 Hz, fuses pitch and roll with a
; complementary filter and broadcasts one 8-byte standard CAN frame at 200 Hz
; on ID 0x5A0 + offset for the Wheelie Assist package on the motor controller.
;
; Frame (little-endian):
;   0-1 pitch      int16  0.01 deg,  front wheel up positive
;   2-3 roll       int16  0.01 deg,  lean right positive
;   4-5 pitch_rate int16  0.1 deg/s, nose rising positive
;   6   seq        uint8  +1 every frame
;   7   flags      uint8  bit0 cal_valid, bit1 imu_ok, bit2 accel_gated,
;                         bit3 SD card present (can log), bits 5-7 protocol version (1)
; --------------------------------------------------------------------------

; ---- Charged Up link ----
; cu_link_core: pairs with the CUP-3.5 and makes this board a link - the
; controller's data to the screen, its modes, CU Wheelie. Loaded before
; this file's own constant block, which it must not end early.
(import "lib/cu_common/cu_gateway_wire.lisp" 'cu-gateway-wire)
(read-eval-program cu-gateway-wire)
(import "lib/cu_common/cu_gateway_can.lisp" 'cu-gateway-can)
(read-eval-program cu-gateway-can)

(import "lib/cu_common/cu_link_core.lisp" 'cu-link-core)
(read-eval-program cu-link-core)

(import "screen_setup.lisp" 'code-screen-setup)
(read-eval-program code-screen-setup)
(import "drv_lsm6ds3trc.lisp" 'drv-lsm6ds3trc)
(read-eval-program drv-lsm6ds3trc)

@const-start

(def cu-version "0.6.7-fresh1")
(def build-id "imu-0.6.7-fresh1")   ; what the flasher checks it is running


; ---- Settings (persisted) ----
; Express Open rev C hardware (fixed by the PCB, not settings):
;   on-board LSM6DS3TR-C at 0x6A, I2C SDA GPIO7 / SCL GPIO6, 400 kHz, tail light data GPIO5
(def imu-type  2)      ; kept in EEPROM/messages for layout compatibility only
(def sda-pin   7)
(def scl-pin   6)
(def i2c-rate  1)
(def fwd-axis  0)      ; sensor axis pointing forward: 0 +X 1 -X 2 +Y 3 -Y 4 +Z 5 -Z
(def up-axis   4)      ; sensor axis pointing up, same coding
(def can-off   0)      ; CAN ID = 0x5A0 + can-off (0..15)
(def tx-en     1)
(def cal-valid 0)
(def alpha     0.98)   ; complementary filter coefficient at 200 Hz
(def gate-g    0.3)    ; skip accel correction when | |a| - 1 g | > gate-g
(def pitch-off 0.0)
(def roll-off  0.0)
(def bias-x    0.0)    ; gyro bias, sensor frame, deg/s
(def bias-y    0.0)
(def bias-z    0.0)

; ---- Tail light settings (persisted, slots 17-24) ----
(def tl-en     1)       ; 1 = drive the tail light strip
(def tl-pin    5)       ; data GPIO (fixed by the PCB)
(def tl-count  15)
(def tl-type   2)       ; rgbled type: 0 GRB, 1 RGB, 2 GRBW (SK6812), 3-4 other RGBW orders
(def tl-run    0.15)    ; running light brightness
(def tl-brk    0.4)     ; brake brightness (the strip shares the VESC's 5 V, keep it modest)
(def tl-party  0)       ; 1 = RGB party mode instead of the running light
(def tl-pbri   0.25)    ; party brightness
(def tl-pmode  0)       ; party style: 0 rainbow flow, 1 colour cycle, 2 breathing,
                        ; 3 scanner, 4 comet, 5 police, 6 sparkle
(def tl-pspeed 1.0)     ; party animation speed, 0.25..2.5
(def tl-tstart 80.0)    ; start dimming the tail light above this chip temperature (degC)

; ---- EEPROM layout ----
;   0 magic (i)     5 fwd-axis (i)    10 alpha (f)      15 bias-y (f)
;   1 imu-type (i)  6 up-axis (i)     11 gate-g (f)     16 bias-z (f)
;   2 sda-pin (i)   7 can-off (i)     12 pitch-off (f)
;   3 scl-pin (i)   8 tx-en (i)       13 roll-off (f)
;   4 i2c-rate (i)  9 cal-valid (i)   14 bias-x (f)
(def cu-magic 1129662721)   ; 0x43554901 = "CUI" v1

; Only what changed is written. Each write is a flash commit that stops
; every thread while it runs, and all 28 of them, twice per save from the
; page, held up the pitch feed past CU Wheelie's stale limit.
(defun ee-i (k v) (if (not (let ((o (eeprom-read-i k))) (and o (= o v)))) (eeprom-store-i k v)))
(defun ee-f (k v) (if (not (let ((o (eeprom-read-f k))) (and o (= o v)))) (eeprom-store-f k v)))

(defun save-settings ()
    (progn
        ; Invalidate before changing a mount; commit calibration validity last.
        (if (= cal-valid 0) (ee-i 9 0))
        (ee-i 1 imu-type)
        (ee-i 2 sda-pin)
        (ee-i 3 scl-pin)
        (ee-i 4 i2c-rate)
        (ee-i 5 fwd-axis)
        (ee-i 6 up-axis)
        (ee-i 7 can-off)
        (ee-i 8 tx-en)
        (ee-f 10 alpha)
        (ee-f 11 gate-g)
        (ee-f 12 pitch-off)
        (ee-f 13 roll-off)
        (ee-f 14 bias-x)
        (ee-f 15 bias-y)
        (ee-f 16 bias-z)
        (ee-i 17 tl-en)
        (ee-i 18 tl-pin)
        (ee-i 19 tl-count)
        (ee-i 20 tl-type)
        (ee-f 21 tl-run)
        (ee-f 22 tl-brk)
        (ee-i 23 tl-party)
        (ee-f 24 tl-pbri)
        (ee-i 25 tl-pmode)
        (ee-f 26 tl-pspeed)
        (ee-f 27 tl-tstart)
        (ee-i 9 cal-valid)
        (ee-i 0 cu-magic)))   ; magic written last = commit

(defun load-settings ()
    (progn
        (setvar 'imu-type  (eeprom-read-i 1))
        (setvar 'sda-pin   (eeprom-read-i 2))
        (setvar 'scl-pin   (eeprom-read-i 3))
        (setvar 'i2c-rate  (eeprom-read-i 4))
        (setvar 'fwd-axis  (eeprom-read-i 5))
        (setvar 'up-axis   (eeprom-read-i 6))
        (setvar 'can-off   (eeprom-read-i 7))
        (setvar 'tx-en     (eeprom-read-i 8))
        (setvar 'cal-valid (eeprom-read-i 9))
        (setvar 'alpha     (eeprom-read-f 10))
        (setvar 'gate-g    (eeprom-read-f 11))
        (setvar 'pitch-off (eeprom-read-f 12))
        (setvar 'roll-off  (eeprom-read-f 13))
        (setvar 'bias-x    (eeprom-read-f 14))
        (setvar 'bias-y    (eeprom-read-f 15))
        (setvar 'bias-z    (eeprom-read-f 16))
        ; slots 17+ came later: range-checked, defaults if never written
        (setvar 'tl-en    (ld-i 17 0 1 tl-en))
        (setvar 'tl-pin   (ld-i 18 0 21 tl-pin))
        (setvar 'tl-count (ld-i 19 1 120 tl-count))
        (setvar 'tl-type  (ld-i 20 0 4 tl-type))
        (setvar 'tl-run   (ld-f 21 0.0 1.0 tl-run))
        (setvar 'tl-brk   (ld-f 22 0.0 1.0 tl-brk))
        (setvar 'tl-party (ld-i 23 0 1 tl-party))
        (setvar 'tl-pbri  (ld-f 24 0.0 1.0 tl-pbri))
        (setvar 'tl-pmode (ld-i 25 0 6 tl-pmode))
        (setvar 'tl-pspeed (ld-f 26 0.25 2.5 tl-pspeed))
        (setvar 'tl-tstart (ld-f 27 50.0 100.0 tl-tstart))))

(defun ld-f (slot lo hi dflt)
    (let ((v (eeprom-read-f slot))) (if (and v (>= v lo) (<= v hi)) v dflt)))
(defun ld-i (slot lo hi dflt)
    (let ((v (eeprom-read-i slot))) (if (and v (>= v lo) (<= v hi)) v dflt)))

; eeprom-read-i returns nil for a never-written slot
(if (let ((m (eeprom-read-i 0))) (and m (= m cu-magic)))
    (load-settings)
    (save-settings))
(defun fix-hw ()
    (progn (setvar 'imu-type 2) (setvar 'sda-pin 7) (setvar 'scl-pin 6)
           (setvar 'i2c-rate 1) (setvar 'tl-pin 5)))
(fix-hw)

(defun clamp (x lo hi) (if (< x lo) lo (if (> x hi) hi x)))

; ---- Driver dispatch ----
(defun drv-whoami () (trc-whoami))
(defun drv-init ()   (trc-init))
(defun drv-read ()   (trc-read))

; ---- Mount orientation ----
; Bike frame: f forward, l left, u up (f x l = u). Each is a signed unit
; vector in sensor coordinates; l = u x f.
(defun axis-vec (code)
    (cond
        ((= code 0) (list 1 0 0)) ((= code 1) (list -1 0 0))
        ((= code 2) (list 0 1 0)) ((= code 3) (list 0 -1 0))
        ((= code 4) (list 0 0 1)) (t (list 0 0 -1))))

(defun cross (a b)
    (list (- (* (ix a 1) (ix b 2)) (* (ix a 2) (ix b 1)))
          (- (* (ix a 2) (ix b 0)) (* (ix a 0) (ix b 2)))
          (- (* (ix a 0) (ix b 1)) (* (ix a 1) (ix b 0)))))

; each bike axis as (index . sign) into the driver list, accel at index+3
(defun vec-sel (v)
    (cond ((not (= (ix v 0) 0)) (cons 0 (ix v 0)))
          ((not (= (ix v 1) 0)) (cons 1 (ix v 1)))
          (t (cons 2 (ix v 2)))))

(def f-i 0) (def f-s 1.0)
(def l-i 1) (def l-s 1.0)
(def u-i 2) (def u-s 1.0)
(def mount-ok 1)

(defun apply-mount ()
    (if (= (/ fwd-axis 2) (/ up-axis 2))
        (setvar 'mount-ok 0)   ; forward and up on the same axis
        (let ((fv (axis-vec fwd-axis)) (uv (axis-vec up-axis)))
            (let ((fs (vec-sel fv)) (us (vec-sel uv)) (ls (vec-sel (cross uv fv))))
                (progn
                    (setvar 'f-i (car fs)) (setvar 'f-s (to-float (cdr fs)))
                    (setvar 'l-i (car ls)) (setvar 'l-s (to-float (cdr ls)))
                    (setvar 'u-i (car us)) (setvar 'u-s (to-float (cdr us)))
                    (setvar 'mount-ok 1))))))

; ---- Runtime state ----
(def imu-ok 0)          ; chip found, configured and reads succeeding
(def chip-ok 0)         ; WHO_AM_I matched
(def i2c-errs 0)
(def consec-errs 0)
(def sample-seen 0)
(def sample-count 0)
(def sample-window 0)
(def sample-hz 0.0)
(def sample-not-ready 0)
(def sample-max-gap-ms 0.0)
(def sample-gap-count 0)
(def imu-restarts 0)
(def tx-cnt 0)
(def seq 0)
(def gated 0)
(def fused-init 0)
(def pitch 0.0)
(def roll 0.0)
(def prate 0.0)
(def af 0.0)            ; bike-frame accel (g), for the UI
(def al 0.0)
(def au 0.0)
(def loop-hz 0.0)
(def period 0.005)      ; 200 Hz, drops to 0.01 if 200 Hz cannot be held
(def tx-div 1)          ; transmit every sample (200 Hz, ~4% of a 500k bus)
(def has-sd 0)          ; 1 if an SD card is mounted (flag bit 3: this Express can log)
(def reinit-req 1)
(def ui-msg "")
(def msg-id 0)
(defun set-msg (s) (progn (setvar 'ui-msg s) (setvar 'msg-id (+ msg-id 1))))

; boot gyro bias refresh: 1 s still after (re)init
(def bb-state 0)        ; 0 collecting, 1 done
(def bb-n 0)
(def bb-sx 0.0) (def bb-sy 0.0) (def bb-sz 0.0)

; Zero Level: 1 s still, level on the stand
(def cal-state 0)       ; 0 idle, 1 collecting
(def cal-n 0)
(def cs-f 0.0) (def cs-l 0.0) (def cs-u 0.0)
(def cs-gx 0.0) (def cs-gy 0.0) (def cs-gz 0.0)
(def cal-moved 0)

(defun imu-start ()
    (progn
        (setvar 'imu-ok 0)
        (setvar 'sample-seen 0)
        (setvar 'imu-restarts (+ imu-restarts 1))
        (i2c-start (if (= i2c-rate 0) 'rate-100k 'rate-400k) sda-pin scl-pin)
        (setvar 'chip-ok (if (drv-whoami) 1 0))
        (setvar 'imu-ok (if (and (= chip-ok 1) (drv-init)) 1 0))
        (setvar 'consec-errs 0)
        (setvar 'fused-init 0)
        (setvar 'bb-state 0) (setvar 'bb-n 0)
        (setvar 'bb-sx 0.0) (setvar 'bb-sy 0.0) (setvar 'bb-sz 0.0)
        (set-msg (if (= imu-ok 1) "IMU started"
                            (if (= chip-ok 1) "IMU found but config failed" "IMU not found")))))

; ---- Stillness: judged by how much the readings VARY over the 1 s window,
; not by their distance from zero. A gyro's fixed zero-rate offset (several
; deg/s on an LSM6DS3TR-C) is exactly what these windows measure, so it must
; not count as movement. Still = each gyro axis spans < 2 deg/s, the accel
; magnitude spans < 0.05 g and averages within 0.15 g of 1 g.
; Two independent windows: boot bias (bb-) and Zero Level (cs-).
(def bb-min (list 0 0 0)) (def bb-max (list 0 0 0)) (def bb-amin 0.0) (def bb-amax 0.0) (def bb-as 0.0)
(def cs-min (list 0 0 0)) (def cs-max (list 0 0 0)) (def cs-amin 0.0) (def cs-amax 0.0) (def cs-as 0.0)

(defun min (a b) (if (< a b) a b))
(defun max (a b) (if (> a b) a b))
(defun g3min (a b) (list (min (ix a 0) (ix b 0)) (min (ix a 1) (ix b 1)) (min (ix a 2) (ix b 2))))
(defun g3max (a b) (list (max (ix a 0) (ix b 0)) (max (ix a 1) (ix b 1)) (max (ix a 2) (ix b 2))))
(defun spread-ok (mn mx amin amax as n)
    (and (< (- (ix mx 0) (ix mn 0)) 2.0) (< (- (ix mx 1) (ix mn 1)) 2.0) (< (- (ix mx 2) (ix mn 2)) 2.0)
         (< (- amax amin) 0.05) (< (abs (- (/ as n) 1.0)) 0.15)))

(defun boot-bias (gx gy gz am)
    ; gx gy gz raw (no bias removed), am = accel magnitude
    (if (= bb-state 0)
        (let ((g (list gx gy gz)))
            (progn
                (if (= bb-n 0)
                    (progn (setvar 'bb-min g) (setvar 'bb-max g) (setvar 'bb-amin am) (setvar 'bb-amax am) (setvar 'bb-as 0.0))
                    (progn (setvar 'bb-min (g3min bb-min g)) (setvar 'bb-max (g3max bb-max g))
                           (setvar 'bb-amin (min bb-amin am)) (setvar 'bb-amax (max bb-amax am))))
                (setvar 'bb-as (+ bb-as am))
                (setvar 'bb-sx (+ bb-sx gx))
                (setvar 'bb-sy (+ bb-sy gy))
                (setvar 'bb-sz (+ bb-sz gz))
                (setvar 'bb-n (+ bb-n 1))
                (if (>= bb-n (to-i (/ 1.0 period)))
                    (progn
                        ; still for the whole second: that average is the gyro offset;
                        ; otherwise keep the stored (Zero Level) offset
                        (if (spread-ok bb-min bb-max bb-amin bb-amax bb-as bb-n)
                            (progn
                                (setvar 'bias-x (/ bb-sx bb-n))
                                (setvar 'bias-y (/ bb-sy bb-n))
                                (setvar 'bias-z (/ bb-sz bb-n))))
                        (setvar 'bb-state 1)))))))

(defun cal-start ()
    (progn
        (setvar 'cal-n 0) (setvar 'cal-moved 0)
        (setvar 'cs-f 0.0) (setvar 'cs-l 0.0) (setvar 'cs-u 0.0)
        (setvar 'cs-gx 0.0) (setvar 'cs-gy 0.0) (setvar 'cs-gz 0.0)
        (set-msg "Zero Level: hold still...")
        (setvar 'cal-state 1)))

(defun cal-step (gx gy gz)
    ; gx gy gz raw, af al au already updated
    (let ((g (list gx gy gz)) (am (sqrt (+ (* af af) (* al al) (* au au)))))
        (progn
            (if (= cal-n 0)
                (progn (setvar 'cs-min g) (setvar 'cs-max g) (setvar 'cs-amin am) (setvar 'cs-amax am) (setvar 'cs-as 0.0))
                (progn (setvar 'cs-min (g3min cs-min g)) (setvar 'cs-max (g3max cs-max g))
                       (setvar 'cs-amin (min cs-amin am)) (setvar 'cs-amax (max cs-amax am))))
            (setvar 'cs-as (+ cs-as am))
            (setvar 'cs-f (+ cs-f af)) (setvar 'cs-l (+ cs-l al)) (setvar 'cs-u (+ cs-u au))
            (setvar 'cs-gx (+ cs-gx gx)) (setvar 'cs-gy (+ cs-gy gy)) (setvar 'cs-gz (+ cs-gz gz))
            (setvar 'cal-n (+ cal-n 1))
            (if (>= cal-n (to-i (/ 1.0 period)))
                (progn
                    (setvar 'cal-state 0)
                    (if is-owner { (def is-owner nil) (def is-status 4) })
                    (if (not (and (spread-ok cs-min cs-max cs-amin cs-amax cs-as cal-n)
                        (< (abs (- (/ cs-gx cal-n) bias-x)) 2.0) (< (abs (- (/ cs-gy cal-n) bias-y)) 2.0) (< (abs (- (/ cs-gz cal-n) bias-z)) 2.0)))
                        (set-msg (if (>= (abs (- (/ cs-as cal-n) 1.0)) 0.15)
                                     "Zero Level failed: accel isn't reading 1 g, check the IMU"
                                     "Zero Level failed: board moved, try again"))
                        (let ((f (/ cs-f cal-n)) (l (/ cs-l cal-n)) (u (/ cs-u cal-n)))
                            (progn
                                (ee-i 9 0) ; power loss during offset writes cannot leave a valid partial calibration
                                (setvar 'pitch-off (rad2deg (atan2 f (sqrt (+ (* l l) (* u u))))))
                                (setvar 'roll-off (rad2deg (atan2 l u)))
                                (setvar 'bias-x (/ cs-gx cal-n))
                                (setvar 'bias-y (/ cs-gy cal-n))
                                (setvar 'bias-z (/ cs-gz cal-n))
                                (setvar 'cal-valid 1)
                                (save-settings)
                                (setvar 'fused-init 0)
                                (if (= is-status 4) (def is-status (if (is-stored) 3 6)))
                                (set-msg "Zero Level saved")))))))))

; bias-corrected gyro component i (0 x, 1 y, 2 z)
(defun g-sel (d i)
    (- (ix d i) (cond ((= i 0) bias-x) ((= i 1) bias-y) (t bias-z))))

(defun fuse (d dt)
    (let ((rgx (ix d 0)) (rgy (ix d 1)) (rgz (ix d 2))
          (ax (ix d 3)) (ay (ix d 4)) (az (ix d 5)))
        (progn
            (boot-bias rgx rgy rgz (sqrt (+ (* ax ax) (* ay ay) (* az az))))
            (setvar 'af (* f-s (ix d (+ f-i 3))))
            (setvar 'al (* l-s (ix d (+ l-i 3))))
            (setvar 'au (* u-s (ix d (+ u-i 3))))
            (if is-owner (is-cal-guard))
            (if (= cal-state 1) (cal-step rgx rgy rgz))
            ; nose up = rotation about the right axis = -left
            (setvar 'prate (- (* l-s (g-sel d l-i))))
            (var rrate (* f-s (g-sel d f-i)))
            (var p-acc (- (rad2deg (atan2 af (sqrt (+ (* al al) (* au au))))) pitch-off))
            (var r-acc (- (rad2deg (atan2 al au)) roll-off))
            (setvar 'gated (if (> (abs (- (sqrt (+ (* ax ax) (* ay ay) (* az az))) 1.0)) gate-g) 1 0))
            (if (= fused-init 0)
                (progn
                    (setvar 'pitch p-acc)
                    (setvar 'roll r-acc)
                    (setvar 'fused-init 1))
                (progn
                    (setvar 'pitch (+ pitch (* prate dt)))
                    (setvar 'roll (+ roll (* rrate dt)))
                    (if (= gated 0)
                        (let ((a (/ tau (+ tau dt))))
                            (progn
                                (setvar 'pitch (+ (* a pitch) (* (- 1.0 a) p-acc)))
                                (setvar 'roll (+ (* a roll) (* (- 1.0 a) r-acc)))))))))))

; alpha is specified at 200 Hz; convert to a time constant so the filter
; behaves the same if the loop rate changes. 0.98 -> tau = 0.245 s
(def tau 0.245)
(defun update-tau ()
    (let ((a (clamp alpha 0.5 0.999)))
        (setvar 'tau (/ (* 0.005 a) (- 1.0 a)))))

; ---- CAN TX ----
(def txbuf nil)   ; allocated at boot, outside the const block

(defun put-i16 (i v)
    (bufset-i16 txbuf i (to-i (clamp v -32768.0 32767.0)) 'little-endian))

(defun frame-flags ()
    (bitwise-or (bitwise-or (if (= cal-valid 1) 1 0)
                            (if (and (= imu-ok 1) (= fused-init 1) (= mount-ok 1)
                                     (= sample-seen 1) (< (secs-since t-last) 0.05)) 2 0))
                (bitwise-or (bitwise-or (if (= gated 1) 4 0) (if (= has-sd 1) 8 0)) 0x20)))

(defun can-tx ()
    (progn
        (put-i16 0 (* pitch 100.0))
        (put-i16 2 (* roll 100.0))
        (put-i16 4 (* prate 10.0))
        (bufset-u8 txbuf 6 seq)
        (bufset-u8 txbuf 7 (frame-flags))
        (can-send-sid (+ 0x5A0 can-off) txbuf)
        (setvar 'seq (bitwise-and (+ seq 1) 0xFF))
        (setvar 'tx-cnt (+ tx-cnt 1))))

; ---- Main loop ----
(def t-last (systime))
(def rate-t (systime))
(def rate-n 0)
(def slow-cnt 0)
(def fast-cnt 0)
(def tx-cnt-div 0)
(def work-ms 0.0)      ; longest loop pass in the last 1 s window
(def work-max 0.0)
(def work-sum 0.0)
(def work-avg 0.0)

(defun main-loop ()
    (loopwhile t
        (progn
            (var t0 (systime))
            (ui-cal-guard)
            (if (= reinit-req 1)
                (progn (setvar 'reinit-req 0) (imu-start) (setvar 't-last (systime))))
            (var d (if (= imu-ok 1) (drv-read) nil))
            ; Only a successful new conversion advances the fusion clock and
            ; CAN sequence. Failed/not-ready reads must not refresh receiver age.
            (if (and d (not (eq d 'not-ready)))
                (progn
                    (var elapsed (atomic {
                        (var age (secs-since t-last))
                        (setvar 't-last (systime))
                        age
                    }))
                    (if (= sample-seen 1) {
                        (setvar 'sample-max-gap-ms (max sample-max-gap-ms (* elapsed 1000.0)))
                        ; A large unobserved interval cannot be reconstructed
                        ; from one gyro reading. Re-seed rather than integrate it.
                        (if (>= elapsed 0.05) {
                            (setvar 'sample-gap-count (+ sample-gap-count 1))
                            (setvar 'fused-init 0)
                            (setvar 'bb-n 0)
                            (setvar 'bb-sx 0.0) (setvar 'bb-sy 0.0) (setvar 'bb-sz 0.0)
                            (if (= cal-state 1) (cal-start))
                        })
                    })
                    (setvar 'sample-seen 1)
                    (setvar 'consec-errs 0)
                    (fuse d (clamp elapsed 0.001 0.05))
                    (setvar 'sample-count (+ sample-count 1))
                    (setvar 'sample-window (+ sample-window 1))
                    (setvar 'tx-cnt-div (+ tx-cnt-div 1))
                    (if (>= tx-cnt-div tx-div)
                        (progn (setvar 'tx-cnt-div 0) (if (= tx-en 1) (can-tx)))))
                (if (= imu-ok 1) {
                    (if (eq d 'not-ready)
                        (setvar 'sample-not-ready (+ sample-not-ready 1))
                        {
                            (setvar 'i2c-errs (+ i2c-errs 1))
                            (setvar 'consec-errs (+ consec-errs 1))
                        })
                    ; Includes a responsive chip whose conversions stopped.
                    (if (or (>= consec-errs 20) (>= (secs-since t-last) 0.1))
                        (progn (setvar 'imu-ok 0) (setvar 'reinit-req 1)))
                }
                    ; IMU absent: retry once a second.
                    (if (> (secs-since rate-t) 0.9) (setvar 'reinit-req 1))))
            ; achieved rate, over 1 s windows
            (setvar 'rate-n (+ rate-n 1))
            (if (>= (secs-since rate-t) 1.0)
                (progn
                    (setvar 'loop-hz (/ rate-n (secs-since rate-t)))
                    (setvar 'sample-hz (/ sample-window (secs-since rate-t)))
                    (setvar 'sample-window 0)
                    (setvar 'work-ms (* work-max 1000.0))
                    (setvar 'work-avg (/ (* work-sum 1000.0) (if (> rate-n 0) rate-n 1)))
                    (setvar 'rate-n 0)
                    (setvar 'work-sum 0.0)
                    (setvar 'work-max 0.0)
                    (setvar 'rate-t (systime))
                    ; 3 slow seconds in a row at 200 Hz: fall back to 100 Hz. Normal
                    ; is ~180 Hz with a CAN frame every sample, so 150 leaves margin;
                    ; a blocked (un-ACKed) bus drops it to ~100 Hz.
                    (if (and (= period 0.005) (< loop-hz 150.0))
                        (setvar 'slow-cnt (+ slow-cnt 1))
                        (setvar 'slow-cnt 0))
                    (if (>= slow-cnt 3)
                        (progn
                            (setvar 'period 0.01) (setvar 'slow-cnt 0)
                            (set-msg "200 Hz not held, running at 100 Hz")))
                    ; At 100 Hz with room to spare for 5 s (e.g. CAN TX no longer
                    ; blocking on an un-ACKed bus, ~8 ms/pass): try 200 Hz again.
                    ; A healthy pass is ~2.6-3.3 ms with the tail light running.
                    (if (and (= period 0.01) (< work-avg 4.0))
                        (setvar 'fast-cnt (+ fast-cnt 1))
                        (setvar 'fast-cnt 0))
                    (if (>= fast-cnt 5)
                        (progn
                            (setvar 'period 0.005) (setvar 'fast-cnt 0)
                            (set-msg "Running at 200 Hz")))))
            (var el (secs-since t0))
            (if (> el work-max) (setvar 'work-max el))
            (setvar 'work-sum (+ work-sum el))
            (if (< el period) (sleep (- period el))))))

; Read-only diagnostics, counters since script start. Existing wire format stays compatible.
(defun imu-diagnostics () (list sample-count sample-hz sample-not-ready i2c-errs
    sample-max-gap-ms sample-gap-count imu-restarts
    (if (= sample-seen 1) (* (secs-since t-last) 1000.0) -1.0)))

; ---- VESC Tool comm (custom app data) ----
; QML -> device (binary, big-endian):
;   [u8 1]                                       request config
;   [u8 2][u8 -][u8 -][u8 -][u8 -][u8 fwd][u8 up]     (bytes 1-4 unused: fixed hardware)
;         [f32 alpha][u8 can-off][u8 tx-en][f32 gate]   apply + save (17 bytes)
;         [u8 tl-en][u8 -][u8 tl-count][u8 tl-type][f32 tl-run][f32 tl-brk][f32 tl-pbri] (33 bytes)
;         [u8 tl-pmode][u8 tl-pspeed x100]                                    (35 bytes)
;         [u8 tl-tstart degC]                                                  (36 bytes)
;   [u8 6][u8 on]                                party mode on/off (saved)
;   [u8 7][u8 style]                             party style (saved)
;   [u8 8][u8 kind][u8 tenths]                   preview: 1 brake, 2 hazard, 0 stop, for tenths/10 s
;   [u8 3]                                       Zero Level
;   [u8 4]                                       re-init IMU
;   [u8 5]                                       keepalive (telemetry runs for 3 s after any command)
; device -> QML (strings):
;   "xconf type sda scl rate fwd up alpha canoff txen gate calvalid poff roff tlen tlpin tlcount tltype tlrun tlbrk tlparty tlpbri tlpmode tlpspeed tltstart"
;   "xrt pitch roll prate hz errs tx flags chip f l u gated cal-busy work-ms"
;   "xv pitch roll prate"                         25 Hz, live view
;   "xmsg <text>"

(defun send-conf ()
    (send-data (str-merge "xconf "
        (str-from-n imu-type "%d ") (str-from-n sda-pin "%d ") (str-from-n scl-pin "%d ")
        (str-from-n i2c-rate "%d ") (str-from-n fwd-axis "%d ") (str-from-n up-axis "%d ")
        (str-from-n alpha "%.4f ") (str-from-n can-off "%d ") (str-from-n tx-en "%d ")
        (str-from-n gate-g "%.3f ") (str-from-n cal-valid "%d ")
        (str-from-n pitch-off "%.2f ") (str-from-n roll-off "%.2f ")
        (str-from-n tl-en "%d ") (str-from-n tl-pin "%d ") (str-from-n tl-count "%d ")
        (str-from-n tl-type "%d ") (str-from-n tl-run "%.2f ") (str-from-n tl-brk "%.2f ")
        (str-from-n tl-party "%d ") (str-from-n tl-pbri "%.2f ")
        (str-from-n tl-pmode "%d ") (str-from-n tl-pspeed "%.2f ")
        (str-from-n tl-tstart "%.0f"))))

(defun apply-set (data)
    (let ((old-fwd fwd-axis) (old-up up-axis))
        (progn
            (setvar 'fwd-axis (clamp (bufget-u8 data 5) 0 5))
            (setvar 'up-axis  (clamp (bufget-u8 data 6) 0 5))
            (setvar 'alpha    (clamp (bufget-f32 data 7) 0.5 0.999))
            (setvar 'can-off  (clamp (bufget-u8 data 11) 0 15))
            (setvar 'tx-en    (if (= (bufget-u8 data 12) 0) 0 1))
            (setvar 'gate-g   (clamp (bufget-f32 data 13) 0.05 2.0))
            (update-tau)
            (apply-mount)
            ; new mount orientation invalidates the level offsets
            (if (or (not (= old-fwd fwd-axis)) (not (= old-up up-axis)))
                (progn (setvar 'cal-valid 0) (setvar 'pitch-off 0.0) (setvar 'roll-off 0.0)
                       (setvar 'fused-init 0)))
            (if (>= (buflen data) 33)
                (progn
                    (var old-count tl-count)
                    (var old-type tl-type)
                    (setvar 'tl-en    (if (= (bufget-u8 data 17) 0) 0 1))
                    (setvar 'tl-count (clamp (bufget-u8 data 19) 1 120))
                    (setvar 'tl-type  (clamp (bufget-u8 data 20) 0 4))
                    (setvar 'tl-run   (clamp (bufget-f32 data 21) 0.0 1.0))
                    (setvar 'tl-brk   (clamp (bufget-f32 data 25) 0.0 1.0))
                    (setvar 'tl-pbri  (clamp (bufget-f32 data 29) 0.0 1.0))
                    (if (>= (buflen data) 35)
                        (progn
                            (setvar 'tl-pmode  (clamp (bufget-u8 data 33) 0 6))
                            (setvar 'tl-pspeed (clamp (/ (bufget-u8 data 34) 100.0) 0.25 2.5))))
                    (if (>= (buflen data) 36)
                        (setvar 'tl-tstart (clamp (to-float (bufget-u8 data 35)) 50.0 100.0)))
                    ; only a new strip layout needs the driver restarted
                    (if (or (not (= old-count tl-count)) (not (= old-type tl-type)))
                        (setvar 'tl-reinit 1))))
            (save-settings)
            (set-msg (if (= mount-ok 1) "Settings saved"
                                "Settings saved - forward and up must be different axes"))
            (send-conf))))

(def ui-seen 0)         ; 1 while a page has talked to us in the last 3 s
(def ui-time (systime))

; Direct Express setup uses the existing controller broadcasts; no extra
; controller requests. 0 ready, 1 status unknown, 2 armed, 3 moving, 4 busy.
(def ui-cal-owner nil)
(defun ui-motion-state ()
    (cond
        ((not (or (and (> sv-last 0) (sv-live))
                  (and (> x-last 0) (dash-esc-live)))) 1)
        ((>= (abs d-speed) 0.5) 3)
        ((and (>= whl-id 0) (or (!= whl-id cfg-esc-id)
              (<= whl-t 0) (not (whl-live)))) 1)
        ((and (>= whl-id 0) (!= (bitwise-and (bufget-u8 whl-tel 6) 1) 0)) 2)
        (t 0)))
(defun ui-setup-state () (if (!= cal-state 0) 4 (ui-motion-state)))
(defun ui-cal-guard () (if ui-cal-owner
    (if (= cal-state 0) (def ui-cal-owner nil)
        (if (!= (ui-motion-state) 0) {
            (setvar 'cal-state 0) (def ui-cal-owner nil)
            (set-msg "Zero Level cancelled: controller moving, armed or unavailable")
        }))))
(defun ui-imu-change (data)
    (or (!= (bufget-u8 data 5) fwd-axis) (!= (bufget-u8 data 6) up-axis)
        (> (abs (- (bufget-f32 data 7) alpha)) 0.00001)
        (!= (bufget-u8 data 11) can-off) (!= (bufget-u8 data 12) tx-en)
        (> (abs (- (bufget-f32 data 13) gate-g)) 0.00001)))

(defun handle-rx (data)
    (if (>= (buflen data) 1)
        (let ((cmd (bufget-u8 data 0)))
            (progn
            (setvar 'ui-seen 1)
            (setvar 'ui-time (systime))
            (cond
                ((= cmd 1) (send-conf))
                ((and (= cmd 2) (>= (buflen data) 17))
                    (if (and (ui-imu-change data) (!= (ui-setup-state) 0))
                        (set-msg "Stop and disarm Wheelie before changing IMU setup")
                        (if (or (> (bufget-u8 data 5) 5) (> (bufget-u8 data 6) 5)
                                (= (/ (bufget-u8 data 5) 2) (/ (bufget-u8 data 6) 2)))
                            (set-msg "Forward and up must be different axes")
                            (apply-set data))))
                ((and (= cmd 6) (>= (buflen data) 2))
                    (progn (setvar 'tl-party (if (= (bufget-u8 data 1) 0) 0 1)) (save-settings) (send-conf)))
                ((and (= cmd 8) (>= (buflen data) 3))
                    (progn (setvar 'pv-kind (bufget-u8 data 1))
                           (setvar 'pv-dur (/ (bufget-u8 data 2) 10.0))
                           (setvar 'pv-t (systime))))
                ((and (= cmd 7) (>= (buflen data) 2))
                    (progn (setvar 'tl-pmode (clamp (bufget-u8 data 1) 0 6)) (save-settings) (send-conf)))
                ((= cmd 3) (if (!= (ui-setup-state) 0)
                    (set-msg "Stop and disarm Wheelie before Zero Level")
                    (if (and (= imu-ok 1) (= mount-ok 1))
                        { (def ui-cal-owner t) (cal-start) }
                        (set-msg "Zero Level needs a working IMU and valid mount"))))
                ((= cmd 4) (if (= (ui-setup-state) 0) (setvar 'reinit-req 1)
                    (set-msg "Stop and disarm Wheelie before restarting IMU")))
                (t nil))))))   ; cmd 5 = keepalive


(def last-msg-id 0)
(def telem-n 0)
; 25 Hz: "xv pitch roll prate" for the live view
;  5 Hz: full "xrt" status line, plus "xmsg" when there is a new message
; Only streams while a UI is open (any command in the last 3 s; pages send
; a keepalive every second), so the CAN bus stays quiet while riding.
(defun check-sd ()
    (let ((r (trap (f-fatinfo))))
        (setvar 'has-sd (if (and (eq (car r) 'exit-ok) (> (ix (ix r 1) 1) 0)) 1 0))))

(def sd-cnt 0)
(defun telem-loop ()
    (loopwhile t
        (progn
            (setvar 'sd-cnt (+ sd-cnt 1))
            (if (>= sd-cnt 250) (progn (setvar 'sd-cnt 0) (check-sd)))   ; every 10 s
            (if (> (secs-since ui-time) 3.0) (setvar 'ui-seen 0))
            (if (= ui-seen 1) (telem-send))
            (sleep 0.04))))

(defun telem-send ()
    (progn
        (send-data (str-merge "xv " (str-from-n pitch "%.2f ") (str-from-n roll "%.2f ")
                                   (str-from-n prate "%.1f")))
        (setvar 'telem-n (+ telem-n 1))
        (if (>= telem-n 5)
            (progn
                (setvar 'telem-n 0)
                (send-data (str-merge "xrt "
                    (str-from-n pitch "%.2f ") (str-from-n roll "%.2f ") (str-from-n prate "%.1f ")
                    (str-from-n loop-hz "%.0f ") (str-from-n i2c-errs "%d ") (str-from-n tx-cnt "%d ")
                    (str-from-n (frame-flags) "%d ") (str-from-n chip-ok "%d ")
                    (str-from-n af "%.3f ") (str-from-n al "%.3f ") (str-from-n au "%.3f ")
                    (str-from-n gated "%d ") (str-from-n cal-state "%d ") (str-from-n work-ms "%.1f ")
                    (str-from-n work-avg "%.2f ")
                    (str-from-n chip-t "%.1f ") (str-from-n tl-scale "%.2f")))
                (send-data (str-merge "xlink "
                    (if dash-mac "1 " "0 ") (if (rx-live) "1 " "0 ")
                    (if (or (< (secs-since d-last) 2.0) (sv-live)) "1 " "0 ")
                    (str-from-n cfg-esc-id "%d ") (if (whl-live) "1 " "0 ")
                    (str-from-n (ui-setup-state) "%d ") cu-version))
                (if (not (= msg-id last-msg-id))
                    (progn (setvar 'last-msg-id msg-id) (send-data (str-merge "xmsg " ui-msg))))))))

;; ==========================================================================
;;  Tail light. Its own 25 Hz thread; the 200 Hz IMU loop never waits on it.
;;  Layers, lowest first: running light or party mode, brake, hazard.
;;  Brake / hazard come from the controller's CU Wheelie status frame
;;  (standard ID 0x540 + controller CAN ID, 'W' 0x81, flags in byte 6:
;;  bit3 crash cutoff, bit4 brake light, bit5 IMU lost).
;; ==========================================================================
(def tl-buf nil)
(def tl-ready 0)
(def tl-reinit 1)
(def tl-frame 0)
(def ct-flags 0)
(def ct-time (systime))
(def ct-seen 0)

(defun tl-can (id data)
    (progn
    (if (= id (+ 0x5C0 can-off)) (is-can id data))
    (if (and (>= id 0x540) (<= id 0x63F) (>= (buflen data) 8)
             (= (bufget-u8 data 0) 0x57) (= (bufget-u8 data 1) 0x81))
        (progn
            (setvar 'ct-flags (bufget-u8 data 6))
            (setvar 'ct-time (systime))
            (setvar 'ct-seen 1)))))

(defun ct-fresh () (and (= ct-seen 1) (< (secs-since ct-time) 0.5)))

(defun hsv (h v)
    ; hue 0..359 -> 0xRRGGBB at value v (0..1)
    (let ((hh (mod h 360)))
        (let ((sect (/ hh 60)) (f (/ (to-float (mod hh 60)) 60.0)) (mx (to-i (* 255.0 v))))
            (let ((up (to-i (* mx f))) (dn (to-i (* mx (- 1.0 f)))))
                (cond ((= sect 0) (+ (* mx 65536) (* up 256)))
                      ((= sect 1) (+ (* dn 65536) (* mx 256)))
                      ((= sect 2) (+ (* mx 256) up))
                      ((= sect 3) (+ (* dn 256) mx))
                      ((= sect 4) (+ (* up 65536) mx))
                      (t (+ (* mx 65536) dn)))))))

; ---- Thermal dimming: the ESP32-C3 die temperature (chip-temp, from the
; Express Open firmware) scales every tail light brightness. Full brightness
; up to tl-tstart, then down to 25% at tl-tstart + 15 degC. Never fully dark:
; brake and hazard must stay visible.
(def chip-t -100.0)     ; filtered die temperature, -100 = unknown
(def tl-scale 1.0)
(def tl-t-last (systime))
(defun tl-thermal ()
    (if (> (secs-since tl-t-last) 1.0)
        (progn
            (setvar 'tl-t-last (systime))
            (let ((r (trap (chip-temp))))
                (if (and (eq (car r) 'exit-ok) (> (ix r 1) -50.0))
                    (progn
                        (setvar 'chip-t (if (< chip-t -50.0) (ix r 1) (+ (* chip-t 0.8) (* (ix r 1) 0.2))))
                        (setvar 'tl-scale
                            (if (<= chip-t tl-tstart) 1.0
                                (max 0.25 (- 1.0 (* 0.75 (/ (- chip-t tl-tstart) 15.0))))))))))))

(defun tl-fill (col bri)
    (looprange i 0 tl-count (rgbled-color tl-buf i col (* bri tl-scale))))

; small integer PRNG for sparkle (ZX81 LCG; stays within 32-bit fixnums)
(def tl-seed 12345)
(defun tl-rand (n)
    (progn (setvar 'tl-seed (mod (+ (* tl-seed 75) 74) 65537)) (mod tl-seed n)))

; animation phase in 'frames', scaled by the speed setting
(defun tl-ph () (* tl-frame tl-pspeed))

(defun tl-party-render ()
    (let ((n tl-count) (b (* tl-pbri tl-scale)) (ph (tl-ph)))
        (cond
            ; 0 rainbow flowing along the strip
            ((= tl-pmode 0)
                (looprange i 0 n
                    (rgbled-color tl-buf i (hsv (to-i (+ (* ph 6.0) (* i (/ 360.0 n)))) 1.0) b)))
            ; 1 whole strip one colour, cycling
            ((= tl-pmode 1)
                (tl-fill (hsv (to-i (* ph 3.0)) 1.0) b))
            ; 2 breathing, colour drifting
            ((= tl-pmode 2)
                (tl-fill (hsv (to-i (* ph 1.0)) 1.0)
                         (* b (+ 0.08 (* 0.92 (+ 0.5 (* 0.5 (sin (* ph 0.12)))))))))
            ; 3 scanner: dot bouncing end to end with a fading tail
            ((= tl-pmode 3)
                (let ((span (max 1 (- n 1))))
                    (let ((pos (to-i (mod (* ph 0.6) (* 2 span)))))
                        (let ((p (if (> pos span) (- (* 2 span) pos) pos)) (col (hsv (to-i (* ph 0.5)) 1.0)))
                            (looprange i 0 n
                                (let ((d (abs (- i p))))
                                    (rgbled-color tl-buf i col (if (< d 4) (* b (- 1.0 (/ d 4.0))) 0.0))))))))
            ; 4 comet: head chasing one way, long tail, colour shifting
            ((= tl-pmode 4)
                (let ((head (to-i (mod (* ph 0.5) n))) (col (hsv (to-i (* ph 2.0)) 1.0)))
                    (looprange i 0 n
                        (let ((d (mod (+ (- head i) n) n)))
                            (rgbled-color tl-buf i col (if (< d 7) (* b (- 1.0 (/ d 7.0))) 0.0))))))
            ; 5 police: double flash, red half then blue half
            ((= tl-pmode 5)
                (let ((st (mod (to-i ph) 16)) (half (/ n 2)))
                    (progn
                        (tl-fill 0 0.0)
                        (if (or (= st 0) (= st 1) (= st 4) (= st 5))
                            (looprange i 0 half (rgbled-color tl-buf i 0xFF0000 b)))
                        (if (or (= st 8) (= st 9) (= st 12) (= st 13))
                            (looprange i half n (rgbled-color tl-buf i 0x0000FF b))))))
            ; 6 sparkle: dim rainbow with random white twinkles
            (t
                (progn
                    (looprange i 0 n
                        (rgbled-color tl-buf i (hsv (to-i (+ (* ph 2.0) (* i (/ 360.0 n)))) 1.0) (* b 0.25)))
                    (looprange k 0 (max 1 (/ n 6))
                        (rgbled-color tl-buf (tl-rand n) (if (>= tl-type 2) 0xFF000000 0xFFFFFF) b)))))))

; preview from the page: show brake or hazard for a few seconds
(def pv-kind 0)
(def pv-dur 0.0)
(def pv-t (systime))
(defun pv-on (k) (and (= pv-kind k) (< (secs-since pv-t) pv-dur)))

(defun tl-render ()
    (progn
        ; brake also from the link core: regen, or the screen's brake light
        (var brake (or (pv-on 1) lt-brake (and (ct-fresh) (= (bitwise-and ct-flags 16) 16))))
        ; crash or IMU lost, or the screen's hazards
        (var hazard (or (pv-on 2) aux-hazard (and (ct-fresh) (> (bitwise-and ct-flags 40) 0))))
        (var on (< (mod tl-frame 12) 6))
        (cond
            (hazard
                (if on (tl-fill 0xFF3800 tl-brk) (tl-fill 0 0.0)))
            ; the screen's turn signals: the turning half flashes amber over
            ; whatever the rest is showing
            ((or aux-left aux-right) {
                    (tl-fill 0xFF0000 (if brake tl-brk tl-run))
                    (var h (/ tl-count 2))
                    (if on (looprange i (if aux-left 0 h) (if aux-left h tl-count)
                               (rgbled-color tl-buf i 0xFF3800 (* tl-brk tl-scale))))
            })
            (brake (tl-fill 0xFF0000 tl-brk))
            ((= tl-party 1) (tl-party-render))
            (t (tl-fill 0xFF0000 tl-run)))
        (rgbled-update tl-buf)
        (setvar 'tl-frame (+ tl-frame 1))))

(defun tl-loop ()
    (loopwhile t
        (progn
            (if (and (= tl-en 1) (or (= tl-ready 0) (= tl-reinit 1)))
                (let ((r (progn
                            ; Always release the driver first. It lives in the
                            ; firmware and survives a script restart (e.g. an install
                            ; over CAN), and initialising it twice leaves the strip
                            ; dark while every call reports success.
                            (trap (rgbled-deinit))
                            (setvar 'tl-ready 0)
                            (trap (rgbled-init tl-pin 3)))))
                    (if (eq (car r) 'exit-ok)
                        (progn
                            (setvar 'tl-buf (rgbled-buffer tl-count tl-type))
                            (setvar 'tl-ready 1) (setvar 'tl-reinit 0))
                        (progn (setvar 'tl-ready 0) (setvar 'tl-reinit 0)
                               (set-msg "Tail light: LED init failed")))))
            (if (and (= tl-en 0) (= tl-ready 1))
                (progn (tl-fill 0 0.0) (rgbled-update tl-buf) (setvar 'tl-ready 0)))
            (tl-thermal)
            (if (and (= tl-en 1) (= tl-ready 1)) (trap (tl-render)))
            (sleep 0.04))))

@const-end

; ---- Boot ----
(setvar 'txbuf (bufcreate 8))
(check-sd)
(update-tau)
(apply-mount)
; The core has the one event handler: this board's app data and CAN
; frames reach it through the hooks.
(core-load)
(setvar 'core-role 3) (setvar 'core-prio 30)
(setvar 'core-app-hook handle-rx)
(setvar 'core-sid-hook tl-can)
(spawn tl-loop)
(spawn telem-loop)
; restarted if it ever fails: it is the pitch feed, and every other thread
; here already comes back by itself
(spawn (fn () (loopwhile t (progn (trap (main-loop)) (sleep 0.1)))))
(core-start)

(print (str-merge "cu_imu v" cu-version " started"))
