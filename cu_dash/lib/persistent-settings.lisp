;! Settings in EEPROM.
; Carved out of main.lisp. This file is one contiguous run of that
; program and is read back in its original position, so the order of
; evaluation is exactly what it was.
;
; the show-bits field, cfg-save, cfg-load and cfg-dump

@const-start
; 256 is retired: orientation reallocates the framebuffer so it has its
; own slot and goes through set-vertical. 262144 is not written here
; either, because cfg-vb-en owns slot 109 and the cfg-keys loop runs
; after set-show.
(defun show-bits () (bitwise-or (if cfg-show-tl 1 0)
        (bitwise-or (if cfg-show-tr 2 0)
        (bitwise-or (if cfg-show-bl 4 0)
        (bitwise-or (if cfg-show-br 8 0)
        (bitwise-or (if cfg-show-gauge 16 0)
        (bitwise-or (if cfg-show-batt 32 0)
        (bitwise-or (if cfg-show-bars 64 0)
        (bitwise-or (if cfg-show-page2 128 0)
        (bitwise-or 0
        (bitwise-or (if cfg-btn-en 512 0)
        (bitwise-or (if cfg-show-modestrip 1024 0)
        (bitwise-or (if cfg-esc2-en 2048 0)
        (bitwise-or (if cfg-show-status 4096 0)
        (bitwise-or (if cfg-aa 8192 0)
        (bitwise-or (if cfg-bms-demo 16384 0)
        (bitwise-or (if cfg-show-bmspage 32768 0)
        (bitwise-or (if cfg-auto-charge 65536 0)
        (bitwise-or (if cfg-cruise-cancel 131072 0)
        (bitwise-or (if cfg-splash 524288 0)
        (bitwise-or (if cfg-rev-en 0 1048576)
        (bitwise-or (if cfg-simple 2097152 0)
        ; Four more, all stored inverted for the same reason reverse is: a
        ; settings file written before they existed has zeroes here, and a
        ; zero has to mean the thing is shown.
        (bitwise-or (if cfg-show-main 0 4194304)
        (bitwise-or (if cfg-show-s6 0 8388608)
        (bitwise-or (if cfg-show-s7 0 16777216)
        (bitwise-or (if cfg-show-s8 0 33554432)
                    (if cfg-show-dial 67108864 0)))))))))))))))))))))))))))

; != and not = or not-eq: eeprom-read-i hands back an i32, bitwise-and keeps
; that type, and not-eq compares type as well as value, so (not-eq 0 0i32) is
; true and every cleared bit read back as set. != compares numerically.
(defun set-show (v) {
        ; 134217727 is not a round number chosen for taste: a plain integer
        ; here is twenty eight bits and signed, so bit twenty seven is the
        ; sign. Setting it made show-bits come back negative, this guard
        ; rejected the lot and every flag reverted to its default. Bit
        ; twenty six is the last one that fits - anything further needs a
        ; slot of its own, which is what road mode has.
        (if (or (eq v nil) (< v 0) (> v 134217727)) false {
                (def cfg-show-tl    (!= 0 (bitwise-and v 1)))
                (def cfg-show-tr    (!= 0 (bitwise-and v 2)))
                (def cfg-show-bl    (!= 0 (bitwise-and v 4)))
                (def cfg-show-br    (!= 0 (bitwise-and v 8)))
                (def cfg-show-gauge (!= 0 (bitwise-and v 16)))
                (def cfg-show-batt  (!= 0 (bitwise-and v 32)))
                (def cfg-show-bars  (!= 0 (bitwise-and v 64)))
                (def cfg-show-page2 (!= 0 (bitwise-and v 128)))
                ; deliberately not restored here: orientation reallocates the
                ; framebuffer and must go through set-vertical. cfg-load sets it
                ; directly before the display is brought up.
        
                (def cfg-btn-en (!= 0 (bitwise-and v 512)))
                (def cfg-show-modestrip (!= 0 (bitwise-and v 1024)))
                (def cfg-esc2-en (!= 0 (bitwise-and v 2048)))
                (def cfg-show-status (!= 0 (bitwise-and v 4096)))
                (def cfg-bms-demo (!= 0 (bitwise-and v 16384)))
        (def cfg-cruise-cancel (!= 0 (bitwise-and v 131072)))
        ; Bit 262144 is deliberately NOT read back into cfg-vb-en.
        ; show-bits never sets it - the flag lives in slot 109 - so
        ; reading it here always yielded false. Inside cfg-load that
        ; was invisible, because the cfg-keys loop restores slot 109
        ; a few lines later. Anywhere else it was destructive:
        ; layout-import calls set-show to merge a layout code, and
        ; every import quietly switched the controller link off, then
        ; the next save made it permanent.
                (def cfg-show-bmspage (!= 0 (bitwise-and v 32768)))
                (def cfg-auto-charge (!= 0 (bitwise-and v 65536)))
                (def cfg-splash (!= 0 (bitwise-and v 524288)))
                ; Stored inverted, so the bit means reverse is OFF. Every
                ; settings file written before this flag existed has a zero
                ; here, and reverse was always on then - read the usual way
                ; round, upgrading would quietly take it away.
                (def cfg-rev-en (= 0 (bitwise-and v 1048576)))
                (def cfg-simple (!= 0 (bitwise-and v 2097152)))
                (def cfg-show-main (= 0 (bitwise-and v 4194304)))
                (def cfg-show-s6   (= 0 (bitwise-and v 8388608)))
                (def cfg-show-s7   (= 0 (bitwise-and v 16777216)))
                (def cfg-show-s8   (= 0 (bitwise-and v 33554432)))
                (def cfg-show-dial (!= 0 (bitwise-and v 67108864)))
                true
        })
})

