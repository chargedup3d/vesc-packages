; Experimental gateway wire format. Only callers with a pinned paired MAC
; may feed these frames. One ordered, CRC-checked packet, at most 512 bytes.
; Header: D7, version=1, kind, actual CAN target, ticket u32,
; payload length u16, offset u16, payload CRC16; up to 180 payload bytes.
@const-start
(defun gw-min (a b) (if (< a b) a b))
(defun gw-wire-reset () {
    (if gw-rx-buf (free gw-rx-buf))
    (def gw-rx-buf nil) (def gw-rx-off 0)
})
(defun gw-wire-frame (kind target ticket payload off) {
    (var n (buflen payload))
    (var cnt (gw-min 180 (- n off)))
    (var b (bufcreate (+ cnt 14)))
    (bufset-u8 b 0 0xD7) (bufset-u8 b 1 1)
    (bufset-u8 b 2 kind) (bufset-u8 b 3 target)
    (bufset-u32 b 4 ticket) (bufset-u16 b 8 n)
    (bufset-u16 b 10 off) (bufset-u16 b 12 (crc16 payload n))
    (bufcpy b 14 payload off cnt)
    b
})
(defun gw-wire-send (send-fn dest kind target ticket payload) {
    (var ok true) (var off 0) (var n (buflen payload))
    (if (or (= n 0) (> n 512)) false {
        (loopwhile (and ok (< off n)) {
            (var b (gw-wire-frame kind target ticket payload off))
            (var r (trap (send-fn dest b)))
            (free b)
            (setq ok (and (eq (car r) 'exit-ok) (eq (ix r 1) t)))
            (setq off (+ off 180))
        })
        ok
    })
})
; Returns (ticket target payload), transferring ownership of payload.
(defun gw-wire-feed (b kind) {
    (if (and gw-rx-buf (> (secs-since gw-rx-t) 1.0)) (gw-wire-reset))
    (var result nil) (var bn (buflen b))
    (if (and (> bn 14) (<= bn 194) (= (bufget-u8 b 0) 0xD7)
             (= (bufget-u8 b 1) 1) (= (bufget-u8 b 2) kind)) {
        (var target (bufget-u8 b 3)) (var ticket (bufget-u32 b 4))
        (var n (bufget-u16 b 8)) (var off (bufget-u16 b 10))
        (var crc (bufget-u16 b 12)) (var cnt (- bn 14))
        (if (and (> n 0) (<= n 512) (<= (+ off cnt) n)
                 (= cnt (gw-min 180 (- n off)))) {
            (if (and (= off 0) (not gw-rx-buf)) {
                (def gw-rx-buf (bufcreate n)) (def gw-rx-off 0)
                (def gw-rx-ticket ticket) (def gw-rx-target target)
                (def gw-rx-crc crc) (def gw-rx-t (systime))
            })
            (if (and gw-rx-buf (= ticket gw-rx-ticket) (= target gw-rx-target)
                     (= n (buflen gw-rx-buf)) (= crc gw-rx-crc)
                     (= off gw-rx-off)) {
                (bufcpy gw-rx-buf off b 14 cnt)
                (def gw-rx-off (+ off cnt))
                (if (= gw-rx-off n) {
                    (if (= (crc16 gw-rx-buf n) crc) {
                        (setq result (list ticket target gw-rx-buf))
                        (def gw-rx-buf nil)
                    })
                    (gw-wire-reset)
                })
            })
        })
    })
    result
})
; Request allowlist duplicated at the CAN boundary. No arbitrary terminal,
; Lisp, firmware, custom-app, raw motor or detection commands pass this gate.
(defun gw-read-ok (b) {
    (var n (buflen b)) (var c (if (> n 0) (bufget-u8 b 0) -1))
    (or (and (= n 1) (member c '(0 4 14 15 17 18 31 32 33 47 79 91 96 157)))
        (and (= n 2) (member c '(93 94)))
        (and (= n 3) (member c '(65 128)))
        (and (= n 5) (member c '(50 51)))
        (and (= n 10) (= c 92)))
})
@const-end
(def gw-rx-buf nil) (def gw-rx-off 0) (def gw-rx-ticket 0u32)
(def gw-rx-target 0) (def gw-rx-crc 0) (def gw-rx-t 0)
