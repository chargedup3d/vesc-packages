; Short offline FAQ. These handlers only change screen navigation.
@const-start
(def help-topic -1) (def help-index 0) (def help-top 0)
(def help-key nil) (def help-lines nil)
(def help-book '(
    ("How do I connect my VESC?"
        "Hold the dashboard to open Quick Settings. Tap CONTROLLER then SCAN and choose your VESC. It needs compatible Bluetooth. If it is missing check controller power and disconnect any phone using its Bluetooth.")
    ("Why are modes locked?"
        "Editing power and speed needs a compatible Charged Up package. Stop and select Neutral before SAVE MODE. No package reply? Check the connection and tap RELOAD. Available VESC readings still work without the package.")
    ("Why is there no VESC data?"
        "Check power to the controller and wait for it to connect. Open Quick Settings then CONTROLLER to check the selected VESC. Disconnect any phone using its Bluetooth and tap RECONNECT. SCAN lets you choose another VESC.")
    ("What does Cart Mode do?"
        "Cart Mode hides CU Wheelie and bike-only setup and actions. It keeps controller readings and selects the Cart theme by default. You can choose another theme without turning Cart Mode off.")
    ("How do I change themes?"
        "Connect the screen to VESC Tool and open the CU Dash package settings. Choose a layout under Layout or change colours under Appearance. Cart Mode stays on when you change the look.")
    ("Why is the screen dim?"
        "Hold the dashboard to open Quick Settings and tap BRIGHTER. Day and night brightness are saved separately. If NIGHT is shown you are adjusting the night level. The screen remembers your brightness after restart.")
))
(defun help-active () (and (= page (pg-setup)) (= setup-view 10)))
(defun help-step () (/ (- fb-h 100) 6))
(defun help-rows () (if (< help-topic 0) 6 (/ (- fb-h 124) 24)))
(defun help-total () (if (< help-topic 0) (length help-book) (length help-lines)))
(defun help-offset () 0)
(defun help-last () 0)
(defun help-prepare () (if (>= help-topic 0) {
    (var key (list help-topic fb-w cfg-font))
    (if (not-eq key help-key) {
        (var lines nil)
        (var line "")
        (loopforeach word (str-split (ix (ix help-book help-topic) 1) " ") {
            (var joined (if (= (str-len line) 0) word (str-merge line " " word)))
            (if (and (> (str-len line) 0) (> (ix (tdim-k font-ui joined) 0) (- fb-w 32))) {
                (setq lines (cons line lines)) (setq line word)
            } (setq line joined))
        })
        (def help-lines (reverse (cons line lines))) (def help-key key)
    })
}))
(defun help-open-page () (if (or (setup-locked) (hall-locked)) (setup-back) {
    (def setup-view 10) (def help-topic -1) (def help-index 0) (def help-top 0)
    (def help-key nil) (def help-lines nil) (def fb-dirty true)
}))
(defun help-back () {
    (if (>= help-topic 0) (def help-topic -1) (def setup-view 0))
    (def help-key nil) (def help-lines nil) (def fb-dirty true)
})
; Consume swipes so they cannot accidentally change the dashboard page.
(defun help-scroll (direction) nil)
(defun help-gesture (dx dy) nil)
(defun help-draw-sig () (list 'faq help-topic fb-w fb-h cfg-font))
(defun draw-help () {
    (help-prepare) (img-clear fb theme-bg)
    (setup-button 12 6 80 "BACK" 0x303640)
    (txt 104 (base-c font-ui 24) 0xFFFFFF font-ui "HELP")
    (if (< help-topic 0) {
        (looprange i 0 (length help-book) {
            (var y (+ 60 (* i (help-step))))
            (var h (- (help-step) 4))
            (rbox 12 y (- fb-w 24) h 6 0x20262E)
            (txt 22 (base-c font-ui (+ y (/ h 2))) 0xFFFFFF font-ui (car (ix help-book i)))
        })
        (txt 12 (base-c font-ui (- fb-h 20)) 0x9CA3AF font-ui "Tap a question")
    } {
        (txt 12 (base-c font-ui 66) 0x38BDF8 font-ui (car (ix help-book help-topic)))
        (looprange i 0 (length help-lines)
            (txt 16 (base-c font-ui (+ 106 (* i 24))) 0xFFFFFF font-ui (ix help-lines i)))
    })
})
(defun help-hit (x y) {
    (cond
        ((setup-inside x y 12 6 80 36) (setup-back))
        ((< help-topic 0) (looprange i 0 (length help-book) {
            (if (setup-inside x y 12 (+ 60 (* i (help-step))) (- fb-w 24) (- (help-step) 4)) {
                (def help-topic i) (def help-key nil) (def fb-dirty true)
            })
        }))
    )
})
@const-end
