; One-time, commit-last upgrade from shipped cu_link (magic 782).
; Old slots 0-73 are never changed, including pairing 40/41 and mode cache 54-73.
; Read/write integer words to preserve the exact stored float bits. Every
; destination is verified before core magic 100 commits the completed copy.
@const-start
(defun express-word (slot fallback) {
    (var v (eeprom-read-i slot)) (if (number? v) v fallback)
})
(defun express-store (slot v) {
    (var word (to-i32 v))
    (var stored (eeprom-store-i slot word))
    (var got (eeprom-read-i slot))
    (if (not (and stored (number? got) (= got word)))
        (exit-error 'express-settings-copy-failed))
})
(defun express-migrate () {
    (if (= (express-word 100 0) core-magic) false
        (if (= (express-word 0 0) 782) {
            ; A previous interrupted copy is retried from the untouched old bank.
            (express-store 100 0)
            (loopforeach row '((101 1 6) (102 2 0) (103 3 0) (104 4 1) (105 5 0)
                (106 6 4) (107 26 0) (108 27 0) (109 28 0) (110 29 0) (111 30 0)
                (112 7 1) (113 8 2) (114 9 3) (115 10 4) (116 17 0) (117 18 0)
                (118 19 0) (119 25 1) (120 31 1) (121 16 0) (122 40 0) (123 41 0)
                (170 11 0) (171 12 20) (172 13 15) (173 14 2) (174 15 1)
                (175 32 0) (176 33 2) (177 34 0) (190 20 0))
                (express-store (ix row 0) (express-word (ix row 1) (ix row 2))))
            (express-store 124 1)
            (looprange i 0 20 (express-store (+ 130 i) (express-word (+ 54 i) 0)))
            ; Legacy used fixed brightness and never persisted the ANT address.
            ; Zero brightness words are valid values, so encode the old defaults.
            (express-store 178 0x3DF5C28F) (express-store 179 0x3F800000)
            (express-store 191 0) (express-store 192 0)
            (express-store 180 lights-magic)
            (express-store 100 core-magic)
            (print "legacy link settings copied and verified") true
        } false))
})
@const-end
