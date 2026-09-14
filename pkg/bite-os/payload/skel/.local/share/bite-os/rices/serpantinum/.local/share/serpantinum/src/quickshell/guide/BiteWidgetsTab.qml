// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia
//  Miroshnichenko). Widget saves: name + save the current desktop-widget
//  layout, load or delete older ones, and an auto-save toggle.
//
//  Backed by ~/.config/hypr/scripts/widget-saves.sh. The saves live OUTSIDE
//  the rice vault, so rice save / restore / load / switch never reset this
//  list. Loading rebuilds the widgets through the shell's widget IPC (no shell
//  reload) and parks the current layout as an auto save first, so a load can
//  always be undone from this same list.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: wTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    readonly property string tool: "\"$HOME/.config/hypr/scripts/widget-saves.sh\""

    property string saveName: ""
    property string statusLine: ""
    property bool busy: false
    property bool autoOn: false
    ListModel { id: saves }

    function refresh() {
        if (!listProc.running) listProc.running = true;
        if (!cfgProc.running) cfgProc.running = true;
    }

    // BITE-OS widget settings file (read here, written atomically below)
    property var cfg: ({})
    function cfgGet(path, fallback) {
        let v = wTabRoot.cfg;
        for (const k of String(path).split(".")) {
            if (v === null || v === undefined || typeof v !== "object") return fallback;
            v = v[k];
        }
        return (v === undefined || v === null) ? fallback : v;
    }
    readonly property var cfgKeys: ["riceSaves.count", "widgetSaves.count", "workspaceMap.count", "procTop.rows"]
    function setCfg(path, n) {
        if (wTabRoot.cfgKeys.indexOf(path) === -1 || !Number.isInteger(n)) return;
        const parts = path.split(".");
        const c = JSON.parse(JSON.stringify(wTabRoot.cfg || {}));
        if (typeof c[parts[0]] !== "object" || c[parts[0]] === null) c[parts[0]] = {};
        c[parts[0]][parts[1]] = n;
        wTabRoot.cfg = c;
        cfgWrite.command = ["bash", "-c",
            "f=\"$HOME/.config/serpantinum/bite-widgets.json\"; [ -s \"$f\" ] || echo '{}' > \"$f\"; " +
            "jq --argjson v " + n + " 'setpath([\"" + parts[0] + "\",\"" + parts[1] + "\"]; $v)' \"$f\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\""];
        cfgWrite.running = true;
    }
    Process {
        id: cfgProc
        running: false
        command: ["bash", "-c", "cat \"$HOME/.config/serpantinum/bite-widgets.json\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { wTabRoot.cfg = JSON.parse((this.text || "").trim() || "{}"); } catch (e) { wTabRoot.cfg = ({}); }
            }
        }
    }
    Process { id: cfgWrite; running: false }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    // auto saves made while this tab is open show up without reopening it
    Timer { interval: 4000; repeat: true; running: wTabRoot.visible; onTriggered: wTabRoot.refresh() }

    Process {
        id: listProc
        running: false
        command: ["bash", "-c", "echo \"AUTO=$(" + wTabRoot.tool + " auto status)\"; " + wTabRoot.tool + " list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = (this.text || "").trim().split("\n");
                let rows = [];
                for (let i = 0; i < lines.length; i++) {
                    let l = lines[i];
                    if (l.indexOf("AUTO=") === 0) { wTabRoot.autoOn = l.slice(5).trim() === "on"; continue; }
                    // id  name  when  count  kind
                    let p = l.split("\t");
                    if (p.length < 5) continue;
                    rows.push({ sid: p[0], sname: p[1], swhen: p[2], scount: parseInt(p[3]) || 0, sauto: p[4] === "auto" });
                }
                // only rebuild when something changed, so the list doesn't
                // flicker or jump while you scroll it
                let same = rows.length === saves.count;
                for (let j = 0; same && j < rows.length; j++) same = saves.get(j).sid === rows[j].sid && saves.get(j).sname === rows[j].sname;
                if (!same) {
                    saves.clear();
                    for (let k = 0; k < rows.length; k++) saves.append(rows[k]);
                }
            }
        }
    }

    Process {
        id: actionProc
        running: false
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (this.text || "").trim().split("\n").pop();
                wTabRoot.busy = false;
                wTabRoot.statusLine = out !== "" ? out : (actionProc.label + " — done");
                wTabRoot.refresh();
            }
        }
    }

    function run(label, args) {
        if (wTabRoot.busy) return;
        wTabRoot.busy = true;
        wTabRoot.statusLine = label + " …";
        actionProc.label = label;
        actionProc.command = ["bash", "-c", wTabRoot.tool + " " + args];
        actionProc.running = true;
    }

    // names and ids go into a shell command: quote names, allow only real ids
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function validId(id) { return /^[0-9]{8}-[0-9]+$/.test(id); }

    ColumnLayout {
        anchors.fill: parent
        spacing: rootObj.s(14)

        Text {
            text: "Widgets"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: rootObj.s(22)
            color: ThemeBackend.text
        }

        Text {
            text: "Save your desktop widgets' layout, go back to an older one, or let it save by itself. These saves are separate from rice saves, so swapping or restoring a rice never touches this list."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.family: ThemeBackend.fontFamily
            font.pixelSize: rootObj.s(11)
            color: ThemeBackend.subtext0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: rootObj.s(8)

            Input {
                Layout.fillWidth: true
                Layout.preferredHeight: rootObj.s(36)
                placeholderText: "name this save (optional)"
                text: wTabRoot.saveName
                onTextEdited: (t) => wTabRoot.saveName = t
            }

            FillButton {
                Layout.preferredWidth: rootObj.s(170)
                Layout.preferredHeight: rootObj.s(36)
                buttonText: "Save widgets now"
                buttonIcon: String.fromCodePoint(0xF0193)
                accentColor: ThemeBackend.green
                baseColor: ThemeBackend.surface0
                hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                textColor: ThemeBackend.green
                filledTextColor: ThemeBackend.crust
                cornerRadius: ThemeBackend.borderRadius
                textFontSize: rootObj.s(12)
                iconFontSize: rootObj.s(15)
                fillDuration: 500
                onTriggered: {
                    wTabRoot.run("Saving", "save " + wTabRoot.q(wTabRoot.saveName.trim()));
                    wTabRoot.saveName = "";
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: autoRow.implicitHeight + rootObj.s(16)
            radius: ThemeBackend.clampedBorderRadius
            color: Qt.alpha(ThemeBackend.surface0, 0.55)

            RowLayout {
                id: autoRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: rootObj.s(12)
                spacing: rootObj.s(10)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Auto-save"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(12)
                        font.bold: true
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "watches your widgets and saves when they change (at most every 2 minutes, keeps the last 10 auto saves; your named saves are never removed)"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(10)
                        color: ThemeBackend.subtext0
                    }
                }

                Toggle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    checked: wTabRoot.autoOn
                    accentColor: ThemeBackend.green
                    baseColor: ThemeBackend.surface1
                    handleColor: ThemeBackend.crust
                    handleOffColor: ThemeBackend.text
                    onToggled: function(val) {
                        wTabRoot.autoOn = val;
                        wTabRoot.run(val ? "Auto-save on" : "Auto-save off", "auto " + (val ? "on" : "off"));
                    }
                }
            }
        }

        // ── BITE-OS widget settings (~/.config/serpantinum/bite-widgets.json,
        // read live by every BITE-OS widget through BiteWidgetConfig) ──────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: settingsCol.implicitHeight + rootObj.s(16)
            radius: ThemeBackend.clampedBorderRadius
            color: Qt.alpha(ThemeBackend.surface0, 0.55)

            ColumnLayout {
                id: settingsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: rootObj.s(12)
                spacing: rootObj.s(8)

                Text {
                    text: "Widget settings"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(12)
                    font.bold: true
                    color: ThemeBackend.text
                }

                Repeater {
                    model: [
                        { key: "riceSaves.count",    label: "Rice saves widget",    hint: "how many saves it lists",       min: 1, max: 10, def: 2 },
                        { key: "widgetSaves.count",  label: "Widget layouts widget", hint: "how many layouts it lists",    min: 1, max: 10, def: 3 },
                        { key: "workspaceMap.count", label: "Workspace map",         hint: "how many workspaces it shows", min: 2, max: 10, def: 8 },
                        { key: "procTop.rows",       label: "Process top",           hint: "how many processes it lists",  min: 3, max: 10, def: 6 }
                    ]

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: rootObj.s(10)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.label; font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(12); color: ThemeBackend.text }
                            Text { text: modelData.hint; font.family: ThemeBackend.fontFamily; font.pixelSize: rootObj.s(10); color: ThemeBackend.subtext0 }
                        }

                        NumberSelector {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: rootObj.s(110)
                            implicitHeight: rootObj.s(32)
                            from: modelData.min
                            to: modelData.max
                            stepSize: 1
                            decimals: 0
                            value: wTabRoot.cfgGet(modelData.key, modelData.def)
                            baseColor: ThemeBackend.surface0
                            accentColor: ThemeBackend.mauve
                            buttonColor: ThemeBackend.surface1
                            buttonTextColor: ThemeBackend.text
                            textColor: ThemeBackend.text
                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                            cornerRadius: ThemeBackend.borderRadius
                            fontFamily: ThemeBackend.fontFamily
                            fontPixelSize: rootObj.s(11)
                            // NumberSelector's valueChanged carries no argument
                            // (auto property signal) -- fall back to `value`
                            onValueChanged: function(val) {
                                const num = (typeof val === "number" && !isNaN(val)) ? val : value;
                                const n = Math.round(num);
                                if (!isFinite(n) || n === wTabRoot.cfgGet(modelData.key, modelData.def)) return;
                                wTabRoot.setCfg(modelData.key, n);
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Saved layouts"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: rootObj.s(13)
                color: ThemeBackend.text
            }
            Item { Layout.fillWidth: true }
            Text {
                text: wTabRoot.statusLine
                font.family: ThemeBackend.fontFamily
                font.pixelSize: rootObj.s(11)
                color: ThemeBackend.peach
                elide: Text.ElideRight
                Layout.maximumWidth: rootObj.s(360)
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: rootObj.s(80)
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: rootObj.s(10)

                Text {
                    visible: saves.count === 0
                    text: "no widget saves yet — press Save widgets now, or turn on auto-save"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: rootObj.s(11)
                    color: ThemeBackend.subtext0
                }

                Repeater {
                    model: saves
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(8)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(6)
                                Text {
                                    text: model.sname
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    color: ThemeBackend.text
                                }
                                Rectangle {
                                    visible: model.sauto
                                    implicitWidth: autoBadge.implicitWidth + rootObj.s(12)
                                    implicitHeight: autoBadge.implicitHeight + rootObj.s(4)
                                    radius: height / 2
                                    color: Qt.alpha(ThemeBackend.mauve, 0.18)
                                    Text {
                                        id: autoBadge
                                        anchors.centerIn: parent
                                        text: "auto"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(9)
                                        font.bold: true
                                        color: ThemeBackend.mauve
                                    }
                                }
                            }
                            Text {
                                text: model.swhen + "   ·   " + model.scount + (model.scount === 1 ? " widget" : " widgets")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(10)
                                color: ThemeBackend.subtext0
                            }
                        }

                        FillButton {
                            // hold to confirm: replaces what's on your desktop
                            // (what's there now is auto-saved first)
                            Layout.preferredWidth: rootObj.s(92)
                            Layout.preferredHeight: rootObj.s(30)
                            buttonText: "Load"
                            buttonIcon: String.fromCodePoint(0xF054C)
                            accentColor: ThemeBackend.peach
                            baseColor: ThemeBackend.surface0
                            hoverColor: Qt.alpha(ThemeBackend.peach, 0.15)
                            textColor: ThemeBackend.peach
                            filledTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            textFontSize: rootObj.s(11)
                            iconFontSize: rootObj.s(13)
                            fillDuration: 900
                            onTriggered: if (wTabRoot.validId(model.sid)) wTabRoot.run("Loading " + model.sname, "load " + model.sid)
                        }

                        ClickButton {
                            Layout.preferredWidth: rootObj.s(34)
                            Layout.preferredHeight: rootObj.s(30)
                            buttonText: ""
                            buttonIcon: String.fromCodePoint(0xF0A79)
                            iconFontSize: rootObj.s(14)
                            cornerRadius: ThemeBackend.borderRadius
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.red
                            onTriggered: if (wTabRoot.validId(model.sid)) wTabRoot.run("Deleting " + model.sname, "delete " + model.sid)
                        }
                    }
                }
            }
        }
    }
}
