; Controller-owned forward power/speed editor. Motor current scales occupy
; base-modes indices 5/8/11; speed in km/h uses 4/7/10, shared by iOS/QML.
; No local EEPROM copy, no native-controller fallback and no write retries.
@const-start
(def pm-open nil) (def pm-mode 0) (def pm-field 0) (def pm-current -1) (def pm-value 0)
(def pm-base -1) (def pm-dirty nil) (def pm-owner nil) (def pm-token 0)
(def pm-pending 0) (def pm-sent 0) (def pm-heard 0) (def pm-query 0)
(def pm-read-retries 0)
(def pm-note "Read the package")
(defun pm-context () (cond
    ((link-carries) (list 1 link-mac cfg-esc-id link-on-t0))
    ((and cfg-vb-en vb-linked (not vb-stale) (< (secs-since vb-last) 2.0))
        (list 2 cfg-vb-mac vb-fwd vb-up))
    (t nil)))
(defun pm-live () (and pm-owner (eq pm-owner (pm-context)) (> pm-heard 0)
    (< (secs-since pm-heard) 4.0) (>= pm-current 0)))
(defun pm-request (write) (if (and pm-owner (eq pm-owner (pm-context)) (= pm-pending 0)) {
    (def pm-token (mod (+ pm-token 1) 256))
    (var b (bufcreate 9))
    (bufset-u8 b 0 (if (= (ix pm-owner 0) 1) 0xC7 36))
    (bufset-u8 b 1 0x57) (bufset-u8 b 2 0x32) (bufset-u8 b 3 pm-token)
    (bufset-u8 b 4 (+ pm-mode pm-field (if write 128 0)))
    (bufset-u16 b 5 (if write pm-value 0)) (bufset-u16 b 7 (if write pm-base 0))
    (def pm-pending (if write 2 1)) (def pm-sent (systime)) (def pm-query (systime))
    (if (= (ix pm-owner 0) 1) (link-send b) (vb-send b))
    (free b)
}))
(defun pm-read () {
    (def pm-owner (pm-context)) (def pm-pending 0) (def pm-heard 0)
    (def pm-current -1) (def pm-dirty nil) (def pm-base -1) (def pm-read-retries 0)
    (def pm-note (if pm-owner "Reading package..." "Connect to controller"))
    (pm-request nil)
})
(defun pm-open-page () {
    (def quick-open t) (def pm-open t) (def pm-mode 0) (def pm-field 0) (pm-read)
})
(defun pm-receive (b off via) (if (and pm-open (> pm-pending 0) pm-owner
    (= via (ix pm-owner 0)) (eq pm-owner (pm-context)) (< (secs-since pm-sent) 2.0)
    (>= (buflen b) (+ off 8)) (= (bufget-u8 b off) 0x57)
    (= (bufget-u8 b (+ off 1)) 0xB0) (= (bufget-u8 b (+ off 2)) pm-token)
    (= (bitwise-and (bufget-u8 b (+ off 3)) 15) (+ pm-mode pm-field))
    (= (bufget-u8 b (+ off 6)) 1) (= (bufget-u8 b (+ off 7)) 0)
    (>= (bufget-u16 b (+ off 4)) (if (= pm-field 4) 100 0))
    (<= (bufget-u16 b (+ off 4)) (if (= pm-field 4) 25000 10000))) {
    (var status (bitwise-and (bufget-u8 b (+ off 3)) 240))
    (if (member status '(0 16 32 48)) {
        (def pm-current (bufget-u16 b (+ off 4))) (def pm-heard (systime))
        (def pm-read-retries 0)
        (if (= pm-pending 2) {
            (if (and (= status 0) (= pm-current pm-value)) {
                (def pm-dirty nil) (def pm-base pm-current) (def pm-note "Saved in package")
            } (def pm-note (cond ((= status 16) "Changed elsewhere / Reload")
                ((= status 32) "Stop and select Neutral") (t "Save not confirmed / Reload"))))
        } {
            (if (not pm-dirty) {
                (def pm-value pm-current) (def pm-base pm-current)
                (if (not-eq pm-note "Saved in package") (def pm-note "Package values synced"))
            } (if (!= pm-current pm-base) (def pm-note "Changed elsewhere / Reload")))
        })
        (def pm-pending 0)
    })
}))
(defun pm-adjust (delta) (if (and (pm-live) (!= pm-pending 2)) {
    (def pm-value (clampx (+ pm-value delta) (if (= pm-field 4) 100 0)
                                               (if (= pm-field 4) 25000 10000)))
    (def pm-dirty (!= pm-value pm-base))
    (def pm-note (if pm-dirty "Unsaved / Save this mode" "Package values synced"))
}))
(defun pm-select-field (field) (if (or pm-dirty (= pm-pending 2))
    (def pm-note "Save or Reload first")
    { (def pm-field field) (pm-read) }))
(defun pm-step (direction) {
    (var delta (* direction 100))
    (if (and (= pm-field 4) (= cfg-unit-speed 0)) {
        ; Step the displayed hundredths of MPH, then round once to 0.01 KPH.
        ; Repeated +1 MPH presses must not accumulate a rounded 1.61 KPH step.
        (var mph100 (to-i (+ 0.5 (/ (* (to-float pm-value) 100.0) 160.9344))))
        (setq delta (- (to-i (+ 0.5 (* (+ mph100 (* direction 100)) 1.609344))) pm-value))
    })
    (pm-adjust delta)
})
(defun pm-value-text () (cond
    ((< pm-current 0) "--")
    ((= pm-field 0) (str-from-n (/ (to-float pm-value) 100.0) "%.2f%%"))
    ((>= pm-value 25000) "Controller max")
    (t (str-merge (str-from-n (/ (to-float pm-value)
            (if (= cfg-unit-speed 0) 160.9344 100.0)) "%.2f")
        (if (= cfg-unit-speed 0) " MPH" " KPH")))))
