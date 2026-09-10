// =====================================================================
//  BITE-OS "fluid" greeter
//
//  Motion ported from the Serpantinum (ilyamiro) OVERLAY family --
//  screenshot region select, Floating/quickactions, Network/Volume popups.
//
//  Vocabulary:
//    - Easing.OutExpo, 350-600ms, is the primary curve. Geometry glides.
//    - Direct manipulation is INSTANT; indirect change is animated.
//    - A selection box snaps between targets, follows the mouse, and
//      everything outside it dims -- region-select, reused as login focus.
//    - Liquid fill: one shared wave phase, bezier surface, clipped card.
// =====================================================================
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#11111b"

    // ---------------------------------------------------------------
    // Theme
    // ---------------------------------------------------------------
    function cfg(key, fallback) {
        var v = config[key]
        return (v !== undefined && v !== null && String(v).length > 0) ? String(v) : fallback
    }

    readonly property color cBase:     "#11111b"
    readonly property color cMantle:   "#181825"
    readonly property color cSurface0: "#313244"
    readonly property color cSurface1: "#45475a"
    readonly property color cSurface2: "#585b70"
    readonly property color cText:     "#cdd6f4"
    readonly property color cSubtext:  "#a6adc8"
    readonly property color cOverlay:  "#6c7086"
    readonly property color cAccent:   cfg("accent", "#b48aff")
    readonly property color cBlue:     "#89b4fa"
    readonly property color cGreen:    "#a6e3a1"
    readonly property color cPeach:    "#fab387"
    readonly property color cRed:      "#f38ba8"
    readonly property color cTeal:     "#94e2d5"
    readonly property color cBurp:     "#e8c547"

    readonly property string mono: cfg("fontFamily", "JetBrains Mono")

    readonly property real scaleFactor: height / 1080
    function s(v) { return Math.round(v * root.scaleFactor) }

    // ---------------------------------------------------------------
    // LOGIN PLUMBING
    //
    // lastUser is EMPTY on a fresh install (sddm has no state yet), so fall
    // back to the first real account in userModel -- without this,
    // sddm.login() is called with "" and every password is rejected.
    // DO NOT remove this fallback.
    // ---------------------------------------------------------------
    readonly property string defaultUser: (userModel.lastUser && userModel.lastUser.length > 0)
        ? userModel.lastUser
        : (userModel.count > 0
            ? String(userModel.data(userModel.index(Math.max(0, userModel.lastIndex), 0), Qt.UserRole + 1) || "")
            : "")

    property int userIndex: -1

    readonly property string loginUser: (userIndex >= 0 && userIndex < userModel.count)
        ? String(userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1) || defaultUser)
        : defaultUser

    readonly property bool multiUser: userModel.count > 1

    property int sessionIndex: sessionModel.lastIndex

    // SDDM's SessionModel roles run Directory, File, Type, Name, Exec, Comment
    // from Qt.UserRole+1, so the name is UserRole+4. DisplayRole returns
    // undefined here, which produced "Unable to assign [undefined] to QString".
    readonly property int sessionNameRole: Qt.UserRole + 4

    function nameOfSession(i) {
        if (i < 0 || i >= sessionModel.count) return "session"
        var idx = sessionModel.index(i, 0)
        var v = sessionModel.data(idx, root.sessionNameRole)
        if (v === undefined || v === null || String(v).length === 0)
            v = sessionModel.data(idx, Qt.DisplayRole)
        return (v === undefined || v === null || String(v).length === 0) ? "session" : String(v)
    }

    readonly property string sessionName: nameOfSession(sessionIndex)

    function currentUserRow() {
        if (root.userIndex >= 0) return root.userIndex
        for (var i = 0; i < userModel.count; i++) {
            if (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) === root.defaultUser)
                return i
        }
        return 0
    }

    function cycleUser(delta) {
        if (!root.multiUser || root.busy || root.isUnlocking) return
        var n = userModel.count
        root.userIndex = ((currentUserRow() + delta) % n + n) % n
        pwInput.text = ""
        root.errorText = ""
    }

    function cycleSession(delta) {
        if (root.busy || root.isUnlocking) return
        var n = sessionModel.count
        if (n <= 0) return
        root.sessionIndex = ((root.sessionIndex + delta) % n + n) % n
    }

    property bool busy: false
    property bool revealed: false

    // idle = nothing typed for a moment; ambient bubbles only drift up then
    property bool idle: false
    Timer {
        id: idleTimer
        interval: 1800
        onTriggered: root.idle = true
    }
    function poke() { root.idle = false; idleTimer.restart() }

    // ---- failure escalation ----
    readonly property int maxFails: 5
    property bool lockedOut: false
    property int lockRemaining: 0
    readonly property int lockSeconds: 120
    property real failLevel: 0.0          // the wrong-tries bar, 0..1
    Behavior on failLevel { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

    property real spill: 0.0              // 1 while the bottle dumps its contents
    property bool exploded: false

    function resetFailures() {
        root.failCount = 0
        root.failLevel = 0
        root.lockedOut = false
        root.exploded = false
        root.lockRemaining = 0
    }

    Timer {
        id: lockTimer
        interval: 1000
        repeat: true
        running: root.lockedOut
        onTriggered: {
            root.lockRemaining -= 1
            if (root.lockRemaining <= 0) root.resetFailures()
        }
    }

    // failures also age out on their own
    Timer {
        interval: 120000
        repeat: true
        running: root.failCount > 0 && !root.lockedOut
        onTriggered: if (!root.lockedOut) root.resetFailures()
    }
    property string errorText: ""
    property int failCount: 0

    function doLogin() {
        if (root.busy || root.isUnlocking || root.isPlayingIntro || root.lockedOut) return
        if (pwInput.text.length === 0) { shakeAnim.restart(); return }
        root.errorText = ""
        root.busy = true
        sddm.login(root.loginUser, pwInput.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failCount += 1
            root.failLevel = Math.min(1, root.failCount / root.maxFails)
            root.errorText = "WRONG"
            pwInput.text = ""
            spillAnim.restart()
            shakeAnim.restart()
            if (root.failCount >= root.maxFails) {
                root.exploded = true
                explodeAnim.restart()
            }
        }
        function onLoginSucceeded() {
            root.busy = false
            root.errorText = ""
            root.resetFailures()
            root.isUnlocking = true
            outroSequence.restart()
        }
    }

    // ---------------------------------------------------------------
    // OVERLAY STATE
    // ---------------------------------------------------------------
    property real reveal: 0.0
    property real contentReveal: 0.0
    property real mainOpacity: 1.0

    property bool isPlayingIntro: true
    property bool isUnlocking: false
    property bool animateChanges: false

    readonly property bool fxLive: root.contentReveal > 0.98 && !root.isUnlocking && !root.reduceMotion

    SequentialAnimation {
        id: introSequence
        running: true
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "reveal"
                from: 0.0; to: 1.0; duration: 600; easing.type: Easing.OutExpo
            }
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                NumberAnimation {
                    target: root; property: "contentReveal"
                    from: 0.0; to: 1.0; duration: 500; easing.type: Easing.OutExpo
                }
            }
        }
        PropertyAction { target: root; property: "isPlayingIntro"; value: false }
        ScriptAction {
            script: {
                root.bumpGeom()
                root.animateChanges = true
                pwInput.forceActiveFocus()
            }
        }
    }

    SequentialAnimation {
        id: outroSequence
        ScriptAction { script: root.animateChanges = false }
        ParallelAnimation {
            NumberAnimation { target: root; property: "contentReveal"; to: 0.0; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "reveal";        to: 0.0; duration: 350; easing.type: Easing.OutExpo }
            NumberAnimation { target: root; property: "mainOpacity";   to: 0.0; duration: 300; easing.type: Easing.InQuad }
        }
    }

    // ---------------------------------------------------------------
    // SHARED WAVE PHASE  (drives every liquid surface)
    // ---------------------------------------------------------------
    property real globalWavePhase: 0.0
    NumberAnimation on globalWavePhase {
        from: 0; to: Math.PI * 2
        duration: 1800
        loops: Animation.Infinite
        running: root.fxLive
    }

    // Reveal staggering. Toggling reveal replays every character from the
    // start; typing a new one while revealed lets it surface immediately.
    property int revealBase: 0

    // washes the box out when the characters go back under
    property real cleanProg: 0.0
    NumberAnimation {
        id: cleanAnim
        target: root; property: "cleanProg"
        from: 0.0; to: 1.0
        duration: 1100
        easing.type: Easing.InOutSine
    }

    onRevealedChanged: {
        if (revealed) revealBase = 0
        else cleanAnim.restart()
    }

    // ---- settings (session-local; the greeter has nowhere to persist) ----
    property bool settingsOpen: false
    property bool userListOpen: false

    function pickUser(row) {
        root.userIndex = row
        root.userListOpen = false
        pwInput.text = ""
        root.errorText = ""
    }
    property bool revealWave: true      // wave = one character at a time
    property int  revealStagger: 220    // ms between characters
    property bool showGauges: true
    property bool dimOutside: true
    property bool ambientFx: true       // idle soap bubbles + glow pulses
    property bool reduceMotion: false   // kill continuous repaints

    // ---------------------------------------------------------------
    // SYSTEM STATS
    //
    // The greeter has no process API, so these come from /proc via QML's
    // XMLHttpRequest. Qt6 gates file:// reads behind QML_XHR_ALLOW_FILE_READ,
    // so without that in sddm's environment the CPU/RAM gauges simply read
    // "n/a" and sit empty -- nothing else in the theme depends on them.
    // ---------------------------------------------------------------
    property bool statsOk: false
    property real cpuLevel: 0.0
    property real ramLevel: 0.0
    property real ramUsedGb: 0.0
    property real ramTotalGb: 0.0

    property var _prevCpu: null

    function readFile(path, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE) {
                cb((x.responseText && x.responseText.length > 0) ? x.responseText : null)
            }
        }
        try { x.open("GET", "file://" + path); x.send(null) } catch (e) { cb(null) }
    }

    function sampleStats() {
        readFile("/proc/stat", function(txt) {
            if (!txt) return
            var line = txt.split("\n")[0].trim().split(/\s+/)
            if (line.length < 5) return
            var idle = parseInt(line[4], 10) + (line.length > 5 ? parseInt(line[5], 10) : 0)
            var total = 0
            for (var i = 1; i < line.length; i++) {
                var v = parseInt(line[i], 10)
                if (!isNaN(v)) total += v
            }
            if (root._prevCpu) {
                var dt = total - root._prevCpu.total
                var di = idle - root._prevCpu.idle
                if (dt > 0) {
                    root.cpuLevel = Math.max(0, Math.min(1, (dt - di) / dt))
                    root.statsOk = true
                }
            }
            root._prevCpu = { total: total, idle: idle }
        })

        readFile("/proc/meminfo", function(txt) {
            if (!txt) return
            var totalKb = 0, availKb = 0
            var lines = txt.split("\n")
            for (var i = 0; i < lines.length && (totalKb === 0 || availKb === 0); i++) {
                if (lines[i].indexOf("MemTotal:") === 0)
                    totalKb = parseInt(lines[i].replace(/[^0-9]/g, ""), 10)
                else if (lines[i].indexOf("MemAvailable:") === 0)
                    availKb = parseInt(lines[i].replace(/[^0-9]/g, ""), 10)
            }
            if (totalKb > 0) {
                root.ramTotalGb = totalKb / 1048576
                root.ramUsedGb = (totalKb - availKb) / 1048576
                root.ramLevel = Math.max(0, Math.min(1, (totalKb - availKb) / totalKb))
                root.statsOk = true
            }
        })
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.fxLive
        triggeredOnStart: true
        onTriggered: root.sampleStats()
    }


    // SDDM's KeyboardModel is an X11/XKB component. On a Wayland greeter it
    // reports enabled=false with zero layouts, so the theme cannot list or
    // switch layouts through it -- verified against the running greeter.
    // The layouts themselves are configured system-wide in vconsole.conf and
    // toggled by XKB itself (grp:alt_shift_toggle), below SDDM entirely.
    readonly property bool kbApiWorks: (typeof keyboard !== "undefined")
                                       && keyboard.enabled
                                       && keyboard.layouts
                                       && keyboard.layouts.length > 1

    property var xkbLayouts: []
    property string xkbToggle: ""

    function applyXkb(layouts, options) {
        if (layouts && layouts.length > 0 && root.xkbLayouts.length === 0) {
            var out = []
            for (var i = 0; i < layouts.length; i++) {
                var s = String(layouts[i]).trim()
                if (s.length > 0) out.push(s)
            }
            if (out.length > 0) root.xkbLayouts = out
        }
        if (options && root.xkbToggle.length === 0) {
            var o = String(options)
            if (o.indexOf("alt_shift") !== -1)       root.xkbToggle = "alt+shift"
            else if (o.indexOf("ctrl_shift") !== -1) root.xkbToggle = "ctrl+shift"
            else if (o.indexOf("toggle") !== -1)     root.xkbToggle = "grp toggle"
        }
    }

    // KEY=value files: /etc/vconsole.conf, /etc/default/keyboard
    function parseEnvStyle(txt) {
        var lines = txt.split("\n")
        var lay = null, opt = null
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i].trim()
            if (ln.length === 0 || ln.charAt(0) === "#") continue
            if (ln.indexOf("XKBLAYOUT=") === 0)
                lay = ln.substring(10).replace(/["']/g, "").split(",")
            else if (ln.indexOf("XKBOPTIONS=") === 0)
                opt = ln.substring(11).replace(/["']/g, "")
        }
        root.applyXkb(lay, opt)
    }

    // xorg InputClass: Option "XkbLayout" "us,il"
    function parseXorgStyle(txt) {
        var lay = null, opt = null
        var mL = txt.match(/Option\s+"XkbLayout"\s+"([^"]*)"/)
        if (mL) lay = mL[1].split(",")
        var mO = txt.match(/Option\s+"XkbOptions"\s+"([^"]*)"/)
        if (mO) opt = mO[1]
        root.applyXkb(lay, opt)
    }

    // Read whatever this machine actually uses. Nothing here is specific to
    // any language -- the layouts come from the system's own config, in the
    // order systemd/xorg would consult them. First file that answers wins.
    function readKeyboardConf() {
        readFile("/etc/vconsole.conf", function(txt) {
            if (txt) root.parseEnvStyle(txt)
            readFile("/etc/X11/xorg.conf.d/00-keyboard.conf", function(t2) {
                if (t2) root.parseXorgStyle(t2)
                readFile("/etc/default/keyboard", function(t3) {
                    if (t3) root.parseEnvStyle(t3)
                })
            })
        })
    }

    readonly property int kbCount: root.kbApiWorks
                                   ? keyboard.layouts.length
                                   : root.xkbLayouts.length

    readonly property string kbLayout: {
        if (typeof keyboard !== "undefined" && keyboard.layouts && keyboard.layouts.length > 0)
            return String(keyboard.layouts[keyboard.currentLayout].shortName).toUpperCase()
        if (root.xkbLayouts.length > 0)
            return String(root.xkbLayouts[0]).toUpperCase()
        return "--"        // unknown: do not invent a layout
    }

    // fraction of the day elapsed -- the TIME gauge's fill
    readonly property real dayLevel: (clock.now.getHours() * 3600
                                      + clock.now.getMinutes() * 60
                                      + clock.now.getSeconds()) / 86400

    // ---------------------------------------------------------------
    // FOCUS SELECTION  (glides between targets, and follows the mouse)
    // ---------------------------------------------------------------
    property int focusIndex: 1
    property int powerIndex: 0
    readonly property var focusables: [userChip, pwWrap, sessionChip, powerRow]
    readonly property var focusLabels: ["user", "password", "session", "power"]
    readonly property Item currentItem: focusables[focusIndex] ? focusables[focusIndex] : null

    property int geomRevision: 0
    function bumpGeom() { root.geomRevision++ }
    onWidthChanged: bumpGeom()
    onHeightChanged: bumpGeom()

    readonly property real selPad: s(12)

    function rectOf(it) {
        var _dep = root.geomRevision
        if (!it || it.width <= 0) return Qt.rect(0, 0, 0, 0)
        var p = it.mapToItem(selLayer, 0, 0)
        return Qt.rect(p.x - root.selPad, p.y - root.selPad,
                       it.width + root.selPad * 2, it.height + root.selPad * 2)
    }

    property real selX: rectOf(currentItem).x
    property real selY: rectOf(currentItem).y
    property real selW: rectOf(currentItem).width
    property real selH: rectOf(currentItem).height

    Behavior on selX { enabled: root.animateChanges; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on selY { enabled: root.animateChanges; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on selW { enabled: root.animateChanges; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
    Behavior on selH { enabled: root.animateChanges; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

    // Mouse attraction: hovering a target pulls the box to it.
    function attract(i) {
        if (root.busy || root.isUnlocking || root.isPlayingIntro) return
        root.focusIndex = i
    }

    function moveFocus(delta) {
        if (root.busy || root.isUnlocking || root.isPlayingIntro) return
        var n = focusables.length
        root.focusIndex = ((root.focusIndex + delta) % n + n) % n
        pwInput.forceActiveFocus()
    }

    function activateFocus() {
        if (root.focusIndex === 0)      root.cycleUser(1)
        else if (root.focusIndex === 1) root.doLogin()
        else if (root.focusIndex === 2) root.cycleSession(1)
        else if (root.focusIndex === 3) {
            if (root.powerIndex === 0)      sddm.suspend()
            else if (root.powerIndex === 1) sddm.reboot()
            else                            sddm.powerOff()
        }
    }

    // ---------------------------------------------------------------
    // LAYER 0 -- wallpaper
    // ---------------------------------------------------------------
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "bg.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: root.s(40)
        blur: 0.65
        opacity: root.reveal
        scale: 1.0 + 0.03 * (1.0 - root.reveal)
    }

    // ---------------------------------------------------------------
    // MAIN CONTENT
    // ---------------------------------------------------------------
    Item {
        id: selLayer
        anchors.fill: parent
        opacity: root.mainOpacity

        Item {
            id: contentLayer
            anchors.fill: parent
            z: 5
            opacity: root.contentReveal
            transform: Translate { y: root.s(16) * (1.0 - root.contentReveal) }

            // clock, top-left
            ColumnLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: root.s(64)
                anchors.topMargin: root.s(52)
                spacing: root.s(2)

                Text {
                    text: Qt.formatDateTime(clock.now, "HH:mm")
                    font.family: root.mono
                    font.pixelSize: root.s(64)
                    font.weight: Font.Light
                    color: root.cText
                }
                Text {
                    text: Qt.formatDateTime(clock.now, "dddd, dd MMMM").toUpperCase()
                    font.family: root.mono
                    font.pixelSize: root.s(13)
                    font.letterSpacing: root.s(3)
                    color: root.cSubtext
                    opacity: 0.75
                }
                Text {
                    text: (typeof sddm !== "undefined" && sddm.hostName) ? ("@" + sddm.hostName) : "@bite-os"
                    font.family: root.mono
                    font.pixelSize: root.s(13)
                    color: root.cOverlay
                }
            }

            ColumnLayout {
                id: panel
                anchors.centerIn: parent
                spacing: root.s(58)
                onHeightChanged: root.bumpGeom()
                onYChanged: root.bumpGeom()

                // ============ [0] user ============
                RowLayout {
                    id: userChip
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(10)

                    HoverHandler { onHoveredChanged: if (hovered) root.attract(0) }

                    Rectangle {
                        Layout.preferredWidth: root.s(30)
                        Layout.preferredHeight: root.s(30)
                        radius: width / 2
                        visible: root.multiUser
                        color: uPrev.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent"
                        border.width: 1
                        border.color: uPrev.containsMouse ? root.cAccent : root.cSurface0
                        scale: uPrev.pressed ? 0.92 : 1.0
                        Behavior on color        { ColorAnimation  { duration: 250 } }
                        Behavior on border.color { ColorAnimation  { duration: 250 } }
                        Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            font.family: root.mono
                            font.pixelSize: root.s(16)
                            color: uPrev.containsMouse ? root.cAccent : root.cSubtext
                        }
                        MouseArea {
                            id: uPrev
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.attract(0); root.cycleUser(-1) }
                        }
                    }

                    // the current user shrinks while the list is open
                    Rectangle {
                        id: avatar
                        Layout.preferredWidth: root.userListOpen ? root.s(34) : root.s(52)
                        Layout.preferredHeight: root.userListOpen ? root.s(34) : root.s(52)
                        radius: width / 2
                        color: root.cMantle
                        border.color: root.cAccent
                        border.width: root.s(2)
                        Behavior on Layout.preferredWidth  { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                        Text {
                            anchors.centerIn: parent
                            text: root.loginUser.length > 0 ? root.loginUser.charAt(0).toUpperCase() : "?"
                            font.family: root.mono
                            font.pixelSize: root.userListOpen ? root.s(15) : root.s(22)
                            color: root.cAccent
                            Behavior on font.pixelSize { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            id: userNameText
                            text: root.loginUser.length > 0 ? root.loginUser : "user"
                            font.family: root.mono
                            font.pixelSize: root.userListOpen ? root.s(14) : root.s(20)
                            font.letterSpacing: root.s(1)
                            color: root.cText
                            Behavior on font.pixelSize { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                        }
                        Text {
                            visible: root.multiUser
                            text: root.userListOpen ? "pick an account" : (userModel.count + " accounts  ·  click to switch")
                            font.family: root.mono
                            font.pixelSize: root.s(11)
                            color: root.cOverlay
                        }
                    }

                    // clicking the user opens the list
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.multiUser
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            root.attract(0)
                            root.userListOpen = !root.userListOpen
                            pwInput.forceActiveFocus()
                        }
                        z: -1
                    }

                    Rectangle {
                        Layout.preferredWidth: root.s(30)
                        Layout.preferredHeight: root.s(30)
                        radius: width / 2
                        visible: root.multiUser
                        color: uNext.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent"
                        border.width: 1
                        border.color: uNext.containsMouse ? root.cAccent : root.cSurface0
                        scale: uNext.pressed ? 0.92 : 1.0
                        Behavior on color        { ColorAnimation  { duration: 250 } }
                        Behavior on border.color { ColorAnimation  { duration: 250 } }
                        Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            font.family: root.mono
                            font.pixelSize: root.s(16)
                            color: uNext.containsMouse ? root.cAccent : root.cSubtext
                        }
                        MouseArea {
                            id: uNext
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.attract(0); root.cycleUser(1) }
                        }
                    }
                }

                // ============ [1] the bottle ============
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(10)

                    // mirror of the button strip, so the bottle stays centred
                    Item {
                        Layout.preferredWidth: root.s(90)
                        Layout.preferredHeight: 1
                    }

                Item {
                    id: pwWrap
                    Layout.preferredWidth: root.s(460)
                    Layout.preferredHeight: root.s(84)

                    HoverHandler { onHoveredChanged: if (hovered) root.attract(1) }

                    property real shakeX: 0
                    // tilt: the bottle tips when a character is poured out
                    // Holding backspace keeps the bottle tipped instead of
                    // replaying a tilt per keystroke; it rights itself once you
                    // stop. A wrong password dumps it much further.
                    property bool deleting: false
                    property bool dumping: false

                    // not readonly: a Behavior cannot attach to a readonly property
                    // Keep this small. At 10 degrees the bottle swung out of
                    // its own selection box and read as floppy rather than tipped.
                    property real tilt: dumping ? 11 : (deleting ? 4.5 : 0)
                    Behavior on tilt { NumberAnimation { duration: 430; easing.type: Easing.OutExpo } }

                    Timer {
                        id: delHold
                        interval: 320
                        onTriggered: pwWrap.deleting = false
                    }
                    Timer {
                        id: dumpHold
                        interval: 900
                        onTriggered: pwWrap.dumping = false
                    }

                    transform: [
                        Rotation {
                            origin.x: pwWrap.width / 2
                            origin.y: pwWrap.height
                            angle: pwWrap.tilt
                        },
                        Translate { x: pwWrap.shakeX }
                    ]

                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: pwWrap; property: "shakeX"; to:  root.s(14); duration: 50 }
                        NumberAnimation { target: pwWrap; property: "shakeX"; to: -root.s(12); duration: 50 }
                        NumberAnimation { target: pwWrap; property: "shakeX"; to:  root.s(8);  duration: 50 }
                        NumberAnimation { target: pwWrap; property: "shakeX"; to: -root.s(5);  duration: 50 }
                        NumberAnimation { target: pwWrap; property: "shakeX"; to: 0; duration: 350; easing.type: Easing.OutExpo }
                    }

                    // pour-out: tip the bottle, let a drop fall, settle back
                    SequentialAnimation {
                        id: spillAnim
                        ScriptAction { script: { pwWrap.dumping = true; dumpHold.restart() } }
                    }

                    // the removed character pours out over the low lip
                    function dragOutLast(glyph) {
                        pwWrap.deleting = true
                        delHold.restart()

                        var i = charRow.shown                       // slot it just vacated
                        var surfaceY = pwFluid.y + pwFluid.fillY
                        var sx = charRow.startX + i * charRow.step - root.s(10)
                        var sy = root.revealed
                                 ? Math.max(root.s(4), surfaceY - root.s(13))
                                 : Math.min(pwWrap.height - root.s(26), surfaceY + root.s(1))

                        var g = ghostPool.itemAt(pwWrap.ghostSlot % 4)
                        pwWrap.ghostSlot++
                        if (g) g.launch(glyph, root.revealed, sx, sy)
                    }

                    function spill() {
                        spillAnim.restart()
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.s(16)
                        color: Qt.rgba(0, 0, 0, 0.4)
                        border.width: root.s(2)
                        border.color: root.errorText.length > 0 ? root.cRed
                                    : (root.focusIndex === 1 ? root.cAccent : root.cSurface1)
                        Behavior on border.color { ColorAnimation { duration: 250 } }
                    }

                    // ---- the liquid ----
                    Canvas {
                        id: pwFluid
                        anchors.fill: parent
                        anchors.margins: root.s(2)
                        renderTarget: Canvas.FramebufferObject
                        renderStrategy: Canvas.Immediate

                        readonly property real cardRadius: root.s(14)
                        // the reveal never recolours the liquid -- only the
                        // bubbles and the characters they carry turn green
                        readonly property color fillCol: root.errorText.length > 0 ? root.cRed : root.cAccent

                        // The level is what grows with a long password -- the
                        // characters never scroll away, the bottle just fills.
                        // never empty: the hidden dots float *in* the liquid,
                        // and a long password raises the level rather than
                        // scrolling characters out of view
                        property real level: pwInput.text.length > 0
                                             ? Math.min(0.30 + 0.70 * (pwInput.text.length / 18.0), 1.0)
                                             : 0.0
                        Behavior on level { NumberAnimation { duration: 480; easing.type: Easing.OutExpo } }

                        readonly property real fillY: height * (1.0 - level)
                        readonly property real waveAmp: level > 0 ? root.s(5) : 0

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            if (level <= 0.001) return

                            ctx.save()
                            var r = cardRadius
                            ctx.beginPath()
                            ctx.moveTo(r, 0)
                            ctx.lineTo(width - r, 0)
                            ctx.quadraticCurveTo(width, 0, width, r)
                            ctx.lineTo(width, height - r)
                            ctx.quadraticCurveTo(width, height, width - r, height)
                            ctx.lineTo(r, height)
                            ctx.quadraticCurveTo(0, height, 0, height - r)
                            ctx.lineTo(0, r)
                            ctx.quadraticCurveTo(0, 0, r, 0)
                            ctx.closePath()
                            ctx.clip()

                            ctx.beginPath()
                            ctx.moveTo(0, fillY)
                            var sinP = Math.sin(root.globalWavePhase)
                            var cosP = Math.cos(root.globalWavePhase + Math.PI)
                            ctx.bezierCurveTo(width * 0.33, fillY + cosP * waveAmp,
                                              width * 0.66, fillY + sinP * waveAmp,
                                              width, fillY)
                            ctx.lineTo(width, height)
                            ctx.lineTo(0, height)
                            ctx.closePath()

                            var grad = ctx.createLinearGradient(0, 0, 0, height)
                            grad.addColorStop(0, Qt.lighter(fillCol, 1.18).toString())
                            grad.addColorStop(1, fillCol.toString())
                            ctx.fillStyle = grad
                            ctx.globalAlpha = 0.5
                            ctx.fill()
                            ctx.restore()
                        }

                        Connections {
                            target: root
                            enabled: root.fxLive
                            function onGlobalWavePhaseChanged() { pwFluid.requestPaint() }
                            function onRevealedChanged() { pwFluid.requestPaint() }
                        }
                        onLevelChanged: requestPaint()
                        onFillColChanged: requestPaint()
                    }

                    // Deleting tips the bottle and the character slides along
                    // the liquid to the low lip, then falls off the edge and is
                    // gone. Pooled, so holding backspace overlaps cleanly.
                    property int ghostSlot: 0

                    Repeater {
                        id: ghostPool
                        model: 4

                        Item {
                            id: gh
                            width: root.s(20)
                            height: root.s(20)
                            opacity: 0
                            z: 7
                            visible: opacity > 0.01

                            property string glyph: ""
                            property bool asChar: false

                            function launch(g, asC, sx, sy) {
                                gh.glyph = g
                                gh.asChar = asC
                                slideAnim.stop()
                                gh.x = sx
                                gh.y = sy
                                gh.rotation = 0
                                gh.opacity = 1
                                slideAnim.startX = sx
                                slideAnim.startY = sy
                                slideAnim.restart()
                            }

                            // the dot, when the password is hidden
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.s(11); height: root.s(11)
                                radius: width / 2
                                visible: !gh.asChar
                                color: root.errorText.length > 0 ? root.cRed : root.cAccent
                            }
                            // the character, when revealed
                            Text {
                                anchors.centerIn: parent
                                visible: gh.asChar
                                text: gh.glyph
                                font.family: root.mono
                                font.pixelSize: root.s(15)
                                font.bold: true
                                color: root.cGreen
                            }

                            SequentialAnimation {
                                id: slideAnim
                                property real startX: 0
                                property real startY: 0

                                // 1. slide down the tilted surface to the lip
                                ParallelAnimation {
                                    NumberAnimation {
                                        target: gh; property: "x"
                                        from: slideAnim.startX
                                        to: pwWrap.width - root.s(16)
                                        duration: 260; easing.type: Easing.InQuad
                                    }
                                    NumberAnimation {
                                        target: gh; property: "y"
                                        from: slideAnim.startY
                                        to: slideAnim.startY + root.s(4)
                                        duration: 260; easing.type: Easing.InQuad
                                    }
                                }

                                // 2. tip over the edge and fall away
                                ParallelAnimation {
                                    NumberAnimation {
                                        target: gh; property: "y"
                                        to: pwWrap.height + root.s(60)
                                        duration: 460; easing.type: Easing.InQuad
                                    }
                                    NumberAnimation {
                                        target: gh; property: "x"
                                        to: pwWrap.width + root.s(10)
                                        duration: 460; easing.type: Easing.OutQuad
                                    }
                                    NumberAnimation {
                                        target: gh; property: "rotation"
                                        to: -55; duration: 460; easing.type: Easing.OutQuad
                                    }
                                    SequentialAnimation {
                                        PauseAnimation { duration: 200 }
                                        NumberAnimation {
                                            target: gh; property: "opacity"
                                            to: 0.0; duration: 260; easing.type: Easing.InQuad
                                        }
                                    }
                                }
                            }
                        }
                    }

                    TextInput {
                        id: pwInput
                        anchors.fill: parent
                        opacity: 0
                        focus: true
                        echoMode: TextInput.Password
                        enabled: !root.busy && !root.isUnlocking

                        property int prevLen: 0
                        property string prevText: ""
                        onAccepted: root.doLogin()
                        onTextChanged: {
                            root.poke()
                            if (root.errorText.length > 0) root.errorText = ""
                            if (text.length < prevLen) {
                                pwWrap.dragOutLast(prevText.length > 0
                                                   ? prevText.charAt(prevText.length - 1) : "")
                            }
                            if (root.revealed && text.length > prevLen) root.revealBase = text.length - 1
                            prevLen = text.length
                            prevText = text
                        }
                    }

                    // ---- ambient soap bubbles ----
                    //
                    // Only while there is liquid and nothing is happening.
                    // Each bubble waits a random spell, then maybe launches --
                    // so they arrive irregularly rather than in a stream.
                    Item {
                        anchors.fill: parent
                        z: 4
                        visible: pwFluid.level > 0.01 && !root.lockedOut

                        Repeater {
                            model: 5

                            Item {
                                id: soap
                                required property int index

                                property real prog: 0
                                property real originX: 0
                                property real size: root.s(5)

                                readonly property real surfaceY: pwFluid.y + pwFluid.fillY

                                width: size; height: size
                                x: originX
                                // rises from the surface and clears the box
                                y: surfaceY - prog * (surfaceY + root.s(34))
                                opacity: prog <= 0 ? 0
                                       : (prog > 0.82 ? (1 - prog) / 0.18 : Math.min(1, prog / 0.12)) * 0.8
                                visible: opacity > 0.01
                                scale: 1 + prog * 0.5

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1
                                    border.color: Qt.rgba(0.85, 0.90, 1.0, 0.55)
                                }

                                NumberAnimation {
                                    id: floatUp
                                    target: soap; property: "prog"
                                    from: 0; to: 1
                                    duration: 2200 + soap.index * 220
                                    easing.type: Easing.InOutSine
                                }

                                Timer {
                                    interval: 1700 + soap.index * 900
                                    repeat: true
                                    running: root.ambientFx && root.idle && root.fxLive && pwFluid.level > 0.01
                                    onTriggered: {
                                        // not a stream, not once in a lifetime
                                        if (floatUp.running) return
                                        if (Math.random() > 0.45) return
                                        soap.size = root.s(4 + Math.floor(Math.random() * 4))
                                        soap.originX = root.s(20) + Math.random() * (pwWrap.width - root.s(50))
                                        floatUp.restart()
                                    }
                                }
                            }
                        }
                    }

                    // ---- the "clean" flood ----
                    //
                    // Un-revealing washes the box out with the same wave wipe
                    // Serpantinum uses for the Super+L lock intro: five bezier
                    // layers, each staggered 7% behind the last.
                    Canvas {
                        id: cleanCanvas
                        anchors.fill: parent
                        anchors.margins: root.s(2)
                        z: 6
                        renderTarget: Canvas.FramebufferObject
                        renderStrategy: Canvas.Immediate
                        visible: root.cleanProg > 0.001 && root.cleanProg < 0.999

                        readonly property var amps: [1.5, 1.3, 1.1, 0.9, 0.6]
                        readonly property var offs: [0.0, 0.5, 1.0, 1.5, 2.0]
                        // fully opaque: the point is you cannot see through it
                        readonly property var layerColors: [
                            Qt.rgba(0.07, 0.06, 0.11, 1.0),
                            Qt.rgba(0.11, 0.09, 0.18, 1.0),
                            Qt.rgba(0.18, 0.13, 0.30, 1.0),
                            Qt.rgba(0.30, 0.21, 0.48, 1.0),
                            Qt.rgba(0.45, 0.34, 0.70, 1.0)
                        ]

                        onPaint: {
                            var ctx = getContext("2d")
                            var w = width, h = height
                            ctx.clearRect(0, 0, w, h)
                            var rev = root.cleanProg
                            if (rev <= 0) return

                            var phase = rev * 7.853981633974483
                            var amp0 = root.s(14)
                            var pi = Math.PI

                            // Opaque, and each layer is a BAND following its own
                            // front -- the wave hides the characters as it passes
                            // and leaves clean box behind it.
                            var band = w * 0.62

                            for (var i = 4; i >= 0; i--) {
                                var prog = (rev - i * 0.07) * 1.62
                                if (prog <= 0) continue

                                // do NOT clamp: a clamped front stops moving and
                                // leaves a band parked on the right until the
                                // animation ends. Let it run off the edge.
                                var sp = Math.pow(prog, 1.4)
                                var cx = w * sp * 1.42          // front runs off the edge
                                var backX = cx - band
                                if (backX > w) continue

                                var waveAmp = amp0 * Math.sin(Math.min(1, sp) * pi) * amps[i]
                                var cp1x = cx + Math.sin(phase + offs[i]) * waveAmp
                                var cp2x = cx + Math.cos(phase + offs[i] + pi) * waveAmp
                                var b1x  = backX + Math.cos(phase + offs[i]) * waveAmp
                                var b2x  = backX + Math.sin(phase + offs[i] + pi) * waveAmp

                                ctx.beginPath()
                                ctx.moveTo(backX, 0)
                                ctx.lineTo(cx, 0)
                                ctx.bezierCurveTo(cp1x, h * 0.33, cp2x, h * 0.66, cx, h)
                                ctx.lineTo(backX, h)
                                ctx.bezierCurveTo(b2x, h * 0.66, b1x, h * 0.33, backX, 0)
                                ctx.closePath()
                                ctx.fillStyle = cleanCanvas.layerColors[i]
                                ctx.fill()
                            }
                        }

                        Connections {
                            target: root
                            function onCleanProgChanged() { cleanCanvas.requestPaint() }
                        }
                    }

                    // ---- one slot per character ----
                    //
                    // Hidden, every slot is a dot. Pressing reveal runs a wave
                    // left to right: the dot rises, pops, and the character
                    // drops out of the burst and settles back on the surface.
                    // t = 0 is a dot at rest, t = 1 is a revealed character.
                    Item {
                        id: charRow
                        anchors.fill: parent
                        visible: pwInput.text.length > 0

                        readonly property real slotSize: root.s(21)
                        readonly property real step: root.s(23)
                        // keep clear of the buttons on the right
                        readonly property real usableW: width - root.s(40)
                        readonly property int maxSlots: Math.max(1, Math.floor(usableW / step))
                        readonly property int shown: Math.min(pwInput.text.length, maxSlots)
                        readonly property real startX: (width - shown * step) / 2 + step / 2

                        Repeater {
                            model: charRow.shown

                            Item {
                                id: slot
                                required property int index

                                readonly property string glyph: pwInput.text.charAt(index)

                                width: charRow.slotSize
                                height: charRow.slotSize
                                x: charRow.startX + index * charRow.step - width / 2

                                // 0 = dot, 1 = revealed character
                                property real t: 0.0

                                readonly property real pRise: 0.45
                                readonly property real pPop:  0.56
                                readonly property real pFall: 1.0

                                // the liquid surface, in pwWrap coordinates
                                readonly property real surfaceY: pwFluid.y + pwFluid.fillY

                                // hidden: the dot floats submerged, below the surface
                                readonly property real restY: Math.min(
                                        pwWrap.height - height - root.s(6),
                                        surfaceY + root.s(10))

                                // it pops clear of the box, not inside it
                                readonly property real riseY: -height - root.s(10)

                                // revealed: the character settles ON the surface
                                readonly property real landY: Math.max(root.s(4), surfaceY - height * 0.62)

                                // ride the liquid surface once settled
                                readonly property real waveY: {
                                    if (t > 0.001 && t < 0.999) return 0
                                    var xn = charRow.shown > 1 ? index / (charRow.shown - 1) : 0.5
                                    var sinP = Math.sin(root.globalWavePhase)
                                    var cosP = Math.cos(root.globalWavePhase + Math.PI)
                                    return (cosP * (1 - xn) + sinP * xn) * root.s(4)
                                }

                                y: {
                                    if (t <= 0) return restY
                                    if (t < pRise) {
                                        // a bubble leaving liquid speeds up
                                        var u = t / pRise
                                        u = u * u * (3 - 2 * u)             // smoothstep
                                        return restY + (riseY - restY) * u
                                    }
                                    if (t < pPop) return riseY
                                    var v = (t - pPop) / (pFall - pPop)
                                    v = Math.sin(v * Math.PI / 2)           // drifts down gently
                                    return riseY + (landY - riseY) * v
                                }

                                // ---- the wave, one character at a time ----
                                SequentialAnimation {
                                    id: revealAnim
                                    PauseAnimation {
                                        duration: root.revealWave ? slot.index * root.revealStagger : 0
                                    }
                                    NumberAnimation {
                                        target: slot; property: "t"; to: 1.0
                                        duration: 900
                                    }
                                }
                                SequentialAnimation {
                                    id: hideAnim
                                    PauseAnimation {
                                        duration: root.revealWave
                                                  ? (charRow.shown - 1 - slot.index) * Math.round(root.revealStagger * 0.45)
                                                  : 0
                                    }
                                    NumberAnimation {
                                        target: slot; property: "t"; to: 0.0
                                        duration: 320; easing.type: Easing.OutExpo
                                    }
                                }

                                function play() {
                                    if (root.revealed) { hideAnim.stop(); revealAnim.restart() }
                                    else               { revealAnim.stop(); hideAnim.restart() }
                                }
                                Component.onCompleted: if (root.revealed) t = 1.0
                                Connections {
                                    target: root
                                    function onRevealedChanged() { slot.play() }
                                }

                                // ---- dot ----
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: root.s(11) + root.s(10) * Math.min(1, slot.t / slot.pRise)
                                    height: width
                                    radius: width / 2
                                    visible: slot.t < slot.pPop
                                    color: slot.t > 0.02
                                           ? Qt.rgba(0.65, 0.89, 0.63, 0.22)
                                           : (root.errorText.length > 0 ? root.cRed : root.cAccent)
                                    border.width: slot.t > 0.02 ? 1 : 0
                                    border.color: Qt.rgba(0.72, 0.93, 0.70, 0.80)

                                    // bubble glint, only once it has lifted
                                    Rectangle {
                                        width: parent.width * 0.26
                                        height: width
                                        radius: width / 2
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                        x: parent.width * 0.20
                                        y: parent.height * 0.18
                                        visible: slot.t > 0.15
                                    }

                                    // pop in when first typed.
                                    // target must be the dot itself -- `parent`
                                    // here is the slot, which left every dot at
                                    // scale 0, i.e. invisible.
                                    id: dotShape
                                    scale: 0
                                    Component.onCompleted: dotPop.start()
                                    NumberAnimation {
                                        id: dotPop
                                        target: dotShape; property: "scale"
                                        from: 0.0; to: 1.0
                                        duration: 400; easing.type: Easing.OutExpo
                                    }
                                }

                                // ---- burst ----
                                Rectangle {
                                    anchors.centerIn: parent
                                    readonly property real burst: {
                                        var w = 0.20
                                        if (slot.t < slot.pPop || slot.t > slot.pPop + w) return 0
                                        return (slot.t - slot.pPop) / w
                                    }
                                    width: charRow.slotSize * (1.0 + 1.7 * burst)
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: Math.max(1, root.s(2) * (1 - burst))
                                    border.color: root.cGreen
                                    opacity: burst > 0 ? (1 - burst) * 0.9 : 0
                                    visible: opacity > 0.01
                                }

                                // ---- the character ----
                                Text {
                                    anchors.centerIn: parent
                                    text: slot.glyph
                                    font.family: root.mono
                                    font.pixelSize: root.s(15)
                                    font.bold: true
                                    color: root.cGreen
                                    visible: slot.t >= slot.pPop
                                    opacity: Math.min(1, (slot.t - slot.pPop) / 0.12)
                                    rotation: slot.t < 0.999
                                              ? (1 - (slot.t - slot.pPop) / (slot.pFall - slot.pPop)) * 14
                                              : 0
                                }

                                transform: Translate { y: slot.waveY }
                            }
                        }
                    }

                    // overflow marker -- past this the bottle just fills higher
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: root.s(14)
                        visible: pwInput.text.length > charRow.maxSlots
                        text: "+" + (pwInput.text.length - charRow.maxSlots)
                        font.family: root.mono
                        font.pixelSize: root.s(12)
                        color: root.cAccent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: pwInput.text.length === 0 && !root.busy
                        text: "password"
                        font.family: root.mono
                        font.pixelSize: root.s(14)
                        color: root.cOverlay
                        opacity: 0.7
                    }

                    // busy sweep
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.s(3)
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: root.s(2)
                        width: root.busy ? parent.width - root.s(28) : 0
                        radius: height / 2
                        color: root.cPeach
                        opacity: root.busy ? 1 : 0
                        Behavior on width   { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                }

                    // ---- controls, outside the bottle ----
                    RowLayout {
                        spacing: root.s(6)
                        Layout.alignment: Qt.AlignVCenter

                        // reveal toggle
                        Rectangle {
                            id: eyeBtn
                            Layout.preferredWidth: root.s(40)
                                Layout.preferredHeight: root.s(40)
                            radius: width / 2
                            z: 8
                            color: eyeMa.containsMouse || root.revealed ? Qt.rgba(1, 0.9, 0.45, 0.16) : "transparent"
                            border.width: 1
                            border.color: root.revealed ? root.cBurp
                                        : (eyeMa.containsMouse ? root.cAccent : root.cSurface0)
                            scale: eyeMa.pressed ? 0.9 : 1.0
                            Behavior on color        { ColorAnimation  { duration: 250 } }
                            Behavior on border.color { ColorAnimation  { duration: 250 } }
                            Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                            Text {
                                anchors.centerIn: parent
                                text: root.revealed ? "◉" : "○"
                                font.family: root.mono
                                font.pixelSize: root.s(15)
                                color: root.revealed ? root.cBurp : root.cText
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                            MouseArea {
                                id: eyeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.revealed = !root.revealed
                                    pwInput.forceActiveFocus()
                                }
                            }
                        }

                        // settings
                        Rectangle {
                            id: gearBtn
                            Layout.preferredWidth: root.s(40)
                                Layout.preferredHeight: root.s(40)
                            radius: width / 2
                            z: 8
                            color: gearMa.containsMouse || root.settingsOpen ? Qt.rgba(1,1,1,0.10) : "transparent"
                            border.width: 1
                            border.color: root.settingsOpen ? root.cAccent
                                        : (gearMa.containsMouse ? root.cAccent : root.cSurface0)
                            scale: gearMa.pressed ? 0.9 : 1.0
                            Behavior on color        { ColorAnimation  { duration: 250 } }
                            Behavior on border.color { ColorAnimation  { duration: 250 } }
                            Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                font.family: root.mono
                                font.pixelSize: root.s(14)
                                color: root.settingsOpen ? root.cAccent : root.cText
                                rotation: root.settingsOpen ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                                Behavior on color    { ColorAnimation  { duration: 250 } }
                            }
                            MouseArea {
                                id: gearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.settingsOpen = !root.settingsOpen
                                    pwInput.forceActiveFocus()
                                }
                            }
                        }

                    }
                }

                // ---- settings panel ----
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.s(460)
                    Layout.preferredHeight: root.settingsOpen ? root.s(232) : 0
                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 420; easing.type: Easing.OutExpo }
                    }
                    clip: true
                    opacity: root.settingsOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    visible: Layout.preferredHeight > 1

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: root.s(6)
                        radius: root.s(14)
                        color: Qt.rgba(0.03, 0.02, 0.06, 0.72)
                        border.width: 1
                        border.color: root.cSurface0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(14)
                            spacing: root.s(9)

                            Text {
                                text: "// REVEAL"
                                font.family: root.mono
                                font.pixelSize: root.s(10)
                                font.letterSpacing: root.s(2)
                                color: root.cAccent
                            }

                            // style
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.preferredWidth: root.s(86)
                                    text: "style"
                                    font.family: root.mono
                                    font.pixelSize: root.s(12)
                                    color: root.cSubtext
                                }
                                Repeater {
                                    model: [
                                        { label: "wave",   wave: true },
                                        { label: "all at once", wave: false }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        Layout.preferredWidth: root.s(104)
                                        Layout.preferredHeight: root.s(26)
                                        radius: root.s(8)
                                        readonly property bool on: root.revealWave === modelData.wave
                                        color: on ? Qt.rgba(0.71,0.54,1.0,0.18)
                                                  : (stMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                        border.width: 1
                                        border.color: on ? root.cAccent : root.cSurface2
                                        Behavior on color        { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            font.family: root.mono
                                            font.pixelSize: root.s(11)
                                            color: parent.on ? root.cAccent : root.cText
                                        }
                                        MouseArea {
                                            id: stMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: root.revealWave = parent.modelData.wave
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            // speed
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.preferredWidth: root.s(86)
                                    text: "speed"
                                    font.family: root.mono
                                    font.pixelSize: root.s(12)
                                    color: root.cSubtext
                                }
                                Repeater {
                                    model: [
                                        { label: "slow",   ms: 340 },
                                        { label: "normal", ms: 220 },
                                        { label: "fast",   ms: 110 }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        Layout.preferredWidth: root.s(68)
                                        Layout.preferredHeight: root.s(26)
                                        radius: root.s(8)
                                        readonly property bool on: root.revealStagger === modelData.ms
                                        color: on ? Qt.rgba(0.71,0.54,1.0,0.18)
                                                  : (spMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                        border.width: 1
                                        border.color: on ? root.cAccent : root.cSurface2
                                        Behavior on color        { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.label
                                            font.family: root.mono
                                            font.pixelSize: root.s(11)
                                            color: parent.on ? root.cAccent : root.cText
                                        }
                                        MouseArea {
                                            id: spMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: root.revealStagger = parent.modelData.ms
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            // keyboard layout -- actually switches it
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                visible: root.kbCount > 0
                                Text {
                                    Layout.preferredWidth: root.s(86)
                                    text: "layout"
                                    font.family: root.mono
                                    font.pixelSize: root.s(12)
                                    color: root.cSubtext
                                }
                                Text {
                                    visible: !root.kbApiWorks && root.xkbToggle.length > 0
                                    text: "switch with " + root.xkbToggle
                                    font.family: root.mono
                                    font.pixelSize: root.s(10)
                                    color: root.cOverlay
                                }
                                Repeater {
                                    model: root.kbCount
                                    Rectangle {
                                        required property int index
                                        readonly property string lname: root.kbApiWorks
                                            ? String(keyboard.layouts[index].shortName).toUpperCase()
                                            : String(root.xkbLayouts[index] || "??").toUpperCase()
                                        readonly property bool on: root.kbApiWorks
                                            ? (keyboard.currentLayout === index)
                                            : false
                                        Layout.preferredWidth: root.s(56)
                                        Layout.preferredHeight: root.s(26)
                                        radius: root.s(8)
                                        color: on ? Qt.rgba(0.58,0.89,0.84,0.18)
                                                  : (kbMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                        border.width: 1
                                        border.color: on ? root.cTeal : root.cSurface2
                                        Behavior on color        { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.lname
                                            font.family: root.mono
                                            font.pixelSize: root.s(11)
                                            color: parent.on ? root.cTeal : root.cText
                                        }
                                        MouseArea {
                                            id: kbMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: root.kbApiWorks
                                            onClicked: keyboard.currentLayout = parent.index
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            // effects
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.preferredWidth: root.s(86)
                                    text: "effects"
                                    font.family: root.mono
                                    font.pixelSize: root.s(12)
                                    color: root.cSubtext
                                }
                                Repeater {
                                    model: [ { label: "bubbles" }, { label: "lite mode" } ]
                                    Rectangle {
                                        required property int index
                                        required property var modelData
                                        Layout.preferredWidth: root.s(96)
                                        Layout.preferredHeight: root.s(26)
                                        radius: root.s(8)
                                        readonly property bool on: index === 0 ? root.ambientFx : root.reduceMotion
                                        color: on ? Qt.rgba(0.65,0.89,0.63,0.16)
                                                  : (fxMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                        border.width: 1
                                        border.color: on ? root.cGreen : root.cSurface2
                                        Behavior on color        { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: (parent.on ? "◉ " : "○ ") + parent.modelData.label
                                            font.family: root.mono
                                            font.pixelSize: root.s(11)
                                            color: parent.on ? root.cGreen : root.cText
                                        }
                                        MouseArea {
                                            id: fxMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (parent.index === 0) root.ambientFx = !root.ambientFx
                                                else                    root.reduceMotion = !root.reduceMotion
                                            }
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }

                            // toggles
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Text {
                                    Layout.preferredWidth: root.s(86)
                                    text: "show"
                                    font.family: root.mono
                                    font.pixelSize: root.s(12)
                                    color: root.cSubtext
                                }
                                Repeater {
                                    model: [ { label: "gauges" }, { label: "dim" } ]
                                    Rectangle {
                                        required property int index
                                        required property var modelData
                                        Layout.preferredWidth: root.s(84)
                                        Layout.preferredHeight: root.s(26)
                                        radius: root.s(8)
                                        readonly property bool on: index === 0 ? root.showGauges : root.dimOutside
                                        color: on ? Qt.rgba(0.65,0.89,0.63,0.16)
                                                  : (tgMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                        border.width: 1
                                        border.color: on ? root.cGreen : root.cSurface2
                                        Behavior on color        { ColorAnimation { duration: 200 } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: (parent.on ? "◉ " : "○ ") + parent.modelData.label
                                            font.family: root.mono
                                            font.pixelSize: root.s(11)
                                            color: parent.on ? root.cGreen : root.cText
                                        }
                                        MouseArea {
                                            id: tgMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (parent.index === 0) root.showGauges = !root.showGauges
                                                else                    root.dimOutside = !root.dimOutside
                                            }
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ============ [2] session ============
                RowLayout {
                    id: sessionChip
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(8)

                    HoverHandler { onHoveredChanged: if (hovered) root.attract(2) }

                    Rectangle {
                        Layout.preferredWidth: root.s(26)
                        Layout.preferredHeight: root.s(26)
                        radius: width / 2
                        visible: sessionModel.count > 1
                        color: sPrev.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent"
                        border.width: 1
                        border.color: sPrev.containsMouse ? root.cAccent : root.cSurface2
                        scale: sPrev.pressed ? 0.92 : 1.0
                        Behavior on color        { ColorAnimation  { duration: 250 } }
                        Behavior on border.color { ColorAnimation  { duration: 250 } }
                        Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            font.family: root.mono
                            font.pixelSize: root.s(13)
                            color: sPrev.containsMouse ? root.cAccent : root.cText
                        }
                        MouseArea {
                            id: sPrev
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.attract(2); root.cycleSession(-1) }
                        }
                    }

                    // fixed width: a longer session name used to resize the
                    // row and shove the whole column sideways on each click
                    Text {
                        Layout.preferredWidth: root.s(300)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.sessionName
                        font.family: root.mono
                        font.pixelSize: root.s(13)
                        color: root.focusIndex === 2 ? root.cAccent : root.cSubtext
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    Rectangle {
                        Layout.preferredWidth: root.s(26)
                        Layout.preferredHeight: root.s(26)
                        radius: width / 2
                        visible: sessionModel.count > 1
                        color: sNext.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent"
                        border.width: 1
                        border.color: sNext.containsMouse ? root.cAccent : root.cSurface2
                        scale: sNext.pressed ? 0.92 : 1.0
                        Behavior on color        { ColorAnimation  { duration: 250 } }
                        Behavior on border.color { ColorAnimation  { duration: 250 } }
                        Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            font.family: root.mono
                            font.pixelSize: root.s(13)
                            color: sNext.containsMouse ? root.cAccent : root.cText
                        }
                        MouseArea {
                            id: sNext
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.attract(2); root.cycleSession(1) }
                        }
                    }
                }

                // ============ [3] power ============
                RowLayout {
                    id: powerRow
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(12)

                    HoverHandler { onHoveredChanged: if (hovered) root.attract(3) }

                    Repeater {
                        model: [
                            { label: "suspend",  ok: sddm.canSuspend,  col: root.cBlue },
                            { label: "reboot",   ok: sddm.canReboot,   col: root.cPeach },
                            { label: "shutdown", ok: sddm.canPowerOff, col: root.cRed }
                        ]

                        Rectangle {
                            required property int index
                            required property var modelData

                            opacity: modelData.ok ? 1.0 : 0.35
                            enabled: modelData.ok
                            Layout.preferredWidth: root.s(112)
                            Layout.preferredHeight: root.s(34)
                            radius: root.s(10)

                            readonly property bool hot: (root.focusIndex === 3 && root.powerIndex === index) || pwrMa.containsMouse

                            color: hot
                                   ? Qt.rgba(modelData.col.r, modelData.col.g, modelData.col.b, 0.22)
                                   : Qt.rgba(1, 1, 1, 0.07)
                            border.width: hot ? root.s(2) : 1
                            border.color: hot ? modelData.col : root.cSurface2
                            scale: pwrMa.pressed ? 0.97 : 1.0

                            Behavior on color        { ColorAnimation  { duration: 250 } }
                            Behavior on border.color { ColorAnimation  { duration: 250 } }
                            Behavior on scale        { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                font.family: root.mono
                                font.pixelSize: root.s(13)
                                font.letterSpacing: root.s(1)
                                color: parent.hot ? parent.modelData.col : root.cText
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }

                            // glow ring on hover so the label is legible
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -root.s(3)
                                radius: root.s(13)
                                color: "transparent"
                                border.width: 1
                                border.color: parent.modelData.col
                                opacity: parent.hot ? 0.55 : 0
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                            }

                            MouseArea {
                                id: pwrMa
                                anchors.fill: parent
                                hoverEnabled: true
                                // hovering a button both pulls the box here and
                                // picks which button is armed
                                onEntered: { root.attract(3); root.powerIndex = parent.index }
                                onClicked: { root.attract(3); root.powerIndex = parent.index; root.activateFocus() }
                            }
                        }
                    }
                }
            }

            // ============ gauge row ============
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.s(76)
                spacing: root.s(14)
                visible: root.showGauges
                opacity: root.showGauges ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

                FluidGauge {
                    label: "CPU"
                    valueText: root.statsOk ? (Math.round(root.cpuLevel * 100) + "%") : "n/a"
                    level: root.statsOk ? root.cpuLevel : 0
                    fillCol: root.cTeal
                    textCol: root.cText; subCol: root.cOverlay
                    cardCol: root.cMantle; borderCol: root.cSurface0
                    mono: root.mono; scaleF: root.scaleFactor
                    wavePhase: root.globalWavePhase
                    live: root.fxLive
                }
                FluidGauge {
                    label: "RAM"
                    valueText: root.statsOk
                        ? (Math.round(root.ramLevel * 100) + "%  " + root.ramUsedGb.toFixed(1) + "G")
                        : "n/a"
                    level: root.statsOk ? root.ramLevel : 0
                    fillCol: root.cBlue
                    textCol: root.cText; subCol: root.cOverlay
                    cardCol: root.cMantle; borderCol: root.cSurface0
                    mono: root.mono; scaleF: root.scaleFactor
                    wavePhase: root.globalWavePhase
                    live: root.fxLive
                }
                FluidGauge {
                    label: "TIME"
                    valueText: Qt.formatDateTime(clock.now, "HH:mm:ss")
                    level: root.dayLevel
                    fillCol: root.cAccent
                    textCol: root.cText; subCol: root.cOverlay
                    cardCol: root.cMantle; borderCol: root.cSurface0
                    mono: root.mono; scaleF: root.scaleFactor
                    wavePhase: root.globalWavePhase
                    live: root.fxLive
                }
                FluidGauge {
                    label: root.xkbToggle.length > 0 ? ("LANG  " + root.xkbToggle) : "LANG"
                    valueText: {
                        if (typeof keyboard !== "undefined" && keyboard.capsLock) return "CAPS"
                        if (root.kbApiWorks) return root.kbLayout
                        if (root.xkbLayouts.length > 0) {
                            var out = []
                            for (var i = 0; i < root.xkbLayouts.length; i++)
                                out.push(String(root.xkbLayouts[i]).toUpperCase())
                            return out.join(" / ")
                        }
                        return root.kbLayout
                    }
                    level: (typeof keyboard !== "undefined" && keyboard.capsLock) ? 1.0 : 0.35
                    fillCol: (typeof keyboard !== "undefined" && keyboard.capsLock) ? root.cPeach : root.cGreen
                    textCol: root.cText; subCol: root.cOverlay
                    cardCol: root.cMantle; borderCol: root.cSurface0
                    mono: root.mono; scaleF: root.scaleFactor
                    wavePhase: root.globalWavePhase
                    live: root.fxLive
                }
            }

            // status bar
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.s(44)

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.s(28)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BITE-OS"
                    font.family: root.mono
                    font.pixelSize: root.s(13)
                    font.letterSpacing: root.s(4)
                    color: root.cAccent
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: root.s(28)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "tab ▸ move   ⏎ ▸ select   F5 ▸ burp"
                    font.family: root.mono
                    font.pixelSize: root.s(12)
                    color: root.cOverlay
                }
            }
        }

        // --- user list: floats over the layout, takes no space in it ---
        Item {
            id: userListLayer
            anchors.fill: parent
            z: 30
            visible: root.userListOpen || userListBox.opacity > 0.01

            MouseArea {
                anchors.fill: parent
                enabled: root.userListOpen
                onClicked: root.userListOpen = false
            }

            readonly property rect anchorRect: root.rectOf(userChip)

            Rectangle {
                id: userListBox
                width: root.s(240)
                height: Math.min(userModel.count, 6) * root.s(34) + root.s(12)
                x: userListLayer.anchorRect.x + userListLayer.anchorRect.width / 2 - width / 2
                y: userListLayer.anchorRect.y + userListLayer.anchorRect.height + root.s(6)
                radius: root.s(12)
                color: Qt.rgba(0.04, 0.03, 0.07, 0.94)
                border.width: 1
                border.color: root.cSurface1

                opacity: root.userListOpen ? 1 : 0
                scale: root.userListOpen ? 1 : 0.94
                transformOrigin: Item.Top
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Behavior on scale   { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }

                Column {
                    anchors.fill: parent
                    anchors.margins: root.s(6)

                    Repeater {
                        model: userModel.count

                        Rectangle {
                            required property int index
                            readonly property string uname:
                                String(userModel.data(userModel.index(index, 0), Qt.UserRole + 1) || "")
                            readonly property bool isCurrent: uname === root.loginUser

                            width: userListBox.width - root.s(12)
                            height: root.s(34)
                            radius: root.s(8)
                            color: rowMa.containsMouse ? Qt.rgba(1,1,1,0.08)
                                 : (isCurrent ? Qt.rgba(0.71,0.54,1.0,0.13) : "transparent")
                            Behavior on color { ColorAnimation { duration: 180 } }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: root.s(9)
                                spacing: root.s(9)

                                Rectangle {
                                    width: root.s(20); height: root.s(20)
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "transparent"
                                    border.width: 1
                                    border.color: parent.parent.isCurrent ? root.cAccent : root.cSurface1
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.parent.parent.uname.length > 0
                                              ? parent.parent.parent.uname.charAt(0).toUpperCase() : "?"
                                        font.family: root.mono
                                        font.pixelSize: root.s(10)
                                        color: parent.parent.parent.isCurrent ? root.cAccent : root.cSubtext
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.uname
                                    font.family: root.mono
                                    font.pixelSize: root.s(13)
                                    color: parent.parent.isCurrent ? root.cAccent : root.cText
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.pickUser(parent.index)
                            }
                        }
                    }
                }
            }
        }

        // --- dim outside the selection ---
        Item {
            id: dimLayer
            anchors.fill: parent
            z: 10
            opacity: root.contentReveal * (root.dimOutside ? 1 : 0)
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
            readonly property color dimCol: Qt.rgba(0.03, 0.02, 0.06, 0.62)

            Rectangle {
                x: 0; y: 0; width: parent.width
                height: Math.max(0, root.selY)
                color: dimLayer.dimCol
            }
            Rectangle {
                x: 0; y: root.selY + root.selH; width: parent.width
                height: Math.max(0, parent.height - (root.selY + root.selH))
                color: dimLayer.dimCol
            }
            Rectangle {
                x: 0; y: root.selY
                width: Math.max(0, root.selX); height: root.selH
                color: dimLayer.dimCol
            }
            Rectangle {
                x: root.selX + root.selW; y: root.selY
                width: Math.max(0, parent.width - (root.selX + root.selW)); height: root.selH
                color: dimLayer.dimCol
            }
        }

        // --- the selection box ---
        Item {
            id: selBox
            x: root.selX
            y: root.selY
            width: root.selW
            height: root.selH
            z: 20
            opacity: root.contentReveal
            visible: root.selW > 0

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: root.errorText.length > 0 ? root.cRed : root.cAccent
                border.width: root.s(2)
                radius: root.s(18)
                Behavior on border.color { ColorAnimation { duration: 250 } }
            }

            // soft breathing glow
            Rectangle {
                anchors.fill: parent
                anchors.margins: -root.s(3)
                color: "transparent"
                border.color: root.errorText.length > 0 ? root.cRed : root.cAccent
                border.width: 1
                radius: root.s(21)
                opacity: glowPulse
                property real glowPulse: 0.15
                SequentialAnimation on glowPulse {
                    loops: Animation.Infinite
                    running: root.ambientFx && root.fxLive
                    NumberAnimation { to: 0.45; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.12; duration: 1400; easing.type: Easing.InOutSine }
                }
            }

            Repeater {
                model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                Rectangle {
                    required property var modelData
                    width: root.s(9); height: root.s(9)
                    radius: width / 2
                    color: root.errorText.length > 0 ? root.cRed : root.cAccent
                    x: modelData[0] * selBox.width  - width / 2
                    y: modelData[1] * selBox.height - height / 2
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }

            Rectangle {
                id: chip
                anchors.bottom: parent.top
                anchors.bottomMargin: root.s(10)
                anchors.horizontalCenter: parent.horizontalCenter
                height: root.s(24)
                width: chipText.implicitWidth + root.s(20)
                radius: root.s(6)
                color: Qt.rgba(0.03, 0.02, 0.06, 0.85)
                border.width: 1
                border.color: root.cAccent
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: root.errorText.length > 0
                          ? (root.errorText + (root.failCount > 1 ? " ×" + root.failCount : ""))
                          : (root.focusLabels[root.focusIndex]
                             + "  " + Math.round(root.selW) + "×" + Math.round(root.selH))
                    font.family: root.mono
                    font.pixelSize: root.s(11)
                    font.letterSpacing: root.s(1)
                    color: root.errorText.length > 0 ? root.cRed : root.cAccent
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Clock + keys
    // ---------------------------------------------------------------
    QtObject {
        id: clock
        property var now: new Date()
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: clock.now = new Date()
    }

    Keys.onPressed: function(event) {
        if (root.isPlayingIntro || root.isUnlocking) { event.accepted = true; return }

        switch (event.key) {
        case Qt.Key_Tab:     root.moveFocus(1);  event.accepted = true; break
        case Qt.Key_Backtab: root.moveFocus(-1); event.accepted = true; break
        case Qt.Key_Down:    root.moveFocus(1);  event.accepted = true; break
        case Qt.Key_Up:      root.moveFocus(-1); event.accepted = true; break
        case Qt.Key_Left:
            if (root.focusIndex === 3) { root.powerIndex = (root.powerIndex + 2) % 3; event.accepted = true }
            break
        case Qt.Key_Right:
            if (root.focusIndex === 3) { root.powerIndex = (root.powerIndex + 1) % 3; event.accepted = true }
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activateFocus(); event.accepted = true; break
        case Qt.Key_Escape:
            if (root.userListOpen) { root.userListOpen = false }
            else { root.focusIndex = 1; pwInput.text = "" }
            event.accepted = true; break
        case Qt.Key_F5:
            root.revealed = !root.revealed; event.accepted = true; break
        }
    }

    // One handler only -- QML rejects a second Component.onCompleted on the
    // same object with "Property value set multiple times".
    Component.onCompleted: {
        root.readKeyboardConf()
        pwInput.forceActiveFocus()
    }
}
