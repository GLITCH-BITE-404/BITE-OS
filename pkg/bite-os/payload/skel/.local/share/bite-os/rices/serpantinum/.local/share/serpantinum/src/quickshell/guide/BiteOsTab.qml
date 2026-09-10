// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Rice vault controls: save the current look/keybinds into
//  the vault, roll back, or swap to another rice.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: biteTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property string activeRice: "…"
    property string activeShell: "…"
    property string statusLine: ""
    property bool busy: false

    property string saveLabel: ""
    property int historyLimit: 10
    ListModel { id: riceHistory }

    // Read the snapshots straight off disk rather than parsing `rice log`
    // output -- that output is coloured for humans and would break the moment
    // its formatting changes. meta.txt travels with each snapshot.
    Process {
        id: riceLogProc
        running: false
        command: ["bash", "-c",
            "for d in ~/.local/share/bite-os/rices/_replaced/*/; do " +
            "[ -d \"$d\" ] || continue; id=$(basename \"$d\"); " +
            "lbl=$(sed -n 's/^label=//p' \"$d/meta.txt\" 2>/dev/null); " +
            "printf '%s\\t%s\\n' \"$id\" \"${lbl:-—}\"; " +
            "done | sort -r | head -8; " +
            "echo \"LIMIT=$(. ${XDG_CONFIG_HOME:-$HOME/.config}/bite-os/rice.conf 2>/dev/null; echo ${HISTORY_LIMIT:-10})\""]
        stdout: StdioCollector {
            onStreamFinished: {
                riceHistory.clear();
                let lines = (this.text || "").trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (!lines[i]) continue;
                    if (lines[i].indexOf("LIMIT=") === 0) {
                        biteTabRoot.historyLimit = parseInt(lines[i].slice(6)) || 10;
                        continue;
                    }
                    let p = lines[i].split("\t");
                    let id = p[0] || "";
                    // id is <rice>-YYYYMMDD-HHMMSS
                    let bits = id.split("-");
                    let t = bits.length >= 2 ? bits[bits.length - 1] : "";
                    let d = bits.length >= 3 ? bits[bits.length - 2] : "";
                    let when = (d.length === 8 && t.length === 6)
                        ? (d.slice(4,6) + "/" + d.slice(6,8) + " " + t.slice(0,2) + ":" + t.slice(2,4))
                        : "";
                    riceHistory.append({ sid: id, slabel: p[1] || "—", swhen: when });
                }
            }
        }
    }

    function refresh() { riceStatusProc.running = true; riceLogProc.running = true; }

    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    Process {
        id: riceStatusProc
        running: false
        command: ["bash", "-c",
            "printf '%s\\n%s\\n' \"$(cat ~/.local/share/bite-os/rices/.active 2>/dev/null || echo unknown)\" \"$(cat ~/.local/state/bite-os/active-shell 2>/dev/null || echo unknown)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text;
                if (!out) return;
                let parts = out.trim().split("\n");
                biteTabRoot.activeRice = (parts[0] || "unknown").trim();
                biteTabRoot.activeShell = (parts[1] || "unknown").trim();
            }
        }
    }

    Process {
        id: actionProc
        running: false
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                void this.text;
                biteTabRoot.busy = false;
                biteTabRoot.statusLine = actionProc.label + " — done";
                biteTabRoot.refresh();
            }
        }
    }

    function runAction(label, cmd) {
        if (biteTabRoot.busy) return;
        biteTabRoot.busy = true;
        biteTabRoot.statusLine = label + " …";
        actionProc.label = label;
        actionProc.command = ["bash", "-c", cmd];
        actionProc.running = true;
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: rootObj.s(14)

            Text {
                text: "BITE-OS"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(22)
                color: ThemeBackend.text
            }

            Text {
                text: "GLITCH-BITE-404  ·  github.com/GLITCH-BITE-404/BITE-OS"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: infoCol.implicitHeight + rootObj.s(16)
                radius: ThemeBackend.clampedBorderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.55)

                ColumnLayout {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: rootObj.s(12)
                    spacing: rootObj.s(4)

                    Text {
                        text: "active rice:  " + biteTabRoot.activeRice
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.green
                    }
                    Text {
                        text: "active shell: " + biteTabRoot.activeShell
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.subtext1
                    }
                    Text {
                        visible: biteTabRoot.statusLine !== ""
                        text: biteTabRoot.statusLine
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.peach
                    }
                }
            }

            Text {
                text: "Save keeps your keybinds, theme and layout in the vault. Without it a rice swap reverts them."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
            }

            Input {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(36)
                placeholderText: "name this save (optional)"
                text: biteTabRoot.saveLabel
                onTextEdited: (t) => biteTabRoot.saveLabel = t
            }

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(38)
                buttonText: "Save this rice"
                buttonIcon: "󰆓"
                accentColor: ThemeBackend.green
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                textColor: ThemeBackend.green
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(12)
                iconFontSize: rootObj.s(16)
                fillDuration: 900
                onTriggered: {
                    // single-quote the label so spaces and punctuation survive
                    let lbl = biteTabRoot.saveLabel.replace(/'/g, "'\\''");
                    let m = lbl.trim() !== "" ? (" -m '" + lbl + "'") : "";
                    biteTabRoot.runAction("Saved rice",
                        "~/.config/glitch/bin/rice save \"$(cat ~/.local/share/bite-os/rices/.active)\"" + m + " --force");
                    biteTabRoot.saveLabel = "";
                }
            }

            FillButton {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(38)
                buttonText: "Roll back last swap"
                buttonIcon: "󰕌"
                accentColor: ThemeBackend.peach
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                textColor: ThemeBackend.peach
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(12)
                iconFontSize: rootObj.s(16)
                fillDuration: 1400
                onTriggered: biteTabRoot.runAction("Rolled back",
                    "~/.config/glitch/bin/rice rollback")
            }

            Text {
                text: "Saved states"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(13)
                color: ThemeBackend.text
                Layout.topMargin: rootObj.s(8)
            }

            Text {
                visible: riceHistory.count === 0
                text: "no earlier saves yet — they appear each time you save over a rice"
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.subtext0
            }

            Repeater {
                model: riceHistory
                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(8)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: model.slabel
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(12)
                            color: ThemeBackend.text
                        }
                        Text {
                            text: model.swhen + "   " + model.sid
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(10)
                            color: ThemeBackend.subtext0
                        }
                    }

                    ClickButton {
                        Layout.preferredWidth: rootObj.s(92)
                        Layout.preferredHeight: rootObj.s(30)
                        buttonText: "Restore"
                        buttonIcon: "󰕌"
                        textFontSize: rootObj.s(11)
                        iconFontSize: rootObj.s(13)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.peach
                        // restore only rewrites the vault entry; nothing live
                        // changes until a swap, which is what makes it safe to
                        // click from here.
                        onTriggered: biteTabRoot.runAction("Restored " + model.sid,
                            "~/.config/glitch/bin/rice restore '" + model.sid + "'")
                    }

                    ClickButton {
                        Layout.preferredWidth: rootObj.s(34)
                        Layout.preferredHeight: rootObj.s(30)
                        buttonText: ""
                        buttonIcon: "󰩹"
                        iconFontSize: rootObj.s(14)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.red
                        onTriggered: biteTabRoot.runAction("Deleted " + model.sid,
                            "~/.config/glitch/bin/rice delete '" + model.sid + "' -y")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(4)
                spacing: rootObj.s(10)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Keep this many snapshots"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        color: ThemeBackend.text
                    }
                    Text {
                        // every save and every swap writes a full copy, so
                        // without a cap the vault grows without bound
                        text: "older ones are removed automatically on save and swap"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.subtext0
                    }
                }

                NumberSelector {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: rootObj.s(110)
                    implicitHeight: rootObj.s(32)
                    from: 1
                    to: 100
                    stepSize: 1
                    decimals: 0
                    value: biteTabRoot.historyLimit
                    baseColor: ThemeBackend.surface0
                    accentColor: ThemeBackend.mauve
                    buttonColor: ThemeBackend.surface1
                    buttonTextColor: ThemeBackend.text
                    textColor: ThemeBackend.text
                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                    cornerRadius: ThemeBackend.borderRadius
                    fontFamily: ThemeBackend.fontFamily
                    fontPixelSize: rootObj.s(11)
                    // NumberSelector has no custom valueChanged signal, so this
                    // is the auto-generated property signal and `val` is
                    // undefined -- which sent `rice limit undefined` and was
                    // rejected silently. Fall back to `value`, as IdleTab does.
                    onValueChanged: function(val) {
                        let num = (typeof val === "number" && !isNaN(val)) ? val : value;
                        let n = Math.round(num);
                        if (!isFinite(n) || n < 1 || n > 100) return;
                        if (n === biteTabRoot.historyLimit) return;
                        biteTabRoot.historyLimit = n;
                        biteTabRoot.runAction("History limit " + n,
                            "~/.config/glitch/bin/rice limit " + n);
                    }
                }
            }

            Text {
                text: "Switch rice"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(13)
                color: ThemeBackend.text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: rootObj.s(8)

                FillButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: rootObj.s(36)
                    buttonText: "caelestia"
                    buttonIcon: "󰋜"
                    accentColor: ThemeBackend.blue
                    baseColor: ThemeBackend.surface0
                    hoverColor: Qt.alpha(ThemeBackend.blue, 0.15)
                    textColor: ThemeBackend.blue
                    filledTextColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    textFontSize: rootObj.s(11)
                    iconFontSize: rootObj.s(14)
                    fillDuration: 1400
                    onTriggered: biteTabRoot.runAction("Swapping to caelestia",
                        "~/.config/glitch/bin/dots-switch.sh caelestia")
                }

                FillButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: rootObj.s(36)
                    buttonText: "serpantinum"
                    buttonIcon: "󰋜"
                    accentColor: ThemeBackend.mauve
                    baseColor: ThemeBackend.surface0
                    hoverColor: Qt.alpha(ThemeBackend.mauve, 0.15)
                    textColor: ThemeBackend.mauve
                    filledTextColor: ThemeBackend.crust
                    cornerRadius: ThemeBackend.borderRadius
                    textFontSize: rootObj.s(11)
                    iconFontSize: rootObj.s(14)
                    fillDuration: 1400
                    onTriggered: biteTabRoot.runAction("Swapping to serpantinum",
                        "~/.config/glitch/bin/dots-switch.sh serpantinum")
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