(defun pm-save () (cond
    ((or (not (pm-live)) (> pm-pending 0)) (def pm-note "Wait for package / Reload"))
    ((not pm-dirty) nil)
    ((!= pm-current pm-base) (def pm-note "Changed elsewhere / Reload"))
    ((or (!= cfg-mode 0) (> (abs d-speed) 0.5) (setup-locked) (hall-locked))
        (def pm-note "Stop and select Neutral"))
    (t { (def pm-note "Saving / reading back...") (pm-request t) })))
(defun pm-tick () (if pm-open {
    (cond
        ((not (eq pm-owner (pm-context))) {
            (def pm-pending 0) (def pm-heard 0) (def pm-current -1)
            (def pm-note "Connection changed / Reload")
        })
        ((and (> pm-pending 0) (> (secs-since pm-sent) 2.0)) {
            ; Retry only reads, with a new token. A lost save acknowledgement
            ; stays unconfirmed and cannot trigger another write or a read retry.
            (if (and (= pm-pending 1) (< pm-read-retries 2)) {
                (def pm-read-retries (+ pm-read-retries 1))
                (def pm-pending 0) (def pm-heard 0)
                (def pm-note "Retrying package read...") (pm-request nil)
            } {
                (def pm-note (if (= pm-pending 2) "Save unconfirmed / Reload" "No package reply / Reload"))
                (def pm-pending 0) (def pm-heard 0)
            })
        })
        ((and (= pm-pending 0) (> pm-heard 0) (> (secs-since pm-query) 2.0)) (pm-request nil)))
}))
(defun pm-button (x y w h label color) {
    (rbox x y w h 8 color)
    (txt-c (+ x (/ w 2)) (base-c font-ui (+ y (/ h 2))) 0xFFFFFF font-ui label)
})
; This is the screen's existing mode-chip preference, shared with screen QML.
; Hiding the control never changes the controller's selected mode or limits.
(defun pm-toggle-display () {
    (def cfg-show-modestrip (not cfg-show-modestrip))
    (eeprom-store-i 19 (show-bits))
    (fb-redraw)
})
(defun draw-power-modes () {
    (if (!= tc-mode 2) (img-clear fb theme-bg))
    (pm-button 12 6 76 40 "BACK" 0x303640)
    (var heading-font (if (< fb-w 400) font-sm font-ui))
    (txt 100 (base-c heading-font 26) 0xFFFFFF heading-font "POWER MODES")
    (pm-button (- fb-w 76) 6 64 40 (if cfg-show-modestrip "ON" "OFF")
        (if cfg-show-modestrip 0x166534 0x303640))
    (var w (/ (- fb-w 40) 3))
    (looprange i 0 3 (pm-button (+ 12 (* i (+ w 8))) 58 w 42
        (str-merge "MODE " (str-from-n (+ i 1) "%d")) (if (= i pm-mode) 0x006CA8 0x20262E)))
    (var half (/ (- fb-w 32) 2))
    (pm-button 12 108 half 32 "POWER" (if (= pm-field 0) 0x006CA8 0x20262E))
    (pm-button (+ 20 half) 108 half 32 "SPEED" (if (= pm-field 4) 0x006CA8 0x20262E))
    (txt-c (/ fb-w 2) (base-c font-ui 156) 0x9CA3AF font-ui
        (if (= pm-field 4) "Speed limit" "Motor current percent"))
    (pm-button 12 174 64 44 "LESS" (if (pm-live) 0x303640 0x14181E))
    (pm-button (- fb-w 76) 174 64 44 "MORE" (if (pm-live) 0x303640 0x14181E))
    (txt-c (/ fb-w 2) (base-c font-ui 196) 0xFFFFFF font-ui (pm-value-text))
    (txt-c (/ fb-w 2) (base-c font-ui 240) 0x9CA3AF font-ui pm-note)
    (pm-button 12 (- fb-h 54) (/ (- fb-w 36) 2) 42 "RELOAD" 0x303640)
    (pm-button (+ 24 (/ (- fb-w 36) 2)) (- fb-h 54) (/ (- fb-w 36) 2) 42 "SAVE MODE"
        (if (and (pm-live) pm-dirty (= pm-pending 0)) 0x006CA8 0x20262E))
})
(defun pm-hit (x y) {
    (var w (/ (- fb-w 40) 3))
    (cond
        ((setup-inside x y 12 6 76 40) (if (= pm-pending 2)
            (def pm-note "Waiting for save readback")
            { (def pm-open nil) (def pm-pending 0) (def pm-owner nil) }))
        ((setup-inside x y (- fb-w 76) 6 64 40) (pm-toggle-display))
        ((and (>= y 58) (< y 100)) {
            (looprange i 0 3 (if (setup-inside x y (+ 12 (* i (+ w 8))) 58 w 42)
                (if (or pm-dirty (= pm-pending 2)) (def pm-note "Save or Reload first")
                    { (def pm-mode i) (pm-read) })))
        })
        ((and (>= y 108) (< y 140)) (pm-select-field (if (< x (/ fb-w 2)) 0 4)))
        ((setup-inside x y 12 174 64 44) (pm-step -1))
        ((setup-inside x y (- fb-w 76) 174 64 44) (pm-step 1))
        ((and (>= y (- fb-h 54)) (< y (- fb-h 12)) (!= pm-pending 2))
            (if (< x (/ fb-w 2)) (pm-read) (pm-save))))
})
@const-end