(def cfg-neg1 -1000001)   ; a stored -1, see cfg-save
(defun cfg-save () {
        (eeprom-store-i 0 cfg-magic)
        ; A flag past bit twenty six makes this negative, set-show then
        ; refuses the whole word and every other flag silently reverts. Say
        ; so rather than writing it, because the symptom otherwise looks
        ; nothing like the cause.
        (var sb (show-bits))
        (if (< sb 0)
            (print "show-bits overflowed 28 bits - a flag past bit 26 needs its own slot")
            (eeprom-store-i 19 sb))
        (eeprom-store-i 94 (if cfg-vertical 1 0))
        (eeprom-store-i 145 (if cfg-d-en 1 0))
        ; show-bits is full to bit 26, so these get their own slots rather
        ; than pushing that word negative and silently losing every flag
        (eeprom-store-i 149 (if cfg-ab-en 1 0))
        (trap (ab-mac-save))
        (eeprom-store-i 107 layout-ver)
        (loopforeach k cfg-keys {
                (var slot (ix k 0))
                (var kind (ix k 1))
                (var val (eval (ix k 2)))
                ; A real -1 is stored as cfg-neg1: -1 is what an unwritten
                ; slot reads, so load skipped it and a Common pin or third
                ; button set to -1 ("none") came back as the default pin.
                (if (eq kind 'f) (eeprom-store-f slot val)
                    (let ((iv (to-i val)))
                        (eeprom-store-i slot (if (= iv -1) cfg-neg1 iv))))
        })
        ; cfg-vb-en is a boolean sitting in an integer slot, and the loop
        ; above stores (to-i val) - which for true is 0, not 1. So saving it
        ; on wrote off, and loading off read back truthy because only nil is
        ; false here. The two cancelled out and direct Bluetooth was simply
        ; always on, whatever the settings page said. Written properly here,
        ; after the loop, and read back as a real boolean in cfg-load.
        (eeprom-store-i 109 (if cfg-vb-en 1 0))
        (eeprom-store-i 148 (if cfg-theme-all 1 0))
        (print (list "saved, vertical" cfg-vertical "style" cfg-style))
        true
})

(defun eeprom-flag (slot dflt) {
        ; Every stored boolean comes back through here. An unwritten slot
        ; reads as -1 on a board that has saved a config and as nil on one
        ; that has not reached that slot yet, and (= nil 1) throws - which
        ; kills cfg-load part way, and with it the rest of main. Reading a
        ; flag that was never written must give the compiled in default, not
        ; an exception.
        (var v (eeprom-read-i slot))
        (if (or (eq v nil) (= v -1)) dflt (= v 1))
})

;; Pins a button may use. The rest belong to the screen or the chip: the
;; backlight (1), touch (4, 8), USB (19, 20), the panel's QSPI (21, 39, 40,
;; 45, 47, 48) and the S3's flash and PSRAM (26-37). A button set on one of
;; those - the settings page takes 0-48 - drove the backlight or the panel's
;; bus as a button input or ground, and the screen went dark or dead with no
;; way back from the screen itself (review 2026-10-24).
(defun pin-free (p)
    (and (>= p 0) (<= p 48)
         (not (and (>= p 26) (<= p 37)))
         (not (or (= p 1) (= p 4) (= p 8) (= p 19) (= p 20) (= p 21)
                  (= p 39) (= p 40) (= p 45) (= p 47) (= p 48)))))

