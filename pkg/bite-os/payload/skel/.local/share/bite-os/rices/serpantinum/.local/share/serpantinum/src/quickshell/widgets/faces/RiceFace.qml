// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Desktop widget: rice + shell switcher with a Save button.
//  Two looks, picked by `look` (Compact is a thin file that sets it):
//    cards    header, big rice name, one hold-to-switch button per rice, Save
//    compact  one slim row
//
//  Switching goes through dots-switch.sh, which swaps the shell with the rice
//  -- it kills this very shell, so it runs under `setsid -f`. Save is a plain
//  `rice save` of the active rice. The vault is read when the widget becomes
//  visible and every few seconds while it stays visible; nothing runs hidden.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property string look: "cards"
    readonly property bool compact: look === "compact"

    property real minWidth: compact ? 220 : 240
    property real minHeight: compact ? 56 : 160
    property real maxWidth: 720
    property real maxHeight: compact ? 120 : 440
    property real minAspect: compact ? 2.4 : 0.9
    property real maxAspect: compact ? 8.0 : 3.0
    property bool isRound: false

    // verified in Symbols NF + JetBrainsMono NF; set by codepoint, never retyped
    readonly property string icPalette: String.fromCodePoint(0xF03D8)
    readonly property string icSave:    String.fromCodePoint(0xF0193)
    readonly property string icSwap:    String.fromCodePoint(0xF04E1)
    readonly property string icCheck:   String.fromCodePoint(0xF012C)

    property string activeRice: "…"
    property string activeShell: "…"
    property string statusLine: ""
    property bool busy: false
    // BITE-OS: fills the cards look's middle (it used to be empty space)
    property string lastLabel: ""
    property string lastWhen: ""
    property int olderCount: 0
    ListModel { id: riceList }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Timer { interval: 5000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    function refresh() { if (!stateProc.running) stateProc.running = true; }

    Process {
        id: stateProc
        running: false
        command: ["bash", "-c",
            "V=\"$HOME/.local/share/bite-os/rices\"; " +
            "echo \"ACTIVE=$(cat \"$V/.active\" 2>/dev/null || echo unknown)\"; " +
            "echo \"SHELL=$(cat \"$HOME/.local/state/bite-os/active-shell\" 2>/dev/null || echo unknown)\"; " +
            "for d in \"$V\"/*/; do n=$(basename \"$d\"); case \"$n\" in _*|.*) continue;; esac; echo \"RICE=$n\"; done; " +
            "A=$(cat \"$V/.active\" 2>/dev/null); m() { sed -n \"s/^$1=//p\" \"$2\" 2>/dev/null | head -n 1; }; " +
            "[ -n \"$A\" ] && printf 'LAST=%s\\t%s\\n' \"$(m label \"$V/$A/meta.txt\")\" \"$(m saved \"$V/$A/meta.txt\")\"; " +
            "echo \"NSAVES=$(ls -d \"$V\"/_replaced/\"$A\"-*/ 2>/dev/null | wc -l)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let names = [];
                let lines = (this.text || "").trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let l = lines[i];
                    if (l.indexOf("ACTIVE=") === 0) root.activeRice = l.slice(7).trim() || "unknown";
                    else if (l.indexOf("SHELL=") === 0) root.activeShell = l.slice(6).trim() || "unknown";
                    else if (l.indexOf("RICE=") === 0) names.push(l.slice(5).trim());
                    else if (l.indexOf("LAST=") === 0) {
                        const lp = l.slice(5).split("\t");
                        root.lastLabel = lp[0] || "unnamed save";
                        const b = (lp[1] || "").split("-");
                        root.lastWhen = (b.length === 2 && b[0].length === 8) ? b[0].slice(4, 6) + "/" + b[0].slice(6, 8) + " " + b[1].slice(0, 2) + ":" + b[1].slice(2, 4) : "";
                    }
                    else if (l.indexOf("NSAVES=") === 0) root.olderCount = parseInt(l.slice(7)) || 0;
                }
                // only rebuild the buttons when the set of rices actually changed
                let same = names.length === riceList.count;
                for (let j = 0; same && j < names.length; j++) same = riceList.get(j).rname === names[j];
                if (!same) {
                    riceList.clear();
                    for (let k = 0; k < names.length; k++) riceList.append({ rname: names[k] });
                }
            }
        }
    }

    Process {
        id: saveProc
        running: false
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            root.statusLine = exitCode === 0 ? "saved" : "save failed";
            clearStatus.restart();
        }
    }
    Timer { id: clearStatus; interval: 4000; onTriggered: root.statusLine = "" }

    function saveRice() {
        if (root.busy) return;
        root.busy = true;
        root.statusLine = "saving…";
        saveProc.command = ["bash", "-c",
            "\"$HOME/.config/glitch/bin/rice\" save \"$(cat \"$HOME/.local/share/bite-os/rices/.active\")\" -m 'widget save' --force"];
        saveProc.running = true;
    }

    function switchTo(name) {
        if (!/^[A-Za-z0-9_-]+$/.test(name) || name === root.activeRice) return;
        root.statusLine = "switching to " + name + "…";
        Quickshell.execDetached(["setsid", "-f", "bash", "-c",
            "\"$HOME/.config/glitch/bin/dots-switch.sh\" " + name + " >/dev/null 2>&1"]);
    }

    readonly property real u: Scaler.s(1)

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: ThemeBackend.surface0
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.mauve, 0.25)
        clip: true

        // ── cards look ──────────────────────────────────────────────────────
        ColumnLayout {
            visible: !root.compact
            anchors.fill: parent
            anchors.margins: Scaler.s(12)
            spacing: Scaler.s(8)

            RowLayout {
                spacing: Scaler.s(6)
                Text {
                    text: root.icPalette
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: Scaler.s(14)
                    color: ThemeBackend.mauve
                }
                Text {
                    text: "rice"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    font.bold: true
                    color: ThemeBackend.subtext0
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "BITE-OS"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    font.bold: true
                    color: ThemeBackend.green
                    opacity: 0.8
                }
            }

            ColumnLayout {
                spacing: 0
                Text {
                    text: root.activeRice
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(22)
                    font.weight: Font.Black
                    color: ThemeBackend.text
                }
                Text {
                    text: root.statusLine !== "" ? root.statusLine : ("shell · " + root.activeShell)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: root.statusLine !== "" ? ThemeBackend.peach : ThemeBackend.subtext0
                }
            }

            // last save + history size, instead of an empty gap
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Scaler.s(38)
                radius: Scaler.s(8)
                color: Qt.alpha(ThemeBackend.surface1, 0.55)

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Scaler.s(10)
                    spacing: Scaler.s(2)
                    Text {
                        Layout.fillWidth: true
                        text: "last save: " + (root.lastLabel || "none yet")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        font.bold: true
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (root.lastWhen ? root.lastWhen + "  ·  " : "") + root.olderCount + (root.olderCount === 1 ? " older save" : " older saves")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.subtext0
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)

                Repeater {
                    model: riceList
                    FillButton {
                        readonly property bool isActive: model.rname === root.activeRice
                        Layout.fillWidth: true
                        Layout.preferredHeight: Scaler.s(34)
                        opacity: isActive ? 0.6 : 1.0
                        buttonText: model.rname
                        buttonIcon: isActive ? root.icCheck : root.icSwap
                        textFontSize: Scaler.s(11)
                        iconFontSize: Scaler.s(14)
                        accentColor: isActive ? ThemeBackend.green : ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        hoverColor: Qt.alpha(isActive ? ThemeBackend.green : ThemeBackend.mauve, 0.15)
                        textColor: isActive ? ThemeBackend.green : ThemeBackend.mauve
                        filledTextColor: ThemeBackend.crust
                        cornerRadius: ThemeBackend.borderRadius
                        fillDuration: 1200
                        onTriggered: root.switchTo(model.rname)
                    }
                }

                ClickButton {
                    Layout.preferredWidth: Scaler.s(34)
                    Layout.preferredHeight: Scaler.s(34)
                    buttonText: ""
                    buttonIcon: root.icSave
                    iconFontSize: Scaler.s(15)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: ThemeBackend.surface1
                    textColor: ThemeBackend.green
                    onTriggered: root.saveRice()
                }
            }
        }

        // ── compact look ────────────────────────────────────────────────────
        RowLayout {
            visible: root.compact
            anchors.fill: parent
            anchors.margins: Scaler.s(8)
            spacing: Scaler.s(8)

            Text {
                text: root.icPalette
                font.family: "Iosevka Nerd Font"
                font.pixelSize: Scaler.s(18)
                color: ThemeBackend.mauve
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text {
                    text: root.activeRice
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(14)
                    font.bold: true
                    color: ThemeBackend.text
                }
                Text {
                    text: root.statusLine !== "" ? root.statusLine : root.activeShell
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: root.statusLine !== "" ? ThemeBackend.peach : ThemeBackend.subtext0
                }
            }

            Repeater {
                model: riceList
                FillButton {
                    // the live rice gets no button in the compact look
                    visible: model.rname !== root.activeRice
                    Layout.preferredHeight: Scaler.s(32)
                    Layout.alignment: Qt.AlignVCenter
                    buttonText: model.rname
                    buttonIcon: root.icSwap
                    textFontSize: Scaler.s(10)
                    iconFontSize: Scaler.s(13)
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface1
                    hoverColor: Qt.alpha(ThemeBackend.mauve, 0.15)
                    textColor: ThemeBackend.mauve
                    filledTextColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    fillDuration: 1200
                    onTriggered: root.switchTo(model.rname)
                }
            }

            ClickButton {
                Layout.preferredWidth: Scaler.s(32)
                Layout.preferredHeight: Scaler.s(32)
                Layout.alignment: Qt.AlignVCenter
                buttonText: ""
                buttonIcon: root.icSave
                iconFontSize: Scaler.s(14)
                cornerRadius: ThemeBackend.borderRadius
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.green
                onTriggered: root.saveRice()
            }
        }
    }
}
