@const-start
;! LSM6DS3TR-C driver.
; drv_lsm6ds3trc.lisp - ST LSM6DS3TR-C driver (production IMU, imu_type 2)
; --------------------------------------------------------------------------
; Bench-checked 2026-10-15 on the Express Open rev C (on-board TR-C at 0x6A):
; WHO_AM_I 0x6A, CTRL1_XL/CTRL2_G/CTRL3_C read back 0x54/0x58/0x44, accel
; ~1 g at rest, loop 198 Hz. Scale factors are from the datasheet tables.
; Address 0x6A (SA0 low) or 0x6B (SA0 high), WHO_AM_I reg 0x0F = 0x6A.
;   CTRL3_C  0x12 = 0x01 then 0x44  software reset, then BDU + IF_INC
;   CTRL1_XL 0x10 = 0x54  accel 208 Hz (ODR 0101), +-16 g (FS 01), default filter
;   CTRL2_G  0x11 = 0x58  gyro 208 Hz (ODR 0101), +-1000 dps (FS 10)
; Accel LPF2 (CTRL8_XL) is left off: the complementary filter and accel
; gating already handle vibration, and the TR-C cutoff coding needs checking.
; Data: 12 bytes from OUTX_L_G 0x22, gx gy gz ax ay az, int16 little-endian.
; Scale: gyro 35 mdps/LSB at +-1000 dps, accel 0.488 mg/LSB at +-16 g.
; --------------------------------------------------------------------------

(def trc-addr 0x6A)
; buffers are allocated on first use: this file is loaded into flash
; (const heap) where arrays would be read-only
(def trc-rx1 nil)
(def trc-rx12 nil)

(defun trc-rd (reg)
    (if (= (i2c-tx-rx trc-addr (list reg) trc-rx1) 0) (bufget-u8 trc-rx1 0) -1))

(defun trc-wr (reg val)
    (= (i2c-tx-rx trc-addr (list reg val)) 0))

(defun trc-whoami ()
    (progn
    (if (not trc-rx1) (progn (setvar 'trc-rx1 (bufcreate 1)) (setvar 'trc-rx12 (bufcreate 12))))
    (cond
        ((progn (setvar 'trc-addr 0x6A) (= (trc-rd 0x0F) 0x6A)) t)
        ((progn (setvar 'trc-addr 0x6B) (= (trc-rd 0x0F) 0x6A)) t)
        (t nil))))

(defun trc-init ()
    (progn
        (trc-wr 0x12 0x01) (sleep 0.05)
        (trc-wr 0x12 0x44)
        (trc-wr 0x10 0x54)
        (trc-wr 0x11 0x58)
        (sleep 0.05)
        (and (= (trc-rd 0x10) 0x54) (= (trc-rd 0x11) 0x58) (= (trc-rd 0x12) 0x44))))

 ; STATUS_REG XLDA/GDA are cleared by reading their output registers.
; Require both conversions before the burst. 'not-ready is not an I2C error.
; ST AN5130 section 4.2; register/bit definitions in ST's TR-C driver.
(defun trc-read ()
    (let ((status (trc-rd 0x1E)))
        (cond
            ((< status 0) nil)
            ((!= (bitwise-and status 3) 3) 'not-ready)
            ((= (i2c-tx-rx trc-addr (list 0x22) trc-rx12) 0)
                (list (* (bufget-i16 trc-rx12 0 'little-endian) 0.035)
                      (* (bufget-i16 trc-rx12 2 'little-endian) 0.035)
                      (* (bufget-i16 trc-rx12 4 'little-endian) 0.035)
                      (* (bufget-i16 trc-rx12 6 'little-endian) 0.000488)
                      (* (bufget-i16 trc-rx12 8 'little-endian) 0.000488)
                      (* (bufget-i16 trc-rx12 10 'little-endian) 0.000488)))
            (t nil))))

@const-end
