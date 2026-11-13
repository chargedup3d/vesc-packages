(def ab-h 0)
(def ab-state "off")
(def ab-frames 0)
(def ab-bad 0)
(def ab-linked false)
(def ab-last 0)
(def ab-wrong false)
(def ab-fails 0)
(def ab-tries 0)
(def ab-paused false)
(def ab-proto 0)
(defun ab-find () {
(def ab-h 0)
(loopforeach c (trap-chars) {
(if (and (= ab-h 0) (eq (ix c 0) 65505)) (def ab-h (ix c 1)))
})
(> ab-h 0)
})
(defun trap-chars () (car (cdr (trap (ble-chars 1)))))
(defun ab-request () {
(var b (bufcreate 6))
(bufset-u8 b 0 0xDB) (bufset-u8 b 1 0xDB)
(bufset-u8 b 2 0) (bufset-u8 b 3 0) (bufset-u8 b 4 0) (bufset-u8 b 5 0)
(var r (trap (ble-write ab-h b 1)))
(free b)
(eq (car r) 'exit-ok)
})
(defun ab-sum (b) {
(var s 0)
(looprange i 4 138 (setq s (+ s (bufget-u8 b i))))
(bitwise-and s 0xFFFF)
})
(defun ab-parse (b) {
(if (or (!= (buflen b) 140)
(!= (bufget-u8 b 0) 0xAA) (!= (bufget-u8 b 1) 0x55)
(!= (bufget-u8 b 2) 0xAA) (!= (bufget-u8 b 3) 0xFF)
(!= (ab-sum b) (bufget-u16 b 138))
(< (bufget-u8 b 123) 1) (> (bufget-u8 b 123) 32))
{ (def ab-bad (+ ab-bad 1)) false }
{
(var n (bufget-u8 b 123))
(var cs nil)
(var i (- n 1))
(loopwhile (>= i 0) {
(setq cs (cons (/ (to-float (bufget-u16 b (+ 6 (* 2 i))))
1000.0)
cs))
(setq i (- i 1))
})
(def bms-cells cs)
(def bms-n n)
(def bms-i (/ (to-float (- 0 (bufget-i32 b 70))) 10.0))
(def bms-charging (> bms-i 0.2))
(def bms-v (/ (to-float (bufget-u16 b 4)) 10.0))
(def bms-soc (to-float (bufget-u8 b 74)))
(def bms-ahfull (/ (to-float (bufget-u32 b 75)) 1000000.0))
(def bms-ah     (/ (to-float (bufget-u32 b 79)) 1000000.0))
(var hi -100.0) (var lo 200.0)
(looprange t2 0 6 {
(var v (to-float (bufget-i16 b (+ 91 (* 2 t2)))))
(if (and (!= v 0.0) (> v -40.0) (< v 150.0)) {
(if (> v hi) (setq hi v))
(if (< v lo) (setq lo v))
})
})
(if (> hi -100.0) {
(def bms-tmax hi)
(def bms-tmin lo)
(def d-tbat hi)
})
(def bms-last (systime))
(def ab-last (systime))
(def ab-frames (+ ab-frames 1))
true
})
})
(defun ab-collect (secs) {
(var b (bufcreate 140))
(var n 0)
(var t0 (systime))
(var done false)
(loopwhile (and (not done) (< (secs-since t0) secs)) {
(var f (car (cdr (trap (ble-rx 1)))))
(if f {
(var fl (buflen f))
(looprange i 0 fl {
(var by (bufget-u8 f i))
(if (< n 4)
(if (= by (ix '(0xAA 0x55 0xAA 0xFF) n)) {
(bufset-u8 b n by)
(setq n (+ n 1))
} (cond
((and (= n 3) (= by 0x55)) (setq n 2))
((= by 0xAA) { (bufset-u8 b 0 by) (setq n 1) })
(t (setq n 0))))
(if (< n 140) {
(bufset-u8 b n by)
(setq n (+ n 1))
}))
})
(if (>= n 140) (setq done true))
} (sleep 0.02))
})
(if done b { (free b) nil })
})
(defun ab-poll-v1 (secs) {
(if (not (ab-request)) false {
(var b (ab-collect secs))
(if b {
(var ok (ab-parse b))
(free b)
ok
} false)
})
})
(defun ab-modbus (b n) {
(var c 0xFFFF)
(looprange i 1 (+ n 1) {
(setq c (bitwise-xor c (bufget-u8 b i)))
(looprange k 0 8
(setq c (if (= (bitwise-and c 1) 1)
(bitwise-xor (shr c 1) 0xA001)
(shr c 1))))
})
c
})
(defun ab-request-v2 () {
(var b (bufcreate 10))
(looprange i 0 10
(bufset-u8 b i (ix '(0x7E 0xA1 0x01 0x00 0x00 0xBE 0x18 0x55 0xAA 0x55) i)))
(var r (trap (ble-write ab-h b 1)))
(free b)
(eq (car r) 'exit-ok)
})
(defun ab-rx () (car (cdr (trap (ble-rx 1)))))
(defun ab-collect-v2 (secs src) {
(var b (bufcreate 200))
(var n 0)
(var want 200)
(var t0 (systime))
(loopwhile (and (< n want) (< (secs-since t0) secs)) {
(var f (src))
(if f
(looprange i 0 (buflen f) {
(var by (bufget-u8 f i))
(cond
((= n 0) (if (= by 0x7E) {
(bufset-u8 b 0 by) (setq n 1) }))
((= n 1) (cond
((= by 0xA1) { (bufset-u8 b 1 by) (setq n 2) })
((= by 0x7E) nil)
(t (setq n 0))))
((< n want) {
(bufset-u8 b n by)
(setq n (+ n 1))
(if (= n 6) {
(setq want (+ 10 (bufget-u8 b 5)))
(if (> want 200) { (setq n 0) (setq want 200) })
})
}))
})
(sleep 0.02))
})
(if (and (> n 9) (= n want)) (list b n) { (free b) nil })
})
(defun ab-le16 (b i) (bufget-u16 b i 'little-endian))
(defun ab-lei16 (b i) (bufget-i16 b i 'little-endian))
(defun ab-parse-v2 (b n) {
(if (or (< n 10) (> n (buflen b))
(!= (bufget-u8 b 0) 0x7E) (!= (bufget-u8 b 1) 0xA1)
(!= n (+ 10 (bufget-u8 b 5)))
(!= (bufget-u8 b 2) 0x11)
(!= (bufget-u8 b (- n 2)) 0xAA) (!= (bufget-u8 b (- n 1)) 0x55)
(!= (ab-modbus b (- n 5)) (ab-le16 b (- n 4))))
{ (def ab-bad (+ ab-bad 1)) false }
{
(var nt (bufget-u8 b 8))
(var nc (bufget-u8 b 9))
(var o (* 2 (+ nc nt)))
(if (or (< nc 1) (> nc 32) (> nt 8) (> (+ 58 o) (- n 4)))
{ (def ab-bad (+ ab-bad 1)) false }
{
(var cs nil)
(var i (- nc 1))
(loopwhile (>= i 0) {
(setq cs (cons (/ (to-float (ab-le16 b (+ 34 (* 2 i)))) 1000.0) cs))
(setq i (- i 1))
})
(def bms-cells cs)
(def bms-n nc)
(def bms-i (- 0.0 (/ (to-float (ab-lei16 b (+ 40 o))) 10.0)))
(def bms-charging (> bms-i 0.2))
(def bms-v (/ (to-float (ab-le16 b (+ 38 o))) 100.0))
(def bms-soc (to-float (ab-le16 b (+ 42 o))))
(def bms-ahfull (/ (to-float (bufget-u32 b (+ 50 o) 'little-endian)) 1000000.0))
(def bms-ah (/ (to-float (bufget-u32 b (+ 54 o) 'little-endian)) 1000000.0))
(var hi -100.0) (var lo 200.0)
(looprange k 0 nt {
(var v (to-float (ab-lei16 b (+ 34 (* 2 nc) (* 2 k)))))
(if (> v hi) (setq hi v))
(if (< v lo) (setq lo v))
})
(if (> hi -100.0) {
(def bms-tmax hi)
(def bms-tmin lo)
(def d-tbat hi)
})
(def bms-last (systime))
(def ab-last (systime))
(def ab-frames (+ ab-frames 1))
true
})
})
})
(defun ab-poll-v2 (secs) {
(if (not (ab-request-v2)) false {
(var r (ab-collect-v2 secs ab-rx))
(if r {
(var ok (ab-parse-v2 (ix r 0) (ix r 1)))
(free (ix r 0))
ok
} false)
})
})
(defun ab-poll () (cond
((= ab-proto 1) (ab-poll-v1 3.0))
((= ab-proto 2) (ab-poll-v2 3.0))
((ab-poll-v1 2.0) { (def ab-proto 1) true })
((ab-poll-v2 2.0) { (def ab-proto 2) true })
(t false)))
(defun ab-seen () {
(if (< (str-len cfg-ab-mac) 17) false {
(var f false)
(loopforeach d (car (cdr (trap (ble-scan-list))))
(if (eq (str-find (ix d 0) cfg-ab-mac) 0) (setq f true)))
f
})
})
(defun ab-recent (secs)
(match (trap (ble-seen-ago cfg-ab-mac))
((exit-ok (? a)) (and (>= a 0.0) (< a secs)))
(_ false)))
(defun ab-link () {
(if (= (car (cdr (trap (ble-state 1)))) 4) true {
(if (< (str-len cfg-ab-mac) 17) {
(def ab-state "no battery chosen")
false
} {
(def ab-state "looking")
(var found (ab-recent 3.0))
(if (not found) {
(trap (ble-scan-start 8))
(var n 0)
(loopwhile (and (not found) (< n 20)) {
(sleep 0.4)
(setq found (or (ab-seen) (ab-recent 1.0)))
(setq n (+ n 1))
})
(trap (ble-scan-stop))
(sleep 0.3)
})
(if (not found) {
(def ab-state "battery asleep")
false
} {
(def ab-state "connecting")
(ble-wait-other 0)
(trap (ble-connect cfg-ab-mac 1))
(if (!= (car (cdr (trap (ble-state 1)))) 4) {
(def ab-state "would not connect")
false
} true)
})
})
})
})
(defun ab-subscribe () {
(if (not (ab-find)) {
(def ab-state "not a BMS")
(trap (ble-disconnect 1))
(def ab-linked false)
(def ab-fails (+ ab-fails 1))
(if (>= ab-fails 3) (def ab-wrong true))
false } {
(trap (ble-notify ab-h 1))
(sleep 0.4)
(trap (ble-cccd ab-h true 1))
(sleep 0.3)
(def ab-last (systime))
(def ab-linked true)
(def ab-fails 0)
(def ab-wrong false)
(def ab-tries 0)
true
})
})
(defun ab-mac-bytes (mac) {
(if (< (str-len mac) 17) nil {
(var b (bufcreate 6))
(var ok true)
(looprange i 0 6 {
(var hi (vb-hex (bufget-u8 mac (* i 3))))
(var lo (vb-hex (bufget-u8 mac (+ 1 (* i 3)))))
(if (or (< hi 0) (< lo 0)) (setq ok false)
(bufset-u8 b i (+ (* 16 hi) lo)))
})
(if ok b { (free b) nil })
})
})
(defun ab-mac-save () {
(var b (ab-mac-bytes cfg-ab-mac))
(if b {
(eeprom-store-i 150 (bufget-u32 b 0))
(eeprom-store-i 151 (bufget-u16 b 4))
(free b)
true
} false)
})
(defun ab-mac-load () {
(var hi (eeprom-read-i 150))
(var lo (eeprom-read-i 151))
(if (or (eq hi nil) (= hi 0) (= hi -1)) false {
(var b (bufcreate 6))
(bufset-u32 b 0 hi)
(bufset-u16 b 4 lo)
(var s "")
(looprange i 0 6 {
(setq s (str-merge s (str-from-n (bufget-u8 b i) "%02X")))
(if (< i 5) (setq s (str-merge s ":")))
})
(free b)
(def cfg-ab-mac s)
true
})
})
(defun ab-forget () {
(def cfg-ab-en false)
(def cfg-ab-mac "")
(def ab-linked false)
(def ab-wrong false)
(def ab-fails 0)
(def ab-tries 0)
(def ab-paused false)
(def ab-state "off")
(def ab-proto 0)
(def bms-n 0)
(eeprom-store-i 149 0)
(eeprom-store-i 150 0)
(eeprom-store-i 151 0)
(trap (ble-disconnect 1))
true
})
(defun ab-use (mac) {
(def cfg-ab-mac mac)
(def cfg-ab-en true)
(def ab-proto 0)
(def ab-paused false)
(def ab-wrong false)
(def ab-fails 0)
(def ab-tries 0)
(ab-mac-save)
(eeprom-store-i 149 1)
(trap (ble-disconnect 1))
(def ab-linked false)
(trap (ab-start))
true
})
(def ab-thread false)
(defun ab-start () {
(if ab-thread (print "ant bms already running") {
(def ab-thread true)
(loopwhile-thd ("Ant" 200) t {
(match (trap (loopwhile t {
(if (and cfg-ab-en (not ab-paused)
(not ab-wrong)
(> (str-len cfg-ab-mac) 1)) {
(if (and (not ab-linked) (vb-phone)) {
(def ab-state "waiting - VESC Tool connected")
(sleep 0.5)
}
(if (not ab-linked) {
(if (ab-link) (ab-subscribe)
{
(def ab-tries (+ ab-tries 1))
(var w (if (< ab-tries 8) 4.0 30.0))
(var t0 (systime))
(loopwhile (and (< (secs-since t0) w)
(not (ab-recent 2.0)))
(sleep 0.5))
})
}))
(if ab-linked {
(var got (ab-poll))
(if got
(def ab-state "connected")
{
(if (> (secs-since ab-last) 30.0) {
(trap (ble-disconnect 1))
(def ab-linked false)
(def ab-state "link lost")
(def ab-fails (+ ab-fails 1))
(if (>= ab-fails 3)
(def ab-wrong true))
})
})
(sleep (if got cfg-ab-period 1.0))
})
} {
(if ab-linked {
(trap (ble-disconnect 1))
(def ab-linked false)
})
(def ab-state (cond (ab-wrong "not a BMS")
(ab-paused "released")
(t "off")))
(sleep 2.0)
})
}))
((exit-ok (? a)) nil) (_ (print "ant bms thread died")))
(def ab-linked false)
(sleep 2.0)
})
})
})
