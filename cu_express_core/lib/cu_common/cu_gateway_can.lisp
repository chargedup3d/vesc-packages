; Paired screen -> this link -> actual controller. Read-only experimental
; gateway. The Link thread owns radio sends; the CAN event thread only collects.
@const-start
(defun gw-can-send (target payload) {
    (var n (buflen payload))
    (if (<= n 6) {
        (var b (bufcreate (+ n 2)))
        (bufset-u8 b 0 cfg-my-id) (bufset-u8 b 1 0)
        (bufcpy b 2 payload 0 n)
        (can-send-eid (+ (shl 8 8) target) b) (free b)
    } {
        (var off 0)
        (loopwhile (< off n) {
            (var short (<= off 255)) (var head (if short 1 2))
            (var cnt (gw-min (- n off) (- 8 head)))
            (var b (bufcreate (+ head cnt)))
            (if short (bufset-u8 b 0 off) (bufset-u16 b 0 off))
            (bufcpy b head payload off cnt)
            (can-send-eid (+ (shl (if short 5 6) 8) target) b)
            (free b) (setq off (+ off cnt))
        })
        (var b (bufcreate 6))
        (bufset-u8 b 0 cfg-my-id) (bufset-u8 b 1 0)
        (bufset-u16 b 2 n) (bufset-u16 b 4 (crc16 payload n))
        (can-send-eid (+ (shl 7 8) target) b) (free b)
    })
    ; Stop unsolicited application output being routed to our reply buffer.
    ; All allowed commands are synchronous, so this follows their reply.
    (var quiet (bufcreate 3))
    (bufset-u8 quiet 0 cfg-my-id) (bufset-u8 quiet 1 2) (bufset-u8 quiet 2 0)
    (can-send-eid (+ (shl 8 8) target) quiet) (free quiet)
})
(defun gw-can-radio (src data) {
    ; Never learn a new paired dash from a gateway frame.
    (if (and dash-mac (eq src dash-mac) (bridge) (not gw-can-job)
             (> (secs-since gw-can-end) 0.35)) {
        (var r (gw-wire-feed data 1))
        (if r {
            (var ticket (ix r 0)) (var target (ix r 1)) (var b (ix r 2))
            (if (and (= target cfg-esc-id) (not (member ticket gw-can-seen)) (gw-read-ok b)) {
                (def gw-can-seen (cons ticket (take gw-can-seen 15)))
                (def gw-can-job r) (def gw-can-src src)
                (def gw-can-started false)
            } (free b))
        })
    })
})
(defun gw-can-result (b n) {
    (if (and gw-can-job gw-can-started (not gw-can-reply) (> n 0) (<= n 512)
             (= (bufget-u8 b 0) (bufget-u8 (ix gw-can-job 2) 0))) {
        (def gw-can-reply (bufcreate n))
        (bufcpy gw-can-reply 0 b 0 n)
    })
})
(defun gw-can-eid (id data) (atomic {
    (var consumed (and gw-can-job gw-can-started (= (bitwise-and id 255) cfg-my-id)))
    (if consumed {
        (var cmd (shr id 8)) (var n (buflen data))
        (cond
            ((and (or (= cmd 5) (= cmd 6)) (> n (if (= cmd 5) 1 2))) {
                (var h (if (= cmd 5) 1 2))
                (var off (if (= cmd 5) (bufget-u8 data 0) (bufget-u16 data 0)))
                ; An offset-zero fragment starts a new packet. Complete,
                ; contiguous coverage AND CRC are required before dispatch.
                (if (= off 0) (def gw-can-off 0))
                (if (and (= off gw-can-off) (<= (+ off (- n h)) 512)) {
                    (bufcpy gw-can-buf off data h (- n h))
                    (def gw-can-off (+ off (- n h)))
                } (def gw-can-off -1))
            })
            ((and (= cmd 7) (= n 6)) {
                (var size (bufget-u16 data 2))
                (if (and (= (bufget-u8 data 0) (ix gw-can-job 1))
                         (= (bufget-u8 data 1) 1) (> size 0) (<= size 512)
                         (= size gw-can-off) (= (crc16 gw-can-buf size) (bufget-u16 data 4)))
                    (gw-can-result gw-can-buf size))
                (def gw-can-off 0)
            })
            ((and (= cmd 8) (> n 2) (= (bufget-u8 data 0) (ix gw-can-job 1))
                  (= (bufget-u8 data 1) 1)) {
                (bufcpy gw-can-buf 0 data 2 (- n 2))
                (gw-can-result gw-can-buf (- n 2))
            })
        )
    })
    consumed
}))
(defun gw-can-finish () (atomic {
    (if gw-can-job (free (ix gw-can-job 2)))
    (if gw-can-reply (free gw-can-reply))
    (def gw-can-job nil) (def gw-can-reply nil)
    (def gw-can-started false) (def gw-can-end 0)
    (def gw-can-last (systime))
}))
(defun gw-can-tick () {
    (if (not gw-can-buf) (def gw-can-buf (bufcreate 512)))
    (if gw-can-job {
        (cond
            ((or (!= cfg-esc-id (ix gw-can-job 1)) (not (eq dash-mac gw-can-src)) (not (bridge)))
                (gw-can-finish))
            ((not gw-can-started)
                (if (> (secs-since sv-req-t) 0.35) {
                    (def gw-can-off 0) (def gw-can-t (systime))
                    (def gw-can-started true)
                    (gw-can-send (ix gw-can-job 1) (ix gw-can-job 2))
                }))
            (gw-can-reply {
                (trap (esp-now-add-peer gw-can-src))
                (gw-wire-send esp-now-send gw-can-src 2 (ix gw-can-job 1) (ix gw-can-job 0) gw-can-reply)
                (gw-can-finish)
            })
            ((> (secs-since gw-can-t) 2.0) { (gw-can-finish) (def gw-can-end (systime)) })
        )
    })
})
@const-end
(def gw-can-job nil) (def gw-can-src nil) (def gw-can-seen nil)
(def gw-can-buf nil) (def gw-can-off 0) (def gw-can-reply nil)
(def gw-can-t 0) (def gw-can-end 0) (def gw-can-started false)

(def gw-can-last 0)