(defun cfg-load () {
        ; A never written cell reads nil, and comparing that to a number
        ; throws, so a virgin device must not reach the =. Returning false
        ; here is what makes main write the defaults out.
        (var m (eeprom-read-i 0))
        (if (and m (= m cfg-magic)) {
                (var bits (eeprom-read-i 19))
                (if (not (set-show bits))
                    (print (list "bad show-bits" bits "- using defaults")))
                ; orientation has its own slot: it reallocates the frame
                ; buffer, so it must never be set by a stray bitfield read
                (def cfg-vertical (eeprom-flag 94 cfg-vertical))
                (def cfg-d-en (eeprom-flag 145 cfg-d-en))
                (def cfg-ab-en (eeprom-flag 149 cfg-ab-en))
                (loopforeach k cfg-keys {
                        (var slot (ix k 0))
                        (var kind (ix k 1))
                        (var v (if (eq kind 'f) (eeprom-read-f slot)
                                                (eeprom-read-i slot)))
                        ; -1 is what an unwritten integer slot reads as. An unwritten
                        ; float slot's all-ones bits are a NaN, which passes every
                        ; range check below (any comparison with it is false) and
                        ; reached the backlight and the meters; a NaN is the one
                        ; value not equal to itself, so it is left out here, and
                        ; an infinity with it (review 2026-10-24)
                        (if (and v (not (eq kind 'f)) (= v cfg-neg1)) (setq v -1)
                            (if (and v (not (eq kind 'f)) (= v -1)) (setq v nil)))
                        (if (and v (if (eq kind 'f)
                                       (and (= v v) (< (abs v) 1.0e30))
                                       true))
                            (eval (list 'def (ix k 2) v)))
                })
                ; after the loop, which is what reads it
                (if (or (< cfg-ab-period 1.0) (> cfg-ab-period 120.0))
                    (def cfg-ab-period 5.0))
                ; guard against values written by an older slot layout
                (if (or (< cfg-mode-pos -1) (> cfg-mode-pos 8)) (def cfg-mode-pos -1))
                (if (or (< cfg-mode-size 20) (> cfg-mode-size 90)) (def cfg-mode-size 48))
                (if (or (< cfg-mode-dx -240) (> cfg-mode-dx 240)) (def cfg-mode-dx 0))
                (if (or (< cfg-mode-dy -240) (> cfg-mode-dy 240)) (def cfg-mode-dy 0))
                (if (or (< cfg-style 0) (> cfg-style 7)) (def cfg-style 0))
                (if (or (< cfg-p2-style 0) (> cfg-p2-style 2)) (def cfg-p2-style 0))
                (if (or (< cfg-vstyle 0) (> cfg-vstyle 7)) (def cfg-vstyle 0))
                (if (or (< cfg-icons 0) (> cfg-icons 1)) (def cfg-icons 1))
                (if (or (< cfg-lbl-main 0) (> cfg-lbl-main 3)) (def cfg-lbl-main 1))
                (if (or (< cfg-lbl-slot 0) (> cfg-lbl-slot 3)) (def cfg-lbl-slot 3))
                (if (or (< cfg-fs-sm 10) (> cfg-fs-sm 50)) (def cfg-fs-sm 22))
                (if (or (< cfg-fs-lg 20) (> cfg-fs-lg 90)) (def cfg-fs-lg 46))
                (if (or (< cfg-fs-xl 40) (> cfg-fs-xl 260)) (def cfg-fs-xl 124))
                (if (or (< cfg-fs-ring 16) (> cfg-fs-ring 110)) (def cfg-fs-ring 88))
                ; the icon face is built with the others, and a size it cannot be
                ; built at left no faces at all: a blank screen (the UI allows 14-48)
                (if (or (< cfg-icon-size 10) (> cfg-icon-size 60)) (def cfg-icon-size 26))
                (if (or (< cfg-font 0) (> cfg-font 1)) (def cfg-font 0))
                (if (or (< cfg-bg-col 0) (> cfg-bg-col 16777215)) (def cfg-bg-col 1976635))
                (if (or (< cfg-acc-col 0) (> cfg-acc-col 16777215)) (def cfg-acc-col 0))
                (if (or (< cfg-refresh 1.0) (> cfg-refresh 25.0)) (def cfg-refresh 25.0))
                (if (not (pin-free cfg-btn-up)) (def cfg-btn-up 15))
                (if (not (pin-free cfg-btn-dn)) (def cfg-btn-dn 16))
                (if (and (>= cfg-btn-3 0) (not (pin-free cfg-btn-3))) (def cfg-btn-3 6))
                (if (and (>= cfg-btn-gnd 0) (not (pin-free cfg-btn-gnd))) (def cfg-btn-gnd 7))
                ; an action index past the end would do nothing, so clamp
                (if (or (< cfg-btn-up-s 0) (> cfg-btn-up-s 31)) (def cfg-btn-up-s 1))
                (if (or (< cfg-btn-up-l 0) (> cfg-btn-up-l 31)) (def cfg-btn-up-l 0))
                (if (or (< cfg-btn-dn-s 0) (> cfg-btn-dn-s 31)) (def cfg-btn-dn-s 2))
                (if (or (< cfg-btn-dn-l 0) (> cfg-btn-dn-l 31)) (def cfg-btn-dn-l 0))
                (if (or (< cfg-btn-3-s 0) (> cfg-btn-3-s 31)) (def cfg-btn-3-s 4))
                (if (or (< cfg-btn-3-l 0) (> cfg-btn-3-l 31)) (def cfg-btn-3-l 6))
                (if (or (< cfg-whl-page 0) (> cfg-whl-page 2)) (def cfg-whl-page 1))
                ; a source past the table renders blank
                (if (or (< cfg-arc-src 0) (> cfg-arc-src 25)) (def cfg-arc-src 0))
                (if (or (< cfg-tl-src 0) (> cfg-tl-src 25)) (def cfg-tl-src 1))
                (if (or (< cfg-tr-src 0) (> cfg-tr-src 25)) (def cfg-tr-src 2))
                (if (or (< cfg-bl-src 0) (> cfg-bl-src 25)) (def cfg-bl-src 3))
                (if (or (< cfg-br-src 0) (> cfg-br-src 25)) (def cfg-br-src 4))
                (if (or (< cfg-bar-src 0) (> cfg-bar-src 25)) (def cfg-bar-src 5))
                (if (or (< cfg-bar-fill 0) (> cfg-bar-fill 25)) (def cfg-bar-fill 5))   ; 25 battery amps
                ; 4 is road mode, which main keeps over a restart; clamped to
                ; 3 here it came back as 1 and then as full power
                (if (or (< cfg-mode -1) (> cfg-mode 4)) (def cfg-mode 1))
                ; a bad duty here turns the backlight off, which looks exactly
                ; like a frozen display
                (if (or (< cfg-bl-day 0.05) (> cfg-bl-day 1.0)) (def cfg-bl-day 1.0))
                (if (or (< cfg-bl-night 0.05) (> cfg-bl-night 1.0)) (def cfg-bl-night 0.25))
                (if (or (< cfg-bl-step 2) (> cfg-bl-step 25)) (def cfg-bl-step 10))
                (if (or (< cfg-kid-mph 3.0) (> cfg-kid-mph 99.0)) (def cfg-kid-mph 26.0))
                (if (or (< cfg-kid-w 100.0) (> cfg-kid-w 30000.0)) (def cfg-kid-w 2000.0))
                (if (or (< cfg-m1-spd 1) (> cfg-m1-spd 200)) (def cfg-m1-spd 25))
                (if (or (< cfg-m2-spd 1) (> cfg-m2-spd 200)) (def cfg-m2-spd 45))
                (if (or (< cfg-m3-spd 1) (> cfg-m3-spd 200)) (def cfg-m3-spd 99))
                (if (or (< cfg-m1-brk 1) (> cfg-m1-brk 400)) (def cfg-m1-brk 30))
                (if (or (< cfg-d-mot 1) (> cfg-d-mot 400)) (def cfg-d-mot 30))
                (if (or (< cfg-d-bat 1) (> cfg-d-bat 400)) (def cfg-d-bat 12))
                (if (or (< cfg-d-spd 1) (> cfg-d-spd 200)) (def cfg-d-spd 25))
                (if (or (< cfg-d-brk 1) (> cfg-d-brk 400)) (def cfg-d-brk 30))
                ; cfg-vb-en is a boolean that lives in an integer slot, so it
                ; comes back as 0 or 1 - and 0 is truthy here, only nil is
                ; false. Left alone, direct Bluetooth could be switched on and
                ; never switched off again: the setting read back as zero and
                ; every (if cfg-vb-en ...) still took the true branch. Caught
                ; with a controller connected while the setting said off.
                ; Read from the slot rather than from whatever the cfg-keys
                ; loop left behind: a config written before slot 109 existed
                ; leaves a boolean here, and comparing that to 1 throws.
                (def cfg-vb-en (eeprom-flag 109 cfg-vb-en))
                (def cfg-theme-all (eeprom-flag 148 cfg-theme-all))
                (if (or (< cfg-walk-kph 2) (> cfg-walk-kph 12)) (def cfg-walk-kph 6))
                (if (or (< cfg-walk-duty 4) (> cfg-walk-duty 40))
                    (def cfg-walk-duty 18))
                ; a mode index from an older layout must not strand the
                ; rider in a road mode this build has turned off
                (if (and (= cfg-mode 4) (not cfg-d-en)) (def cfg-mode 1))
                (if (or (< cfg-m2-brk 1) (> cfg-m2-brk 400)) (def cfg-m2-brk 60))
                (if (or (< cfg-m3-brk 1) (> cfg-m3-brk 400)) (def cfg-m3-brk 90))
                (if (or (< cfg-chan 1) (> cfg-chan 13)) (def cfg-chan 1))

                ; One time migration. Earlier versions stored explicit screen
                ; positions for the strip and the mode chip; those were chosen
                ; before layouts could place them, so they now land on top of
                ; whatever the layout draws there. Reset just those three and
                ; leave every other setting alone.
                ; nil when saved by a version from before this slot existed,
                ; which is exactly the case the reset below is here to handle
                (var lv (eeprom-read-i 107))
                (if (or (not lv) (< lv layout-ver)) {
                        (def cfg-status-x -1)
                        (def cfg-status-y -1)
                        (def cfg-mode-pos -1)
                        (eeprom-store-i 107 layout-ver)
                        (print "placement reset to automatic")
                })

                ; One time migration. Refresh defaulted to eight until the
                ; draw loop became cheap enough for twenty five, and a board
                ; that saved its settings in between kept the eight: the
                ; bench unit drew at 7.95 frames a second while every
                ; measurement, which set twenty five first, said twenty four.
                ; Lift exactly the old default and nothing else - a rate
                ; somebody chose on purpose stays. Slot 153 is new, so it
                ; reads back empty on every save from before this.
                (var rv (eeprom-read-i 153))
                (if (or (not rv) (!= rv 1)) {
                        (if (= cfg-refresh 8.0) {
                                (def cfg-refresh 25.0)
                                (eeprom-store-f 31 cfg-refresh)
                                (print "refresh raised from the old default to 25")
                        })
                        (eeprom-store-i 153 1)
                })

; Backlight, 0..1. Night level is applied by the assignable action.

; Kids mode. Enter by holding top and bottom together, exit with five presses
; of the centre button inside four seconds, holding the last. Nothing is shown
; on screen either way.
                (print (list "loaded, vertical" cfg-vertical "bits" (show-bits)))
                true
        } {
                (if cfg-simple (cart-defaults))
                false
        })
})

; The console truncates a long line, and with ninety odd settings a single
; print no longer fits. Sent in chunks and reassembled by the settings page.
(defun cfg-dump () {
        (print (str-merge "CFG0:" (str-from-n cfg-arc-src "%d") "," (str-from-n cfg-arc-min "%.0f") "," (str-from-n cfg-arc-max "%.0f") "," (str-from-n cfg-tl-src "%d") "," (str-from-n cfg-tl-min "%.0f") "," (str-from-n cfg-tl-max "%.0f") "," (str-from-n cfg-tr-src "%d") "," (str-from-n cfg-tr-min "%.0f") "," (str-from-n cfg-tr-max "%.0f") "," (str-from-n cfg-bl-src "%d") "," (str-from-n cfg-bl-min "%.0f") "," (str-from-n cfg-bl-max "%.0f") "," (str-from-n cfg-br-src "%d") "," (str-from-n cfg-br-min "%.0f") "," (str-from-n cfg-br-max "%.0f") "," (str-from-n cfg-bar-src "%d") "," (str-from-n cfg-bar-fill "%d") "," (str-from-n cfg-bar-min "%.0f") "," (str-from-n cfg-bar-max "%.0f") "," (str-from-n cfg-unit-speed "%d")))
        (print (str-merge "CFG1:" (str-from-n cfg-unit-temp "%d") "," (str-from-n cfg-unit-dist "%d") "," (str-from-n (show-bits) "%d") "," (str-from-n (if cfg-vertical 1 0) "%d") "," (str-from-n cfg-fs-sm "%d") "," (str-from-n cfg-fs-lg "%d") "," (str-from-n cfg-fs-xl "%d") "," (str-from-n cfg-fs-ring "%d") "," (str-from-n cfg-refresh "%.0f") "," (str-from-n cfg-esc-id "%d") "," (str-from-n cfg-orient "%d") "," (str-from-n cfg-acc-tl "%d") "," (str-from-n cfg-acc-tr "%d") "," (str-from-n cfg-acc-bl "%d") "," (str-from-n cfg-acc-br "%d") "," (str-from-n cfg-acc-arc "%d") "," (str-from-n cfg-c-value "%d") "," (str-from-n cfg-c-unit "%d") "," (str-from-n cfg-m1-mot "%d") "," (str-from-n cfg-m1-bat "%d")))
        (print (str-merge "CFG2:" (str-from-n cfg-m2-mot "%d") "," (str-from-n cfg-m2-bat "%d") "," (str-from-n cfg-m3-mot "%d") "," (str-from-n cfg-m3-bat "%d") "," (str-from-n cfg-style "%d") "," (str-from-n cfg-vstyle "%d") "," (str-from-n cfg-icons "%d") "," (str-from-n cfg-lbl-main "%d") "," (str-from-n cfg-lbl-slot "%d") "," (str-from-n cfg-btn-up "%d") "," (str-from-n cfg-btn-dn "%d") "," (str-from-n cfg-btn-3 "%d") "," (str-from-n cfg-btn-up-s "%d") "," (str-from-n cfg-btn-up-l "%d") "," (str-from-n cfg-btn-dn-s "%d") "," (str-from-n cfg-btn-dn-l "%d") "," (str-from-n cfg-btn-3-s "%d") "," (str-from-n cfg-btn-3-l "%d") "," (str-from-n cfg-mode-pos "%d") "," (str-from-n cfg-mode-size "%d")))
        (print (str-merge "CFG3:" (str-from-n cfg-mode-dx "%d") "," (str-from-n cfg-mode-dy "%d") "," (str-from-n cfg-esc2-id "%d") "," (str-from-n cfg-chan "%d") "," (str-from-n cfg-status-x "%d") "," (str-from-n cfg-status-y "%d") "," (str-from-n cfg-p2-style "%d") "," (str-from-n cfg-acc-batt "%d") "," (str-from-n cfg-s6-src "%d") "," (str-from-n cfg-s6-min "%.0f") "," (str-from-n cfg-s6-max "%.0f") "," (str-from-n cfg-s7-src "%d") "," (str-from-n cfg-s7-min "%.0f") "," (str-from-n cfg-s7-max "%.0f") "," (str-from-n cfg-s8-src "%d") "," (str-from-n cfg-s8-min "%.0f") "," (str-from-n cfg-s8-max "%.0f") "," (str-from-n cfg-acc-s6 "%d") "," (str-from-n cfg-acc-s7 "%d") "," (str-from-n cfg-acc-s8 "%d")))
        (print (str-merge "CFG4:" (str-from-n cfg-bl-day "%.2f") "," (str-from-n cfg-bl-night "%.2f") "," (str-from-n cfg-kid-mph "%.0f") "," (str-from-n cfg-kid-w "%.0f") "," (str-from-n cfg-m1-spd "%d") "," (str-from-n cfg-m2-spd "%d") "," (str-from-n cfg-m3-spd "%d") "," (str-from-n cfg-m1-brk "%d") "," (str-from-n cfg-m2-brk "%d") "," (str-from-n cfg-m3-brk "%d") "," (str-from-n cfg-bl-step "%d") "," (str-from-n cfg-font "%d") "," (str-from-n cfg-bg-col "%d") "," (str-from-n cfg-acc-col "%d") "," (str-from-n cfg-d-mot "%d") "," (str-from-n cfg-d-bat "%d") "," (str-from-n cfg-d-spd "%d") "," (str-from-n cfg-d-brk "%d") "," (str-from-n (if cfg-d-en 1 0) "%d") "," (str-from-n (if cfg-theme-all 1 0) "%d") "," (str-from-n (if cfg-vb-en 1 0) "%d")))
        ; 101 on: added since. A settings page from before reads its 101.
        ; appended, so every earlier index stays where the page expects it
        (print (str-merge "CFG5:" (str-from-n cfg-whl-page "%d") "," (str-from-n cfg-btn-gnd "%d") "," (str-from-n cfg-icon-size "%d")))
        true
})

@const-end
